//! Visible-calendar reads. The application owns selection and imported identities;
//! callers may require an observed scope but cannot supply ownership records.
use super::{calendar_reads, AppState, Platform, Response, ServiceError};
use serde::{Deserialize, Serialize};
use std::sync::Arc;

#[derive(Clone, Debug, Serialize, Deserialize, PartialEq, Eq)]
pub struct Scope {
    pub calendar_ids: Vec<String>,
    pub timezone: String,
    pub revision: u64,
}
#[derive(Clone, Debug)]
pub struct Request {
    pub start_utc: String,
    pub end_utc: String,
    pub expected_scope: Option<Scope>,
}
#[derive(Clone, Debug, PartialEq)]
pub struct QueryResult {
    pub start_utc: String,
    pub end_utc: String,
    pub scope: Scope,
    pub events: Vec<calendar_reads::Event>,
    pub unavailable_calendar_ids: Vec<String>,
    pub unavailable_events: Vec<calendar_reads::UnavailableEvent>,
}
#[derive(Debug, PartialEq, thiserror::Error)]
pub enum QueryError {
    #[error("Kalenderauswahl wurde geändert. Erneut laden.")]
    SelectionChanged { during_load: bool },
    #[error(transparent)]
    Service(#[from] ServiceError),
}
impl QueryError {
    /// Only the old command adapter retains its established presentation strings.
    /// Native failures keep their variants, even when their messages resemble them.
    pub fn legacy(self) -> ServiceError {
        match self {
            Self::SelectionChanged { during_load: true } => ServiceError::Legacy(
                "Kalenderauswahl wurde während des Ladens geändert. Erneut laden.".into(),
            ),
            Self::SelectionChanged { during_load: false } => {
                ServiceError::Legacy("Kalenderauswahl wurde geändert. Erneut laden.".into())
            }
            Self::Service(error) => error,
        }
    }
}
fn storage(error: impl std::fmt::Display) -> ServiceError {
    ServiceError::Storage(error.to_string())
}
pub fn selection(state: &AppState) -> Response<Scope> {
    let preferences = super::settings::settings_value(state, None).map_err(storage)?;
    let mut calendar_ids: Vec<_> = preferences["display_calendar_ids"]
        .as_array()
        .into_iter()
        .flatten()
        .filter_map(|id| id.as_str().map(str::to_string))
        .collect();
    calendar_ids.sort();
    calendar_ids.dedup();
    Ok(Scope {
        calendar_ids,
        timezone: preferences["timezone"]
            .as_str()
            .unwrap_or("Europe/Vienna")
            .into(),
        revision: preferences["display_selection_revision"]
            .as_u64()
            .unwrap_or(0),
    })
}
pub async fn query(
    platform: Arc<dyn Platform>,
    state: &AppState,
    request: Request,
) -> Result<QueryResult, QueryError> {
    let start = chrono::DateTime::parse_from_rfc3339(&request.start_utc)
        .map_err(|_| ServiceError::Validation("Suchbeginn ungültig.".into()))?;
    let end = chrono::DateTime::parse_from_rfc3339(&request.end_utc)
        .map_err(|_| ServiceError::Validation("Suchende ungültig.".into()))?;
    if end <= start || end - start > chrono::Duration::days(366) {
        return Err(ServiceError::Validation("Suchzeitraum: maximal ein Jahr.".into()).into());
    }
    let scope = selection(state)?;
    if request
        .expected_scope
        .as_ref()
        .is_some_and(|expected| expected != &scope)
    {
        return Err(QueryError::SelectionChanged { during_load: false });
    }
    let result = if scope.calendar_ids.is_empty() {
        calendar_reads::QueryResult {
            events: vec![],
            unavailable_calendar_ids: vec![],
            unavailable_events: vec![],
        }
    } else {
        let records = state
            .store
            .lock()
            .map_err(storage)?
            .owned_records()
            .map_err(storage)?
            .into_iter()
            .filter(|record| record.status == "saved" && record.external_id.is_some())
            .collect();
        let result = calendar_reads::query(
            &platform,
            calendar_reads::Query {
                calendar_ids: scope.calendar_ids.clone(),
                start_utc: request.start_utc.clone(),
                end_utc: request.end_utc.clone(),
                timezone: scope.timezone.clone(),
                selection_revision: scope.revision,
                records,
            },
        )
        .await?;
        if selection(state)? != scope {
            return Err(QueryError::SelectionChanged { during_load: true });
        }
        if result
            .events
            .iter()
            .any(|event| !scope.calendar_ids.contains(&event.calendar_id))
        {
            return Err(
                ServiceError::Storage("Kalenderantwort außerhalb der Auswahl.".into()).into(),
            );
        }
        result
    };
    Ok(QueryResult {
        start_utc: request.start_utc,
        end_utc: request.end_utc,
        scope,
        events: result.events,
        unavailable_calendar_ids: result.unavailable_calendar_ids,
        unavailable_events: result.unavailable_events,
    })
}
