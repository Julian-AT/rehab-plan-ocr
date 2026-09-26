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
