use super::Store;
use crate::{contracts::*, Error, Result};
use rusqlite::params;
use serde::{Deserialize, Serialize};

#[derive(Clone, Serialize, Deserialize)]
pub struct BatchOperation {
    pub attempt_id: String,
    pub operation: CalendarOperation,
    pub status: String,
    pub result: Option<CalendarResult>,
}
#[derive(Clone, Serialize, Deserialize)]
pub struct ImportBatch {
    pub id: String,
    pub document_ids: Vec<String>,
    pub schedule_id: String,
    pub created_at: i64,
    pub undo_of: Option<String>,
    pub undone_by: Option<String>,
    pub operations: Vec<BatchOperation>,
}
impl Store {
    /// Persist the complete user-authorized intent before the first platform write.
    /// Every operation participates in the existing recovery journal.
    pub fn begin_batch(
        &mut self,
        documents: &[String],
        schedule: &str,
        operations: &[CalendarOperation],
        undo_of: Option<&str>,
    ) -> Result<ImportBatch> {
        self.begin_batch_impl(documents, schedule, operations, undo_of, None)
    }
    pub fn begin_accepted_batch(
        &mut self,
        proposal: &crate::service::Proposal,
        runs: &[PipelineRun],
        acceptance: &crate::readiness::PlanAcceptance,
    ) -> Result<ImportBatch> {
        self.begin_batch_impl(
            &proposal.document_ids,
            &proposal.schedule_id,
            &proposal.operations,
            None,
            Some((proposal, runs, acceptance)),
        )
    }
    fn begin_batch_impl(
        &mut self,
        documents: &[String],
        schedule: &str,
        operations: &[CalendarOperation],
        undo_of: Option<&str>,
        accepted: Option<(
            &crate::service::Proposal,
            &[PipelineRun],
            &crate::readiness::PlanAcceptance,
        )>,
    ) -> Result<ImportBatch> {
        if !self.pending()?.is_empty() {
            return Err(Error::Invalid(
                "Unklare Schreibvorgänge zuerst abgleichen.".into(),
            ));
        }
        let id = uuid::Uuid::new_v4().to_string();
        let tx = self.connection.transaction()?;
        tx.execute(
            "INSERT INTO import_batches VALUES(?1,?2,?3,?4,?5)",
            params![
                id,
                serde_json::to_string(documents)?,
                schedule,
                chrono::Utc::now().timestamp(),
                undo_of
            ],
        )?;
        if let Some((proposal, runs, acceptance)) = accepted {
            tx.execute(
                "INSERT INTO plan_acceptances VALUES(?1,?2)",
                params![id, serde_json::to_string(acceptance)?],
            )?;
            tx.execute("INSERT INTO schedules VALUES(?1,?2) ON CONFLICT(id) DO UPDATE SET fingerprint=excluded.fingerprint", params![schedule, proposal.fingerprint])?;
            for run in runs {
                let mut run = run.clone();
                for a in &mut run.appointments {
                    if let Some(event) = proposal.bindings.get(&a.id) {
                        a.calendar_event_id = Some(event.clone());
                    }
                }
                tx.execute(
                    "UPDATE scans SET run=?2,schedule_id=?3 WHERE id=?1",
                    params![run.document.id, serde_json::to_string(&run)?, schedule],
                )?;
            }
        }
        for (index, op) in operations
            .iter()
            .filter(|o| ["create", "update", "remove"].contains(&o.kind.as_str()))
            .enumerate()
        {
            if op.requires_resolution {
                return Err(Error::Invalid("Unklare Zuordnung.".into()));
            }
            let attempt = uuid::Uuid::new_v4().to_string();
            tx.execute(
                "INSERT INTO operations(id,schedule_id,operation,status) VALUES(?1,?2,?3,'queued')",
                params![attempt, schedule, serde_json::to_string(op)?],
            )?;
            tx.execute(
                "INSERT INTO batch_operations VALUES(?1,?2,?3)",
                params![id, attempt, index],
            )?;
        }
        tx.commit()?;
        self.batches()?
            .into_iter()
            .find(|b| b.id == id)
            .ok_or_else(|| Error::Invalid("Import fehlt.".into()))
    }
    pub fn batches(&self) -> Result<Vec<ImportBatch>> {
        let mut q = self.connection.prepare("SELECT id,document_ids,schedule_id,created_at,undo_of,(SELECT id FROM import_batches u WHERE u.undo_of=b.id) FROM import_batches b ORDER BY created_at DESC,id")?;
        let rows = q.query_map([], |r| {
            Ok((
                r.get::<_, String>(0)?,
                r.get::<_, String>(1)?,
                r.get(2)?,
                r.get(3)?,
                r.get(4)?,
                r.get(5)?,
            ))
        })?;
        let mut batches = vec![];
        for row in rows {
            let (id, documents, schedule_id, created_at, undo_of, undone_by) = row?;
            let mut query = self.connection.prepare("SELECT o.id,o.operation,o.status,o.result FROM batch_operations b JOIN operations o ON b.operation_id=o.id WHERE b.batch_id=?1 ORDER BY b.ordinal")?;
            let rows = query.query_map([&id], |r| {
                Ok((
                    r.get(0)?,
                    r.get::<_, String>(1)?,
                    r.get(2)?,
                    r.get::<_, Option<String>>(3)?,
                ))
            })?;
            let operations = rows
                .map(|r| {
                    let (attempt_id, operation, status, result) = r?;
                    Ok(BatchOperation {
                        attempt_id,
                        operation: serde_json::from_str(&operation)?,
                        status,
                        result: result.map(|v| serde_json::from_str(&v)).transpose()?,
                    })
                })
                .collect::<Result<_>>()?;
            batches.push(ImportBatch {
                id,
                document_ids: serde_json::from_str(&documents)?,
                schedule_id,
                created_at,
                undo_of,
                undone_by,
                operations,
            });
        }
        Ok(batches)
    }
    /// `queued` proves no platform call has started. Every other open status is
    /// reconciled without blindly repeating its effect.
    pub fn start_operation(&self, id: &str) -> Result<bool> {
        let status: String =
            self.connection
                .query_row("SELECT status FROM operations WHERE id=?1", [id], |r| {
                    r.get(0)
                })?;
        if status == "queued" {
            self.connection
                .execute("UPDATE operations SET status='pending' WHERE id=?1", [id])?;
            Ok(false)
        } else if ["pending", "uncertain"].contains(&status.as_str()) {
            Ok(true)
        } else {
            Err(Error::Invalid("Schreibvorgang ist nicht offen.".into()))
        }
    }
    pub fn retry_failed_batch(
        &mut self,
        id: &str,
        operations: &[CalendarOperation],
    ) -> Result<ImportBatch> {
        if !self.pending()?.is_empty() {
            return Err(Error::Invalid(
                "Unklare Schreibvorgänge zuerst abgleichen.".into(),
            ));
        }
        let batch = self
            .batches()?
            .into_iter()
            .find(|b| b.id == id)
            .ok_or_else(|| Error::Invalid("Import fehlt.".into()))?;
        let tx = self.connection.transaction()?;
        for entry in &batch.operations {
            if !["failed", "conflict"].contains(&entry.status.as_str()) {
                continue;
            }
            let retry = operations.iter().any(|op| {
                op.id == entry.operation.id
                    && ["create", "update", "remove"].contains(&op.kind.as_str())
                    && !op.requires_resolution
            });
            tx.execute(
                "UPDATE operations SET status=?2,result=NULL WHERE id=?1",
                params![entry.attempt_id, if retry { "queued" } else { "skipped" }],
            )?;
        }
        tx.commit()?;
        let mut batch = self
            .batches()?
            .into_iter()
            .find(|b| b.id == id)
            .ok_or_else(|| Error::Invalid("Import fehlt.".into()))?;
        batch.operations.retain(|e| e.status == "queued");
        Ok(batch)
    }
}
