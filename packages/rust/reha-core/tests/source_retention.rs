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
        run.document.source_hash = id.clone();
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
