use crate::{
    application::{failure, storage},
    runtime, AppError, EventConfirmation, EventEditProposal, EventMutationResult,
    NativeApplication,
};
use reha_core::service::{calendar_administration as core, calendar_mutations as edits};

#[derive(Clone, Copy, Debug, uniffi::Enum)]
pub enum CalendarAccessStatus {
    FullAccess,
    Denied,
    Restricted,
    NotDetermined,
}
#[derive(Clone, Debug, uniffi::Record)]
pub struct CalendarStatusItem {
    pub id: String,
    pub title: String,
    pub writable: bool,
}
#[derive(Clone, Debug, uniffi::Record)]
pub struct CalendarPlatformStatus {
    pub access: CalendarAccessStatus,
    pub last_read_at: Option<String>,
    pub calendars: Vec<CalendarStatusItem>,
    pub unavailable_calendar_ids: Vec<String>,
}
#[derive(Clone, Debug, uniffi::Record)]
pub struct CalendarAdministrationStatus {
    pub platform: CalendarPlatformStatus,
    pub calendar_id: Option<String>,
    pub display_calendar_ids: Vec<String>,
    pub pending_imports: u64,
    pub pending_events: u32,
    pub pending_bookkeeping: u32,
}
#[derive(Clone, Copy, Debug, uniffi::Enum)]
pub enum EventHistoryStatus {
    Pending,
    Saved,
    Failed,
    Uncertain,
    Conflict,
    Acknowledged,
}
#[derive(Clone, Debug, uniffi::Record)]
pub struct EventHistoryRecord {
    pub id: String,
    pub created_at: i64,
    pub proposal: EventEditProposal,
    pub status: EventHistoryStatus,
    pub result: Option<EventMutationResult>,
    pub undo_of: Option<String>,
    pub undone_by: Option<String>,
}
#[derive(Clone, Debug, uniffi::Record)]
pub struct CalendarBookkeepingResult {
    pub pending_bookkeeping: u32,
}
#[derive(Clone, Debug, uniffi::Record)]
pub struct EventReconciliationResult {
    pub maintenance_warnings: Vec<String>,
}
#[derive(Clone, Debug, uniffi::Record)]
pub struct ResolveEventUncertaintyRequest {
    pub id: String,
    pub confirmation: EventConfirmation,
}

