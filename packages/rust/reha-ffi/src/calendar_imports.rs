//! Field-preserving native import projections; no intermediate JSON payloads.
use crate::{records::*, AppError, CalendarOverlap};
use reha_core::contracts as domain;

impl From<domain::EventValues> for EventValues {
    fn from(value: domain::EventValues) -> Self {
        Self {
            title: value.title,
            start_utc: value.start_utc,
            end_utc: value.end_utc,
            timezone: value.timezone,
            location: value.location,
            notes: value.notes,
            reminder_minutes: value.reminder_minutes,
        }
    }
}
impl From<EventValues> for domain::EventValues {
    fn from(value: EventValues) -> Self {
        Self {
            title: value.title,
            start_utc: value.start_utc,
            end_utc: value.end_utc,
            timezone: value.timezone,
            location: value.location,
            notes: value.notes,
            reminder_minutes: value.reminder_minutes,
        }
    }
}
impl From<CalendarOverlap> for domain::CalendarOverlap {
    fn from(value: CalendarOverlap) -> Self {
        Self {
            appointment_id: value.appointment_id,
            external_id: value.external_id,
            title: value.title,
            start_utc: value.start_utc,
            end_utc: value.end_utc,
        }
    }
}
impl From<domain::ImportRecord> for ImportRecord {
    fn from(value: domain::ImportRecord) -> Self {
        Self {
            id: value.id,
            schedule_id: value.schedule_id,
            calendar_id: value.calendar_id,
            external_id: value.external_id,
            approved: value.approved.into(),
            status: value.status,
            operation_id: value.operation_id,
        }
    }
}
impl TryFrom<domain::CalendarOperation> for CalendarOperation {
    type Error = AppError;
    fn try_from(value: domain::CalendarOperation) -> Result<Self, Self::Error> {
        let kind = match value.kind.as_str() {
            "create" => OperationKind::Create,
            "update" => OperationKind::Update,
            "remove" => OperationKind::Remove,
            "unchanged" => OperationKind::Unchanged,
            "keep" => OperationKind::Keep,
            "protected" => OperationKind::Protected,
            "ambiguous" => OperationKind::Ambiguous,
            "conflict" => OperationKind::Conflict,
            _ => {
                return Err(AppError::Storage {
                    message: "Unbekannte Kalenderoperation.".into(),
                })
            }
        };
        Ok(Self {
            kind,
            id: value.id,
            calendar_id: value.calendar_id,
            external_id: value.external_id,
            before: value.before.map(Into::into),
            after: value.after.map(Into::into),
            requires_resolution: value.requires_resolution,
            reason: value.reason,
        })
    }
}
impl From<CalendarResult> for domain::CalendarResult {
    fn from(value: CalendarResult) -> Self {
        Self {
            id: value.id,
            status: match value.status {
                WriteStatus::Saved => "saved",
                WriteStatus::Failed => "failed",
                WriteStatus::Uncertain => "uncertain",
                WriteStatus::Conflict => "conflict",
            }
            .into(),
            external_id: value.external_id,
            error: value.error,
            maintenance_warnings: value.maintenance_warnings,
        }
    }
}
