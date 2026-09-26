//! Calendar editing independent of photo ownership. Only an explicit UI confirmation
//! consumes a volatile proposal; confirmed requests alone enter the durable journal.
use super::{failure, AppState, Platform, Response};
use serde_json::{json, Value};
use std::sync::Arc;

pub use super::calendar_mutations::Proposal as EventProposal;
fn required<'a>(v: &'a Value, key: &str) -> Response<&'a str> {
    v[key]
        .as_str()
        .filter(|s| !s.is_empty())
        .ok_or_else(|| format!("{key} fehlt.").into())
}
async fn native(platform: &Arc<dyn Platform>, name: &'static str, args: Value) -> Response<Value> {
    let platform = platform.clone();
    tokio::task::spawn_blocking(move || platform.call(name, args))
        .await
        .map_err(failure)?
}
/// Compatibility command adapter. New application callers use agenda_queries directly.
pub async fn query(platform: Arc<dyn Platform>, state: &AppState, args: Value) -> Response<Value> {
    let request = super::agenda_queries::Request {
        start_utc: required(&args, "start_utc")?.into(),
        end_utc: required(&args, "end_utc")?.into(),
        // Missing scope means current selection; explicit null remains invalid.
        expected_scope: args
            .get("scope")
            .map(|scope| serde_json::from_value(scope.clone()))
            .transpose()
            .map_err(failure)?,
    };
    let result = super::agenda_queries::query(platform, state, request)
        .await
        .map_err(super::agenda_queries::QueryError::legacy)?;
    Ok(json!({"events": result.events, "scope": result.scope,
        "unavailable_calendar_ids": result.unavailable_calendar_ids,
        "unavailable_events": result.unavailable_events}))
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
                "event" => {
                    drop(store);
                    serde_json::to_value(super::calendar_administration::event_detail(state, id)?)
                        .map_err(failure)
                }
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
            serde_json::to_value(super::calendar_administration::status(platform, state).await?)
                .map_err(failure)
        }
        "reconcileCalendarBookkeeping" => serde_json::to_value(
            super::calendar_administration::reconcile_bookkeeping(state).await?,
        )
        .map_err(failure),
        "refreshAgenda" => {
            let _guard = state.calendar_lock.lock().await;
            super::agenda::legacy_sync(&platform, state).await
        }
        "appendPlanPages" => {
            let pages: Vec<String> =
                serde_json::from_value(args["pages"].clone()).map_err(failure)?;
            Ok(
                json!({"count": super::calendar::append_pages(state, required(&args, "id")?.into(), pages)?}),
            )
        }
        "agendaSelection" => {
            serde_json::to_value(super::agenda_queries::selection(state)?).map_err(failure)
        }
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
        "eventHistory" => Ok(json!({"history":super::calendar_administration::history(state)?})),
        "registerEventSession" => {
            let session = super::calendar_mutations::register(state)?;
            Ok(json!({"session":session}))
        }
        "invalidateEventSession" => {
            let session = required(&args, "session")?;
            super::calendar_mutations::invalidate(state, session)?;
            Ok(json!({}))
        }
        "resolveEventUncertainty" => serde_json::to_value(
            super::calendar_administration::acknowledge(
                state,
                super::calendar_administration::AcknowledgeRequest {
                    id: required(&args, "id")?.into(),
                    confirmation: if args["confirmation"] == "button" {
                        super::calendar_mutations::Confirmation::Button
                    } else {
                        super::calendar_mutations::Confirmation::MissingVisibleButton
                    },
                },
            )
            .await?,
        )
        .map_err(failure),
        "reconcileEventMutations" => serde_json::to_value(
            super::calendar_administration::reconcile_events(platform, state).await?,
        )
        .map_err(failure),
        _ => Err("Unbekannte Kalenderfunktion.".into()),
    }
}
