use crate as reha_core;
use crate::service::{failure, Response};
use base64::{engine::general_purpose::STANDARD, Engine};
use reha_core::contracts::*;
use serde_json::{json, Value};
use std::path::PathBuf;
/// Local reference tools share the same validation and frozen groups as the former lab.
/// The directory is explicit; no settings or calendar store is opened.
struct ReferenceLibrary {
    pub directory: PathBuf,
}
impl ReferenceLibrary {
    fn open(directory: &std::path::Path) -> Response<Self> {
        let directory = directory.canonicalize().map_err(failure)?;
        if !directory.join("inventory.json").is_file() {
            return Err("Inventar fehlt.".into());
        }
        for relative in [
            "inventory.json",
            "split.json",
            "labels",
            "labels/provisional",
            "raw",
            "experiments",
            ".reference-lock.sqlite3",
        ] {
            checked_path(&directory, std::path::Path::new(relative))?;
        }
        Ok(Self { directory })
    }
}

fn evaluate_annotation(
    state: &ReferenceLibrary,
    mut annotation: reha_core::evaluation::Annotation,
    run: PipelineRun,
) -> Response<reha_core::evaluation::Metrics> {
    // Interactive evaluation only accepts the exact retained user-approved reference.
    let stored = provisional_reference(state, run.document.source_hash.clone())?;
    let saved: reha_core::evaluation::Annotation =
        serde_json::from_value(stored).map_err(failure)?;
    if saved.approval_hash.is_none()
        || reha_core::evaluation::reference_hash(&saved)
            != reha_core::evaluation::reference_hash(&annotation)
    {
        return Err("Referenz zuerst speichern und ausdrücklich freigeben.".into());
    }
    annotation = saved;
    guard_reference(state, &annotation, true)?;
    if !annotation
        .document_hashes
        .contains(&run.document.source_hash)
    {
        return Err("Referenz und Vorhersage gehören nicht zum selben Dokument.".into());
    }
    reha_core::evaluation::compare_run(&annotation, &run, false).map_err(failure)
}
fn save_annotation(
    state: &ReferenceLibrary,
    mut annotation: reha_core::evaluation::Annotation,
) -> Response<()> {
    if annotation.schema_version != 2
        || annotation.day_id.is_empty()
        || !annotation
            .day_id
            .chars()
            .all(|c| c.is_ascii_alphanumeric() || c == '-' || c == '_')
    {
        return Err("Ungültige Tages-ID.".into());
    }
    reha_core::evaluation::validate_reference(&annotation, annotation.verified).map_err(failure)?;
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
    guard_reference(state, &annotation, annotation.verified)?;
    for hash in &annotation.document_hashes {
        dataset_image(state, hash.clone())?;
    }
    let dir = root(state)?.join("labels");
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
    let temporary = path.with_extension(format!("{}.part", uuid::Uuid::new_v4()));
    std::fs::write(
        &temporary,
        serde_json::to_vec_pretty(&annotation).map_err(failure)?,
    )
    .map_err(failure)?;
    std::fs::rename(temporary, path).map_err(failure)?;
    Ok(())
}

