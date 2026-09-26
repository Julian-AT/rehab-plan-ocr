use reha_core::{calendar, contracts::*, geometry, parser, refinement, review, store::Store};
use std::collections::BTreeMap;
fn run() -> PipelineRun {
    let mut r: PipelineRun = serde_json::from_str(include_str!(
        "../../../../ml/evaluation/fixtures/sample-run.json"
    ))
    .unwrap();
    review::migrate(&mut r).unwrap();
    r
}
fn complete(id: &str) -> Appointment {
    let mut a = Appointment::empty(id.into());
    a.date = Some("2026-09-10".into());
    a.start = Some("08:00".into());
    a.end = Some("08:30".into());
    a.title = "Bewegung".into();
    a
}
fn parse(cells: &[(f64, f64, &str)]) -> (Vec<Appointment>, Vec<ScheduleSection>) {
    let regions: Vec<_> = cells
        .iter()
        .enumerate()
        .map(|(i, (x, y, _))| Region {
            id: format!("r{i}"),
            polygon: geometry::rect(*x, *y, 100., 20.),
            frame: "page".into(),
            kind: "text".into(),
            parent: None,
            children: vec![],
        })
        .collect();
    let observations: Vec<_> = cells
        .iter()
        .enumerate()
        .map(|(i, (_, _, t))| Observation {
            id: format!("o{i}"),
            text: t.to_string(),
            region_ids: vec![format!("r{i}")],
            engine: "test".into(),
            score: None,
            alternatives: vec![],
        })
        .collect();
    (
        parser::extract("document", &observations, &regions).0,
        parser::sections(&observations, &regions),
    )
}
#[test]
fn vertical_days_and_side_by_side_days_keep_their_dates() {
    for cells in [
        vec![
            (0., 0., "Donnerstag, der 10.09.2026"),
            (0., 40., "08:00 - 08:30 Übung"),
            (0., 100., "Freitag, der 11.09.2026"),
            (0., 140., "09:00 - 09:30 Zweite"),
        ],
        vec![
            (0., 0., "Donnerstag, der 10.09.2026"),
            (500., 0., "Freitag, der 11.09.2026"),
            (0., 40., "08:00 - 08:30 Übung"),
            (500., 40., "09:00 - 09:30 Zweite"),
        ],
    ] {
        let (a, s) = parse(&cells);
        assert_eq!(a.len(), 2);
        assert_eq!(s.len(), 2);
        assert_eq!(a[0].date.as_deref(), Some("2026-09-10"));
        assert_eq!(a[1].date.as_deref(), Some("2026-09-11"));
        assert_ne!(a[0].section_id, a[1].section_id);
    }
}
#[test]
fn scoped_metadata_and_administrative_text_do_not_leak_into_notes() {
    let (a, _) = parse(&[
        (0., 0., "Donnerstag, der 10.09.2026"),
        (0., 25., "Klinik: A"),
        (0., 65., "08:00 - 08:30 Übung"),
        (100., 90., "Patient: Privat"),
        (0., 150., "Freitag, der 11.09.2026"),
        (0., 175., "Klinik: B"),
        (0., 220., "08:00 - 08:30 Übung"),
    ]);
    assert_eq!(a[0].metadata.clinic, "A");
    assert_eq!(a[1].metadata.clinic, "B");
    assert!(!a[0].notes.contains("Privat"));
}
#[test]
fn contradictory_metadata_stays_unset_when_one_candidate_repeats() {
    for labels in [
        ["Klinik: A", "Einrichtung: B", "Klinik: B"],
        ["Klinik: B", "Klinik: B", "Einrichtung: A"],
        ["Einrichtung: B", "Klinik: A", "Klinik: B"],
    ] {
        for global in [false, true] {
            let mut cells = vec![
                (0., 0., "Donnerstag, der 10.09.2026"),
                (0., 30., labels[0]),
                (0., 60., labels[1]),
                (0., 90., labels[2]),
                (0., 120., "Abteilung: Bewegung"),
                (0., 160., "08:00 - 08:30 Übung"),
            ];
            if global {
                cells.insert(0, (0., -30., "Klinik: Allgemein"));
            }
            let (appointments, sections) = parse(&cells);
            assert_eq!(appointments.len(), 1);
            assert!(appointments[0].metadata.clinic.is_empty());
            assert!(sections[0].metadata.clinic.is_empty());
            assert_eq!(appointments[0].metadata.department, "Bewegung");
        }
    }
}
#[test]
fn selected_approvals_do_not_require_unresolved_siblings_or_allow_stale_values() {
    let mut r = run();
    let a = complete(&uuid::Uuid::new_v4().to_string());
    let mut b = complete(&uuid::Uuid::new_v4().to_string());
    b.end = None;
    r.appointments = vec![a.clone(), b.clone()];
    review::approve_selection(&mut r, std::slice::from_ref(&a.id), 100).unwrap();
    assert!(!r.review_confirmed);
    assert!(r.appointments[1].included);
    assert_eq!(
        calendar::selected_events(
            &[r.clone()],
            std::slice::from_ref(&a.id),
            "Europe/Vienna",
            None
        )
        .unwrap()
        .len(),
        1
    );
    assert!(calendar::selected_events(
        &[r.clone()],
        std::slice::from_ref(&b.id),
        "Europe/Vienna",
        None
    )
    .is_err());
    r.appointments[0].metadata.preparation = "Gedruckte Anweisung".into();
    assert!(calendar::selected_events(&[r], &[a.id], "Europe/Vienna", None).is_err());
}
#[test]
fn partial_save_later_identical_sibling_is_created_and_old_event_is_kept() {
    let a = complete(&uuid::Uuid::new_v4().to_string());
    let b = complete(&uuid::Uuid::new_v4().to_string());
    let values = calendar::event_values(&a, "Europe/Vienna", None).unwrap();
    let old = ImportRecord {
        id: a.id.clone(),
        schedule_id: "s".into(),
        calendar_id: "c".into(),
        external_id: Some("e".into()),
        approved: values.clone(),
        status: "saved".into(),
        operation_id: "o".into(),
    };
    let current = BTreeMap::from([(a.id.clone(), values.clone())]);
    let ops = calendar::propose_with_identity(
        std::slice::from_ref(&old),
        &[(b.id, values.clone())],
        &current,
        "c",
        false,
        true,
    );
    assert_eq!(ops[0].kind, "create");
    assert_eq!(ops[1].kind, "keep");
    let mut changed = values;
    changed.title = "Neuer Titel".into();
    changed.start_utc = "2026-09-10T07:00:00Z".into();
    changed.end_utc = "2026-09-10T07:30:00Z".into();
    changed.location = "B".into();
    let ops = calendar::propose_with_identity(
        &[old],
        &[(a.id.clone(), changed)],
        &current,
        "c",
        false,
        true,
    );
    assert_eq!(ops[0].kind, "update");
    assert_eq!(ops[0].id, a.id);
}
#[test]
fn suggestions_require_acceptance_remain_rejected_and_never_cross_clinics() {
    let mut r = run();
    let mut a = complete("a");
    a.metadata.clinic = "A".into();
    a.end = None;
    r.appointments = vec![a];
    let d = CompletionDefault {
        id: "d".into(),
        clinic: "A".into(),
        treatment: "Bewegung".into(),
        field: "duration_minutes".into(),
        value: serde_json::json!(30),
    };
    review::suggest(&mut r, std::slice::from_ref(&d), &[]);
    assert_eq!(r.appointments[0].suggestions.len(), 1);
    assert_eq!(r.appointments[0].duration_minutes, None);
    let mut next = r.appointments[0].clone();
    next.suggestions[0].status = "rejected".into();
    r.appointments[0] = review::edit(Some(&r.appointments[0]), next).unwrap();
    review::suggest(&mut r, std::slice::from_ref(&d), &[]);
    assert_eq!(r.appointments[0].suggestions[0].status, "rejected");
    assert_eq!(r.appointments[0].suggestions.len(), 1);
    r.appointments[0].metadata.clinic = "B".into();
    r.appointments[0].suggestions.clear();
    review::suggest(&mut r, &[d], &[]);
    assert!(r.appointments[0].suggestions.is_empty());
}
#[test]
fn agreeing_rereads_recover_missing_fields_and_conflicts_keep_both_candidates() {
    let mut r = run();
    let mut a = complete("a");
    a.end = None;
    r.appointments = vec![a];
    let reading = |attempt: &str, v: &str| refinement::Reading {
        appointment_id: "a".into(),
        field: "end".into(),
        value: serde_json::json!(v),
        evidence: vec![format!("{attempt}-observation")],
        attempt: attempt.into(),
    };
    refinement::apply_readings(&mut r, &[reading("one", "08:30")]).unwrap();
    assert_eq!(r.appointments[0].end.as_deref(), Some("08:30"));
    assert!(!review::field_problems(&r.appointments[0]).is_empty());
    refinement::apply_readings(&mut r, &[reading("one", "08:30"), reading("two", "08:30")])
        .unwrap();
    assert_eq!(r.appointments[0].end.as_deref(), Some("08:30"));
    refinement::apply_readings(&mut r, &[reading("three", "08:45")]).unwrap();
    assert!(r.appointments[0]
        .issues
        .iter()
        .any(|i| i.code == "reread_conflict"));
    assert_eq!(r.appointments[0].end.as_deref(), Some("08:30"));
    let mut edit = r.appointments[0].clone();
    edit.end = Some("09:00".into());
    r.appointments[0] = review::edit(Some(&r.appointments[0]), edit).unwrap();
    refinement::apply_readings(
        &mut r,
        &[reading("four", "08:50"), reading("five", "08:50")],
    )
    .unwrap();
    assert_eq!(r.appointments[0].end.as_deref(), Some("09:00"));
}
#[test]
fn v1_migration_keeps_edits_bindings_and_expires_refinement_evidence() {
    let temp = tempfile::tempdir().unwrap();
    let store = Store::open(temp.path()).unwrap();
    let mut r: PipelineRun = serde_json::from_str(include_str!(
        "../../../../ml/evaluation/fixtures/sample-run.json"
    ))
    .unwrap();
    r.document.imported_at = 100;
    r.appointments[0].title = "Old manual edit".into();
    r.review_confirmed = true;
    store.save_run(&r).unwrap();
    store
        .bind_schedule(&r.document.id, "schedule", "hash")
        .unwrap();
    let migrated = store.load_run(&r.document.id).unwrap();
    assert_eq!(migrated.schema_version, 3);
    assert!(migrated.appointments[0].approval.is_none());
    assert_eq!(migrated.appointments[0].title, "Old manual edit");
    assert_eq!(migrated.appointments[0].origins["title"].kind, "manual");
    assert_eq!(
        store.list_scans().unwrap()[0].schedule_id.as_deref(),
        Some("schedule")
    );
    let dir = store.scan_dir(&r.document.id).unwrap();
    std::fs::create_dir_all(&dir).unwrap();
    std::fs::write(dir.join("refinement-readings.json"), "private evidence").unwrap();
    store
        .set_setting("preferences", r#"{"retention_days":30}"#)
        .unwrap();
    assert_eq!(store.cleanup(100 + 30 * 86400 - 1).unwrap(), 0);
    assert_eq!(store.cleanup(100 + 30 * 86400).unwrap(), 1);
    assert!(!dir.exists());
    assert_eq!(
        store.list_scans().unwrap()[0].schedule_id.as_deref(),
        Some("schedule")
    );
}

#[test]
fn cached_column_refresh_preserves_edits_bindings_and_capture_warnings() {
    let mut r = run();
    r.appointments = parser::extract(&r.document.id, &r.observations, &r.regions).0;
    assert!(!r.appointments.is_empty());
    r.extraction_version = 5;
    let mut edited = r.appointments[0].clone();
    edited.title = "Meine geprüfte Bezeichnung".into();
    r.appointments[0] = review::edit(Some(&r.appointments[0]), edited).unwrap();
    let a = &mut r.appointments[0];
    a.calendar_event_id = Some("retained-calendar-id".into());
    a.ics_event_id = Some("retained-ics-id".into());
    a.calendar_saved_hash = Some("retained-calendar-hash".into());
    a.fields
        .entry("start".into())
        .or_default()
        .reasons
        .push("Obsolete column warning".into());
    let clipped = a.fields.entry("therapist".into()).or_default();
    clipped.state = PrintedState::Cropped;
    clipped
        .reasons
        .push("Text berührt den Bildrand; möglicherweise abgeschnitten.".into());
    let ids: Vec<_> = r.appointments.iter().map(|a| a.id.clone()).collect();
    let mut structural_change = r.clone();
    structural_change.appointments.pop();
    let unchanged = serde_json::to_value(&structural_change).unwrap();
    assert!(!refinement::refresh_cached_mapping(&mut structural_change).unwrap());
    assert_eq!(unchanged, serde_json::to_value(&structural_change).unwrap());
    assert!(refinement::refresh_cached_mapping(&mut r).unwrap());
    assert_eq!(r.extraction_version, parser::EXTRACTION_VERSION);
    assert_eq!(
        ids,
        r.appointments
            .iter()
            .map(|a| a.id.clone())
            .collect::<Vec<_>>()
    );
    let a = &r.appointments[0];
    assert_eq!(a.title, "Meine geprüfte Bezeichnung");
    assert_eq!(a.calendar_event_id.as_deref(), Some("retained-calendar-id"));
    assert_eq!(a.ics_event_id.as_deref(), Some("retained-ics-id"));
    assert_eq!(
        a.calendar_saved_hash.as_deref(),
        Some("retained-calendar-hash")
    );
    assert!(!a.fields["start"]
        .reasons
        .iter()
        .any(|r| r == "Obsolete column warning"));
    assert_eq!(a.fields["therapist"].state, PrintedState::Cropped);
    assert!(a.approval.is_none());
    r.extraction_version = 6;
    assert!(refinement::refresh_cached_mapping(&mut r).unwrap());
    r.extraction_version = 7;
    assert!(refinement::refresh_cached_mapping(&mut r).unwrap());
    assert_eq!(r.appointments[0].title, "Meine geprüfte Bezeichnung");
    assert!(!refinement::refresh_cached_mapping(&mut r).unwrap());
}

#[test]
fn actual_numeric_alternatives_stay_visible_and_preserve_original_text() {
    let mut r = run();
    let header = r
        .observations
        .iter_mut()
        .find(|o| o.text.contains("Tagesplan"))
        .unwrap();
    let original = "Donnerstag, der 10.09.2026".to_string();
    header.text = original.replace("2026", "2O26");
    header.alternatives = vec![original];
    let retained = header.text.clone();
    let source_id = header.id.clone();
    let appointments = parser::extract(&r.document.id, &r.observations, &r.regions).0;
    let sections = parser::sections(&r.observations, &r.regions);
    assert!(!appointments.is_empty());
    for a in &appointments {
        assert_eq!(a.date.as_deref(), Some("2026-09-10"));
        assert_eq!(a.fields["date"].state, PrintedState::Unreviewed);
        assert!(a
            .issues
            .iter()
            .any(|i| i.code == "numeric_candidate" && i.blocking));
    }
    assert_eq!(sections[0].date.as_deref(), Some("2026-09-10"));
    assert_eq!(
        r.observations
            .iter()
            .find(|o| o.id == source_id)
            .unwrap()
            .text,
        retained
    );
}

#[test]
fn reprocessing_preserves_manual_values_and_calendar_identity_in_original_coordinates() {
    let mut previous = run();
    previous.appointments.truncate(1);
    let mut edited = previous.appointments[0].clone();
    edited.title = "Meine Korrektur".into();
    previous.appointments[0] = review::edit(Some(&previous.appointments[0]), edited).unwrap();
    previous.appointments[0].calendar_event_id = Some("stable-calendar-binding".into());
    let mut next = previous.clone();
    next.appointments[0].id = "new-detector-id".into();
    next.appointments[0].title = "New OCR reading".into();
    next.appointments[0].origins.clear();
    next.appointments[0].calendar_event_id = None;
    // The detector now operates at half resolution.
    for region in &mut next.regions {
        for point in &mut region.polygon {
            point.x *= 0.5;
            point.y *= 0.5;
        }
    }
    next.page_to_original = geometry::multiply(
        &previous.page_to_original,
        &[2., 0., 0., 0., 2., 0., 0., 0., 1.],
    );
    next.refinement_readings.push(RefinementReading {
        appointment_id: "new-detector-id".into(),
        field: "title".into(),
        value: serde_json::json!("New OCR reading"),
        evidence: vec![],
        attempt: "crop".into(),
    });
    refinement::preserve_review(&previous, &mut next).unwrap();
    assert_eq!(
        next.refinement_readings[0].appointment_id,
        previous.appointments[0].id
    );
    assert_eq!(next.appointments.len(), 1);
    assert_eq!(next.appointments[0].id, previous.appointments[0].id);
    assert_eq!(next.appointments[0].title, "Meine Korrektur");
    assert_eq!(
        next.appointments[0].calendar_event_id.as_deref(),
        Some("stable-calendar-binding")
    );
    // A detector splitting one reviewed row cannot silently create two approved appointments.
    let mut ambiguous = next.clone();
    let mut duplicate = ambiguous.appointments[0].clone();
    duplicate.id = "split-row".into();
    ambiguous.appointments.push(duplicate);
    refinement::preserve_review(&previous, &mut ambiguous).unwrap();
    let ids: std::collections::HashSet<_> = ambiguous.appointments.iter().map(|a| &a.id).collect();
    assert_eq!(ids.len(), ambiguous.appointments.len());
    assert_eq!(
        ambiguous
            .appointments
            .iter()
            .filter(|a| a.id == previous.appointments[0].id)
            .count(),
        1
    );
    assert!(ambiguous.appointments.iter().all(|a| a
        .issues
        .iter()
        .any(|i| i.code == "retained_review" && i.blocking)));
}

#[test]
fn experiment_crop_records_original_pixel_transform_and_never_approves() {
    let temp = tempfile::tempdir().unwrap();
    let mut r = run();
    r.appointments = vec![complete("a")];
    r.appointments[0]
        .provenance
        .insert("title".into(), vec!["observation".into()]);
    r.observations = vec![Observation {
        id: "observation".into(),
        text: "08:00 Übung".into(),
        region_ids: vec!["row".into()],
        engine: "test".into(),
        score: None,
        alternatives: vec![],
    }];
    r.regions = vec![Region {
        id: "row".into(),
        polygon: geometry::rect(40., 40., 100., 20.),
        frame: "page".into(),
        kind: "text".into(),
        parent: None,
        children: vec![],
    }];
    r.page_to_original = [2., 0., 10., 0., 2., 20., 0., 0., 1.];
    image::RgbImage::new(400, 400)
        .save(temp.path().join("original.png"))
        .unwrap();
    let output = temp.path().join("experiment");
    let crop = refinement::experiment_crop(&r, temp.path(), &output).unwrap();
    assert_eq!(
        crop["crop_to_original"],
        serde_json::json!([1., 0., 78., 0., 1., 88., 0., 0., 1.])
    );
    assert_eq!(crop["width"], 224);
    assert_eq!(crop["height"], 64);
    assert_eq!(crop["approved"], false);
    assert_eq!(
        crop["crop_sha256"],
        reha_core::hash(&std::fs::read(output.join("crop.png")).unwrap())
    );
    assert!(r.appointments[0].approval.is_none());
}

#[cfg(feature = "onnx")]
#[test]
fn exhausted_or_cancelled_pass_does_not_schedule_inference_or_change_the_draft() {
    use std::sync::atomic::AtomicBool;
    let models = std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("../../../.local/models/runtime/small");
    if !models.join("manifest.json").exists() {
        return;
    }
    let mut engine = reha_core::ocr::OnnxEngine::load(&models).unwrap();
    let temp = tempfile::tempdir().unwrap();
    let deadline = std::time::Instant::now();
    let image = image::RgbImage::new(100, 100);
    let (regions, observations, stages) = engine
        .recognize_until(
            &image,
            &PipelineConfig::default(),
            &AtomicBool::new(false),
            temp.path(),
            Some(deadline),
        )
        .unwrap();
    assert!(regions.is_empty() && observations.is_empty());
    assert_eq!(stages[0].status, "budget_exhausted");
    let mut r = run();
    let before = r.appointments.clone();
    refinement::refine(
        &mut engine,
        &mut r,
        temp.path(),
        &AtomicBool::new(true),
        deadline + std::time::Duration::from_secs(60),
    )
    .unwrap();
    assert!(r.refinement_attempts.is_empty());
    assert_eq!(
        r.appointments
            .iter()
            .map(review::values_hash)
            .collect::<Vec<_>>(),
        before.iter().map(review::values_hash).collect::<Vec<_>>()
    );
}

#[test]
fn metadata_above_neighboring_columns_does_not_cross_section_boundaries() {
    let (a, _) = parse(&[
        (0., 0., "Klinik: A"),
        (500., 0., "Klinik: B"),
        (0., 30., "Donnerstag, der 10.09.2026"),
        (500., 30., "Freitag, der 11.09.2026"),
        (0., 70., "08:00 - 08:30 Übung"),
        (500., 70., "09:00 - 09:30 Zweite"),
        (0., 110., "Klinik: Terminbezogener Hinweis"),
    ]);
    assert_eq!(a.len(), 2);
    assert_eq!(a[0].metadata.clinic, "A");
    assert_eq!(a[1].metadata.clinic, "B");
}

#[test]
fn partial_ics_exports_preserve_identical_siblings_and_metadata_update_uids() {
    let mut r = run();
    r.appointments = vec![
        complete("6a2fcf86-d1ec-427e-a008-42b375027ce1"),
        complete("6a2fcf86-d1ec-427e-a008-42b375027ce2"),
    ];
    review::approve_selection(
        &mut r,
        &[
            "6a2fcf86-d1ec-427e-a008-42b375027ce1".into(),
            "6a2fcf86-d1ec-427e-a008-42b375027ce2".into(),
        ],
        1,
    )
    .unwrap();
    let first = calendar::selected_ics_events(
        &[r.clone()],
        &["6a2fcf86-d1ec-427e-a008-42b375027ce1".into()],
        "Europe/Vienna",
        None,
        None,
    )
    .unwrap();
    r.appointments[0].ics_event_id = Some(first[0].0.clone());
    let second = calendar::selected_ics_events(
        &[r.clone()],
        &["6a2fcf86-d1ec-427e-a008-42b375027ce2".into()],
        "Europe/Vienna",
        None,
        Some(&[first[0].0.clone()]),
    )
    .unwrap();
    assert_ne!(first[0].0, second[0].0);
    r.appointments[0].metadata.preparation =
        "Handtuch, Wasser; Tasche\\bereit\nZweite Zeile".into();
    review::approve_selection(&mut r, &["6a2fcf86-d1ec-427e-a008-42b375027ce1".into()], 2).unwrap();
    let changed = calendar::selected_ics_events(
        &[r],
        &["6a2fcf86-d1ec-427e-a008-42b375027ce1".into()],
        "Europe/Vienna",
        None,
        None,
    )
    .unwrap();
    assert_eq!(changed[0].0, first[0].0);
    let text = calendar::ics(&changed, chrono::Utc::now()).unwrap();
    assert_eq!(text.matches("BEGIN:VEVENT").count(), 1);
    assert!(text
        .replace("\r\n ", "")
        .contains("Handtuch\\, Wasser\\; Tasche\\\\bereit\\n  Zweite Zeile"));
}

#[test]
fn approved_history_suggests_only_allowed_fields_from_the_same_clinic() {
    let mut old = complete("old");
    old.metadata.clinic = "A".into();
    old.metadata.preparation = "Gedruckter Testhinweis".into();
    old.therapist = "Testperson".into();
    old.location = "2".into();
    let record = ImportRecord {
        id: "old".into(),
        schedule_id: "s".into(),
        calendar_id: "c".into(),
        external_id: Some("e".into()),
        approved: calendar::event_values(&old, "Europe/Vienna", None).unwrap(),
        status: "saved".into(),
        operation_id: "op".into(),
    };
    let mut r = run();
    let mut missing = complete("new");
    missing.date = None;
    missing.start = None;
    missing.end = None;
    missing.metadata.clinic = "B".into();
    r.appointments = vec![missing];
    review::suggest(&mut r, &[], std::slice::from_ref(&record));
    assert!(r.appointments[0].suggestions.is_empty());
    r.appointments[0].metadata.clinic = "A".into();
    review::suggest(&mut r, &[], &[record]);
    assert_eq!(r.appointments[0].suggestions.len(), 4);
    assert!(r.appointments[0]
        .suggestions
        .iter()
        .all(|s| review::COMPLETABLE.contains(&s.field.as_str()) && s.status == "pending"));
    assert_eq!(r.appointments[0].date, None);
    assert_eq!(r.appointments[0].start, None);
    assert_eq!(r.appointments[0].duration_minutes, None);
    let mut forged = r.appointments[0].clone();
    let suggested = forged
        .suggestions
        .iter_mut()
        .find(|s| s.field == "duration_minutes")
        .unwrap();
    suggested.status = "accepted".into();
    suggested.value = serde_json::json!(90);
    forged.duration_minutes = Some(90);
    assert!(review::edit(Some(&r.appointments[0]), forged).is_err());
}

#[test]
fn populated_uncertain_fields_block_only_the_affected_appointment_and_cannot_be_erased() {
    let mut r = run();
    let ready = complete("ready");
    let mut uncertain = complete("uncertain");
    uncertain.location = "Raum 107 Fr. A. Belvara".into();
    uncertain.fields.insert(
        "location".into(),
        FieldAssessment {
            state: PrintedState::Contradictory,
            frame: "page".into(),
            polygon: geometry::rect(600., 100., 200., 40.),
            reasons: vec!["Text überquert die Namensspalte".into()],
            ..Default::default()
        },
    );
    r.appointments = vec![ready, uncertain.clone()];
    review::approve_selection(&mut r, &["ready".into()], 100).unwrap();
    assert!(review::approved(&r.appointments[0]));
    assert!(review::approve_selection(&mut r, &["uncertain".into()], 101).is_err());
    let mut erased = uncertain.clone();
    erased.fields.clear();
    erased.issues.clear();
    let guarded = review::edit(Some(&uncertain), erased).unwrap();
    assert!(!review::field_problems(&guarded).is_empty());
    assert!(calendar::event_values(&guarded, "Europe/Vienna", None).is_err());
    let mut confirmed = guarded.clone();
    confirmed.location = "Raum 107".into();
    let field = confirmed.fields.get_mut("location").unwrap();
    field.state = PrintedState::Legible;
    field.confirmed_value = Some(serde_json::json!("Raum 107"));
    field.confirmed_at = Some(102);
    let mut confirmed = review::edit(Some(&guarded), confirmed).unwrap();
    assert!(review::field_problems(&confirmed).is_empty());
    confirmed.location = "Raum 701".into();
    assert!(!review::field_problems(&confirmed).is_empty());
}

#[test]
fn blank_printed_cell_requires_confirmation_but_never_a_fabricated_name() {
    let mut a = complete("blank");
    a.fields.insert(
        "therapist".into(),
        FieldAssessment {
            state: PrintedState::Cropped,
            reasons: vec!["rechte Spalte fehlt".into()],
            ..Default::default()
        },
    );
    assert!(calendar::event_values(&a, "Europe/Vienna", None).is_err());
    let mut edited = a.clone();
    let f = edited.fields.get_mut("therapist").unwrap();
    f.state = PrintedState::NotPrinted;
    f.confirmed_at = Some(1);
    f.confirmed_value = Some(serde_json::json!(""));
    let edited = review::edit(Some(&a), edited).unwrap();
    assert!(calendar::event_values(&edited, "Europe/Vienna", None).is_ok());
    assert!(edited.therapist.is_empty());
}

#[test]
fn recurring_calendar_updates_remain_protected_and_partial_checks_do_not_remove() {
    let values = calendar::event_values(&complete("bound"), "Europe/Vienna", None).unwrap();
    let mut op = CalendarOperation {
        id: "bound".into(),
        kind: "update".into(),
        calendar_id: "calendar".into(),
        external_id: Some("external".into()),
        before: Some(values.clone()),
        after: Some(values),
        requires_resolution: false,
        reason: "changed".into(),
    };
    calendar::protect_recurring(std::slice::from_mut(&mut op), &["bound".into()]);
    assert_eq!(op.kind, "protected");
    assert!(op.requires_resolution);
    let dir = tempfile::tempdir().unwrap();
    let store = Store::open(dir.path()).unwrap();
    assert!(store.begin_operation("schedule", &op).is_err());
}

#[test]
fn explicitly_confirmed_absent_field_survives_rereading() {
    let mut r = run();
    let mut a = complete("a");
    a.fields.insert(
        "location".into(),
        FieldAssessment {
            state: PrintedState::NotPrinted,
            confirmed_value: Some(serde_json::json!("")),
            confirmed_at: Some(100),
            ..Default::default()
        },
    );
    assert!(review::field_confirmed(&a, "location"));
    r.appointments = vec![a];
    refinement::apply_readings(
        &mut r,
        &[refinement::Reading {
            appointment_id: "a".into(),
            field: "location".into(),
            value: serde_json::json!("Raum 2"),
            evidence: vec!["vision-observation".into()],
            attempt: "vision-crop".into(),
        }],
    )
    .unwrap();
    assert!(r.appointments[0].location.is_empty());
    assert!(review::field_confirmed(&r.appointments[0], "location"));
}

#[test]
fn completely_failed_reader_pass_is_not_reported_as_complete() {
    let temp = tempfile::tempdir().unwrap();
    let mut r = run();
    r.appointments[0].location.clear();
    let original = image::RgbImage::new(2500, 3500);
    refinement::refine_with_reader(
        &mut r,
        temp.path(),
        &std::sync::atomic::AtomicBool::new(false),
        // This asserts failure reporting, not image-processing throughput. Leave
        // enough time for instrumented/debug builds and contended CI machines.
        std::time::Instant::now() + std::time::Duration::from_secs(60),
        Some(&original),
        &mut |_, _, _, _, _| {
            Err(reha_core::Error::Invalid(
                "Simulated native reader failure".into(),
            ))
        },
    )
    .unwrap();
    assert!(!r.refinement_attempts.is_empty());
    assert!(r
        .refinement_attempts
        .iter()
        .all(|attempt| attempt.status == "failed"));
    assert_eq!(r.stages.last().unwrap().status, "failed");
    assert!(!r.appointments.is_empty());
}

#[test]
fn field_confirmation_alone_keeps_a_row_missed_by_a_new_detector() {
    let mut previous = run();
    previous.appointments.truncate(1);
    let row = &mut previous.appointments[0];
    row.location.clear();
    row.approval = None;
    row.origins.clear();
    let field = row.fields.get_mut("location").unwrap();
    field.state = PrintedState::NotPrinted;
    field.confirmed_at = Some(1);
    field.confirmed_value = Some(serde_json::json!(""));
    assert!(review::field_confirmed(row, "location"));
    let mut next = previous.clone();
    next.appointments.clear();
    refinement::preserve_review(&previous, &mut next).unwrap();
    assert_eq!(next.appointments.len(), 1);
    assert!(next.appointments[0].location.is_empty());
    assert!(next.appointments[0]
        .issues
        .iter()
        .any(|issue| issue.code == "retained_review" && issue.blocking));
}
