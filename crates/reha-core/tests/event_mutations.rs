use reha_core::{
    service::{self, events, Application, Platform},
    store::Store,
};
use serde_json::{json, Value};
use std::sync::{Arc, Mutex};
struct Calendar {
    state: Arc<Application>,
    event: Mutex<Value>,
    calls: Mutex<usize>,
    calendars: Mutex<Value>,
    uncertain: Mutex<bool>,
    interrupted: Mutex<bool>,
    maintenance_failure: Mutex<bool>,
    change_selection_during_query: Mutex<bool>,
}
impl Platform for Calendar {
    fn progress(&self, _: Value) {}
    fn call(&self, command: &str, args: Value) -> service::Response<Value> {
        match command {
            "agenda" => {
                if *self.maintenance_failure.lock().unwrap() {
                    Err("Reminder service unavailable".into())
                } else {
                    Ok(json!({}))
                }
            }
            "eventCalendars" => Ok(self.calendars.lock().unwrap().clone()),
            "queryEvents" => {
                assert_eq!(args["calendar_ids"], json!(["selected"]));
                if *self.change_selection_during_query.lock().unwrap() {
                    service::settings::settings_value(
                        &self.state,
                        Some(json!({"timezone":"Europe/Vienna","display_calendar_ids":[]})),
                    )?;
                    service::settings::settings_value(
                        &self.state,
                        Some(
                            json!({"timezone":"Europe/Vienna","display_calendar_ids":["selected"]}),
                        ),
                    )?;
                }
                Ok(json!({"events":[self.event.lock().unwrap().clone()]}))
            }
            "getEvent" => {
                if *self.interrupted.lock().unwrap() {
                    self.state
                        .invalid_event_sessions
                        .lock()
                        .unwrap()
                        .insert("session".into());
                }
                Ok(json!({"event":self.event.lock().unwrap().clone()}))
            }
            "mutateEvent" => {
                assert!(self
                    .state
                    .store
                    .lock()
                    .unwrap()
                    .event_history()
                    .unwrap()
                    .iter()
                    .any(|h| h["id"] == args["proposal"]["token"]));
                if args["recovery_only"] == true {
                    return Ok(json!({"status":"uncertain"}));
                }
                *self.calls.lock().unwrap() += 1;
                if *self.uncertain.lock().unwrap() {
                    return Err("connection dropped".into());
                }
                let p = &args["proposal"];
                let mut event = self.event.lock().unwrap();
                if p["kind"] == "remove" {
                    *event = Value::Null;
                } else {
                    if p["kind"] == "create" {
                        *event = fixture_event();
                        if let Some(id) = p["owned_id"].as_str() {
                            event["metadata"]["url"] = json!(format!("reha-calendar://event/{id}"));
                        }
                    }
                    for (key, value) in p["patch"].as_object().unwrap() {
                        event["values"][key] = value.clone();
                    }
                    event["fingerprint"] = json!(uuid::Uuid::new_v4().to_string());
                }
                Ok(json!({"status":"saved","event":event.clone()}))
            }
            _ => panic!("unexpected {command}"),
        }
    }
}
fn fixture_event() -> Value {
    json!({"id":"event|occurrence","external_id":"native","calendar_id":"selected","calendar_title":"Therapie","source":"Account","occurrence":"2026-09-15T07:00:00Z","recurring":false,"system_only":false,"writable":true,"fingerprint":"original","values":{"title":"Ergo","start_utc":"2026-09-15T07:00:00Z","end_utc":"2026-09-15T07:30:00Z","timezone":"Europe/Vienna","location":"Raum 1","reminder_minutes":10},"metadata":{"notes":"Keep these notes","url":"https://example.org/original","alarms":[{"relative":-600},{"absolute":"2026-09-14T09:00:00Z"}]}})
}
fn fixture() -> (tempfile::TempDir, Arc<Application>, Arc<Calendar>) {
    let root = tempfile::tempdir().unwrap();
    let store = Store::open(root.path()).unwrap();
    store.set_setting("preferences",&json!({"timezone":"Europe/Vienna","calendar_id":"selected","display_calendar_ids":["selected"]}).to_string()).unwrap();
    let state = Arc::new(Application::new(store, "missing".into()));
    let calendar = Arc::new(Calendar {
        state: state.clone(),
        event: Mutex::new(fixture_event()),
        calls: Mutex::new(0),
        calendars: Mutex::new(
            json!({"calendars":[{"id":"selected","title":"Therapie","source":"Account","writable":true}]}),
        ),
        uncertain: Mutex::new(false),
        interrupted: Mutex::new(false),
        maintenance_failure: Mutex::new(false),
        change_selection_during_query: Mutex::new(false),
    });
    (root, state, calendar)
}

