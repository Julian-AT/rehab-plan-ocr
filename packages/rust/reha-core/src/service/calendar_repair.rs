//! Explicit local-link cleanup. This service never sends an EventKit mutation.
use super::calendar_links::LinkState;
use super::{failure, AppState, Platform, Response};
use crate::store::OwnedEventRecord;
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use sha2::{Digest, Sha256};
use std::{
    collections::{BTreeMap, BTreeSet},
    sync::Arc,
};

#[derive(Clone, Debug, Deserialize)]
pub struct Selection {
    pub id: String,
    pub fingerprint: String,
}
#[derive(Clone, Debug, PartialEq, Serialize)]
pub struct Issue {
    pub id: String,
    pub fingerprint: String,
    pub calendar_id: String,
    pub title: String,
    pub start_utc: String,
    pub end_utc: String,
    pub timezone: String,
    pub reason: String,
}
#[derive(Clone, Debug, PartialEq, Serialize)]
pub struct Report {
    pub issues: Vec<Issue>,
    pub missing_calendar_ids: Vec<String>,
    pub relinked_count: u64,
    pub removed_count: u64,
    pub cleanup_blocked: bool,
    pub refresh_warning: Option<String>,
}
pub enum Request {
    Inspect,
    Confirm {
        selection: Vec<Selection>,
        confirmation: super::calendar_mutations::Confirmation,
    },
}
fn fingerprint(record: &OwnedEventRecord) -> Response<String> {
    Ok(format!(
        "{:x}",
        Sha256::digest(serde_json::to_vec(record).map_err(failure)?)
    ))
}

pub async fn run(
    platform: Arc<dyn Platform>,
    state: &AppState,
    command: &str,
    args: Value,
) -> Response<Value> {
    let confirming = command == "confirmCalendarRepair";
    if confirming && args["confirmation"] != "button" {
        return Err("Die ausgewählten Zuordnungen ausdrücklich bestätigen.".into());
    }
    let request = if confirming {
        Request::Confirm {
            selection: serde_json::from_value(args["selection"].clone()).map_err(failure)?,
            confirmation: super::calendar_mutations::Confirmation::Button,
        }
    } else {
        Request::Inspect
    };
    serde_json::to_value(execute(platform, state, request).await?).map_err(failure)
}

