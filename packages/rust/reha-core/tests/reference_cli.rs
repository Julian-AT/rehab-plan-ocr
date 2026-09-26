use reha_core::{contracts::*, evaluation::*, lab};
use serde_json::{json, Value};
fn approved_fixture() -> Annotation {
    let hash = "a".repeat(64);
    let mut r = Annotation {
        schema_version: 2,
        day_id: "development-01".into(),
        document_hashes: vec![hash.clone()],
        verified: true,
        reviewed_at: Some("2026-09-11".into()),
        split: "development".into(),
        coverage_confirmed: true,
        sources: vec![ReferenceSource {
            source_hash: hash.clone(),
            original_hash: "b".repeat(64),
            width: 1000,
            height: 1000,
            logical_page: "one".into(),
            capture_series: "capture".into(),
            treatment_days: vec!["2026-09-10".into()],
            table_polygon: reha_core::geometry::rect(0., 0., 1000., 1000.),
            relationships_confirmed: true,
        }],
        ..Default::default()
    };
    for i in 0..2 {
        let mut a = Appointment::empty(format!("a{i}"));
        a.date = Some("2026-09-10".into());
        a.start = Some("08:00".into());
        a.end = Some("08:30".into());
        a.title = "Übung".into();
        a.location = format!("Raum {i}");
        a.therapist = format!("Person {i}");
        a.row_polygon = reha_core::geometry::rect(0., 100. + i as f64 * 100., 900., 40.);
        for field in [
            "date",
            "start",
            "end",
            "title",
            "location",
            "therapist",
            "notes",
        ] {
            let value = reha_core::review::value(&a, field);
            let state = if reha_core::review::empty(&value) {
                PrintedState::NotPrinted
            } else {
                PrintedState::Legible
            };
            a.fields.insert(
                field.into(),
                reha_core::contracts::FieldAssessment {
                    state: state.clone(),
                    frame: "original".into(),
                    polygon: a.row_polygon.clone(),
                    confirmed_value: Some(value.clone()),
                    confirmed_at: Some(100),
                    ..Default::default()
                },
            );
            if state == PrintedState::Legible {
                r.lines.push(ReferenceLine {
                    id: format!("{i}-{field}"),
                    source_hash: hash.clone(),
                    appointment_id: a.id.clone(),
                    field: field.into(),
                    text: value.as_str().unwrap().into(),
                    polygon: a.row_polygon.clone(),
                    state,
                    error_causes: vec![],
                });
            }
        }
        r.appointments.push(a);
    }
    r.approval_hash = Some(reference_hash(&r));
    r
}

