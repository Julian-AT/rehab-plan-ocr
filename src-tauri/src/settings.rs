use crate::state::{failure, AppState, Response};
use serde_json::{json, Value};
use std::sync::Arc;
use tauri::State;

#[tauri::command]
pub(crate) async fn erase_all(
    app: tauri::AppHandle,
    state: State<'_, Arc<AppState>>,
) -> Response<()> {
    let _guard = state.calendar_lock.lock().await;
    if !state.cancel.lock().map_err(failure)?.is_empty() {
        return Err("Laufende Erkennung zuerst abbrechen.".into());
    }
    state.proposals.lock().map_err(failure)?.clear();
    state
        .store
        .lock()
        .map_err(failure)?
        .erase_all()
        .map_err(failure)?;
    #[cfg(target_os = "ios")]
    tauri::async_runtime::spawn_blocking(move || {
        tauri_plugin_reha_calendar::call(&app, "forgetCalendar", json!({}))
    })
    .await
    .map_err(failure)??;
    #[cfg(not(target_os = "ios"))]
    let _ = app;
    Ok(())
}
#[tauri::command]
pub(crate) fn maintenance(state: State<'_, Arc<AppState>>) -> Response<usize> {
    state
        .store
        .lock()
        .map_err(failure)?
        .cleanup(chrono::Utc::now().timestamp())
        .map_err(failure)
}
#[tauri::command]
pub(crate) fn settings(state: State<'_, Arc<AppState>>, value: Option<Value>) -> Response<Value> {
    let store = state.store.lock().map_err(failure)?;
    if let Some(value) = value {
        let timezone = value["timezone"].as_str().ok_or("Zeitzone fehlt.")?;
        timezone
            .parse::<chrono_tz::Tz>()
            .map_err(|_| "Unbekannte Zeitzone.")?;
        store
            .set_setting("preferences", &value.to_string())
            .map_err(failure)?;
        return Ok(value);
    }
    Ok(store
        .setting("preferences")
        .map_err(failure)?
        .and_then(|s| serde_json::from_str(&s).ok())
        .unwrap_or(json!({"timezone":"Europe/Vienna","reminder":null,"detailed_debug":false})))
}
#[tauri::command]
pub(crate) fn engine_status(state: State<'_, Arc<AppState>>) -> Value {
    json!({"portable_packaged":state.models.join("manifest.json").exists(),"platform":std::env::consts::OS,"runtime":"ONNX Runtime 1.22.0 / ort 2.0.0-rc.10","cloud_recognition":false})
}