fn root(state: &ReferenceLibrary) -> Response<PathBuf> {
    Ok(state.directory.clone())
}
fn guard_reference(
    state: &ReferenceLibrary,
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
            let library = ReferenceLibrary::open(directory)?;
            let reference: reha_core::evaluation::Annotation =
                serde_json::from_value(provisional_reference(&library, hash.to_string())?)
                    .map_err(failure)?;
            reha_core::evaluation::validate_reference(&reference, false).map_err(failure)?;
            dataset_image(&library, hash.to_string())?;
            Ok(reference)
        })
        .collect()
}
fn freeze_reference_groups(state: &ReferenceLibrary) -> Response<Value> {
    let directory = root(state)?;
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
        let temp = path.with_extension(format!("{}.part", uuid::Uuid::new_v4()));
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
fn dataset(state: &ReferenceLibrary) -> Response<Value> {
    let directory = root(state)?;
    let data = inventory(&directory)?;
    let split: Value = std::fs::read(directory.join("split.json"))
        .ok()
        .map(|bytes| serde_json::from_slice(&bytes))
        .transpose()
        .map_err(failure)?
        .unwrap_or(json!({"days":{}}));
    let entries=data["entries"].as_array().ok_or("Ungültiges Inventar.")?.iter().map(|entry|{
        let day=split["days"].as_object().and_then(|days|days.iter().find(|(_,group)|group["document_hashes"].as_array().is_some_and(|hashes|hashes.contains(&entry["sha256"]))));
        let reference: Option<reha_core::evaluation::Annotation> = entry["sha256"].as_str().filter(|h|h.len()==64 && h.chars().all(|c|c.is_ascii_hexdigit())).and_then(|h|provisional_reference(state, h.to_string()).ok()).and_then(|value|serde_json::from_value(value).ok());
        let approved=reference.as_ref().is_some_and(|r|r.verified && r.approval_hash.as_ref()==Some(&reha_core::evaluation::reference_hash(r)));
        let reviewed=reference.as_ref().map(|r|r.appointments.iter().filter(|a|["date","start","end","title","location","therapist","notes"].iter().all(|f|a.fields.get(*f).is_some_and(|f|f.confirmed_at.is_some()))).count()).unwrap_or(0);
        json!({"verified":approved,"reviewed_rows":reviewed,"reference_rows":reference.as_ref().map(|r|r.appointments.len()),"filename":entry["filename"],"sha256":entry["sha256"],"bytes":entry["bytes"],"day_id":day.map(|(id,_)|id),"split":day.map(|(_,group)|&group["split"])})
    }).collect::<Vec<_>>();
    Ok(
        json!({"root":directory,"entries":entries,"split_frozen":split["schema_version"]==3 && split["grouping_verified"]==true}),
    )
}
fn dataset_image(state: &ReferenceLibrary, hash: String) -> Response<Value> {
    let directory = root(state)?;
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
    let path = checked_path(
        &directory,
        std::path::Path::new("raw").join(filename).as_path(),
    )?
    .canonicalize()
    .map_err(failure)?;
    if path.parent() != Some(raw.as_path())
        || path.metadata().map_err(failure)?.len() > crate::photo_source::MAX_BYTES as u64
    {
        return Err("Bildpfad oder Größe ungültig.".into());
    }
    let bytes = crate::photo_source::read(path).map_err(failure)?;
    if reha_core::hash(&bytes) != hash {
        return Err("Quellbild stimmt nicht mit der inventarisierten Prüfsumme überein.".into());
    }
    Ok(json!({"filename":filename,"base64":STANDARD.encode(bytes)}))
}
fn provisional_reference(state: &ReferenceLibrary, hash: String) -> Response<Value> {
    if hash.len() != 64 || !hash.chars().all(|c| c.is_ascii_hexdigit()) {
        return Err("Ungültige Quellkennung.".into());
    }
    let directory = root(state)?;
    let path = checked_path(
        &directory,
        std::path::Path::new(&format!("labels/provisional/{hash}.json")),
    )?;
    let value: Value =
        serde_json::from_slice(&std::fs::read(path).map_err(failure)?).map_err(failure)?;
    if value["document_hashes"] != json!([hash]) {
        return Err("Quelle und Referenz stimmen nicht überein.".into());
    }
    Ok(value)
}

/// All reference CLI commands run inside a bounded cross-process writer lock.
pub fn command(args: &[String]) -> Response<Value> {
    let action = args.first().ok_or("Referenzbefehl fehlt.")?;
    let library = ReferenceLibrary::open(std::path::Path::new(
        args.get(1).ok_or("Datensatzpfad fehlt.")?,
    ))?;
    let mut lock = rusqlite::Connection::open(library.directory.join(".reference-lock.sqlite3"))
        .map_err(failure)?;
    lock.busy_timeout(std::time::Duration::from_secs(5))
        .map_err(failure)?;
    let _transaction = lock
        .transaction_with_behavior(rusqlite::TransactionBehavior::Immediate)
        .map_err(failure)?;
    let argument = || args.get(2).ok_or("Datei oder Quellhash fehlt.");
    match action.as_str() {
        "list" if args.len() == 2 => dataset(&library),
        "get" if args.len() == 3 => provisional_reference(&library, argument()?.clone()),
        "save" if args.len() == 3 => {
            let mut annotation: reha_core::evaluation::Annotation = serde_json::from_slice(&std::fs::read(argument()?).map_err(failure)?).map_err(failure)?;
            let previous = annotation.document_hashes.first().and_then(|hash| provisional_reference(&library, hash.clone()).ok()).and_then(|value| serde_json::from_value(value).ok());
            retain_confirmations(previous.as_ref(), &mut annotation);
            save_annotation(&library, annotation)?;
            Ok(json!({"saved":true,"verified":false}))
        }
        "confirm-row" | "confirm-coverage" | "approve" => {
            if args.len() != if action == "confirm-row" { 4 } else { 3 } { return Err("Ungültige Argumente.".into()); }
            let mut annotation: reha_core::evaluation::Annotation = serde_json::from_value(provisional_reference(&library, argument()?.clone())?).map_err(failure)?;
            annotation.verified = false;
            if action == "confirm-row" {
                let a = annotation.appointments.iter_mut().find(|a| a.id == args[3]).ok_or("Terminzeile fehlt.")?;
                for field in reha_core::review::FIELDS {
                    let value = reha_core::review::value(a, field);
                    if let Some(assessment) = a.fields.get_mut(*field) {
                        assessment.confirmed_value = Some(value);
                        assessment.confirmed_at = Some(chrono::Utc::now().timestamp());
                    }
                }
            } else if action == "confirm-coverage" { annotation.coverage_confirmed = true; }
            else { annotation.verified = true; }
            save_annotation(&library, annotation)?;
            Ok(json!({"saved":true,"verified":action=="approve"}))
        }
        "freeze-groups" if args.len() == 2 => freeze_reference_groups(&library),
        "evaluate" if args.len() == 4 => {
            let annotation = serde_json::from_value(provisional_reference(&library, argument()?.clone())?).map_err(failure)?;
            let run = serde_json::from_slice(&std::fs::read(&args[3]).map_err(failure)?).map_err(failure)?;
            serde_json::to_value(evaluate_annotation(&library, annotation, run)?).map_err(failure)
        }
        "archive" if args.len() == 4 => archive_run(&library, std::path::Path::new(argument()?), &args[3]),
        "image" if args.len() == 4 => {
            let data = dataset_image(&library, argument()?.clone())?;
            let bytes = STANDARD.decode(data["base64"].as_str().ok_or("Bilddaten fehlen.")?).map_err(failure)?;
            std::fs::write(&args[3], bytes).map_err(failure)?;
            Ok(json!({"saved":true}))
        }
        _ => Err("reha lab list ROOT | get ROOT HASH | save ROOT FILE | confirm-row ROOT HASH ROW_ID | confirm-coverage ROOT HASH | approve ROOT HASH | freeze-groups ROOT | evaluate ROOT HASH RUN_JSON | image ROOT HASH OUTPUT | archive ROOT RUN_DIRECTORY BATCH_UUID".into())
    }
}

/// File edits cannot manufacture row confirmation or carry stale approval forward.
fn retain_confirmations(
    previous: Option<&reha_core::evaluation::Annotation>,
    next: &mut reha_core::evaluation::Annotation,
) {
    next.verified = false;
    next.approval_hash = None;
    next.reviewed_at = None;
    let row_lines = |r: &reha_core::evaluation::Annotation, id: &str| {
        let mut lines: Vec<_> = r
            .lines
            .iter()
            .filter(|l| l.appointment_id == id)
            .map(|l| serde_json::to_string(l).unwrap())
            .collect();
        lines.sort();
        lines
    };
    let same_sources = previous.is_some_and(|p| {
        p.input_class == next.input_class
            && p.document_hashes == next.document_hashes
            && serde_json::to_value(&p.sources).ok() == serde_json::to_value(&next.sources).ok()
    });
    next.coverage_confirmed = previous.is_some_and(|p| {
        p.coverage_confirmed
            && same_sources
            && p.appointments
                .iter()
                .map(|a| &a.id)
                .eq(next.appointments.iter().map(|a| &a.id))
    });
    let next_lines: std::collections::HashMap<_, _> = next
        .appointments
        .iter()
        .map(|a| (a.id.clone(), row_lines(next, &a.id)))
        .collect();
    for a in &mut next.appointments {
        let old = previous.and_then(|p| p.appointments.iter().find(|old| old.id == a.id));
        let same = same_sources
            && previous.is_some_and(|p| row_lines(p, &a.id) == next_lines[&a.id])
            && old.is_some_and(|old| {
                reha_core::review::values_hash(old) == reha_core::review::values_hash(a)
                    && old.row_polygon == a.row_polygon
                    && old.fields.iter().all(|(key, value)| {
                        a.fields.get(key).is_some_and(|field| {
                            let mut old = value.clone();
                            old.confirmed_at = None;
                            old.confirmed_value = None;
                            let mut new = field.clone();
                            new.confirmed_at = None;
                            new.confirmed_value = None;
                            old == new
                        })
                    })
                    && old.fields.len() == a.fields.len()
            });
        for (key, field) in &mut a.fields {
            field.confirmed_at = if same {
                old.and_then(|a| a.fields.get(key))
                    .and_then(|f| f.confirmed_at)
            } else {
                None
            };
            field.confirmed_value = if same {
                old.and_then(|a| a.fields.get(key))
                    .and_then(|f| f.confirmed_value.clone())
            } else {
                None
            };
        }
    }
}

/// Preserve an experiment without granting reference approval or copying models.
fn archive_run(
    library: &ReferenceLibrary,
    source: &std::path::Path,
    batch: &str,
) -> Response<Value> {
    uuid::Uuid::parse_str(batch).map_err(failure)?;
    let source = source.canonicalize().map_err(failure)?;
    let run: PipelineRun =
        serde_json::from_slice(&std::fs::read(source.join("run.json")).map_err(failure)?)
            .map_err(failure)?;
    uuid::Uuid::parse_str(&run.document.id).map_err(failure)?;
    let parent = checked_path(
        &library.directory,
        std::path::Path::new("experiments").join(batch).as_path(),
    )?;
    let destination = checked_path(
        &library.directory,
        std::path::Path::new("experiments")
            .join(batch)
            .join(&run.document.id)
            .as_path(),
    )?;
    if destination.exists() {
        return Err("Versuch ist bereits archiviert.".into());
    }
    std::fs::create_dir_all(&parent).map_err(failure)?;
    let staging = parent.join(format!("{}.partial", uuid::Uuid::new_v4()));
    std::fs::create_dir(&staging).map_err(failure)?;
    let result = (|| {
        let bytes = std::fs::read(source.join("run.json")).map_err(failure)?;
        let run: PipelineRun = serde_json::from_slice(&bytes).map_err(failure)?;
        if destination.file_name().and_then(|s| s.to_str()) != Some(&run.document.id) {
            return Err("Versuch wurde während der Archivierung ersetzt.".into());
        }
        std::fs::write(staging.join("run.json"), &bytes).map_err(failure)?;
        let mut files = std::collections::BTreeSet::from([
            "source.bin".to_string(),
            "original.png".into(),
            "page.png".into(),
            "refinement-readings.json".into(),
            "pdf-evidence.json".into(),
        ]);
        files.extend(run.stages.iter().flat_map(|s| s.artifacts.iter().cloned()));
        for relative in files {
            let path = std::path::Path::new(&relative);
            if !matches!(
                path.extension().and_then(|s| s.to_str()),
                Some("png" | "jpg" | "jpeg" | "json")
            ) && relative != "source.bin"
            {
                continue;
            }
            let input = checked_path(&source, path)?;
            if !input.is_file() {
                continue;
            }
            let output = staging.join(path);
            std::fs::create_dir_all(output.parent().ok_or("Artefaktpfad fehlt.")?)
                .map_err(failure)?;
            std::fs::copy(input, output).map_err(failure)?;
        }
        let manifest = json!({"schema_version":1,"batch_id":batch,"run_id":run.document.id,
            "app_version":env!("CARGO_PKG_VERSION"),"platform":std::env::consts::OS,
            "source_sha256":run.document.source_hash,"config":run.config,"models":run.model_manifest,
            "run_sha256":reha_core::hash(&std::fs::read(staging.join("run.json")).map_err(failure)?),
            "archiver_binary_sha256":reha_core::hash(&std::fs::read(std::env::current_exe().map_err(failure)?).map_err(failure)?),"verified_accuracy":false});
        std::fs::write(
            staging.join("manifest.json"),
            serde_json::to_vec_pretty(&manifest).map_err(failure)?,
        )
        .map_err(failure)?;
        std::fs::rename(&staging, &destination).map_err(failure)?;
        Ok(json!({"directory":destination,"verified_accuracy":false}))
    })();
    if result.is_err() {
        let _ = std::fs::remove_dir_all(staging);
    }
    result
}

fn checked_path(root: &std::path::Path, relative: &std::path::Path) -> Response<PathBuf> {
    let mut path = root.to_path_buf();
    for component in relative.components() {
        if let std::path::Component::Normal(name) = component {
            path.push(name);
        } else {
            return Err("Ungültiger Pfad im Datensatz.".into());
        }
        match path.symlink_metadata() {
            Ok(metadata) if metadata.file_type().is_symlink() => {
                return Err("Symbolische Verknüpfungen sind im Datensatz nicht zulässig.".into())
            }
            Ok(_) => (),
            Err(e) if e.kind() == std::io::ErrorKind::NotFound => (),
            Err(e) => return Err(failure(e)),
        }
    }
    Ok(path)
}
