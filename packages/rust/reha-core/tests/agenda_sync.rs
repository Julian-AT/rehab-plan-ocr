use reha_core::{
    contracts::EventValues,
    service::{self, agenda, events, Application, Platform, ServiceError},
    store::{OwnedEventRecord, Store},
};
use serde_json::{json, Value};
use std::sync::{Arc, Mutex};

fn fixture() -> (tempfile::TempDir, Arc<Application>) {
    let directory = tempfile::tempdir().unwrap();
    let store = Store::open(directory.path()).unwrap();
    for (id, status, external) in [
        ("confirmed-hidden", "saved", Some("native")),
        ("missing-identity", "saved", None),
        ("removed", "deleted", Some("old-native")),
    ] {
        let record = OwnedEventRecord {
            id: id.into(),
            calendar_id: "hidden".into(),
            external_id: external.map(Into::into),
            approved: EventValues {
                title: "Approved title".into(),
                start_utc: "2031-05-17T08:00:00Z".into(),
                end_utc: "2031-05-17T08:30:00Z".into(),
                timezone: "Europe/Vienna".into(),
                location: "Room 105".into(),
                notes: "Keep approved notes".into(),
                reminder_minutes: Some(15),
            },
            status: status.into(),
            origin: "manual".into(),
            import_id: None,
            operation_id: "confirmed-operation".into(),
        };
        store
            .connection
            .execute(
                "INSERT INTO owned_events(id,calendar_id,external_id,record) VALUES(?1,?2,?3,?4)",
                rusqlite::params![
                    record.id,
                    record.calendar_id,
                    record.external_id,
                    serde_json::to_string(&record).unwrap()
                ],
            )
            .unwrap();
    }
    (
        directory,
        Arc::new(Application::new(store, "missing".into())),
    )
}
struct Typed {
    requests: Mutex<Vec<agenda::SyncRequest>>,
    error: Option<ServiceError>,
}
impl Platform for Typed {
    fn progress(&self, _: Value) {}
    fn call(&self, command: &str, _: Value) -> service::Response<Value> {
        panic!("Native maintenance must stay typed: {command}")
    }
    fn synchronize_agenda(
        &self,
        request: agenda::SyncRequest,
    ) -> service::Response<agenda::SyncResult> {
        self.requests.lock().unwrap().push(request);
        if let Some(error) = &self.error {
            return Err(error.clone());
        }
        Ok(agenda::SyncResult {
            maintenance_warnings: vec!["Widget unavailable".into()],
        })
    }
}
#[tokio::test]
async fn typed_maintenance_keeps_hidden_owned_records_and_separate_visible_scope() {
    let (_directory, state) = fixture();
    let host = Arc::new(Typed {
        requests: Mutex::new(vec![]),
        error: None,
    });
    let platform: Arc<dyn Platform> = host.clone();
    for ids in [json!(["visible"]), json!([])] {
        state
            .store
            .lock()
            .unwrap()
            .set_setting(
                "preferences",
                &json!({
                    "display_calendar_ids": ids, "app_reminders_enabled":true,
                    "app_reminder_minutes":null, "reminder_sound":false, "reminder_preview":false,
                })
                .to_string(),
            )
            .unwrap();
        assert_eq!(
            agenda::sync_warnings(&platform, &state).await,
            ["Widget unavailable"]
        );
        let requests = host.requests.lock().unwrap();
        let request = requests.last().unwrap();
        assert_eq!(json!(request.display_calendar_ids), ids);
        assert_eq!(request.records.len(), 1);
        let record = &request.records[0];
        assert_eq!(record.id, "confirmed-hidden");
        assert_eq!(record.calendar_id, "hidden");
        assert_eq!(record.operation_id, "confirmed-operation");
        assert_eq!(record.origin, "manual");
        assert_eq!(record.approved.notes, "Keep approved notes");
        assert_eq!(record.approved.reminder_minutes, Some(15));
        assert!(request.preferences.enabled);
        assert_eq!(request.preferences.minutes, None);
        assert!(!request.preferences.sound && !request.preferences.preview);
    }
    let error = ServiceError::Timeout("agenda".into());
    let failing: Arc<dyn Platform> = Arc::new(Typed {
        requests: Mutex::new(vec![]),
        error: Some(error.clone()),
    });
    assert_eq!(agenda::sync(&failing, &state).await.unwrap_err(), error);
}
#[test]
fn old_settings_defaults_survive_but_malformed_minutes_cannot_reach_the_host() {
    let (_directory, state) = fixture();
    let request = agenda::sync_request(&state).unwrap();
    assert_eq!(request.preferences.minutes, Some(10));
    assert!(!request.preferences.enabled);
    assert!(request.preferences.sound && request.preferences.preview);
    assert!(request.display_calendar_ids.is_empty());
    for minutes in [json!("ten"), json!(-1), json!(4294967296u64)] {
        let saved = json!({"app_reminder_minutes": minutes}).to_string();
        state
            .store
            .lock()
            .unwrap()
            .set_setting("preferences", &saved)
            .unwrap();
        assert!(matches!(
            agenda::sync_request(&state),
            Err(ServiceError::Storage(_))
        ));
        assert_eq!(
            state
                .store
                .lock()
                .unwrap()
                .setting("preferences")
                .unwrap()
                .unwrap(),
            saved
        );
    }
}
struct Legacy(Value);
impl Platform for Legacy {
    fn progress(&self, _: Value) {}
    fn call(&self, command: &str, args: Value) -> service::Response<Value> {
        assert_eq!(command, "agenda");
        assert_eq!(args["preferences"]["minutes"], 10);
        assert_eq!(args["records"][0]["origin"], "manual");
        Ok(self.0.clone())
    }
}
#[tokio::test]
async fn compatibility_command_retains_full_response_and_old_hosts_still_report_warnings() {
    let (_directory, state) = fixture();
    let response = json!({"snapshot":{"events":[],"future":17},"presentation":{"today":[]},"reminders":{"error":"Alarm journal unavailable"}});
    let host: Arc<dyn Platform> = Arc::new(Legacy(response.clone()));
    assert_eq!(
        events::dispatch(host.clone(), &state, "refreshAgenda", json!({}))
            .await
            .unwrap(),
        response
    );
    assert_eq!(
        agenda::sync_warnings(&host, &state).await,
        ["Alarm journal unavailable"]
    );
}
