use super::Store;
use crate::{
    contracts::{EventValues, ImportRecord},
    Error, Result,
};
use rusqlite::{params, Connection, OptionalExtension};
use serde::{Deserialize, Serialize};
use serde_json::Value;

/// Calendar ownership is independent of photo/import comparison baselines.
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct OwnedEventRecord {
    pub id: String,
    pub calendar_id: String,
    pub external_id: Option<String>,
    pub approved: EventValues,
    pub status: String,
    pub origin: String,
    pub import_id: Option<String>,
    pub operation_id: String,
}
impl From<ImportRecord> for OwnedEventRecord {
    fn from(r: ImportRecord) -> Self {
        Self {
            import_id: Some(r.id.clone()),
            id: r.id,
            calendar_id: r.calendar_id,
            external_id: r.external_id,
            approved: r.approved,
            status: r.status,
            origin: "import".into(),
            operation_id: r.operation_id,
        }
    }
}
pub(super) fn upsert(connection: &Connection, record: &OwnedEventRecord) -> Result<()> {
    connection.execute("INSERT INTO owned_events(id,calendar_id,external_id,record) VALUES(?1,?2,?3,?4) ON CONFLICT(id) DO UPDATE SET calendar_id=excluded.calendar_id,external_id=excluded.external_id,record=excluded.record",
        params![record.id, record.calendar_id, record.external_id, serde_json::to_string(record)?])?;
    Ok(())
}
type EventMutationRow = (
    String,
    String,
    Option<String>,
    i64,
    Option<String>,
    Option<String>,
);

const RESOLVED_PAGE_IMPORTS: &str = "SELECT i.record,o.record FROM imports i
    LEFT JOIN owned_events o ON o.id=i.id
    WHERE i.schedule_id IN (SELECT schedule_id FROM scans WHERE id IN (SELECT value FROM json_each(?1)))";

fn resolved_records(
    connection: &Connection,
    sql: &str,
    parameters: impl rusqlite::Params,
) -> Result<Vec<ImportRecord>> {
    let mut query = connection.prepare(sql)?;
    let rows = query.query_map(parameters, |row| {
        Ok((row.get::<_, String>(0)?, row.get::<_, Option<String>>(1)?))
    })?;
    rows.map(|row| {
        let (raw, owned) = row?;
        let mut record: ImportRecord = serde_json::from_str(&raw)?;
        if let Some(raw) = owned {
            let current: OwnedEventRecord = serde_json::from_str(&raw)?;
            record.calendar_id = current.calendar_id;
            record.external_id = if current.status == "saved" {
                current.external_id
            } else {
                None
            };
            record.status = current.status;
        }
        Ok(record)
    })
    .collect()
}

impl Store {
    /// Import baselines are historical evidence. Only current identity and
    /// ownership status are overlaid for live reconciliation and undo.
    pub fn resolved_import_records(&self, schedule: Option<&str>) -> Result<Vec<ImportRecord>> {
        if let Some(schedule) = schedule {
            resolved_records(
                &self.connection,
                "SELECT i.record,o.record FROM imports i LEFT JOIN owned_events o ON o.id=i.id WHERE i.schedule_id=?1",
                [schedule],
            )
        } else {
            resolved_records(
                &self.connection,
                "SELECT i.record,o.record FROM imports i LEFT JOIN owned_events o ON o.id=i.id",
                [],
            )
        }
    }

    pub(super) fn resolved_page_imports(&self, pages: &[String]) -> Result<Vec<ImportRecord>> {
        resolved_records(
            &self.connection,
            RESOLVED_PAGE_IMPORTS,
            [serde_json::to_string(pages)?],
        )
    }

    /// Change local ownership only; preserve the original import evidence and
    /// reject a stale inspection atomically before applying any selected change.
    pub(crate) fn repair_owned_links(
        &mut self,
        changes: &[(OwnedEventRecord, OwnedEventRecord)],
    ) -> Result<()> {
        if self.has_unresolved_calendar_writes()? {
            return Err(Error::Invalid(
                "Zuerst ungeklärte Kalendervorgänge prüfen.".into(),
            ));
        }
        let tx = self.connection.transaction()?;
        for (expected, replacement) in changes {
            let raw: Option<String> = tx
                .query_row(
                    "SELECT record FROM owned_events WHERE id=?1",
                    [&expected.id],
                    |r| r.get(0),
                )
                .optional()?;
            let current = raw
                .map(|r| serde_json::from_str::<OwnedEventRecord>(&r))
                .transpose()?;
            if current.as_ref().map(serde_json::to_value).transpose()?
                != Some(serde_json::to_value(expected)?)
            {
                return Err(Error::Invalid(
                    "Die Terminzuordnung wurde geändert. Bitte erneut prüfen.".into(),
                ));
            }
            upsert(&tx, replacement)?;
        }
        tx.commit()?;
        Ok(())
    }

