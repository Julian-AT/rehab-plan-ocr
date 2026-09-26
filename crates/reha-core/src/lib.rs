pub mod calendar;
pub mod contracts;
pub mod evaluation;
pub mod geometry;
#[cfg(feature = "onnx")]
pub mod ocr;
pub mod parser;
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