pub async fn execute(
    platform: Arc<dyn Platform>,
    state: &AppState,
    request: Request,
) -> Response<Report> {
    let (confirming, selected) = match request {
        Request::Inspect => (false, vec![]),
        Request::Confirm {
            selection,
            confirmation: super::calendar_mutations::Confirmation::Button,
        } => (true, selection),
        Request::Confirm {
            confirmation: super::calendar_mutations::Confirmation::MissingVisibleButton,
            ..
        } => return Err("Die ausgewählten Zuordnungen ausdrücklich bestätigen.".into()),
    };
    if confirming && (selected.is_empty() || selected.len() > 1000) {
        return Err("Bitte die zu bereinigenden Zuordnungen auswählen.".into());
    }
    let selection: BTreeMap<_, _> = selected
        .iter()
        .map(|s| (s.id.as_str(), s.fingerprint.as_str()))
        .collect();
    if selection.len() != selected.len() {
        return Err("Doppelte Auswahl.".into());
    }
    let _guard = state.calendar_lock.lock().await;
    let (records, preferences, blocked) = {
        let store = state.store.lock().map_err(failure)?;
        let preferences: Value = store
            .setting("preferences")
            .map_err(failure)?
            .map(|s| serde_json::from_str(&s))
            .transpose()
            .map_err(failure)?
            .unwrap_or(json!({}));
        (
            store.owned_records().map_err(failure)?,
            preferences,
            store.has_unresolved_calendar_writes().map_err(failure)?,
        )
    };
    if confirming && blocked {
        return Err("Zuerst ungeklärte Kalendervorgänge prüfen.".into());
    }
    for selected in &selected {
        let record = records
            .iter()
            .find(|r| r.id == selected.id)
            .ok_or("Die Auswahl ist nicht mehr aktuell. Bitte erneut prüfen.")?;
        if fingerprint(record)? != selected.fingerprint {
            return Err("Die Terminzuordnung wurde geändert. Bitte erneut prüfen.".into());
        }
    }
    let host = platform.clone();
    let request = records.clone();
    let inspection = tokio::task::spawn_blocking(move || host.inspect_calendar_links(request))
        .await
        .map_err(failure)??;
    let calendars: BTreeSet<_> = inspection.calendar_ids.iter().map(String::as_str).collect();
    let results: BTreeMap<_, _> = inspection
        .results
        .iter()
        .map(|r| (r.id.as_str(), r))
        .collect();
    if results.len() != records.len()
        || results.len() != inspection.results.len()
        || records.iter().any(|r| !results.contains_key(r.id.as_str()))
    {
        return Err("Kalenderprüfung unvollständig. Bitte erneut versuchen.".into());
    }
    let mut changes = vec![];
    let mut issues = vec![];
    let mut relinked = 0;
    let mut removed = 0;
    for record in records {
        let result = results[record.id.as_str()];
        match &result.state {
            LinkState::Found {
                calendar_id,
                external_id,
                ownership_url,
            } => {
                let calendar = calendar_id.as_str();
                let external = external_id.as_str();
                if !calendars.contains(calendar) {
                    return Err("Gefundener Kalender ist nicht lesbar.".into());
                }
                if external.is_empty() {
                    return Err("Gefundene Terminkennung fehlt.".into());
                }
                if ownership_url.as_deref()
                    != Some(format!("reha-calendar://event/{}", record.id).as_str())
                {
                    return Err("Terminzuordnung nicht eindeutig bestätigt.".into());
                }
                if !blocked
                    && (record.calendar_id != calendar
                        || record.external_id.as_deref() != Some(external))
                {
                    let mut updated = record.clone();
                    updated.calendar_id = calendar.into();
                    updated.external_id = Some(external.into());
                    changes.push((record, updated));
                    relinked += 1;
                }
            }
            LinkState::Deleted { reason } | LinkState::Unavailable { reason } => {
                if selection.contains_key(record.id.as_str()) {
                    let mut retired = record.clone();
                    retired.status = "detached".into();
                    changes.push((record, retired));
                    removed += 1;
                } else {
                    issues.push(Issue {
                        fingerprint: fingerprint(&record)?,
                        id: record.id,
                        calendar_id: record.calendar_id,
                        title: record.approved.title,
                        start_utc: record.approved.start_utc,
                        end_utc: record.approved.end_utc,
                        timezone: record.approved.timezone,
                        reason: reason.clone().unwrap_or_else(|| match result.state {
                            LinkState::Deleted { .. } => "deleted".into(),
                            _ => "unavailable".into(),
                        }),
                    });
                }
            }
        }
    }
    if !changes.is_empty() {
        state
            .store
            .lock()
            .map_err(failure)?
            .repair_owned_links(&changes)
            .map_err(failure)?;
        state.proposals.lock().map_err(failure)?.clear();
        state.event_proposals.lock().map_err(failure)?.clear();
    }
    let mut selected_calendars: BTreeSet<String> = preferences["display_calendar_ids"]
        .as_array()
        .into_iter()
        .flatten()
        .filter_map(|v| v.as_str().map(str::to_owned))
        .collect();
    if let Some(id) = preferences["calendar_id"]
        .as_str()
        .filter(|s| !s.is_empty())
    {
        selected_calendars.insert(id.into());
    }
    let missing: Vec<_> = selected_calendars
        .into_iter()
        .filter(|id| !calendars.contains(id.as_str()))
        .collect();
    // A failed refresh after a committed cleanup must not pretend that the
    // removal failed and invite an accidental retry with a different selection.
    let refresh_warning = if blocked {
        None
    } else {
        let warnings = super::agenda::sync_warnings(&platform, state).await;
        (!warnings.is_empty()).then(|| warnings.join("\n\n"))
    };
    Ok(Report {
        issues,
        missing_calendar_ids: missing,
        relinked_count: relinked,
        removed_count: removed,
        cleanup_blocked: blocked,
        refresh_warning,
    })
}
