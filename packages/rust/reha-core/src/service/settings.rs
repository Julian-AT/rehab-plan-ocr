use crate as reha_core;
use crate::service::{failure, AppState, DomainFailure, Response};
use serde_json::{json, Value};
use std::sync::Arc;

pub async fn erase_all(app: Arc<dyn super::Platform>, state: &Arc<AppState>) -> Response<()> {
    let _guard = state.calendar_lock.lock().await;
    let _admission = state.lifecycle_lock.lock().await;
    if !state.cancel.lock().map_err(failure)?.is_empty() {
        return Err("Laufende Erkennung zuerst abbrechen.".into());
    }
    state.proposals.lock().map_err(failure)?.clear();
    state.event_proposals.lock().map_err(failure)?.clear();
    state.event_sessions.lock().map_err(failure)?.revoke_all();
    #[cfg(target_os = "ios")]
    tokio::task::spawn_blocking(move || app.call("forgetCalendar", json!({})))
        .await
        .map_err(failure)??;
    state
        .store
        .lock()
        .map_err(failure)?
        .erase_all()
        .map_err(failure)?;
    #[cfg(not(target_os = "ios"))]
    let _ = app;
    Ok(())
}
pub fn maintenance(state: &Arc<AppState>) -> Response<usize> {
    let _admission = state
        .lifecycle_lock
        .try_lock()
        .map_err(|_| DomainFailure::Busy.with_message("Eine Datenänderung läuft bereits."))?;
    if !state.cancel.lock().map_err(failure)?.is_empty() {
        return Err(DomainFailure::Busy
            .with_message("Eine Verarbeitung läuft bereits. Bitte warten oder abbrechen."));
    }
    state
        .store
        .lock()
        .map_err(failure)?
        .cleanup(chrono::Utc::now().timestamp())
        .map_err(failure)
}
pub fn settings_value(state: &AppState, value: Option<Value>) -> Response<Value> {
    let store = state.store.lock().map_err(failure)?;
    if let Some(mut value) = value {
        // Older transports omit these keys. Preserve explicit native choices.
        let old: Value = store
            .setting("preferences")
            .map_err(failure)?
            .and_then(|s| serde_json::from_str(&s).ok())
            .unwrap_or(json!({}));
        for key in ["display_calendar_ids", "recent_calendar_ids"] {
            if value.get(key).is_none() {
                if let Some(previous) = old.get(key) {
                    value[key] = previous.clone();
                } else {
                    continue;
                }
            }
            let ids = value[key].as_array().ok_or("Kalenderauswahl ungültig.")?;
            if ids.len() > 100
                || ids
                    .iter()
                    .any(|id| id.as_str().is_none_or(|s| s.is_empty() || s.len() > 1024))
            {
                return Err("Kalenderauswahl ungültig.".into());
            }
        }
        let changed = value["display_calendar_ids"] != old["display_calendar_ids"]
            || value["timezone"] != old["timezone"];
        let revision = old["display_selection_revision"].as_u64().unwrap_or(0);
        value["display_selection_revision"] = json!(if changed {
            revision
                .checked_add(1)
                .ok_or("Kalenderauswahl-Version erschöpft.")?
        } else {
            revision
        });
        let timezone = value["timezone"].as_str().ok_or("Zeitzone fehlt.")?;
        timezone
            .parse::<chrono_tz::Tz>()
            .map_err(|_| "Unbekannte Zeitzone.")?;
        if value["reminder"].as_u64().is_some_and(|m| m > 10080) {
            return Err("Erinnerung maximal sieben Tage vorher.".into());
        }
        if let Some(days) = value.get("retention_days").filter(|v| !v.is_null()) {
            if !days.as_u64().is_some_and(|v| (1..=3650).contains(&v)) {
                return Err("Aufbewahrung: bis zum Löschen oder 1 bis 3650 Tage.".into());
            }
        }
        if let Some(minutes) = value.get("app_reminder_minutes") {
            if !minutes.is_null()
                && !minutes
                    .as_u64()
                    .is_some_and(|v| [5, 10, 15, 30, 60].contains(&v))
            {
                return Err("Erinnerung: aus, 5, 10, 15, 30 oder 60 Minuten wählen.".into());
            }
        }
        if let Some(defaults) = value.get("completion_defaults") {
            let defaults: Vec<reha_core::contracts::CompletionDefault> =
                serde_json::from_value(defaults.clone()).map_err(failure)?;
            if defaults.len() > 100 {
                return Err("Maximal 100 Vorgaben.".into());
            }
            for d in &defaults {
                reha_core::review::validate_default(d).map_err(failure)?;
            }
        }
        store
            .set_setting("preferences", &value.to_string())
            .map_err(failure)?;
        return Ok(value);
    }
    Ok(store
        .setting("preferences")
        .map_err(failure)?
        .and_then(|s| serde_json::from_str(&s).ok())
        .unwrap_or(json!({"timezone":"Europe/Vienna","reminder":10,"detailed_debug":false})))
}
