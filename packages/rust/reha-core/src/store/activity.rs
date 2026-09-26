use super::Store;
use crate::{Error, Result};
use rusqlite::params;
use serde::{Deserialize, Serialize};

#[derive(Debug, Serialize, Deserialize)]
pub struct ActivityItem {
    pub id: String,
    pub created_at: i64,
    pub source: String,
    pub source_id: String,
    pub document_id: Option<String>,
    pub kind: String,
    pub status: String,
    pub count: u32,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct ActivityPage {
    pub items: Vec<ActivityItem>,
    pub next_cursor: Option<String>,
}
#[derive(Debug, Serialize, Deserialize, PartialEq, Eq)]
pub struct RecognitionActivityDetail {
    pub document_id: String,
    pub status: String,
    pub error: Option<String>,
}
#[derive(Serialize, Deserialize)]
struct Cursor {
    at: i64,
    id: String,
}

#[derive(Clone, Copy)]
struct Source {
    name: &'static str,
    table: &'static str,
    timestamp: &'static str,
    detail: &'static str,
}

const SOURCES: [Source; 4] = [
    Source {
        name: "capture",
        table: "intakes",
        timestamp: "imported_at",
        detail: "SELECT id,'capture',status,1 FROM intakes WHERE id=?1",
    },
    Source {
        name: "recognition",
        table: "processing_attempts",
        timestamp: "started_at",
        detail: "SELECT scan_id,'recognition',status,1 FROM processing_attempts WHERE id=?1",
    },
    Source {
        name: "import",
        table: "import_batches",
        timestamp: "created_at",
        detail: "SELECT json_extract(b.document_ids,'$[0]'),CASE WHEN b.undo_of IS NULL THEN 'import' ELSE 'undo' END,
            CASE WHEN EXISTS(SELECT 1 FROM batch_operations bo JOIN operations o ON o.id=bo.operation_id WHERE bo.batch_id=b.id AND o.status IN ('queued','pending','uncertain')) THEN 'uncertain'
              WHEN EXISTS(SELECT 1 FROM batch_operations bo JOIN operations o ON o.id=bo.operation_id WHERE bo.batch_id=b.id AND o.status IN ('failed','conflict')) THEN 'failed' ELSE 'saved' END,
            (SELECT count(*) FROM batch_operations bo WHERE bo.batch_id=b.id)
            FROM import_batches b WHERE b.id=?1",
    },
    Source {
        name: "event",
        table: "event_mutations",
        timestamp: "created_at",
        detail: "SELECT NULL,CASE WHEN undo_of IS NULL THEN json_extract(proposal,'$.kind') ELSE 'undo' END,status,1 FROM event_mutations WHERE id=?1",
    },
];

struct Candidate {
    key: String,
    id: String,
    at: i64,
    source: Source,
}

// All identifiers come from SOURCES. Split the prefixed cursor key before
// querying so SQLite can seek the existing (timestamp DESC,id DESC) indexes,
// including within a large group of entries sharing the same timestamp.
fn candidate_query(source: Source, cursor: Option<&Cursor>) -> (String, i64, Option<&str>) {
    let prefix = format!("{}:", source.name);
    let at = cursor.map_or(i64::MAX, |c| c.at);
    let id = cursor.and_then(|c| c.id.strip_prefix(&prefix));
    let timestamp = source.timestamp;
    let predicate = if id.is_some() {
        format!("({timestamp},id)<(?2,?3)")
    } else if cursor.is_none_or(|c| prefix < c.id) {
        format!("{timestamp}<=?2")
    } else {
        format!("{timestamp}<?2")
    };
    (
        format!(
            "SELECT id,{timestamp} FROM {} WHERE {predicate} ORDER BY {timestamp} DESC,id DESC LIMIT ?1",
            source.table
        ),
        at,
        id,
    )
}

impl Store {
    pub fn recognition_activity_detail(&self, id: &str) -> Result<RecognitionActivityDetail> {
        Ok(self.connection.query_row(
            "SELECT scan_id,status,error FROM processing_attempts WHERE id=?1",
            [id],
            |row| {
                Ok(RecognitionActivityDetail {
                    document_id: row.get(0)?,
                    status: row.get(1)?,
                    error: row.get(2)?,
                })
            },
        )?)
    }

