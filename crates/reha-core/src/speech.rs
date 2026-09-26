//! Offline German Kokoro/Martin, 24 kHz PCM. eSpeak-NG produces phonemes only;
//! audible audio comes exclusively from Kokoro. No network or persistent audio.
use crate::{Error, Result};
use ort::{
    session::{run_options::RunOptions, Session},
    value::Tensor,
};
use std::{
    collections::HashMap,
    ffi::{c_char, c_int, c_void, CStr, CString},
    path::{Path, PathBuf},
    sync::{
        atomic::{AtomicBool, AtomicU64, Ordering},
        Mutex,
    },
    time::Duration,
};

fn err(e: impl std::fmt::Display) -> Error {
    Error::Invalid(format!("Lokale Stimme: {e}"))
}
// eSpeak's API owns global mutable state. Serialize *all* uses across engines.
static PHONEMIZER: Mutex<Option<PathBuf>> = Mutex::new(None);
unsafe extern "C" {
    fn espeak_Initialize(
        output: c_int,
        buflength: c_int,
        path: *const c_char,
        options: c_int,
    ) -> c_int;
    fn espeak_SetVoiceByName(name: *const c_char) -> c_int;
    fn espeak_TextToPhonemes(
        text: *mut *const c_void,
        textmode: c_int,
        phonememode: c_int,
    ) -> *const c_char;
    fn espeak_Terminate() -> c_int;
}
fn phonemize(root: &Path, text: &str) -> Result<String> {
    let mut initialized = PHONEMIZER
        .lock()
        .map_err(|_| err("Aussprache ist beschäftigt"))?;
    let path = root.to_path_buf();
    if initialized.as_ref() != Some(&path) {
        let cpath = CString::new(path.to_string_lossy().as_bytes()).map_err(err)?;
        // Synchronous retrieval, DONT_EXIT: no device playback, no process exit.
        unsafe {
            if initialized.is_some() {
                espeak_Terminate();
                *initialized = None;
            }
            if espeak_Initialize(2, 0, cpath.as_ptr(), 0x8000) <= 0 {
                return Err(err("Aussprachedaten fehlen"));
            }
            if espeak_SetVoiceByName(c"de".as_ptr()) != 0 {
                return Err(err("Deutsche Aussprache fehlt"));
            }
        }
        *initialized = Some(path);
    }
    let mut output = String::new();
    // Preserve sentence punctuation explicitly; the C API consumes it.
    for part in text.split_inclusive(['.', ',', '!', '?', ';', ':']) {
        let input =
            CString::new(part.trim_end_matches(['.', ',', '!', '?', ';', ':'])).map_err(err)?;
        let mut pointer = input.as_ptr().cast::<c_void>();
        while !pointer.is_null() {
            let previous = pointer;
            // C's result remains valid until its next call. Copy under the lock.
            let result = unsafe { espeak_TextToPhonemes(&mut pointer, 1, 2) };
            if result.is_null() {
                return Err(err("Aussprache konnte nicht erstellt werden"));
            }
            let phonemes = unsafe { CStr::from_ptr(result) }.to_str().map_err(err)?;
            output.push_str(phonemes);
            output.push(' ');
            if pointer == previous {
                return Err(err("Aussprache wurde unterbrochen"));
            }
        }
        if let Some(c) = part.chars().last().filter(|c| ".,!?;:".contains(*c)) {
            output = output.trim_end().to_owned();
            output.push(c);
            output.push(' ');
        }
    }
    Ok(output)
}

