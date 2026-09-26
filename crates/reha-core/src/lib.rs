pub mod calendar;
pub mod contracts;
pub mod evaluation;
pub mod geometry;
#[cfg(feature = "onnx")]
pub mod ocr;
pub mod parser;
mod photo;
#[cfg(target_os = "macos")]
mod photo_macos;
pub mod pipeline;
pub mod store;

pub type Result<T> = std::result::Result<T, Error>;

#[derive(Debug, thiserror::Error)]
pub enum Error {
    #[error("{0}")]
    Invalid(String),
    #[error("Local storage operation failed: {0}")]
    Io(#[from] std::io::Error),
    #[error("Invalid local record: {0}")]
    Json(#[from] serde_json::Error),
    #[error("Local database operation failed: {0}")]
    Sql(#[from] rusqlite::Error),
    #[error("Image could not be decoded: {0}")]
    Image(#[from] image::ImageError),
}

pub fn hash(bytes: &[u8]) -> String {
    use sha2::{Digest, Sha256};
    format!("{:x}", Sha256::digest(bytes))
}

pub mod readiness;
pub mod review;

mod numeric_candidates;
pub mod refinement;
mod refinement_targets;

pub mod service;
#[cfg(feature = "kokoro")]
pub mod speech;
#[path = "speech/text.rs"]
pub mod speech_text;

#[cfg(not(target_os = "ios"))]
pub mod lab;
