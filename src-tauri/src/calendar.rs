//! Compatibility commands. Business rules live in reha-core::service.
use crate::state::{AppState, Proposal, Response, TauriPlatform};
use reha_core::contracts::*;
use serde_json::Value;
use std::sync::Arc;

#[tauri::command]
pub(crate) async fn prepare_undo(
    app: tauri::AppHandle,
    state: State<'_, Arc<AppState>>,
    batch_id: String,
) -> Response<Proposal> {
    reha_core::service::undo::prepare(Arc::new(TauriPlatform(app)), state.inner(), batch_id).await
}
use tauri::State;
#[tauri::command]
pub(crate) async fn set_page_group(
    state: State<'_, Arc<AppState>>,
    id: String,
    page_ids: Vec<String>,
) -> Response<usize> {
    let state = state.inner().clone();
    tauri::async_runtime::spawn_blocking(move || {
        reha_core::service::calendar::set_page_group(&state, id, page_ids)
    })
    .await
    .map_err(crate::state::failure)?
}

#[tauri::command]
pub(crate) async fn page_group(
    state: State<'_, Arc<AppState>>,
    id: String,
) -> Response<Vec<String>> {
    let state = state.inner().clone();
    tauri::async_runtime::spawn_blocking(move || {
        reha_core::service::calendar::page_group(&state, id)
    })
    .await
    .map_err(crate::state::failure)?
}

#[tauri::command]
pub(crate) async fn export_ics(
    state: State<'_, Arc<AppState>>,
    id: String,
    timezone: String,
    reminder: Option<u32>,
    selection: Option<Vec<String>>,
) -> Response<String> {
    let state = state.inner().clone();
    tauri::async_runtime::spawn_blocking(move || {
        reha_core::service::calendar::export_ics(&state, id, timezone, reminder, selection)
    })
    .await
    .map_err(crate::state::failure)?
}

#[tauri::command]
pub(crate) async fn calendars(app: tauri::AppHandle, dedicated: Option<bool>) -> Response<Value> {
    reha_core::service::calendar::calendars(Arc::new(TauriPlatform(app)), dedicated).await
}

#[tauri::command]
pub(crate) async fn share_export(
    app: tauri::AppHandle,
    filename: String,
    content: String,
) -> Response<Value> {
    reha_core::service::calendar::share_export(Arc::new(TauriPlatform(app)), filename, content)
        .await
}

#[tauri::command]
pub(crate) async fn resolve_proposal(
    state: State<'_, Arc<AppState>>,
    token: String,
    event_id: String,
    choice: String,
) -> Response<Proposal> {
    let state = state.inner().clone();
    tauri::async_runtime::spawn_blocking(move || {
        reha_core::service::calendar::resolve_proposal(&state, token, event_id, choice)
    })
    .await
    .map_err(crate::state::failure)?
}

#[tauri::command]
pub(crate) async fn approve_calendar(
    app: tauri::AppHandle,
    state: State<'_, Arc<AppState>>,
    token: String,
    approve_removals: bool,
) -> Response<Vec<CalendarResult>> {
    let state = state.inner().clone();
    tauri::async_runtime::spawn(async move {
        reha_core::service::calendar::approve_calendar(
            Arc::new(TauriPlatform(app)),
            &state,
            token,
            approve_removals,
        )
        .await
    })
    .await
    .map_err(crate::state::failure)?
}

#[tauri::command]
pub(crate) async fn reconcile_calendar(
    app: tauri::AppHandle,
    state: State<'_, Arc<AppState>>,
) -> Response<Vec<CalendarResult>> {
    reha_core::service::calendar::reconcile_calendar(Arc::new(TauriPlatform(app)), state.inner())
        .await
}

#[tauri::command]
pub(crate) async fn resolve_pending_write(
    state: State<'_, Arc<AppState>>,
    operation_id: String,
    resolution: String,
) -> Response<()> {
    reha_core::service::calendar::resolve_pending_write(state.inner(), operation_id, resolution)
        .await
}

#[tauri::command]
#[allow(clippy::too_many_arguments)]
pub(crate) async fn prepare_calendar(
    app: tauri::AppHandle,
    state: State<'_, Arc<AppState>>,
    id: String,
    calendar_id: String,
    previous: Option<String>,
    timezone: String,
    reminder: Option<u32>,
    selection: Option<Vec<String>>,
    replacement: Option<bool>,
) -> Response<Proposal> {
    reha_core::service::calendar::prepare_calendar(
        Arc::new(TauriPlatform(app)),
        state.inner(),
        id,
        calendar_id,
        previous,
        timezone,
        reminder,
        selection,
        replacement,
    )
    .await
}

#[tauri::command]
pub(crate) async fn assess_draft(
    state: State<'_, Arc<AppState>>,
    id: String,
    timezone: String,
) -> Response<reha_core::readiness::DraftAssessment> {
    let state = state.inner().clone();
    tauri::async_runtime::spawn_blocking(move || {
        reha_core::service::draft::assess(&state, id, timezone)
    })
    .await
    .map_err(crate::state::failure)?
}
#[tauri::command]
pub(crate) async fn preview_draft(
    app: tauri::AppHandle,
    state: State<'_, Arc<AppState>>,
    id: String,
    calendar_id: String,
    timezone: String,
    reminder: Option<u32>,
) -> Response<reha_core::service::draft::DraftPreview> {
    reha_core::service::draft::preview(
        Arc::new(TauriPlatform(app)),
        state.inner(),
        id,
        calendar_id,
        timezone,
        reminder,
    )
    .await
}
#[tauri::command]
pub(crate) async fn answer_draft_question(
    state: State<'_, Arc<AppState>>,
    id: String,
    revision: String,
    question_id: String,
    value: Option<Value>,
    timezone: String,
) -> Response<()> {
    let state = state.inner().clone();
    tauri::async_runtime::spawn_blocking(move || {
        reha_core::service::draft::answer(&state, id, revision, question_id, value, timezone)
    })
    .await
    .map_err(crate::state::failure)?
}
#[tauri::command]
pub(crate) async fn accept_and_save(
    app: tauri::AppHandle,
    state: State<'_, Arc<AppState>>,
    token: String,
    selection: Vec<String>,
    approve_removals: bool,
) -> Response<reha_core::service::draft::SaveOutcome> {
    let state = state.inner().clone();
    tauri::async_runtime::spawn(async move {
        reha_core::service::draft::accept_and_save(
            Arc::new(TauriPlatform(app)),
            &state,
            token,
            selection,
            approve_removals,
        )
        .await
    })
    .await
    .map_err(crate::state::failure)?
}

#[tauri::command]
pub(crate) async fn export_draft_ics(
    state: State<'_, Arc<AppState>>,
    id: String,
    revision: String,
    timezone: String,
    reminder: Option<u32>,
    selection: Vec<String>,
) -> Response<String> {
    let state = state.inner().clone();
    tauri::async_runtime::spawn_blocking(move || {
        reha_core::service::draft::export_ics(&state, id, revision, timezone, reminder, selection)
    })
    .await
    .map_err(crate::state::failure)?
}
#[tauri::command]
pub(crate) async fn preview_replacement(
    app: tauri::AppHandle,
    state: State<'_, Arc<AppState>>,
    id: String,
    calendar_id: String,
    timezone: String,
    reminder: Option<u32>,
) -> Response<reha_core::service::draft::DraftPreview> {
    reha_core::service::draft::preview_replacement(
        Arc::new(TauriPlatform(app)),
        state.inner(),
        id,
        calendar_id,
        timezone,
        reminder,
    )
    .await
}
