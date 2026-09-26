use crate::inference::{self, ImportRequest};
use crate::state::{failure, AppState, Response};
use base64::{engine::general_purpose::STANDARD, Engine};
use reha_core::contracts::*;
use serde_json::{json, Value};
use std::sync::Arc;
use std::{
    collections::HashSet,
    sync::atomic::{AtomicBool, Ordering},
};
use tauri::State;

#[tauri::command]
pub(crate) async fn import_image(
    app: tauri::AppHandle,
    state: State<'_, Arc<AppState>>,
    request: ImportRequest,
) -> Response<Value> {
    let started = std::time::Instant::now();
    uuid::Uuid::parse_str(&request.id).map_err(failure)?;
    if state
        .store
        .lock()
        .map_err(failure)?
        .load_run(&request.id)
        .is_ok()
    {
        return Err("Scan-ID wird bereits verwendet.".into());
    }
    if request.base64.len() > 56 * 1024 * 1024 {
        return Err("Foto ist zu groß (maximal 40 MB).".into());
    }
    let bytes = STANDARD
        .decode(&request.base64)
        .map_err(|_| "Ungültige Bilddaten.")?;
    let source_hash = reha_core::hash(&bytes);
    if !request.force {
        let store = state.store.lock().map_err(failure)?;
        if let Some(id) = store.identical(&source_hash).map_err(failure)? {
            if let Ok(run) = store.load_run(&id) {
                if run.config == request.config
                    && run.extraction_version == reha_core::parser::EXTRACTION_VERSION
                {
                    return Ok(json!({"run":run,"duplicate":true}));
                }
            }
        }
    }
    let cancel = Arc::new(AtomicBool::new(false));
    {
        let mut active = state.cancel.lock().map_err(failure)?;
        if !active.is_empty() {
            return Err("Eine Verarbeitung läuft bereits. Bitte warten oder abbrechen.".into());
        }
        active.insert(request.id.clone(), cancel.clone());
    }
    let shared = state.inner().clone();
    let id = request.id.clone();
    let attempt = json!({"id":id,"filename":request.filename,"config":request.config,"source_hash":source_hash,"started_at":chrono::Utc::now().timestamp(),"engine":request.config.engine});
    let result = tauri::async_runtime::spawn_blocking(move || {
        inference::process(app, shared, request, bytes, cancel, started)
    })
    .await
    .map_err(failure);
    state.cancel.lock().map_err(failure)?.remove(&id);
    let result = result.and_then(|inner| inner);
    if let Err(ref error) = result {
        let mut record = attempt;
        record["status"] = json!("failed");
        record["error"] = json!(error);
        record["internal_stage"] = json!("unavailable after pipeline failure");
        state
            .store
            .lock()
            .map_err(failure)?
            .record_failure(&id, chrono::Utc::now().timestamp(), &record)
            .map_err(failure)?;
    }
    result
}
#[tauri::command]
pub(crate) fn cancel_processing(state: State<'_, Arc<AppState>>) -> Response<()> {
    for flag in state.cancel.lock().map_err(failure)?.values() {
        flag.store(true, Ordering::Relaxed);
    }
    Ok(())
}
#[tauri::command]
pub(crate) fn history(state: State<'_, Arc<AppState>>) -> Response<Value> {
    let store = state.store.lock().map_err(failure)?;
    Ok(
        json!({"scans":store.list_scans().map_err(failure)?,"imports":store.records(None).map_err(failure)?,"pending":store.pending().map_err(failure)?.len(),"pending_details":store.pending().map_err(failure)?,"failures":store.failures().map_err(failure)?}),
    )
}
#[tauri::command]
pub(crate) fn load_scan(state: State<'_, Arc<AppState>>, id: String) -> Response<PipelineRun> {
    state
        .store
        .lock()
        .map_err(failure)?
        .load_run(&id)
        .map_err(failure)
}
#[tauri::command]
pub(crate) fn source_bytes(state: State<'_, Arc<AppState>>, id: String) -> Response<String> {
    let store = state.store.lock().map_err(failure)?;
    store.load_run(&id).map_err(failure)?;
    Ok(STANDARD.encode(
        std::fs::read(store.scan_dir(&id).map_err(failure)?.join("source.bin")).map_err(failure)?,
    ))
}
#[tauri::command]
pub(crate) fn scan_image(
    state: State<'_, Arc<AppState>>,
    id: String,
    artifact: String,
) -> Response<String> {
    if !["original.png", "page.png"].contains(&artifact.as_str())
        && !(artifact.starts_with("region-")
            && artifact.ends_with(".png")
            && artifact
                .chars()
                .all(|c| c.is_ascii_alphanumeric() || c == '-' || c == '.'))
    {
        return Err("Unbekanntes Bildartefakt.".into());
    }
    let store = state.store.lock().map_err(failure)?;
    store.load_run(&id).map_err(failure)?;
    let bytes =
        std::fs::read(store.scan_dir(&id).map_err(failure)?.join(artifact)).map_err(failure)?;
    Ok(format!("data:image/png;base64,{}", STANDARD.encode(bytes)))
}
#[tauri::command]
pub(crate) fn save_review(
    state: State<'_, Arc<AppState>>,
    id: String,
    appointments: Vec<Appointment>,
    complete: bool,
    reviewed: bool,
    selection: Option<Vec<String>>,
) -> Response<PipelineRun> {
    if appointments.len() > 1500 {
        return Err("Zu viele Termine.".into());
    }
    let store = state.store.lock().map_err(failure)?;
    let mut run = store.load_run(&id).map_err(failure)?;
    let mut ids = HashSet::new();
    for a in &appointments {
        uuid::Uuid::parse_str(&a.id).map_err(failure)?;
        if !ids.insert(&a.id) {
            return Err("Doppelte interne Termin-ID.".into());
        }
        if serde_json::to_vec(a).map_err(failure)?.len() > 100_000 {
            return Err("Termindaten zu lang.".into());
        }
    }
    let mut edited = Vec::new();
    for a in appointments {
        let old = run.appointments.iter().find(|old| old.id == a.id);
        edited.push(reha_core::review::edit(old, a).map_err(failure)?);
    }
    run.appointments = edited;
    run.complete_page_confirmed = complete;
    let selected = selection.unwrap_or_else(|| {
        if reviewed {
            run.appointments
                .iter()
                .filter(|a| a.included)
                .map(|a| a.id.clone())
                .collect()
        } else {
            vec![]
        }
    });
    reha_core::review::approve_selection(&mut run, &selected, chrono::Utc::now().timestamp())
        .map_err(failure)?;
    let preferences: Value = store
        .setting("preferences")
        .map_err(failure)?
        .and_then(|s| serde_json::from_str(&s).ok())
        .unwrap_or_default();
    let defaults = serde_json::from_value::<Vec<CompletionDefault>>(
        preferences["completion_defaults"].clone(),
    )
    .unwrap_or_default();
    reha_core::review::suggest(&mut run, &defaults, &store.records(None).map_err(failure)?);
    store.save_run(&run).map_err(failure)?;
    Ok(run)
}
#[tauri::command]
pub(crate) async fn capture(app: tauri::AppHandle, source: String) -> Response<Value> {
    if !["camera", "photos"].contains(&source.as_str()) {
        return Err("Unbekannte Bildquelle.".into());
    }
    tauri::async_runtime::spawn_blocking(move || {
        tauri_plugin_reha_calendar::call(&app, &source, json!({}))
    })
    .await
    .map_err(failure)?
}
#[tauri::command]
pub(crate) fn delete_scan(state: State<'_, Arc<AppState>>, id: String) -> Response<()> {
    state
        .store
        .lock()
        .map_err(failure)?
        .delete_scan(&id)
        .map_err(failure)
}

