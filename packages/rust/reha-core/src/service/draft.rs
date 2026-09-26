//! Read-only preparation followed by one durable plan acceptance.
use super::{calendar, failure, AppState, Platform, Proposal, Response};
use crate::{
    contracts::*,
    readiness::{self, DraftAssessment, PlanAcceptance, Readiness},
    review,
    store::Store,
};
use serde::{Deserialize, Serialize};
use std::{
    collections::{BTreeMap, HashSet},
    sync::Arc,
};

#[derive(Clone, Serialize)]
pub struct DraftIntent {
    pub timezone: String,
    pub reminder: Option<u32>,
    pub selection: Vec<String>,
    pub current: BTreeMap<String, EventValues>,
    pub records: Vec<ImportRecord>,
    pub policy_version: u32,
}
#[derive(Clone, Serialize)]
pub struct DraftPreview {
    pub assessment: DraftAssessment,
    pub proposal: Option<Proposal>,
}
#[derive(Clone, Serialize, Deserialize)]
pub struct SaveOutcome {
    pub batch_id: String,
    pub results: Vec<CalendarResult>,
    pub existing_ids: Vec<String>,
    pub remaining_ids: Vec<String>,
}
pub(super) fn available_runs(store: &Store, id: &str) -> Response<(Vec<PipelineRun>, Vec<String>)> {
    let mut runs = vec![];
    let mut missing = vec![];
    for page in store.page_ids(id).map_err(failure)? {
        // Null/missing runs are retained intake pages, not permission to replace a plan.
        let retained: Option<String> = store
            .connection
            .query_row("SELECT run FROM scans WHERE id=?1", [&page], |r| r.get(0))
            .optional()
            .map_err(failure)?
            .flatten();
        if retained.is_some() {
            runs.push(store.load_run(&page).map_err(failure)?);
        } else {
            missing.push(page);
        }
    }
    Ok((runs, missing))
}
use rusqlite::OptionalExtension;
pub fn assess(state: &Arc<AppState>, id: String, timezone: String) -> Response<DraftAssessment> {
    let store = state.store.lock().map_err(failure)?;
    let (runs, missing) = available_runs(&store, &id)?;
    let mut assessment = readiness::assess(&runs, &timezone);
    assessment.unprocessed_page_ids = missing;
    Ok(assessment)
}
pub(super) fn events(
    runs: &[PipelineRun],
    selection: &[String],
    timezone: &str,
    reminder: Option<u32>,
) -> Response<Vec<(String, EventValues)>> {
    if selection.is_empty() || selection.iter().collect::<HashSet<_>>().len() != selection.len() {
        return Err("Keine eindeutige Auswahl.".into());
    }
    selection
        .iter()
        .map(|id| {
            let (run, a) = runs
                .iter()
                .find_map(|r| r.appointments.iter().find(|a| &a.id == id).map(|a| (r, a)))
                .ok_or("Termin fehlt.")?;
            if readiness::appointment(a, &run.document.id, timezone).state != Readiness::Ready {
                return Err("Offene Angaben zuerst klären.".into());
            }
            Ok((
                a.calendar_event_id.clone().unwrap_or_else(|| a.id.clone()),
                crate::calendar::validated_values(a, timezone, reminder).map_err(failure)?,
            ))
        })
        .collect()
}
pub async fn preview(
    app: Arc<dyn Platform>,
    state: &Arc<AppState>,
    id: String,
    calendar_id: String,
    timezone: String,
    reminder: Option<u32>,
) -> Response<DraftPreview> {
    let assessment = assess(state, id.clone(), timezone.clone())?;
    let proposal = if assessment.ready_ids.is_empty() {
        None
    } else {
        let proposal = calendar::prepare_impl(
            app,
            state,
            id,
            calendar_id,
            None,
            timezone,
            reminder,
            Some(assessment.ready_ids.clone()),
            Some(false),
            true,
        )
        .await?;
        if proposal.run_hash != assessment.revision {
            return Err("Prüfdaten wurden geändert. Erneut laden.".into());
        }
        Some(proposal)
    };
    Ok(DraftPreview {
        assessment,
        proposal,
    })
}
/// Targeted exception decision. A shared date answer applies only to the server's
/// evidence-based question membership and to the exact displayed revision.
pub fn answer(
    state: &Arc<AppState>,
    id: String,
    revision: String,
    question_id: String,
    value: Option<serde_json::Value>,
    timezone: String,
) -> Response<()> {
    let mut store = state.store.lock().map_err(failure)?;
    let (mut runs, _) = available_runs(&store, &id)?;
    if !store.pending().map_err(failure)?.is_empty() {
        return Err("Unklare Schreibvorgänge zuerst abgleichen.".into());
    }
    if state
        .cancel
        .lock()
        .map_err(failure)?
        .keys()
        .any(|id| runs.iter().any(|r| &r.document.id == id))
    {
        return Err("Erkennung zuerst abschließen oder abbrechen.".into());
    }
    let assessment = readiness::assess(&runs, &timezone);
    if assessment.revision != revision {
        return Err("stale_revision".into());
    }
    let q = assessment
        .questions
        .iter()
        .find(|q| q.id == question_id)
        .ok_or("Frage nicht mehr offen.")?;
    for run in &mut runs {
        for a in &mut run.appointments {
            if !q.appointment_ids.contains(&a.id) {
                continue;
            }
            if let Some(code) = q.field.strip_prefix("issue:") {
                let issue = a
                    .issues
                    .iter()
                    .find(|i| i.code == code && i.blocking && i.field.is_none())
                    .ok_or("Hinweis nicht mehr vorhanden.")?;
                let hash = readiness::issue_decision_hash(a, issue);
                let decision = a.fields.entry(q.field.clone()).or_default();
                // This is a row-level decision; no printed field state is changed.
                decision.confirmed_at = Some(chrono::Utc::now().timestamp());
                decision.confirmed_value = Some(hash);
            } else if q.field == "cancellation" {
                let hash = serde_json::json!(review::values_hash(a));
                let f = a.fields.entry("cancellation".into()).or_default();
                f.state = PrintedState::Legible;
                f.confirmed_at = Some(chrono::Utc::now().timestamp());
                f.confirmed_value = Some(hash);
            } else {
                let mut edited = a.clone();
                if let Some(v) = &value {
                    review::set_value(&mut edited, &q.field, v.clone()).map_err(failure)?;
                }
                let v = review::value(&edited, &q.field);
                if review::empty(&v) {
                    return Err("Die benötigte Angabe fehlt noch.".into());
                }
                if value.is_none() {
                    let f = edited.fields.entry(q.field.clone()).or_default();
                    f.state = PrintedState::Legible;
                    f.confirmed_value = Some(v);
                    f.confirmed_at = Some(chrono::Utc::now().timestamp());
                }
                // A manual correction changes the origin, not the retained photo evidence.
                if crate::parser::validate(&edited)
                    .iter()
                    .any(|i| i.field.as_deref() == Some(&q.field))
                {
                    return Err("Die Angabe ist noch nicht gültig.".into());
                }
                *a = review::edit(Some(a), edited).map_err(failure)?;
            }
        }
    }
    let tx = store.connection.transaction().map_err(failure)?;
    for run in &runs {
        tx.execute(
            "UPDATE scans SET run=?2 WHERE id=?1",
            rusqlite::params![
                run.document.id,
                serde_json::to_string(run).map_err(failure)?
            ],
        )
        .map_err(failure)?;
    }
    tx.commit().map_err(failure)?;
    state.proposals.lock().map_err(failure)?.retain(|_, p| {
        !p.document_ids
            .iter()
            .any(|id| runs.iter().any(|r| &r.document.id == id))
    });
    Ok(())
}
pub async fn accept_and_save(
    app: Arc<dyn Platform>,
    state: &Arc<AppState>,
    token: String,
    selection: Vec<String>,
    approve_removals: bool,
) -> Response<SaveOutcome> {
    let _guard = state.calendar_lock.lock().await;
    let mut proposal = state
        .proposals
        .lock()
        .map_err(failure)?
        .get(&token)
        .cloned()
        .ok_or("Vorschau abgelaufen.")?;
    let intent = proposal.draft.clone().ok_or("Keine Planvorschau.")?;
    if intent.policy_version != readiness::POLICY_VERSION {
        return Err("Prüfregeln geändert. Vorschau erneuern.".into());
    }
    if selection.is_empty()
        || selection.iter().collect::<HashSet<_>>().len() != selection.len()
        || selection.iter().any(|id| !intent.selection.contains(id))
    {
        return Err("Ungültige Auswahl.".into());
    }
    if proposal.operations.iter().any(|op| op.kind == "remove")
        && selection.len() != intent.selection.len()
    {
        return Err("Teilweise Auswahl darf keine fehlenden Termine entfernen.".into());
    }
    let ids: HashSet<_> = selection
        .iter()
        .filter_map(|id| proposal.bindings.get(id))
        .cloned()
        .collect();
    proposal
        .operations
        .retain(|op| ids.contains(&op.id) || op.kind == "remove");
    proposal.bindings.retain(|id, _| selection.contains(id));
    if proposal.operations.iter().any(|op| op.requires_resolution) {
        return Err("Kalenderkonflikt zuerst klären oder Termin für später lassen.".into());
    }
    if proposal.operations.iter().any(|op| op.kind == "remove") && !approve_removals {
        return Err("Löschungen separat bestätigen.".into());
    }
    // Check even unchanged entries: they do not pass through the platform write callback.
    let platform = app.clone();
    let records = state
        .store
        .lock()
        .map_err(failure)?
        .resolved_import_records(Some(&proposal.schedule_id))
        .map_err(failure)?;
    if serde_json::to_value(&records).map_err(failure)?
        != serde_json::to_value(&intent.records).map_err(failure)?
    {
        return Err("Terminzuordnung wurde geändert. Vergleich erneut laden.".into());
    }
    let live = tokio::task::spawn_blocking(move || platform.import_snapshot(records))
        .await
        .map_err(failure)??;
    let current = live.current;
    let protected = live.protected_ids;
    if current != intent.current || protected != proposal.protected_event_ids {
        return Err("Kalender wurde geändert. Vergleich erneut laden.".into());
    }
    if proposal.overlaps.is_some() {
        let platform = app.clone();
        let events = proposal.comparison_events.clone();
        let excluded = proposal.overlap_exclusions.clone();
        if tokio::task::spawn_blocking(move || platform.overlaps(events, excluded))
            .await
            .map_err(failure)??
            != proposal.overlaps
        {
            return Err("Kalenderüberschneidungen geändert. Vergleich erneut laden.".into());
        }
    }
    let (batch, remaining_ids) = {
        let mut store = state.store.lock().map_err(failure)?;
        if store
            .event_history()
            .map_err(failure)?
            .iter()
            .any(|h| matches!(h["status"].as_str(), Some("pending" | "uncertain")))
        {
            return Err("Unklare Schreibvorgänge zuerst abgleichen.".into());
        }
        let (runs, missing) = available_runs(&store, &proposal.document_id)?;
        let assessment = readiness::assess(&runs, &intent.timezone);
        if assessment.revision != proposal.run_hash {
            return Err("Prüfdaten wurden geändert. Vergleich erneut laden.".into());
        }
        if !missing.is_empty() && proposal.operations.iter().any(|op| op.kind == "remove") {
            return Err("Unvollständiger Plan darf keine Termine ersetzen.".into());
        }
        if state
            .cancel
            .lock()
            .map_err(failure)?
            .keys()
            .any(|id| runs.iter().any(|r| &r.document.id == id))
        {
            return Err("Erkennung zuerst abschließen oder abbrechen.".into());
        }
        let accepted_events = events(&runs, &selection, &intent.timezone, intent.reminder)?;
        proposal.fingerprint = crate::calendar::schedule_fingerprint(
            &accepted_events
                .into_iter()
                .map(|(_, v)| v)
                .collect::<Vec<_>>(),
        );
        let accepted = PlanAcceptance {
            policy_version: readiness::POLICY_VERSION,
            accepted_at: chrono::Utc::now().timestamp(),
            proposal_revision: proposal.run_hash.clone(),
            value_hashes: runs
                .iter()
                .flat_map(|r| &r.appointments)
                .filter(|a| selection.contains(&a.id))
                .map(|a| (a.id.clone(), review::values_hash(a)))
                .collect(),
        };
        let remaining = assessment
            .appointments
            .iter()
            .filter(|a| a.state != Readiness::Excluded && !selection.contains(&a.id))
            .map(|a| a.id.clone())
            .collect();
        (
            store
                .begin_accepted_batch(&proposal, &runs, &accepted)
                .map_err(failure)?,
            remaining,
        )
    };
    let batch_id = batch.id.clone();
    let existing_ids = proposal
        .operations
        .iter()
        .filter(|o| o.kind == "unchanged" || (o.kind == "keep" && o.before.is_some()))
        .map(|o| o.id.clone())
        .collect();
    let results = calendar::execute_batch(app, state, proposal, batch).await?;
    Ok(SaveOutcome {
        batch_id,
        results,
        existing_ids,
        remaining_ids,
    })
}

