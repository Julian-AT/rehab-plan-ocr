use reha_core::{
    contracts::{
        Appointment, CalendarOperation, CalendarResult, EventValues, PipelineRun, SCHEMA_VERSION,
    },
    review::values_hash,
    service::{self, draft, Application, Platform},
    store::{bookkeeping, Store},
};
use serde_json::{json, Value};
use std::{
    collections::BTreeMap,
    path::PathBuf,
    sync::{Arc, Mutex},
};

/// The platform owns its event state independently of the application so tests
/// can really close and reopen SQLite without resetting the external calendar.
struct Calendar {
    database: PathBuf,
    current: Mutex<BTreeMap<String, EventValues>>,
    writes: Mutex<usize>,
    fail_bookkeeping: Mutex<bool>,
    fail_once: Mutex<Option<String>>,
}

impl Platform for Calendar {
    fn progress(&self, _: Value) {}

    fn call(&self, command: &str, args: Value) -> service::Response<Value> {
        match command {
            "snapshot" => {
                Ok(json!({"current": *self.current.lock().unwrap(), "protected_ids": []}))
            }
            "agenda" => Ok(Value::Null),
            "apply" => {
                // Completed operations must never be sent back to the platform,
                // including as recovery-only calls, to repair local markings.
                assert_eq!(args["recovery_only"], false);
                let op: CalendarOperation =
                    serde_json::from_value(args["operation"].clone()).unwrap();
                let mut failure = self.fail_once.lock().unwrap();
                if failure.as_ref() == Some(&op.id) {
                    *failure = None;
                    return Ok(json!({"id": op.id, "status": "failed", "external_id": null,
                        "error": "injected failure before calendar effect"}));
                }
                drop(failure);
                let mut current = self.current.lock().unwrap();
                if op.kind != "create" {
                    assert_eq!(current.get(&op.id), op.before.as_ref());
                }
                if let Some(after) = op.after {
                    current.insert(op.id.clone(), after);
                } else {
                    current.remove(&op.id);
                }
                *self.writes.lock().unwrap() += 1;
                if *self.fail_bookkeeping.lock().unwrap() {
                    // Injection occurs after the external effect. All proposal,
                    // acceptance and pre-write journal persistence has succeeded.
                    rusqlite::Connection::open(&self.database)
                        .unwrap()
                        .execute_batch(
                            "CREATE TRIGGER IF NOT EXISTS fail_calendar_bookkeeping
                             BEFORE UPDATE OF run ON scans
                             BEGIN SELECT RAISE(ABORT, 'injected post-write bookkeeping failure'); END;",
                        )
                        .unwrap();
                }
                Ok(json!({
                    "id": op.id, "status": "saved", "error": null,
                    "external_id": if op.kind == "remove" { None } else { Some(format!("external-{}", op.id)) }
                }))
            }
            _ => panic!("unexpected platform command: {command}"),
        }
    }
}

fn fixture() -> (tempfile::TempDir, Arc<Application>, Arc<Calendar>, String) {
    let root = tempfile::tempdir().unwrap();
    let mut run: PipelineRun = serde_json::from_str(include_str!(
        "../../../../ml/evaluation/fixtures/sample-run.json"
    ))
    .unwrap();
    run.schema_version = SCHEMA_VERSION;
    run.document.schema_version = SCHEMA_VERSION;
    run.appointments = (0..3)
        .map(|index| {
            let mut row = Appointment::empty(uuid::Uuid::new_v4().to_string());
            row.title = format!("Synthetische Therapie {index}");
            row.date = Some("2026-09-11".into());
            row.start = Some(format!("{:02}:00", 8 + index));
            row.end = Some(format!("{:02}:30", 8 + index));
            row
        })
        .collect();
    run.review_confirmed = false;
    let store = Store::open(root.path()).unwrap();
    store.save_run(&run).unwrap();
    let state = Arc::new(Application::new(store, "missing".into()));
    let calendar = Arc::new(Calendar {
        database: root.path().join("ledger.sqlite"),
        current: Mutex::new(BTreeMap::new()),
        writes: Mutex::new(0),
        fail_bookkeeping: Mutex::new(false),
        fail_once: Mutex::new(None),
    });
    (root, state, calendar, run.document.id)
}

async fn import(
    state: &Arc<Application>,
    calendar: &Arc<Calendar>,
    document: &str,
) -> draft::SaveOutcome {
    let preview = draft::preview(
        calendar.clone(),
        state,
        document.into(),
        "destination".into(),
        "Europe/Vienna".into(),
        None,
    )
    .await
    .unwrap();
    draft::accept_and_save(
        calendar.clone(),
        state,
        preview.proposal.unwrap().token,
        preview.assessment.ready_ids,
        false,
    )
    .await
    .expect("a failed local marking must retain the durable calendar result")
}

