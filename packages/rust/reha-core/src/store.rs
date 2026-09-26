use crate::{contracts::*, Error, Result};
use rusqlite::{params, Connection, OptionalExtension};
use serde::{Deserialize, Serialize};
use std::path::{Path, PathBuf};

mod activity;
mod archive;
mod batches;
pub mod bookkeeping;
pub use activity::{ActivityItem, ActivityPage, RecognitionActivityDetail};
mod event_mutations;
mod intake;
mod migrations;
mod owned_events;
mod plans;
mod retention;
mod summaries;
pub use archive::{ArchiveCursor, ArchivePage, ArchiveStatus, PlanSummary};
pub use batches::{BatchOperation, ImportBatch};
pub use intake::Intake;
pub use migrations::STORE_VERSION;
pub use owned_events::OwnedEventRecord;
pub use plans::Plan;

pub struct Store {
    pub connection: Connection,
    root: PathBuf,
}
#[derive(Serialize, Deserialize)]
pub struct ScanSummary {
    pub id: String,
    pub imported_at: i64,
    pub retained: bool,
    pub item_count: usize,
    pub pending_count: usize,
    pub dates: Vec<String>,
    pub schedule_id: Option<String>,
}
impl Store {
    pub fn open(root: &Path) -> Result<Self> {
        std::fs::create_dir_all(root.join("scans"))?;
        let mut connection = Connection::open(root.join("ledger.sqlite"))?;
        migrations::migrate(&mut connection)?;
        let store = Self {
            connection,
            root: root.into(),
        };
        store.recover_source_deletions()?;
        store.recover_intakes()?;
        Ok(store)
    }
    pub fn scan_dir(&self, id: &str) -> Result<PathBuf> {
        uuid::Uuid::parse_str(id).map_err(|_| Error::Invalid("Invalid scan ID".into()))?;
        Ok(self.root.join("scans").join(id))
    }
    pub fn record_failure(&self, id: &str, now: i64, record: &serde_json::Value) -> Result<()> {
        self.connection.execute(
            "INSERT OR REPLACE INTO failures VALUES(?1,?2,?3)",
            params![id, now, serde_json::to_string(record)?],
        )?;
        Ok(())
    }
    pub fn failures(&self) -> Result<Vec<serde_json::Value>> {
        let mut query = self
            .connection
            .prepare("SELECT record FROM failures ORDER BY occurred_at DESC")?;
        let rows = query.query_map([], |row| row.get::<_, String>(0))?;
        rows.map(|row| Ok(serde_json::from_str(&row?)?)).collect()
    }
    pub fn save_run(&self, run: &PipelineRun) -> Result<()> {
        if run.schema_version > SCHEMA_VERSION {
            return Err(Error::Invalid("Unsupported run schema".into()));
        }
        let summary = serde_json::to_string(&summaries::ContentSummary::from_run(run))?;
        self.connection.execute("INSERT INTO scans(id,source_hash,imported_at,run,schedule_id,run_summary) VALUES(?1,?2,?3,?4,(SELECT schedule_id FROM scans WHERE source_hash=?2 AND schedule_id IS NOT NULL ORDER BY imported_at DESC LIMIT 1),?5) ON CONFLICT(id) DO UPDATE SET run=excluded.run,run_summary=excluded.run_summary",params![run.document.id,run.document.source_hash,run.document.imported_at,serde_json::to_string(run)?,summary])?;
        self.ensure_page(&run.document.id, run.document.imported_at)?;
        Ok(())
    }
    pub fn load_run(&self, id: &str) -> Result<PipelineRun> {
        let json: Option<String> = self
            .connection
            .query_row("SELECT run FROM scans WHERE id=?1", [id], |r| r.get(0))
            .optional()?
            .flatten();
        let mut run: PipelineRun = serde_json::from_str(&json.ok_or(Error::MissingRun)?)?;
        crate::review::migrate(&mut run)?;
        Ok(run)
    }
    pub fn identical(&self, source_hash: &str) -> Result<Option<String>> {
        Ok(self
            .connection
            .query_row(
                "SELECT id FROM scans WHERE source_hash=?1 ORDER BY imported_at DESC LIMIT 1",
                [source_hash],
                |r| r.get(0),
            )
            .optional()?)
    }
    pub fn list_scans(&self) -> Result<Vec<ScanSummary>> {
        let mut q = self.connection.prepare(
            "SELECT id,imported_at,run IS NOT NULL,schedule_id,run_summary,
             CASE WHEN run_summary IS NULL THEN run END
             FROM scans ORDER BY imported_at DESC,id",
        )?;
        let rows = q.query_map([], |r| {
            Ok((
                r.get::<_, String>(0)?,
                r.get::<_, i64>(1)?,
                r.get::<_, bool>(2)?,
                r.get::<_, Option<String>>(3)?,
                r.get::<_, Option<String>>(4)?,
                r.get::<_, Option<String>>(5)?,
            ))
        })?;
        let rows = rows.collect::<std::result::Result<Vec<_>, _>>()?;
        let mut result = vec![];
        for (id, imported_at, retained, schedule_id, cached, raw) in rows {
            let summary =
                summaries::ContentSummary::load(&self.connection, &id, cached.as_deref(), raw)?;
            result.push(ScanSummary {
                id,
                imported_at,
                retained,
                item_count: summary.item_count,
                pending_count: summary.pending_count,
                dates: summary.dates,
                schedule_id,
            });
        }
        Ok(result)
    }
    pub fn delete_scan(&self, id: &str) -> Result<()> {
        self.delete_sources(&[id.to_owned()])
    }
    pub fn records(&self, schedule_id: Option<&str>) -> Result<Vec<ImportRecord>> {
        let mut q = self
            .connection
            .prepare("SELECT record FROM imports WHERE (?1 IS NULL OR schedule_id=?1)")?;
        let rows = q.query_map([schedule_id], |r| r.get::<_, String>(0))?;
        let mut out = vec![];
        for row in rows {
            out.push(serde_json::from_str(&row?)?);
        }
        Ok(out)
    }
    pub fn equivalent_schedule(&self, fingerprint: &str) -> Result<Option<String>> {
        Ok(self
            .connection
            .query_row(
                "SELECT id FROM schedules WHERE fingerprint=?1 LIMIT 1",
                [fingerprint],
                |r| r.get(0),
            )
            .optional()?)
    }
    pub fn bind_schedule(&self, scan: &str, schedule: &str, fingerprint: &str) -> Result<()> {
        self.connection.execute("INSERT INTO schedules(id,fingerprint) VALUES(?1,?2) ON CONFLICT(id) DO UPDATE SET fingerprint=excluded.fingerprint",params![schedule,fingerprint])?;
        self.connection.execute(
            "UPDATE scans SET schedule_id=?2 WHERE id=?1",
            params![scan, schedule],
        )?;
        Ok(())
    }
    pub fn begin_operation(&self, schedule: &str, op: &CalendarOperation) -> Result<String> {
        if op.requires_resolution || !["create", "update", "remove"].contains(&op.kind.as_str()) {
            return Err(Error::Invalid(
                "Operation is not approved for writing".into(),
            ));
        }
        // Uncertain writes must be reconciled; never create a new attempt blindly.
        let existing:Option<String>=self.connection.query_row("SELECT id FROM operations WHERE json_extract(operation,'$.id')=?1 AND status IN ('queued','pending','uncertain')",[&op.id],|r|r.get(0)).optional()?;
        if let Some(id) = existing {
            return Ok(id);
        }
        let operation_id = uuid::Uuid::new_v4().to_string();
        self.connection.execute(
            "INSERT INTO operations(id,schedule_id,operation,status) VALUES(?1,?2,?3,'pending')",
            params![operation_id, schedule, serde_json::to_string(op)?],
        )?;
        Ok(operation_id)
    }
    pub fn pending(&self) -> Result<Vec<(String, CalendarOperation)>> {
        let mut q = self.connection.prepare(
            "SELECT id,operation FROM operations WHERE status IN ('queued','pending','uncertain')",
        )?;
        let rows = q.query_map([], |r| Ok((r.get::<_, String>(0)?, r.get::<_, String>(1)?)))?;
        let mut out = vec![];
        for row in rows {
            let (id, json) = row?;
            out.push((id, serde_json::from_str(&json)?));
        }
        Ok(out)
    }
    pub fn finish_operation(&mut self, operation_id: &str, result: &CalendarResult) -> Result<()> {
        let tx = self.connection.transaction()?;
        let (schedule, json, status): (String, String, String) = tx.query_row(
            "SELECT schedule_id,operation,status FROM operations WHERE id=?1",
            [operation_id],
            |r| Ok((r.get(0)?, r.get(1)?, r.get(2)?)),
        )?;
        let op: CalendarOperation = serde_json::from_str(&json)?;
        if op.id != result.id {
            return Err(Error::Invalid("Mismatched write result".into()));
        }
        if status == "saved" {
            return Ok(());
        }
        if !["saved", "failed", "uncertain", "conflict"].contains(&result.status.as_str()) {
            return Err(Error::Invalid("Unknown write status".into()));
        }
        if result.status == "saved" {
            if op.kind == "remove" {
                tx.execute("DELETE FROM imports WHERE id=?1", [&op.id])?;
                tx.execute("DELETE FROM owned_events WHERE id=?1", [&op.id])?;
            } else {
                if result.external_id.is_none() {
                    return Err(Error::Invalid("Saved event lacks external ID".into()));
                }
                let record = ImportRecord {
                    id: op.id.clone(),
                    schedule_id: schedule.clone(),
                    calendar_id: op.calendar_id.clone(),
                    external_id: result.external_id.clone(),
                    approved: op
                        .after
                        .clone()
                        .ok_or_else(|| Error::Invalid("Missing approved values".into()))?,
                    status: "saved".into(),
                    operation_id: operation_id.into(),
                };
                tx.execute("INSERT INTO imports(id,schedule_id,record) VALUES(?1,?2,?3) ON CONFLICT(id) DO UPDATE SET record=excluded.record",params![op.id,schedule,serde_json::to_string(&record)?])?;
                owned_events::upsert(&tx, &record.into())?;
            }
        }
        tx.execute(
            "UPDATE operations SET status=?2,result=?3 WHERE id=?1",
            params![operation_id, result.status, serde_json::to_string(result)?],
        )?;
        tx.commit()?;
        Ok(())
    }
    pub fn setting(&self, key: &str) -> Result<Option<String>> {
        Ok(self
            .connection
            .query_row("SELECT value FROM settings WHERE key=?1", [key], |r| {
                r.get(0)
            })
            .optional()?)
    }
    pub fn set_setting(&self, key: &str, value: &str) -> Result<()> {
        self.connection.execute("INSERT INTO settings(key,value) VALUES(?1,?2) ON CONFLICT(key) DO UPDATE SET value=excluded.value",params![key,value])?;
        Ok(())
    }
    pub fn erase_all(&mut self) -> Result<()> {
        let scans = self.root.join("scans");
        if scans.exists() {
            std::fs::remove_dir_all(&scans)?;
        }
        std::fs::create_dir_all(scans)?;
        self.connection.execute_batch("DELETE FROM source_deletions; DELETE FROM owned_events; DELETE FROM event_mutations; DELETE FROM plan_acceptances; DELETE FROM processing_attempts; DELETE FROM plan_pages; DELETE FROM plans; DELETE FROM batch_operations; DELETE FROM import_batches; DELETE FROM intakes; DELETE FROM operations; DELETE FROM imports; DELETE FROM scans; DELETE FROM schedules; DELETE FROM settings; DELETE FROM failures; VACUUM;")?;
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn cleanup_boundary_and_ledger_survives() {
        let temp = tempfile::tempdir().unwrap();
        let store = Store::open(temp.path()).unwrap();
        let id = uuid::Uuid::new_v4().to_string();
        let dir = store.scan_dir(&id).unwrap();
        std::fs::create_dir_all(&dir).unwrap();
        std::fs::write(dir.join("source"), b"private synthetic image").unwrap();
        store
            .connection
            .execute(
                "INSERT INTO scans(id,source_hash,imported_at,run,schedule_id) VALUES(?1,'hash',100,'{\"review_confirmed\":true}','schedule')",
                [&id],
            )
            .unwrap();
        store
            .set_setting("preferences", r#"{"retention_days":null}"#)
            .unwrap();
        assert_eq!(store.cleanup(100 + 30 * 86400 - 1).unwrap(), 0);
        assert!(dir.exists());
        assert_eq!(store.cleanup(100 + 365 * 86400).unwrap(), 0);
        store
            .set_setting("preferences", r#"{"retention_days":30}"#)
            .unwrap();
        assert_eq!(store.cleanup(100 + 30 * 86400).unwrap(), 1);
        assert!(!dir.exists());
        assert_eq!(store.identical("hash").unwrap(), Some(id));
    }
    #[test]
    fn paths_reject_traversal() {
        let temp = tempfile::tempdir().unwrap();
        let store = Store::open(temp.path()).unwrap();
        assert!(store.scan_dir("../outside").is_err());
    }
    #[test]
    fn failure_metadata_survives_until_deleted() {
        let temp = tempfile::tempdir().unwrap();
        let store = Store::open(temp.path()).unwrap();
        store
            .record_failure(
                "synthetic",
                100,
                &serde_json::json!({"status":"failed","error":"model unavailable"}),
            )
            .unwrap();
        store.cleanup(100 + 30 * 86400 - 1).unwrap();
        assert_eq!(store.failures().unwrap().len(), 1);
        store.cleanup(100 + 30 * 86400).unwrap();
        assert_eq!(store.failures().unwrap().len(), 1);
    }
    #[test]
    fn pending_write_is_durable_and_reuses_attempt() {
        let temp = tempfile::tempdir().unwrap();
        let store = Store::open(temp.path()).unwrap();
        let op = CalendarOperation {
            kind: "create".into(),
            id: "owned".into(),
            calendar_id: "dest".into(),
            external_id: None,
            before: None,
            after: None,
            requires_resolution: false,
            reason: String::new(),
        };
        let id = store.begin_operation("day", &op).unwrap();
        drop(store);
        let store = Store::open(temp.path()).unwrap();
        assert_eq!(store.pending().unwrap().len(), 1);
        assert_eq!(store.begin_operation("day", &op).unwrap(), id);
    }
    #[test]
    fn expired_identical_photo_inherits_calendar_identity() {
        let temp = tempfile::tempdir().unwrap();
        let store = Store::open(temp.path()).unwrap();
        let mut run: PipelineRun = serde_json::from_str(include_str!(
            "../../../../ml/evaluation/fixtures/sample-run.json"
        ))
        .unwrap();
        run.document.id = uuid::Uuid::new_v4().to_string();
        run.document.imported_at = 100;
        store.save_run(&run).unwrap();
        store
            .bind_schedule(&run.document.id, "approved-day", "fingerprint")
            .unwrap();
        store.cleanup(100 + 30 * 86400).unwrap();
        run.document.id = uuid::Uuid::new_v4().to_string();
        run.document.imported_at = 100 + 31 * 86400;
        store.save_run(&run).unwrap();
        let latest = store
            .list_scans()
            .unwrap()
            .into_iter()
            .find(|scan| scan.id == run.document.id)
            .unwrap();
        assert_eq!(latest.schedule_id.as_deref(), Some("approved-day"));
    }
    #[test]
    fn partial_and_uncertain_writes_do_not_replace_approved_snapshot() {
        let temp = tempfile::tempdir().unwrap();
        let mut store = Store::open(temp.path()).unwrap();
        let run: PipelineRun = serde_json::from_str(include_str!(
            "../../../../ml/evaluation/fixtures/sample-run.json"
        ))
        .unwrap();
        let approved =
            crate::calendar::event_values(&run.appointments[0], "Europe/Vienna", None).unwrap();
        let mut op = CalendarOperation {
            kind: "create".into(),
            id: uuid::Uuid::new_v4().to_string(),
            calendar_id: "dest".into(),
            external_id: None,
            before: None,
            after: Some(approved.clone()),
            requires_resolution: false,
            reason: String::new(),
        };
        let first = store.begin_operation("day", &op).unwrap();
        store
            .finish_operation(
                &first,
                &CalendarResult {
                    maintenance_warnings: vec![],
                    id: op.id.clone(),
                    status: "saved".into(),
                    external_id: Some("external".into()),
                    error: None,
                },
            )
            .unwrap();
        op.kind = "update".into();
        op.before = Some(approved.clone());
        op.after.as_mut().unwrap().title = "Changed title".into();
        op.external_id = Some("external".into());
        let second = store.begin_operation("day", &op).unwrap();
        store
            .finish_operation(
                &second,
                &CalendarResult {
                    maintenance_warnings: vec![],
                    id: op.id.clone(),
                    status: "uncertain".into(),
                    external_id: None,
                    error: None,
                },
            )
            .unwrap();
        assert_eq!(store.records(None).unwrap()[0].approved, approved);
        assert_eq!(store.pending().unwrap().len(), 1);
        store
            .finish_operation(
                &second,
                &CalendarResult {
                    maintenance_warnings: vec![],
                    id: op.id.clone(),
                    status: "saved".into(),
                    external_id: Some("external".into()),
                    error: None,
                },
            )
            .unwrap();
        assert_eq!(store.records(None).unwrap()[0].approved, op.after.unwrap());
        assert!(store.pending().unwrap().is_empty());
    }
}
