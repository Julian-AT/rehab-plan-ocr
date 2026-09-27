#[cfg(feature = "kokoro")]
use crate::runtime;
use crate::AppError;
#[cfg(feature = "kokoro")]
use std::sync::Mutex;
use std::{
    path::PathBuf,
    sync::{
        atomic::{AtomicU64, Ordering},
        Arc,
    },
};

#[derive(uniffi::Record)]
pub struct SpeechWordMark {
    pub text: String,
    pub start: f64,
    pub end: f64,
}
#[derive(uniffi::Record)]
pub struct SpeechRender {
    pub audio: Vec<u8>,
    pub marks: Vec<SpeechWordMark>,
    pub duration: f64,
}

#[derive(uniffi::Object)]
pub struct NativeSpeech {
    root: PathBuf,
    latest: AtomicU64,
    threads: u32,
    #[cfg(feature = "kokoro")]
    engine: Mutex<Option<reha_core::speech::SpeechEngine>>,
}
#[uniffi::export]
impl NativeSpeech {
    #[uniffi::constructor]
    pub fn new(model_directory: String) -> Self {
        Self::with_threads(model_directory, 4)
    }
    /// Explicit configuration for fixed-text device qualification. The app uses
    /// `new`; never accepts an unbounded thread pool from a model or transcript.
    #[uniffi::constructor]
    pub fn with_threads(model_directory: String, threads: u32) -> Self {
        Self {
            root: model_directory.into(),
            latest: AtomicU64::new(0),
            threads,
            #[cfg(feature = "kokoro")]
            engine: Mutex::new(None),
        }
    }
    pub fn set_request(&self, request: u64) {
        self.latest.store(request, Ordering::Release);
    }
    /// Verify and load once while the user is listening. No generated speech,
    /// microphone work, or playback happens on this background worker.
    pub async fn prepare(self: Arc<Self>, request: u64) -> Result<(), AppError> {
        #[cfg(feature = "kokoro")]
        return runtime()
            .spawn_blocking(move || {
                self.check_request(request)?;
                let mut cache = self.engine.lock().map_err(|_| AppError::Busy)?;
                self.check_request(request)?;
                self.load(&mut cache)?;
                self.check_request(request)
            })
            .await
            .map_err(|_| AppError::Validation {
                message: "Lokale Stimme konnte nicht geladen werden.".into(),
            })?;
        #[cfg(not(feature = "kokoro"))]
        {
            let _ = (self.root.as_path(), self.threads, request);
            Err(AppError::Validation {
                message: "Lokale Stimme ist in diesem Build nicht enthalten.".into(),
            })
        }
    }
    pub async fn render(
        self: Arc<Self>,
        text: String,
        voice: String,
        speed: f32,
        request: u64,
    ) -> Result<Vec<u8>, AppError> {
        Ok(self.render_timed(text, voice, speed, request).await?.audio)
    }
    pub async fn render_timed(
        self: Arc<Self>,
        text: String,
        voice: String,
        speed: f32,
        request: u64,
    ) -> Result<SpeechRender, AppError> {
        #[cfg(feature = "kokoro")]
        return runtime()
            .spawn_blocking(move || {
                self.check_request(request)?;
                let mut cache = self.engine.lock().map_err(|_| AppError::Busy)?;
                self.check_request(request)?;
                let map = |e: reha_core::Error| AppError::Validation {
                    message: e.to_string(),
                };
                self.load(&mut cache)?;
                self.check_request(request)?;
                cache
                    .as_mut()
                    .unwrap()
                    .render_timed(&text, &voice, speed, request, &self.latest)
                    .map(|render| SpeechRender {
                        audio: render.audio,
                        duration: render.duration,
                        marks: render
                            .marks
                            .into_iter()
                            .map(|mark| SpeechWordMark {
                                text: mark.text,
                                start: mark.start,
                                end: mark.end,
                            })
                            .collect(),
                    })
                    .map_err(map)
            })
            .await
            .map_err(|_| AppError::Validation {
                message: "Lokale Stimme konnte nicht geladen werden.".into(),
            })?;
        #[cfg(not(feature = "kokoro"))]
        {
            let _ = (self.root.as_path(), text, voice, speed, request);
            Err(AppError::Validation {
                message: "Lokale Stimme ist in diesem Build nicht enthalten.".into(),
            })
        }
    }
}

#[cfg(feature = "kokoro")]
impl NativeSpeech {
    fn check_request(&self, request: u64) -> Result<(), AppError> {
        if self.latest.load(Ordering::Acquire) == request {
            Ok(())
        } else {
            Err(AppError::Cancelled)
        }
    }
    fn load(&self, cache: &mut Option<reha_core::speech::SpeechEngine>) -> Result<(), AppError> {
        if cache.is_none() {
            *cache = Some(
                reha_core::speech::SpeechEngine::load_with_threads(
                    &self.root,
                    self.threads as usize,
                )
                .map_err(|e| AppError::Validation {
                    message: e.to_string(),
                })?,
            );
        }
        Ok(())
    }
}

/// Same preparation as the renderer, without loading model weights.
#[uniffi::export]
pub fn normalize_speech(text: String) -> String {
    reha_core::speech_text::normalize(&text)
}
