use reha_core::store::Store;
use std::collections::HashSet;
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
