use crate::state::Proposal;
use crate::state::{failure, AppState, Response};
use reha_core::contracts::*;
use reha_core::{calendar, store::Store};
use serde_json::{json, Value};
use std::collections::{BTreeMap, HashSet};
use std::sync::Arc;
use tauri::State;

fn approved_events(
    run: &PipelineRun,
    timezone: &str,
    reminder: Option<u32>,
) -> Response<Vec<(String, EventValues)>> {
    if !run.review_confirmed {
        return Err("Zuerst mit dem Papier vergleichen und die Prüfung bestätigen.".into());
    }
    let events = run
        .appointments
        .iter()
        .filter(|a| a.included)
        .map(|a| {
            calendar::event_values(a, timezone, reminder)
                .map(|v| (a.id.clone(), v))
                .map_err(failure)
        })
        .collect::<Response<Vec<_>>>()?;
    if events.is_empty() {
        return Err("Mindestens einen Termin auswählen.".into());
    }
    Ok(events)
}
fn schedule_runs(store: &Store, id: &str) -> Response<Vec<PipelineRun>> {
    let ids: Vec<String> = store
        .setting(&format!("pages:{id}"))
        .map_err(failure)?
        .map(|v| serde_json::from_str(&v))
        .transpose()
        .map_err(failure)?
        .unwrap_or_else(|| vec![id.to_owned()]);
    ids.iter()
        .map(|id| store.load_run(id).map_err(failure))
        .collect()
}
fn schedule_events(
    runs: &[PipelineRun],
    timezone: &str,
    reminder: Option<u32>,
) -> Response<Vec<(String, EventValues)>> {
    let mut events = vec![];
    for run in runs {
        events.extend(approved_events(run, timezone, reminder)?);
    }
    Ok(events)
}
#[tauri::command]
pub(crate) fn set_page_group(
    state: State<'_, Arc<AppState>>,
    id: String,
    page_ids: Vec<String>,
) -> Response<usize> {
    if page_ids.len() > 12 {
        return Err("Maximal zwölf Seiten pro Tagesplan.".into());
    }
    let store = state.store.lock().map_err(failure)?;
    let mut ids = vec![id.clone()];
    for page in page_ids {
        if !ids.contains(&page) {
            ids.push(page);
        }
    }
    let mut hashes = HashSet::new();
    let mut dates = HashSet::new();
    for page in &ids {
        let run = store.load_run(page).map_err(failure)?;
        if !run.review_confirmed {
            return Err("Jede zugehörige Seite zuerst einzeln prüfen und bestätigen.".into());
        }
        if !hashes.insert(run.document.source_hash) {
            return Err("Dasselbe Foto darf nur einmal in einer Seitengruppe vorkommen.".into());
        }
        for a in run.appointments.iter().filter(|a| a.included) {
            dates.insert(a.date.clone());
        }
    }
    if dates.len() != 1 || dates.contains(&None) {
        return Err(
            "Zusammengehörige Seiten brauchen denselben bestätigten Behandlungstag.".into(),
        );
    }
    store
        .set_setting(
            &format!("pages:{id}"),
            &serde_json::to_string(&ids).map_err(failure)?,
        )
        .map_err(failure)?;
    state.proposals.lock().map_err(failure)?.clear();
    Ok(ids.len())
}
#[tauri::command]
pub(crate) fn page_group(state: State<'_, Arc<AppState>>, id: String) -> Response<Vec<String>> {
    let store = state.store.lock().map_err(failure)?;
    Ok(schedule_runs(&store, &id)?
        .iter()
        .map(|r| r.document.id.clone())
        .collect())
}
#[tauri::command]
pub(crate) fn export_ics(
    state: State<'_, Arc<AppState>>,
    id: String,
    timezone: String,
    reminder: Option<u32>,
) -> Response<String> {
    let store = state.store.lock().map_err(failure)?;
    let runs = schedule_runs(&store, &id)?;
    let mut events = schedule_events(&runs, &timezone, reminder)?;
    let fingerprint =
        calendar::schedule_fingerprint(&events.iter().map(|(_, v)| v.clone()).collect::<Vec<_>>());
    let key = format!("export:{fingerprint}");
    if let Some(saved) = store.setting(&key).map_err(failure)? {
        let ids: Vec<String> = serde_json::from_str(&saved).map_err(failure)?;
        let mut indices: Vec<_> = (0..events.len()).collect();
        indices.sort_by_key(|&i| serde_json::to_string(&events[i].1).unwrap());
        if ids.len() == indices.len() {
            for (i, id) in indices.into_iter().zip(ids) {
                events[i].0 = id;
            }
        }
    } else {
        let mut sorted = events.clone();
        sorted.sort_by_key(|(_, v)| serde_json::to_string(v).unwrap());
        store
            .set_setting(
                &key,
                &serde_json::to_string(&sorted.iter().map(|(id, _)| id).collect::<Vec<_>>())
                    .map_err(failure)?,
            )
            .map_err(failure)?;
    }
    calendar::ics(&events, chrono::Utc::now()).map_err(failure)
}
#[tauri::command]
pub(crate) async fn calendars(app: tauri::AppHandle) -> Response<Value> {
    tauri::async_runtime::spawn_blocking(move || {
        tauri_plugin_reha_calendar::call(&app, "calendars", json!({}))
    })
    .await
    .map_err(failure)?
}
#[tauri::command]
pub(crate) async fn share_export(
    app: tauri::AppHandle,
    filename: String,
    content: String,
) -> Response<Value> {
    tauri::async_runtime::spawn_blocking(move || {
        tauri_plugin_reha_calendar::call(
            &app,
            "share",
            json!({"filename":filename,"content":content}),
        )
    })
    .await
    .map_err(failure)?
}
#[tauri::command]
pub(crate) async fn prepare_calendar(
    app: tauri::AppHandle,
    state: State<'_, Arc<AppState>>,
    id: String,
    calendar_id: String,
    previous: Option<String>,
    timezone: String,
    reminder: Option<u32>,
) -> Response<Proposal> {
    let (runs, events, records, schedule_id, fingerprint) = {
        let store = state.store.lock().map_err(failure)?;
        if !store.pending().map_err(failure)?.is_empty() {
            return Err("Unklare Schreibvorgänge zuerst im Verlauf abgleichen. Keine neue Erstellung bis zur Auflösung.".into());
        }
        let runs = schedule_runs(&store, &id)?;
        let events = schedule_events(&runs, &timezone, reminder)?;
        let fingerprint = calendar::schedule_fingerprint(
            &events.iter().map(|(_, v)| v.clone()).collect::<Vec<_>>(),
        );
        let equivalent = store.equivalent_schedule(&fingerprint).map_err(failure)?;
        let bound = store
            .list_scans()
            .map_err(failure)?
            .into_iter()
            .find(|s| s.id == id)
            .and_then(|s| s.schedule_id);
        let schedule_id = previous
            .or(equivalent)
            .or(bound)
            .unwrap_or_else(|| uuid::Uuid::new_v4().to_string());
        let records = store.records(Some(&schedule_id)).map_err(failure)?;
        if records
            .iter()
            .any(|record| record.calendar_id != calendar_id)
        {
            return Err("Dieser Plan wurde in einen anderen Kalender importiert. Für Änderungen den ursprünglichen Zielkalender auswählen.".into());
        }
        (runs, events, records, schedule_id, fingerprint)
    };
    let query = json!({"records":records});
    let live = tauri::async_runtime::spawn_blocking(move || {
        tauri_plugin_reha_calendar::call(&app, "snapshot", query)
    })
    .await
    .map_err(failure)??;
    let current: BTreeMap<String, EventValues> =
        serde_json::from_value(live["current"].clone()).map_err(failure)?;
    let operations = calendar::propose(
        &records,
        &events,
        &current,
        &calendar_id,
        runs[0].complete_page_confirmed,
    );
    let proposal = Proposal {
        token: uuid::Uuid::new_v4().to_string(),
        document_id: id,
        document_ids: runs.iter().map(|r| r.document.id.clone()).collect(),
        run_hash: reha_core::hash(&serde_json::to_vec(&runs).map_err(failure)?),
        schedule_id,
        fingerprint,
        operations,
    };
    let mut proposals = state.proposals.lock().map_err(failure)?;
    proposals.clear();
    proposals.insert(proposal.token.clone(), proposal.clone());
    Ok(proposal)
}
#[tauri::command]
pub(crate) fn resolve_proposal(
    state: State<'_, Arc<AppState>>,
    token: String,
    event_id: String,
    choice: String,
) -> Response<Proposal> {
    let mut proposals = state.proposals.lock().map_err(failure)?;
    let proposal = proposals.get_mut(&token).ok_or("Vorschau abgelaufen.")?;
    if let Some(previous_id) = choice.strip_prefix("match:") {
        let new_index = proposal
            .operations
            .iter()
            .position(|op| op.id == event_id && op.kind == "ambiguous")
            .ok_or("Neue Zuordnung fehlt.")?;
        let old_index = proposal
            .operations
            .iter()
            .position(|op| {
                op.id == previous_id
                    && op.kind == "keep"
                    && op.after.is_none()
                    && op.before.is_some()
                    && op.external_id.is_some()
            })
            .ok_or("Bisheriger Eintrag kann nicht zugeordnet werden.")?;
        if new_index == old_index {
            return Err("Ungültige Zuordnung.".into());
        }
        let mut matched = proposal.operations[old_index].clone();
        matched.kind = "update".into();
        matched.after = proposal.operations[new_index].after.clone();
        matched.requires_resolution = false;
        matched.reason =
            "Vorherigen App-Termin ausdrücklich diesem Papiertermin zugeordnet.".into();
        proposal.operations[new_index] = matched;
        proposal.operations.remove(old_index);
        return Ok(proposal.clone());
    }
    let op = proposal
        .operations
        .iter_mut()
        .find(|o| o.id == event_id)
        .ok_or("Termin fehlt.")?;
    match choice.as_str() {
        "keep" => {
            op.kind = "keep".into();
            op.requires_resolution = false;
            op.reason = "Bisherigen Kalenderstand ausdrücklich behalten.".into();
        }
        "paper" if op.kind == "conflict" && op.before.is_some() && op.after.is_some() => {
            op.kind = "update".into();
            op.requires_resolution = false;
            op.reason = "Papierwerte ausdrücklich gewählt.".into();
        }
        "new" if op.kind == "ambiguous" => {
            op.kind = "create".into();
            op.requires_resolution = false;
            op.reason = "Ausdrücklich als zusätzlichen Termin ausgewählt.".into();
        }
        _ => {
            return Err(
                "Diese Auflösung ist nicht möglich. Kalender prüfen und neue Vorschau erstellen."
                    .into(),
            )
        }
    }
    Ok(proposal.clone())
}
#[tauri::command]
pub(crate) async fn approve_calendar(
    app: tauri::AppHandle,
    state: State<'_, Arc<AppState>>,
    token: String,
    approve_removals: bool,
) -> Response<Vec<CalendarResult>> {
    let _guard = state.calendar_lock.lock().await;
    let proposal = state
        .proposals
        .lock()
        .map_err(failure)?
        .get(&token)
        .cloned()
        .ok_or("Vorschau abgelaufen.")?;
    if proposal.operations.iter().any(|o| o.requires_resolution) {
        return Err("Unklare Zuordnungen zuerst auflösen.".into());
    }
    if proposal.operations.iter().any(|o| o.kind == "remove") && !approve_removals {
        return Err("Löschungen separat bestätigen.".into());
    }
    {
        let store = state.store.lock().map_err(failure)?;
        let runs = schedule_runs(&store, &proposal.document_id)?;
        if reha_core::hash(&serde_json::to_vec(&runs).map_err(failure)?) != proposal.run_hash {
            return Err("Prüfdaten wurden geändert. Kalender-Vorschau neu erstellen.".into());
        }
        for page in &proposal.document_ids {
            store
                .bind_schedule(page, &proposal.schedule_id, &proposal.fingerprint)
                .map_err(failure)?;
        }
    }
    let mut results = vec![];
    for op in proposal
        .operations
        .iter()
        .filter(|o| ["create", "update", "remove"].contains(&o.kind.as_str()))
    {
        let (operation_id, recovery_only) = {
            let store = state.store.lock().map_err(failure)?;
            let recovery = store
                .pending()
                .map_err(failure)?
                .iter()
                .any(|(_, p)| p.id == op.id);
            (
                store
                    .begin_operation(&proposal.schedule_id, op)
                    .map_err(failure)?,
                recovery,
            )
        };
        let args = json!({"operation":op,"recovery_only":recovery_only});
        let app = app.clone();
        let result = tauri::async_runtime::spawn_blocking(move || {
            tauri_plugin_reha_calendar::call(&app, "apply", args)
        })
        .await
        .map_err(failure)?;
        let outcome = match result {
            Ok(value) => serde_json::from_value(value).map_err(failure)?,
            Err(_) => CalendarResult {
                id: op.id.clone(),
                status: "uncertain".into(),
                external_id: None,
                error: Some("Schreibstatus unklar. Vor erneutem Schreiben abgleichen.".into()),
            },
        };
        state
            .store
            .lock()
            .map_err(failure)?
            .finish_operation(&operation_id, &outcome)
            .map_err(failure)?;
        results.push(outcome);
    }
    state.proposals.lock().map_err(failure)?.remove(&token);
    Ok(results)
}
#[tauri::command]
pub(crate) async fn reconcile_calendar(
    app: tauri::AppHandle,
    state: State<'_, Arc<AppState>>,
) -> Response<Vec<CalendarResult>> {
    let _guard = state.calendar_lock.lock().await;
    let pending = state
        .store
        .lock()
        .map_err(failure)?
        .pending()
        .map_err(failure)?;
    let mut results = vec![];
    for (id, op) in pending {
        let args = json!({"operation":op,"recovery_only":true});
        let app = app.clone();
        let value = tauri::async_runtime::spawn_blocking(move || {
            tauri_plugin_reha_calendar::call(&app, "apply", args)
        })
        .await
        .map_err(failure)??;
        let result: CalendarResult = serde_json::from_value(value).map_err(failure)?;
        state
            .store
            .lock()
            .map_err(failure)?
            .finish_operation(&id, &result)
            .map_err(failure)?;
        results.push(result);
    }
    Ok(results)
}
#[tauri::command]
pub(crate) async fn resolve_pending_write(
    state: State<'_, Arc<AppState>>,
    operation_id: String,
    resolution: String,
) -> Response<()> {
    let _guard = state.calendar_lock.lock().await;
    let mut store = state.store.lock().map_err(failure)?;
    let (_, op) = store
        .pending()
        .map_err(failure)?
        .into_iter()
        .find(|(id, _)| id == &operation_id)
        .ok_or("Unklarer Vorgang existiert nicht mehr.")?;
    let status = match resolution.as_str() {
        "not_applied" => "failed",
        "removal_applied" if op.kind == "remove" => "saved",
        _ => return Err("Ungültige manuelle Auflösung.".into()),
    };
    store
        .finish_operation(
            &operation_id,
            &CalendarResult {
                id: op.id,
                status: status.into(),
                external_id: None,
                error: Some(
                    "Ergebnis vom Benutzer nach Prüfung im Kalender ausdrücklich bestätigt.".into(),
                ),
            },
        )
        .map_err(failure)?;
    state.proposals.lock().map_err(failure)?.clear();
    Ok(())
}
