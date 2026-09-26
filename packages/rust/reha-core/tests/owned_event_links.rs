use reha_core::{
    service::{
        self,
        calendar_links::{self, OwnedResolution},
        events, Application, Platform, ServiceError,
    },
    store::{OwnedEventRecord, Store},
};
use serde_json::{json, Value};
use std::sync::{Arc, Mutex};

const ID: &str = "54e2fe8f-07b8-4629-bf91-c64fc01f8a7b";
fn record() -> OwnedEventRecord {
    serde_json::from_value(
        json!({"id":ID,"calendar_id":"hidden","external_id":"original",
        "status":"saved","origin":"import","import_id":ID,"operation_id":"committed",
        "approved":{"title":"Bestätigt","start_utc":"2026-09-19T08:00:00Z",
        "end_utc":"2026-09-19T09:00:00Z","timezone":"Europe/Vienna","location":"Raum 2",
        "notes":"Unverändert","reminder_minutes":10}}),
    )
    .unwrap()
}
fn found() -> OwnedResolution {
    serde_json::from_value(json!({"status":"found","event":{
        "id":"occurrence","external_id":"repaired","calendar_id":"moved",
        "calendar_title":"Kalender","source":"Lokal","occurrence":"2026-09-19T08:00:00Z",
        "recurring":false,"system_only":false,"writable":true,"fingerprint":"native",
        "values":{"title":"Aktueller Titel","start_utc":"2026-09-19T08:00:00Z",
        "end_utc":"2026-09-19T09:00:00Z","timezone":"Europe/Vienna","location":"Raum 3",
        "reminder_minutes":null},"import_id":ID,
        "metadata":{"notes":"Fremde Änderung bleibt","url":format!("reha-calendar://event/{ID}"),
        "alarms":[{"relative":-600}],"future":[true,null]}}}))
    .unwrap()
}
struct Host {
    result: Mutex<service::Response<OwnedResolution>>,
    records: Mutex<Vec<OwnedEventRecord>>,
}
impl Platform for Host {
    fn progress(&self, _: Value) {}
    fn call(&self, command: &str, _: Value) -> service::Response<Value> {
        panic!("Owned lookup used string callback: {command}")
    }
    fn resolve_owned_event(&self, record: OwnedEventRecord) -> service::Response<OwnedResolution> {
        self.records.lock().unwrap().push(record);
        self.result.lock().unwrap().clone()
    }
}
fn fixture() -> (tempfile::TempDir, Application, Arc<Host>) {
    let folder = tempfile::tempdir().unwrap();
    let store = Store::open(folder.path()).unwrap();
    store
        .set_setting("preferences", r#"{"display_calendar_ids":[]}"#)
        .unwrap();
    store
        .connection
        .execute(
            "INSERT INTO owned_events VALUES(?1,'hidden','original',?2)",
            rusqlite::params![ID, serde_json::to_string(&record()).unwrap()],
        )
        .unwrap();
    (
        folder,
        Application::new(store, "missing".into()),
        Arc::new(Host {
            result: Mutex::new(Ok(found())),
            records: Mutex::new(vec![]),
        }),
    )
}

#[tokio::test]
async fn explicit_links_keep_hidden_records_and_native_statuses_without_writing() {
    let (folder, state, host) = fixture();
    for expected in [
        found(),
        OwnedResolution::Deleted,
        OwnedResolution::Unavailable,
    ] {
        *host.result.lock().unwrap() = Ok(expected.clone());
        assert_eq!(
            calendar_links::resolve_owned(host.clone(), &state, ID)
                .await
                .unwrap(),
            expected
        );
        assert_eq!(
            events::dispatch(host.clone(), &state, "resolveOwnedEvent", json!({"id":ID}))
                .await
                .unwrap(),
            serde_json::to_value(expected).unwrap()
        );
    }
    assert_eq!(host.records.lock().unwrap().len(), 6);
    for actual in host.records.lock().unwrap().iter() {
        assert_eq!(
            serde_json::to_value(actual).unwrap(),
            serde_json::to_value(record()).unwrap()
        );
    }
    let reopened = Store::open(folder.path()).unwrap();
    assert_eq!(
        serde_json::to_value(reopened.owned_record(ID).unwrap().unwrap()).unwrap(),
        serde_json::to_value(record()).unwrap()
    );
    assert_eq!(
        reopened.setting("preferences").unwrap().as_deref(),
        Some(r#"{"display_calendar_ids":[]}"#)
    );
}

#[tokio::test]
async fn missing_deleted_invalid_and_locked_records_do_not_reach_the_host() {
    let (_folder, state, host) = fixture();
    for id in ["", "bad-identity", "../../store"] {
        assert!(calendar_links::resolve_owned(host.clone(), &state, id)
            .await
            .is_err());
    }
    assert_eq!(
        calendar_links::resolve_owned(host.clone(), &state, &uuid::Uuid::new_v4().to_string())
            .await
            .unwrap(),
        OwnedResolution::Missing
    );
    let guard = state.calendar_lock.lock().await;
    assert!(tokio::time::timeout(
        std::time::Duration::from_millis(20),
        calendar_links::resolve_owned(host.clone(), &state, ID)
    )
    .await
    .is_err());
    drop(guard);
    let mut deleted = record();
    deleted.status = "deleted".into();
    state
        .store
        .lock()
        .unwrap()
        .connection
        .execute(
            "UPDATE owned_events SET record=?1 WHERE id=?2",
            rusqlite::params![serde_json::to_string(&deleted).unwrap(), ID],
        )
        .unwrap();
    assert_eq!(
        calendar_links::resolve_owned(host.clone(), &state, ID)
            .await
            .unwrap(),
        OwnedResolution::Deleted
    );
    assert!(host.records.lock().unwrap().is_empty());
}

#[tokio::test]
async fn lookup_failures_retain_identity_and_committed_record() {
    let (_folder, state, host) = fixture();
    for error in [
        ServiceError::PermissionDenied,
        ServiceError::Timeout("resolveOwnedEvent".into()),
        ServiceError::Cancelled,
        ServiceError::Storage("Kalenderzugriff fehlt.".into()),
    ] {
        *host.result.lock().unwrap() = Err(error.clone());
        assert_eq!(
            calendar_links::resolve_owned(host.clone(), &state, ID)
                .await
                .unwrap_err(),
            error
        );
        assert_eq!(
            events::dispatch(host.clone(), &state, "resolveOwnedEvent", json!({"id":ID}))
                .await
                .unwrap_err(),
            error
        );
    }
    assert_eq!(
        state
            .store
            .lock()
            .unwrap()
            .owned_record(ID)
            .unwrap()
            .unwrap()
            .status,
        "saved"
    );
}

struct Legacy(Value);
impl Platform for Legacy {
    fn progress(&self, _: Value) {}
    fn call(&self, command: &str, args: Value) -> service::Response<Value> {
        assert_eq!(command, "resolveOwnedEvent");
        assert_eq!(args, json!({"record":record()}));
        Ok(self.0.clone())
    }
}
#[test]
fn legacy_hosts_keep_status_shapes_and_reject_incomplete_found_payloads() {
    for expected in [
        found(),
        OwnedResolution::Deleted,
        OwnedResolution::Unavailable,
        OwnedResolution::Missing,
    ] {
        assert_eq!(
            Legacy(serde_json::to_value(&expected).unwrap())
                .resolve_owned_event(record())
                .unwrap(),
            expected
        );
    }
    for invalid in [
        json!({}),
        json!({"status":"unknown"}),
        json!({"status":"found"}),
        json!({"status":"found","event":null}),
    ] {
        assert!(matches!(
            Legacy(invalid).resolve_owned_event(record()),
            Err(ServiceError::Storage(_))
        ));
    }
}
