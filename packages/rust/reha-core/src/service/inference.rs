use crate as reha_core;
// Native adapters around the shared image-to-appointment pipeline.
use crate::service::{AppState, Response};
use reha_core::contracts::PipelineConfig;
use serde::Deserialize;
use serde_json::Value;
use std::sync::{atomic::AtomicBool, Arc};

#[derive(Deserialize)]
pub struct ImportRequest {
    pub id: String,
    pub filename: String,
    pub base64: String,
    pub config: PipelineConfig,
    #[serde(default)]
    pub force: bool,
}

#[cfg(feature = "onnx")]
pub fn process(
    app: Arc<dyn super::Platform>,
    state: Arc<AppState>,
    request: ImportRequest,
    bytes: Vec<u8>,
    cancel: Arc<AtomicBool>,
    started: std::time::Instant,
) -> Response<Value> {
    use crate::service::{domain_failure, failure};
    use reha_core::{
        contracts::*,
        pipeline::{self, RecognitionOutput, ScanInput},
    };
    use serde_json::json;
    use std::time::Instant;

    let source_hash = reha_core::hash(&bytes);
    let directly_decodable = cfg!(target_os = "macos")
        || bytes.starts_with(&[0xff, 0xd8, 0xff])
        || bytes.starts_with(b"\x89PNG\r\n\x1a\n");
    // Capture the previous review before publishing a draft under the new ID.
    let previous = {
        let store = state.store.lock().map_err(failure)?;
        store
            .identical(&source_hash)
            .map_err(failure)?
            .and_then(|id| store.load_run(&id).ok())
    };
    let last_notification = std::sync::Mutex::new(None::<std::time::Instant>);
    let draft_saved = AtomicBool::new(false);
    let progress = |stage: &str, run: Option<&PipelineRun>| {
        if let Some(run) = run.filter(|_| !cancel.load(std::sync::atomic::Ordering::Relaxed)) {
            let mut draft = run.clone();
            draft.document.source_hash = source_hash.clone();
            let preserved = previous
                .as_ref()
                .map(|old| reha_core::refinement::preserve_review(old, &mut draft))
                .transpose()
                .is_ok();
            if let Ok(store) = state.store.lock() {
                // Check under the same lock as the deadline's retained-draft save.
                if preserved && !cancel.load(std::sync::atomic::Ordering::Relaxed) {
                    // The shared decoder retains original source bytes, including macOS HEIC.
                    // Native conversions must restore the actual input photo.
                    let source_retained = directly_decodable
                        || store.scan_dir(&request.id).ok().is_some_and(|dir| {
                            std::fs::write(dir.join("source.bin"), &bytes).is_ok()
                        });
                    if source_retained && store.save_run(&draft).is_ok() {
                        draft_saved.store(true, std::sync::atomic::Ordering::Relaxed);
                    }
                }
            }
        }
        let mut last = last_notification.lock().unwrap_or_else(|p| p.into_inner());
        if last.is_some_and(|time| time.elapsed() < std::time::Duration::from_millis(100)) {
            return;
        }
        *last = Some(std::time::Instant::now());
        app.progress( json!({"id": request.id, "stage": stage, "elapsed_ms": started.elapsed().as_millis() as u64, "budget_ms": 60000, "draft_available": draft_saved.load(std::sync::atomic::Ordering::Relaxed)}));
    };
    progress("Foto laden", None);

    let directory = state
        .store
        .lock()
        .map_err(failure)?
        .scan_dir(&request.id)
        .map_err(failure)?;
    let result = (|| {
        let decoded = if directly_decodable {
            std::borrow::Cow::Borrowed(bytes.as_slice())
        } else {
            std::borrow::Cow::Owned(app.decode_photo(&bytes)?)
        };
        let mut load_ms = 0;
        let mut cached = false;
        let mut run = if request.config.engine == "apple-vision" {
            let prepared = pipeline::prepare(
                &decoded,
                &request.filename,
                &request.id,
                chrono::Utc::now().timestamp(),
                &request.config,
                &directory,
            )
            .map_err(failure)?;
            let response = app.recognize_text(super::text_recognition::Request {
                image: std::fs::read(directory.join("page.png")).map_err(failure)?,
                budget_ms: super::text_recognition::MAXIMUM_BUDGET_MS,
            })?;
            let output = RecognitionOutput {
                engine: "Apple Vision".into(),
                manifest: response.manifest,
                regions: response.regions,
                observations: response.observations,
                stages: vec![
                    Stage {
                        name: "detection".into(),
                        status: "unavailable".into(),
                        duration_ms: 0,
                        detail: "Vision exposes combined detection and recognition only.".into(),
                        artifacts: vec![],
                    },
                    Stage {
                        name: "recognition".into(),
                        status: "complete".into(),
                        duration_ms: response.duration_ms,
                        detail: "Apple Vision accurate recognition; language correction disabled."
                            .into(),
                        artifacts: vec![],
                    },
                ],
                cache_used: false,
            };
            pipeline::assemble(&prepared, output, &cancel).map_err(failure)?
        } else {
            let tier = request
                .config
                .engine
                .strip_prefix("portable-")
                .ok_or("Unknown engine.")?;
            if !["small", "tiny", "medium"].contains(&tier) {
                return Err("Unknown model tier.".into());
            }
            let models = if tier == "small" {
                state.models.clone()
            } else {
                state
                    .models
                    .parent()
                    .ok_or("Missing model directory.")?
                    .join(tier)
            };
            let mut engine = state.engine.lock().map_err(failure)?;
            cached = engine
                .as_ref()
                .is_some_and(|engine| engine.name == format!("PP-OCRv6_{tier}"));
            let loading = Instant::now();
            progress("Lokales Modell laden", None);
            if !cached {
                *engine = None;
                *engine = Some(reha_core::ocr::OnnxEngine::load(&models).map_err(failure)?);
            }
            load_ms = loading.elapsed().as_millis() as u64;
            pipeline::run_with_progress(
                engine.as_mut().ok_or("Model session unavailable.")?,
                ScanInput {
                    bytes: &decoded,
                    filename: &request.filename,
                    id: &request.id,
                    now: chrono::Utc::now().timestamp(),
                    config: request.config.clone(),
                    dir: &directory,
                    deadline: started + std::time::Duration::from_secs(60),
                },
                &cancel,
                cached,
                &progress,
            )
            .map_err(failure)?
        };
        // Retain a useful first draft before the second independent local reader.
        progress("Ersten Entwurf sichern", Some(&run));
        #[cfg(target_os = "ios")]
        if !cancel.load(std::sync::atomic::Ordering::Relaxed) && started.elapsed().as_secs() < 55 {
            let refinement = refine_vision(
                app.as_ref(),
                &mut run,
                &directory,
                &cancel,
                started + std::time::Duration::from_secs(55),
            );
            if refinement.is_err() {
                run.stages.push(Stage {
                    name: "vision_refinement".into(),
                    status: "failed".into(),
                    duration_ms: 0,
                    detail: "Nachprüfung nicht abgeschlossen. Der erste Entwurf bleibt erhalten."
                        .into(),
                    artifacts: vec![],
                });
            }
        }
        if cancel.load(std::sync::atomic::Ordering::Relaxed) {
            let saved = state
                .store
                .lock()
                .map_err(failure)?
                .load_run(&request.id)
                .map_err(domain_failure)?;
            return Ok(json!({"run":saved,"duplicate":false}));
        }
        if !directly_decodable {
            std::fs::write(directory.join("source.bin"), &bytes).map_err(failure)?;
            run.document.source_hash = source_hash.clone();
        }
        if let Some(previous) = &previous {
            reha_core::refinement::preserve_review(previous, &mut run).map_err(failure)?;
        }
        let vision = run.engine == "Apple Vision";
        run.stages.insert(
            0,
            Stage {
                name: "model_load".into(),
                status: if vision { "unavailable" } else { "complete" }.into(),
                duration_ms: load_ms,
                detail: if vision {
                    "Vision manages model loading; separate timing unavailable."
                } else if cached {
                    "Reused CPU sessions."
                } else {
                    "Verified pinned model hashes; loaded CPU sessions."
                }
                .into(),
                artifacts: vec![],
            },
        );
        run.total_ms = started.elapsed().as_millis() as u64;
        {
            let store = state.store.lock().map_err(failure)?;
            let prefs: Value = store
                .setting("preferences")
                .map_err(failure)?
                .and_then(|s| serde_json::from_str(&s).ok())
                .unwrap_or_default();
            let defaults = serde_json::from_value::<Vec<CompletionDefault>>(
                prefs["completion_defaults"].clone(),
            )
            .unwrap_or_default();
            reha_core::review::suggest(&mut run, &defaults, &store.records(None).map_err(failure)?);
        }
        let store = state.store.lock().map_err(failure)?;
        if cancel.load(std::sync::atomic::Ordering::Relaxed) {
            return Ok(
                json!({"run":store.load_run(&request.id).map_err(domain_failure)?,"duplicate":false}),
            );
        }
        store.save_run(&run).map_err(failure)?;
        Ok(json!({ "run": run, "duplicate": false }))
    })();
    result
}

