//! Replayable local marking after a durable calendar operation. This journal is
//! written before effects and never issues calendar commands when replayed.
use crate::{
    contracts::CalendarOperation,
    review::values_hash,
    store::{ImportBatch, Store},
    Result,
};
use serde::{Deserialize, Serialize};
use std::collections::{BTreeMap, BTreeSet};

const PREFIX: &str = "calendar_bookkeeping:";
pub const WARNING: &str =
    "Der lokale Planstand braucht noch einen Abgleich. Bestätigte Kalenderänderungen bleiben erhalten.";

#[derive(Serialize, Deserialize)]
struct Entry {
    document: String,
    appointment: String,
    event: String,
    values_hash: String,
    unchanged: bool,
}
#[derive(Serialize, Deserialize)]
struct Journal {
    version: u32,
    batch: String,
    clear: bool,
    entries: Vec<Entry>,
}

/// Capture current row identity before any platform effect. Missing/expired pages
/// need no marking; malformed retained pages must not silently lose protection.
pub fn prepare(
    store: &Store,
    batch: &ImportBatch,
    operations: &[CalendarOperation],
    clear: bool,
) -> Result<()> {
    let mut entries = vec![];
    for document in &batch.document_ids {
        if !exists(store, document)? {
            continue;
        }
        let run = store.load_run(document)?;
        for a in run.appointments {
            let event = a.calendar_event_id.as_ref().unwrap_or(&a.id);
            if let Some(op) = operations.iter().find(|op| &op.id == event) {
                entries.push(Entry {
                    document: document.clone(),
                    appointment: a.id.clone(),
                    event: event.clone(),
                    values_hash: values_hash(&a),
                    unchanged: op.kind == "unchanged",
                });
            }
        }
    }
    if !entries.is_empty() {
        store.set_setting(
            &format!("{PREFIX}{}:{}", batch.id, uuid::Uuid::new_v4()),
            &serde_json::to_string(&Journal {
                version: 1,
                batch: batch.id.clone(),
                clear,
                entries,
            })?,
        )?;
    }
    Ok(())
}

fn exists(store: &Store, document: &str) -> Result<bool> {
    Ok(store.connection.query_row(
        "SELECT EXISTS(SELECT 1 FROM scans WHERE id=?1 AND run IS NOT NULL)",
        [document],
        |row| row.get(0),
    )?)
}

pub fn pending_count(store: &Store) -> Result<u32> {
    Ok(store.connection.query_row(
        "SELECT count(*) FROM settings WHERE key GLOB 'calendar_bookkeeping:*'",
        [],
        |row| row.get(0),
    )?)
}

/// Apply an entire journal atomically, then retire it only after every operation
/// is terminal. A failed save rolls back markings and retains the replay intent.
pub fn recover(store: &Store) -> Result<()> {
    let mut query = store.connection.prepare(
        "SELECT key,value FROM settings WHERE key GLOB 'calendar_bookkeeping:*' ORDER BY rowid",
    )?;
    let journals = query
        .query_map([], |row| {
            Ok((row.get::<_, String>(0)?, row.get::<_, String>(1)?))
        })?
        .collect::<std::result::Result<Vec<_>, _>>()?;
    drop(query);
    for (key, raw) in journals {
        let journal: Journal = serde_json::from_str(&raw)?;
        if journal.version != 1 || !key.starts_with(&format!("{PREFIX}{}:", journal.batch)) {
            return Err(crate::Error::Invalid(
                "Unbekannte lokale Kalender-Nachbearbeitung.".into(),
            ));
        }
        let batch = store.batch(&journal.batch)?.ok_or_else(|| {
            crate::Error::Invalid("Kalenderjournal für lokale Nachbearbeitung fehlt.".into())
        })?;
        let saved: BTreeSet<_> = batch
            .operations
            .iter()
            .filter(|op| op.status == "saved")
            .map(|op| op.operation.id.as_str())
            .collect();
        let terminal = batch.operations.iter().all(|op| {
            matches!(
                op.status.as_str(),
                "saved" | "failed" | "conflict" | "acknowledged" | "skipped"
            )
        });
        let mut documents: BTreeMap<&str, Vec<&Entry>> = BTreeMap::new();
        for entry in &journal.entries {
            if entry.unchanged || saved.contains(entry.event.as_str()) {
                documents.entry(&entry.document).or_default().push(entry);
            }
        }
        let tx = store.connection.unchecked_transaction()?;
        for (document, entries) in documents {
            if !exists(store, document)? {
                continue;
            }
            let mut run = store.load_run(document)?;
            let mut changed = false;
            for entry in entries {
                if let Some(a) = run
                    .appointments
                    .iter_mut()
                    .find(|a| a.id == entry.appointment)
                {
                    if a.calendar_event_id.as_ref().unwrap_or(&a.id) != &entry.event
                        || values_hash(a) != entry.values_hash
                    {
                        continue;
                    }
                    let mark = if journal.clear {
                        None
                    } else {
                        Some(entry.values_hash.clone())
                    };
                    if a.calendar_saved_hash != mark {
                        a.calendar_saved_hash = mark;
                        changed = true;
                    }
                }
            }
            if changed {
                store.save_run(&run)?;
            }
        }
        if terminal {
            tx.execute("DELETE FROM settings WHERE key=?1", [&key])?;
        }
        tx.commit()?;
    }
    Ok(())
}