    pub fn owned_records(&self) -> Result<Vec<OwnedEventRecord>> {
        let mut query = self
            .connection
            .prepare("SELECT record FROM owned_events ORDER BY id")?;
        let rows = query.query_map([], |row| row.get::<_, String>(0))?;
        rows.map(|row| Ok(serde_json::from_str::<OwnedEventRecord>(&row?)?))
            .filter(|row: &Result<OwnedEventRecord>| {
                row.as_ref().map_or(true, |r| r.status == "saved")
            })
            .collect()
    }
    pub fn owned_record(&self, id: &str) -> Result<Option<OwnedEventRecord>> {
        let raw: Option<String> = self
            .connection
            .query_row("SELECT record FROM owned_events WHERE id=?1", [id], |r| {
                r.get(0)
            })
            .optional()?;
        raw.map(|s| Ok(serde_json::from_str(&s)?)).transpose()
    }
    pub fn has_unresolved_calendar_writes(&self) -> Result<bool> {
        Ok(self.connection.query_row("SELECT EXISTS(SELECT 1 FROM operations WHERE status IN ('queued','pending','uncertain')) OR EXISTS(SELECT 1 FROM event_mutations WHERE status IN ('pending','uncertain'))", [], |r| r.get(0))?)
    }
    pub fn event_mutation(&self, id: &str) -> Result<Option<Value>> {
        let raw: Option<EventMutationRow> = self.connection.query_row(
            "SELECT proposal,status,result,created_at,undo_of,(SELECT id FROM event_mutations u WHERE u.undo_of=m.id AND u.status IN ('pending','uncertain','saved','acknowledged')) FROM event_mutations m WHERE id=?1",
            [id], |r| Ok((r.get(0)?,r.get(1)?,r.get(2)?,r.get(3)?,r.get(4)?,r.get(5)?))).optional()?;
        raw.map(
            |(proposal, status, result, created_at, undo_of, undone_by)| {
                Ok(serde_json::json!({
                    "id":id,"proposal":serde_json::from_str::<Value>(&proposal)?,"status":status,
                    "result":result.map(|r| serde_json::from_str::<Value>(&r)).transpose()?,
                    "created_at":created_at,"undo_of":undo_of,"undone_by":undone_by
                }))
            },
        )
        .transpose()
    }
}

pub(super) fn finish_owned_mutation(
    connection: &Connection,
    proposal: &crate::service::events::EventProposal,
    result: &Value,
) -> Result<()> {
    let Some(id) = &proposal.owned_id else {
        return Ok(());
    };
    if proposal.kind == crate::service::calendar_mutations::Kind::Remove {
        if let Some(raw) = connection
            .query_row("SELECT record FROM owned_events WHERE id=?1", [id], |r| {
                r.get::<_, String>(0)
            })
            .optional()?
        {
            let mut record: OwnedEventRecord = serde_json::from_str(&raw)?;
            record.status = "removed".into();
            record.operation_id = proposal.token.clone();
            upsert(connection, &record)?;
        }
        return Ok(());
    }
    let event = &result["event"];
    if event["metadata"]["url"].as_str() != Some(format!("reha-calendar://event/{id}").as_str())
        || event["calendar_id"].as_str() != Some(proposal.calendar_id.as_str())
        || event["external_id"].as_str().is_none_or(str::is_empty)
    {
        return Err(Error::Invalid(
            "Gespeicherte Terminzuordnung nicht bestätigt.".into(),
        ));
    }
    let old: Option<String> = connection
        .query_row("SELECT record FROM owned_events WHERE id=?1", [id], |r| {
            r.get(0)
        })
        .optional()?;
    let old = old
        .map(|s| serde_json::from_str::<OwnedEventRecord>(&s))
        .transpose()?;
    let mut values = event["values"].clone();
    values["notes"] = event["metadata"]["notes"]
        .as_str()
        .unwrap_or_default()
        .into();
    let record = OwnedEventRecord {
        id: id.clone(),
        calendar_id: proposal.calendar_id.clone(),
        external_id: event["external_id"].as_str().map(str::to_string),
        approved: serde_json::from_value(values)?,
        status: "saved".into(),
        origin: old
            .as_ref()
            .map(|r| r.origin.clone())
            .unwrap_or_else(|| proposal.origin.clone()),
        import_id: old.and_then(|r| r.import_id),
        operation_id: proposal.token.clone(),
    };
    upsert(connection, &record)
}
#[cfg(test)]
mod query_tests {
    use super::*;
    use rusqlite::StatementStatus;

    #[test]
    fn plan_import_lookup_work_does_not_grow_with_unrelated_history() {
        let root = tempfile::tempdir().unwrap();
        let store = Store::open(root.path()).unwrap();
        store
            .connection
            .execute_batch(
                "INSERT INTO scans VALUES('page','hash',100,NULL,'selected',NULL);
            INSERT INTO imports VALUES('selected-event','selected','selected evidence');",
            )
            .unwrap();
        for size in [1_000, 10_000] {
            store
                .connection
                .execute("DELETE FROM imports WHERE schedule_id='unrelated'", [])
                .unwrap();
            store.connection.execute("WITH RECURSIVE n(i) AS (VALUES(1) UNION ALL SELECT i+1 FROM n WHERE i<?1)
                INSERT INTO imports SELECT printf('other-%06d',i),'unrelated','unavailable evidence' FROM n",[size]).unwrap();
            let mut query = store.connection.prepare(RESOLVED_PAGE_IMPORTS).unwrap();
            let records = query
                .query_map([r#"["page"]"#], |r| r.get::<_, String>(0))
                .unwrap()
                .collect::<rusqlite::Result<Vec<_>>>()
                .unwrap();
            assert_eq!(records, vec!["selected evidence"]);
            let steps = query.get_status(StatementStatus::VmStep);
            eprintln!("plan calendar imports: unrelated_rows={size}, vm_steps={steps}");
            assert!(
                steps < 1_000,
                "plan import query scanned unrelated history: {steps}"
            );
            assert_eq!(query.get_status(StatementStatus::FullscanStep), 0);
        }
    }
}
