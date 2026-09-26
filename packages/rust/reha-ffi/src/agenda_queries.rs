//! Application read requests carry a selection expectation, never ownership records.
use crate::{
    application::{failure, storage},
    runtime, AppError, CalendarReadEvent, CalendarReadUnavailableEvent, NativeApplication,
};
use reha_core::service::agenda_queries as core;

#[derive(Clone, Debug, uniffi::Record)]
pub struct AgendaQueryScope {
    pub calendar_ids: Vec<String>,
    pub timezone: String,
    pub revision: u64,
}
#[derive(Clone, Debug, uniffi::Record)]
pub struct AgendaQueryRequest {
    pub start_utc: String,
    pub end_utc: String,
    pub expected_scope: Option<AgendaQueryScope>,
}
#[derive(Clone, Debug, uniffi::Record)]
pub struct AgendaQueryResult {
    pub start_utc: String,
    pub end_utc: String,
    pub scope: AgendaQueryScope,
    pub events: Vec<CalendarReadEvent>,
    pub unavailable_calendar_ids: Vec<String>,
    pub unavailable_events: Vec<CalendarReadUnavailableEvent>,
}
impl From<core::Scope> for AgendaQueryScope {
    fn from(scope: core::Scope) -> Self {
        Self {
            calendar_ids: scope.calendar_ids,
            timezone: scope.timezone,
            revision: scope.revision,
        }
    }
}
impl From<AgendaQueryScope> for core::Scope {
    fn from(scope: AgendaQueryScope) -> Self {
        Self {
            calendar_ids: scope.calendar_ids,
            timezone: scope.timezone,
            revision: scope.revision,
        }
    }
}
impl From<AgendaQueryRequest> for core::Request {
    fn from(request: AgendaQueryRequest) -> Self {
        Self {
            start_utc: request.start_utc,
            end_utc: request.end_utc,
            expected_scope: request.expected_scope.map(Into::into),
        }
    }
}
impl From<core::QueryResult> for AgendaQueryResult {
    fn from(result: core::QueryResult) -> Self {
        Self {
            start_utc: result.start_utc,
            end_utc: result.end_utc,
            scope: result.scope.into(),
            events: result.events.into_iter().map(Into::into).collect(),
            unavailable_calendar_ids: result.unavailable_calendar_ids,
            unavailable_events: result
                .unavailable_events
                .into_iter()
                .map(|event| CalendarReadUnavailableEvent {
                    id: event.id,
                    start_utc: event.start_utc,
                    end_utc: event.end_utc,
                })
                .collect(),
        }
    }
}
fn query_error(error: core::QueryError) -> AppError {
    match error {
        core::QueryError::SelectionChanged { .. } => AppError::StaleRevision,
        core::QueryError::Service(error) => failure(error),
    }
}
#[uniffi::export]
impl NativeApplication {
    pub async fn agenda_selection(&self) -> Result<AgendaQueryScope, AppError> {
        let state = self.state.clone();
        runtime()
            .spawn_blocking(move || core::selection(&state).map(Into::into).map_err(failure))
            .await
            .map_err(storage)?
    }
    pub async fn query_calendar_events(
        &self,
        request: AgendaQueryRequest,
    ) -> Result<AgendaQueryResult, AppError> {
        let state = self.state.clone();
        let host = self.bridge.clone();
        runtime()
            .spawn(async move {
                core::query(host, &state, request.into())
                    .await
                    .map(Into::into)
                    .map_err(query_error)
            })
            .await
            .map_err(storage)?
    }
}
