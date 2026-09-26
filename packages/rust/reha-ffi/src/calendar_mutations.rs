//! Typed editing boundary; only opaque EventKit metadata keeps JSON.
use crate::{AppError, CalendarReadEvent, CalendarReadValues};
use reha_core::service::calendar_mutations as core;

type Result<T> = std::result::Result<T, AppError>;
#[derive(Clone, Copy, Debug, uniffi::Enum)]
pub enum EventMutationKind {
    Create,
    Update,
    Remove,
}
#[derive(Clone, Debug, uniffi::Enum)]
pub enum EventReminderChange {
    Unchanged,
    Disabled,
    Minutes { minutes: u32 },
}
#[derive(Clone, Copy, Debug, uniffi::Enum)]
pub enum EventConfirmation {
    Button,
}
#[derive(Clone, Copy, Debug, uniffi::Enum)]
pub enum EventMutationStatus {
    Saved,
    Failed,
    Uncertain,
    Conflict,
    Acknowledged,
}
#[derive(Clone, Debug, uniffi::Record)]
pub struct EventEditPatch {
    pub title: Option<String>,
    pub start_utc: Option<String>,
    pub end_utc: Option<String>,
    pub timezone: Option<String>,
    pub location: Option<String>,
    pub reminder: EventReminderChange,
}
#[derive(Clone, Debug, uniffi::Record)]
pub struct EventPreviewRequest {
    pub session: String,
    pub revision: u64,
    pub kind: EventMutationKind,
    pub calendar_id: String,
    pub event: Option<CalendarReadEvent>,
    pub patch: EventEditPatch,
    pub origin: String,
}
#[derive(Clone, Debug, uniffi::Record)]
pub struct EventConfirmRequest {
    pub token: String,
    pub session: String,
    pub revision: u64,
    pub confirmation: EventConfirmation,
}
#[derive(Clone, Debug, uniffi::Record)]
pub struct EventUndoRequest {
    pub id: String,
    pub session: String,
    pub revision: u64,
}
#[derive(Clone, Debug, uniffi::Record)]
pub struct EventEditProposal {
    pub token: String,
    pub session: String,
    pub revision: u64,
    pub expires_at: i64,
    pub kind: EventMutationKind,
    pub calendar_id: String,
    pub calendar_title: String,
    pub before: Option<CalendarReadEvent>,
    pub patch: EventEditPatch,
    pub undo_of: Option<String>,
    pub owned_id: Option<String>,
    pub origin: String,
}
// The exported sum type carries named value records; Core boxes its internal
// variants. Keeping these as records makes both alternatives explicit in Swift.
#[allow(clippy::large_enum_variant)]
#[derive(Clone, Debug, uniffi::Enum)]
pub enum EventPreviewResult {
    Proposal { proposal: EventEditProposal },
    SystemEditor { event: CalendarReadEvent },
}
#[derive(Clone, Debug, uniffi::Record)]
pub struct EventMutationResult {
    pub status: EventMutationStatus,
    pub event: Option<CalendarReadEvent>,
    pub operation_id: Option<String>,
    pub message: Option<String>,
    pub maintenance_warnings: Vec<String>,
}
#[derive(Clone, Debug, uniffi::Record)]
pub struct EventMutationRequest {
    pub proposal: EventEditProposal,
    pub recovery_only: bool,
}
#[derive(Clone, Debug, uniffi::Record)]
pub struct EventCalendarDestination {
    pub id: String,
    pub title: String,
    pub source: String,
    pub writable: bool,
    pub color_components: Option<Vec<f64>>,
}