    /// One stable chronology derived from existing journals, without loading photos.
    pub fn activity_page(
        &self,
        limit: Option<u32>,
        cursor: Option<&str>,
        source: Option<&str>,
    ) -> Result<ActivityPage> {
        let limit = limit.unwrap_or(50).clamp(1, 100) as usize;
        if cursor.is_some_and(|s| s.len() > 512) {
            return Err(Error::Invalid("Ungültige Verlaufsseite.".into()));
        }
        let cursor: Option<Cursor> = cursor.map(serde_json::from_str).transpose()?;
        if source.is_some_and(|s| !["capture", "recognition", "import", "event"].contains(&s)) {
            return Err(Error::Invalid("Unbekannter Verlaufsfilter.".into()));
        }
        // Preserve the single-query snapshot when reading candidates and then
        // their metadata. An existing caller transaction already provides it.
        let tx = self
            .connection
            .is_autocommit()
            .then(|| self.connection.unchecked_transaction())
            .transpose()?;
        let mut candidates = Vec::new();
        for journal in SOURCES
            .into_iter()
            .filter(|s| source.is_none_or(|name| name == s.name))
        {
            let (sql, at, id) = candidate_query(journal, cursor.as_ref());
            let mut query = self.connection.prepare_cached(&sql)?;
            let mut rows = if let Some(id) = id {
                query.query(params![limit + 1, at, id])?
            } else {
                query.query(params![limit + 1, at])?
            };
            while let Some(row) = rows.next()? {
                let id: String = row.get(0)?;
                candidates.push(Candidate {
                    key: format!("{}:{id}", journal.name),
                    id,
                    at: row.get(1)?,
                    source: journal,
                });
            }
        }
        candidates.sort_unstable_by(|a, b| b.at.cmp(&a.at).then_with(|| b.key.cmp(&a.key)));
        let has_more = candidates.len() > limit;
        candidates.truncate(limit);
        let mut items = Vec::with_capacity(candidates.len());
        for candidate in candidates {
            let (document_id, kind, status, count) = self
                .connection
                .prepare_cached(candidate.source.detail)?
                .query_row([&candidate.id], |row| {
                    Ok((row.get(0)?, row.get(1)?, row.get(2)?, row.get(3)?))
                })?;
            items.push(ActivityItem {
                id: candidate.key,
                created_at: candidate.at,
                source: candidate.source.name.into(),
                source_id: candidate.id,
                document_id,
                kind,
                status,
                count,
            });
        }
        let next_cursor = if has_more {
            items
                .last()
                .map(|i| {
                    serde_json::to_string(&Cursor {
                        at: i.created_at,
                        id: i.id.clone(),
                    })
                })
                .transpose()?
        } else {
            None
        };
        if let Some(tx) = tx {
            tx.commit()?;
        }
        Ok(ActivityPage { items, next_cursor })
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use rusqlite::StatementStatus;

    #[test]
    fn candidate_queries_seek_deep_equal_timestamp_cursors_with_bounded_work() {
        let root = tempfile::tempdir().unwrap();
        let store = Store::open(root.path()).unwrap();
        for size in [1_000, 10_000] {
            store.connection.execute("DELETE FROM intakes", []).unwrap();
            store.connection.execute(
                "WITH RECURSIVE n(i) AS (VALUES(1) UNION ALL SELECT i+1 FROM n WHERE i<?1)
                 INSERT INTO intakes SELECT printf('id-%06d',i),'hash','synthetic',100,'{}','completed',NULL FROM n",
                [size],
            ).unwrap();
            for cursor in [
                None,
                Some(Cursor {
                    at: 100,
                    id: "capture:id-000060".into(),
                }),
            ] {
                let (sql, at, id) = candidate_query(SOURCES[0], cursor.as_ref());
                let mut query = store.connection.prepare(&sql).unwrap();
                let mut count = 0;
                {
                    let mut rows = if let Some(id) = id {
                        query.query(params![51, at, id]).unwrap()
                    } else {
                        query.query(params![51, at]).unwrap()
                    };
                    while rows.next().unwrap().is_some() {
                        count += 1;
                    }
                }
                let steps = query.get_status(StatementStatus::VmStep);
                eprintln!(
                    "activity candidates: rows={size}, cursor={}, vm_steps={steps}",
                    cursor.is_some()
                );
                assert_eq!(count, 51);
                assert!(
                    steps < 2_000,
                    "candidate query scanned history: {steps} VM steps"
                );
                assert_eq!(query.get_status(StatementStatus::FullscanStep), 0);
                assert_eq!(query.get_status(StatementStatus::Sort), 0);
            }
        }
    }
}
