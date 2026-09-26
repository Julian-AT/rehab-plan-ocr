use reha_core::{
    contracts::*,
    service::{self, Application, Platform},
    store::Store,
};
use serde_json::{json, Value};
use std::{
    collections::BTreeMap,
    sync::{Arc, Mutex},
};

struct Calendar {
    values: Mutex<BTreeMap<String, EventValues>>,
    writes: Mutex<usize>,
    uncertain: bool,
    fail_once: Mutex<Option<String>>,
    overlaps: Mutex<Option<Vec<CalendarOverlap>>>,
}
impl Platform for Calendar {
    fn progress(&self, _: Value) {}
    fn overlaps(
        &self,
        _: BTreeMap<String, EventValues>,
        _: Vec<String>,
    ) -> service::Response<Option<Vec<CalendarOverlap>>> {
        Ok(self.overlaps.lock().unwrap().clone())
    }
    fn call(&self, command: &str, args: Value) -> service::Response<Value> {
        match command {
            "snapshot" => Ok(json!({"current":*self.values.lock().unwrap(),"protected_ids":[]})),
            "agenda" => Ok(Value::Null),
            "apply" => {
                let op: CalendarOperation =
                    serde_json::from_value(args["operation"].clone()).unwrap();
                let mut current = self.values.lock().unwrap();
                let mut fail_once = self.fail_once.lock().unwrap();
                if fail_once.as_ref() == Some(&op.id) {
                    *fail_once = None;
                    return Ok(
                        json!({"id":op.id,"status":"failed","external_id":null,"error":"Temporary failure before any write"}),
                    );
                }
                if self.uncertain {
                    return Err("connection lost".into());
                }
                if args["recovery_only"] == true {
                    return Ok(
                        json!({"id":op.id,"status":"uncertain","external_id":null,"error":null}),
                    );
                }
                if op.kind != "create" && current.get(&op.id) != op.before.as_ref() {
                    return Err("stale".into());
                }
                *self.writes.lock().unwrap() += 1;
                if let Some(after) = op.after {
                    current.insert(op.id.clone(), after);
                } else {
                    current.remove(&op.id);
                }
                Ok(
                    json!({"id":op.id,"status":"saved","external_id":if op.kind=="remove" {None} else {Some("external")},"error":null}),
                )
            }
            _ => Err("unknown".into()),
        }
    }
}
fn values(title: &str) -> EventValues {
    EventValues {
        title: title.into(),
        start_utc: "2026-09-11T08:00:00Z".into(),
        end_utc: "2026-09-11T08:30:00Z".into(),
        timezone: "Europe/Vienna".into(),
        location: "".into(),
        notes: "".into(),
        reminder_minutes: None,
    }
}
fn operation(
    kind: &str,
    before: Option<EventValues>,
    after: Option<EventValues>,
) -> CalendarOperation {
    CalendarOperation {
        kind: kind.into(),
        id: uuid::Uuid::new_v4().to_string(),
        calendar_id: "destination".into(),
        external_id: Some("external".into()),
        before,
        after,
        requires_resolution: false,
        reason: "".into(),
    }
}
fn setup(
    ops: Vec<CalendarOperation>,
    uncertain: bool,
) -> (tempfile::TempDir, Arc<Application>, Arc<Calendar>, String) {
    let dir = tempfile::tempdir().unwrap();
    let mut store = Store::open(dir.path()).unwrap();
    let batch = store
        .begin_batch(&[uuid::Uuid::new_v4().to_string()], "schedule", &ops, None)
        .unwrap();
    assert_eq!(
        store.pending().unwrap().len(),
        ops.len(),
        "The complete intent is durable before any effects"
    );
    for entry in &batch.operations {
        store
            .finish_operation(
                &entry.attempt_id,
                &CalendarResult {
                    id: entry.operation.id.clone(),
                    status: "saved".into(),
                    external_id: Some("external".into()),
                    error: None,
                },
            )
            .unwrap();
    }
    let platform = Arc::new(Calendar {
        values: Mutex::new(
            ops.iter()
                .filter_map(|op| op.after.clone().map(|v| (op.id.clone(), v)))
                .collect(),
        ),
        writes: Mutex::new(0),
        uncertain,
        fail_once: Mutex::new(None),
        overlaps: Mutex::new(None),
    });
    (
        dir,
        Arc::new(Application::new(store, "missing".into())),
        platform,
        batch.id,
    )
}

