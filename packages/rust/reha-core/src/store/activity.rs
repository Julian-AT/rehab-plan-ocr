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
        let mut query = self.connection.prepare("WITH activity AS (
          SELECT 'capture:'||id AS key,imported_at AS at,'capture' AS source,id AS source_id,id AS document_id,'capture' AS kind,status,1 AS count FROM intakes
          UNION ALL SELECT 'recognition:'||id,started_at,'recognition',id,scan_id,'recognition',status,1 FROM processing_attempts
          UNION ALL SELECT 'import:'||b.id,b.created_at,'import',b.id,json_extract(b.document_ids,'$[0]'),CASE WHEN b.undo_of IS NULL THEN 'import' ELSE 'undo' END,
            CASE WHEN EXISTS(SELECT 1 FROM batch_operations bo JOIN operations o ON o.id=bo.operation_id WHERE bo.batch_id=b.id AND o.status IN ('queued','pending','uncertain')) THEN 'uncertain'
              WHEN EXISTS(SELECT 1 FROM batch_operations bo JOIN operations o ON o.id=bo.operation_id WHERE bo.batch_id=b.id AND o.status IN ('failed','conflict')) THEN 'failed' ELSE 'saved' END,
            (SELECT count(*) FROM batch_operations bo WHERE bo.batch_id=b.id) FROM import_batches b
          UNION ALL SELECT 'event:'||id,created_at,'event',id,NULL,CASE WHEN undo_of IS NULL THEN json_extract(proposal,'$.kind') ELSE 'undo' END,status,1 FROM event_mutations
        ) SELECT key,at,source,source_id,document_id,kind,status,count FROM activity
          WHERE (?1 IS NULL OR at < ?1 OR (at = ?1 AND key < ?2)) AND (?3 IS NULL OR source=?3)
          ORDER BY at DESC,key DESC LIMIT ?4")?;
        let rows = query.query_map(
            params![
                cursor.as_ref().map(|c| c.at),
                cursor.as_ref().map(|c| &c.id),
                source,
                limit + 1
            ],
            |r| {
                Ok(ActivityItem {
                    id: r.get(0)?,
                    created_at: r.get(1)?,
                    source: r.get(2)?,
                    source_id: r.get(3)?,
                    document_id: r.get(4)?,
                    kind: r.get(5)?,
                    status: r.get(6)?,
                    count: r.get(7)?,
                })
            },
        )?;
        let mut items = rows.collect::<std::result::Result<Vec<_>, _>>()?;
        let has_more = items.len() > limit;
        items.truncate(limit);
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
        Ok(ActivityPage { items, next_cursor })
    }
}
