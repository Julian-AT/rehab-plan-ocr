use super::{domain_failure, failure, AppState, DomainFailure, Platform, Proposal, Response};
use crate::{contracts::*, store::ImportBatch};
use std::{collections::BTreeMap, sync::Arc};

fn evidence(
    state: &AppState,
    id: &str,
) -> Response<(ImportBatch, Vec<ImportRecord>, String, Option<ImportBatch>)> {
    let store = state.store.lock().map_err(failure)?;
    if store.has_unresolved_calendar_writes().map_err(failure)? {
        return Err(DomainFailure::UncertainWrite
            .with_message("Unklare Schreibvorgänge zuerst abgleichen."));
    }
    let batch = store
        .batches()
        .map_err(failure)?
        .into_iter()
        .find(|b| b.id == id)
        .ok_or("Importverlauf fehlt. Historische Zuordnungen werden nicht geraten.")?;
    if batch.undo_of.is_some() {
        return Err("Die Rücknahme selbst kann nicht nochmals rückgängig gemacht werden.".into());
    }
    let resume = batch
        .undone_by
        .as_ref()
        .and_then(|id| store.batches().ok()?.into_iter().find(|b| &b.id == id));
    if batch.undone_by.is_some()
        && !resume.as_ref().is_some_and(|b| {
            b.operations
                .iter()
                .any(|e| ["failed", "conflict"].contains(&e.status.as_str()))
        })
    {
        return Err("Die Rücknahme enthält keine weiteren ausführbaren Änderungen.".into());
    }
    let records = store.resolved_import_records(None).map_err(failure)?;
    let revision = crate::hash(&serde_json::to_vec(&(&batch, &records, &resume)).map_err(failure)?);
    Ok((batch, records, revision, resume))
}

pub async fn prepare(
    app: Arc<dyn Platform>,
    state: &Arc<AppState>,
    id: String,
) -> Response<Proposal> {
    let (batch, records, revision, resume) = evidence(state, &id)?;
    let mut query = vec![];
    for entry in batch.operations.iter().filter(|e| e.status == "saved") {
        let op = &entry.operation;
        if let Some(record) = records.iter().find(|r| r.id == op.id) {
            query.push(record.clone());
        } else if let Some(values) = op.before.as_ref().or(op.after.as_ref()) {
            query.push(ImportRecord {
                id: op.id.clone(),
                schedule_id: batch.schedule_id.clone(),
                calendar_id: op.calendar_id.clone(),
                external_id: entry
                    .result
                    .as_ref()
                    .and_then(|r| r.external_id.clone())
                    .or(op.external_id.clone()),
                approved: values.clone(),
                status: "saved".into(),
                operation_id: entry.attempt_id.clone(),
            });
        }
    }
    let live = tokio::task::spawn_blocking(move || app.import_snapshot(query))
        .await
        .map_err(failure)??;
    let current = live.current;
    let protected = live.protected_ids;
    let mut operations = vec![];
    for entry in batch
        .operations
        .iter()
        .rev()
        .filter(|e| e.status == "saved")
    {
        if resume.as_ref().is_some_and(|b| {
            !b.operations.iter().any(|e| {
                e.operation.id == entry.operation.id
                    && ["failed", "conflict"].contains(&e.status.as_str())
            })
        }) {
            continue;
        }
        let original = &entry.operation;
        let record = records.iter().find(|r| r.id == original.id);
        let live = current.get(&original.id);
        let still_owned = match original.kind.as_str() {
            "create" | "update" => {
                record.is_some_and(|r| r.operation_id == entry.attempt_id)
                    && live == original.after.as_ref()
            }
            "remove" => record.is_none() && live.is_none(),
            _ => false,
        } && !protected.contains(&original.id);
        let mut op = CalendarOperation {
            kind: match original.kind.as_str() {
                "create" => "remove",
                "update" => "update",
                "remove" => "create",
                _ => "keep",
            }
            .into(),
            id: original.id.clone(),
            calendar_id: record
                .map(|r| r.calendar_id.clone())
                .unwrap_or_else(|| original.calendar_id.clone()),
            external_id: record.and_then(|r| r.external_id.clone()),
            before: live.cloned(),
            after: original.before.clone(),
            requires_resolution: !still_owned,
            reason: "Änderung dieses Imports rückgängig machen.".into(),
        };
        if !still_owned {
            op.kind = "conflict".into();
            op.reason = "Inzwischen verändert, erneut importiert oder nicht mehr sicher zugeordnet. Aktuellen Kalenderstand behalten.".into();
        }
        operations.push(op);
    }
    if operations.is_empty() {
        return Err("Dieser Import enthält keine nachweislich gespeicherten Änderungen.".into());
    }
    let proposal = Proposal {
        draft: None,
        token: uuid::Uuid::new_v4().to_string(),
        document_id: batch.document_ids.first().cloned().unwrap_or_default(),
        document_ids: batch.document_ids,
        run_hash: revision,
        schedule_id: batch.schedule_id,
        fingerprint: String::new(),
        operations,
        protected_event_ids: protected,
        bindings: BTreeMap::new(),
        undo_of: Some(id),
        resume_batch: resume.map(|b| b.id),
        overlaps: None,
        comparison_events: BTreeMap::new(),
        overlap_exclusions: vec![],
    };
    state
        .proposals
        .lock()
        .map_err(failure)?
        .insert(proposal.token.clone(), proposal.clone());
    Ok(proposal)
}

