use crate as reha_core;
use crate::service::inference::{self, ImportRequest};
use crate::service::{failure, AppState, Response};
use base64::{engine::general_purpose::STANDARD, Engine};
use reha_core::contracts::*;
use serde_json::{json, Value};
use std::sync::Arc;
use std::{
    collections::HashSet,
    sync::atomic::{AtomicBool, Ordering},
};

pub async fn import_image(
    app: Arc<dyn super::Platform>,
    state: &Arc<AppState>,
    request: ImportRequest,
) -> Response<Value> {
    let started = std::time::Instant::now();
    let admission = state.lifecycle_lock.lock().await;
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
    state
        .store
        .lock()
        .map_err(failure)?
        .stage_intake(
            &request.id,
            &request.filename,
            &bytes,
            &request.config,
            chrono::Utc::now().timestamp(),
        )
        .map_err(failure)?;
    state
        .store
        .lock()
        .map_err(failure)?
        .connection
        .execute(
            "UPDATE intakes SET config=?2 WHERE id=?1",
            rusqlite::params![
                request.id,
                serde_json::to_string(&request.config).map_err(failure)?
            ],
        )
        .map_err(failure)?;
    app.progress(json!({"id":request.id,"stage":"Original gespeichert","draft_available":false}));
    let source_hash = reha_core::hash(&bytes);
    if !request.force {
        let store = state.store.lock().map_err(failure)?;
        if let Some(id) = store.identical(&source_hash).map_err(failure)? {
            if let Ok(run) = store.load_run(&id) {
                if run.config == request.config
                    && run.extraction_version == reha_core::parser::EXTRACTION_VERSION
                {
                    store
                        .intake_status(&request.id, "duplicate", None)
                        .map_err(failure)?;
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
        if app.cancelled(&request.id) {
            cancel.store(true, Ordering::Relaxed);
        }
    }
    let shared = state.clone();
    let processing_attempt = state
        .store
        .lock()
        .map_err(failure)?
        .begin_processing(&request.id)
        .map_err(failure);
    let processing_attempt = match processing_attempt {
        Ok(attempt) => attempt,
        Err(error) => {
            state.cancel.lock().map_err(failure)?.remove(&request.id);
            return Err(error);
        }
    };
    let id = request.id.clone();
    let attempt = json!({"id":id,"filename":request.filename,"config":request.config,"source_hash":source_hash,"started_at":chrono::Utc::now().timestamp(),"engine":request.config.engine});
    let worker_cancel = cancel.clone();
    let worker_id = id.clone();
    let mut task = tokio::task::spawn_blocking(move || {
        let result =
            inference::process(app, shared.clone(), request, bytes, worker_cancel, started);
        if let Ok(store) = shared.store.lock() {
            // A timeout/cancel may have returned earlier. Do not overwrite it.
            let cancelled = shared
                .cancel
                .lock()
                .map(|active| {
                    active
                        .get(&worker_id)
                        .is_some_and(|c| c.load(Ordering::Relaxed))
                })
                .unwrap_or(true);
            let status = if cancelled {
                "interrupted"
            } else if result.is_ok() {
                "completed"
            } else {
                "failed"
            };
            if status == "completed" {
                let _ = store
                    .connection
                    .execute("DELETE FROM failures WHERE id=?1", [&worker_id]);
            }
            let _ = store.intake_status(
                &worker_id,
                status,
                result.as_ref().err().map(ToString::to_string).as_deref(),
            );
            let _ = store.finish_processing(
                &processing_attempt,
                status,
                result.as_ref().err().map(ToString::to_string).as_deref(),
            );
        }
        if let Ok(mut active) = shared.cancel.lock() {
            active.remove(&worker_id);
        }
        result
    });
    drop(admission);
    let result = loop {
        tokio::select! {
            result = &mut task => break result.map_err(failure),
            _ = tokio::time::sleep(std::time::Duration::from_millis(20)) => {
                if cancel.load(Ordering::Relaxed) || started.elapsed().as_secs() >= 60 {
                    let status = if cancel.load(Ordering::Relaxed) { "cancelled" } else { "budget_exhausted" };
                    cancel.store(true, Ordering::Relaxed);
                    let store = state.store.lock().map_err(failure)?;
                    store.intake_status(&id, "interrupted", Some("Erkennung unterbrochen; Original bleibt gespeichert.")).map_err(failure)?;
                    if let Ok(mut run) = store.load_run(&id) {
                        run.stages.push(Stage { name: "automatic_review".into(), status: status.into(), duration_ms: started.elapsed().as_millis() as u64, detail: "Letzter brauchbarer Entwurf bleibt erhalten.".into(), artifacts: vec![] });
                        store.save_run(&run).map_err(failure)?;
                        return Ok(json!({"run":run,"duplicate":false}));
                    }
                    return Err("Prüfung beendet (Abbruch oder 60 Sekunden). Der bisherige Entwurf bleibt erhalten; noch kein neuer Entwurf verfügbar.".into());
                }
            }
        }
    };
    let result = result.and_then(|inner| inner);
    if let Err(ref error) = result {
        let mut record = attempt;
        record["status"] = json!("failed");
        record["error"] = json!(error);
        record["internal_stage"] = json!("unavailable after pipeline failure");
        let store = state.store.lock().map_err(failure)?;
        store
            .record_failure(&id, chrono::Utc::now().timestamp(), &record)
            .map_err(failure)?;
        if let Ok(mut run) = store.load_run(&id) {
            run.stages.push(Stage {
                name: "automatic_review".into(),
                status: "failed".into(),
                duration_ms: started.elapsed().as_millis() as u64,
                detail: format!("{error} Letzter brauchbarer Entwurf bleibt erhalten."),
                artifacts: vec![],
            });
            store.save_run(&run).map_err(failure)?;
            return Ok(json!({"run":run,"duplicate":false}));
        }
    }
    result
}
pub fn history(state: &Arc<AppState>) -> Response<Value> {
    let store = state.store.lock().map_err(failure)?;
    Ok(
        json!({"scans":store.list_scans().map_err(failure)?,"plans":store.plans().map_err(failure)?,"intakes":store.intakes().map_err(failure)?,"batches":store.batches().map_err(failure)?,"imports":store.records(None).map_err(failure)?,"pending":store.pending().map_err(failure)?.len(),"pending_details":store.pending().map_err(failure)?,"failures":store.failures().map_err(failure)?}),
    )
}
pub fn load_scan(state: &Arc<AppState>, id: String) -> Response<PipelineRun> {
    let store = state.store.lock().map_err(failure)?;
    let mut run = store.load_run(&id).map_err(failure)?;
    if reha_core::refinement::refresh_cached_mapping(&mut run).map_err(failure)? {
        store.save_run(&run).map_err(failure)?;
    }
    Ok(run)
}
pub fn save_review(
    state: &Arc<AppState>,
    id: String,
    appointments: Vec<Appointment>,
    complete: bool,
    reviewed: bool,
    selection: Option<Vec<String>>,
    expected_revision: Option<String>,
) -> Response<PipelineRun> {
    if appointments.len() > 1500 {
        return Err("Zu viele Termine.".into());
    }
    let store = state.store.lock().map_err(failure)?;
    if !store.pending().map_err(failure)?.is_empty() {
        return Err("Unklare Schreibvorgänge zuerst abgleichen.".into());
    }
    let mut run = store.load_run(&id).map_err(failure)?;
    if expected_revision
        .as_ref()
        .is_some_and(|expected| expected != &revision(&run))
    {
        return Err("stale_revision".into());
    }
    if state.cancel.lock().map_err(failure)?.contains_key(&id) {
        return Err("Eine Erkennung bearbeitet diesen Scan. Bitte warten oder abbrechen.".into());
    }
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
pub async fn capture(app: Arc<dyn super::Platform>, source: String) -> Response<Value> {
    if !["camera", "photos"].contains(&source.as_str()) {
        return Err("Unbekannte Bildquelle.".into());
    }
    tokio::task::spawn_blocking(move || app.call(&source, json!({})))
        .await
        .map_err(failure)?
}
pub fn delete_scan(state: &Arc<AppState>, id: String) -> Response<()> {
    let _admission = state
        .lifecycle_lock
        .try_lock()
        .map_err(|_| "Eine Datenänderung läuft bereits.")?;
    let pages = state
        .store
        .lock()
        .map_err(failure)?
        .page_ids(&id)
        .map_err(failure)?;
    let is_parent = state
        .store
        .lock()
        .map_err(failure)?
        .plans()
        .map_err(failure)?
        .iter()
        .any(|p| p.id == id);
    let mut removed = if is_parent { pages } else { vec![] };
    if !removed.contains(&id) {
        removed.push(id);
    }
    if state
        .cancel
        .lock()
        .map_err(failure)?
        .keys()
        .any(|id| removed.contains(id))
    {
        return Err("Eine Verarbeitung läuft bereits. Bitte warten oder abbrechen.".into());
    }
    let store = state.store.lock().map_err(failure)?;
    store.delete_sources(&removed).map_err(failure)
}

/// Explicit photo reassignment is local. Calendar proposals still require a
/// separate review and confirmation, and never delete missing rows.
pub fn associate_recheck(state: &Arc<AppState>, id: String, previous: String) -> Response<()> {
    let store = state.store.lock().map_err(failure)?;
    store.load_run(&id).map_err(failure)?;
    let scans = store.list_scans().map_err(failure)?;
    let schedule = scans
        .iter()
        .find(|s| s.id == previous)
        .and_then(|s| s.schedule_id.as_ref())
        .ok_or("Kein früherer Kalenderimport für diesen Plan.")?;
    if scans
        .iter()
        .any(|s| s.id == id && s.schedule_id.as_ref().is_some_and(|v| v != schedule))
    {
        return Err("Das Foto ist bereits einem anderen Kalenderimport zugeordnet.".into());
    }
    // Preserve the ledger fingerprint until the user approves the calendar diff.
    store
        .connection
        .execute(
            "UPDATE scans SET schedule_id=?2 WHERE id=?1",
            [id.as_str(), schedule.as_str()],
        )
        .map_err(failure)?;
    store
        .set_setting(&format!("recheck:{id}"), &previous)
        .map_err(failure)?;
    state.proposals.lock().map_err(failure)?.clear();
    Ok(())
}

pub async fn retry_scan(
    app: Arc<dyn super::Platform>,
    state: &Arc<AppState>,
    id: String,
) -> Response<PipelineRun> {
    let intake = {
        let store = state.store.lock().map_err(failure)?;
        if store.load_run(&id).is_ok() {
            None
        } else {
            let intake = store
                .intakes()
                .map_err(failure)?
                .into_iter()
                .find(|v| v.id == id && v.status != "deleted")
                .ok_or("Aufnahme wurde gelöscht oder fehlt.")?;
            Some((
                intake,
                std::fs::read(store.source_path(&id).map_err(failure)?).map_err(failure)?,
            ))
        }
    };
    if let Some((intake, bytes)) = intake {
        let value = import_image(
            app,
            state,
            ImportRequest {
                id,
                filename: intake.filename,
                base64: STANDARD.encode(bytes),
                config: intake.config,
                force: true,
            },
        )
        .await?;
        return serde_json::from_value(value["run"].clone()).map_err(failure);
    }
    #[cfg(not(feature = "onnx"))]
    {
        let _ = (app, state, id);
        Err("Portable Erkennung nicht verfügbar.".into())
    }
    #[cfg(feature = "onnx")]
    {
        let started = std::time::Instant::now();
        let admission = state.lifecycle_lock.lock().await;
        let cancel = Arc::new(AtomicBool::new(false));
        {
            let mut active = state.cancel.lock().map_err(failure)?;
            if !active.is_empty() {
                return Err("Eine Verarbeitung läuft bereits.".into());
            }
            active.insert(id.clone(), cancel.clone());
            if app.cancelled(&id) {
                cancel.store(true, Ordering::Relaxed);
            }
        }
        drop(admission);
        let shared = state.clone();
        let scan_id = id.clone();
        let worker_cancel = cancel.clone();
        let cleanup = shared.clone();
        let cleanup_id = id.clone();
        let mut task = tokio::task::spawn_blocking(move || {
            let result = (|| {
                let cancel = worker_cancel;
                app.progress( json!({"id":scan_id,"stage":"Lokales Modell laden und Felder nachlesen","elapsed_ms":started.elapsed().as_millis() as u64,"budget_ms":60000,"draft_available":true}));
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
                        *engine = Some(
                            reha_core::ocr::OnnxEngine::load(&shared.models).map_err(failure)?,
                        );
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
                        detail: error.to_string(),
                        artifacts: vec![],
                    });
                }
                drop(engine);
                #[cfg(target_os = "ios")]
                if !cancel.load(Ordering::Relaxed) && started.elapsed().as_secs() < 60 {
                    if let Err(error) = inference::refine_vision(
                        app.as_ref(),
                        &mut run,
                        &dir,
                        &cancel,
                        started + std::time::Duration::from_secs(60),
                    ) {
                        run.stages.push(Stage {
                            name: "vision_refinement".into(),
                            status: "failed".into(),
                            duration_ms: 0,
                            detail: error.to_string(),
                            artifacts: vec![],
                        });
                    }
                }
                let store = shared.store.lock().map_err(failure)?;
                // Discard no user edits that arrived while the CPU pass was running.
                let current = store.load_run(&scan_id).map_err(failure)?;
                if cancel.load(Ordering::Relaxed) {
                    return Ok(current);
                }
                for a in &mut run.appointments {
                    if let Some(latest) = current.appointments.iter().find(|v| v.id == a.id) {
                        for field in reha_core::review::FIELDS {
                            if reha_core::review::field_confirmed(latest, field)
                                || latest.origins.get(*field).is_some_and(|o| {
                                    ["manual", "suggested"].contains(&o.kind.as_str())
                                })
                            {
                                reha_core::review::set_value(
                                    a,
                                    field,
                                    reha_core::review::value(latest, field),
                                )
                                .map_err(failure)?;
                                if let Some(origin) = latest.origins.get(*field) {
                                    a.origins.insert((*field).into(), origin.clone());
                                }
                            }
                        }
                        a.included = latest.included;
                        a.suggestions = latest.suggestions.clone();
                        a.calendar_event_id = latest.calendar_event_id.clone();
                        a.ics_exported_hash = latest.ics_exported_hash.clone();
                        a.ics_event_id = latest.ics_event_id.clone();
                        a.calendar_saved_hash = latest.calendar_saved_hash.clone();
                        for (field, assessment) in &latest.fields {
                            if reha_core::review::field_confirmed(latest, field) {
                                a.fields.insert(field.clone(), assessment.clone());
                            }
                        }
                        if a.fields == latest.fields
                            && reha_core::review::values_hash(a)
                                == reha_core::review::values_hash(latest)
                        {
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
            })();
            if let Ok(mut active) = cleanup.cancel.lock() {
                active.remove(&cleanup_id);
            }
            result
        });
        loop {
            tokio::select! {
                result = &mut task => return result.map_err(failure)?,
                _ = tokio::time::sleep(std::time::Duration::from_millis(20)) => {
                    if cancel.load(Ordering::Relaxed) || started.elapsed().as_secs() >= 60 {
                        let status = if cancel.load(Ordering::Relaxed) { "cancelled" } else { "budget_exhausted" };
                        cancel.store(true, Ordering::Relaxed);
                        let store = state.store.lock().map_err(failure)?;
                        let mut run = store.load_run(&id).map_err(failure)?;
                        run.stages.push(Stage { name:"automatic_review".into(), status:status.into(), duration_ms:started.elapsed().as_millis() as u64, detail:"Letzter brauchbarer Entwurf bleibt erhalten.".into(), artifacts:vec![] });
                        store.save_run(&run).map_err(failure)?;
                        return Ok(run);
                    }
                }
            }
        }
    }
}

pub fn revision(run: &PipelineRun) -> String {
    reha_core::hash(&serde_json::to_vec(run).expect("serializable run"))
}
