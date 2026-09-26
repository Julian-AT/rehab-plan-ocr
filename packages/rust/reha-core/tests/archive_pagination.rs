use reha_core::{
    contracts::*,
    store::{ArchiveStatus, Store},
};

fn scan(store: &Store, index: u32, time: i64) -> String {
    let mut run: PipelineRun = serde_json::from_str(include_str!(
        "../../../../ml/evaluation/fixtures/sample-run.json"
    ))
    .unwrap();
    run.document.id = format!("00000000-0000-4000-8000-{index:012}");
    run.document.imported_at = time;
    store.save_run(&run).unwrap();
    run.document.id
}

fn batch(store: &Store, id: &str, document: &str, undo: Option<&str>, time: i64, status: &str) {
    store
        .connection
        .execute(
            "INSERT INTO import_batches VALUES(?1,?2,'schedule',?3,?4)",
            rusqlite::params![id, serde_json::to_string(&[document]).unwrap(), time, undo],
        )
        .unwrap();
    // Intentionally unavailable full evidence: the list must use status metadata,
    // leaving detailed journal parsing to reconciliation/review.
    store
        .connection
        .execute(
            "INSERT INTO operations VALUES(?1,'schedule','unavailable evidence',?2,NULL)",
            rusqlite::params![id, status],
        )
        .unwrap();
    store
        .connection
        .execute("INSERT INTO batch_operations VALUES(?1,?1,0)", [id])
        .unwrap();
}

#[test]
fn stable_keyset_pages_survive_new_imports_and_skip_removed_sources() {
    let directory = tempfile::tempdir().unwrap();
    let mut store = Store::open(directory.path()).unwrap();
    let ids: Vec<_> = (0..45).map(|i| scan(&store, i, 100)).collect();
    let first = store.archive_page(None, 20).unwrap();
    assert_eq!(first.plans.len(), 20);
    assert_eq!(first.plans[0].id, ids[0]);
    scan(&store, 100, 200); // Newer imports appear on refresh, not in an older cursor.
    store.delete_scan(&ids[21]).unwrap();
    let second = store.archive_page(first.next.as_ref(), 20).unwrap();
    let third = store.archive_page(second.next.as_ref(), 20).unwrap();
    assert!(third.next.is_none());
    let actual: Vec<_> = first
        .plans
        .into_iter()
        .chain(second.plans)
        .chain(third.plans)
        .map(|p| p.id)
        .collect();
    assert_eq!(
        actual,
        ids.into_iter()
            .filter(|id| id != &format!("00000000-0000-4000-8000-{:012}", 21))
            .collect::<Vec<_>>()
    );
    assert!(store.archive_page(None, 0).is_err());
    assert!(store.archive_page(None, 101).is_err());
}

#[test]
fn status_precedence_preserves_pending_undo_partial_saved_and_review_rows() {
    let directory = tempfile::tempdir().unwrap();
    let mut store = Store::open(directory.path()).unwrap();
    let id = scan(&store, 1, 100);
    assert_eq!(
        store.archive_page(None, 20).unwrap().plans[0].status,
        ArchiveStatus::ReadyForReview
    );
    batch(&store, "first", &id, None, 101, "saved");
    batch(&store, "undo", &id, Some("first"), 102, "saved");
    assert_eq!(
        store.archive_page(None, 20).unwrap().plans[0].status,
        ArchiveStatus::Undone
    );
    store
        .connection
        .execute(
            "UPDATE operations SET status='uncertain' WHERE id='first'",
            [],
        )
        .unwrap();
    assert_eq!(
        store.archive_page(None, 20).unwrap().plans[0].status,
        ArchiveStatus::ReconciliationNeeded
    );
    store
        .connection
        .execute("UPDATE operations SET status='saved'", [])
        .unwrap();
    store
        .connection
        .execute("UPDATE import_batches SET undo_of=NULL", [])
        .unwrap();
    store.bind_schedule(&id, "schedule", "fingerprint").unwrap();
    store
        .connection
        .execute(
            "INSERT INTO imports VALUES('event','schedule','unavailable evidence')",
            [],
        )
        .unwrap();
    let page = store.archive_page(None, 20).unwrap();
    assert!(page.plans[0].item_count > 1);
    assert_eq!(page.plans[0].status, ArchiveStatus::PartiallySaved);
    for i in 1..page.plans[0].item_count {
        store
            .connection
            .execute(
                "INSERT INTO imports VALUES(?1,'schedule','unavailable evidence')",
                [format!("event-{i}")],
            )
            .unwrap();
    }
    assert_eq!(
        store.archive_page(None, 20).unwrap().plans[0].status,
        ArchiveStatus::Saved
    );
    store.delete_scan(&id).unwrap();
    // Historical import metadata keeps the row visible after source retention.
    let row = store.archive_page(None, 20).unwrap().plans.remove(0);
    assert_eq!(row.item_count, 0);
    assert!(row.dates.is_empty());
    assert_eq!(row.status, ArchiveStatus::Saved);
}