fn assert_saved_with_recovery(results: &[CalendarResult], state: &Application) {
    assert_eq!(results.len(), 3);
    assert!(results.iter().all(|result| {
        result.status == "saved"
            && result
                .maintenance_warnings
                .iter()
                .any(|warning| warning == bookkeeping::WARNING)
    }));
    let store = state.store.lock().unwrap();
    assert!(store.pending().unwrap().is_empty());
    assert_eq!(bookkeeping::pending_count(&store).unwrap(), 1);
    assert!(store
        .batches()
        .unwrap()
        .iter()
        .flat_map(|batch| &batch.operations)
        .all(|operation| operation.status == "saved"));
}

fn remove_failure(state: &Application, calendar: &Calendar) {
    *calendar.fail_bookkeeping.lock().unwrap() = false;
    state
        .store
        .lock()
        .unwrap()
        .connection
        .execute_batch("DROP TRIGGER fail_calendar_bookkeeping")
        .unwrap();
}

async fn reconcile(state: &Arc<Application>, calendar: &Arc<Calendar>) {
    assert!(
        service::calendar::reconcile_calendar(calendar.clone(), state)
            .await
            .unwrap()
            .is_empty()
    );
    assert_eq!(
        bookkeeping::pending_count(&state.store.lock().unwrap()).unwrap(),
        0
    );
}

#[tokio::test]
async fn saved_import_recovers_local_marks_after_restart_without_repeating_writes() {
    let (root, state, calendar, document) = fixture();
    *calendar.fail_bookkeeping.lock().unwrap() = true;
    let outcome = import(&state, &calendar, &document).await;
    assert_saved_with_recovery(&outcome.results, &state);
    assert!(state
        .store
        .lock()
        .unwrap()
        .load_run(&document)
        .unwrap()
        .appointments
        .iter()
        .all(|row| row.calendar_saved_hash.is_none()));
    assert_eq!(*calendar.writes.lock().unwrap(), 3);
    remove_failure(&state, &calendar);
    drop(state);

    let state = Arc::new(Application::new(
        Store::open(root.path()).unwrap(),
        "missing".into(),
    ));
    reconcile(&state, &calendar).await;
    assert!(state
        .store
        .lock()
        .unwrap()
        .load_run(&document)
        .unwrap()
        .appointments
        .iter()
        .all(|row| row.calendar_saved_hash.as_ref() == Some(&values_hash(row))));
    reconcile(&state, &calendar).await;
    assert_eq!(*calendar.writes.lock().unwrap(), 3);
    assert_eq!(calendar.current.lock().unwrap().len(), 3);
}

#[tokio::test]
async fn restart_before_first_calendar_effect_preserves_the_local_marking_intent() {
    let (root, state, calendar, document) = fixture();
    {
        let mut store = state.store.lock().unwrap();
        let run = store.load_run(&document).unwrap();
        let operations: Vec<_> = run
            .appointments
            .iter()
            .enumerate()
            .map(|(index, row)| CalendarOperation {
                kind: "create".into(),
                id: row.id.clone(),
                calendar_id: "destination".into(),
                external_id: None,
                before: None,
                after: Some(EventValues {
                    title: row.title.clone(),
                    start_utc: format!("2026-09-11T{:02}:00:00Z", 6 + index),
                    end_utc: format!("2026-09-11T{:02}:30:00Z", 6 + index),
                    timezone: "Europe/Vienna".into(),
                    location: String::new(),
                    notes: String::new(),
                    reminder_minutes: None,
                }),
                requires_resolution: false,
                reason: "Synthetic accepted plan".into(),
            })
            .collect();
        let batch = store
            .begin_batch(&[document.clone()], "synthetic-schedule", &operations, None)
            .unwrap();
        assert_eq!(batch.operations.len(), 3);
        assert!(batch
            .operations
            .iter()
            .all(|operation| operation.status == "queued"));
        assert_eq!(bookkeeping::pending_count(&store).unwrap(), 1);
        assert_eq!(store.pending().unwrap().len(), 3);
    }
    assert_eq!(*calendar.writes.lock().unwrap(), 0);
    drop(state);

    let state = Arc::new(Application::new(
        Store::open(root.path()).unwrap(),
        "missing".into(),
    ));
    let results = service::calendar::reconcile_calendar(calendar.clone(), &state)
        .await
        .unwrap();
    assert_eq!(results.len(), 3);
    assert!(results.iter().all(|result| result.status == "saved"));
    assert!(state
        .store
        .lock()
        .unwrap()
        .load_run(&document)
        .unwrap()
        .appointments
        .iter()
        .all(|row| row.calendar_saved_hash.as_ref() == Some(&values_hash(row))));
    reconcile(&state, &calendar).await;
    assert_eq!(*calendar.writes.lock().unwrap(), 3);
}

