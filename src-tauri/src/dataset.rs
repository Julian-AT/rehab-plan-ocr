use crate::state::{failure, AppState, Response};
use base64::{engine::general_purpose::STANDARD, Engine};
use reha_core::contracts::*;
use serde_json::{json, Value};
use std::path::PathBuf;
use std::sync::Arc;
use tauri::State;

#[tauri::command]
pub(crate) fn evaluate_annotation(
    state: State<'_, Arc<AppState>>,
    mut annotation: reha_core::evaluation::Annotation,
    run: PipelineRun,
) -> Response<reha_core::evaluation::Metrics> {
    // Interactive evaluation only accepts the exact retained user-approved reference.
    let stored = provisional_reference(state.clone(), run.document.source_hash.clone())?;
    let saved: reha_core::evaluation::Annotation =
        serde_json::from_value(stored).map_err(failure)?;
    if saved.approval_hash.is_none()
        || reha_core::evaluation::reference_hash(&saved)
            != reha_core::evaluation::reference_hash(&annotation)
    {
        return Err("Referenz zuerst speichern und ausdrücklich freigeben.".into());
    }
    annotation = saved;
    guard_reference(&state, &annotation, true)?;
    if !annotation
        .document_hashes
        .contains(&run.document.source_hash)
    {
        return Err("Referenz und Vorhersage gehören nicht zum selben Dokument.".into());
    }
    reha_core::evaluation::compare_run(&annotation, &run, false).map_err(failure)
}
#[tauri::command]
pub(crate) fn save_annotation(
    state: State<'_, Arc<AppState>>,
    mut annotation: reha_core::evaluation::Annotation,
) -> Response<()> {
    #[cfg(target_os = "ios")]
    {
        let _ = (state, annotation);
        Err("Referenzen werden im Desktoplabor verwaltet.".into())
    }
    #[cfg(not(target_os = "ios"))]
    {
        if annotation.schema_version != 2
            || annotation.day_id.is_empty()
            || !annotation
                .day_id
                .chars()
                .all(|c| c.is_ascii_alphanumeric() || c == '-' || c == '_')
        {
            return Err("Ungültige Tages-ID.".into());
        }
        reha_core::evaluation::validate_reference(&annotation, annotation.verified)
            .map_err(failure)?;
        annotation.content_hash = Some(reha_core::evaluation::reference_hash(&annotation));
        annotation.approval_hash = if annotation.verified {
            annotation.content_hash.clone()
        } else {
            None
        };
        annotation.reviewed_at = if annotation.verified {
            Some(chrono::Utc::now().to_rfc3339())
        } else {
            None
        };
        if annotation.verified
            && (!annotation.uncertainty_notes.is_empty() || annotation.reviewed_at.is_none())
        {
            return Err("Offene Fragen vor der Verifikation auflösen.".into());
        }
        guard_reference(&state, &annotation, annotation.verified)?;
        let dir = root(&state)?.join("labels");
        std::fs::create_dir_all(&dir).map_err(failure)?;
        if annotation.document_hashes.len() != 1 {
            return Err("Eine Referenz pro Originalfoto speichern.".into());
        }
        let hash = &annotation.document_hashes[0];
        if hash.len() != 64 || !hash.chars().all(|c| c.is_ascii_hexdigit()) {
            return Err("Ungültiger Quellhash.".into());
        }
        std::fs::create_dir_all(dir.join("provisional")).map_err(failure)?;
        let mut path = dir.join("provisional").join(format!("{hash}.json"));
        // Frozen day grouping must not be silently changed by the annotation editor.
        let split = dir.parent().unwrap().join("split.json");
        if split.exists() {
            let value: Value =
                serde_json::from_slice(&std::fs::read(split).map_err(failure)?).map_err(failure)?;
            if value["grouping_verified"] == false && annotation.document_hashes.len() == 1 {
                let hash = &annotation.document_hashes[0];
                if hash.len() != 64 || !hash.chars().all(|c| c.is_ascii_hexdigit()) {
                    return Err("Ungültiger Quellhash.".into());
                }
                // Related pages have the same provisional day ID. Keep their
                // individual corrections instead of overwriting a sibling.
                let provisional = dir.join("provisional");
                std::fs::create_dir_all(&provisional).map_err(failure)?;
                path = provisional.join(format!("{hash}.json"));
            }
            if let Some(expected) = value["days"][&annotation.day_id]["split"].as_str() {
                if expected != annotation.split {
                    return Err("Datensatzgruppe ist bereits eingefroren.".into());
                }
            }
        }
        let temporary = path.with_extension("json.part");
        std::fs::write(
            &temporary,
            serde_json::to_vec_pretty(&annotation).map_err(failure)?,
        )
        .map_err(failure)?;
        std::fs::rename(temporary, path).map_err(failure)?;
        Ok(())
    }
}

