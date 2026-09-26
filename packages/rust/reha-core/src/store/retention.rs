//! Completed documents expire as connected aggregates, never individual PDF pages.
//! A durable deletion intent precedes filesystem effects and is replayed on open.
use super::Store;
use crate::Result;
use std::collections::BTreeSet;

impl Store {
    pub fn delete_sources(&self, ids: &[String]) -> Result<()> {
        for id in ids {
            self.scan_dir(id)?;
        }
        let tx = self.connection.unchecked_transaction()?;
        for id in ids {
            tx.execute("INSERT OR IGNORE INTO source_deletions VALUES(?1)", [id])?;
        }
        tx.commit()?;
        self.recover_source_deletions()
    }

    pub(super) fn recover_source_deletions(&self) -> Result<()> {
        let ids = self
            .connection
            .prepare("SELECT id FROM source_deletions ORDER BY id")?
            .query_map([], |r| r.get::<_, String>(0))?
            .collect::<std::result::Result<Vec<_>, _>>()?;
        for id in &ids {
            let dir = self.scan_dir(id)?;
            if dir.exists() {
                std::fs::remove_dir_all(dir)?;
            }
        }
        let tx = self.connection.unchecked_transaction()?;
        for id in &ids {
            tx.execute("UPDATE scans SET run=NULL WHERE id=?1", [id])?;
            tx.execute(
                "UPDATE intakes SET status='deleted',error=NULL WHERE id=?1",
                [id],
            )?;
            tx.execute(
                "DELETE FROM settings WHERE key=?1",
                [format!("pdf-evidence:{id}")],
            )?;
            tx.execute("DELETE FROM failures WHERE id=?1", [id])?;
            tx.execute("DELETE FROM processing_attempts WHERE scan_id=?1", [id])?;
            tx.execute("DELETE FROM source_deletions WHERE id=?1", [id])?;
        }
        tx.commit()?;
        Ok(())
    }

    pub fn cleanup(&self, now: i64) -> Result<usize> {
        self.recover_source_deletions()?;
        let preferences: serde_json::Value = self
            .setting("preferences")?
            .and_then(|s| serde_json::from_str(&s).ok())
            .unwrap_or_default();
        let Some(days) = preferences["retention_days"]
            .as_u64()
            .filter(|d| (1..=3650).contains(d))
        else {
            return Ok(0);
        };
        if self.has_unresolved_calendar_writes()? {
            return Ok(0);
        }
        let cutoff = now.saturating_sub(days as i64 * 86400);
        let pages = self.connection.prepare("SELECT id FROM scans WHERE imported_at<=?1 AND run IS NOT NULL
            AND json_valid(run) AND json_extract(run,'$.review_confirmed')=1
            AND NOT EXISTS(SELECT 1 FROM intakes WHERE intakes.id=scans.id AND status!='completed')
            AND NOT EXISTS(SELECT 1 FROM failures WHERE failures.id=scans.id)
            AND NOT EXISTS(SELECT 1 FROM processing_attempts WHERE scan_id=scans.id AND status='processing')")?
            .query_map([cutoff], |r| r.get::<_, String>(0))?
            .collect::<std::result::Result<BTreeSet<_>, _>>()?;
        let mut eligible = pages.clone();
        let mut live_documents = BTreeSet::new();
        let intakes = self.intakes()?;
        eligible.extend(
            intakes
                .iter()
                .filter(|i| i.status == "deleted")
                .map(|i| i.id.clone()),
        );
        let mut groups: Vec<BTreeSet<String>> = self
            .plans()?
            .into_iter()
            .map(|p| p.page_ids.into_iter().collect())
            .collect();
        let documents = self
            .connection
            .prepare("SELECT substr(key,10),value FROM settings WHERE key LIKE 'document:%'")?
            .query_map([], |r| Ok((r.get::<_, String>(0)?, r.get::<_, String>(1)?)))?
            .collect::<std::result::Result<Vec<_>, _>>()?;
        for (source, raw) in documents {
            let mut group: BTreeSet<String> = serde_json::from_str(&raw)?;
            group.insert(source.clone());
            groups.push(group);
            if intakes
                .iter()
                .any(|i| i.id == source && i.status == "document" && i.imported_at <= cutoff)
                && !self.connection.query_row(
                    "SELECT EXISTS(SELECT 1 FROM failures WHERE id=?1) OR EXISTS(SELECT 1 FROM processing_attempts WHERE scan_id=?1 AND status='processing')",
                    [&source],
                    |r| r.get::<_, bool>(0),
                )?
            {
                live_documents.insert(source.clone());
                eligible.insert(source);
            }
        }
        // Exact duplicate captures have their own durable original but reuse a
        // prior scan instead of creating another run. Connect every matching
        // scan, including legacy duplicates, to its plan/PDF aggregate. A fresh
        // capture or unfinished related page therefore protects the whole group.
        let duplicates = self.connection.prepare(
            "SELECT i.id,s.id,
                i.imported_at<=?1
                AND NOT EXISTS(SELECT 1 FROM failures WHERE id=i.id)
                AND NOT EXISTS(SELECT 1 FROM processing_attempts WHERE scan_id=i.id AND status='processing'),
                s.run IS NULL
                AND NOT EXISTS(SELECT 1 FROM intakes WHERE id=s.id AND status!='deleted')
                AND NOT EXISTS(SELECT 1 FROM failures WHERE id=s.id)
                AND NOT EXISTS(SELECT 1 FROM processing_attempts WHERE scan_id=s.id AND status='processing')
             FROM intakes i JOIN scans s ON s.source_hash=i.source_hash AND s.id!=i.id
             WHERE i.status='duplicate'",
        )?.query_map([cutoff], |r| Ok((r.get::<_, String>(0)?, r.get::<_, String>(1)?, r.get::<_, bool>(2)?, r.get::<_, bool>(3)?)))?
            .collect::<std::result::Result<Vec<_>, _>>()?;
        let mut live_duplicates = BTreeSet::new();
        for (duplicate, source, expired, source_deleted) in duplicates {
            groups.push(BTreeSet::from([duplicate.clone(), source.clone()]));
            if expired {
                eligible.insert(duplicate.clone());
                live_duplicates.insert(duplicate);
            }
            // A legacy scan may have been explicitly removed before intakes
            // existed. Its tombstone must not retain a duplicate forever.
            if source_deleted {
                eligible.insert(source);
            }
        }
        // Include old scans that predate archive indexing, then merge transitive
        // plan/PDF relationships before considering any source for deletion.
        groups.extend(pages.iter().map(|id| BTreeSet::from([id.clone()])));
        let mut merged: Vec<BTreeSet<String>> = Vec::new();
        for mut group in groups {
            let mut index = 0;
            while index < merged.len() {
                if !group.is_disjoint(&merged[index]) {
                    group.extend(merged.remove(index));
                    index = 0;
                } else {
                    index += 1;
                }
            }
            merged.push(group);
        }
        let mut count = 0;
        for group in merged {
            let live_count = group.intersection(&pages).count();
            if (live_count > 0
                || !group.is_disjoint(&live_documents)
                || !group.is_disjoint(&live_duplicates))
                && group.is_subset(&eligible)
            {
                self.delete_sources(&group.into_iter().collect::<Vec<_>>())?;
                count += live_count;
            }
        }
        Ok(count)
    }
}
