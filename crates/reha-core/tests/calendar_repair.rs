use reha_core::{
    service::{self, events, Application, Platform},
    store::Store,
};
use serde_json::{json, Value};
use std::sync::{Arc, Mutex};

struct Host {
    response: Mutex<Value>,
    sync_error: Mutex<bool>,
}
impl Platform for Host {
    fn progress(&self, _: Value) {}
    fn call(&self, command: &str, _: Value) -> service::Response<Value> {
        match command {
            "inspectCalendarLinks" => Ok(self.response.lock().unwrap().clone()),
            "agenda" if *self.sync_error.lock().unwrap() => Err("refresh unavailable".into()),
            "agenda" => Ok(json!({})),
            _ => panic!("Calendar cleanup must not invoke {command}"),
        }
    }
}
fn record(id: &str) -> Value {
    json!({"id":id,"calendar_id":"gone","external_id":"old","status":"saved",
        "origin":"import","import_id":id,"operation_id":"original-operation",
        "approved":{"title":"Erfundene Therapie","start_utc":"2026-09-15T07:00:00Z",
            "end_utc":"2026-09-15T07:30:00Z","timezone":"Europe/Vienna",
            "location":"Raum 1","notes":"Originale Notiz","reminder_minutes":10}})
}
fn fixture() -> (tempfile::TempDir, Arc<Application>, Arc<Host>) {
    let root = tempfile::tempdir().unwrap();
    let store = Store::open(root.path()).unwrap();
    store
        .set_setting(
            "preferences",
            &json!({"display_calendar_ids":["readable"],"calendar_id":"readable"}).to_string(),
        )
        .unwrap();
    for id in ["one", "two"] {
        let r = record(id);
        store
            .connection
            .execute(
                "INSERT INTO owned_events VALUES(?1,'gone','old',?2)",
                rusqlite::params![id, r.to_string()],
            )
            .unwrap();
        store
            .connection
            .execute(
                "INSERT INTO imports VALUES(?1,'original-schedule',?2)",
                rusqlite::params![id, r.to_string()],
            )
            .unwrap();
    }
    let state = Arc::new(Application::new(store, "missing".into()));
    let host = Arc::new(Host {
        response: Mutex::new(
            json!({"access":"fullAccess","calendars":[{"id":"readable"}],
        "results":[{"id":"one","status":"unavailable","reason":"calendar_missing"},{"id":"two","status":"unavailable","reason":"calendar_missing"}]}),
        ),
        sync_error: Mutex::new(false),
    });
    (root, state, host)
}
async fn inspect(state: &Application, host: Arc<Host>) -> Value {
    events::dispatch(host, state, "inspectCalendarRepair", json!({}))
        .await
        .unwrap()
}
async fn confirm(
    state: &Application,
    host: Arc<Host>,
    report: &Value,
    id: &str,
) -> service::Response<Value> {
    let issue = report["issues"]
        .as_array()
        .unwrap()
        .iter()
        .find(|v| v["id"] == id)
        .unwrap();
    events::dispatch(
        host,
        state,
        "confirmCalendarRepair",
        json!({"confirmation":"button","selection":[{"id":id,"fingerprint":issue["fingerprint"]}]}),
    )
    .await
}
fn read(state: &Application, id: &str) -> Value {
    serde_json::to_value(
        state
            .store
            .lock()
            .unwrap()
            .owned_record(id)
            .unwrap()
            .unwrap(),
    )
    .unwrap()
}
fn recovered(id: &str) -> Value {
    json!({"id":id,"status":"found","event":{"calendar_id":"readable","external_id":"new",
        "metadata":{"url":format!("reha-calendar://event/{id}")}}})
}