/// Caller holds the shared calendar lock. Platform revalidates ownership and the
/// exact before snapshot again for each write, including alarm/recurrence guards.
pub(super) async fn approve_locked(
    app: Arc<dyn Platform>,
    state: &Arc<AppState>,
    proposal: Proposal,
    approve_removals: bool,
) -> Response<Vec<CalendarResult>> {
    let undo_of = proposal.undo_of.as_deref().ok_or("Import fehlt.")?;
    if proposal.operations.iter().any(|o| o.requires_resolution) {
        return Err("Unklare Zuordnungen zuerst auflösen.".into());
    }
    if proposal.operations.iter().any(|o| o.kind == "remove") && !approve_removals {
        return Err("Löschungen separat bestätigen.".into());
    }
    if evidence(state, undo_of)?.2 != proposal.run_hash {
        return Err(DomainFailure::StaleProposal
            .with_message("Prüfdaten wurden geändert. Kalender-Vorschau neu erstellen."));
    }
    // Re-run comparison before storing intent; even resolved 'keep' choices must
    // not conceal newly changed events among the operations being reversed.
    let fresh = prepare(app.clone(), state, undo_of.to_owned()).await?;
    state
        .proposals
        .lock()
        .map_err(failure)?
        .remove(&fresh.token);
    for op in proposal.operations.iter().filter(|o| o.kind != "keep") {
        let Some(now) = fresh.operations.iter().find(|o| o.id == op.id) else {
            return Err(DomainFailure::StaleProposal.with_message("Vorschau abgelaufen."));
        };
        if now.requires_resolution
            || serde_json::to_value(now).map_err(failure)?
                != serde_json::to_value(op).map_err(failure)?
        {
            return Err(
                "Kalender wurde seit der Vorschau verändert. Vorschau erneut erstellen.".into(),
            );
        }
    }
    let batch = {
        let mut store = state.store.lock().map_err(failure)?;
        if let Some(resume) = &proposal.resume_batch {
            store
                .retry_failed_batch(resume, &proposal.operations)
                .map_err(domain_failure)?
        } else {
            store
                .begin_batch(
                    &proposal.document_ids,
                    &proposal.schedule_id,
                    &proposal.operations,
                    Some(undo_of),
                )
                .map_err(domain_failure)?
        }
    };
    let mut results = vec![];
    for entry in batch.operations {
        let op = entry.operation;
        let platform = app.clone();
        let recovery_only = state
            .store
            .lock()
            .map_err(failure)?
            .start_operation(&entry.attempt_id)
            .map_err(failure)?;
        let request = super::calendar_imports::ApplyRequest {
            operation: op.clone(),
            recovery_only,
        };
        let response = tokio::task::spawn_blocking(move || platform.apply_import(request))
            .await
            .map_err(failure)?;
        let outcome = response
            .ok()
            .filter(|r| r.id == op.id)
            .unwrap_or(CalendarResult {
                maintenance_warnings: vec![],
                id: op.id,
                status: "uncertain".into(),
                external_id: None,
                error: Some("Schreibstatus unklar. Vor erneutem Schreiben abgleichen.".into()),
            });
        state
            .store
            .lock()
            .map_err(failure)?
            .finish_operation(&entry.attempt_id, &outcome)
            .map_err(failure)?;
        results.push(outcome);
    }
    super::calendar::finish_bookkeeping(state, &mut results)?;
    state
        .proposals
        .lock()
        .map_err(failure)?
        .remove(&proposal.token);
    for warning in super::agenda::sync_warnings(&app, state).await {
        for result in &mut results {
            result.maintenance_warnings.push(warning.to_string());
        }
    }
    Ok(results)
}