fn command(root: &std::path::Path, action: &str, arguments: &[&str]) -> Result<Value, String> {
    let args: Vec<String> = [action, root.to_str().unwrap()]
        .into_iter()
        .chain(arguments.iter().copied())
        .map(str::to_string)
        .collect();
    lab::command(&args)
}
fn dataset() -> (tempfile::TempDir, Vec<String>) {
    let dir = tempfile::tempdir().unwrap();
    std::fs::create_dir_all(dir.path().join("raw")).unwrap();
    let mut entries = vec![];
    let mut references = vec![];
    let mut hashes = vec![];
    for i in 0..4 {
        let bytes = format!("invented-source-{i}");
        let hash = reha_core::hash(bytes.as_bytes());
        let name = format!("source-{i}.png");
        std::fs::write(dir.path().join("raw").join(&name), bytes).unwrap();
        entries.push(json!({"filename":name,"sha256":hash,"bytes":17}));
        let mut reference = approved_fixture();
        reference.document_hashes = vec![hash.clone()];
        let source = &mut reference.sources[0];
        source.source_hash = hash.clone();
        source.original_hash = hash.clone();
        source.logical_page = format!("page-{i}");
        source.capture_series = format!("capture-{i}");
        source.treatment_days = vec![format!("2026-09-{}", 10 + i)];
        for line in &mut reference.lines {
            line.source_hash = hash.clone();
        }
        references.push(reference);
        hashes.push(hash);
    }
    std::fs::write(
        dir.path().join("inventory.json"),
        serde_json::to_vec(&json!({"entries":entries})).unwrap(),
    )
    .unwrap();
    for reference in references {
        let file = dir.path().join("editing.json");
        std::fs::write(&file, serde_json::to_vec(&reference).unwrap()).unwrap();
        command(dir.path(), "save", &[file.to_str().unwrap()]).unwrap();
    }
    command(dir.path(), "freeze-groups", &[]).unwrap();
    (dir, hashes)
}
#[test]
fn reference_progress_requires_explicit_approval_and_edits_revoke_it() {
    let (root, hashes) = dataset();
    let hash = &hashes[0];
    assert!(command(root.path(), "approve", &[hash]).is_err());
    command(root.path(), "confirm-row", &[hash, "a0"]).unwrap();
    let saved: Annotation =
        serde_json::from_value(command(root.path(), "get", &[hash]).unwrap()).unwrap();
    assert!(saved.appointments[0]
        .fields
        .values()
        .all(|f| f.confirmed_at.is_some()));
    assert!(saved.appointments[1]
        .fields
        .values()
        .all(|f| f.confirmed_at.is_none()));
    assert!(!saved.verified);
    assert!(command(root.path(), "approve", &[hash]).is_err());
    command(root.path(), "confirm-row", &[hash, "a1"]).unwrap();
    command(root.path(), "confirm-coverage", &[hash]).unwrap();
    command(root.path(), "approve", &[hash]).unwrap();
    let mut saved: Annotation =
        serde_json::from_value(command(root.path(), "get", &[hash]).unwrap()).unwrap();
    assert!(saved.verified);
    saved.appointments[0].title = "Korrigiertes Training".into();
    let file = root.path().join("editing.json");
    std::fs::write(&file, serde_json::to_vec(&saved).unwrap()).unwrap();
    command(root.path(), "save", &[file.to_str().unwrap()]).unwrap();
    let changed: Annotation =
        serde_json::from_value(command(root.path(), "get", &[hash]).unwrap()).unwrap();
    assert!(!changed.verified);
    assert!(changed.approval_hash.is_none());
    assert!(changed.appointments[0]
        .fields
        .values()
        .all(|f| f.confirmed_at.is_none()));
    assert!(changed.appointments[1]
        .fields
        .values()
        .all(|f| f.confirmed_at.is_some()));
    assert!(command(root.path(), "approve", &[hash]).is_err());
    let mut changed_group = changed;
    changed_group.day_id = "changed".into();
    std::fs::write(&file, serde_json::to_vec(&changed_group).unwrap()).unwrap();
    assert!(command(root.path(), "save", &[file.to_str().unwrap()]).is_err());
}
#[test]
fn invalid_source_paths_hashes_and_field_types_are_rejected() {
    let (root, hashes) = dataset();
    assert!(command(root.path(), "get", &["../outside"]).is_err());
    let output = root.path().join("image.png");
    std::fs::write(root.path().join("raw/source-0.png"), "changed original").unwrap();
    assert!(command(
        root.path(),
        "image",
        &[&hashes[0], output.to_str().unwrap()]
    )
    .is_err());
    let mut value = command(root.path(), "get", &[&hashes[0]]).unwrap();
    value["appointments"][0]["title"] = json!({});
    assert!(serde_json::from_value::<Annotation>(value).is_err());
    let mut value = serde_json::to_value(approved_fixture()).unwrap();
    value["appointments"][0]
        .as_object_mut()
        .unwrap()
        .remove("therapist");
    assert_eq!(
        serde_json::from_value::<Annotation>(value)
            .unwrap()
            .appointments[0]
            .therapist,
        ""
    );
}