/// Advanced replacement still requires explicit complete-page and removal approval.
pub async fn preview_replacement(
    app: Arc<dyn Platform>,
    state: &Arc<AppState>,
    id: String,
    calendar_id: String,
    timezone: String,
    reminder: Option<u32>,
) -> Response<DraftPreview> {
    let assessment = assess(state, id.clone(), timezone.clone())?;
    {
        let store = state.store.lock().map_err(failure)?;
        let (runs, missing) = available_runs(&store, &id)?;
        if !missing.is_empty()
            || runs.is_empty()
            || runs.iter().any(|r| !r.complete_page_confirmed)
            || assessment
                .appointments
                .iter()
                .any(|a| a.state == Readiness::Attention)
        {
            return Err(
                "Ersetzen braucht alle erkannten Seiten und geklärte Pflichtangaben.".into(),
            );
        }
    }
    let proposal = calendar::prepare_impl(
        app,
        state,
        id,
        calendar_id,
        None,
        timezone,
        reminder,
        Some(assessment.ready_ids.clone()),
        Some(true),
        true,
    )
    .await?;
    if proposal.run_hash != assessment.revision {
        return Err("Prüfdaten geändert. Erneut laden.".into());
    }
    Ok(DraftPreview {
        assessment,
        proposal: Some(proposal),
    })
}

