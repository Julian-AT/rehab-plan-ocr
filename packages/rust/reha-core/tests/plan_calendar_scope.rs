use reha_core::{
    contracts::{EventValues, ImportRecord},
    store::{OwnedEventRecord, Store},
};
use rusqlite::params;

fn import(store: &Store, id: &str, calendar: &str) -> ImportRecord {
    let record = ImportRecord {
        id: id.into(),
        schedule_id: "schedule".into(),
        calendar_id: calendar.into(),
        external_id: Some(format!("external-{id}")),
        approved: EventValues {
            title: "Approved appointment".into(),
            start_utc: "2026-09-21T08:00:00Z".into(),
            end_utc: "2026-09-21T09:00:00Z".into(),
            timezone: "Europe/Vienna".into(),
            location: "Approved room".into(),
            notes: "Approved notes".into(),
            reminder_minutes: Some(10),
        },
        status: "saved".into(),
        operation_id: format!("operation-{id}"),
    };
    store
        .connection
        .execute(
            "INSERT INTO imports VALUES(?1,?2,?3)",
            params![
                id,
                record.schedule_id,
                serde_json::to_string(&record).unwrap()
            ],
        )
        .unwrap();
    record
}

fn ownership(store: &Store, record: &OwnedEventRecord) {
    store.connection.execute("INSERT INTO owned_events VALUES(?1,?2,?3,?4) ON CONFLICT(id) DO UPDATE SET calendar_id=excluded.calendar_id,external_id=excluded.external_id,record=excluded.record",params![record.id,record.calendar_id,record.external_id,serde_json::to_string(record).unwrap()]).unwrap();
}

#[test]
fn plan_calendar_reads_only_its_schedules_and_preserves_ownership_and_evidence() {
    let root = tempfile::tempdir().unwrap();
    let store = Store::open(root.path()).unwrap();
    store.connection.execute_batch(
        "INSERT INTO plans VALUES('plan',100);
         INSERT INTO plan_pages VALUES('page-a','plan',0),('page-b','plan',1);
         INSERT INTO scans VALUES('page-a','hash-a',100,'unavailable recognition','schedule','stale projection'),
             ('page-b','hash-b',100,NULL,'schedule',NULL),
             ('unrelated','hash-other',0,'unavailable recognition','other-schedule','stale projection');
         INSERT INTO imports VALUES('unrelated','other-schedule','unavailable historical record');
         INSERT INTO owned_events VALUES('unrelated','other-calendar',NULL,'unavailable ownership');",
    ).unwrap();
    store
        .set_setting("preferences", r#"{"calendar_id":"default"}"#)
        .unwrap();
    assert_eq!(
        store.plan_calendar("page-b").unwrap(),
        ("default".into(), false)
    );
    store.select_plan_calendar("plan", "selected").unwrap();
    assert_eq!(
        store.plan_calendar("page-b").unwrap(),
        ("selected".into(), false)
    );

    let historical = import(&store, "event", "historical-calendar");
    assert_eq!(
        store.plan_calendar("page-b").unwrap(),
        ("historical-calendar".into(), true)
    );
    let mut current = OwnedEventRecord::from(historical.clone());
    current.calendar_id = "moved-calendar".into();
    current.external_id = Some("new-external-id".into());
    current.approved.title = "Live value must not replace approved evidence".into();
    ownership(&store, &current);
    assert_eq!(
        store.plan_calendar("plan").unwrap(),
        ("moved-calendar".into(), true)
    );
    let records = store.resolved_import_records(Some("schedule")).unwrap();
    assert_eq!(records.len(), 1); // Two pages referencing one schedule do not duplicate events.
    assert_eq!(records[0].calendar_id, "moved-calendar");
    assert_eq!(records[0].external_id.as_deref(), Some("new-external-id"));
    assert_eq!(records[0].approved, historical.approved);
    assert_eq!(records[0].operation_id, historical.operation_id);

    current.status = "removed".into();
    ownership(&store, &current);
    let records = store.resolved_import_records(Some("schedule")).unwrap();
    assert_eq!(records[0].status, "removed");
    assert_eq!(records[0].external_id, None);
    assert_eq!(
        store.plan_calendar("plan").unwrap(),
        ("moved-calendar".into(), true)
    );
    assert!(store.select_plan_calendar("page-a", "different").is_err());
    import(&store, "second-event", "other-calendar");
    assert!(store
        .plan_calendar("plan")
        .unwrap_err()
        .to_string()
        .contains("mehreren Kalendern"));

    let raw: String = store
        .connection
        .query_row("SELECT record FROM imports WHERE id='event'", [], |r| {
            r.get(0)
        })
        .unwrap();
    assert_eq!(raw, serde_json::to_string(&historical).unwrap());
    let stale: usize = store
        .connection
        .query_row(
            "SELECT count(*) FROM scans WHERE run_summary='stale projection'",
            [],
            |r| r.get(0),
        )
        .unwrap();
    assert_eq!(stale, 2); // Calendar lookup does not refresh any recognition cache.
}
