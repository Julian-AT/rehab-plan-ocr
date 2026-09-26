use reha_core::{contracts::*, store::Store};
use serde_json::Value;

fn document(store: &mut Store) -> (String, Vec<String>) {
    let source = uuid::Uuid::new_v4().to_string();
    store
        .stage_intake(
            &source,
            "synthetic.pdf",
            b"%PDF-synthetic",
            &PipelineConfig::default(),
            100,
        )
        .unwrap();
    let pages = store.pdf_pages(&source, 2).unwrap();
    for id in &pages {
        store
            .stage_intake(
                id,
                "page.png",
                id.as_bytes(),
                &PipelineConfig::default(),
                100,
            )
            .unwrap();
        let mut run: PipelineRun = serde_json::from_str(include_str!(
            "../../../../ml/evaluation/fixtures/sample-run.json"
        ))
        .unwrap();
        run.document.id = id.clone();
        run.document.imported_at = 100;
        run.document.source_hash = reha_core::hash(id.as_bytes());
        run.review_confirmed = true;
        store.save_run(&run).unwrap();
        store.intake_status(id, "completed", None).unwrap();
    }
    (source, pages)
}

#[test]
fn only_new_stores_receive_thirty_days_and_existing_choices_survive_reopen() {
    let root = tempfile::tempdir().unwrap();
    let store = Store::open(root.path()).unwrap();
    let preferences: Value =
        serde_json::from_str(&store.setting("preferences").unwrap().unwrap()).unwrap();
    assert_eq!(preferences["retention_days"], 30);
    for old in [
        r#"{"timezone":"Europe/Vienna","retention_days":null}"#,
        r#"{"timezone":"Europe/Vienna"}"#,
    ] {
        store.set_setting("preferences", old).unwrap();
        let reopened = Store::open(root.path()).unwrap();
        assert_eq!(
            reopened.setting("preferences").unwrap().as_deref(),
            Some(old)
        );
        assert_eq!(reopened.cleanup(i64::MAX).unwrap(), 0);
    }
}

#[test]
fn pdf_retention_waits_for_every_page_then_erases_original_and_cannot_replay() {
    let root = tempfile::tempdir().unwrap();
    let mut store = Store::open(root.path()).unwrap();
    let (source, pages) = document(&mut store);
    let cutoff = 100 + 30 * 86400;
    assert_eq!(store.cleanup(cutoff - 1).unwrap(), 0);
    let mut unfinished = store.load_run(&pages[1]).unwrap();
    unfinished.review_confirmed = false;
    store.save_run(&unfinished).unwrap();
    assert_eq!(store.cleanup(cutoff).unwrap(), 0);
    assert!(store.source_path(&source).unwrap().exists());
    assert!(store.load_run(&pages[0]).is_ok());
    unfinished.review_confirmed = true;
    store.save_run(&unfinished).unwrap();
    assert_eq!(store.cleanup(cutoff).unwrap(), 2);
    drop(store);
    let mut store = Store::open(root.path()).unwrap();
    for id in pages.iter().chain([&source]) {
        assert!(!store.scan_dir(id).unwrap().exists());
        assert!(store
            .intakes()
            .unwrap()
            .iter()
            .any(|i| &i.id == id && i.status == "deleted"));
    }
    assert!(store.pdf_pages(&source, 2).is_err());
    assert_eq!(
        store.page_ids(&source).unwrap(),
        pages,
        "Historical relationships remain intact"
    );
    assert_eq!(store.cleanup(i64::MAX).unwrap(), 0);
}

#[test]
fn interrupted_aggregate_deletion_finishes_before_intake_recovery() {
    let root = tempfile::tempdir().unwrap();
    let mut store = Store::open(root.path()).unwrap();
    let (source, pages) = document(&mut store);
    for id in pages.iter().chain([&source]) {
        store
            .connection
            .execute("INSERT INTO source_deletions VALUES(?1)", [id])
            .unwrap();
    }
    std::fs::remove_dir_all(store.scan_dir(&pages[0]).unwrap()).unwrap();
    drop(store);
    let mut store = Store::open(root.path()).unwrap();
    assert!(store
        .intakes()
        .unwrap()
        .iter()
        .all(|i| i.status == "deleted"));
    assert!(store.pdf_pages(&source, 2).is_err());
    assert!(store.list_scans().unwrap().iter().all(|s| !s.retained));
    assert_eq!(
        store
            .connection
            .query_row("SELECT count(*) FROM source_deletions", [], |r| r
                .get::<_, u32>(0))
            .unwrap(),
        0
    );
}

#[test]
fn legacy_deleted_pages_do_not_leave_the_pdf_original_forever() {
    let root = tempfile::tempdir().unwrap();
    let mut store = Store::open(root.path()).unwrap();
    let (source, pages) = document(&mut store);
    store.delete_sources(&pages).unwrap();
    assert!(store.source_path(&source).unwrap().exists());
    assert_eq!(store.cleanup(100 + 30 * 86400).unwrap(), 0);
    assert!(!store.scan_dir(&source).unwrap().exists());
    assert!(store.pdf_pages(&source, 2).is_err());
}

fn duplicate(store: &Store, source: &str, imported_at: i64) -> String {
    let id = uuid::Uuid::new_v4().to_string();
    store
        .stage_intake(
            &id,
            "duplicate.png",
            source.as_bytes(),
            &PipelineConfig::default(),
            imported_at,
        )
        .unwrap();
    store.intake_status(&id, "duplicate", None).unwrap();
    id
}