#[tokio::test]
async fn retry_failed_undo_does_not_repeat_successful_inverse_operations() {
    let first = operation("create", None, Some(values("First")));
    let second = operation("create", None, Some(values("Second")));
    let (_dir, app, calendar, batch) = setup(vec![first.clone(), second.clone()], false);
    *calendar.fail_once.lock().unwrap() = Some(first.id.clone());
    let preview = service::undo::prepare(calendar.clone(), &app, batch.clone())
        .await
        .unwrap();
    let results = service::calendar::approve_calendar(calendar.clone(), &app, preview.token, true)
        .await
        .unwrap();
    assert_eq!(results.iter().filter(|r| r.status == "saved").count(), 1);
    assert_eq!(results.iter().filter(|r| r.status == "failed").count(), 1);
    assert_eq!(*calendar.writes.lock().unwrap(), 1);
    let preview = service::undo::prepare(calendar.clone(), &app, batch.clone())
        .await
        .unwrap();
    assert_eq!(preview.operations.len(), 1);
    assert_eq!(preview.operations[0].id, first.id);
    let results = service::calendar::approve_calendar(calendar.clone(), &app, preview.token, true)
        .await
        .unwrap();
    assert_eq!(results.len(), 1);
    assert_eq!(results[0].status, "saved");
    assert_eq!(*calendar.writes.lock().unwrap(), 2);
    assert!(calendar.values.lock().unwrap().is_empty());
    assert_eq!(app.store.lock().unwrap().batches().unwrap().len(), 2);
    assert!(service::undo::prepare(calendar, &app, batch).await.is_err());
}

#[tokio::test]
async fn whole_batch_undo_removes_creates_restores_updates_and_preserves_unrelated_events() {
    let create = operation("create", None, Some(values("New")));
    let update = operation("update", Some(values("Before")), Some(values("After")));
    let (_dir, app, calendar, batch) = setup(vec![create.clone(), update.clone()], false);
    calendar
        .values
        .lock()
        .unwrap()
        .insert("unrelated".into(), values("Keep"));
    let proposal = service::undo::prepare(calendar.clone(), &app, batch.clone())
        .await
        .unwrap();
    assert!(service::calendar::approve_calendar(
        calendar.clone(),
        &app,
        proposal.token.clone(),
        false
    )
    .await
    .is_err());
    let results = service::calendar::approve_calendar(calendar.clone(), &app, proposal.token, true)
        .await
        .unwrap();
    assert_eq!(results.iter().filter(|r| r.status == "saved").count(), 2);
    {
        let current = calendar.values.lock().unwrap();
        assert!(!current.contains_key(&create.id));
        assert_eq!(current[&update.id], values("Before"));
        assert_eq!(current["unrelated"], values("Keep"));
    }
    assert!(service::undo::prepare(calendar, &app, batch).await.is_err());
    assert_eq!(app.store.lock().unwrap().batches().unwrap().len(), 2);
}

#[tokio::test]
async fn external_edit_requires_keep_and_cannot_be_overwritten() {
    let create = operation("create", None, Some(values("Original")));
    let (_dir, app, calendar, batch) = setup(vec![create.clone()], false);
    calendar
        .values
        .lock()
        .unwrap()
        .insert(create.id.clone(), values("Externally edited"));
    let proposal = service::undo::prepare(calendar.clone(), &app, batch)
        .await
        .unwrap();
    assert!(proposal.operations[0].requires_resolution);
    assert!(service::calendar::resolve_proposal(
        &app,
        proposal.token.clone(),
        create.id.clone(),
        "paper".into()
    )
    .is_err());
    let proposal =
        service::calendar::resolve_proposal(&app, proposal.token, create.id, "keep".into())
            .unwrap();
    service::calendar::approve_calendar(calendar.clone(), &app, proposal.token, true)
        .await
        .unwrap();
    assert_eq!(*calendar.writes.lock().unwrap(), 0);
}

