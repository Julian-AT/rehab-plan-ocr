use crate::service::{failure, AppState, Response};
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use std::sync::Arc;

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct ReminderPreferences {
    pub enabled: bool,
    pub minutes: Option<u32>,
    pub sound: bool,
    pub preview: bool,
}
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct SyncRequest {
    pub records: Vec<crate::store::OwnedEventRecord>,
    pub preferences: ReminderPreferences,
    pub display_calendar_ids: Vec<String>,
}
#[derive(Clone, Debug, Default)]
pub struct SyncResult {
    pub maintenance_warnings: Vec<String>,
}
fn storage(error: impl std::fmt::Display) -> super::ServiceError {
    super::ServiceError::Storage(error.to_string())
}
fn reminder_preferences(value: &Value) -> Response<ReminderPreferences> {
    Ok(ReminderPreferences {
        enabled: value["app_reminders_enabled"].as_bool().unwrap_or(false),
        minutes: match value.get("app_reminder_minutes") {
            None => Some(10),
            Some(value) => serde_json::from_value(value.clone()).map_err(storage)?,
        },
        sound: value["reminder_sound"].as_bool().unwrap_or(true),
        preview: value["reminder_preview"].as_bool().unwrap_or(true),
    })
}

pub fn sync_request(state: &AppState) -> Response<SyncRequest> {
    let store = state.store.lock().map_err(failure)?;
    let records: Vec<_> = store
        .owned_records()
        .map_err(failure)?
        .into_iter()
        .filter(|r| r.status == "saved" && r.external_id.is_some())
        .collect();
    let preferences = store
        .setting("preferences")
        .map_err(failure)?
        .and_then(|v| serde_json::from_str::<Value>(&v).ok())
        .unwrap_or(json!({}));
    let display_calendar_ids: Option<Vec<String>> = serde_json::from_value(
        preferences
            .get("display_calendar_ids")
            .cloned()
            .unwrap_or(Value::Null),
    )
    .map_err(storage)?;
    Ok(SyncRequest {
        records,
        preferences: reminder_preferences(&preferences)?,
        display_calendar_ids: display_calendar_ids.unwrap_or_default(),
    })
}
pub fn maintenance_warnings(response: &Value) -> Vec<String> {
    response["reminders"]["error"]
        .as_str()
        .filter(|s| !s.is_empty())
        .map(|s| vec![s.to_string()])
        .unwrap_or_default()
}
pub async fn sync(app: &Arc<dyn super::Platform>, state: &AppState) -> Response<SyncResult> {
    let args = sync_request(state)?;
    let app = app.clone();
    tokio::task::spawn_blocking(move || app.synchronize_agenda(args))
        .await
        .map_err(failure)?
}
pub async fn sync_warnings(app: &Arc<dyn super::Platform>, state: &AppState) -> Vec<String> {
    match sync(app, state).await {
        Ok(response) => response.maintenance_warnings,
        Err(error) => vec![error.to_string()],
    }
}
pub async fn agenda(app: Arc<dyn super::Platform>, state: &Arc<AppState>) -> Response<Value> {
    let _guard = state.calendar_lock.lock().await;
    legacy_sync(&app, state).await
}
/// Existing command clients retain the complete historical response. The native
/// app and internal maintenance use the typed effect above.
pub async fn legacy_sync(app: &Arc<dyn super::Platform>, state: &AppState) -> Response<Value> {
    let args = serde_json::to_value(sync_request(state)?).map_err(storage)?;
    let app = app.clone();
    tokio::task::spawn_blocking(move || app.call("agenda", args))
        .await
        .map_err(failure)?
}
pub async fn test_reminder(app: Arc<dyn super::Platform>) -> Response<Value> {
    tokio::task::spawn_blocking(move || app.call("testReminder", json!({})))
        .await
        .map_err(failure)?
}
