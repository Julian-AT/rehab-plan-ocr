//! Compatibility commands. Business rules live in reha-core::service.
use crate::inference::ImportRequest;
use crate::state::{AppState, Response, TauriPlatform};
use reha_core::contracts::*;
use serde_json::Value;
use std::sync::Arc;
use tauri::State;
#[tauri::command]
pub(crate) async fn import_image(
    app: tauri::AppHandle,
    state: State<'_, Arc<AppState>>,
    request: ImportRequest,
) -> Response<Value> {
    let mut value = reha_core::service::scan::import_image(
        Arc::new(TauriPlatform(app)),
        state.inner(),
        request,
    )
    .await?;
    let run = serde_json::from_value(value["run"].clone()).map_err(crate::state::failure)?;
    value["run"] = wire_run(run)?;
    Ok(value)
}

#[tauri::command]
pub(crate) fn cancel_processing(state: State<'_, Arc<AppState>>) -> Response<()> {
    reha_core::service::scan::cancel_processing(state.inner())
}

#[tauri::command]
pub(crate) async fn history(state: State<'_, Arc<AppState>>) -> Response<Value> {
    let state = state.inner().clone();
    tauri::async_runtime::spawn_blocking(move || reha_core::service::scan::history(&state))
        .await
        .map_err(crate::state::failure)?
}

#[tauri::command]
pub(crate) async fn load_scan(state: State<'_, Arc<AppState>>, id: String) -> Response<Value> {
    let state = state.inner().clone();
    tauri::async_runtime::spawn_blocking(move || {
        reha_core::service::scan::load_scan(&state, id).and_then(wire_run)
    })
    .await
    .map_err(crate::state::failure)?
}

#[tauri::command]
pub(crate) async fn source_bytes(state: State<'_, Arc<AppState>>, id: String) -> Response<String> {
    let state = state.inner().clone();
    tauri::async_runtime::spawn_blocking(move || reha_core::service::scan::source_bytes(&state, id))
        .await
        .map_err(crate::state::failure)?
}

#[tauri::command]
pub(crate) async fn scan_image(
    state: State<'_, Arc<AppState>>,
    id: String,
    artifact: String,
) -> Response<String> {
    let state = state.inner().clone();
    tauri::async_runtime::spawn_blocking(move || {
        reha_core::service::scan::scan_image(&state, id, artifact)
    })
    .await
    .map_err(crate::state::failure)?
}

#[tauri::command]
pub(crate) async fn save_review(
    state: State<'_, Arc<AppState>>,
    id: String,
    appointments: Vec<Appointment>,
    complete: bool,
    reviewed: bool,
    selection: Option<Vec<String>>,
    expected_revision: Option<String>,
) -> Response<Value> {
    let state = state.inner().clone();
    tauri::async_runtime::spawn_blocking(move || {
        reha_core::service::scan::save_review(
            &state,
            id,
            appointments,
            complete,
            reviewed,
            selection,
            expected_revision,
        )
        .and_then(wire_run)
    })
    .await
    .map_err(crate::state::failure)?
}

#[tauri::command]
pub(crate) async fn capture(app: tauri::AppHandle, source: String) -> Response<Value> {
    reha_core::service::scan::capture(Arc::new(TauriPlatform(app)), source).await
}

#[tauri::command]
pub(crate) async fn delete_scan(state: State<'_, Arc<AppState>>, id: String) -> Response<()> {
    let state = state.inner().clone();
    tauri::async_runtime::spawn_blocking(move || reha_core::service::scan::delete_scan(&state, id))
        .await
        .map_err(crate::state::failure)?
}

#[tauri::command]
pub(crate) async fn associate_recheck(
    state: State<'_, Arc<AppState>>,
    id: String,
    previous: String,
) -> Response<()> {
    let state = state.inner().clone();
    tauri::async_runtime::spawn_blocking(move || {
        reha_core::service::scan::associate_recheck(&state, id, previous)
    })
    .await
    .map_err(crate::state::failure)?
}

#[tauri::command]
pub(crate) async fn retry_scan(
    app: tauri::AppHandle,
    state: State<'_, Arc<AppState>>,
    id: String,
) -> Response<Value> {
    reha_core::service::scan::retry_scan(Arc::new(TauriPlatform(app)), state.inner(), id)
        .await
        .and_then(wire_run)
}

fn wire_run(run: PipelineRun) -> Response<Value> {
    let revision = reha_core::service::scan::revision(&run);
    let mut value = serde_json::to_value(run).map_err(crate::state::failure)?;
    value["revision"] = Value::String(revision);
    Ok(value)
}
