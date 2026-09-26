mod calendar;
mod dataset;
mod inference;
mod scan;
mod settings;
mod state;

use reha_core::store::Store;
use state::AppState;
use std::{
    collections::HashMap,
    path::PathBuf,
    sync::{Arc, Mutex},
};
use tauri::Manager;

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .plugin(tauri_plugin_reha_calendar::init())
        .setup(|app| {
            #[cfg(not(target_os = "ios"))]
            let root = app.path().app_local_data_dir()?;
            #[cfg(target_os = "ios")]
            let root = {
                let storage = tauri_plugin_reha_calendar::call(
                    app.handle(),
                    "protectStorage",
                    serde_json::json!({}),
                )
                .map_err(std::io::Error::other)?;
                PathBuf::from(storage["path"].as_str().ok_or_else(|| {
                    std::io::Error::other("Native storage did not return a directory")
                })?)
            };
            let store = Store::open(&root)?;
            store.cleanup(chrono::Utc::now().timestamp())?;
            let bundled = app.path().resource_dir()?.join("models");
            let models = if bundled.join("manifest.json").exists() {
                bundled
            } else {
                PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../models/private/small")
            };
            app.manage(Arc::new(AppState {
                store: Mutex::new(store),
                models,
                #[cfg(any(feature = "desktop-onnx", feature = "ios-onnx"))]
                engine: Mutex::new(None),
                cancel: Mutex::new(HashMap::new()),
                proposals: Mutex::new(HashMap::new()),
                calendar_lock: tokio::sync::Mutex::new(()),
            }));
            Ok(())
        })
        .invoke_handler(tauri::generate_handler![
            scan::import_image,
            scan::cancel_processing,
            scan::history,
            scan::load_scan,
            scan::source_bytes,
            scan::scan_image,
            scan::save_review,
            calendar::set_page_group,
            calendar::page_group,
            calendar::export_ics,
            calendar::calendars,
            scan::capture,
            calendar::share_export,
            calendar::prepare_calendar,
            calendar::resolve_proposal,
            calendar::approve_calendar,
            calendar::reconcile_calendar,
            calendar::resolve_pending_write,
            scan::delete_scan,
            settings::erase_all,
            settings::maintenance,
            settings::settings,
            settings::engine_status,
            dataset::save_annotation,
            dataset::evaluate_annotation,
            dataset::dataset,
            dataset::dataset_image,
            dataset::save_lab_run
        ])
        .run(tauri::generate_context!())
        .expect("Unable to start local application");
}