pub struct SpeechEngine {
    root: PathBuf,
    vocab: HashMap<char, i64>,
    voice: Vec<f32>,
    model: Session,
}
impl SpeechEngine {
    pub fn load(root: &Path) -> Result<Self> {
        let manifest: serde_json::Value =
            serde_json::from_slice(include_bytes!("../../../models/kokoro.lock.json"))?;
        for item in manifest["files"]
            .as_array()
            .ok_or_else(|| err("Modellverzeichnis fehlt"))?
        {
            let name = item["path"]
                .as_str()
                .ok_or_else(|| err("Modelldatei fehlt"))?;
            if item["sha256"].as_str() != Some(&crate::hash(&std::fs::read(root.join(name))?)) {
                return Err(err("Sprachdatei ist beschädigt"));
            }
        }
        let raw = std::fs::read(root.join("martin.f32"))?;
        if raw.len() != 510 * 256 * 4 {
            return Err(err("Stimmeninformationen sind beschädigt"));
        }
        let voice = raw
            .chunks_exact(4)
            .map(|v| f32::from_le_bytes(v.try_into().unwrap()))
            .collect::<Vec<_>>();
        if voice.iter().any(|v| !v.is_finite()) {
            return Err(err("Stimmeninformationen sind ungültig"));
        }
        let vocab = serde_json::from_slice(&std::fs::read(root.join("vocab.json"))?)?;
        let model = Session::builder()
            .map_err(err)?
            .with_intra_threads(2)
            .map_err(err)?
            .with_inter_threads(1)
            .map_err(err)?
            .commit_from_file(root.join("kokoro-martin.onnx"))
            .map_err(err)?;
        Ok(Self {
            root: root.to_path_buf(),
            vocab,
            voice,
            model,
        })
    }
    pub fn render(
        &mut self,
        text: &str,
        _voice: &str,
        speed: f32,
        request: u64,
        latest: &AtomicU64,
    ) -> Result<Vec<u8>> {
        let check = || {
            if latest.load(Ordering::Acquire) == request {
                Ok(())
            } else {
                Err(err("Vorlesen beendet"))
            }
        };
        check()?;
        if text.trim().is_empty()
            || text.chars().count() > 2000
            || !speed.is_finite()
            || !(0.75..=1.25).contains(&speed)
        {
            return Err(err("Ungültiger Vorlesetext oder Geschwindigkeit"));
        }
        let normalized = crate::speech_text::normalize(text);
        let phonemes = phonemize(&self.root, &normalized)?;
        check()?;
        let filtered: String = phonemes
            .chars()
            .filter(|c| self.vocab.contains_key(c))
            .collect();
        if filtered.trim().is_empty() {
            return Err(err("Kein aussprechbarer Text"));
        }
        let mut audio = Vec::new();
        // Bound each graph invocation by phonemes, not written characters. Long
        // words also split, and no token is dropped at a chunk boundary.
        for chunk in chunks(&filtered, 400) {
            check()?;
            let mut ids = chunk.chars().map(|c| self.vocab[&c]).collect::<Vec<_>>();
            let length = ids.len();
            let style = Tensor::from_array((
                [1, 256],
                self.voice[length * 256..(length + 1) * 256].to_vec(),
            ))
            .map_err(err)?;
            ids.insert(0, 0);
            ids.push(0);
            let tokens = Tensor::from_array(([1, ids.len()], ids)).map_err(err)?;
            let speed = Tensor::from_array(([1], vec![speed])).map_err(err)?;
            let options = RunOptions::new().map_err(err)?;
            let finished = AtomicBool::new(false);
            let result = std::thread::scope(|scope| {
                scope.spawn(|| {
                    while !finished.load(Ordering::Acquire) {
                        if latest.load(Ordering::Acquire) != request {
                            let _ = options.terminate();
                            break;
                        }
                        std::thread::sleep(Duration::from_millis(20));
                    }
                });
                let result = self
                    .model
                    .run_with_options(
                        ort::inputs! {"tokens" => tokens, "style" => style, "speed" => speed},
                        &options,
                    )
                    .map_err(err)
                    .and_then(|output| {
                        let (_, samples) = output["waveform"]
                            .try_extract_tensor::<f32>()
                            .map_err(err)?;
                        Ok(samples.to_vec())
                    });
                finished.store(true, Ordering::Release);
                result
            });
            check()?;
            let samples = result?;
            if samples.is_empty()
                || samples.len() > 24_000 * 120
                || samples.iter().any(|v| !v.is_finite())
                || samples.iter().all(|v| v.abs() < 0.00001)
            {
                return Err(err("Die erzeugte Sprachausgabe ist leer oder ungültig"));
            }
            audio.extend(samples);
        }
        check()?;
        Ok(wav(&audio))
    }
}
fn chunks(text: &str, max: usize) -> Vec<String> {
    let mut result = Vec::new();
    let mut current = String::new();
    for word in text.split_inclusive(' ') {
        if current.chars().count() + word.chars().count() > max && !current.is_empty() {
            result.push(std::mem::take(&mut current));
        }
        for c in word.chars() {
            if current.chars().count() == max {
                result.push(std::mem::take(&mut current));
            }
            current.push(c);
        }
    }
    if !current.is_empty() {
        result.push(current);
    }
    result
}
fn wav(samples: &[f32]) -> Vec<u8> {
    let bytes = (samples.len() * 2) as u32;
    let mut out = Vec::with_capacity(bytes as usize + 44);
    out.extend(b"RIFF");
    out.extend((36 + bytes).to_le_bytes());
    out.extend(b"WAVEfmt ");
    out.extend(16_u32.to_le_bytes());
    out.extend(1_u16.to_le_bytes());
    out.extend(1_u16.to_le_bytes());
    out.extend(24_000_u32.to_le_bytes());
    out.extend(48_000_u32.to_le_bytes());
    out.extend(2_u16.to_le_bytes());
    out.extend(16_u16.to_le_bytes());
    out.extend(b"data");
    out.extend(bytes.to_le_bytes());
    for sample in samples {
        out.extend(((sample.clamp(-1.0, 1.0) * 32767.0) as i16).to_le_bytes());
    }
    out
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn bounded_chunks_lose_no_phonemes() {
        let text = format!("{} {}", "ɛ".repeat(900), "a ".repeat(300));
        let parts = chunks(&text, 400);
        assert!(parts.iter().all(|p| p.chars().count() <= 400));
        assert_eq!(parts.concat(), text);
    }
    #[test]
    fn wav_is_24khz_mono_pcm16() {
        let audio = wav(&[-1.0, 0.0, 1.0]);
        assert_eq!(&audio[..4], b"RIFF");
        assert_eq!(
            u32::from_le_bytes(audio[24..28].try_into().unwrap()),
            24_000
        );
        assert_eq!(audio.len(), 50);
    }
}