#[tokio::test]
async fn committed_mutation_survives_maintenance_failure_without_repeating_write() {
    let (_root, state, calendar) = fixture();
    let p = preview(
        &state,
        calendar.clone(),
        "update",
        json!({"title":"Gespeichert"}),
    )
    .await;
    *calendar.maintenance_failure.lock().unwrap() = true;
    let result = confirm(&state, calendar.clone(), &p).await.unwrap();
    assert_eq!(result["status"], "saved");
    assert_eq!(
        result["maintenance_warnings"][0],
        "Reminder service unavailable"
    );
    assert_eq!(
        state.store.lock().unwrap().event_history().unwrap()[0]["status"],
        "saved"
    );
    assert_eq!(
        confirm(&state, calendar.clone(), &p).await.unwrap()["status"],
        "saved"
    );
    assert_eq!(*calendar.calls.lock().unwrap(), 1);
}

#[tokio::test]
async fn calendar_query_scope_rejects_stale_revisions_and_empty_means_none() {
    let (_root, state, calendar) = fixture();
    let scope = events::dispatch(calendar.clone(), &state, "agendaSelection", json!({}))
        .await
        .unwrap();
    let request =
        json!({"start_utc":"2026-09-15T00:00:00Z","end_utc":"2026-09-16T00:00:00Z","scope":scope});
    assert_eq!(
        events::query(calendar.clone(), &state, request.clone())
            .await
            .unwrap()["events"]
            .as_array()
            .unwrap()
            .len(),
        1
    );
    *calendar.change_selection_during_query.lock().unwrap() = true;
    assert!(events::query(calendar.clone(), &state, request.clone())
        .await
        .is_err());
    *calendar.change_selection_during_query.lock().unwrap() = false;
    assert!(events::query(calendar.clone(), &state, request)
        .await
        .is_err());
    service::settings::settings_value(
        &state,
        Some(
            json!({"timezone":"Europe/Vienna","calendar_id":"selected","display_calendar_ids":[]}),
        ),
    )
    .unwrap();
    let empty = events::query(
        calendar,
        &state,
        json!({"start_utc":"2026-09-15T00:00:00Z","end_utc":"2026-09-16T00:00:00Z"}),
    )
    .await
    .unwrap();
    assert_eq!(empty["events"], json!([]));
    assert_eq!(empty["scope"]["calendar_ids"], json!([]));
}
async fn preview(state: &Application, calendar: Arc<Calendar>, kind: &str, patch: Value) -> Value {
    events::dispatch(calendar,state,"previewEventMutation",json!({"kind":kind,"patch":patch,"calendar_id":"selected","event":fixture_event(),"session":"session","revision":1})).await.unwrap()["proposal"].clone()
}
async fn confirm(
    state: &Application,
    calendar: Arc<Calendar>,
    p: &Value,
) -> service::Response<Value> {
    events::dispatch(
        calendar,
        state,
        "confirmProposal",
        json!({"token":p["token"],"session":"session","revision":1,"confirmation":"button"}),
    )
    .await
}
#[tokio::test]
async fn explicit_patch_confirm_replay_and_undo_preserve_external_metadata() {
    let (_root, state, calendar) = fixture();
    let p = preview(
        &state,
        calendar.clone(),
        "update",
        json!({"location":"Raum 2"}),
    )
    .await;
    assert_eq!(*calendar.calls.lock().unwrap(), 0);
    assert!(state
        .store
        .lock()
        .unwrap()
        .event_history()
        .unwrap()
        .is_empty());
    assert_eq!(
        confirm(&state, calendar.clone(), &p).await.unwrap()["status"],
        "saved"
    );
    assert_eq!(
        confirm(&state, calendar.clone(), &p).await.unwrap()["status"],
        "saved"
    );
    assert_eq!(*calendar.calls.lock().unwrap(), 1);
    assert_eq!(
        calendar.event.lock().unwrap()["metadata"],
        fixture_event()["metadata"]
    );
    assert!(state
        .store
        .lock()
        .unwrap()
        .records(None)
        .unwrap()
        .is_empty());
    let undo = events::dispatch(
        calendar.clone(),
        &state,
        "previewEventUndo",
        json!({"id":p["token"],"session":"session","revision":1}),
    )
    .await
    .unwrap()["proposal"]
        .clone();
    assert_eq!(undo["patch"], json!({"location":"Raum 1"}));
    assert_eq!(
        confirm(&state, calendar.clone(), &undo).await.unwrap()["status"],
        "saved"
    );
    assert_eq!(
        calendar.event.lock().unwrap()["values"]["location"],
        "Raum 1"
    );
    assert!(events::dispatch(
        calendar,
        &state,
        "previewEventUndo",
        json!({"id":p["token"],"session":"session","revision":1})
    )
    .await
    .is_err());
}
#[tokio::test]
async fn stale_preview_permission_and_selection_are_rechecked() {
    let (_root, state, calendar) = fixture();
    let p = preview(&state, calendar.clone(), "update", json!({"title":"Neu"})).await;
    calendar.event.lock().unwrap()["metadata"]["notes"] = json!("External change");
    assert!(confirm(&state, calendar.clone(), &p)
        .await
        .unwrap_err()
        .contains("geändert"));
    let p = preview(&state, calendar.clone(), "remove", json!({})).await;
    calendar.calendars.lock().unwrap()["calendars"][0]["writable"] = json!(false);
    assert!(confirm(&state, calendar.clone(), &p).await.is_err());
    assert_eq!(*calendar.calls.lock().unwrap(), 0);
}
#[tokio::test]
async fn speech_cannot_confirm_and_background_invalidates_awaiting_confirmation() {
    let (_root, state, calendar) = fixture();
    let p = preview(&state, calendar.clone(), "remove", json!({})).await;
    assert!(events::dispatch(
        calendar.clone(),
        &state,
        "confirmProposal",
        json!({"token":p["token"],"session":"session","revision":1,"confirmation":"spoken"})
    )
    .await
    .is_err());
    let p = preview(&state, calendar.clone(), "remove", json!({})).await;
    *calendar.interrupted.lock().unwrap() = true;
    assert!(confirm(&state, calendar.clone(), &p).await.is_err());
    assert_eq!(*calendar.calls.lock().unwrap(), 0);
}
#[tokio::test]
async fn uncertain_is_durable_and_never_replayed() {
    let (root, state, calendar) = fixture();
    let p = preview(
        &state,
        calendar.clone(),
        "create",
        fixture_event()["values"].clone(),
    )
    .await;
    *calendar.uncertain.lock().unwrap() = true;
    assert_eq!(
        confirm(&state, calendar.clone(), &p).await.unwrap()["status"],
        "uncertain"
    );
    let reopened = Store::open(root.path()).unwrap();
    assert_eq!(reopened.event_history().unwrap()[0]["status"], "uncertain");
    confirm(&state, calendar.clone(), &p).await.unwrap();
    events::dispatch(
        calendar.clone(),
        &state,
        "reconcileEventMutations",
        json!({}),
    )
    .await
    .unwrap();
    assert_eq!(*calendar.calls.lock().unwrap(), 1);
    let p = preview(&state, calendar.clone(), "remove", json!({})).await;
    assert!(confirm(&state, calendar.clone(), &p).await.is_err());
}
#[tokio::test]
async fn query_is_bounded_and_excludes_unselected_calendar() {
    let (_root, state, calendar) = fixture();
    let query = json!({"start_utc":"2026-09-01T00:00:00Z","end_utc":"2026-09-30T00:00:00Z"});
    assert_eq!(
        events::dispatch(
            calendar.clone(),
            &state,
            "queryCalendarEvents",
            query.clone()
        )
        .await
        .unwrap()["events"]
            .as_array()
            .unwrap()
            .len(),
        1
    );
    calendar.event.lock().unwrap()["calendar_id"] = json!("private-not-selected");
    assert!(events::dispatch(
        calendar.clone(),
        &state,
        "queryCalendarEvents",
        query.clone()
    )
    .await
    .is_err());
    // Import ownership must not override the user's display/read selection.
    let owned = json!({"id":"owned-hidden","status":"saved","origin":"import",
        "import_id":"original","operation_id":"save","calendar_id":"private-not-selected",
        "external_id":"native","approved":{"title":"Ergo","start_utc":"2026-09-15T07:00:00Z",
        "end_utc":"2026-09-15T07:30:00Z","timezone":"Europe/Vienna","location":"",
        "notes":"","reminder_minutes":10}});
    state
        .store
        .lock()
        .unwrap()
        .connection
        .execute(
            "INSERT INTO owned_events VALUES(?1,?2,?3,?4)",
            rusqlite::params![
                "owned-hidden",
                "private-not-selected",
                "native",
                owned.to_string()
            ],
        )
        .unwrap();
    calendar.event.lock().unwrap()["import_id"] = json!("owned-hidden");
    assert!(
        events::dispatch(calendar.clone(), &state, "queryCalendarEvents", query)
            .await
            .is_err()
    );
    assert!(events::dispatch(
        calendar,
        &state,
        "queryCalendarEvents",
        json!({"start_utc":"2026-01-01T00:00:00Z","end_utc":"2030-01-01T00:00:00Z"})
    )
    .await
    .is_err());
}
#[tokio::test]
async fn invitation_handoff_and_external_changes_protect_undo() {
    let (_root, state, calendar) = fixture();
    calendar.event.lock().unwrap()["system_only"] = json!(true);
    let handoff=events::dispatch(calendar.clone(),&state,"previewEventMutation",json!({"kind":"remove","patch":{},"calendar_id":"selected","event":fixture_event(),"session":"session"})).await.unwrap();
    assert!(handoff.get("proposal").is_none());
    assert!(handoff.get("system_editor").is_some());
    calendar.event.lock().unwrap()["system_only"] = json!(false);
    let p = preview(
        &state,
        calendar.clone(),
        "update",
        json!({"title":"Changed"}),
    )
    .await;
    confirm(&state, calendar.clone(), &p).await.unwrap();
    calendar.event.lock().unwrap()["metadata"]["notes"] = json!("Later external note");
    assert!(events::dispatch(
        calendar,
        &state,
        "previewEventUndo",
        json!({"id":p["token"],"session":"session","revision":1})
    )
    .await
    .is_err());
}
#[tokio::test]
async fn create_delete_restore_do_not_create_import_provenance() {
    let (_root, state, calendar) = fixture();
    let p = preview(&state, calendar.clone(), "remove", json!({})).await;
    confirm(&state, calendar.clone(), &p).await.unwrap();
    let undo = events::dispatch(
        calendar.clone(),
        &state,
        "previewEventUndo",
        json!({"id":p["token"],"session":"session","revision":1}),
    )
    .await
    .unwrap()["proposal"]
        .clone();
    assert_eq!(undo["kind"], "create");
    assert_eq!(undo["undo_of"], p["token"]);
    confirm(&state, calendar.clone(), &undo).await.unwrap();
    assert!(state
        .store
        .lock()
        .unwrap()
        .records(None)
        .unwrap()
        .is_empty());
}

