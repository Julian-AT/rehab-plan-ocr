//! Small, disposable archive projections. Original recognition JSON is authoritative.
use crate::{contracts::PipelineRun, Result};
use rusqlite::{params, Connection};
use serde::{Deserialize, Serialize};

// Bump when deriving these fields changes; stale projections rebuild from run JSON.
const SUMMARY_VERSION: u8 = 1;

#[derive(Serialize, Deserialize)]
pub(super) struct ContentSummary {
    #[serde(default)]
    version: u8,
    pub item_count: usize,
    pub pending_count: usize,
    pub dates: Vec<String>,
}

impl Default for ContentSummary {
    fn default() -> Self {
        Self {
            version: SUMMARY_VERSION,
            item_count: 0,
            pending_count: 0,
            dates: Vec::new(),
        }
    }
}

impl ContentSummary {
    pub fn load(
        connection: &Connection,
        id: &str,
        cached: Option<&str>,
        mut raw: Option<String>,
    ) -> Result<Self> {
        if let Some(summary) = cached
            .and_then(|value| serde_json::from_str::<Self>(value).ok())
            .filter(Self::current)
        {
            return Ok(summary);
        }
        if cached.is_some() {
            raw = connection.query_row("SELECT run FROM scans WHERE id=?1", [id], |r| r.get(0))?;
        }
        let summary = Self::from_json(raw.as_deref());
        connection.execute(
            "UPDATE scans SET run_summary=?2 WHERE id=?1 AND run IS ?3",
            params![id, serde_json::to_string(&summary)?, raw],
        )?;
        Ok(summary)
    }

    pub fn current(&self) -> bool {
        self.version == SUMMARY_VERSION
    }

    pub fn from_run(run: &PipelineRun) -> Self {
        let mut dates: Vec<_> = run
            .appointments
            .iter()
            .filter_map(|a| a.date.clone())
            .collect();
        dates.sort();
        dates.dedup();
        Self {
            version: SUMMARY_VERSION,
            item_count: run.appointments.len(),
            pending_count: run
                .appointments
                .iter()
                .filter(|a| a.included && !crate::review::approved(a))
                .count(),
            dates,
        }
    }

    pub fn from_json(raw: Option<&str>) -> Self {
        raw.and_then(|s| serde_json::from_str::<PipelineRun>(s).ok())
            .as_ref()
            .map(Self::from_run)
            .unwrap_or_default()
    }
}

pub(super) fn backfill(connection: &Connection) -> Result<()> {
    // Bound migration memory independently of the number of archived photos.
    loop {
        let rows = connection
            .prepare(
                "SELECT id,run FROM scans WHERE run_summary IS NULL AND run IS NOT NULL LIMIT 32",
            )?
            .query_map([], |row| {
                Ok((row.get::<_, String>(0)?, row.get::<_, String>(1)?))
            })?
            .collect::<std::result::Result<Vec<_>, _>>()?;
        if rows.is_empty() {
            break;
        }
        for (id, raw) in rows {
            let summary = ContentSummary::from_json(Some(&raw));
            connection.execute(
                "UPDATE scans SET run_summary=?2 WHERE id=?1",
                params![id, serde_json::to_string(&summary)?],
            )?;
        }
    }
    Ok(())
}
