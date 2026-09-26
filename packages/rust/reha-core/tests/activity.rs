use reha_core::store::Store;
use std::collections::HashSet;

struct NoCalendar;
impl reha_core::service::Platform for NoCalendar {
    fn progress(&self, _: serde_json::Value) {}
    fn call(
        &self,
        command: &str,
        _: serde_json::Value,
    ) -> reha_core::service::Response<serde_json::Value> {
        panic!("History read reached the calendar: {command}")
    }
}

#[tokio::test]
async fn recognition_details_keep_attempt_identity_errors_and_legacy_shape_after_reopen() {
    use reha_core::{
        contracts::PipelineConfig,
        service::{events, Application},
    };
    use serde_json::json;
    use std::sync::Arc;
    let root = tempfile::tempdir().unwrap();
    let store = Store::open(root.path()).unwrap();
    let id = uuid::Uuid::new_v4().to_string();
    store
        .stage_intake(
            &id,
            "private filename",
            b"synthetic-invalid-image",
            &PipelineConfig::default(),
            1000,
        )
        .unwrap();
    let failed = store.begin_processing(&id).unwrap();
    store
        .finish_processing(&failed, "failed", Some("Das Testbild ist beschädigt."))
        .unwrap();
    let completed = store.begin_processing(&id).unwrap();
    store
        .finish_processing(&completed, "completed", None)
        .unwrap();
    store.intake_status(&id, "completed", None).unwrap();
    let first = store.recognition_activity_detail(&failed).unwrap();
    let second = store.recognition_activity_detail(&completed).unwrap();
    assert_eq!(first.document_id, id);
    assert_eq!(first.status, "failed");
    assert_eq!(first.error.as_deref(), Some("Das Testbild ist beschädigt."));
    assert_eq!(second.document_id, id);
    assert_eq!(second.status, "completed");
    assert_eq!(second.error, None);
    assert!(store.recognition_activity_detail(&id).is_err());
    assert!(store.recognition_activity_detail("' OR 1=1 --").is_err());
    let before = serde_json::to_value(store.activity_page(None, None, None).unwrap()).unwrap();
    let state = Application::new(store, "missing-models".into());
    for attempt in [&failed, &completed] {
        let legacy = events::dispatch(
            Arc::new(NoCalendar),
            &state,
            "activityDetail",
            json!({"id": format!("recognition:{attempt}")}),
        )
        .await
        .unwrap();
        let typed = state
            .store
            .lock()
            .unwrap()
            .recognition_activity_detail(attempt)
            .unwrap();
        assert_eq!(legacy, serde_json::to_value(typed).unwrap());
        assert_eq!(legacy.as_object().unwrap().len(), 3);
    }
    drop(state);
    let reopened = Store::open(root.path()).unwrap();
    assert_eq!(
        first,
        reopened.recognition_activity_detail(&failed).unwrap()
    );
    assert_eq!(
        second,
        reopened.recognition_activity_detail(&completed).unwrap()
    );
    let recognition = reopened
        .activity_page(None, None, Some("recognition"))
        .unwrap();
    assert_eq!(recognition.items.len(), 2);
    assert!(recognition
        .items
        .iter()
        .all(|row| row.document_id.as_deref() == Some(&id)));
    // Reads leave both attempts, including the earlier failure, unchanged.
    let after = reopened.activity_page(None, None, None).unwrap();
    assert_eq!(before, serde_json::to_value(after).unwrap());
    assert_eq!(
        std::fs::read(reopened.source_path(&id).unwrap()).unwrap(),
        b"synthetic-invalid-image"
    );
}
#[test]
fn activity_keyset_has_no_duplicates_at_equal_timestamps_and_respects_limits() {
    let root = tempfile::tempdir().unwrap();
    let store = Store::open(root.path()).unwrap();
    for i in 0..151 {
        store
            .connection
            .execute(
                "INSERT INTO intakes VALUES(?1,?2,'private filename',1000,'{}','completed',NULL)",
                rusqlite::params![format!("capture-{i:04}"), format!("hash-{i}")],
            )
            .unwrap();
    }
    let first = store.activity_page(None, None, None).unwrap();
    assert_eq!(first.items.len(), 50);
    let mut ids: HashSet<_> = first.items.iter().map(|i| i.id.clone()).collect();
    let mut cursor = first.next_cursor;
    while let Some(ref next) = cursor {
        let page = store.activity_page(Some(1000), Some(next), None).unwrap();
        assert!(page.items.len() <= 100);
        for item in page.items {
            assert!(ids.insert(item.id));
        }
        cursor = page.next_cursor;
    }
    assert_eq!(ids.len(), 151);
    assert!(store
        .activity_page(None, None, Some("event"))
        .unwrap()
        .items
        .is_empty());
    assert!(store.activity_page(None, Some("bad cursor"), None).is_err());
    assert!(store.activity_page(None, None, Some("invalid")).is_err());
    let encoded = serde_json::to_string(&first.items).unwrap();
    assert!(!encoded.contains("private filename") && !encoded.contains("hash-"));
}
#[test]
fn mixed_journals_page_in_exact_timestamp_and_prefixed_id_order() {
    let root = tempfile::tempdir().unwrap();
    let store = Store::open(root.path()).unwrap();
    let mut expected = Vec::new();
    for at in [99, 100, 101] {
        for number in 0..4 {
            let id = format!("{at}-{number}");
            store
                .connection
                .execute(
                    "INSERT INTO intakes VALUES(?1,'hash','synthetic',?2,'{}','completed',NULL)",
                    rusqlite::params![id, at],
                )
                .unwrap();
            store.connection.execute("INSERT INTO processing_attempts VALUES(?1,'document',?2,'failed','test failure')",rusqlite::params![id,at]).unwrap();
            store
                .connection
                .execute(
                    "INSERT INTO import_batches VALUES(?1,'[\"document\"]','schedule',?2,NULL)",
                    rusqlite::params![id, at],
                )
                .unwrap();
            store.connection.execute("INSERT INTO event_mutations VALUES(?1,?2,'{\"kind\":\"create\"}','saved',NULL,NULL)",rusqlite::params![id,at]).unwrap();
            for source in ["capture", "recognition", "import", "event"] {
                expected.push((at, format!("{source}:{id}")));
            }
        }
    }
    expected.sort_by(|a, b| b.cmp(a));
    for source in [
        None,
        Some("capture"),
        Some("recognition"),
        Some("import"),
        Some("event"),
    ] {
        let expected: Vec<_> = expected
            .iter()
            .filter(|(_, id)| source.is_none_or(|s| id.starts_with(&format!("{s}:"))))
            .cloned()
            .collect();
        let mut actual = Vec::new();
        let mut cursor = None;
        loop {
            let page = store
                .activity_page(Some(3), cursor.as_deref(), source)
                .unwrap();
            actual.extend(
                page.items
                    .iter()
                    .map(|item| (item.created_at, item.id.clone())),
            );
            for item in page.items {
                assert_eq!(item.count, if item.source == "import" { 0 } else { 1 });
                assert_eq!(
                    item.kind,
                    if item.source == "event" {
                        "create"
                    } else {
                        &item.source
                    }
                );
            }
            cursor = page.next_cursor;
            if cursor.is_none() {
                break;
            }
        }
        assert_eq!(actual, expected);
    }
    // Changing filters with a cursor from a different journal must respect
    // the same prefixed key ordering at the boundary timestamp.
    let cursor = r#"{"at":100,"id":"import:100-2"}"#;
    for source in ["capture", "recognition", "event"] {
        let actual = store
            .activity_page(Some(100), Some(cursor), Some(source))
            .unwrap();
        let expected: Vec<_> = expected
            .iter()
            .filter(|(at, id)| {
                id.starts_with(&format!("{source}:"))
                    && (*at < 100 || (*at == 100 && id.as_str() < "import:100-2"))
            })
            .cloned()
            .collect();
        assert_eq!(
            actual
                .items
                .iter()
                .map(|item| (item.created_at, item.id.clone()))
                .collect::<Vec<_>>(),
            expected
        );
    }
    let tx = store.connection.unchecked_transaction().unwrap();
    assert_eq!(
        store
            .activity_page(Some(3), None, None)
            .unwrap()
            .items
            .len(),
        3
    );
    tx.rollback().unwrap();
}

