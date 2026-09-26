//! Typed platform reads. JSON exists only at old UI/host adapters and for the
//! unchanged metadata snapshot used by comparison and recovery journals.
use super::{failure, Platform, Response, ServiceError};
use crate::store::OwnedEventRecord;
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use std::sync::Arc;

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct Query {
    pub calendar_ids: Vec<String>,
    pub start_utc: String,
    pub end_utc: String,
    pub timezone: String,
    pub selection_revision: u64,
    pub records: Vec<OwnedEventRecord>,
}
#[derive(Clone, Debug, Serialize, Deserialize, PartialEq)]
pub struct Reference {
    pub calendar_id: String,
    pub external_id: String,
    pub occurrence: String,
    pub expected_start_utc: String,
}
impl Reference {
    pub fn legacy(&self) -> Value {
        json!({"calendar_id":self.calendar_id,"external_id":self.external_id,
            "occurrence":self.occurrence,"values":{"start_utc":self.expected_start_utc}})
    }
}
#[derive(Clone, Debug, Serialize, Deserialize, PartialEq)]
pub struct Values {
    pub title: String,
    pub start_utc: String,
    pub end_utc: String,
    pub timezone: String,
    pub location: String,
    pub reminder_minutes: Option<i64>,
}
#[derive(Clone, Debug, Serialize, Deserialize, PartialEq)]
pub struct Event {
    pub id: String,
    pub external_id: String,
    pub calendar_id: String,
    pub calendar_title: String,
    pub source: String,
    pub occurrence: String,
    pub recurring: bool,
    pub system_only: bool,
    pub writable: bool,
    pub values: Values,
    pub metadata: Value,
    pub fingerprint: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub import_id: Option<String>,
}
#[derive(Clone, Debug, Serialize, Deserialize, PartialEq)]
pub struct UnavailableEvent {
    pub id: String,
    pub start_utc: String,
    pub end_utc: String,
}
#[derive(Clone, Debug, Serialize, Deserialize, PartialEq)]
pub struct QueryResult {
    pub events: Vec<Event>,
    #[serde(default)]
    pub unavailable_calendar_ids: Vec<String>,
    #[serde(default)]
    pub unavailable_events: Vec<UnavailableEvent>,
}
pub fn invalid_response(error: impl std::fmt::Display) -> ServiceError {
    ServiceError::Storage(format!("Kalenderantwort ungültig: {error}"))
}
pub async fn query(platform: &Arc<dyn Platform>, request: Query) -> Response<QueryResult> {
    let platform = platform.clone();
    tokio::task::spawn_blocking(move || platform.query_calendar(request))
        .await
        .map_err(|error| ServiceError::Storage(error.to_string()))?
}
pub async fn resolve(platform: &Arc<dyn Platform>, event: &Event) -> Response<Option<Event>> {
    if event.calendar_id.is_empty() || event.external_id.is_empty() || event.occurrence.is_empty() {
        return Err(ServiceError::Validation(
            "Kalender oder Terminzuordnung fehlt.".into(),
        ));
    }
    let reference = Reference {
        calendar_id: event.calendar_id.clone(),
        external_id: event.external_id.clone(),
        occurrence: event.occurrence.clone(),
        expected_start_utc: event.values.start_utc.clone(),
    };
    let platform = platform.clone();
    tokio::task::spawn_blocking(move || platform.resolve_calendar_event(reference))
        .await
        .map_err(failure)?
}
