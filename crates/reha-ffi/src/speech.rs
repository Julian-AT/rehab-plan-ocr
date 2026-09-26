#[cfg(feature = "onnx")]
use crate::runtime;
use crate::AppError;
#[cfg(feature = "onnx")]
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
    #[cfg(feature = "onnx")]
    engine: Mutex<Option<reha_core::speech::SpeechEngine>>,
}
#[uniffi::export]
impl NativeSpeech {
    #[uniffi::constructor]
    pub fn new(model_directory: String) -> Self {
        Self {
            root: model_directory.into(),
            latest: AtomicU64::new(0),
            #[cfg(feature = "onnx")]
            engine: Mutex::new(None),
        }
    }
    pub fn set_request(&self, request: u64) {
        self.latest.store(request, Ordering::Release);
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
        #[cfg(feature = "onnx")]
        return runtime()
            .spawn_blocking(move || {
                if self.latest.load(Ordering::Acquire) != request {
                    return Err(AppError::Cancelled);
                }
                let mut cache = self.engine.lock().map_err(|_| AppError::Busy)?;
                let map = |e: reha_core::Error| AppError::Validation {
                    message: e.to_string(),
                };
                if cache.is_none() {
                    *cache = Some(reha_core::speech::SpeechEngine::load(&self.root).map_err(map)?);
                }
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
        #[cfg(not(feature = "onnx"))]
        {
            let _ = (self.root.as_path(), text, voice, speed, request);
            Err(AppError::Validation {
                message: "Lokale Stimme ist in diesem Build nicht enthalten.".into(),
            })
        }
    }
}
