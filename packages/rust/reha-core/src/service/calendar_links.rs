//! Read-only ownership evidence. No calendar snapshot or write crosses this boundary.
use super::{calendar_reads::invalid_response, Response};
use serde::Deserialize;
use serde_json::Value;

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
