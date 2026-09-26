//! Explicit local-link cleanup. This service never sends an EventKit mutation.
use super::{failure, AppState, Platform, Response};
use crate::store::OwnedEventRecord;
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use sha2::{Digest, Sha256};
use std::{
    collections::{BTreeMap, BTreeSet},
    sync::Arc,
};

#[derive(Deserialize)]
struct Inspection {
    access: String,
    calendars: Vec<Calendar>,
    results: Vec<LinkResult>,
}
#[derive(Deserialize)]
struct Calendar {
    id: String,
}
#[derive(Deserialize)]
struct LinkResult {
    id: String,
    status: String,
    reason: Option<String>,
    event: Option<Value>,
}
#[derive(Deserialize)]
struct Selection {
    id: String,
    fingerprint: String,
}
#[derive(Serialize)]
struct Issue {
    id: String,
    fingerprint: String,
    calendar_id: String,
    title: String,
    start_utc: String,
    end_utc: String,
    timezone: String,
    reason: String,
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
    let selected: Vec<Selection> = if confirming {
        serde_json::from_value(args["selection"].clone()).map_err(failure)?
    } else {
        vec![]
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
    let request = json!({"records": records});
    let raw = tokio::task::spawn_blocking(move || host.call("inspectCalendarLinks", request))
        .await
        .map_err(failure)??;
    let inspection: Inspection = serde_json::from_value(raw).map_err(failure)?;
    if inspection.access != "fullAccess" {
        return Err("Zuerst Kalender-Vollzugriff erlauben.".into());
    }
    let calendars: BTreeSet<_> = inspection.calendars.iter().map(|c| c.id.as_str()).collect();
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
        match result.status.as_str() {
            "found" => {
                let event = result.event.as_ref().ok_or("Gefundener Termin fehlt.")?;
                let calendar = event["calendar_id"]
                    .as_str()
                    .filter(|s| calendars.contains(s))
                    .ok_or("Gefundener Kalender ist nicht lesbar.")?;
                let external = event["external_id"]
                    .as_str()
                    .filter(|s| !s.is_empty())
                    .ok_or("Gefundene Terminkennung fehlt.")?;
                if event["metadata"]["url"].as_str()
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
            "deleted" | "unavailable" => {
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
                        reason: result
                            .reason
                            .clone()
                            .unwrap_or_else(|| result.status.clone()),
                    });
                }
            }
            _ => return Err("Unbekanntes Prüfergebnis. Es wurde nichts bereinigt.".into()),
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
        super::agenda::sync(&platform, state).await.err()
    };
    Ok(json!({"issues": issues, "missing_calendar_ids": missing,
        "relinked_count": relinked, "removed_count": removed,
        "cleanup_blocked": blocked, "refresh_warning": refresh_warning}))
}
