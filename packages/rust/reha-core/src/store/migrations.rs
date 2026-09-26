use crate::{Error, Result};
use rusqlite::{Connection, TransactionBehavior};

pub const STORE_VERSION: u32 = 10;

pub(super) fn migrate(connection: &mut Connection) -> Result<()> {
    // Reject a newer store before changing any pragma or schema. A preserved old
    // binary is not a downgrade strategy: restore its matching backup as well.
    let version: u32 = connection.pragma_query_value(None, "user_version", |r| r.get(0))?;
    if version > STORE_VERSION {
        return Err(Error::Invalid(format!(
            "Datenbankversion {version} benötigt eine neuere App (unterstützt: {STORE_VERSION})."
        )));
    }
    connection.execute_batch("PRAGMA foreign_keys=ON; PRAGMA journal_mode=DELETE; PRAGMA secure_delete=ON; PRAGMA synchronous=FULL;")?;
    let tx = connection.transaction_with_behavior(TransactionBehavior::Immediate)?;
    // Read again after taking the writer lock (another shell may have upgraded).
    let version: u32 = tx.pragma_query_value(None, "user_version", |r| r.get(0))?;
    if version > STORE_VERSION {
        return Err(Error::Invalid(
            "Datenbank wurde von einer neueren App aktualisiert.".into(),
        ));
    }
    if version < 1 {
        tx.execute_batch("CREATE TABLE IF NOT EXISTS scans(id TEXT PRIMARY KEY, source_hash TEXT NOT NULL, imported_at INTEGER NOT NULL, run TEXT, schedule_id TEXT);
            CREATE INDEX IF NOT EXISTS scans_hash ON scans(source_hash);
            CREATE TABLE IF NOT EXISTS imports(id TEXT PRIMARY KEY, schedule_id TEXT NOT NULL, record TEXT NOT NULL);
            CREATE TABLE IF NOT EXISTS operations(id TEXT PRIMARY KEY, schedule_id TEXT NOT NULL, operation TEXT NOT NULL, status TEXT NOT NULL, result TEXT);
            CREATE TABLE IF NOT EXISTS schedules(id TEXT PRIMARY KEY, fingerprint TEXT NOT NULL);
            CREATE TABLE IF NOT EXISTS settings(key TEXT PRIMARY KEY, value TEXT NOT NULL);
            PRAGMA user_version=1;")?;
    }
    if version < 2 {
        tx.execute_batch("CREATE TABLE IF NOT EXISTS failures(id TEXT PRIMARY KEY, occurred_at INTEGER NOT NULL, record TEXT NOT NULL); PRAGMA user_version=2;")?;
    }
    if version < 3 {
        tx.execute_batch("CREATE TABLE intakes(id TEXT PRIMARY KEY, source_hash TEXT NOT NULL, filename TEXT NOT NULL, imported_at INTEGER NOT NULL, config TEXT NOT NULL, status TEXT NOT NULL, error TEXT);
            PRAGMA user_version=3;")?;
    }
    if version < 4 {
        tx.execute_batch("CREATE TABLE import_batches(id TEXT PRIMARY KEY, document_ids TEXT NOT NULL, schedule_id TEXT NOT NULL, created_at INTEGER NOT NULL, undo_of TEXT REFERENCES import_batches(id));
            CREATE TABLE batch_operations(batch_id TEXT NOT NULL REFERENCES import_batches(id), operation_id TEXT PRIMARY KEY REFERENCES operations(id), ordinal INTEGER NOT NULL);
            CREATE UNIQUE INDEX one_batch_undo ON import_batches(undo_of) WHERE undo_of IS NOT NULL;
            PRAGMA user_version=4;")?;
    }
    if version < 5 {
        tx.execute_batch("CREATE TABLE plans(id TEXT PRIMARY KEY, imported_at INTEGER NOT NULL);
            CREATE TABLE plan_pages(scan_id TEXT PRIMARY KEY, plan_id TEXT NOT NULL REFERENCES plans(id), ordinal INTEGER NOT NULL);
            CREATE INDEX plan_page_order ON plan_pages(plan_id,ordinal);
            CREATE TABLE processing_attempts(id TEXT PRIMARY KEY, scan_id TEXT NOT NULL, started_at INTEGER NOT NULL, status TEXT NOT NULL, error TEXT);
            INSERT INTO plans SELECT id,imported_at FROM scans;
            INSERT INTO plans SELECT id,imported_at FROM intakes WHERE id NOT IN (SELECT id FROM plans);
            INSERT INTO plan_pages SELECT id,id,0 FROM plans;
            PRAGMA user_version=5;")?;
        let groups: Vec<(String, String)> = {
            let mut q =
                tx.prepare("SELECT substr(key,7),value FROM settings WHERE key LIKE 'pages:%'")?;
            let rows = q.query_map([], |r| Ok((r.get(0)?, r.get(1)?)))?;
            rows.collect::<std::result::Result<_, _>>()?
        };
        for (parent, json) in groups {
            let ids: Vec<String> = serde_json::from_str(&json)?;
            for (index, id) in ids.iter().enumerate() {
                tx.execute("UPDATE plan_pages SET plan_id=?2,ordinal=?3 WHERE scan_id=?1 AND EXISTS(SELECT 1 FROM plans WHERE id=?2)", rusqlite::params![id,parent,index])?;
            }
        }
    }
    if version < 6 {
        tx.execute_batch("CREATE TABLE plan_acceptances(batch_id TEXT PRIMARY KEY REFERENCES import_batches(id), acceptance TEXT NOT NULL); PRAGMA user_version=6;")?;
    }
    if version < 7 {
        tx.execute_batch("CREATE TABLE event_mutations(id TEXT PRIMARY KEY, created_at INTEGER NOT NULL, proposal TEXT NOT NULL, status TEXT NOT NULL, result TEXT, undo_of TEXT REFERENCES event_mutations(id)); CREATE UNIQUE INDEX one_active_event_undo ON event_mutations(undo_of) WHERE undo_of IS NOT NULL AND status IN ('pending','uncertain','saved','acknowledged'); PRAGMA user_version=7;")?;
    }
    if version < 8 {
        tx.execute_batch("CREATE TABLE owned_events(id TEXT PRIMARY KEY, calendar_id TEXT NOT NULL, external_id TEXT, record TEXT NOT NULL);
            CREATE INDEX owned_external ON owned_events(calendar_id,external_id);
            CREATE INDEX batch_order ON batch_operations(batch_id,ordinal);
            CREATE INDEX batch_chronology ON import_batches(created_at DESC,id DESC);
            CREATE INDEX intake_chronology ON intakes(imported_at DESC,id DESC);
            CREATE INDEX processing_chronology ON processing_attempts(started_at DESC,id DESC);
            CREATE INDEX mutation_chronology ON event_mutations(created_at DESC,id DESC);
            CREATE INDEX pending_operations ON operations(status) WHERE status IN ('queued','pending','uncertain');
            CREATE INDEX pending_mutations ON event_mutations(status) WHERE status IN ('pending','uncertain');
            PRAGMA user_version=8;")?;
        let records = {
            let mut query = tx.prepare("SELECT record FROM imports")?;
            let rows = query.query_map([], |r| r.get::<_, String>(0))?;
            rows.collect::<std::result::Result<Vec<_>, _>>()?
        };
        for raw in records {
            let record: crate::contracts::ImportRecord = serde_json::from_str(&raw)?;
            super::owned_events::upsert(&tx, &record.into())?;
        }
    }
    if version < 9 {
        tx.execute_batch(
            "CREATE TABLE source_deletions(id TEXT PRIMARY KEY); PRAGMA user_version=9;",
        )?;
    }
    if version < 10 {
        tx.execute_batch(
            "ALTER TABLE scans ADD COLUMN run_summary TEXT;
            CREATE INDEX scans_chronology ON scans(imported_at DESC,id);
            CREATE INDEX plans_chronology ON plans(imported_at DESC,id);
            CREATE TRIGGER invalidate_scan_summary AFTER UPDATE OF run ON scans
                WHEN NEW.run IS NOT OLD.run AND NEW.run_summary IS OLD.run_summary
                BEGIN UPDATE scans SET run_summary=NULL WHERE id=NEW.id; END;",
        )?;
        super::summaries::backfill(&tx)?;
        tx.pragma_update(None, "user_version", 10)?;
    }
    tx.commit()?;
    Ok(())
}
