//! Offline Supertonic 3 inference. No network, transcript logging, or audio files.
//! Model I/O follows Supertone's MIT-licensed reference implementation;
//! see licenses/supertonic-code-mit.txt and licenses/supertonic-model-openrail.txt.
use crate::{Error, Result};
use ort::{session::Session, value::Tensor};
use rand_distr::{Distribution, StandardNormal};
use serde::Deserialize;
use std::{
    path::Path,
    sync::atomic::{AtomicU64, Ordering},
};
use unicode_normalization::UnicodeNormalization;

fn err(e: impl std::fmt::Display) -> Error {
    Error::Invalid(format!("Lokale Stimme: {e}"))
}
#[derive(Deserialize)]
struct Config {
    ae: AE,
    ttl: Ttl,
}
#[derive(Deserialize)]
struct AE {
    sample_rate: usize,
    base_chunk_size: usize,
}
#[derive(Deserialize)]
struct Ttl {
    latent_dim: usize,
    chunk_compress_factor: usize,
}
#[derive(Deserialize)]
struct StylePart {
    data: Vec<Vec<Vec<f32>>>,
    dims: Vec<usize>,
}
#[derive(Deserialize)]
struct Style {
    style_ttl: StylePart,
    style_dp: StylePart,
}
impl StylePart {
    fn tensor(&self) -> Result<Tensor<f32>> {
        Tensor::from_array((
            self.dims.clone(),
            self.data
                .iter()
                .flatten()
                .flatten()
                .copied()
                .collect::<Vec<_>>(),
        ))
        .map_err(err)
    }
}
pub struct SpeechEngine {
    config: Config,
    index: Vec<i64>,
    female: Style,
    male: Style,
    duration: Session,
    encoder: Session,
    estimator: Session,
    vocoder: Session,
}
impl SpeechEngine {
    pub fn load(root: &Path) -> Result<Self> {
        let manifest: serde_json::Value =
            serde_json::from_slice(include_bytes!("../../../models/supertonic.lock.json"))?;
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
        let read = |name: &str| std::fs::read(root.join(name));
        let load = |name: &str| {
            Session::builder()
                .map_err(err)?
                .with_intra_threads(2)
                .map_err(err)?
                .with_inter_threads(1)
                .map_err(err)?
                .commit_from_file(root.join("onnx").join(name))
                .map_err(err)
        };
        Ok(Self {
            config: serde_json::from_slice(&read("onnx/tts.json")?)?,
            index: serde_json::from_slice(&read("onnx/unicode_indexer.json")?)?,
            female: serde_json::from_slice(&read("voice_styles/F1.json")?)?,
            male: serde_json::from_slice(&read("voice_styles/M1.json")?)?,
            duration: load("duration_predictor.onnx")?,
            encoder: load("text_encoder.onnx")?,
            estimator: load("vector_estimator.onnx")?,
            vocoder: load("vocoder.onnx")?,
        })
    }
    /// A single bounded phrase, returned as in-memory PCM WAV. Swift queues phrases
    /// to start playback promptly and checks the same request ID between phrases.
    pub fn render(
        &mut self,
        text: &str,
        voice: &str,
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
            || text.chars().count() > 320
            || !speed.is_finite()
            || !(0.75..=1.25).contains(&speed)
        {
            return Err(err("Ungültiger Vorlesetext oder Geschwindigkeit"));
        }
        let text = normalize(text);
        let ids: Vec<i64> = text
            .chars()
            .map(|c| self.index.get(c as usize).copied().unwrap_or(-1))
            .collect();
        if ids.contains(&-1) {
            return Err(err("Dieser Text enthält nicht unterstützte Zeichen"));
        }
        let n = ids.len();
        let ids = Tensor::from_array(([1, n], ids)).map_err(err)?;
        let mask = Tensor::from_array(([1, 1, n], vec![1_f32; n])).map_err(err)?;
        let style = match voice {
            "F1" => &self.female,
            "M1" => &self.male,
            _ => return Err(err("Stimme nicht verfügbar")),
        };
        let dp = style.style_dp.tensor()?;
        let ttl = style.style_ttl.tensor()?;
        let outputs = self
            .duration
            .run(ort::inputs! { "text_ids" => &ids, "style_dp" => &dp, "text_mask" => &mask })
            .map_err(err)?;
        let (_, duration) = outputs["duration"]
            .try_extract_tensor::<f32>()
            .map_err(err)?;
        let seconds = duration
            .first()
            .copied()
            .ok_or_else(|| err("Leere Audioantwort"))?
            / speed;
        if !seconds.is_finite() || !(0.05..=45.).contains(&seconds) {
            return Err(err("Sprachausgabe konnte nicht erzeugt werden"));
        }
        drop(outputs);
        check()?;
        let outputs = self
            .encoder
            .run(ort::inputs! { "text_ids" => &ids, "style_ttl" => &ttl, "text_mask" => &mask })
            .map_err(err)?;
        let (shape, values) = outputs["text_emb"]
            .try_extract_tensor::<f32>()
            .map_err(err)?;
        let embedded = Tensor::from_array((shape.to_vec(), values.to_vec())).map_err(err)?;
        drop(outputs);
        let samples = (seconds * self.config.ae.sample_rate as f32) as usize;
        let chunk = self.config.ae.base_chunk_size * self.config.ttl.chunk_compress_factor;
        let width = samples.div_ceil(chunk);
        let dimensions = self.config.ttl.latent_dim * self.config.ttl.chunk_compress_factor;
        let mut rng = rand::thread_rng();
        let noise: Vec<f32> = (0..dimensions * width)
            .map(|_| StandardNormal.sample(&mut rng))
            .collect();
        let mut latent = Tensor::from_array(([1, dimensions, width], noise)).map_err(err)?;
        let latent_mask = Tensor::from_array(([1, 1, width], vec![1_f32; width])).map_err(err)?;
        const STEPS: usize = 10;
        let total = Tensor::from_array(([1], vec![STEPS as f32])).map_err(err)?;
        for step in 0..STEPS {
            check()?;
            let current = Tensor::from_array(([1], vec![step as f32])).map_err(err)?;
            let output = self
                .estimator
                .run(ort::inputs! {
                    "noisy_latent" => &latent, "text_emb" => &embedded, "style_ttl" => &ttl,
                    "latent_mask" => &latent_mask, "text_mask" => &mask,
                    "current_step" => &current, "total_step" => &total
                })
                .map_err(err)?;
            let (shape, values) = output["denoised_latent"]
                .try_extract_tensor::<f32>()
                .map_err(err)?;
            latent = Tensor::from_array((shape.to_vec(), values.to_vec())).map_err(err)?;
        }
        check()?;
        let output = self
            .vocoder
            .run(ort::inputs! { "latent" => &latent })
            .map_err(err)?;
        let (_, values) = output["wav_tts"].try_extract_tensor::<f32>().map_err(err)?;
        let values = &values[..samples.min(values.len())];
        if values.is_empty()
            || values.iter().any(|x| !x.is_finite())
            || values.iter().all(|x| x.abs() < 0.00001)
        {
            return Err(err("Die erzeugte Sprachausgabe ist leer"));
        }
        check()?;
        Ok(wav(values, self.config.ae.sample_rate as u32))
    }
}
fn normalize(text: &str) -> String {
    let text: String = text
        .nfkd()
        .filter(|c| !matches!(*c as u32, 0x1F000..=0x1FAFF|0x2600..=0x27BF))
        .collect();
    let text = text
        .replace(['–', '—', '‑'], "-")
        .replace(['“', '”'], "\"")
        .replace(['‘', '’'], "'")
        .replace(['[', ']', '|', '/', '_', '→', '←'], " ");
    let mut text = text.split_whitespace().collect::<Vec<_>>().join(" ");
    if !text.ends_with(['.', '!', '?', ':', ';']) {
        text.push('.');
    }
    format!("<de>{text}</de>")
}
fn wav(samples: &[f32], rate: u32) -> Vec<u8> {
    let bytes = (samples.len() * 2) as u32;
    let mut out = Vec::with_capacity(bytes as usize + 44);
    out.extend(b"RIFF");
    out.extend((bytes + 36).to_le_bytes());
    out.extend(b"WAVEfmt ");
    out.extend(16_u32.to_le_bytes());
    out.extend(1_u16.to_le_bytes());
    out.extend(1_u16.to_le_bytes());
    out.extend(rate.to_le_bytes());
    out.extend((rate * 2).to_le_bytes());
    out.extend(2_u16.to_le_bytes());
    out.extend(16_u16.to_le_bytes());
    out.extend(b"data");
    out.extend(bytes.to_le_bytes());
    for x in samples {
        out.extend(((x.clamp(-1., 1.) * 32767.) as i16).to_le_bytes());
    }
    out
}