#[test]
fn changed_evidence_requires_reconfirmation_and_malformed_grouping_is_an_error() {
    let (root, hashes) = dataset();
    let hash = &hashes[0];
    command(root.path(), "confirm-row", &[hash, "a0"]).unwrap();
    let mut reference = command(root.path(), "get", &[hash]).unwrap();
    reference["lines"][0]["text"] = json!("changed printed reading");
    let file = root.path().join("editing.json");
    std::fs::write(&file, serde_json::to_vec(&reference).unwrap()).unwrap();
    command(root.path(), "save", &[file.to_str().unwrap()]).unwrap();
    let reference: Annotation =
        serde_json::from_value(command(root.path(), "get", &[hash]).unwrap()).unwrap();
    assert!(reference.appointments[0]
        .fields
        .values()
        .all(|f| f.confirmed_at.is_none()));
    let mut malformed = serde_json::to_value(reference).unwrap();
    malformed["document_hashes"] = json!([]);
    std::fs::write(
        root.path().join(format!("labels/provisional/{hash}.json")),
        serde_json::to_vec(&malformed).unwrap(),
    )
    .unwrap();
    assert!(command(root.path(), "freeze-groups", &[]).is_err());
}
#[test]
#[cfg(unix)]
fn library_rejects_directory_symlinks() {
    let (root, _) = dataset();
    let outside = tempfile::tempdir().unwrap();
    std::os::unix::fs::symlink(outside.path(), root.path().join("experiments")).unwrap();
    assert!(command(root.path(), "list", &[]).is_err());
    assert!(std::fs::read_dir(outside.path()).unwrap().next().is_none());
}

#[test]
fn reference_commands_wait_for_the_shared_writer_lock() {
    let (root, _) = dataset();
    let mut connection =
        rusqlite::Connection::open(root.path().join(".reference-lock.sqlite3")).unwrap();
    let transaction = connection
        .transaction_with_behavior(rusqlite::TransactionBehavior::Immediate)
        .unwrap();
    let path = root.path().to_path_buf();
    let (sender, receiver) = std::sync::mpsc::channel();
    let thread = std::thread::spawn(move || sender.send(command(&path, "list", &[])).unwrap());
    assert!(matches!(
        receiver.recv_timeout(std::time::Duration::from_millis(50)),
        Err(std::sync::mpsc::RecvTimeoutError::Timeout)
    ));
    transaction.commit().unwrap();
    receiver
        .recv_timeout(std::time::Duration::from_secs(2))
        .unwrap()
        .unwrap();
    thread.join().unwrap();
}
#[test]
fn archive_preserves_declared_nested_evidence_and_excludes_models() {
    let (root, _) = dataset();
    let source = tempfile::tempdir().unwrap();
    let mut run: PipelineRun =
        serde_json::from_str(include_str!("../../../../tests/fixtures/sample-run.json")).unwrap();
    run.document.id = uuid::Uuid::new_v4().to_string();
    run.stages[0].artifacts = vec!["refinement/crop.png".into(), "model.onnx".into()];
    std::fs::create_dir(source.path().join("refinement")).unwrap();
    std::fs::write(source.path().join("refinement/crop.png"), "invented crop").unwrap();
    std::fs::write(source.path().join("model.onnx"), "not an artifact").unwrap();
    std::fs::write(
        source.path().join("unrelated.txt"),
        "private unrelated file",
    )
    .unwrap();
    std::fs::write(
        source.path().join("run.json"),
        serde_json::to_vec(&run).unwrap(),
    )
    .unwrap();
    let batch = uuid::Uuid::new_v4().to_string();
    let result = command(
        root.path(),
        "archive",
        &[source.path().to_str().unwrap(), &batch],
    )
    .unwrap();
    let archived = std::path::Path::new(result["directory"].as_str().unwrap());
    assert!(archived.join("refinement/crop.png").is_file());
    assert!(!archived.join("model.onnx").exists());
    assert!(!archived.join("unrelated.txt").exists());
    let manifest: Value =
        serde_json::from_slice(&std::fs::read(archived.join("manifest.json")).unwrap()).unwrap();
    assert!(manifest["archiver_binary_sha256"].is_string());
    assert!(manifest.get("binary_sha256").is_none());
    assert_eq!(manifest["verified_accuracy"], false);
    assert!(command(
        root.path(),
        "archive",
        &[source.path().to_str().unwrap(), &batch]
    )
    .is_err());
}