/// Export acceptance uses the same readiness/value policy and historical ICS
/// identities. It cannot mark a field as verified or an event as calendar-saved.
pub fn export_ics(
    state: &Arc<AppState>,
    id: String,
    revision: String,
    timezone: String,
    reminder: Option<u32>,
    selection: Vec<String>,
) -> Response<String> {
    let mut store = state.store.lock().map_err(failure)?;
    let (mut runs, _) = available_runs(&store, &id)?;
    if readiness::assess(&runs, &timezone).revision != revision {
        return Err("stale_revision".into());
    }
    if state
        .cancel
        .lock()
        .map_err(failure)?
        .keys()
        .any(|id| runs.iter().any(|r| &r.document.id == id))
    {
        return Err("Erkennung zuerst abschließen.".into());
    }
    let events = events(&runs, &selection, &timezone, reminder)?;
    let fingerprint = crate::calendar::schedule_fingerprint(
        &events.iter().map(|(_, v)| v.clone()).collect::<Vec<_>>(),
    );
    let key = format!("export:{fingerprint}");
    let previous = store
        .setting(&key)
        .map_err(failure)?
        .map(|v| serde_json::from_str::<Vec<String>>(&v))
        .transpose()
        .map_err(failure)?;
    let events = crate::calendar::ics_identities(&runs, &selection, events, previous.as_deref());
    let text = crate::calendar::ics(&events, chrono::Utc::now()).map_err(failure)?;
    let identities: BTreeMap<_, _> = selection
        .iter()
        .zip(&events)
        .map(|(id, (uid, _))| (id.clone(), uid.clone()))
        .collect();
    let accepted = PlanAcceptance {
        policy_version: readiness::POLICY_VERSION,
        accepted_at: chrono::Utc::now().timestamp(),
        proposal_revision: revision,
        value_hashes: runs
            .iter()
            .flat_map(|r| &r.appointments)
            .filter(|a| selection.contains(&a.id))
            .map(|a| (a.id.clone(), review::values_hash(a)))
            .collect(),
    };
    let tx = store.connection.transaction().map_err(failure)?;
    tx.execute(
        "INSERT INTO settings VALUES(?1,?2)",
        rusqlite::params![
            format!("export-acceptance:{}", uuid::Uuid::new_v4()),
            serde_json::to_string(&accepted).map_err(failure)?
        ],
    )
    .map_err(failure)?;
    if previous.is_none() {
        let mut sorted = events;
        sorted.sort_by_key(|(_, v)| serde_json::to_string(v).unwrap());
        tx.execute(
            "INSERT INTO settings VALUES(?1,?2)",
            rusqlite::params![
                key,
                serde_json::to_string(&sorted.into_iter().map(|(id, _)| id).collect::<Vec<_>>())
                    .map_err(failure)?
            ],
        )
        .map_err(failure)?;
    }
    for run in &mut runs {
        for a in &mut run.appointments {
            if let Some(uid) = identities.get(&a.id) {
                a.ics_event_id = Some(uid.clone());
                a.ics_exported_hash = Some(review::values_hash(a));
            }
        }
        tx.execute(
            "UPDATE scans SET run=?2 WHERE id=?1",
            rusqlite::params![
                run.document.id,
                serde_json::to_string(run).map_err(failure)?
            ],
        )
        .map_err(failure)?;
    }
    tx.commit().map_err(failure)?;
    Ok(text)
}