#[tokio::test]
async fn manual_uncertainty_resolution_never_claims_success_or_retries() {
    let (_root, state, calendar) = fixture();
    let p = preview(&state, calendar.clone(), "remove", json!({})).await;
    *calendar.uncertain.lock().unwrap() = true;
    confirm(&state, calendar.clone(), &p).await.unwrap();
    assert!(events::dispatch(
        calendar.clone(),
        &state,
        "resolveEventUncertainty",
        json!({"id":p["token"],"confirmation":"spoken"})
    )
    .await
    .is_err());
    let result = events::dispatch(
        calendar.clone(),
        &state,
        "resolveEventUncertainty",
        json!({"id":p["token"],"confirmation":"button"}),
    )
    .await
    .unwrap();
    assert_eq!(result["status"], "acknowledged");
    assert_eq!(
        confirm(&state, calendar.clone(), &p).await.unwrap()["status"],
        "acknowledged"
    );
    assert_eq!(*calendar.calls.lock().unwrap(), 1);
}

#[tokio::test]
async fn deselection_revokes_external_edit_even_when_same_calendar_has_imports() {
    let (_root, state, calendar) = fixture();
    let p = preview(&state, calendar.clone(), "remove", json!({})).await;
    {
        let store = state.store.lock().unwrap();
        let mut approved = fixture_event()["values"].clone();
        approved["notes"] = json!("");
        let record = json!({"id":"different-import","schedule_id":"schedule","calendar_id":"selected","external_id":"other-native-id","approved":approved,"status":"saved","operation_id":"old-import"});
        store
            .connection
            .execute(
                "INSERT INTO imports VALUES(?1,?2,?3)",
                rusqlite::params!["different-import", "schedule", record.to_string()],
            )
            .unwrap();
        store.set_setting("preferences", &json!({"timezone":"Europe/Vienna","calendar_id":"selected","display_calendar_ids":[]}).to_string()).unwrap();
    }
    assert!(confirm(&state, calendar.clone(), &p)
        .await
        .unwrap_err()
        .contains("Kalenderauswahl"));
    assert_eq!(*calendar.calls.lock().unwrap(), 0);
}