#[test]
fn original_pdf_and_unfinished_pages_remain_visible_without_recognition() {
    let directory = tempfile::tempdir().unwrap();
    let mut store = Store::open(directory.path()).unwrap();
    let id = "11111111-1111-4111-8111-111111111111";
    store
        .stage_intake(
            id,
            "plan.pdf",
            b"%PDF-1.4 synthetic",
            &PipelineConfig::default(),
            100,
        )
        .unwrap();
    let pages = store.pdf_pages(id, 2).unwrap();
    let page = store.archive_page(None, 20).unwrap();
    assert_eq!(page.plans.len(), 1);
    assert_eq!(page.plans[0].page_ids, pages);
    assert_eq!(page.plans[0].status, ArchiveStatus::RecognitionPending);
    store
        .connection
        .execute("UPDATE intakes SET status='deleted'", [])
        .unwrap();
    assert!(store.archive_page(None, 20).unwrap().plans.is_empty());
}

#[test]
fn version_ten_backfill_and_document_membership_updates_preserve_journal_bytes() {
    let directory = tempfile::tempdir().unwrap();
    let store = Store::open(directory.path()).unwrap();
    let first = scan(&store, 1, 100);
    let second = scan(&store, 2, 100);
    batch(&store, "batch", &first, None, 102, "pending");
    let original: String = store
        .connection
        .query_row("SELECT document_ids FROM import_batches", [], |r| r.get(0))
        .unwrap();
    store.connection.execute_batch("DROP TRIGGER batch_documents_insert; DROP TRIGGER batch_documents_update; DROP TABLE batch_documents; DROP INDEX imports_schedule; PRAGMA user_version=10;").unwrap();
    drop(store);
    let mut store = Store::open(directory.path()).unwrap();
    assert_eq!(
        store
            .connection
            .query_row("SELECT document_ids FROM import_batches", [], |r| r
                .get::<_, String>(0))
            .unwrap(),
        original
    );
    let page = store.archive_page(None, 20).unwrap();
    assert_eq!(page.plans[0].status, ArchiveStatus::ReconciliationNeeded);
    assert_eq!(page.plans[1].status, ArchiveStatus::ReadyForReview);
    store
        .connection
        .execute(
            "UPDATE import_batches SET document_ids=?1",
            [serde_json::to_string(&[second]).unwrap()],
        )
        .unwrap();
    let page = store.archive_page(None, 20).unwrap();
    assert_eq!(page.plans[0].status, ArchiveStatus::ReadyForReview);
    assert_eq!(page.plans[1].status, ArchiveStatus::ReconciliationNeeded);
    store
        .connection
        .execute("DELETE FROM batch_operations", [])
        .unwrap();
    store
        .connection
        .execute("DELETE FROM import_batches", [])
        .unwrap();
    assert_eq!(
        store
            .connection
            .query_row("SELECT COUNT(*) FROM batch_documents", [], |r| r
                .get::<_, u32>(0))
            .unwrap(),
        0
    );
}

