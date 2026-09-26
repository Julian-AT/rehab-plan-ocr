use reha_core::{
    service::{self, calendar_reads as read, events, Application, Platform, ServiceError},
    store::Store,
};
use serde_json::{json, Value};
use std::sync::{Arc, Mutex};

fn event(calendar: &str) -> read::Event {
    serde_json::from_value(json!({
        "id":"stable-occurrence", "external_id":"native", "calendar_id":calendar,
        "calendar_title":"Therapie", "source":"Account", "occurrence":"2026-09-18T08:00:00Z",
        "recurring":true,"system_only":true,"writable":false,"fingerprint":"unchanged",
        "values":{"title":"Therapie","start_utc":"2026-09-18T08:00:00Z","end_utc":"2026-09-18T09:00:00Z",
            "timezone":"Europe/Vienna","location":"Raum 2","reminder_minutes":null},
        "metadata":{"notes":"Keep","alarms":[{"relative":-600,"absolute":null}],
            "recurrence":[{"opaque_future_field":[1,null,true]}],"all_day":true}
    })).unwrap()
}
struct Typed {
    state: Arc<Application>,
    queries: Mutex<Vec<read::Query>>,
    references: Mutex<Vec<read::Reference>>,
    wrong_scope: bool,
    change_selection: bool,
    failure: Option<ServiceError>,
}
impl Platform for Typed {
    fn progress(&self, _: Value) {}
    fn call(&self, command: &str, _: Value) -> service::Response<Value> {
        panic!("typed reads must not invoke the JSON host: {command}")
    }
    fn query_calendar(&self, query: read::Query) -> service::Response<read::QueryResult> {
        self.queries.lock().unwrap().push(query);
        if let Some(error) = &self.failure {
            return Err(error.clone());
        }
        if self.change_selection {
            for ids in [json!([]), json!(["selected"])] {
                service::settings::settings_value(
                    &self.state,
                    Some(json!({
                    "timezone":"Europe/Vienna","display_calendar_ids":ids})),
                )?;
            }
        }
        Ok(read::QueryResult {
            events: vec![event(if self.wrong_scope {
                "hidden"
            } else {
                "selected"
            })],
            unavailable_calendar_ids: vec!["selected".into()],
            unavailable_events: vec![read::UnavailableEvent {
                id: "missing".into(),
                start_utc: "2026-09-18T07:00:00Z".into(),
                end_utc: "2026-09-18T08:00:00Z".into(),
            }],
        })
    }
    fn resolve_calendar_event(
        &self,
        reference: read::Reference,
    ) -> service::Response<Option<read::Event>> {
        self.references.lock().unwrap().push(reference);
        if let Some(error) = &self.failure {
            return Err(error.clone());
        }
        Ok(Some(event("selected")))
    }
}
fn fixture(
    wrong_scope: bool,
    change_selection: bool,
    failure: Option<ServiceError>,
) -> (tempfile::TempDir, Arc<Application>, Arc<Typed>) {
    let root = tempfile::tempdir().unwrap();
    let state = Arc::new(Application::new(
        Store::open(root.path()).unwrap(),
        "missing".into(),
    ));
    service::settings::settings_value(
        &state,
        Some(json!({
        "timezone":"Europe/Vienna","display_calendar_ids":["selected"]})),
    )
    .unwrap();
    let host = Arc::new(Typed {
        state: state.clone(),
        queries: Mutex::new(vec![]),
        references: Mutex::new(vec![]),
        wrong_scope,
        change_selection,
        failure,
    });
    (root, state, host)
}
fn range() -> Value {
    json!({"start_utc":"2026-09-18T00:00:00Z","end_utc":"2026-09-19T00:00:00Z"})
}
#[tokio::test]
async fn typed_reads_keep_scope_occurrence_metadata_and_unavailable_evidence() {
    let (_root, state, host) = fixture(false, false, None);
    let result = events::query(host.clone(), &state, range()).await.unwrap();
    let actual = host.queries.lock().unwrap()[0].clone();
    assert_eq!(actual.calendar_ids, vec!["selected"]);
    assert_eq!(actual.timezone, "Europe/Vienna");
    assert_eq!(actual.selection_revision, 1);
    assert_eq!(actual.start_utc, range()["start_utc"].as_str().unwrap());
    assert_eq!(actual.end_utc, range()["end_utc"].as_str().unwrap());
    assert_eq!(
        result["events"][0],
        serde_json::to_value(event("selected")).unwrap()
    );
    assert!(result["events"][0].get("import_id").is_none());
    assert_eq!(result["unavailable_events"][0]["id"], "missing");
    let supplied: read::Event = serde_json::from_value(result["events"][0].clone()).unwrap();
    let platform: Arc<dyn Platform> = host.clone();
    assert_eq!(
        read::resolve(&platform, &supplied).await.unwrap(),
        Some(supplied.clone())
    );
    let refs = host.references.lock().unwrap();
    assert_eq!(refs[0].external_id, "native");
    assert_eq!(refs[0].occurrence, "2026-09-18T08:00:00Z");
    assert_eq!(refs[0].expected_start_utc, supplied.values.start_utc);
}
#[tokio::test]
async fn empty_selection_never_reads_and_scope_changes_reject_results() {
    for (wrong, changed) in [(true, false), (false, true)] {
        let (_root, state, host) = fixture(wrong, changed, None);
        assert!(events::query(host, &state, range()).await.is_err());
    }
    let (_root, state, host) = fixture(false, false, None);
    service::settings::settings_value(
        &state,
        Some(json!({"timezone":"Europe/Vienna","display_calendar_ids":[]})),
    )
    .unwrap();
    assert_eq!(
        events::query(host.clone(), &state, range()).await.unwrap()["events"],
        json!([])
    );
    assert!(host.queries.lock().unwrap().is_empty());
}
#[tokio::test]
async fn typed_read_errors_are_not_reclassified_by_display_text() {
    for error in [
        ServiceError::PermissionDenied,
        ServiceError::Timeout("queryEvents".into()),
        ServiceError::Cancelled,
        ServiceError::Storage("Kalenderzugriff fehlt.".into()),
    ] {
        let (_root, state, host) = fixture(false, false, Some(error.clone()));
        assert_eq!(
            events::query(host.clone(), &state, range())
                .await
                .unwrap_err(),
            error
        );
        let platform: Arc<dyn Platform> = host;
        assert_eq!(
            read::resolve(&platform, &event("selected"))
                .await
                .unwrap_err(),
            error
        );
    }
}
