use reha_core::{
    contracts::{CalendarOperation, PipelineRun},
    service::{
        self, calendar_mutations as edits, Application, DomainFailure, Platform, ServiceError,
    },
    store::Store,
    Error,
};
use serde_json::{json, Value};
use std::sync::{atomic::AtomicBool, Arc};

fn fixture() -> (tempfile::TempDir, Arc<Application>, PipelineRun) {
    let root = tempfile::tempdir().unwrap();
    let mut run: PipelineRun = serde_json::from_str(include_str!(
        "../../../../ml/evaluation/fixtures/sample-run.json"
    ))
    .unwrap();
    reha_core::review::migrate(&mut run).unwrap();
    let store = Store::open(root.path()).unwrap();
    store.save_run(&run).unwrap();
    (
        root,
        Arc::new(Application::new(store, "missing".into())),
        run,
    )
}

struct NoEffects;
impl Platform for NoEffects {
    fn call(&self, command: &str, _: Value) -> service::Response<Value> {
        panic!("Rejected request reached platform: {command}")
    }
    fn progress(&self, _: Value) {}
}

fn rejected<T>(result: service::Response<T>, kind: DomainFailure, message: &str) {
    let error = result.err().expect("Request must be rejected");
    assert_eq!(error, kind.with_message(message));
    assert_eq!(error.to_string(), message);
    assert_eq!(serde_json::to_value(error).unwrap(), json!(message));
}

#[tokio::test]
async fn missing_runs_and_intakes_keep_distinct_diagnostics_and_expired_identity() {
    let (_root, app, run) = fixture();
    let missing = uuid::Uuid::new_v4().to_string();
    assert!(matches!(
        app.store.lock().unwrap().load_run(&missing),
        Err(Error::MissingRun)
    ));
    rejected(
        service::scan::load_scan(&app, missing.clone()),
        DomainFailure::ExpiredScan,
        "Scan wurde gelöscht oder ist noch nicht erkannt.",
    );
    rejected(
        service::scan::retry_scan(Arc::new(NoEffects), &app, missing).await,
        DomainFailure::ExpiredScan,
        "Aufnahme wurde gelöscht oder fehlt.",
    );
    assert_eq!(
        serde_json::to_value(
            app.store
                .lock()
                .unwrap()
                .load_run(&run.document.id)
                .unwrap()
        )
        .unwrap(),
        serde_json::to_value(run).unwrap()
    );
}

#[test]
fn busy_guards_keep_original_diagnostics_and_preserve_retained_data() {
    let (_root, app, run) = fixture();
    let admission = app.lifecycle_lock.try_lock().unwrap();
    for result in [
        service::calendar::set_page_group(&app, run.document.id.clone(), vec![]),
        service::calendar::append_pages(&app, run.document.id.clone(), vec![]),
        service::settings::maintenance(&app),
    ] {
        rejected(
            result,
            DomainFailure::Busy,
            "Eine Datenänderung läuft bereits.",
        );
    }
    rejected(
        service::scan::delete_scan(&app, run.document.id.clone()),
        DomainFailure::Busy,
        "Eine Datenänderung läuft bereits.",
    );
    drop(admission);
    app.cancel
        .lock()
        .unwrap()
        .insert(run.document.id.clone(), Arc::new(AtomicBool::new(false)));
    rejected(
        service::scan::delete_scan(&app, run.document.id.clone()),
        DomainFailure::Busy,
        "Eine Verarbeitung läuft bereits. Bitte warten oder abbrechen.",
    );
    rejected(
        service::settings::maintenance(&app),
        DomainFailure::Busy,
        "Eine Verarbeitung läuft bereits. Bitte warten oder abbrechen.",
    );
    assert!(app.store.lock().unwrap().load_run(&run.document.id).is_ok());
}

#[test]
fn stale_draft_answers_and_exports_keep_revision_identity_without_writing() {
    let (_root, app, run) = fixture();
    rejected(
        service::draft::answer(
            &app,
            run.document.id.clone(),
            "obsolete".into(),
            "question".into(),
            None,
            "Europe/Vienna".into(),
        ),
        DomainFailure::StaleRevision,
        "stale_revision",
    );
    rejected(
        service::draft::export_ics(
            &app,
            run.document.id.clone(),
            "obsolete".into(),
            "Europe/Vienna".into(),
            None,
            vec![],
        ),
        DomainFailure::StaleRevision,
        "stale_revision",
    );
    assert_eq!(
        serde_json::to_value(
            app.store
                .lock()
                .unwrap()
                .load_run(&run.document.id)
                .unwrap()
        )
        .unwrap(),
        serde_json::to_value(run).unwrap()
    );
}

