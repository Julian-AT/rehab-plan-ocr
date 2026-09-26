//! Compatibility commands. Business rules live in reha-core::service.
use crate::state::{AppState, Response, TauriPlatform};
use serde_json::Value;
use std::sync::Arc;
use tauri::State;
#[tauri::command]
pub(crate) async fn erase_all(
    app: tauri::AppHandle,
    state: State<'_, Arc<AppState>>,
) -> Response<()> {
    reha_core::service::settings::erase_all(Arc::new(TauriPlatform(app)), state.inner()).await
}

#[tauri::command]
pub(crate) async fn maintenance(state: State<'_, Arc<AppState>>) -> Response<usize> {
    let state = state.inner().clone();
    tauri::async_runtime::spawn_blocking(move || reha_core::service::settings::maintenance(&state))
        .await
        .map_err(crate::state::failure)?
}

#[tauri::command]
pub(crate) async fn settings(
    app: tauri::AppHandle,
    state: State<'_, Arc<AppState>>,
    value: Option<Value>,
) -> Response<Value> {
    reha_core::service::settings::settings(Arc::new(TauriPlatform(app)), state.inner(), value).await
}

#[tauri::command]
pub(crate) fn engine_status(state: State<'_, Arc<AppState>>) -> Value {
    reha_core::service::settings::engine_status(state.inner())
}