#[tokio::test]
async fn calendar_change_after_undo_preview_invalidates_write() {
    let create = operation("create", None, Some(values("Original")));
    let (_dir, app, calendar, batch) = setup(vec![create.clone()], false);
    let proposal = service::undo::prepare(calendar.clone(), &app, batch)
        .await
        .unwrap();
    calendar
        .values
        .lock()
        .unwrap()
        .insert(create.id, values("Changed after preview"));
    assert!(
        service::calendar::approve_calendar(calendar.clone(), &app, proposal.token, true)
            .await
            .is_err()
    );
    assert_eq!(*calendar.writes.lock().unwrap(), 0);
}

#[tokio::test]
async fn overlap_added_after_preview_blocks_import_without_recording_intent() {
    let (_dir, app, calendar, _) = setup(vec![], false);
    let mut run: PipelineRun = serde_json::from_str(include_str!(
        "../../../../ml/evaluation/fixtures/sample-run.json"
    ))
    .unwrap();
    reha_core::review::migrate(&mut run).unwrap();
    run.appointments.truncate(1);
    let appointment = &mut run.appointments[0];
    appointment.fields.clear();
    appointment.issues.clear();
    appointment.included = true;
    let selection = vec![appointment.id.clone()];
    reha_core::review::approve_selection(&mut run, &selection, 1).unwrap();
    app.store.lock().unwrap().save_run(&run).unwrap();
    *calendar.overlaps.lock().unwrap() = Some(vec![]);
    let preview = service::calendar::prepare_calendar(
        calendar.clone(),
        &app,
        run.document.id,
        "destination".into(),
        None,
        "Europe/Vienna".into(),
        None,
        Some(selection.clone()),
        None,
    )
    .await
    .unwrap();
    *calendar.overlaps.lock().unwrap() = Some(vec![CalendarOverlap {
        appointment_id: selection[0].clone(),
        external_id: "external-meeting".into(),
        title: "New meeting".into(),
        start_utc: "2026-09-11T08:00:00Z".into(),
        end_utc: "2026-09-11T09:00:00Z".into(),
    }]);
    let result =
        service::calendar::approve_calendar(calendar.clone(), &app, preview.token, false).await;
    assert!(result.unwrap_err().contains("überschneidungen"));
    assert_eq!(*calendar.writes.lock().unwrap(), 0);
    assert_eq!(app.store.lock().unwrap().batches().unwrap().len(), 1);
    assert!(app.store.lock().unwrap().pending().unwrap().is_empty());
}

#[tokio::test]
async fn uncertain_undo_survives_reopen_and_prevents_a_second_attempt() {
    let (dir, app, calendar, batch) = setup(
        vec![operation("create", None, Some(values("Original")))],
        true,
    );
    let proposal = service::undo::prepare(calendar.clone(), &app, batch.clone())
        .await
        .unwrap();
    let results = service::calendar::approve_calendar(calendar.clone(), &app, proposal.token, true)
        .await
        .unwrap();
    assert_eq!(results[0].status, "uncertain");
    drop(app);
    let app = Arc::new(Application::new(
        Store::open(dir.path()).unwrap(),
        "missing".into(),
    ));
    assert_eq!(app.store.lock().unwrap().pending().unwrap().len(), 1);
    assert!(service::undo::prepare(calendar, &app, batch).await.is_err());
    assert_eq!(app.store.lock().unwrap().batches().unwrap().len(), 2);
}

