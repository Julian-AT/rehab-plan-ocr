use crate::{contracts::CalendarOperation, store::Store};
use serde::Serialize;
use std::{
    collections::HashMap,
    path::PathBuf,
    sync::{atomic::AtomicBool, Arc, Mutex},
};

pub type Response<T> = std::result::Result<T, String>;
pub fn failure(e: impl std::fmt::Display) -> String {
    e.to_string()
}
pub struct Application {
    pub store: Mutex<Store>,
    pub models: PathBuf,
    #[cfg(feature = "onnx")]
    pub engine: Mutex<Option<crate::ocr::OnnxEngine>>,
    pub cancel: Mutex<HashMap<String, Arc<AtomicBool>>>,
    pub proposals: Mutex<HashMap<String, Proposal>>,
    pub event_proposals: Mutex<HashMap<String, events::EventProposal>>,
    pub invalid_event_sessions: Mutex<std::collections::HashSet<String>>,
    pub calendar_lock: tokio::sync::Mutex<()>,
    /// Serializes job admission with deletion; never held during inference.
    pub lifecycle_lock: tokio::sync::Mutex<()>,
}
#[derive(Clone, Serialize)]
pub struct Proposal {
    pub token: String,
    pub document_id: String,
    pub document_ids: Vec<String>,
    pub run_hash: String,
    pub schedule_id: String,
    pub fingerprint: String,
    pub operations: Vec<CalendarOperation>,
    pub protected_event_ids: Vec<String>,
    pub bindings: std::collections::BTreeMap<String, String>,
    pub undo_of: Option<String>,
    pub resume_batch: Option<String>,
    pub overlaps: Option<Vec<crate::contracts::CalendarOverlap>>,
    pub comparison_events: std::collections::BTreeMap<String, crate::contracts::EventValues>,
    pub overlap_exclusions: Vec<String>,
    pub draft: Option<draft::DraftIntent>,
}

/// Platform effects only. The FFI adapter exposes typed callbacks, while the
/// Tauri adapter preserves its existing wire payloads.
pub trait Platform: Send + Sync {
    fn call(&self, command: &str, arguments: serde_json::Value) -> Response<serde_json::Value>;
    fn progress(&self, value: serde_json::Value);
    fn cancelled(&self, _id: &str) -> bool {
        false
    }
    fn overlaps(
        &self,
        _events: std::collections::BTreeMap<String, crate::contracts::EventValues>,
        _exclude: Vec<String>,
    ) -> Response<Option<Vec<crate::contracts::CalendarOverlap>>> {
        Ok(None)
    }
}
pub type AppState = Application;
impl Application {
    pub fn new(store: Store, models: PathBuf) -> Self {
        Self {
            store: Mutex::new(store),
            models,
            #[cfg(feature = "onnx")]
            engine: Mutex::new(None),
            cancel: Mutex::new(HashMap::new()),
            proposals: Mutex::new(HashMap::new()),
            event_proposals: Mutex::new(HashMap::new()),
            invalid_event_sessions: Mutex::new(std::collections::HashSet::new()),
            calendar_lock: tokio::sync::Mutex::new(()),
            lifecycle_lock: tokio::sync::Mutex::new(()),
        }
    }
    pub fn cancel_job(&self, id: &str) -> Response<()> {
        if let Some(flag) = self.cancel.lock().map_err(failure)?.get(id) {
            flag.store(true, std::sync::atomic::Ordering::Relaxed);
        }
        Ok(())
    }
}
pub mod agenda;
pub mod calendar;
pub mod inference;
pub mod scan;
pub mod settings;
pub mod undo;

pub mod draft;
pub mod events;
