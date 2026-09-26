//! Synthetic retained-data fixtures exercise both shell adapters' shared service.
use reha_core::{
    contracts::*,
    service::{self, Application},
    store::Store,
};
use std::sync::Arc;
fn fixture() -> (tempfile::TempDir, Arc<Application>, PipelineRun) {
    let dir = tempfile::tempdir().unwrap();
    let mut run: PipelineRun =
        serde_json::from_str(include_str!("../../../tests/fixtures/sample-run.json")).unwrap();
    reha_core::review::migrate(&mut run).unwrap();
    let store = Store::open(dir.path()).unwrap();
    store.save_run(&run).unwrap();
    (dir, Arc::new(Application::new(store, "models".into())), run)
}
#[test]
fn revision_check_is_atomic_and_stale_approval_cannot_return() {
    let (_dir, app, run) = fixture();
    let revision = service::scan::revision(&run);
    let mut appointments = run.appointments.clone();
    appointments[0].title = "Neuere Änderung".into();
    let next = service::scan::save_review(
        &app,
        run.document.id.clone(),
        appointments,
        false,
        false,
        None,
        Some(revision.clone()),
    )
    .unwrap();
    assert_ne!(revision, service::scan::revision(&next));
    let stale = service::scan::save_review(
        &app,
        run.document.id.clone(),
        run.appointments.clone(),
        true,
        true,
        None,
        Some(revision),
    );
    assert_eq!(stale.unwrap_err(), "stale_revision");
    let saved = app
        .store
        .lock()
        .unwrap()
        .load_run(&run.document.id)
        .unwrap();
    assert_eq!(saved.appointments[0].title, "Neuere Änderung");
    assert!(saved.appointments[0].approval.is_none());
}
#[test]
fn reopen_preserves_canonical_hash_schema_and_unknown_preferences() {
    let (dir, app, run) = fixture();
    let settings = serde_json::json!({"timezone":"Europe/Vienna","reminder":10,"future_preference":{"keep":true}});
    service::settings::settings_value(&app, Some(settings.clone())).unwrap();
    let expected = service::scan::revision(&run);
    drop(app);
    let store = Store::open(dir.path()).unwrap();
    assert_eq!(
        expected,
        service::scan::revision(&store.load_run(&run.document.id).unwrap())
    );
    assert_eq!(
        store
            .connection
            .query_row("PRAGMA user_version", [], |r| r.get::<_, u32>(0))
            .unwrap(),
        reha_core::store::STORE_VERSION
    );
    assert_eq!(
        serde_json::from_str::<serde_json::Value>(&store.setting("preferences").unwrap().unwrap())
            .unwrap(),
        settings
    );
}
#[test]
fn calendar_journal_and_identities_survive_service_reopen() {
    let (dir, app, run) = fixture();
    let op = CalendarOperation {
        kind: "create".into(),
        id: uuid::Uuid::new_v4().to_string(),
        calendar_id: "synthetic".into(),
        external_id: None,
        before: None,
        after: Some(EventValues {
            title: "Synthetic appointment".into(),
            start_utc: "2026-09-11T08:00:00Z".into(),
            end_utc: "2026-09-11T08:30:00Z".into(),
            timezone: "Europe/Vienna".into(),
            location: "Test".into(),
            notes: String::new(),
            reminder_minutes: Some(10),
        }),
        requires_resolution: false,
        reason: String::new(),
    };
    let attempt = {
        let store = app.store.lock().unwrap();
        store
            .bind_schedule(&run.document.id, "existing-schedule", "fingerprint")
            .unwrap();
        store.begin_operation("existing-schedule", &op).unwrap()
    };
    drop(app);
    let mut store = Store::open(dir.path()).unwrap();
    assert_eq!(
        store.begin_operation("existing-schedule", &op).unwrap(),
        attempt
    );
    store
        .finish_operation(
            &attempt,
            &CalendarResult {
                id: op.id,
                status: "uncertain".into(),
                external_id: None,
                error: None,
            },
        )
        .unwrap();
    assert_eq!(store.pending().unwrap().len(), 1);
    assert_eq!(
        store.list_scans().unwrap()[0].schedule_id.as_deref(),
        Some("existing-schedule")
    );
    assert!(store.records(None).unwrap().is_empty());
}

#[test]
fn deletion_and_retention_cannot_remove_an_active_scan() {
    let (_dir, app, run) = fixture();
    app.cancel.lock().unwrap().insert(
        run.document.id.clone(),
        Arc::new(std::sync::atomic::AtomicBool::new(false)),
    );
    assert!(service::scan::delete_scan(&app, run.document.id.clone()).is_err());
    assert!(service::settings::maintenance(&app).is_err());
    assert!(app.store.lock().unwrap().load_run(&run.document.id).is_ok());
    app.cancel.lock().unwrap().clear();
    let admission = app.lifecycle_lock.try_lock().unwrap();
    assert!(service::scan::delete_scan(&app, run.document.id.clone()).is_err());
    drop(admission);
    service::scan::delete_scan(&app, run.document.id.clone()).unwrap();
    assert!(app
        .store
        .lock()
        .unwrap()
        .load_run(&run.document.id)
        .is_err());
}