#[cfg(not(feature = "onnx"))]
pub fn process(
    _: Arc<dyn super::Platform>,
    _: Arc<AppState>,
    _: ImportRequest,
    _: Vec<u8>,
    _: Arc<AtomicBool>,
    _: std::time::Instant,
) -> Response<Value> {
    Err("This build has no portable inference runtime.".into())
}

/// Shared bounded Vision pass for initial processing and explicit field retries.
#[cfg(target_os = "ios")]
pub(super) fn refine_vision(
    app: &dyn super::Platform,
    run: &mut crate::contracts::PipelineRun,
    directory: &std::path::Path,
    cancel: &AtomicBool,
    deadline: std::time::Instant,
) -> crate::Result<()> {
    let first_stage = run.stages.len();
    let result = crate::refinement::refine_with_reader(
        run,
        directory,
        cancel,
        deadline,
        None,
        &mut |crop, _, flag, _, _| {
            if flag.load(std::sync::atomic::Ordering::Relaxed)
                || std::time::Instant::now() >= deadline
            {
                return Err(crate::Error::Invalid(
                    "Nachprüfung abgebrochen oder Zeitbudget erschöpft.".into(),
                ));
            }
            let mut png = std::io::Cursor::new(Vec::new());
            image::DynamicImage::ImageRgb8(crop.clone())
                .write_to(&mut png, image::ImageFormat::Png)?;
            let response = app
                .recognize_text(super::text_recognition::Request {
                    image: png.into_inner(),
                    budget_ms: deadline
                        .saturating_duration_since(std::time::Instant::now())
                        .as_millis() as u64,
                })
                .map_err(|error| crate::Error::Invalid(error.to_string()))?;
            Ok((response.regions, response.observations, vec![]))
        },
    );
    for stage in &mut run.stages[first_stage..] {
        if stage.name == "selective_reread" {
            stage.name = "vision_refinement".into();
        }
    }
    result
}
