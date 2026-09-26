use reha_core::{
    contracts::*,
    service::{self, Application, Platform},
    store::{Store, STORE_VERSION},
};
use std::sync::Arc;

#[test]
fn future_schema_is_rejected_without_downgrade_or_mutation() {
    let dir = tempfile::tempdir().unwrap();
    let db = rusqlite::Connection::open(dir.path().join("ledger.sqlite")).unwrap();
    db.execute_batch("CREATE TABLE future(value TEXT); INSERT INTO future VALUES('preserve'); PRAGMA user_version=999;").unwrap();
    assert!(Store::open(dir.path()).is_err());
    assert_eq!(
        db.pragma_query_value(None, "user_version", |r| r.get::<_, u32>(0))
            .unwrap(),
        999
    );
    assert_eq!(
        db.query_row("SELECT value FROM future", [], |r| r.get::<_, String>(0))
            .unwrap(),
        "preserve"
    );
}

#[test]
fn migration_failure_rolls_back_the_entire_upgrade() {
    let dir = tempfile::tempdir().unwrap();
    let db = rusqlite::Connection::open(dir.path().join("ledger.sqlite")).unwrap();
    db.execute_batch("CREATE TABLE intakes(collision TEXT); PRAGMA user_version=1;")
        .unwrap();
    assert!(Store::open(dir.path()).is_err());
    assert_eq!(
        db.pragma_query_value(None, "user_version", |r| r.get::<_, u32>(0))
            .unwrap(),
        1
    );
    assert_eq!(
        db.query_row(
            "SELECT COUNT(*) FROM sqlite_master WHERE name='failures'",
            [],
            |r| r.get::<_, u32>(0)
        )
        .unwrap(),
        0
    );
}

#[test]
fn interrupted_first_creation_initializes_preferences_with_the_schema() {
    for collision in [false, true] {
        let dir = tempfile::tempdir().unwrap();
        let db = rusqlite::Connection::open(dir.path().join("ledger.sqlite")).unwrap();
        if collision {
            db.execute_batch("CREATE TABLE intakes(collision TEXT)")
                .unwrap();
            assert!(Store::open(dir.path()).is_err());
            assert_eq!(
                db.pragma_query_value(None, "user_version", |r| r.get::<_, u32>(0))
                    .unwrap(),
                0
            );
            assert_eq!(
                db.query_row(
                    "SELECT count(*) FROM sqlite_master WHERE name='settings'",
                    [],
                    |r| r.get::<_, u32>(0)
                )
                .unwrap(),
                0,
                "Default preferences roll back with the failed schema"
            );
            db.execute_batch("DROP TABLE intakes").unwrap();
        }
        drop(db);
        let store = Store::open(dir.path()).unwrap();
        let preferences: serde_json::Value =
            serde_json::from_str(&store.setting("preferences").unwrap().unwrap()).unwrap();
        assert_eq!(preferences["retention_days"], 30);
        assert_eq!(
            store
                .connection
                .pragma_query_value(None, "user_version", |r| r.get::<_, u32>(0))
                .unwrap(),
            STORE_VERSION
        );
    }
}

#[test]
fn version_zero_migration_preserves_explicit_preferences_byte_for_byte() {
    let dir = tempfile::tempdir().unwrap();
    let db = rusqlite::Connection::open(dir.path().join("ledger.sqlite")).unwrap();
    let original =
        r#"{ "timezone": "Europe/Vienna", "retention_days": null, "calendar_id": "preserve" }"#;
    db.execute_batch("CREATE TABLE settings(key TEXT PRIMARY KEY,value TEXT NOT NULL)")
        .unwrap();
    db.execute("INSERT INTO settings VALUES('preferences',?1)", [original])
        .unwrap();
    drop(db);
    let store = Store::open(dir.path()).unwrap();
    assert_eq!(
        store.setting("preferences").unwrap().as_deref(),
        Some(original)
    );
    assert_eq!(store.cleanup(i64::MAX).unwrap(), 0);
}

#[test]
fn v2_upgrade_preserves_exact_serialized_records_and_hashes() {
    let dir = tempfile::tempdir().unwrap();
    let store = Store::open(dir.path()).unwrap();
    let run: PipelineRun = serde_json::from_str(include_str!(
        "../../../../ml/evaluation/fixtures/sample-run.json"
    ))
    .unwrap();
    store.save_run(&run).unwrap();
    store
        .set_setting(
            "preferences",
            r#"{"timezone":"Europe/Vienna","calendar_id":"keep-me"}"#,
        )
        .unwrap();
    let before: String = store
        .connection
        .query_row("SELECT run FROM scans", [], |r| r.get(0))
        .unwrap();
    store.connection.execute_batch("DROP TRIGGER batch_documents_insert; DROP TRIGGER batch_documents_update; DROP TABLE batch_documents; DROP INDEX imports_schedule; DROP TRIGGER invalidate_scan_summary; DROP INDEX scans_chronology; DROP INDEX plans_chronology; ALTER TABLE scans DROP COLUMN run_summary; DROP TABLE source_deletions; DROP TABLE owned_events; DROP INDEX pending_operations; DROP TABLE event_mutations; DROP TABLE plan_acceptances; DROP TABLE processing_attempts; DROP TABLE plan_pages; DROP TABLE plans; DROP TABLE batch_operations; DROP TABLE import_batches; DROP TABLE intakes; PRAGMA user_version=2;").unwrap();
    drop(store);
    let store = Store::open(dir.path()).unwrap();
    let after: String = store
        .connection
        .query_row("SELECT run FROM scans", [], |r| r.get(0))
        .unwrap();
    assert_eq!(before, after);
    assert!(store
        .setting("preferences")
        .unwrap()
        .unwrap()
        .contains("keep-me"));
    assert_eq!(
        store
            .connection
            .pragma_query_value(None, "user_version", |r| r.get::<_, u32>(0))
            .unwrap(),
        STORE_VERSION
    );
    assert_eq!(store.cleanup(i64::MAX).unwrap(), 0);
}