#[test]
fn pages_preserve_serialized_reviews_multiplicity_and_order_across_reopen() {
    let dir = tempfile::tempdir().unwrap();
    let mut store = Store::open(dir.path()).unwrap();
    let mut a: PipelineRun = serde_json::from_str(include_str!(
        "../../../../ml/evaluation/fixtures/sample-run.json"
    ))
    .unwrap();
    let mut b = a.clone();
    b.document.id = uuid::Uuid::new_v4().to_string();
    b.appointments[0].date = Some("2027-01-01".into());
    a.complete_page_confirmed = false;
    b.complete_page_confirmed = false;
    store.save_run(&a).unwrap();
    store.save_run(&b).unwrap();
    let read = |s: &Store| {
        s.connection
            .prepare("SELECT run FROM scans ORDER BY id")
            .unwrap()
            .query_map([], |r| r.get::<_, String>(0))
            .unwrap()
            .collect::<std::result::Result<Vec<_>, _>>()
            .unwrap()
    };
    let before = read(&store);
    store
        .group_pages(
            &a.document.id,
            &[a.document.id.clone(), b.document.id.clone()],
        )
        .unwrap();
    drop(store);
    let mut store = Store::open(dir.path()).unwrap();
    assert_eq!(read(&store), before);
    assert_eq!(
        store.page_ids(&b.document.id).unwrap(),
        vec![a.document.id.clone(), b.document.id.clone()]
    );
    assert_eq!(store.plans().unwrap().len(), 1);
    store
        .group_pages(&a.document.id, &[a.document.id.clone()])
        .unwrap();
    assert_eq!(store.plans().unwrap().len(), 2);
    assert_eq!(read(&store), before);
}

#[tokio::test]
async fn queued_undo_continues_after_reopen_but_in_flight_writes_only_reconcile() {
    let create = operation("create", None, Some(values("Original")));
    let (dir, app, calendar, original) = setup(vec![create.clone()], false);
    let inverse = operation("remove", Some(values("Original")), None);
    let mut inverse = CalendarOperation {
        id: create.id.clone(),
        ..inverse
    };
    inverse.external_id = Some("external".into());
    let batch = app
        .store
        .lock()
        .unwrap()
        .begin_batch(&[], "schedule", &[inverse], Some(&original))
        .unwrap();
    assert_eq!(batch.operations[0].status, "queued");
    drop(app);
    let app = Arc::new(Application::new(
        Store::open(dir.path()).unwrap(),
        "missing".into(),
    ));
    let results = service::calendar::reconcile_calendar(calendar.clone(), &app)
        .await
        .unwrap();
    assert_eq!(results[0].status, "saved");
    assert!(!calendar.values.lock().unwrap().contains_key(&create.id));
    assert_eq!(*calendar.writes.lock().unwrap(), 1);
}

#[test]
fn interrupted_pdf_pages_keep_order_and_ids_without_authorizing_a_partial_plan() {
    let dir = tempfile::tempdir().unwrap();
    let mut store = Store::open(dir.path()).unwrap();
    let source = uuid::Uuid::new_v4().to_string();
    store
        .stage_intake(
            &source,
            "synthetic.pdf",
            b"%PDF-1.7 synthetic fixture",
            &PipelineConfig::default(),
            1,
        )
        .unwrap();
    let pages = store.pdf_pages(&source, 2).unwrap();
    store
        .stage_intake(
            &pages[0],
            "page-1.png",
            b"first page retained",
            &PipelineConfig::default(),
            1,
        )
        .unwrap();
    drop(store);
    let mut store = Store::open(dir.path()).unwrap();
    assert_eq!(store.pdf_pages(&source, 2).unwrap(), pages);
    assert_eq!(store.page_ids(&source).unwrap(), pages);
    assert_eq!(
        std::fs::read(store.source_path(&source).unwrap()).unwrap(),
        b"%PDF-1.7 synthetic fixture"
    );
    assert!(store.load_run(&pages[1]).is_err());
    assert!(store.pdf_pages(&source, 3).is_err());
}
