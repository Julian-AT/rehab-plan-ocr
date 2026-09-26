//! Read-only callback DTOs. Metadata bytes retain the established journal format.
use crate::{AppError, EventValues};
use reha_core::service::calendar_reads as core;

#[derive(Clone, Debug, uniffi::Record)]
pub struct CalendarReadQuery {
    pub calendar_ids: Vec<String>,
    pub start_utc: String,
    pub end_utc: String,
    pub timezone: String,
    pub selection_revision: u64,
    pub records: Vec<CalendarReadOwnedRecord>,
}
#[derive(Clone, Debug, uniffi::Record)]
pub struct CalendarReadOwnedRecord {
    pub id: String,
    pub calendar_id: String,
    pub external_id: Option<String>,
    pub approved: EventValues,
    pub status: String,
}
#[derive(Clone, Debug, uniffi::Record)]
pub struct CalendarReadReference {
    pub calendar_id: String,
    pub external_id: String,
    pub occurrence: String,
    pub expected_start_utc: String,
}
#[derive(Clone, Debug, uniffi::Record)]
pub struct CalendarReadValues {
    pub title: String,
    pub start_utc: String,
    pub end_utc: String,
    pub timezone: String,
    pub location: String,
    pub reminder_minutes: Option<i64>,
}
#[derive(Clone, Debug, uniffi::Record)]
pub struct CalendarReadEvent {
    pub id: String,
    pub external_id: String,
    pub calendar_id: String,
    pub calendar_title: String,
    pub source: String,
    pub occurrence: String,
    pub recurring: bool,
    pub system_only: bool,
    pub writable: bool,
    pub values: CalendarReadValues,
    pub metadata_json: String,
    pub fingerprint: String,
    pub import_id: Option<String>,
}
#[derive(Clone, Debug, uniffi::Record)]
pub struct CalendarReadUnavailableEvent {
    pub id: String,
    pub start_utc: String,
    pub end_utc: String,
}
#[derive(Clone, Debug, uniffi::Record)]
pub struct CalendarReadResult {
    pub events: Vec<CalendarReadEvent>,
    pub unavailable_calendar_ids: Vec<String>,
    pub unavailable_events: Vec<CalendarReadUnavailableEvent>,
}
impl From<core::Query> for CalendarReadQuery {
    fn from(q: core::Query) -> Self {
        Self {
            calendar_ids: q.calendar_ids,
            start_utc: q.start_utc,
            end_utc: q.end_utc,
            timezone: q.timezone,
            selection_revision: q.selection_revision,
            records: q
                .records
                .into_iter()
                .map(|r| CalendarReadOwnedRecord {
                    id: r.id,
                    calendar_id: r.calendar_id,
                    external_id: r.external_id,
                    approved: EventValues {
                        title: r.approved.title,
                        start_utc: r.approved.start_utc,
                        end_utc: r.approved.end_utc,
                        timezone: r.approved.timezone,
                        location: r.approved.location,
                        notes: r.approved.notes,
                        reminder_minutes: r.approved.reminder_minutes,
                    },
                    status: r.status,
                })
                .collect(),
        }
    }
}
impl From<core::Reference> for CalendarReadReference {
    fn from(r: core::Reference) -> Self {
        Self {
            calendar_id: r.calendar_id,
            external_id: r.external_id,
            occurrence: r.occurrence,
            expected_start_utc: r.expected_start_utc,
        }
    }
}
impl TryFrom<CalendarReadEvent> for core::Event {
    type Error = AppError;
    fn try_from(e: CalendarReadEvent) -> Result<Self, Self::Error> {
        let metadata = serde_json::from_str(&e.metadata_json).map_err(|_| AppError::Storage {
            message: "Kalender-Metadaten ungültig.".into(),
        })?;
        Ok(Self {
            id: e.id,
            external_id: e.external_id,
            calendar_id: e.calendar_id,
            calendar_title: e.calendar_title,
            source: e.source,
            occurrence: e.occurrence,
            recurring: e.recurring,
            system_only: e.system_only,
            writable: e.writable,
            values: core::Values {
                title: e.values.title,
                start_utc: e.values.start_utc,
                end_utc: e.values.end_utc,
                timezone: e.values.timezone,
                location: e.values.location,
                reminder_minutes: e.values.reminder_minutes,
            },
            metadata,
            fingerprint: e.fingerprint,
            import_id: e.import_id,
        })
    }
}
impl TryFrom<CalendarReadResult> for core::QueryResult {
    type Error = AppError;
    fn try_from(r: CalendarReadResult) -> Result<Self, Self::Error> {
        Ok(Self {
            events: r
                .events
                .into_iter()
                .map(TryInto::try_into)
                .collect::<Result<_, _>>()?,
            unavailable_calendar_ids: r.unavailable_calendar_ids,
            unavailable_events: r
                .unavailable_events
                .into_iter()
                .map(|e| core::UnavailableEvent {
                    id: e.id,
                    start_utc: e.start_utc,
                    end_utc: e.end_utc,
                })
                .collect(),
        })
    }
}