#[test]
fn activity_only_decodes_metadata_for_the_returned_page() {
    let root = tempfile::tempdir().unwrap();
    let store = Store::open(root.path()).unwrap();
    store
        .connection
        .execute(
            "INSERT INTO intakes VALUES('recent','hash','synthetic',100,'{}','completed',NULL)",
            [],
        )
        .unwrap();
    store
        .connection
        .execute(
            "INSERT INTO event_mutations VALUES('old',1,'unavailable evidence','saved',NULL,NULL)",
            [],
        )
        .unwrap();
    let first = store.activity_page(Some(1), None, None).unwrap();
    assert_eq!(first.items[0].id, "capture:recent");
    assert!(first.next_cursor.is_some());
    assert!(store
        .activity_page(Some(1), first.next_cursor.as_deref(), None)
        .is_err());
    assert!(store.connection.is_autocommit());
    assert_eq!(
        store
            .activity_page(Some(1), None, Some("capture"))
            .unwrap()
            .items
            .len(),
        1
    );
}

#[test]
fn selected_import_metadata_preserves_status_precedence_counts_and_undo_kind() {
    let root = tempfile::tempdir().unwrap();
    let store = Store::open(root.path()).unwrap();
    store.connection.execute_batch("INSERT INTO import_batches VALUES('batch','[\"document\"]','schedule',100,NULL);
        INSERT INTO operations VALUES('one','schedule','unavailable evidence','saved',NULL),('two','schedule','unavailable evidence','failed',NULL),('three','schedule','unavailable evidence','queued',NULL);
        INSERT INTO batch_operations VALUES('batch','one',0),('batch','two',1),('batch','three',2);").unwrap();
    for (operation_status, expected) in [
        ("queued", "uncertain"),
        ("pending", "uncertain"),
        ("uncertain", "uncertain"),
        ("saved", "failed"),
    ] {
        store
            .connection
            .execute(
                "UPDATE operations SET status=?1 WHERE id='three'",
                [operation_status],
            )
            .unwrap();
        let page = store.activity_page(Some(1), None, Some("import")).unwrap();
        assert_eq!(page.items[0].status, expected);
        assert_eq!(page.items[0].count, 3);
        assert_eq!(page.items[0].document_id.as_deref(), Some("document"));
    }
    store
        .connection
        .execute("UPDATE operations SET status='saved'", [])
        .unwrap();
    assert_eq!(
        store
            .activity_page(Some(1), None, Some("import"))
            .unwrap()
            .items[0]
            .status,
        "saved"
    );
    store
        .connection
        .execute(
            "INSERT INTO import_batches VALUES('undo','[\"document\"]','schedule',101,'batch')",
            [],
        )
        .unwrap();
    let page = store.activity_page(Some(1), None, Some("import")).unwrap();
    assert_eq!(page.items[0].kind, "undo");
    assert_eq!(page.items[0].count, 0);
}
