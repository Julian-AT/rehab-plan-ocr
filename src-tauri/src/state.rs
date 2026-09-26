use reha_core::{contracts::CalendarOperation, store::Store};
use serde::Serialize;
use std::{
    collections::HashMap,
    path::PathBuf,
    sync::{atomic::AtomicBool, Arc, Mutex},
};

pub(crate) type Response<T> = std::result::Result<T, String>;
pub(crate) fn failure(e: impl std::fmt::Display) -> String {
    e.to_string()
}
pub(crate) struct AppState {
    pub(crate) store: Mutex<Store>,
    pub(crate) models: PathBuf,
    #[cfg(any(feature = "desktop-onnx", feature = "ios-onnx"))]
    pub(crate) engine: Mutex<Option<reha_core::ocr::OnnxEngine>>,
    pub(crate) cancel: Mutex<HashMap<String, Arc<AtomicBool>>>,
    pub(crate) proposals: Mutex<HashMap<String, Proposal>>,
    pub(crate) calendar_lock: tokio::sync::Mutex<()>,
}
#[derive(Clone, Serialize)]
pub(crate) struct Proposal {
    pub(crate) token: String,
    pub(crate) document_id: String,
    pub(crate) document_ids: Vec<String>,
    pub(crate) run_hash: String,
    pub(crate) schedule_id: String,
    pub(crate) fingerprint: String,
    pub(crate) operations: Vec<CalendarOperation>,
}