pub(crate) fn root(state: &AppState) -> Response<PathBuf> {
    #[cfg(target_os = "ios")]
    return Err("Das Forschungslabor ist nur auf dem Desktop verfügbar.".into());
    #[cfg(not(target_os = "ios"))]
    {
        let configured = state
            .store
            .lock()
            .map_err(failure)?
            .setting("dataset_root")
            .map_err(failure)?;
        Ok(configured
            .map(PathBuf::from)
            .unwrap_or_else(|| PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../data/private")))
    }
}
pub(crate) fn guard_reference(
    state: &AppState,
    annotation: &reha_core::evaluation::Annotation,
    evaluation: bool,
) -> Response<()> {
    let split = root(state)?.join("split.json");
    if split.exists() {
        let frozen: Value =
            serde_json::from_slice(&std::fs::read(split).map_err(failure)?).map_err(failure)?;
        if evaluation && (frozen["schema_version"] != 3 || frozen["grouping_verified"] != true) {
            return Err("Seitengruppen zuerst verifizieren; vorläufige Referenzen sind kein Genauigkeitsbenchmark.".into());
        }
        if evaluation {
            let references = read_references(&root(state)?)?;
            if frozen["relationships_hash"].as_str()
                != Some(&reha_core::evaluation::relationships_hash(&references))
            {
                return Err("Seitengruppen wurden nach dem Einfrieren verändert. Neue Datensatzversion vor der Bewertung anlegen.".into());
            }
        }
        for (day, group) in frozen["days"]
            .as_object()
            .ok_or("Ungültige Datensatzgruppen.")?
        {
            let hashes = group["document_hashes"]
                .as_array()
                .ok_or("Quellen fehlen.")?;
            if hashes.iter().any(|h| {
                annotation
                    .document_hashes
                    .iter()
                    .any(|a| h.as_str() == Some(a))
            }) {
                if day != &annotation.day_id || group["split"].as_str() != Some(&annotation.split) {
                    return Err("Tages-ID oder Gruppe widerspricht dem eingefrorenen Split.".into());
                }
                if evaluation && group["split"] == "holdout" {
                    return Err("Finaler Holdout ist im interaktiven Labor gesperrt.".into());
                }
            }
        }
    } else if evaluation {
        return Err("Bestätigte Entwicklungsgruppen fehlen.".into());
    }
    Ok(())
}
fn read_references(
    directory: &std::path::Path,
) -> Response<Vec<reha_core::evaluation::Annotation>> {
    let data = inventory(directory)?;
    data["entries"]
        .as_array()
        .ok_or("Inventar fehlt.")?
        .iter()
        .map(|e| {
            let hash = e["sha256"]
                .as_str()
                .filter(|h| h.len() == 64 && h.chars().all(|c| c.is_ascii_hexdigit()))
                .ok_or("Ungültiger Quellhash.")?;
            serde_json::from_slice(
                &std::fs::read(
                    directory
                        .join("labels/provisional")
                        .join(format!("{hash}.json")),
                )
                .map_err(failure)?,
            )
            .map_err(failure)
        })
        .collect()
}
#[tauri::command]
pub(crate) fn freeze_reference_groups(state: State<'_, Arc<AppState>>) -> Response<Value> {
    let directory = root(&state)?;
    let mut references = read_references(&directory)?;
    let groups = reha_core::evaluation::development_groups(&references).map_err(failure)?;
    if let Ok(bytes) = std::fs::read(directory.join("split.json")) {
        let old: Value = serde_json::from_slice(&bytes).map_err(failure)?;
        if old["grouping_verified"] == true {
            if old != groups {
                return Err("Eingefrorene Gruppierung verändert: bisherigen Versuch archivieren und eine neue Datensatzversion anlegen.".into());
            }
            return Ok(old);
        }
    }
    // Update references before publishing a verified split: an interrupted write
    // remains unusable for training and can be retried safely.
    for reference in &mut references {
        reference.day_id = groups["days"]
            .as_object()
            .unwrap()
            .iter()
            .find(|(_, g)| {
                g["document_hashes"]
                    .as_array()
                    .unwrap()
                    .contains(&json!(reference.document_hashes[0]))
            })
            .ok_or("Quelle fehlt in Gruppen.")?
            .0
            .clone();
        reference.verified = false;
        reference.reviewed_at = None;
        reference.approval_hash = None;
        reference.content_hash = None;
        let path = directory
            .join("labels/provisional")
            .join(format!("{}.json", reference.document_hashes[0]));
        let temp = path.with_extension("json.part");
        std::fs::write(
            &temp,
            serde_json::to_vec_pretty(reference).map_err(failure)?,
        )
        .map_err(failure)?;
        std::fs::rename(temp, path).map_err(failure)?;
    }
    let temp = directory.join("split.json.part");
    std::fs::write(&temp, serde_json::to_vec_pretty(&groups).map_err(failure)?).map_err(failure)?;
    std::fs::rename(temp, directory.join("split.json")).map_err(failure)?;
    Ok(groups)
}
fn inventory(root: &std::path::Path) -> Response<Value> {
    if !root.join("inventory.json").exists() {
        return Ok(json!({"entries":[]}));
    }
    serde_json::from_slice(&std::fs::read(root.join("inventory.json")).map_err(failure)?)
        .map_err(failure)
}
#[tauri::command]
pub(crate) fn dataset(state: State<'_, Arc<AppState>>, path: Option<String>) -> Response<Value> {
    if let Some(path) = path {
        let directory = PathBuf::from(path).canonicalize().map_err(failure)?;
        if !directory.is_dir() || !directory.join("inventory.json").is_file() {
            return Err("Privates Verzeichnis mit inventory.json auswählen.".into());
        }
        state
            .store
            .lock()
            .map_err(failure)?
            .set_setting(
                "dataset_root",
                directory.to_str().ok_or("Ungültiger Pfad.")?,
            )
            .map_err(failure)?;
    }
    let directory = root(&state)?;
    let data = inventory(&directory)?;
    let split: Value = std::fs::read(directory.join("split.json"))
        .ok()
        .map(|bytes| serde_json::from_slice(&bytes))
        .transpose()
        .map_err(failure)?
        .unwrap_or(json!({"days":{}}));
    let entries=data["entries"].as_array().ok_or("Ungültiges Inventar.")?.iter().map(|entry|{
        let day=split["days"].as_object().and_then(|days|days.iter().find(|(_,group)|group["document_hashes"].as_array().is_some_and(|hashes|hashes.contains(&entry["sha256"]))));
        let reference: Option<reha_core::evaluation::Annotation> = entry["sha256"].as_str().filter(|h|h.len()==64 && h.chars().all(|c|c.is_ascii_hexdigit())).and_then(|h|std::fs::read(directory.join("labels/provisional").join(format!("{h}.json"))).ok()).and_then(|b|serde_json::from_slice(&b).ok());
        let approved=reference.as_ref().is_some_and(|r|r.verified && r.approval_hash.as_ref()==Some(&reha_core::evaluation::reference_hash(r)));
        let reviewed=reference.as_ref().map(|r|r.appointments.iter().filter(|a|["date","start","end","title","location","therapist","notes"].iter().all(|f|a.fields.get(*f).is_some_and(|f|f.confirmed_at.is_some()))).count()).unwrap_or(0);
        json!({"verified":approved,"reviewed_rows":reviewed,"reference_rows":reference.as_ref().map(|r|r.appointments.len()),"filename":entry["filename"],"sha256":entry["sha256"],"bytes":entry["bytes"],"day_id":day.map(|(id,_)|id),"split":day.map(|(_,group)|&group["split"])})
    }).collect::<Vec<_>>();
    Ok(
        json!({"root":directory,"entries":entries,"split_frozen":split["schema_version"]==3 && split["grouping_verified"]==true}),
    )
}
#[tauri::command]
pub(crate) fn dataset_image(state: State<'_, Arc<AppState>>, hash: String) -> Response<Value> {
    let directory = root(&state)?;
    let data = inventory(&directory)?;
    let entry = data["entries"]
        .as_array()
        .ok_or("Inventar fehlt.")?
        .iter()
        .find(|e| e["sha256"].as_str() == Some(&hash))
        .ok_or("Bild nicht im Inventar.")?;
    let filename = entry["filename"].as_str().ok_or("Dateiname fehlt.")?;
    if std::path::Path::new(filename)
        .file_name()
        .and_then(|n| n.to_str())
        != Some(filename)
    {
        return Err("Ungültiger Bildpfad.".into());
    }
    let raw = directory.join("raw").canonicalize().map_err(failure)?;
    let path = raw.join(filename).canonicalize().map_err(failure)?;
    if path.parent() != Some(raw.as_path())
        || path.metadata().map_err(failure)?.len() > 40 * 1024 * 1024
    {
        return Err("Bildpfad oder Größe ungültig.".into());
    }
    let bytes = std::fs::read(path).map_err(failure)?;
    if reha_core::hash(&bytes) != hash {
        return Err("Quellbild stimmt nicht mit der inventarisierten Prüfsumme überein.".into());
    }
    Ok(json!({"filename":filename,"base64":STANDARD.encode(bytes)}))
}
#[tauri::command]
pub(crate) fn save_lab_run(
    state: State<'_, Arc<AppState>>,
    batch: String,
    id: String,
) -> Response<String> {
    uuid::Uuid::parse_str(&batch).map_err(failure)?;
    let root = root(&state)?;
    let output = if root == PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../data/private") {
        PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../artifacts/private/lab")
    } else {
        root.join("experiments")
    };
    let store = state.store.lock().map_err(failure)?;
    let run = store.load_run(&id).map_err(failure)?;
    let destination = output.join(&batch).join(&id);
    std::fs::create_dir_all(&destination).map_err(failure)?;
    for entry in std::fs::read_dir(store.scan_dir(&id).map_err(failure)?).map_err(failure)? {
        let entry = entry.map_err(failure)?;
        if entry.file_type().map_err(failure)?.is_file() {
            std::fs::copy(entry.path(), destination.join(entry.file_name())).map_err(failure)?;
        }
    }
    std::fs::write(
        destination.join("run.json"),
        serde_json::to_vec_pretty(&run).map_err(failure)?,
    )
    .map_err(failure)?;
    let manifest = json!({"schema_version":1,"batch_id":batch,"run_id":id,"app_version":env!("CARGO_PKG_VERSION"),"platform":std::env::consts::OS,"source_sha256":run.document.source_hash,"config":run.config,"models":run.model_manifest,"run_sha256":reha_core::hash(&std::fs::read(destination.join("run.json")).map_err(failure)?),"binary_sha256":reha_core::hash(&std::fs::read(std::env::current_exe().map_err(failure)?).map_err(failure)?),"verified_accuracy":false});
    std::fs::write(
        destination.join("manifest.json"),
        serde_json::to_vec_pretty(&manifest).map_err(failure)?,
    )
    .map_err(failure)?;
    Ok(destination.to_string_lossy().to_string())
}

#[tauri::command]
pub(crate) fn provisional_reference(
    state: State<'_, Arc<AppState>>,
    hash: String,
) -> Response<Value> {
    if hash.len() != 64 || !hash.chars().all(|c| c.is_ascii_hexdigit()) {
        return Err("Ungültige Quellkennung.".into());
    }
    let directory = root(&state)?;
    let path = directory
        .join("labels/provisional")
        .join(format!("{hash}.json"));
    let value: Value =
        serde_json::from_slice(&std::fs::read(path).map_err(failure)?).map_err(failure)?;
    if !value["document_hashes"]
        .as_array()
        .is_some_and(|hashes| hashes.contains(&json!(hash)))
    {
        return Err("Quelle und Referenz stimmen nicht überein.".into());
    }
    Ok(value)
}
