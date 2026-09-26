//! Verify the linked engine and the numeric contract used by archive queries.
use rusqlite::Connection;

#[test]
fn linked_sqlite_includes_reviewed_security_fixes() {
    assert!(
        rusqlite::version_number() >= 3_053_002,
        "SQLite {} predates the reviewed FTS5 security fixes",
        rusqlite::version()
    );
    let db = Connection::open_in_memory().unwrap();
    let reported: String = db
        .query_row("SELECT sqlite_version()", [], |row| row.get(0))
        .unwrap();
    assert_eq!(reported, rusqlite::version());
}

#[test]
fn unsigned_archive_counts_remain_checked() {
    let db = Connection::open_in_memory().unwrap();
    db.execute_batch("CREATE TABLE entries(value INTEGER)")
        .unwrap();
    let count: usize = db
        .query_row("SELECT count(*) FROM entries", [], |row| row.get(0))
        .unwrap();
    assert_eq!(count, 0);
    let value: u64 = db
        .query_row("SELECT ?1", [i64::MAX], |row| row.get(0))
        .unwrap();
    assert_eq!(value, i64::MAX as u64);
    assert!(db
        .query_row("SELECT -1", [], |row| row.get::<_, u64>(0))
        .is_err());
    assert!(db
        .execute("INSERT INTO entries VALUES(?1)", [u64::MAX])
        .is_err());
}
