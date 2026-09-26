use crate::service::{failure, AppState, Response};
use serde_json::{json, Value};
use std::sync::Arc;

fn reminder_preferences(value: &Value) -> Value {
    json!({
        "enabled": value["app_reminders_enabled"].as_bool().unwrap_or(false),
        "minutes": value.get("app_reminder_minutes").cloned().unwrap_or(json!(10)),
        "sound": value["reminder_sound"].as_bool().unwrap_or(true),
        "preview": value["reminder_preview"].as_bool().unwrap_or(true)
    })
}

pub fn sync_request(state: &AppState) -> Response<Value> {
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
    Ok(
        json!({"records": records, "preferences": reminder_preferences(&preferences),
            "display_calendar_ids": preferences.get("display_calendar_ids").cloned().unwrap_or(json!([]))}),
    )
}
pub fn maintenance_warnings(response: &Value) -> Vec<String> {
    response["reminders"]["error"]
        .as_str()
        .filter(|s| !s.is_empty())
        .map(|s| vec![s.to_string()])
        .unwrap_or_default()
}
pub async fn sync(app: &Arc<dyn super::Platform>, state: &AppState) -> Response<Value> {
    let args = sync_request(state)?;
    let app = app.clone();
    tokio::task::spawn_blocking(move || app.call("agenda", args))
        .await
        .map_err(failure)?
}
pub async fn sync_warnings(app: &Arc<dyn super::Platform>, state: &AppState) -> Vec<String> {
    match sync(app, state).await {
        Ok(response) => maintenance_warnings(&response),
        Err(error) => vec![error.to_string()],
    }
}
pub async fn agenda(app: Arc<dyn super::Platform>, state: &Arc<AppState>) -> Response<Value> {
    let _guard = state.calendar_lock.lock().await;
    sync(&app, state).await
}
pub async fn test_reminder(app: Arc<dyn super::Platform>) -> Response<Value> {
    tokio::task::spawn_blocking(move || app.call("testReminder", json!({})))
        .await
        .map_err(failure)?
}