#[tokio::test]
async fn failed_bookkeeping_intent_rolls_back_acceptance_and_queued_operations_before_effects() {
    let (_root, state, calendar, document) = fixture();
    let before: String;
    {
        let store = state.store.lock().unwrap();
        before = store
            .connection
            .query_row("SELECT run FROM scans WHERE id=?1", [&document], |row| {
                row.get(0)
            })
            .unwrap();
        store
            .connection
            .execute_batch(
                "CREATE TRIGGER fail_bookkeeping_intent BEFORE INSERT ON settings
             WHEN NEW.key GLOB 'calendar_bookkeeping:*'
             BEGIN SELECT RAISE(ABORT, 'injected bookkeeping intent failure'); END;",
            )
            .unwrap();
    }
    let preview = draft::preview(
        calendar.clone(),
        &state,
        document.clone(),
        "destination".into(),
        "Europe/Vienna".into(),
        None,
    )
    .await
    .unwrap();
    assert!(draft::accept_and_save(
        calendar.clone(),
        &state,
        preview.proposal.unwrap().token,
        preview.assessment.ready_ids,
        false
    )
    .await
    .is_err());
    assert_eq!(*calendar.writes.lock().unwrap(), 0);
    assert!(calendar.current.lock().unwrap().is_empty());
    let store = state.store.lock().unwrap();
    assert!(store.batches().unwrap().is_empty());
    assert!(store.pending().unwrap().is_empty());
    assert_eq!(bookkeeping::pending_count(&store).unwrap(), 0);
    for table in ["operations", "plan_acceptances"] {
        let count: usize = store
            .connection
            .query_row(&format!("SELECT count(*) FROM {table}"), [], |row| {
                row.get(0)
            })
            .unwrap();
        assert_eq!(count, 0, "{table} must roll back with the local intent");
    }
    let after: String = store
        .connection
        .query_row("SELECT run FROM scans WHERE id=?1", [&document], |row| {
            row.get(0)
        })
        .unwrap();
    assert_eq!(
        after, before,
        "failed acceptance cannot alter the retained scan"
    );
}

#[tokio::test]
async fn saved_undo_recovers_local_marks_after_restart_without_repeating_removals() {
    let (root, state, calendar, document) = fixture();
    let outcome = import(&state, &calendar, &document).await;
    assert!(state
        .store
        .lock()
        .unwrap()
        .load_run(&document)
        .unwrap()
        .appointments
        .iter()
        .all(|row| row.calendar_saved_hash.is_some()));
    let preview = service::undo::prepare(calendar.clone(), &state, outcome.batch_id)
        .await
        .unwrap();
    *calendar.fail_bookkeeping.lock().unwrap() = true;
    let results =
        service::calendar::approve_calendar(calendar.clone(), &state, preview.token, true)
            .await
            .expect("a failed local marking must retain the durable undo result");
    assert_saved_with_recovery(&results, &state);
    assert!(state
        .store
        .lock()
        .unwrap()
        .load_run(&document)
        .unwrap()
        .appointments
        .iter()
        .all(|row| row.calendar_saved_hash.is_some()));
    assert!(calendar.current.lock().unwrap().is_empty());
    remove_failure(&state, &calendar);
    drop(state);

    let state = Arc::new(Application::new(
        Store::open(root.path()).unwrap(),
        "missing".into(),
    ));
    reconcile(&state, &calendar).await;
    assert!(state
        .store
        .lock()
        .unwrap()
        .load_run(&document)
        .unwrap()
        .appointments
        .iter()
        .all(|row| row.calendar_saved_hash.is_none()));
    reconcile(&state, &calendar).await;
    assert_eq!(*calendar.writes.lock().unwrap(), 6);
}

#[tokio::test]
async fn failed_local_reconciliation_reports_the_remaining_repair_without_rewriting_calendar() {
    let (_root, state, calendar, document) = fixture();
    *calendar.fail_bookkeeping.lock().unwrap() = true;
    let outcome = import(&state, &calendar, &document).await;
    assert_saved_with_recovery(&outcome.results, &state);
    let error = service::calendar::reconcile_calendar(calendar.clone(), &state)
        .await
        .expect_err(
            "an unresolved local repair must not be presented as successful reconciliation",
        );
    assert!(error
        .to_string()
        .contains("Bestätigte Kalenderänderungen bleiben erhalten"));
    assert_saved_with_recovery(&outcome.results, &state);
    assert_eq!(*calendar.writes.lock().unwrap(), 3);
    remove_failure(&state, &calendar);
    reconcile(&state, &calendar).await;
    assert_eq!(*calendar.writes.lock().unwrap(), 3);
}

