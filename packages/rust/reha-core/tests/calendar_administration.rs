use reha_core::{
    service::{
        self, calendar_administration as admin, calendar_mutations as edits, events, Application,
        Platform, ServiceError,
    },
    store::Store,
};
use serde_json::{json, Value};
use std::sync::{Arc, Mutex};

#[derive(Default)]
struct Host {
    mutations: Mutex<Vec<edits::MutationRequest>>,
    failure: Option<ServiceError>,
}
impl Platform for Host {
    fn progress(&self, _: Value) {}
    fn call(&self, command: &str, _: Value) -> service::Response<Value> {
        assert_eq!(
            command, "agenda",
            "administration used a string host effect"
        );
        Ok(json!({"reminders":{"error":"Synthetic maintenance warning"}}))
    }
    fn calendar_status(&self) -> service::Response<admin::PlatformStatus> {
        if let Some(error) = &self.failure {
            return Err(error.clone());
        }
        Ok(admin::PlatformStatus {
            access: admin::Access::FullAccess,
            last_read_at: Some("2026-09-18T08:00:00Z".into()),
            calendars: vec![admin::Calendar {
                id: "visible".into(),
                title: "Therapie".into(),
                writable: false,
            }],
            unavailable_calendar_ids: vec!["unavailable".into()],
        })
    }
    fn mutate_event(
        &self,
        request: edits::MutationRequest,
    ) -> service::Response<edits::MutationResult> {
        assert!(request.recovery_only);
        self.mutations.lock().unwrap().push(request);
        Ok(edits::MutationResult::uncertain())
    }
}
fn fixture() -> (tempfile::TempDir, Arc<Application>, Arc<Host>) {
    let root = tempfile::tempdir().unwrap();
    let state = Arc::new(Application::new(
        Store::open(root.path()).unwrap(),
        "missing".into(),
    ));
    service::settings::settings_value(&state, Some(json!({
        "timezone":"Europe/Vienna", "calendar_id":"hidden-save-target", "display_calendar_ids":["visible"]
    }))).unwrap();
    (root, state, Arc::new(Host::default()))
}
fn proposal() -> edits::Proposal {
    serde_json::from_value(json!({
        "token":"record", "session":"session", "revision":1, "expires_at":1,
        "kind":"create", "calendar_id":"visible", "calendar_title":"Therapie", "before":null,
        "patch":{"title":"Ergotherapie","start_utc":"2026-09-18T08:00:00Z", "end_utc":"2026-09-18T09:00:00Z",
            "timezone":"Europe/Vienna", "reminder_minutes":null}, "undo_of":null
    })).unwrap()
}
#[tokio::test]
async fn status_combines_observations_with_core_owned_selection_and_pending_counts() {
    let (_root, state, host) = fixture();
    state
        .store
        .lock()
        .unwrap()
        .begin_event_mutation(&proposal())
        .unwrap();
    let status = admin::status(host.clone(), &state).await.unwrap();
    assert_eq!(status.platform.access, admin::Access::FullAccess);
    assert_eq!(status.platform.unavailable_calendar_ids, ["unavailable"]);
    assert_eq!(status.calendar_id.as_deref(), Some("hidden-save-target"));
    assert_eq!(status.display_calendar_ids.as_ref().unwrap(), &["visible"]);
    assert_eq!(
        (
            status.pending_imports,
            status.pending_events,
            status.pending_bookkeeping
        ),
        (0, 1, 0)
    );
    let legacy = events::dispatch(host, &state, "calendarStatus", json!({}))
        .await
        .unwrap();
    assert_eq!(legacy, serde_json::to_value(status).unwrap());
    for error in [
        ServiceError::PermissionDenied,
        ServiceError::Cancelled,
        ServiceError::Timeout("calendarStatus".into()),
        ServiceError::Storage("Kalenderzugriff fehlt.".into()),
    ] {
        let failing = Arc::new(Host {
            failure: Some(error.clone()),
            ..Host::default()
        });
        assert_eq!(
            admin::status(failing.clone(), &state).await.unwrap_err(),
            error
        );
        assert_eq!(
            events::dispatch(failing, &state, "calendarStatus", json!({}))
                .await
                .unwrap_err(),
            error
        );
    }
}
#[tokio::test]
async fn explicit_acknowledgement_preserves_proposal_and_never_replays_or_allows_undo() {
    let (root, state, host) = fixture();
    state
        .store
        .lock()
        .unwrap()
        .begin_event_mutation(&proposal())
        .unwrap();
    let before = state
        .store
        .lock()
        .unwrap()
        .event_mutation("record")
        .unwrap()
        .unwrap()["proposal"]
        .clone();
    let forbidden = admin::acknowledge(
        &state,
        admin::AcknowledgeRequest {
            id: "record".into(),
            confirmation: edits::Confirmation::MissingVisibleButton,
        },
    )
    .await;
    assert!(matches!(forbidden, Err(ServiceError::Validation(_))));
    assert_eq!(
        admin::event_detail(&state, "record")
            .unwrap()
            .unwrap()
            .status,
        admin::HistoryStatus::Pending
    );
    let result = admin::acknowledge(
        &state,
        admin::AcknowledgeRequest {
            id: "record".into(),
            confirmation: edits::Confirmation::Button,
        },
    )
    .await
    .unwrap();
    assert_eq!(result.status, edits::Status::Acknowledged);
    assert!(result.event.is_none());
    assert!(admin::acknowledge(
        &state,
        admin::AcknowledgeRequest {
            id: "record".into(),
            confirmation: edits::Confirmation::Button,
        }
    )
    .await
    .is_err());
    assert!(edits::undo(
        host.clone(),
        &state,
        edits::UndoRequest {
            id: "record".into(),
            session: "session".into(),
            revision: 1,
        }
    )
    .await
    .is_err());
    let reconciled = admin::reconcile_events(host.clone(), &state).await.unwrap();
    assert_eq!(
        reconciled.maintenance_warnings,
        ["Synthetic maintenance warning"]
    );
    assert!(host.mutations.lock().unwrap().is_empty());
    let stored = state
        .store
        .lock()
        .unwrap()
        .event_mutation("record")
        .unwrap()
        .unwrap();
    assert_eq!(stored["proposal"], before);
    assert_eq!(
        stored["result"],
        json!({"status":"acknowledged", "message":result.message})
    );
    let detail = admin::event_detail(&state, "record").unwrap().unwrap();
    assert_eq!(detail.status, admin::HistoryStatus::Acknowledged);
    assert_eq!(
        detail.proposal.patch.reminder_minutes,
        edits::ReminderChange::Disabled
    );
    assert_eq!(
        events::dispatch(host, &state, "activityDetail", json!({"id":"event:record"}))
            .await
            .unwrap(),
        serde_json::to_value(&detail).unwrap()
    );
    assert!(admin::event_detail(&state, "missing").unwrap().is_none());
    drop(state);
    let reopened = Application::new(Store::open(root.path()).unwrap(), "missing".into());
    assert_eq!(
        admin::history(&reopened).unwrap()[0].status,
        admin::HistoryStatus::Acknowledged
    );
}
#[tokio::test]
async fn recovery_only_replays_unresolved_records_and_does_not_decode_finished_proposals() {
    let (_root, state, host) = fixture();
    {
        let store = state.store.lock().unwrap();
        store.begin_event_mutation(&proposal()).unwrap();
        store.connection.execute("INSERT INTO event_mutations(id,created_at,proposal,status) VALUES('older',0,'{}','failed')", []).unwrap();
    }
    let result = admin::reconcile_events(host.clone(), &state).await.unwrap();
    assert_eq!(result.maintenance_warnings.len(), 1);
    assert_eq!(host.mutations.lock().unwrap().len(), 1);
    assert_eq!(
        admin::event_detail(&state, "record")
            .unwrap()
            .unwrap()
            .status,
        admin::HistoryStatus::Uncertain
    );
    // Manual acknowledgement likewise never needs to reinterpret old intent.
    state
        .store
        .lock()
        .unwrap()
        .connection
        .execute(
            "UPDATE event_mutations SET proposal='{}' WHERE id='record'",
            [],
        )
        .unwrap();
    admin::acknowledge(
        &state,
        admin::AcknowledgeRequest {
            id: "record".into(),
            confirmation: edits::Confirmation::Button,
        },
    )
    .await
    .unwrap();
    assert_eq!(host.mutations.lock().unwrap().len(), 1);
}
#[tokio::test]
async fn failed_local_bookkeeping_retains_its_journal_and_returns_storage_error() {
    let (_root, state, host) = fixture();
    state
        .store
        .lock()
        .unwrap()
        .set_setting("calendar_bookkeeping:damaged:1", "not-json")
        .unwrap();
    assert_eq!(
        admin::status(host, &state)
            .await
            .unwrap()
            .pending_bookkeeping,
        1
    );
    assert!(matches!(
        admin::reconcile_bookkeeping(&state).await,
        Err(ServiceError::Storage(_))
    ));
    assert_eq!(
        state
            .store
            .lock()
            .unwrap()
            .setting("calendar_bookkeeping:damaged:1")
            .unwrap()
            .as_deref(),
        Some("not-json")
    );
}