#[test]
fn duplicate_capture_expires_with_its_complete_pdf_and_preserves_calendar_journals() {
    let root = tempfile::tempdir().unwrap();
    let mut store = Store::open(root.path()).unwrap();
    let (source, pages) = document(&mut store);
    let duplicate = duplicate(&store, &pages[0], 101);
    store.connection.execute("INSERT INTO operations VALUES('saved','schedule','retained approved values','saved','retained result')", []).unwrap();
    let mut unfinished = store.load_run(&pages[1]).unwrap();
    unfinished.review_confirmed = false;
    store.save_run(&unfinished).unwrap();
    let original = serde_json::to_string(&unfinished).unwrap();
    drop(store);
    let mut store = Store::open(root.path()).unwrap();
    assert!(
        !store
            .archive_page(None, 20)
            .unwrap()
            .plans
            .iter()
            .any(|p| p.id == duplicate),
        "Reuse the existing plan instead of showing phantom recognition work"
    );
    let cutoff = 101 + 30 * 86400;
    assert_eq!(store.cleanup(cutoff).unwrap(), 0);
    assert_eq!(
        serde_json::to_string(&store.load_run(&pages[1]).unwrap()).unwrap(),
        original
    );
    for id in pages.iter().chain([&source, &duplicate]) {
        assert!(store.source_path(id).unwrap().exists());
    }
    unfinished.review_confirmed = true;
    store.save_run(&unfinished).unwrap();
    assert_eq!(
        store.cleanup(cutoff - 1).unwrap(),
        0,
        "The newer duplicate still protects the aggregate"
    );
    assert_eq!(store.cleanup(cutoff).unwrap(), 2);
    drop(store);
    let mut store = Store::open(root.path()).unwrap();
    for id in pages.iter().chain([&source, &duplicate]) {
        assert!(!store.scan_dir(id).unwrap().exists());
        assert!(store
            .intakes()
            .unwrap()
            .iter()
            .any(|i| &i.id == id && i.status == "deleted"));
    }
    assert!(!store
        .archive_page(None, 20)
        .unwrap()
        .plans
        .iter()
        .any(|p| p.id == duplicate));
    assert_eq!(
        store
            .connection
            .query_row(
                "SELECT operation||'/'||result FROM operations WHERE id='saved'",
                [],
                |r| r.get::<_, String>(0)
            )
            .unwrap(),
        "retained approved values/retained result"
    );
}

#[test]
fn duplicate_links_preserve_pending_work_and_other_document_membership() {
    let root = tempfile::tempdir().unwrap();
    let mut store = Store::open(root.path()).unwrap();
    let (_, pages) = document(&mut store);
    let duplicate = duplicate(&store, &pages[0], 100);
    let cutoff = 100 + 30 * 86400;
    let attempt = store.begin_processing(&duplicate).unwrap();
    store.intake_status(&duplicate, "duplicate", None).unwrap();
    assert_eq!(store.cleanup(cutoff).unwrap(), 0);
    store
        .finish_processing(&attempt, "completed", None)
        .unwrap();
    store
        .record_failure(
            &duplicate,
            101,
            &serde_json::json!({"synthetic":"retry needed"}),
        )
        .unwrap();
    assert_eq!(store.cleanup(cutoff).unwrap(), 0);
    store
        .connection
        .execute("DELETE FROM failures WHERE id=?1", [&duplicate])
        .unwrap();
    let pending = uuid::Uuid::new_v4().to_string();
    store
        .stage_intake(
            &pending,
            "pending.png",
            b"unprocessed document member",
            &PipelineConfig::default(),
            100,
        )
        .unwrap();
    store
        .group_pages(&duplicate, &[duplicate.clone(), pending.clone()])
        .unwrap();
    assert_eq!(
        store.cleanup(cutoff).unwrap(),
        0,
        "A duplicate's own plan membership also protects its originals"
    );
    assert!(store.source_path(&duplicate).unwrap().exists());
    assert!(store.source_path(&pending).unwrap().exists());
    store.delete_sources(&[pending]).unwrap();
    assert_eq!(store.cleanup(cutoff).unwrap(), 2);
}

#[test]
fn duplicate_without_original_evidence_remains_visible_and_is_not_deleted() {
    let root = tempfile::tempdir().unwrap();
    let mut store = Store::open(root.path()).unwrap();
    let duplicate = duplicate(&store, "missing source", 100);
    assert_eq!(store.cleanup(i64::MAX).unwrap(), 0);
    assert!(store.source_path(&duplicate).unwrap().exists());
    assert_eq!(store.archive_page(None, 20).unwrap().plans[0].id, duplicate);
}

#[test]
fn duplicate_of_an_explicitly_deleted_legacy_scan_can_expire() {
    let root = tempfile::tempdir().unwrap();
    let store = Store::open(root.path()).unwrap();
    let source = uuid::Uuid::new_v4().to_string();
    store
        .connection
        .execute(
            "INSERT INTO scans(id,source_hash,imported_at,run) VALUES(?1,?2,100,NULL)",
            [&source, &reha_core::hash(source.as_bytes())],
        )
        .unwrap();
    let duplicate = duplicate(&store, &source, 100);
    assert_eq!(store.cleanup(100 + 30 * 86400).unwrap(), 0);
    assert!(!store.source_path(&duplicate).unwrap().exists());
    assert!(store
        .intakes()
        .unwrap()
        .iter()
        .any(|i| i.id == duplicate && i.status == "deleted"));
}
