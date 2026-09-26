//! Calendar editing independent of photo ownership. Only an explicit UI confirmation
//! consumes a volatile proposal; confirmed requests alone enter the durable journal.
use super::{failure, AppState, Platform, Response};
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use std::sync::Arc;

pub use super::calendar_mutations::Proposal as EventProposal;
fn required<'a>(v: &'a Value, key: &str) -> Response<&'a str> {
    v[key]
        .as_str()
        .filter(|s| !s.is_empty())
        .ok_or_else(|| format!("{key} fehlt.").into())
}
fn preferences(state: &AppState) -> Response<Value> {
    super::settings::settings_value(state, None)
}
fn ids(p: &Value) -> Vec<String> {
    p["display_calendar_ids"]
        .as_array()
        .into_iter()
        .flatten()
        .filter_map(|s| s.as_str().map(str::to_string))
        .collect()
}

/// A read is bound to one visible selection, independently of the save target
/// and reminder ownership. The revision also detects A -> B -> A changes.
#[derive(Clone, Debug, Serialize, Deserialize, PartialEq, Eq)]
pub struct AgendaScope {
    pub calendar_ids: Vec<String>,
    pub timezone: String,
    pub revision: u64,
}
impl AgendaScope {
    fn current(state: &AppState) -> Response<Self> {
        let p = preferences(state)?;
        let mut calendar_ids = ids(&p);
        calendar_ids.sort();
        calendar_ids.dedup();
        Ok(Self {
            calendar_ids,
            timezone: p["timezone"].as_str().unwrap_or("Europe/Vienna").into(),
            revision: p["display_selection_revision"].as_u64().unwrap_or(0),
        })
    }
}
async fn native(platform: &Arc<dyn Platform>, name: &'static str, args: Value) -> Response<Value> {
    let platform = platform.clone();
    tokio::task::spawn_blocking(move || platform.call(name, args))
        .await
        .map_err(failure)?
}
pub async fn query(platform: Arc<dyn Platform>, state: &AppState, args: Value) -> Response<Value> {
    let start = chrono::DateTime::parse_from_rfc3339(required(&args, "start_utc")?)
        .map_err(|_| "Suchbeginn ungültig.")?;
    let end = chrono::DateTime::parse_from_rfc3339(required(&args, "end_utc")?)
        .map_err(|_| "Suchende ungültig.")?;
    if end <= start || end - start > chrono::Duration::days(366) {
        return Err("Suchzeitraum: maximal ein Jahr.".into());
    }
    let scope = AgendaScope::current(state)?;
    if let Some(requested) = args.get("scope") {
        let requested: AgendaScope = serde_json::from_value(requested.clone()).map_err(failure)?;
        if requested != scope {
            return Err("Kalenderauswahl wurde geändert. Erneut laden.".into());
        }
    }
    if scope.calendar_ids.is_empty() {
        return Ok(
            json!({"events":[],"unavailable_calendar_ids":[],"unavailable_events":[],"scope":scope}),
        );
    }
    let selected = &scope.calendar_ids;
    let records: Vec<_> = state
        .store
        .lock()
        .map_err(failure)?
        .owned_records()
        .map_err(failure)?
        .into_iter()
        .filter(|r| r.status == "saved" && r.external_id.is_some())
        .collect();
    let mut result = super::calendar_reads::query(
        &platform,
        super::calendar_reads::Query {
            calendar_ids: selected.clone(),
            records,
            start_utc: required(&args, "start_utc")?.into(),
            end_utc: required(&args, "end_utc")?.into(),
            timezone: scope.timezone.clone(),
            selection_revision: scope.revision,
        },
    )
    .await?;
    if AgendaScope::current(state)? != scope {
        return Err("Kalenderauswahl wurde während des Ladens geändert. Erneut laden.".into());
    }
    if result["events"].as_array().is_none_or(|a| {
        a.iter()
            .any(|e| !selected.contains(&e["calendar_id"].as_str().unwrap_or_default().to_string()))
    }) {
        return Err("Kalenderantwort außerhalb der Auswahl.".into());
    }
    result["scope"] = serde_json::to_value(scope).map_err(failure)?;
    Ok(result)
}
pub async fn dispatch(
    platform: Arc<dyn Platform>,
    state: &AppState,
    command: &str,
    args: Value,
) -> Response<Value> {
    match command {
        "activityPage" => serde_json::to_value(
            state
                .store
                .lock()
                .map_err(failure)?
                .activity_page(
                    args["limit"].as_u64().map(|n| n.min(100) as u32),
                    args["cursor"].as_str(),
                    args["source"].as_str(),
                )
                .map_err(failure)?,
        )
        .map_err(failure),
        "activityDetail" => {
            let id = required(&args, "id")?;
            let (source, id) = id.split_once(':').ok_or("Ungültiger Verlaufseintrag.")?;
            let store = state.store.lock().map_err(failure)?;
            match source {
                "import" => {
                    serde_json::to_value(store.batch(id).map_err(failure)?).map_err(failure)
                }
                "event" => Ok(store
                    .event_mutation(id)
                    .map_err(failure)?
                    .unwrap_or(Value::Null)),
                "capture" => Ok(json!({"document_id":id})),
                "recognition" => {
                    let result: (String, String, Option<String>) = store
                        .connection
                        .query_row(
                            "SELECT scan_id,status,error FROM processing_attempts WHERE id=?1",
                            [id],
                            |r| Ok((r.get(0)?, r.get(1)?, r.get(2)?)),
                        )
                        .map_err(failure)?;
                    Ok(json!({"document_id":result.0,"status":result.1,"error":result.2}))
                }
                _ => Err("Unbekannter Verlaufseintrag.".into()),
            }
        }
        "ownedEventRecords" => Ok(
            json!({"records":state.store.lock().map_err(failure)?.owned_records().map_err(failure)?}),
        ),
        "resolveOwnedEvent" => {
            let id = required(&args, "id")?;
            uuid::Uuid::parse_str(id).map_err(failure)?;
            let _guard = state.calendar_lock.lock().await;
            let record = state
                .store
                .lock()
                .map_err(failure)?
                .owned_record(id)
                .map_err(failure)?;
            match record {
                Some(record) if record.status == "saved" => {
                    native(&platform, "resolveOwnedEvent", json!({"record":record})).await
                }
                Some(_) => Ok(json!({"status":"deleted"})),
                None => Ok(json!({"status":"missing"})),
            }
        }
        "inspectCalendarRepair" | "confirmCalendarRepair" => {
            super::calendar_repair::run(platform, state, command, args).await
        }
        "calendarStatus" => {
            let mut status = native(&platform, "calendarStatus", json!({})).await?;
            let store = state.store.lock().map_err(failure)?;
            let prefs: Value = store
                .setting("preferences")
                .map_err(failure)?
                .and_then(|s| serde_json::from_str(&s).ok())
                .unwrap_or(json!({}));
            status["calendar_id"] = prefs["calendar_id"].clone();
            status["display_calendar_ids"] = prefs["display_calendar_ids"].clone();
            status["pending_imports"] = json!(store.pending().map_err(failure)?.len());
            let pending: u32 = store
                .connection
                .query_row(
                    "SELECT count(*) FROM event_mutations WHERE status IN ('pending','uncertain')",
                    [],
                    |r| r.get(0),
                )
                .map_err(failure)?;
            status["pending_events"] = json!(pending);
            status["pending_bookkeeping"] =
                json!(crate::store::bookkeeping::pending_count(&store).map_err(failure)?);
            Ok(status)
        }
        "reconcileCalendarBookkeeping" => {
            let _guard = state.calendar_lock.lock().await;
            let store = state.store.lock().map_err(failure)?;
            crate::store::bookkeeping::recover(&store).map_err(|_| {
                super::ServiceError::Storage(crate::store::bookkeeping::WARNING.into())
            })?;
            Ok(
                json!({"pending_bookkeeping":crate::store::bookkeeping::pending_count(&store).map_err(failure)?}),
            )
        }
        "refreshAgenda" => {
            let _guard = state.calendar_lock.lock().await;
            super::agenda::sync(&platform, state).await
        }
        "appendPlanPages" => {
            let pages: Vec<String> =
                serde_json::from_value(args["pages"].clone()).map_err(failure)?;
            Ok(
                json!({"count": super::calendar::append_pages(state, required(&args, "id")?.into(), pages)?}),
            )
        }
        "agendaSelection" => serde_json::to_value(AgendaScope::current(state)?).map_err(failure),
        "queryCalendarEvents" => query(platform, state, args).await,
        "previewEventMutation" => serde_json::to_value(
            super::calendar_mutations::preview(
                platform,
                state,
                serde_json::from_value(args).map_err(failure)?,
            )
            .await?,
        )
        .map_err(failure),
        "confirmProposal" => serde_json::to_value(
            super::calendar_mutations::confirm(
                platform,
                state,
                serde_json::from_value(args).map_err(failure)?,
            )
            .await?,
        )
        .map_err(failure),
        "previewEventUndo" => serde_json::to_value(
            super::calendar_mutations::undo(
                platform,
                state,
                serde_json::from_value(args).map_err(failure)?,
            )
            .await?,
        )
        .map_err(failure),
        "eventHistory" => Ok(
            json!({"history":state.store.lock().map_err(failure)?.event_history().map_err(failure)?}),
        ),
        "registerEventSession" => {
            let session = super::calendar_mutations::register(state)?;
            Ok(json!({"session":session}))
        }
        "invalidateEventSession" => {
            let session = required(&args, "session")?;
            super::calendar_mutations::invalidate(state, session)?;
            Ok(json!({}))
        }
        "resolveEventUncertainty" => {
            let _guard = state.calendar_lock.lock().await;
            if args["confirmation"] != "button" {
                return Err("Kalenderprüfung ausdrücklich bestätigen.".into());
            }
            let id = required(&args, "id")?;
            let store = state.store.lock().map_err(failure)?;
            let history = store.event_history().map_err(failure)?;
            let item = history
                .iter()
                .find(|h| h["id"] == id)
                .ok_or("Verlaufseintrag fehlt.")?;
            if !matches!(item["status"].as_str(), Some("pending" | "uncertain")) {
                return Err("Nur unklare Vorgänge manuell abschließen.".into());
            }
            let result = json!({"status":"acknowledged","message":"Nach manueller Kalenderprüfung abgeschlossen. Kein erneuter Schreibversuch und kein App-Rückgängig."});
            store.finish_event_mutation(id, &result).map_err(failure)?;
            Ok(result)
        }
        "reconcileEventMutations" => {
            let _guard = state.calendar_lock.lock().await;
            let history = state
                .store
                .lock()
                .map_err(failure)?
                .event_history()
                .map_err(failure)?;
            for item in history.iter().filter(|h| {
                ["pending", "uncertain"].contains(&h["status"].as_str().unwrap_or_default())
            }) {
                let result = super::calendar_mutations::mutate(
                    platform.clone(),
                    super::calendar_mutations::MutationRequest {
                        proposal: serde_json::from_value(item["proposal"].clone())
                            .map_err(failure)?,
                        recovery_only: true,
                    },
                )
                .await?;
                let result = serde_json::to_value(result).map_err(failure)?;
                state
                    .store
                    .lock()
                    .map_err(failure)?
                    .finish_event_mutation(required(item, "id")?, &result)
                    .map_err(failure)?;
            }
            let warnings = super::agenda::sync_warnings(&platform, state).await;
            Ok(json!({"maintenance_warnings":warnings}))
        }
        _ => Err("Unbekannte Kalenderfunktion.".into()),
    }
}
