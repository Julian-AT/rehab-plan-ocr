use crate::{contracts::CalendarOperation, store::Store};
use serde::Serialize;
use std::{
    collections::HashMap,
    path::PathBuf,
    sync::{atomic::AtomicBool, Arc, Mutex},
};

mod error;
pub use error::ServiceError;
mod event_sessions;
pub use event_sessions::EventSessions;
pub type Response<T> = std::result::Result<T, ServiceError>;
pub fn failure(e: impl std::fmt::Display) -> ServiceError {
    ServiceError::Legacy(e.to_string())
}
pub struct Application {
    pub store: Mutex<Store>,
    pub models: PathBuf,
    #[cfg(feature = "onnx")]
    pub engine: Mutex<Option<crate::ocr::OnnxEngine>>,
    pub cancel: Mutex<HashMap<String, Arc<AtomicBool>>>,
    pub proposals: Mutex<HashMap<String, Proposal>>,
    pub event_proposals: Mutex<HashMap<String, events::EventProposal>>,
    pub event_sessions: Mutex<EventSessions>,
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

/// Platform effects only. The native FFI adapter exposes typed host callbacks;
/// shared service commands and test hosts retain JSON payloads at this boundary.
pub trait Platform: Send + Sync {
    fn call(&self, command: &str, arguments: serde_json::Value) -> Response<serde_json::Value>;
    /// Compatibility defaults are confined to older hosts. Native effects override
    /// these methods and carry the existing domain values directly to UniFFI.
    fn import_snapshot(
        &self,
        records: Vec<crate::contracts::ImportRecord>,
    ) -> Response<calendar_imports::Snapshot> {
        serde_json::from_value(self.call("snapshot", serde_json::json!({"records":records}))?)
            .map_err(calendar_imports::invalid_response)
    }
    fn apply_import(
        &self,
        request: calendar_imports::ApplyRequest,
    ) -> Response<crate::contracts::CalendarResult> {
        let arguments =
            serde_json::to_value(request).map_err(calendar_imports::invalid_response)?;
        serde_json::from_value(self.call("apply", arguments)?)
            .map_err(calendar_imports::invalid_response)
    }
    fn synchronize_agenda(&self, request: agenda::SyncRequest) -> Response<agenda::SyncResult> {
        let arguments =
            serde_json::to_value(request).map_err(calendar_imports::invalid_response)?;
        let response = self.call("agenda", arguments)?;
        Ok(agenda::SyncResult {
            maintenance_warnings: agenda::maintenance_warnings(&response),
        })
    }
    fn calendar_status(&self) -> Response<calendar_administration::PlatformStatus> {
        serde_json::from_value(self.call("calendarStatus", serde_json::json!({}))?)
            .map_err(calendar_administration::storage)
    }
    /// Compatibility defaults serve older JSON hosts. Native adapters override
    /// both methods and never serialize a whole read payload across the FFI.
    fn query_calendar(
        &self,
        request: calendar_reads::Query,
    ) -> Response<calendar_reads::QueryResult> {
        let args = serde_json::to_value(request).map_err(calendar_reads::invalid_response)?;
        serde_json::from_value(self.call("queryEvents", args)?)
            .map_err(calendar_reads::invalid_response)
    }
    fn resolve_calendar_event(
        &self,
        reference: calendar_reads::Reference,
    ) -> Response<Option<calendar_reads::Event>> {
        let response = self.call("getEvent", serde_json::json!({"event":reference.legacy()}))?;
        let event = response
            .get("event")
            .ok_or_else(|| calendar_reads::invalid_response("Terminstatus fehlt."))?;
        serde_json::from_value(event.clone()).map_err(calendar_reads::invalid_response)
    }
    /// Legacy adapters keep their journal-shaped JSON. The native host overrides
    /// these methods and carries mutations and destinations as typed records.
    fn event_calendars(&self) -> Response<Vec<calendar_mutations::Destination>> {
        let response = self.call("eventCalendars", serde_json::json!({}))?;
        serde_json::from_value(response["calendars"].clone())
            .map_err(calendar_reads::invalid_response)
    }
    fn mutate_event(
        &self,
        request: calendar_mutations::MutationRequest,
    ) -> Response<calendar_mutations::MutationResult> {
        let args = serde_json::to_value(request).map_err(calendar_reads::invalid_response)?;
        serde_json::from_value(self.call("mutateEvent", args)?)
            .map_err(calendar_reads::invalid_response)
    }
    /// Native adapters override this binary boundary. The default only preserves
    /// compatibility for JSON platform adapters and existing test hosts.
    fn decode_photo(&self, bytes: &[u8]) -> Response<Vec<u8>> {
        use base64::{engine::general_purpose::STANDARD, Engine};
        let response = self.call(
            "decodePhoto",
            serde_json::json!({"base64": STANDARD.encode(bytes)}),
        )?;
        STANDARD
            .decode(
                response["base64"]
                    .as_str()
                    .ok_or("Unsupported image format.")?,
            )
            .map_err(failure)
    }
    fn progress(&self, value: serde_json::Value);
    fn cancelled(&self, _id: &str) -> bool {
        false
    }
    /// A native registration shares its attempt-specific flag with the worker.
    /// Other hosts keep the existing Core-owned cancellation registration.
    fn cancellation_flag(&self, _id: &str) -> Option<Arc<AtomicBool>> {
        None
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
            event_sessions: Mutex::new(EventSessions::default()),
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
pub mod agenda_queries;
pub mod calendar;
pub mod calendar_administration;
pub mod calendar_imports;
pub mod calendar_mutations;
pub mod calendar_reads;
mod calendar_repair;
pub mod inference;
pub mod scan;
pub mod settings;
pub mod undo;

pub mod draft;
pub mod events;
