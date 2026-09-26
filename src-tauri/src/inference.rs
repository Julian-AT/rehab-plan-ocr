//! Native adapters around the shared image-to-appointment pipeline.
use crate::state::{AppState, Response};
use reha_core::contracts::PipelineConfig;
use serde::Deserialize;
use serde_json::Value;
use std::sync::{atomic::AtomicBool, Arc};

#[derive(Deserialize)]
pub(crate) struct ImportRequest {
    pub id: String,
    pub filename: String,
    pub base64: String,
    pub config: PipelineConfig,
    #[serde(default)]
    pub force: bool,
}

#[cfg(any(feature = "desktop-onnx", feature = "ios-onnx"))]
pub(crate) fn process(
    app: tauri::AppHandle,
    state: Arc<AppState>,
    request: ImportRequest,
    bytes: Vec<u8>,
    cancel: Arc<AtomicBool>,
) -> Response<Value> {
    use crate::state::failure;
    use base64::{engine::general_purpose::STANDARD, Engine};
    use reha_core::{
        contracts::*,
        pipeline::{self, RecognitionOutput, ScanInput},
    };
    use serde_json::json;
    use std::{sync::atomic::Ordering, time::Instant};

    let started = Instant::now();
    let directory = state
        .store
        .lock()
        .map_err(failure)?
        .scan_dir(&request.id)
        .map_err(failure)?;
    let result = (|| {
        let decoded =
            if bytes.starts_with(&[0xff, 0xd8, 0xff]) || bytes.starts_with(b"\x89PNG\r\n\x1a\n") {
                bytes.clone()
            } else {
                let response = tauri_plugin_reha_calendar::call(
                    &app,
                    "decodePhoto",
                    json!({ "base64": request.base64 }),
                )?;
                STANDARD
                    .decode(
                        response["base64"]
                            .as_str()
                            .ok_or("Unsupported image format.")?,
                    )
                    .map_err(failure)?
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
            let response = tauri_plugin_reha_calendar::call(
                &app,
                "recognize",
                json!({
                    "base64": STANDARD.encode(std::fs::read(directory.join("page.png")).map_err(failure)?)
                }),
            )?;
            let output = RecognitionOutput {
                engine: "Apple Vision".into(),
                manifest: response["manifest"].clone(),
                regions: serde_json::from_value(response["regions"].clone()).map_err(failure)?,
                observations: serde_json::from_value(response["observations"].clone())
                    .map_err(failure)?,
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
                        duration_ms: response["duration_ms"].as_u64().unwrap_or(0),
                        detail: "Apple Vision accurate recognition; language correction disabled."
                            .into(),
                        artifacts: vec![],
                    },
                ],
                cache_used: false,
            };
            pipeline::assemble(prepared, output, &cancel).map_err(failure)?
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
            if !cached {
                *engine = None;
                *engine = Some(reha_core::ocr::OnnxEngine::load(&models).map_err(failure)?);
            }
            load_ms = loading.elapsed().as_millis() as u64;
            pipeline::run(
                engine.as_mut().ok_or("Model session unavailable.")?,
                ScanInput {
                    bytes: &decoded,
                    filename: &request.filename,
                    id: &request.id,
                    now: chrono::Utc::now().timestamp(),
                    config: request.config,
                    dir: &directory,
                },
                &cancel,
                cached,
            )
            .map_err(failure)?
        };
        if bytes != decoded {
            std::fs::write(directory.join("source.bin"), &bytes).map_err(failure)?;
            run.document.source_hash = reha_core::hash(&bytes);
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
        if cancel.load(Ordering::Relaxed) {
            return Err("Processing cancelled.".into());
        }
        state
            .store
            .lock()
            .map_err(failure)?
            .save_run(&run)
            .map_err(failure)?;
        Ok(json!({ "run": run, "duplicate": false }))
    })();
    if result.is_err() {
        let _ = std::fs::remove_dir_all(directory);
    }
    result
}

#[cfg(not(any(feature = "desktop-onnx", feature = "ios-onnx")))]
pub(crate) fn process(
    _: tauri::AppHandle,
    _: Arc<AppState>,
    _: ImportRequest,
    _: Vec<u8>,
    _: Arc<AtomicBool>,
) -> Response<Value> {
    Err("This build has no portable inference runtime.".into())
}