#[tokio::test]
async fn inspection_does_not_retire_unavailable_links() {
    let (_root, state, host) = fixture();
    let report = inspect(&state, host).await;
    assert_eq!(report["issues"].as_array().unwrap().len(), 2);
    assert_eq!(
        report["issues"][0]["start_utc"],
        record("one")["approved"]["start_utc"]
    );
    assert_eq!(read(&state, "one"), record("one"));
}
#[tokio::test]
async fn confirmed_cleanup_changes_only_selected_local_status_and_survives_restart() {
    let (root, state, host) = fixture();
    let report = inspect(&state, host.clone()).await;
    let result = confirm(&state, host.clone(), &report, "one").await.unwrap();
    assert_eq!(result["removed_count"], 1);
    let mut expected = record("one");
    expected["status"] = json!("detached");
    assert_eq!(read(&state, "one"), expected);
    assert_eq!(read(&state, "two"), record("two"));
    assert!(confirm(&state, host, &report, "one").await.is_err());
    drop(state);
    let store = Store::open(root.path()).unwrap();
    assert_eq!(store.owned_records().unwrap().len(), 1);
    for id in ["one", "two"] {
        let original: String = store
            .connection
            .query_row("SELECT record FROM imports WHERE id=?1", [id], |row| {
                row.get(0)
            })
            .unwrap();
        assert_eq!(
            serde_json::from_str::<Value>(&original).unwrap(),
            record(id)
        );
    }
    assert_eq!(
        store.owned_record("one").unwrap().unwrap().status,
        "detached"
    );
}
#[tokio::test]
async fn recovered_link_is_rebound_without_overwriting_approved_values() {
    let (_root, state, host) = fixture();
    host.response.lock().unwrap()["results"][0] = recovered("one");
    let report = inspect(&state, host).await;
    assert_eq!(report["relinked_count"], 1);
    let mut expected = record("one");
    expected["calendar_id"] = json!("readable");
    expected["external_id"] = json!("new");
    assert_eq!(read(&state, "one"), expected);
}
#[tokio::test]
async fn recovery_between_preview_and_confirmation_preserves_the_link() {
    let (_root, state, host) = fixture();
    let report = inspect(&state, host.clone()).await;
    host.response.lock().unwrap()["results"][0] = recovered("one");
    let result = confirm(&state, host, &report, "one").await.unwrap();
    assert_eq!(result["removed_count"], 0);
    assert_eq!(result["relinked_count"], 1);
    assert_eq!(read(&state, "one")["status"], "saved");
}
#[tokio::test]
async fn revoked_permission_and_malformed_results_leave_all_records_unchanged() {
    let (_root, state, host) = fixture();
    let report = inspect(&state, host.clone()).await;
    host.response.lock().unwrap()["access"] = json!("denied");
    assert!(confirm(&state, host.clone(), &report, "one").await.is_err());
    host.response.lock().unwrap()["access"] = json!("fullAccess");
    host.response.lock().unwrap()["results"] = json!([{ "id":"one","status":"unavailable" }]);
    assert!(confirm(&state, host, &report, "one").await.is_err());
    assert_eq!(read(&state, "one"), record("one"));
}
#[tokio::test]
async fn stale_selection_wrong_marker_and_pending_writes_are_rejected() {
    let (_root, state, host) = fixture();
    let report = inspect(&state, host.clone()).await;
    let mut wrong = report.clone();
    wrong["issues"][0]["fingerprint"] = json!("stale");
    assert!(confirm(&state, host.clone(), &wrong, "one").await.is_err());
    host.response.lock().unwrap()["results"][0] = recovered("one");
    host.response.lock().unwrap()["results"][0]["event"]["metadata"]["url"] =
        json!("https://example.org/unrelated");
    assert!(confirm(&state, host.clone(), &report, "one").await.is_err());
    host.response.lock().unwrap()["results"][0] = json!({"id":"one","status":"unavailable"});
    state.store.lock().unwrap().connection.execute("INSERT INTO event_mutations(id,created_at,proposal,status) VALUES('pending',0,'{}','uncertain')",[]).unwrap();
    assert_eq!(inspect(&state, host.clone()).await["cleanup_blocked"], true);
    assert!(confirm(&state, host, &report, "one").await.is_err());
    assert_eq!(read(&state, "one"), record("one"));
}
#[tokio::test]
async fn cleanup_requires_explicit_selection_and_refresh_failure_reports_committed_result() {
    let (_root, state, host) = fixture();
    assert!(events::dispatch(
        host.clone(),
        &state,
        "confirmCalendarRepair",
        json!({"confirmation":"spoken","selection":[]})
    )
    .await
    .is_err());
    assert!(events::dispatch(
        host.clone(),
        &state,
        "confirmCalendarRepair",
        json!({"confirmation":"button","selection":[]})
    )
    .await
    .is_err());
    let report = inspect(&state, host.clone()).await;
    *host.sync_error.lock().unwrap() = true;
    let result = confirm(&state, host, &report, "one").await.unwrap();
    assert_eq!(result["removed_count"], 1);
    assert_eq!(result["refresh_warning"], "refresh unavailable");
}
#[tokio::test]
async fn missing_selected_calendar_is_reported_without_guessing_its_days() {
    let (_root, state, host) = fixture();
    state
        .store
        .lock()
        .unwrap()
        .set_setting(
            "preferences",
            &json!({"display_calendar_ids":["not-readable"]}).to_string(),
        )
        .unwrap();
    assert_eq!(
        inspect(&state, host).await["missing_calendar_ids"],
        json!(["not-readable"])
    );
}