#[tokio::test]
async fn missing_proposal_tokens_are_typed_before_any_platform_effect() {
    let (_root, app, _) = fixture();
    let host = Arc::new(NoEffects);
    rejected(
        service::calendar::resolve_proposal(&app, "gone".into(), "event".into(), "keep".into()),
        DomainFailure::StaleProposal,
        "Vorschau abgelaufen.",
    );
    rejected(
        service::calendar::approve_calendar(host.clone(), &app, "gone".into(), false).await,
        DomainFailure::StaleProposal,
        "Vorschau abgelaufen.",
    );
    rejected(
        service::draft::accept_and_save(host.clone(), &app, "gone".into(), vec![], false).await,
        DomainFailure::StaleProposal,
        "Vorschau abgelaufen.",
    );
    rejected(
        edits::confirm(
            host,
            &app,
            edits::ConfirmRequest {
                token: "gone".into(),
                session: "gone".into(),
                revision: 1,
                confirmation: edits::Confirmation::Button,
            },
        )
        .await,
        DomainFailure::StaleProposal,
        "Vorschau abgelaufen. Erneut prüfen.",
    );
    let store = app.store.lock().unwrap();
    assert!(store.batches().unwrap().is_empty());
    assert!(store.event_history().unwrap().is_empty());
}

#[tokio::test]
async fn unresolved_writes_keep_typed_rejection_and_journal_bytes() {
    let (root, app, run) = fixture();
    let operation = CalendarOperation {
        kind: "create".into(),
        id: uuid::Uuid::new_v4().to_string(),
        calendar_id: "synthetic".into(),
        external_id: None,
        before: None,
        after: None,
        requires_resolution: false,
        reason: String::new(),
    };
    app.store
        .lock()
        .unwrap()
        .begin_operation("schedule", &operation)
        .unwrap();
    let before = serde_json::to_value(app.store.lock().unwrap().pending().unwrap()).unwrap();
    rejected(
        service::scan::save_review(
            &app,
            run.document.id.clone(),
            run.appointments.clone(),
            false,
            false,
            None,
            None,
        ),
        DomainFailure::UncertainWrite,
        "Unklare Schreibvorgänge zuerst abgleichen.",
    );
    rejected(
        service::undo::prepare(Arc::new(NoEffects), &app, "missing".into()).await,
        DomainFailure::UncertainWrite,
        "Unklare Schreibvorgänge zuerst abgleichen.",
    );
    let proposal = edits::Proposal {
        token: "new".into(),
        session: "session".into(),
        revision: 1,
        expires_at: i64::MAX,
        kind: edits::Kind::Create,
        calendar_id: "synthetic".into(),
        calendar_title: "Test".into(),
        before: None,
        patch: edits::Patch::default(),
        undo_of: None,
        owned_id: None,
        origin: "manual".into(),
    };
    {
        let mut store = app.store.lock().unwrap();
        for (result, diagnostic) in [
            (
                store.begin_batch(&[], "schedule", &[], None).map(|_| ()),
                "Unklare Schreibvorgänge zuerst abgleichen.",
            ),
            (
                store.retry_failed_batch("missing", &[]).map(|_| ()),
                "Unklare Schreibvorgänge zuerst abgleichen.",
            ),
            (
                store.begin_event_mutation(&proposal),
                "Unklare Schreibvorgänge zuerst prüfen.",
            ),
        ] {
            let error = result.expect_err("Pending write must block admission");
            assert!(matches!(error, Error::UnresolvedCalendarWrites(_)));
            assert_eq!(error.to_string(), diagnostic);
            rejected(
                Err::<(), _>(service::domain_failure(error)),
                DomainFailure::UncertainWrite,
                diagnostic,
            );
        }
        assert!(store.batches().unwrap().is_empty());
        assert!(store.event_history().unwrap().is_empty());
    }
    drop(app);
    let reopened = Store::open(root.path()).unwrap();
    assert_eq!(
        serde_json::to_value(reopened.pending().unwrap()).unwrap(),
        before
    );
}

#[test]
fn arbitrary_domain_diagnostics_never_acquire_failure_identity_from_words() {
    for message in [
        "Kalenderzugriff fehlt.",
        "stale_revision",
        "Vorschau abgelaufen.",
        "Prüfdaten wurden geändert.",
        "gelöscht oder",
        "läuft bereits",
        "Unklare Schreibvorgänge",
    ] {
        let error = service::domain_failure(Error::Invalid(message.into()));
        assert_eq!(error, ServiceError::Legacy(message.into()));
        assert_eq!(serde_json::to_value(error).unwrap(), json!(message));
    }
}
