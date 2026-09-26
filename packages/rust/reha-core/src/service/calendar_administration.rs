//! Calendar status and journal administration. Only explicit visible confirmation
//! can acknowledge an uncertain write; recovery never starts a new mutation.
use super::{calendar_mutations as edits, AppState, Platform, Response, ServiceError};
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use std::sync::Arc;

#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum Access {
    FullAccess,
    Denied,
    Restricted,
    NotDetermined,
}
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct Calendar {
    pub id: String,
    pub title: String,
    pub writable: bool,
}
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct PlatformStatus {
    pub access: Access,
    pub last_read_at: Option<String>,
    pub calendars: Vec<Calendar>,
    #[serde(default)]
    pub unavailable_calendar_ids: Vec<String>,
}
#[derive(Debug, Serialize)]
pub struct Status {
    #[serde(flatten)]
    pub platform: PlatformStatus,
    pub calendar_id: Option<String>,
    pub display_calendar_ids: Option<Vec<String>>,
    pub pending_imports: u64,
    pub pending_events: u32,
    pub pending_bookkeeping: u32,
}
#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum HistoryStatus {
    Pending,
    Saved,
    Failed,
    Uncertain,
    Conflict,
    Acknowledged,
}
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct HistoryItem {
    pub id: String,
    pub created_at: i64,
    pub proposal: edits::Proposal,
    pub status: HistoryStatus,
    pub result: Option<edits::MutationResult>,
    pub undo_of: Option<String>,
    pub undone_by: Option<String>,
}
#[derive(Debug, Serialize)]
pub struct BookkeepingResult {
    pub pending_bookkeeping: u32,
}
#[derive(Debug, Serialize)]
pub struct ReconciliationResult {
    pub maintenance_warnings: Vec<String>,
}
pub struct AcknowledgeRequest {
    pub id: String,
    pub confirmation: edits::Confirmation,
}
pub fn storage(error: impl std::fmt::Display) -> ServiceError {
    ServiceError::Storage(error.to_string())
}
pub async fn status(platform: Arc<dyn Platform>, state: &AppState) -> Response<Status> {
    let platform = tokio::task::spawn_blocking(move || platform.calendar_status())
        .await
        .map_err(storage)??;
    let store = state.store.lock().map_err(storage)?;
    let preferences: Value = store
        .setting("preferences")
        .map_err(storage)?
        .and_then(|s| serde_json::from_str(&s).ok())
        .unwrap_or(json!({}));
    Ok(Status {
        platform,
        calendar_id: serde_json::from_value(preferences["calendar_id"].clone()).map_err(storage)?,
        display_calendar_ids: serde_json::from_value(preferences["display_calendar_ids"].clone())
            .map_err(storage)?,
        pending_imports: store.pending().map_err(storage)?.len() as u64,
        pending_events: store
            .connection
            .query_row(
                "SELECT count(*) FROM event_mutations WHERE status IN ('pending','uncertain')",
                [],
                |row| row.get(0),
            )
            .map_err(storage)?,
        pending_bookkeeping: crate::store::bookkeeping::pending_count(&store).map_err(storage)?,
    })
}
pub fn history(state: &AppState) -> Response<Vec<HistoryItem>> {
    state
        .store
        .lock()
        .map_err(storage)?
        .event_history()
        .map_err(storage)?
        .into_iter()
        .map(|item| serde_json::from_value(item).map_err(storage))
        .collect()
}
pub fn event_detail(state: &AppState, id: &str) -> Response<Option<HistoryItem>> {
    if id.is_empty() {
        return Err(ServiceError::Validation("Verlaufseintrag fehlt.".into()));
    }
    state
        .store
        .lock()
        .map_err(storage)?
        .event_mutation(id)
        .map_err(storage)?
        .map(|item| serde_json::from_value(item).map_err(storage))
        .transpose()
}
pub async fn reconcile_bookkeeping(state: &AppState) -> Response<BookkeepingResult> {
    let _guard = state.calendar_lock.lock().await;
    let store = state.store.lock().map_err(storage)?;
    crate::store::bookkeeping::recover(&store)
        .map_err(|_| ServiceError::Storage(crate::store::bookkeeping::WARNING.into()))?;
    Ok(BookkeepingResult {
        pending_bookkeeping: crate::store::bookkeeping::pending_count(&store).map_err(storage)?,
    })
}
pub async fn acknowledge(
    state: &AppState,
    request: AcknowledgeRequest,
) -> Response<edits::MutationResult> {
    let _guard = state.calendar_lock.lock().await;
    if request.confirmation != edits::Confirmation::Button {
        return Err(ServiceError::Validation(
            "Kalenderprüfung ausdrücklich bestätigen.".into(),
        ));
    }
    if request.id.is_empty() {
        return Err(ServiceError::Validation("Verlaufseintrag fehlt.".into()));
    }
    let store = state.store.lock().map_err(storage)?;
    // Acknowledgement does not replay or reinterpret the stored proposal.
    let item = store
        .event_mutation(&request.id)
        .map_err(storage)?
        .ok_or_else(|| ServiceError::Validation("Verlaufseintrag fehlt.".into()))?;
    let status: HistoryStatus = serde_json::from_value(item["status"].clone()).map_err(storage)?;
    if !matches!(status, HistoryStatus::Pending | HistoryStatus::Uncertain) {
        return Err(ServiceError::Validation(
            "Nur unklare Vorgänge manuell abschließen.".into(),
        ));
    }
    let result = edits::MutationResult {
        status: edits::Status::Acknowledged, event: None, operation_id: None,
        message: Some("Nach manueller Kalenderprüfung abgeschlossen. Kein erneuter Schreibversuch und kein App-Rückgängig.".into()),
        maintenance_warnings: vec![],
    };
    store
        .finish_event_mutation(
            &request.id,
            &serde_json::to_value(&result).map_err(storage)?,
        )
        .map_err(storage)?;
    Ok(result)
}
pub async fn reconcile_events(
    platform: Arc<dyn Platform>,
    state: &AppState,
) -> Response<ReconciliationResult> {
    let _guard = state.calendar_lock.lock().await;
    let records = state
        .store
        .lock()
        .map_err(storage)?
        .event_history()
        .map_err(storage)?;
    for record in records
        .into_iter()
        .filter(|item| matches!(item["status"].as_str(), Some("pending" | "uncertain")))
    {
        // Finished historical records need no replay-contract decoding.
        let item: HistoryItem = serde_json::from_value(record).map_err(storage)?;
        let result = edits::mutate(
            platform.clone(),
            edits::MutationRequest {
                proposal: item.proposal,
                recovery_only: true,
            },
        )
        .await?;
        state
            .store
            .lock()
            .map_err(storage)?
            .finish_event_mutation(&item.id, &serde_json::to_value(result).map_err(storage)?)
            .map_err(storage)?;
    }
    Ok(ReconciliationResult {
        maintenance_warnings: super::agenda::sync_warnings(&platform, state).await,
    })
}
