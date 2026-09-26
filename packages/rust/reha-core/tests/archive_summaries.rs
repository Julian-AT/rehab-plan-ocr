use reha_core::{contracts::PipelineRun, store::Store};

fn fixture() -> PipelineRun {
    let mut run: PipelineRun = serde_json::from_str(include_str!(
        "../../../../ml/evaluation/fixtures/sample-run.json"
    ))
    .unwrap();
    run.document.id = uuid::Uuid::new_v4().to_string();
    run
}

fn original(store: &Store, id: &str) -> String {
    store
        .connection
        .query_row("SELECT run FROM scans WHERE id=?1", [id], |r| r.get(0))
        .unwrap()
}

#[test]
fn save_and_raw_transaction_updates_keep_archive_summaries_current() {
    let directory = tempfile::tempdir().unwrap();
    let store = Store::open(directory.path()).unwrap();
    let mut run = fixture();
    store.save_run(&run).unwrap();
    assert_eq!(
        store.list_scans().unwrap()[0].item_count,
        run.appointments.len()
    );
    run.appointments.truncate(1);
    run.appointments[0].date = Some("2030-09-18".into());
    run.appointments[0].included = false;
    let raw = serde_json::to_string(&run).unwrap();
    // Draft acceptance and batch completion also write run JSON inside their
    // own transactions. The cache must never conceal such a change.
    store
        .connection
        .execute(
            "UPDATE scans SET run=?2 WHERE id=?1",
            rusqlite::params![run.document.id, raw],
        )
        .unwrap();
    assert!(store
        .connection
        .query_row("SELECT run_summary IS NULL FROM scans", [], |r| r
            .get::<_, bool>(0))
        .unwrap());
    let rows = store.list_scans().unwrap();
    assert_eq!(rows[0].item_count, 1);
    assert_eq!(rows[0].pending_count, 0);
    assert_eq!(rows[0].dates, ["2030-09-18"]);
    assert_eq!(original(&store, &run.document.id), raw);
    drop(store);
    let store = Store::open(directory.path()).unwrap();
    assert_eq!(store.list_scans().unwrap()[0].dates, ["2030-09-18"]);
}

#[test]
fn deletion_clears_derived_dates_and_corrupt_cache_is_rebuilt_from_original() {
    let directory = tempfile::tempdir().unwrap();
    let store = Store::open(directory.path()).unwrap();
    let run = fixture();
    store.save_run(&run).unwrap();
    let raw = original(&store, &run.document.id);
    store
        .connection
        .execute("UPDATE scans SET run_summary='broken cache'", [])
        .unwrap();
    assert_eq!(
        store.list_scans().unwrap()[0].item_count,
        run.appointments.len()
    );
    assert_eq!(original(&store, &run.document.id), raw);
    store
        .connection
        .execute(
            "UPDATE scans SET run_summary=?1",
            [r#"{"version":255,"item_count":999,"pending_count":0,"dates":["2999-01-01"]}"#],
        )
        .unwrap();
    assert_eq!(
        store.list_scans().unwrap()[0].item_count,
        run.appointments.len()
    );
    store.delete_scan(&run.document.id).unwrap();
    let rows = store.list_scans().unwrap();
    assert!(!rows[0].retained);
    assert!(rows[0].dates.is_empty());
    assert_eq!((rows[0].item_count, rows[0].pending_count), (0, 0));
}

#[test]
fn version_nine_backfill_preserves_original_bytes_preferences_and_approval_values() {
    let directory = tempfile::tempdir().unwrap();
    let store = Store::open(directory.path()).unwrap();
    let run = fixture();
    store.save_run(&run).unwrap();
    store
        .set_setting(
            "preferences",
            r#"{"retention_days":0,"calendar_id":"preserve"}"#,
        )
        .unwrap();
    let raw = original(&store, &run.document.id);
    store
        .connection
        .execute_batch(
            "DROP TRIGGER batch_documents_insert; DROP TRIGGER batch_documents_update; DROP TABLE batch_documents; DROP INDEX imports_schedule; DROP TRIGGER invalidate_scan_summary;
        DROP INDEX scans_chronology; DROP INDEX plans_chronology;
        ALTER TABLE scans DROP COLUMN run_summary; PRAGMA user_version=9;",
        )
        .unwrap();
    drop(store);
    let store = Store::open(directory.path()).unwrap();
    assert_eq!(original(&store, &run.document.id), raw);
    assert_eq!(
        store.setting("preferences").unwrap().unwrap(),
        r#"{"retention_days":0,"calendar_id":"preserve"}"#
    );
    assert_eq!(
        store.list_scans().unwrap()[0].item_count,
        run.appointments.len()
    );
    let summaries: usize = store
        .connection
        .query_row(
            "SELECT COUNT(*) FROM scans WHERE run_summary IS NOT NULL",
            [],
            |r| r.get(0),
        )
        .unwrap();
    assert_eq!(summaries, 1);
}

#[test]
fn equal_import_times_have_stable_indexed_order() {
    let directory = tempfile::tempdir().unwrap();
    let store = Store::open(directory.path()).unwrap();
    let mut ids = vec![];
    for _ in 0..3 {
        let run = fixture();
        ids.push(run.document.id.clone());
        store.save_run(&run).unwrap();
    }
    ids.sort();
    assert_eq!(
        store
            .list_scans()
            .unwrap()
            .into_iter()
            .map(|s| s.id)
            .collect::<Vec<_>>(),
        ids
    );
    let plan: String = store
        .connection
        .query_row(
            "EXPLAIN QUERY PLAN SELECT id FROM scans ORDER BY imported_at DESC,id",
            [],
            |r| r.get(3),
        )
        .unwrap();
    assert!(plan.contains("scans_chronology"));
}