#[test]
fn excluded_rows_do_not_make_a_saved_selection_partial_and_old_caches_rebuild() {
    let directory = tempfile::tempdir().unwrap();
    let store = Store::open(directory.path()).unwrap();
    let id = scan(&store, 1, 100);
    let mut run = store.load_run(&id).unwrap();
    run.appointments.truncate(2);
    run.appointments[0].included = true;
    run.appointments[1].included = false;
    store.save_run(&run).unwrap();
    store.bind_schedule(&id, "schedule", "fingerprint").unwrap();
    store
        .connection
        .execute_batch("INSERT INTO imports VALUES('saved-event','schedule','retained journal');")
        .unwrap();
    let original: String = store
        .connection
        .query_row("SELECT run FROM scans", [], |r| r.get(0))
        .unwrap();
    // Version one counted recognized rows without recording the included selection.
    store.connection.execute_batch("UPDATE scans SET run_summary='{\"version\":1,\"item_count\":2,\"pending_count\":0,\"dates\":[]}'").unwrap();
    drop(store);
    let mut store = Store::open(directory.path()).unwrap();
    let summary = store.archive_page(None, 20).unwrap().plans.remove(0);
    assert_eq!(
        summary.item_count, 2,
        "Retain the recognized-row display count"
    );
    assert_eq!(summary.status, ArchiveStatus::Saved);
    assert_eq!(
        store
            .connection
            .query_row("SELECT run FROM scans", [], |r| r.get::<_, String>(0))
            .unwrap(),
        original
    );
    assert_eq!(
        store
            .connection
            .query_row("SELECT record FROM imports", [], |r| r.get::<_, String>(0))
            .unwrap(),
        "retained journal"
    );
    run.appointments[1].included = true;
    store.save_run(&run).unwrap();
    assert_eq!(
        store.archive_page(None, 20).unwrap().plans[0].status,
        ArchiveStatus::PartiallySaved
    );
}

#[test]
fn equal_second_import_undo_and_reimport_follow_committed_insertion_order() {
    let directory = tempfile::tempdir().unwrap();
    let store = Store::open(directory.path()).unwrap();
    let id = scan(&store, 1, 100);
    batch(&store, "a-original", &id, None, 101, "saved");
    batch(&store, "z-undo", &id, Some("a-original"), 101, "saved");
    drop(store);
    let mut store = Store::open(directory.path()).unwrap();
    assert_eq!(
        store.archive_page(None, 20).unwrap().plans[0].status,
        ArchiveStatus::Undone
    );
    batch(&store, "m-reimport", &id, None, 101, "saved");
    store.bind_schedule(&id, "schedule", "fingerprint").unwrap();
    let count = store.archive_page(None, 20).unwrap().plans[0].item_count;
    for index in 0..count {
        store
            .connection
            .execute(
                "INSERT INTO imports VALUES(?1,'schedule','retained journal')",
                [format!("event-{index}")],
            )
            .unwrap();
    }
    drop(store);
    let mut store = Store::open(directory.path()).unwrap();
    assert_eq!(
        store.archive_page(None, 20).unwrap().plans[0].status,
        ArchiveStatus::Saved
    );
}

#[test]
fn saved_page_does_not_claim_an_unprocessed_group_is_complete() {
    let directory = tempfile::tempdir().unwrap();
    let mut store = Store::open(directory.path()).unwrap();
    let id = scan(&store, 1, 100);
    let other = "11111111-1111-4111-8111-111111111111";
    store
        .stage_intake(
            other,
            "pending.png",
            b"synthetic",
            &PipelineConfig::default(),
            100,
        )
        .unwrap();
    store.group_pages(&id, &[id.clone(), other.into()]).unwrap();
    store.bind_schedule(&id, "schedule", "fingerprint").unwrap();
    let count = store.archive_page(None, 20).unwrap().plans[0].item_count;
    for index in 0..count {
        store
            .connection
            .execute(
                "INSERT INTO imports VALUES(?1,'schedule','retained journal')",
                [format!("event-{index}")],
            )
            .unwrap();
    }
    assert_eq!(
        store.archive_page(None, 20).unwrap().plans[0].status,
        ArchiveStatus::PartiallySaved
    );
}