#[tauri::command]
pub(crate) async fn retry_scan(
    state: State<'_, Arc<AppState>>,
    id: String,
) -> Response<PipelineRun> {
    #[cfg(not(any(feature = "desktop-onnx", feature = "ios-onnx")))]
    {
        let _ = (state, id);
        Err("Portable Erkennung nicht verfügbar.".into())
    }
    #[cfg(any(feature = "desktop-onnx", feature = "ios-onnx"))]
    {
        let started = std::time::Instant::now();
        let cancel = Arc::new(AtomicBool::new(false));
        {
            let mut active = state.cancel.lock().map_err(failure)?;
            if !active.is_empty() {
                return Err("Eine Verarbeitung läuft bereits.".into());
            }
            active.insert(id.clone(), cancel.clone());
        }
        let shared = state.inner().clone();
        let scan_id = id.clone();
        let result = tauri::async_runtime::spawn_blocking(move || {
            let (mut run, dir) = {
                let store = shared.store.lock().map_err(failure)?;
                (
                    store.load_run(&scan_id).map_err(failure)?,
                    store.scan_dir(&scan_id).map_err(failure)?,
                )
            };
            let mut engine = shared.engine.lock().map_err(failure)?;
            let refinement = (|| -> Response<()> {
                if engine.as_ref().is_none_or(|e| e.name != "PP-OCRv6_small") {
                    *engine =
                        Some(reha_core::ocr::OnnxEngine::load(&shared.models).map_err(failure)?);
                }
                reha_core::refinement::refine(
                    engine.as_mut().ok_or("Model fehlt.")?,
                    &mut run,
                    &dir,
                    &cancel,
                    started + std::time::Duration::from_secs(60),
                )
                .map_err(failure)
            })();
            if let Err(error) = refinement {
                run.stages.push(Stage {
                    name: "selective_reread".into(),
                    status: "failed".into(),
                    duration_ms: started.elapsed().as_millis() as u64,
                    detail: error,
                    artifacts: vec![],
                });
            }
            let store = shared.store.lock().map_err(failure)?;
            // Discard no user edits that arrived while the CPU pass was running.
            let current = store.load_run(&scan_id).map_err(failure)?;
            for a in &mut run.appointments {
                if let Some(latest) = current.appointments.iter().find(|v| v.id == a.id) {
                    for field in reha_core::review::FIELDS {
                        if latest
                            .origins
                            .get(*field)
                            .is_some_and(|o| ["manual", "suggested"].contains(&o.kind.as_str()))
                        {
                            reha_core::review::set_value(
                                a,
                                field,
                                reha_core::review::value(latest, field),
                            )
                            .map_err(failure)?;
                            a.origins
                                .insert((*field).into(), latest.origins[*field].clone());
                        }
                    }
                    a.included = latest.included;
                    a.suggestions = latest.suggestions.clone();
                    a.calendar_event_id = latest.calendar_event_id.clone();
                    a.ics_exported_hash = latest.ics_exported_hash.clone();
                    if reha_core::review::values_hash(a) == reha_core::review::values_hash(latest) {
                        a.approval = latest.approval.clone();
                    }
                }
            }
            let prefs: Value = store
                .setting("preferences")
                .map_err(failure)?
                .and_then(|s| serde_json::from_str(&s).ok())
                .unwrap_or_default();
            reha_core::review::suggest(
                &mut run,
                &serde_json::from_value::<Vec<CompletionDefault>>(
                    prefs["completion_defaults"].clone(),
                )
                .unwrap_or_default(),
                &store.records(None).map_err(failure)?,
            );
            store.save_run(&run).map_err(failure)?;
            Ok(run)
        })
        .await
        .map_err(failure);
        state.cancel.lock().map_err(failure)?.remove(&id);
        result.and_then(|inner| inner)
    }
}