impl From<core::Kind> for EventMutationKind {
    fn from(v: core::Kind) -> Self {
        match v {
            core::Kind::Create => Self::Create,
            core::Kind::Update => Self::Update,
            core::Kind::Remove => Self::Remove,
        }
    }
}
impl From<EventMutationKind> for core::Kind {
    fn from(v: EventMutationKind) -> Self {
        match v {
            EventMutationKind::Create => Self::Create,
            EventMutationKind::Update => Self::Update,
            EventMutationKind::Remove => Self::Remove,
        }
    }
}
impl From<core::ReminderChange> for EventReminderChange {
    fn from(v: core::ReminderChange) -> Self {
        match v {
            core::ReminderChange::Unchanged => Self::Unchanged,
            core::ReminderChange::Disabled => Self::Disabled,
            core::ReminderChange::Minutes(minutes) => Self::Minutes { minutes },
        }
    }
}
impl From<EventReminderChange> for core::ReminderChange {
    fn from(v: EventReminderChange) -> Self {
        match v {
            EventReminderChange::Unchanged => Self::Unchanged,
            EventReminderChange::Disabled => Self::Disabled,
            EventReminderChange::Minutes { minutes } => Self::Minutes(minutes),
        }
    }
}
impl From<core::Patch> for EventEditPatch {
    fn from(p: core::Patch) -> Self {
        Self {
            title: p.title,
            start_utc: p.start_utc,
            end_utc: p.end_utc,
            timezone: p.timezone,
            location: p.location,
            reminder: p.reminder_minutes.into(),
        }
    }
}
impl From<EventEditPatch> for core::Patch {
    fn from(p: EventEditPatch) -> Self {
        Self {
            title: p.title,
            start_utc: p.start_utc,
            end_utc: p.end_utc,
            timezone: p.timezone,
            location: p.location,
            reminder_minutes: p.reminder.into(),
        }
    }
}
impl From<reha_core::service::calendar_reads::Event> for CalendarReadEvent {
    fn from(e: reha_core::service::calendar_reads::Event) -> Self {
        Self {
            id: e.id,
            external_id: e.external_id,
            calendar_id: e.calendar_id,
            calendar_title: e.calendar_title,
            source: e.source,
            occurrence: e.occurrence,
            recurring: e.recurring,
            system_only: e.system_only,
            writable: e.writable,
            values: CalendarReadValues {
                title: e.values.title,
                start_utc: e.values.start_utc,
                end_utc: e.values.end_utc,
                timezone: e.values.timezone,
                location: e.values.location,
                reminder_minutes: e.values.reminder_minutes,
            },
            metadata_json: e.metadata.to_string(),
            fingerprint: e.fingerprint,
            import_id: e.import_id,
        }
    }
}
impl From<core::Proposal> for EventEditProposal {
    fn from(p: core::Proposal) -> Self {
        Self {
            token: p.token,
            session: p.session,
            revision: p.revision,
            expires_at: p.expires_at,
            kind: p.kind.into(),
            calendar_id: p.calendar_id,
            calendar_title: p.calendar_title,
            before: p.before.map(Into::into),
            patch: p.patch.into(),
            undo_of: p.undo_of,
            owned_id: p.owned_id,
            origin: p.origin,
        }
    }
}
impl TryFrom<EventEditProposal> for core::Proposal {
    type Error = AppError;
    fn try_from(p: EventEditProposal) -> Result<Self> {
        Ok(Self {
            token: p.token,
            session: p.session,
            revision: p.revision,
            expires_at: p.expires_at,
            kind: p.kind.into(),
            calendar_id: p.calendar_id,
            calendar_title: p.calendar_title,
            before: p.before.map(TryInto::try_into).transpose()?,
            patch: p.patch.into(),
            undo_of: p.undo_of,
            owned_id: p.owned_id,
            origin: p.origin,
        })
    }
}
impl TryFrom<EventPreviewRequest> for core::PreviewRequest {
    type Error = AppError;
    fn try_from(p: EventPreviewRequest) -> Result<Self> {
        Ok(Self {
            session: p.session,
            revision: p.revision,
            kind: p.kind.into(),
            calendar_id: p.calendar_id,
            event: p.event.map(TryInto::try_into).transpose()?,
            patch: p.patch.into(),
            origin: p.origin,
        })
    }
}
impl From<core::PreviewResult> for EventPreviewResult {
    fn from(p: core::PreviewResult) -> Self {
        match p {
            core::PreviewResult::Proposal { proposal } => Self::Proposal {
                proposal: (*proposal).into(),
            },
            core::PreviewResult::SystemEditor { system_editor } => Self::SystemEditor {
                event: (*system_editor).into(),
            },
        }
    }
}
impl From<core::MutationRequest> for EventMutationRequest {
    fn from(r: core::MutationRequest) -> Self {
        Self {
            proposal: r.proposal.into(),
            recovery_only: r.recovery_only,
        }
    }
}
impl From<core::MutationResult> for EventMutationResult {
    fn from(r: core::MutationResult) -> Self {
        Self {
            status: match r.status {
                core::Status::Saved => EventMutationStatus::Saved,
                core::Status::Failed => EventMutationStatus::Failed,
                core::Status::Uncertain => EventMutationStatus::Uncertain,
                core::Status::Conflict => EventMutationStatus::Conflict,
                core::Status::Acknowledged => EventMutationStatus::Acknowledged,
            },
            event: r.event.map(Into::into),
            operation_id: r.operation_id,
            message: r.message,
            maintenance_warnings: r.maintenance_warnings,
        }
    }
}
impl TryFrom<EventMutationResult> for core::MutationResult {
    type Error = AppError;
    fn try_from(r: EventMutationResult) -> Result<Self> {
        Ok(Self {
            status: match r.status {
                EventMutationStatus::Saved => core::Status::Saved,
                EventMutationStatus::Failed => core::Status::Failed,
                EventMutationStatus::Uncertain => core::Status::Uncertain,
                EventMutationStatus::Conflict => core::Status::Conflict,
                EventMutationStatus::Acknowledged => core::Status::Acknowledged,
            },
            event: r.event.map(TryInto::try_into).transpose()?,
            operation_id: r.operation_id,
            message: r.message,
            maintenance_warnings: r.maintenance_warnings,
        })
    }
}
impl From<core::Destination> for EventCalendarDestination {
    fn from(c: core::Destination) -> Self {
        Self {
            id: c.id,
            title: c.title,
            source: c.source,
            writable: c.writable,
            color_components: c.color_components,
        }
    }
}
impl From<EventCalendarDestination> for core::Destination {
    fn from(c: EventCalendarDestination) -> Self {
        Self {
            id: c.id,
            title: c.title,
            source: c.source,
            writable: c.writable,
            color_components: c.color_components,
        }
    }
}

