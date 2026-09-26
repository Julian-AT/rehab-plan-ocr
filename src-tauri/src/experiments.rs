//! Desktop-only opt-in experiments. All documents and outputs remain in scan retention.
use crate::state::{failure, AppState, Response};
use serde_json::Value;
use std::sync::Arc;
use tauri::State;

#[tauri::command]
pub(crate) async fn compare_regions(
    state: State<'_, Arc<AppState>>,
    id: String,
) -> Response<Value> {
    #[cfg(target_os = "ios")]
    {
        let _ = (state, id);
        Err("Modellvergleiche sind im Desktoplabor verfügbar.".into())
    }
    #[cfg(not(target_os = "ios"))]
    {
        use std::{
            sync::atomic::{AtomicBool, Ordering},
            time::Duration,
        };
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
            let dir = {
                let store = shared.store.lock().map_err(failure)?;
                let run = store.load_run(&scan_id).map_err(failure)?;
                let dir = store.scan_dir(&scan_id).map_err(failure)?;
                std::fs::write(dir.join("run.json"), serde_json::to_vec(&run).map_err(failure)?)
                    .map_err(failure)?;
                dir
            };
            let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("..");
            if !root.join("models/private/experiments/candidates.json").is_file() {
                return Err("Experimentmodelle zuerst gemäß experiments/vlm/README.md prüfen und einrichten.".into());
            }
            let output = dir.join("experiments").join(uuid::Uuid::new_v4().to_string());
            let stop = dir.join("stop-experiment");
            let _ = std::fs::remove_file(&stop);
            let mut child = std::process::Command::new("python3")
                .arg(root.join("scripts/compare-regions.py"))
                .arg(dir.join("run.json"))
                .arg(&output)
                .arg("--cancel-file")
                .arg(&stop)
                .stdout(std::process::Stdio::null())
                .stderr(std::process::Stdio::null())
                .spawn().map_err(failure)?;
            let started = std::time::Instant::now();
            loop {
                if cancel.load(Ordering::Relaxed) || started.elapsed() > Duration::from_secs(130) {
                    std::fs::write(&stop, b"cancel").map_err(failure)?;
                }
                if let Some(status) = child.try_wait().map_err(failure)? {
                    if !status.success() {
                        return Err("Modellvergleich fehlgeschlagen; vorhandener Entwurf bleibt erhalten.".into());
                    }
                    break;
                }
                if started.elapsed() > Duration::from_secs(140) {
                    let _ = child.kill();
                    let _ = child.wait();
                    return Err("Modellvergleich beendet: Zeitlimit.".into());
                }
                std::thread::sleep(Duration::from_millis(50));
            }
            serde_json::from_slice(&std::fs::read(output.join("comparison.json")).map_err(failure)?)
                .map_err(failure)
        }).await.map_err(failure);
        state.cancel.lock().map_err(failure)?.remove(&id);
        result.and_then(|v| v)
    }
}
