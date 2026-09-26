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

pub async fn sync(app: &Arc<dyn super::Platform>, state: &AppState) -> Response<Value> {
    let args = {
        let store = state.store.lock().map_err(failure)?;
        let records: Vec<_> = store
            .records(None)
            .map_err(failure)?
            .into_iter()
            .filter(|r| r.status == "saved" && r.external_id.is_some())
            .collect();
        let preferences = store
            .setting("preferences")
            .map_err(failure)?
            .and_then(|v| serde_json::from_str::<Value>(&v).ok())
            .unwrap_or(json!({}));
        json!({"records": records, "preferences": reminder_preferences(&preferences)})
    };
    let app = app.clone();
    tokio::task::spawn_blocking(move || app.call("agenda", args))
        .await
        .map_err(failure)?
}
pub async fn agenda(app: Arc<dyn super::Platform>, state: &Arc<AppState>) -> Response<Value> {
    let _guard = state.calendar_lock.lock().await;
    sync(&app, state).await
}
pub async fn enable_reminders(
    app: Arc<dyn super::Platform>,
    state: &Arc<AppState>,
) -> Response<Value> {
    let _guard = state.calendar_lock.lock().await;
    let mut preferences: Value = state
        .store
        .lock()
        .map_err(failure)?
        .setting("preferences")
        .map_err(failure)?
        .and_then(|v| serde_json::from_str(&v).ok())
        .unwrap_or(json!({"timezone":"Europe/Vienna","reminder":10}));
    // Seed the committed registry before requesting permission; drafts never enter it.
    sync(&app, state).await?;
    let args = reminder_preferences(&preferences);
    let handle = app.clone();
    let result = tokio::task::spawn_blocking(move || handle.call("enableReminders", args))
        .await
        .map_err(failure)??;
    if matches!(
        result["reminders"]["authorization"].as_str(),
        Some("authorized" | "provisional")
    ) {
        preferences["app_reminders_enabled"] = json!(true);
        if preferences.get("app_reminder_minutes").is_none() {
            preferences["app_reminder_minutes"] = json!(10);
        }
        state
            .store
            .lock()
            .map_err(failure)?
            .set_setting("preferences", &preferences.to_string())
            .map_err(failure)?;
    }
    Ok(result)
}
pub async fn reminder_status(app: Arc<dyn super::Platform>) -> Response<Value> {
    tokio::task::spawn_blocking(move || app.call("reminderStatus", json!({})))
        .await
        .map_err(failure)?
}
pub async fn pending_event_open(
    app: Arc<dyn super::Platform>,
    acknowledge: Option<String>,
) -> Response<Value> {
    tokio::task::spawn_blocking(move || {
        app.call("pendingEventOpen", json!({"acknowledge":acknowledge}))
    })
    .await
    .map_err(failure)?
}
pub async fn test_reminder(app: Arc<dyn super::Platform>) -> Response<Value> {
    tokio::task::spawn_blocking(move || app.call("testReminder", json!({})))
        .await
        .map_err(failure)?
}