#[test]
fn interrupted_capture_is_durable_immutable_and_never_expires() {
    let dir = tempfile::tempdir().unwrap();
    let id = uuid::Uuid::new_v4().to_string();
    let store = Store::open(dir.path()).unwrap();
    let config = PipelineConfig::default();
    store
        .stage_intake(
            &id,
            "broken.heic",
            b"undecodable original bytes",
            &config,
            1,
        )
        .unwrap();
    store.intake_status(&id, "processing", None).unwrap();
    drop(store);
    let store = Store::open(dir.path()).unwrap();
    assert_eq!(store.intakes().unwrap()[0].status, "interrupted");
    store
        .set_setting("preferences", r#"{"retention_days":1}"#)
        .unwrap();
    assert_eq!(store.cleanup(999999999).unwrap(), 0);
    assert_eq!(
        std::fs::read(store.source_path(&id).unwrap()).unwrap(),
        b"undecodable original bytes"
    );
    assert!(store
        .stage_intake(&id, "other.jpg", b"different", &config, 2)
        .is_err());
    store.delete_scan(&id).unwrap();
    assert!(!store.source_path(&id).unwrap().exists());
    assert_eq!(store.intakes().unwrap()[0].status, "deleted");
    assert!(store
        .stage_intake(
            &id,
            "broken.heic",
            b"undecodable original bytes",
            &config,
            3
        )
        .is_err());
}

struct NoEffects;

#[test]
fn reopen_repairs_archive_index_after_original_was_committed() {
    let dir = tempfile::tempdir().unwrap();
    let id = uuid::Uuid::new_v4().to_string();
    let store = Store::open(dir.path()).unwrap();
    store
        .stage_intake(&id, "photo.jpg", b"original", &PipelineConfig::default(), 1)
        .unwrap();
    // Simulate termination after the original rename and before page indexing.
    store
        .connection
        .execute("DELETE FROM plan_pages WHERE scan_id=?1", [&id])
        .unwrap();
    store
        .connection
        .execute("DELETE FROM plans WHERE id=?1", [&id])
        .unwrap();
    store.intake_status(&id, "receiving", None).unwrap();
    drop(store);
    let store = Store::open(dir.path()).unwrap();
    assert_eq!(store.intakes().unwrap()[0].status, "interrupted");
    assert_eq!(store.plans().unwrap()[0].page_ids, vec![id.clone()]);
    assert_eq!(
        std::fs::read(store.source_path(&id).unwrap()).unwrap(),
        b"original"
    );
}

impl Platform for NoEffects {
    fn call(&self, _: &str, _: serde_json::Value) -> service::Response<serde_json::Value> {
        Err("unavailable".into())
    }
    fn progress(&self, _: serde_json::Value) {}
}
#[tokio::test]
async fn decoding_or_model_failure_keeps_the_source_in_both_shells_shared_service() {
    use base64::Engine;
    let dir = tempfile::tempdir().unwrap();
    let state = Arc::new(Application::new(
        Store::open(dir.path()).unwrap(),
        dir.path().join("missing-models"),
    ));
    let id = uuid::Uuid::new_v4().to_string();
    let result = service::scan::import_image(
        Arc::new(NoEffects),
        &state,
        service::inference::ImportRequest {
            id: id.clone(),
            filename: "broken.jpg".into(),
            base64: base64::engine::general_purpose::STANDARD.encode(b"not an image"),
            config: PipelineConfig::default(),
            force: false,
        },
    )
    .await;
    assert!(result.is_err());
    let store = state.store.lock().unwrap();
    assert_eq!(store.intakes().unwrap()[0].status, "failed");
    assert_eq!(
        std::fs::read(store.source_path(&id).unwrap()).unwrap(),
        b"not an image"
    );
}

#[tokio::test]
async fn attempt_journal_failure_does_not_leave_recognition_locked() {
    use base64::Engine;
    let dir = tempfile::tempdir().unwrap();
    let store = Store::open(dir.path()).unwrap();
    store.connection.execute_batch("CREATE TRIGGER fail_attempt BEFORE INSERT ON processing_attempts BEGIN SELECT RAISE(ABORT, 'simulated storage failure'); END;").unwrap();
    let state = Arc::new(Application::new(store, dir.path().join("missing-models")));
    let id = uuid::Uuid::new_v4().to_string();
    let result = service::scan::import_image(
        Arc::new(NoEffects),
        &state,
        service::inference::ImportRequest {
            id: id.clone(),
            filename: "photo.jpg".into(),
            base64: base64::engine::general_purpose::STANDARD.encode(b"retained bytes"),
            config: PipelineConfig::default(),
            force: false,
        },
    )
    .await;
    assert!(result
        .unwrap_err()
        .to_string()
        .contains("simulated storage failure"));
    assert!(state.cancel.lock().unwrap().is_empty());
    assert_eq!(
        std::fs::read(state.store.lock().unwrap().source_path(&id).unwrap()).unwrap(),
        b"retained bytes"
    );
}