impl From<core::PlatformStatus> for CalendarPlatformStatus {
    fn from(value: core::PlatformStatus) -> Self {
        Self {
            access: match value.access {
                core::Access::FullAccess => CalendarAccessStatus::FullAccess,
                core::Access::Denied => CalendarAccessStatus::Denied,
                core::Access::Restricted => CalendarAccessStatus::Restricted,
                core::Access::NotDetermined => CalendarAccessStatus::NotDetermined,
            },
            last_read_at: value.last_read_at,
            calendars: value
                .calendars
                .into_iter()
                .map(|c| CalendarStatusItem {
                    id: c.id,
                    title: c.title,
                    writable: c.writable,
                })
                .collect(),
            unavailable_calendar_ids: value.unavailable_calendar_ids,
        }
    }
}
impl From<CalendarPlatformStatus> for core::PlatformStatus {
    fn from(value: CalendarPlatformStatus) -> Self {
        Self {
            access: match value.access {
                CalendarAccessStatus::FullAccess => core::Access::FullAccess,
                CalendarAccessStatus::Denied => core::Access::Denied,
                CalendarAccessStatus::Restricted => core::Access::Restricted,
                CalendarAccessStatus::NotDetermined => core::Access::NotDetermined,
            },
            last_read_at: value.last_read_at,
            calendars: value
                .calendars
                .into_iter()
                .map(|c| core::Calendar {
                    id: c.id,
                    title: c.title,
                    writable: c.writable,
                })
                .collect(),
            unavailable_calendar_ids: value.unavailable_calendar_ids,
        }
    }
}
impl From<core::Status> for CalendarAdministrationStatus {
    fn from(value: core::Status) -> Self {
        Self {
            platform: value.platform.into(),
            calendar_id: value.calendar_id,
            display_calendar_ids: value.display_calendar_ids.unwrap_or_default(),
            pending_imports: value.pending_imports,
            pending_events: value.pending_events,
            pending_bookkeeping: value.pending_bookkeeping,
        }
    }
}
impl From<core::HistoryItem> for EventHistoryRecord {
    fn from(value: core::HistoryItem) -> Self {
        Self {
            id: value.id,
            created_at: value.created_at,
            proposal: value.proposal.into(),
            status: match value.status {
                core::HistoryStatus::Pending => EventHistoryStatus::Pending,
                core::HistoryStatus::Saved => EventHistoryStatus::Saved,
                core::HistoryStatus::Failed => EventHistoryStatus::Failed,
                core::HistoryStatus::Uncertain => EventHistoryStatus::Uncertain,
                core::HistoryStatus::Conflict => EventHistoryStatus::Conflict,
                core::HistoryStatus::Acknowledged => EventHistoryStatus::Acknowledged,
            },
            result: value.result.map(Into::into),
            undo_of: value.undo_of,
            undone_by: value.undone_by,
        }
    }
}
#[uniffi::export]
impl NativeApplication {
    pub async fn calendar_status(&self) -> Result<CalendarAdministrationStatus, AppError> {
        let state = self.state.clone();
        let host = self.bridge.clone();
        runtime()
            .spawn(async move {
                core::status(host, &state)
                    .await
                    .map(Into::into)
                    .map_err(failure)
            })
            .await
            .map_err(storage)?
    }
    pub async fn reconcile_calendar_bookkeeping(
        &self,
    ) -> Result<CalendarBookkeepingResult, AppError> {
        let state = self.state.clone();
        runtime()
            .spawn(async move {
                core::reconcile_bookkeeping(&state)
                    .await
                    .map(|result| CalendarBookkeepingResult {
                        pending_bookkeeping: result.pending_bookkeeping,
                    })
                    .map_err(failure)
            })
            .await
            .map_err(storage)?
    }
    pub async fn reconcile_event_mutations(&self) -> Result<EventReconciliationResult, AppError> {
        let state = self.state.clone();
        let host = self.bridge.clone();
        runtime()
            .spawn(async move {
                core::reconcile_events(host, &state)
                    .await
                    .map(|result| EventReconciliationResult {
                        maintenance_warnings: result.maintenance_warnings,
                    })
                    .map_err(failure)
            })
            .await
            .map_err(storage)?
    }
    pub async fn resolve_event_uncertainty(
        &self,
        request: ResolveEventUncertaintyRequest,
    ) -> Result<EventMutationResult, AppError> {
        let state = self.state.clone();
        runtime()
            .spawn(async move {
                core::acknowledge(
                    &state,
                    core::AcknowledgeRequest {
                        id: request.id,
                        confirmation: match request.confirmation {
                            EventConfirmation::Button => edits::Confirmation::Button,
                        },
                    },
                )
                .await
                .map(Into::into)
                .map_err(failure)
            })
            .await
            .map_err(storage)?
    }
    pub async fn event_history(&self) -> Result<Vec<EventHistoryRecord>, AppError> {
        let state = self.state.clone();
        runtime()
            .spawn_blocking(move || {
                core::history(&state)
                    .map(|rows| rows.into_iter().map(Into::into).collect())
                    .map_err(failure)
            })
            .await
            .map_err(storage)?
    }
    pub async fn event_history_detail(
        &self,
        id: String,
    ) -> Result<Option<EventHistoryRecord>, AppError> {
        let state = self.state.clone();
        runtime()
            .spawn_blocking(move || {
                core::event_detail(&state, &id)
                    .map(|item| item.map(Into::into))
                    .map_err(failure)
            })
            .await
            .map_err(storage)?
    }
}