use crate::{
    application::{failure, NativeApplication},
    runtime,
};
#[uniffi::export]
impl NativeApplication {
    pub fn register_event_session(&self) -> Result<String> {
        core::register(&self.state).map_err(failure)
    }
    pub fn invalidate_event_session(&self, session: String) -> Result<()> {
        core::invalidate(&self.state, &session).map_err(failure)
    }
    pub async fn event_calendars(&self) -> Result<Vec<EventCalendarDestination>> {
        let host = self.bridge.clone();
        runtime()
            .spawn(async move {
                core::destinations(host)
                    .await
                    .map(|v| v.into_iter().map(Into::into).collect())
                    .map_err(failure)
            })
            .await
            .map_err(crate::application::storage)?
    }
    pub async fn preview_event_mutation(
        &self,
        request: EventPreviewRequest,
    ) -> Result<EventPreviewResult> {
        let request = request.try_into()?;
        let state = self.state.clone();
        let host = self.bridge.clone();
        runtime()
            .spawn(async move {
                core::preview(host, &state, request)
                    .await
                    .map(Into::into)
                    .map_err(failure)
            })
            .await
            .map_err(crate::application::storage)?
    }
    pub async fn confirm_event_proposal(
        &self,
        request: EventConfirmRequest,
    ) -> Result<EventMutationResult> {
        let request = core::ConfirmRequest {
            token: request.token,
            session: request.session,
            revision: request.revision,
            confirmation: match request.confirmation {
                EventConfirmation::Button => core::Confirmation::Button,
            },
        };
        let state = self.state.clone();
        let host = self.bridge.clone();
        runtime()
            .spawn(async move {
                core::confirm(host, &state, request)
                    .await
                    .map(Into::into)
                    .map_err(failure)
            })
            .await
            .map_err(crate::application::storage)?
    }
    pub async fn preview_event_undo(
        &self,
        request: EventUndoRequest,
    ) -> Result<EventPreviewResult> {
        let request = core::UndoRequest {
            id: request.id,
            session: request.session,
            revision: request.revision,
        };
        let state = self.state.clone();
        let host = self.bridge.clone();
        runtime()
            .spawn(async move {
                core::undo(host, &state, request)
                    .await
                    .map(Into::into)
                    .map_err(failure)
            })
            .await
            .map_err(crate::application::storage)?
    }
}