#[tokio::test]
async fn recovery_does_not_mark_changed_values_or_resurrect_removed_appointments() {
    let (root, state, calendar, document) = fixture();
    *calendar.fail_bookkeeping.lock().unwrap() = true;
    let outcome = import(&state, &calendar, &document).await;
    assert_saved_with_recovery(&outcome.results, &state);
    remove_failure(&state, &calendar);
    let removed;
    {
        let store = state.store.lock().unwrap();
        let mut run = store.load_run(&document).unwrap();
        run.appointments[0].title = "Spätere bestätigte Korrektur".into();
        removed = run.appointments.pop().unwrap().id;
        store.save_run(&run).unwrap();
    }
    drop(state);

    let state = Arc::new(Application::new(
        Store::open(root.path()).unwrap(),
        "missing".into(),
    ));
    reconcile(&state, &calendar).await;
    let run = state.store.lock().unwrap().load_run(&document).unwrap();
    assert_eq!(run.appointments.len(), 2);
    assert!(!run.appointments.iter().any(|row| row.id == removed));
    assert_eq!(run.appointments[0].title, "Spätere bestätigte Korrektur");
    assert!(run.appointments[0].calendar_saved_hash.is_none());
    assert_eq!(
        run.appointments[1].calendar_saved_hash.as_ref(),
        Some(&values_hash(&run.appointments[1]))
    );
    assert_eq!(*calendar.writes.lock().unwrap(), 3);
}

#[tokio::test]
async fn recovery_does_not_resurrect_expired_document_contents() {
    let (root, state, calendar, document) = fixture();
    *calendar.fail_bookkeeping.lock().unwrap() = true;
    let outcome = import(&state, &calendar, &document).await;
    assert_saved_with_recovery(&outcome.results, &state);
    remove_failure(&state, &calendar);
    state
        .store
        .lock()
        .unwrap()
        .delete_sources(&[document.clone()])
        .unwrap();
    drop(state);

    let state = Arc::new(Application::new(
        Store::open(root.path()).unwrap(),
        "missing".into(),
    ));
    reconcile(&state, &calendar).await;
    let store = state.store.lock().unwrap();
    assert!(store.load_run(&document).is_err());
    let retained: Option<String> = store
        .connection
        .query_row("SELECT run FROM scans WHERE id=?1", [&document], |row| {
            row.get(0)
        })
        .unwrap();
    assert!(retained.is_none());
    assert!(!store.scan_dir(&document).unwrap().exists());
    assert_eq!(*calendar.writes.lock().unwrap(), 3);
}

#[tokio::test]
async fn keeping_a_failed_undo_operation_retires_its_local_bookkeeping() {
    let (_root, state, calendar, document) = fixture();
    let outcome = import(&state, &calendar, &document).await;
    let kept = state
        .store
        .lock()
        .unwrap()
        .load_run(&document)
        .unwrap()
        .appointments[0]
        .calendar_event_id
        .clone()
        .unwrap();
    *calendar.fail_once.lock().unwrap() = Some(kept.clone());
    let preview = service::undo::prepare(calendar.clone(), &state, outcome.batch_id.clone())
        .await
        .unwrap();
    let results =
        service::calendar::approve_calendar(calendar.clone(), &state, preview.token, true)
            .await
            .unwrap();
    assert_eq!(
        results
            .iter()
            .filter(|result| result.status == "saved")
            .count(),
        2
    );
    assert_eq!(
        results
            .iter()
            .filter(|result| result.status == "failed")
            .count(),
        1
    );
    let retry = service::undo::prepare(calendar.clone(), &state, outcome.batch_id)
        .await
        .unwrap();
    assert_eq!(retry.operations.len(), 1);
    let kept_proposal =
        service::calendar::resolve_proposal(&state, retry.token, kept.clone(), "keep".into())
            .unwrap();
    assert!(service::calendar::approve_calendar(
        calendar.clone(),
        &state,
        kept_proposal.token,
        true
    )
    .await
    .unwrap()
    .is_empty());
    reconcile(&state, &calendar).await;
    let store = state.store.lock().unwrap();
    let run = store.load_run(&document).unwrap();
    assert!(run.appointments.iter().all(|row| {
        row.calendar_saved_hash.is_some() == (row.calendar_event_id.as_ref() == Some(&kept))
    }));
    assert!(store
        .batches()
        .unwrap()
        .iter()
        .flat_map(|batch| &batch.operations)
        .any(|operation| operation.status == "skipped"));
    assert_eq!(calendar.current.lock().unwrap().len(), 1);
    assert_eq!(*calendar.writes.lock().unwrap(), 5);
}
