//! Read-only ownership inspection and explicit lookup of retained event links.
use super::{calendar_reads::invalid_response, failure, AppState, Platform, Response};
use serde::{Deserialize, Serialize};
use serde_json::Value;
use std::sync::Arc;

#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
#[serde(tag = "status", rename_all = "snake_case")]
pub enum OwnedResolution {
    Found {
        event: Box<super::calendar_reads::Event>,
    },
    Deleted,
    Unavailable,
    Missing,
}

/// Explicit owned-event links may open a hidden calendar; ordinary agenda reads
/// still use their captured visible scope. This lookup never repairs or writes.
pub async fn resolve_owned(
    platform: Arc<dyn Platform>,
    state: &AppState,
    id: &str,
) -> Response<OwnedResolution> {
    if id.is_empty() {
        return Err("id fehlt.".into());
    }
    uuid::Uuid::parse_str(id).map_err(failure)?;
    let _guard = state.calendar_lock.lock().await;
    let record = state
        .store
        .lock()
        .map_err(failure)?
        .owned_record(id)
        .map_err(failure)?;
    match record {
        Some(record) if record.status == "saved" => {
            tokio::task::spawn_blocking(move || platform.resolve_owned_event(record))
                .await
                .map_err(failure)?
        }
        Some(_) => Ok(OwnedResolution::Deleted),
        None => Ok(OwnedResolution::Missing),
    }
}

#[derive(Clone, Debug)]
pub struct Inspection {
    pub calendar_ids: Vec<String>,
    pub results: Vec<LinkResult>,
}
#[derive(Clone, Debug)]
pub struct LinkResult {
    pub id: String,
    pub state: LinkState,
}
#[derive(Clone, Debug)]
pub enum LinkState {
    Found {
        calendar_id: String,
        external_id: String,
        ownership_url: Option<String>,
    },
    Deleted {
        reason: Option<String>,
    },
    Unavailable {
        reason: Option<String>,
    },
}

impl Inspection {
    /// The legacy native response keeps its full snapshot. Only the three fields
    /// used as ownership evidence are decoded by this compatibility adapter.
    pub fn from_legacy(value: Value) -> Response<Self> {
        #[derive(Deserialize)]
        struct Legacy {
            access: String,
            calendars: Vec<Calendar>,
            results: Vec<Result>,
        }
        #[derive(Deserialize)]
        struct Calendar {
            id: String,
        }
        #[derive(Deserialize)]
        struct Result {
            id: String,
            status: String,
            reason: Option<String>,
            event: Option<Value>,
        }
        let legacy: Legacy = serde_json::from_value(value).map_err(invalid_response)?;
        if legacy.access != "fullAccess" {
            return Err("Zuerst Kalender-Vollzugriff erlauben.".into());
        }
        let results = legacy
            .results
            .into_iter()
            .map(|result| {
                let state = match result.status.as_str() {
                    "found" => {
                        let event = result.event.ok_or("Gefundener Termin fehlt.")?;
                        LinkState::Found {
                            calendar_id: event["calendar_id"]
                                .as_str()
                                .ok_or("Gefundener Kalender ist nicht lesbar.")?
                                .into(),
                            external_id: event["external_id"]
                                .as_str()
                                .ok_or("Gefundene Terminkennung fehlt.")?
                                .into(),
                            ownership_url: event["metadata"]["url"].as_str().map(str::to_owned),
                        }
                    }
                    "deleted" => LinkState::Deleted {
                        reason: result.reason,
                    },
                    "unavailable" => LinkState::Unavailable {
                        reason: result.reason,
                    },
                    _ => return Err("Unbekanntes Prüfergebnis. Es wurde nichts bereinigt.".into()),
                };
                Ok(LinkResult {
                    id: result.id,
                    state,
                })
            })
            .collect::<Response<Vec<_>>>()?;
        Ok(Self {
            calendar_ids: legacy.calendars.into_iter().map(|c| c.id).collect(),
            results,
        })
    }
}
