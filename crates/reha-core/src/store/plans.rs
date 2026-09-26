use super::Store;
use crate::{Error, Result};
use rusqlite::params;
use serde::{Deserialize, Serialize};

#[derive(Clone, Serialize, Deserialize)]
pub struct Plan {
    pub id: String,
    pub imported_at: i64,
    pub page_ids: Vec<String>,
}
impl Store {
    pub fn plan_calendar(&self, id: &str) -> Result<(String, bool)> {
        let pages = self.page_ids(id)?;
        let scans = self.list_scans()?;
        let schedules: Vec<_> = scans
            .iter()
            .filter(|s| pages.contains(&s.id))
            .filter_map(|s| s.schedule_id.as_ref())
            .collect();
        let calendars: std::collections::BTreeSet<_> = self
            .records(None)?
            .into_iter()
            .filter(|r| schedules.contains(&&r.schedule_id))
            .map(|r| r.calendar_id)
            .collect();
        if calendars.len() > 1 {
            return Err(Error::Invalid(
                "Plan ist mehreren Kalendern zugeordnet. Importverlauf prüfen.".into(),
            ));
        }
        if let Some(calendar) = calendars.into_iter().next() {
            return Ok((calendar, true));
        }
        let key = format!("plan-calendar:{}", pages.first().unwrap_or(&id.to_string()));
        if let Some(calendar) = self.setting(&key)? {
            return Ok((calendar, false));
        }
        let preferences: serde_json::Value = self
            .setting("preferences")?
            .and_then(|s| serde_json::from_str(&s).ok())
            .unwrap_or_default();
        Ok((
            preferences["calendar_id"]
                .as_str()
                .unwrap_or_default()
                .into(),
            false,
        ))
    }
    pub fn select_plan_calendar(&self, id: &str, calendar: &str) -> Result<()> {
        if calendar.is_empty() {
            return Err(Error::Invalid("Kalender fehlt.".into()));
        }
        let (current, locked) = self.plan_calendar(id)?;
        if locked && current != calendar {
            return Err(Error::Invalid(
                "Dieser Plan bleibt im bisherigen Zielkalender.".into(),
            ));
        }
        if self.has_unresolved_calendar_writes()? {
            return Err(Error::Invalid(
                "Unklare Schreibvorgänge zuerst abgleichen.".into(),
            ));
        }
        let pages = self.page_ids(id)?;
        self.set_setting(
            &format!("plan-calendar:{}", pages.first().unwrap_or(&id.to_string())),
            calendar,
        )
    }
    /// Allocate PDF page identities once, before rasterization. Replaying a Files
    /// or share receipt returns the same ordered pages and cannot duplicate imports.
    pub fn pdf_pages(&mut self, source: &str, count: usize) -> Result<Vec<String>> {
        if !(1..=12).contains(&count) {
            return Err(Error::Invalid(
                "PDF braucht 1 bis 12 Seiten. Die Originaldatei bleibt gespeichert.".into(),
            ));
        }
        self.scan_dir(source)?;
        if self
            .intakes()?
            .iter()
            .any(|i| i.id == source && i.status == "deleted")
        {
            return Err(Error::Invalid(
                "Die Originaldatei wurde gelöscht und wird nicht erneut eingelesen.".into(),
            ));
        }
        let key = format!("document:{source}");
        if let Some(saved) = self.setting(&key)? {
            let ids: Vec<String> = serde_json::from_str(&saved)?;
            if ids.len() != count {
                return Err(Error::Invalid(
                    "Die gespeicherte PDF-Seitenzahl stimmt nicht überein.".into(),
                ));
            }
            return Ok(ids);
        }
        let bytes = std::fs::read(self.source_path(source)?)?;
        if !bytes.starts_with(b"%PDF-") {
            return Err(Error::Invalid("Keine lesbare PDF-Datei.".into()));
        }
        let ids: Vec<_> = (0..count)
            .map(|_| uuid::Uuid::new_v4().to_string())
            .collect();
        let tx = self.connection.transaction()?;
        tx.execute(
            "INSERT INTO settings(key,value) VALUES(?1,?2)",
            params![key, serde_json::to_string(&ids)?],
        )?;
        tx.execute("DELETE FROM plan_pages WHERE scan_id=?1", [source])?;
        for (index, id) in ids.iter().enumerate() {
            tx.execute(
                "INSERT INTO plan_pages VALUES(?1,?2,?3)",
                params![id, source, index],
            )?;
        }
        tx.execute("UPDATE intakes SET status='document' WHERE id=?1", [source])?;
        tx.commit()?;
        Ok(ids)
    }
    pub(super) fn ensure_page(&self, id: &str, now: i64) -> Result<()> {
        self.connection.execute(
            "INSERT OR IGNORE INTO plans VALUES(?1,?2)",
            params![id, now],
        )?;
        self.connection
            .execute("INSERT OR IGNORE INTO plan_pages VALUES(?1,?1,0)", [id])?;
        Ok(())
    }
    pub fn page_ids(&self, id: &str) -> Result<Vec<String>> {
        let mut q = self.connection.prepare("SELECT scan_id FROM plan_pages WHERE plan_id=COALESCE((SELECT plan_id FROM plan_pages WHERE scan_id=?1),?1) ORDER BY ordinal,scan_id")?;
        let ids = q
            .query_map([id], |r| r.get::<_, String>(0))?
            .collect::<std::result::Result<Vec<_>, _>>()?;
        Ok(if ids.is_empty() { vec![id.into()] } else { ids })
    }
    pub fn plans(&self) -> Result<Vec<Plan>> {
        let mut q = self.connection.prepare("SELECT id,imported_at FROM plans WHERE EXISTS(SELECT 1 FROM plan_pages WHERE plan_id=plans.id) ORDER BY imported_at DESC,id")?;
        let rows = q.query_map([], |r| Ok((r.get::<_, String>(0)?, r.get(1)?)))?;
        rows.map(|r| {
            let (id, imported_at) = r?;
            let page_ids = self.page_ids(&id)?;
            Ok(Plan {
                id,
                imported_at,
                page_ids,
            })
        })
        .collect()
    }
    pub fn group_pages(&mut self, parent: &str, ids: &[String]) -> Result<()> {
        let document = self.setting(&format!("document:{parent}"))?.is_some();
        if ids.is_empty() || ids.len() > 12 || (!document && ids[0] != parent) {
            return Err(Error::Invalid(
                "Ein Plan braucht 1 bis 12 geordnete Seiten; die erste Seite bleibt erhalten."
                    .into(),
            ));
        }
        let mut unique = std::collections::HashSet::new();
        for id in ids {
            self.scan_dir(id)?;
            if !unique.insert(id) {
                return Err(Error::Invalid("Seite doppelt zugeordnet.".into()));
            }
            let exists: bool = self.connection.query_row("SELECT EXISTS(SELECT 1 FROM scans WHERE id=?1 AND run IS NOT NULL UNION SELECT 1 FROM intakes WHERE id=?1 AND status!='deleted')", [id], |r| r.get(0))?;
            if !exists {
                return Err(Error::Invalid("Seite fehlt oder wurde gelöscht.".into()));
            }
            let old = self.page_ids(id)?;
            if old.len() > 1 && old != self.page_ids(parent)? {
                return Err(Error::Invalid(
                    "Seite gehört bereits zu einem anderen mehrseitigen Plan.".into(),
                ));
            }
        }
        let old = self.page_ids(parent)?;
        let tx = self.connection.transaction()?;
        for id in old.iter().filter(|id| !ids.contains(id)) {
            tx.execute(
                "INSERT OR IGNORE INTO plans VALUES(?1,?2)",
                params![id, chrono::Utc::now().timestamp()],
            )?;
            tx.execute(
                "UPDATE plan_pages SET plan_id=scan_id,ordinal=0 WHERE scan_id=?1",
                [id],
            )?;
        }
        for (index, id) in ids.iter().enumerate() {
            tx.execute(
                "UPDATE plan_pages SET plan_id=?2,ordinal=?3 WHERE scan_id=?1",
                params![id, parent, index],
            )?;
        }
        tx.execute("INSERT INTO settings(key,value) VALUES(?1,?2) ON CONFLICT(key) DO UPDATE SET value=excluded.value", params![format!("pages:{parent}"),serde_json::to_string(ids)?])?;
        tx.commit()?;
        Ok(())
    }
    pub fn begin_processing(&self, id: &str) -> Result<String> {
        let attempt = uuid::Uuid::new_v4().to_string();
        self.connection.execute(
            "INSERT INTO processing_attempts VALUES(?1,?2,?3,'processing',NULL)",
            params![attempt, id, chrono::Utc::now().timestamp()],
        )?;
        self.intake_status(id, "processing", None)?;
        Ok(attempt)
    }
    pub fn finish_processing(
        &self,
        attempt: &str,
        status: &str,
        error: Option<&str>,
    ) -> Result<()> {
        self.connection.execute(
            "UPDATE processing_attempts SET status=?2,error=?3 WHERE id=?1",
            params![attempt, status, error],
        )?;
        Ok(())
    }
}