#[tokio::test]
async fn owned_create_delete_undo_preserve_identity_without_import_baselines() {
    let (root, state, calendar) = fixture();
    let p = preview(
        &state,
        calendar.clone(),
        "create",
        fixture_event()["values"].clone(),
    )
    .await;
    let id = p["owned_id"].as_str().unwrap().to_string();
    assert_eq!(
        confirm(&state, calendar.clone(), &p).await.unwrap()["status"],
        "saved"
    );
    let records = state.store.lock().unwrap().owned_records().unwrap();
    assert_eq!(records.len(), 1);
    assert_eq!(records[0].id, id);
    assert_eq!(records[0].origin, "manual");
    assert!(state
        .store
        .lock()
        .unwrap()
        .records(None)
        .unwrap()
        .is_empty());
    assert_eq!(
        Store::open(root.path()).unwrap().owned_records().unwrap()[0].id,
        id
    );
    let live = calendar.event.lock().unwrap().clone();
    let remove = events::dispatch(calendar.clone(), &state, "previewEventMutation", json!({"kind":"remove","calendar_id":"selected","event":live,"patch":{},"session":"session","revision":1})).await.unwrap()["proposal"].clone();
    assert_eq!(
        confirm(&state, calendar.clone(), &remove).await.unwrap()["status"],
        "saved"
    );
    assert!(state
        .store
        .lock()
        .unwrap()
        .owned_records()
        .unwrap()
        .is_empty());
    let undo = events::dispatch(
        calendar.clone(),
        &state,
        "previewEventUndo",
        json!({"id":remove["token"],"session":"session","revision":1}),
    )
    .await
    .unwrap()["proposal"]
        .clone();
    assert_eq!(undo["owned_id"], id);
    assert_eq!(
        confirm(&state, calendar, &undo).await.unwrap()["status"],
        "saved"
    );
    assert_eq!(
        state.store.lock().unwrap().owned_records().unwrap()[0].id,
        id
    );
}

#[tokio::test]
async fn uncertain_manual_write_blocks_import_batch_admission() {
    let (_root, state, calendar) = fixture();
    *calendar.uncertain.lock().unwrap() = true;
    let p = preview(
        &state,
        calendar.clone(),
        "update",
        json!({"location":"Raum 2"}),
    )
    .await;
    confirm(&state, calendar, &p).await.unwrap();
    assert!(state
        .store
        .lock()
        .unwrap()
        .begin_batch(&[], "schedule", &[], None)
        .is_err());
    assert!(state
        .store
        .lock()
        .unwrap()
        .owned_records()
        .unwrap()
        .is_empty());
}
