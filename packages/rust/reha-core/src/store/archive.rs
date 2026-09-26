//! Bounded archive projections. Full recognition and calendar evidence stay in detail APIs.
use super::{summaries::ContentSummary, Store};
use crate::{Error, Result};
use rusqlite::{params, Connection, OptionalExtension};
use serde::{Deserialize, Serialize};

#[derive(Clone, Debug, Serialize, Deserialize, PartialEq, Eq)]
pub struct ArchiveCursor {
    pub imported_at: i64,
    pub id: String,
}

#[derive(Clone, Debug, Serialize, Deserialize, PartialEq, Eq)]
pub enum ArchiveStatus {
    ReconciliationNeeded,
    Undone,
    Saved,
    PartiallySaved,
    RecognitionPending,
    ReadyForReview,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct PlanSummary {
    pub id: String,
    pub imported_at: i64,
    pub page_ids: Vec<String>,
    pub item_count: u64,
    pub dates: Vec<String>,
    pub status: ArchiveStatus,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct ArchivePage {
    pub plans: Vec<PlanSummary>,
    pub next: Option<ArchiveCursor>,
}

const VISIBLE_PLANS: &str = "SELECT p.id,p.imported_at FROM plans p
    WHERE EXISTS(SELECT 1 FROM plan_pages WHERE plan_id=p.id)
    AND (
        EXISTS(SELECT 1 FROM plan_pages pp JOIN scans s ON s.id=pp.scan_id
               WHERE pp.plan_id=p.id AND s.run IS NOT NULL)
        OR EXISTS(SELECT 1 FROM intakes i WHERE i.status!='deleted' AND
            (i.id=p.id OR i.id IN(SELECT scan_id FROM plan_pages WHERE plan_id=p.id)))
        OR EXISTS(SELECT 1 FROM plan_pages pp JOIN batch_documents d ON d.document_id=pp.scan_id
                  WHERE pp.plan_id=p.id)
        OR EXISTS(SELECT 1 FROM plan_pages pp JOIN scans s ON s.id=pp.scan_id
                  JOIN imports i ON i.schedule_id=s.schedule_id WHERE pp.plan_id=p.id)
    )
    AND p.imported_at<=?1 AND (p.imported_at<?1 OR ?2 IS NULL OR p.id>?2)
    ORDER BY p.imported_at DESC,p.id LIMIT ?3";

impl Store {
    pub fn archive_page(
        &mut self,
        after: Option<&ArchiveCursor>,
        limit: u32,
    ) -> Result<ArchivePage> {
        if !(1..=100).contains(&limit) {
            return Err(Error::Invalid(
                "Archivseitengröße muss 1 bis 100 sein.".into(),
            ));
        }
        // One consistent snapshot covers visibility, metadata and cache recovery.
        let tx = self.connection.transaction()?;
        let mut rows = tx
            .prepare(VISIBLE_PLANS)?
            .query_map(
                params![
                    after.map_or(i64::MAX, |c| c.imported_at),
                    after.map(|c| &c.id),
                    limit + 1
                ],
                |r| Ok((r.get::<_, String>(0)?, r.get::<_, i64>(1)?)),
            )?
            .collect::<std::result::Result<Vec<_>, _>>()?;
        let more = rows.len() > limit as usize;
        rows.truncate(limit as usize);
        let next = if more {
            rows.last().map(|(id, imported_at)| ArchiveCursor {
                id: id.clone(),
                imported_at: *imported_at,
            })
        } else {
            None
        };
        let plans = rows
            .into_iter()
            .map(|(id, imported_at)| summarize(&tx, id, imported_at))
            .collect::<Result<_>>()?;
        tx.commit()?;
        Ok(ArchivePage { plans, next })
    }
}

fn summarize(connection: &Connection, id: String, imported_at: i64) -> Result<PlanSummary> {
    let pages = connection
        .prepare(
            "SELECT pp.scan_id,s.id IS NOT NULL,s.run_summary,
         CASE WHEN s.run_summary IS NULL THEN s.run END
         FROM plan_pages pp LEFT JOIN scans s ON s.id=pp.scan_id
         WHERE pp.plan_id=?1 ORDER BY pp.ordinal,pp.scan_id",
        )?
        .query_map([&id], |r| {
            Ok((
                r.get::<_, String>(0)?,
                r.get::<_, bool>(1)?,
                r.get::<_, Option<String>>(2)?,
                r.get::<_, Option<String>>(3)?,
            ))
        })?
        .collect::<std::result::Result<Vec<_>, _>>()?;
    let mut summary = PlanSummary {
        id,
        imported_at,
        page_ids: vec![],
        item_count: 0,
        dates: vec![],
        status: ArchiveStatus::ReadyForReview,
    };
    let mut scan_count = 0;
    for (page, exists, cached, raw) in pages {
        if exists {
            let content = ContentSummary::load(connection, &page, cached.as_deref(), raw)?;
            summary.item_count += content.item_count as u64;
            summary.dates.extend(content.dates);
            scan_count += 1;
        }
        summary.page_ids.push(page);
    }
    summary.dates.sort();
    summary.dates.dedup();
    let pending: bool = connection.query_row(
        "SELECT EXISTS(SELECT 1 FROM plan_pages pp JOIN batch_documents d ON d.document_id=pp.scan_id
         JOIN batch_operations bo ON bo.batch_id=d.batch_id JOIN operations o ON o.id=bo.operation_id
         WHERE pp.plan_id=?1 AND o.status IN ('pending','uncertain','queued'))", [&summary.id], |r| r.get(0))?;
    let latest: Option<(String, bool)> = connection
        .query_row(
            "SELECT b.id,b.undo_of IS NOT NULL FROM import_batches b WHERE b.id IN(
         SELECT d.batch_id FROM batch_documents d JOIN plan_pages pp ON pp.scan_id=d.document_id
         WHERE pp.plan_id=?1) ORDER BY b.created_at DESC,b.id LIMIT 1",
            [&summary.id],
            |r| Ok((r.get(0)?, r.get(1)?)),
        )
        .optional()?;
    let undone = if let Some((batch, true)) = latest {
        connection.query_row("SELECT NOT EXISTS(SELECT 1 FROM batch_operations bo JOIN operations o ON o.id=bo.operation_id WHERE bo.batch_id=?1 AND o.status NOT IN ('saved','skipped'))", [batch], |r| r.get::<_, bool>(0))?
    } else {
        false
    };
    let saved: u64 = connection.query_row(
        "SELECT COUNT(*) FROM imports WHERE schedule_id IN(
         SELECT s.schedule_id FROM scans s JOIN plan_pages pp ON pp.scan_id=s.id WHERE pp.plan_id=?1)", [&summary.id], |r| r.get(0))?;
    summary.status = if pending {
        ArchiveStatus::ReconciliationNeeded
    } else if undone {
        ArchiveStatus::Undone
    } else if saved > 0 && saved >= summary.item_count {
        ArchiveStatus::Saved
    } else if saved > 0 {
        ArchiveStatus::PartiallySaved
    } else if scan_count < summary.page_ids.len() {
        ArchiveStatus::RecognitionPending
    } else {
        ArchiveStatus::ReadyForReview
    };
    Ok(summary)
}
