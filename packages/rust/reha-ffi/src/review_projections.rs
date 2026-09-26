//! Review records cross the native boundary directly. Only domain field values
//! remain JSON scalars, with the existing numeric and optional-value semantics.
use crate::{
    application::storage, AppError, Appointment, ApprovalSnapshot, CompletionSuggestion, Document,
    FieldAssessment, FieldOrigin, FieldValue, Issue, Metadata, Point, PrintedState, Stage,
};
use reha_core::contracts as domain;
use serde_json::Value;

type Result<T> = std::result::Result<T, AppError>;

impl TryFrom<Value> for FieldValue {
    type Error = AppError;

    fn try_from(value: Value) -> Result<Self> {
        match value {
            Value::Null => Ok(Self::Empty),
            Value::String(value) => Ok(Self::Text { value }),
            Value::Number(value) if value.is_i64() => Ok(Self::Integer {
                value: value.as_i64().expect("checked signed integer"),
            }),
            Value::Number(value) if value.is_u64() => Ok(Self::Unsigned {
                value: value.as_u64().expect("checked unsigned integer"),
            }),
            Value::Number(value) => value
                .as_f64()
                .filter(|value| value.is_finite())
                .map(|value| Self::Number { value })
                .ok_or_else(|| storage("Invalid field number")),
            Value::Bool(value) => Ok(Self::Boolean { value }),
            Value::Array(_) | Value::Object(_) => Err(storage("Field values must be scalar")),
        }
    }
}

impl From<FieldValue> for Value {
    fn from(value: FieldValue) -> Self {
        match value {
            FieldValue::Empty => Self::Null,
            FieldValue::Text { value } => Self::String(value),
            FieldValue::Integer { value } => Self::Number(value.into()),
            FieldValue::Unsigned { value } => Self::Number(value.into()),
            // serde_json represented non-finite native field numbers as null.
            FieldValue::Number { value } => serde_json::Number::from_f64(value)
                .map(Self::Number)
                .unwrap_or(Self::Null),
            FieldValue::Boolean { value } => Self::Bool(value),
        }
    }
}

impl From<domain::PrintedState> for PrintedState {
    fn from(value: domain::PrintedState) -> Self {
        match value {
            domain::PrintedState::Unreviewed => Self::Unreviewed,
            domain::PrintedState::Legible => Self::Legible,
            domain::PrintedState::NotPrinted => Self::NotPrinted,
            domain::PrintedState::Illegible => Self::Illegible,
            domain::PrintedState::Cropped => Self::Cropped,
            domain::PrintedState::Contradictory => Self::Contradictory,
        }
    }
}

impl From<PrintedState> for domain::PrintedState {
    fn from(value: PrintedState) -> Self {
        match value {
            PrintedState::Unreviewed => Self::Unreviewed,
            PrintedState::Legible => Self::Legible,
            PrintedState::NotPrinted => Self::NotPrinted,
            PrintedState::Illegible => Self::Illegible,
            PrintedState::Cropped => Self::Cropped,
            PrintedState::Contradictory => Self::Contradictory,
        }
    }
}

fn finite_point(x: f64, y: f64) -> Result<()> {
    if x.is_finite() && y.is_finite() {
        Ok(())
    } else {
        Err(storage("Nicht endliche Seitenkoordinate."))
    }
}

impl TryFrom<domain::Point> for Point {
    type Error = AppError;

    fn try_from(value: domain::Point) -> Result<Self> {
        finite_point(value.x, value.y)?;
        Ok(Self {
            x: value.x,
            y: value.y,
        })
    }
}

impl TryFrom<Point> for domain::Point {
    type Error = AppError;

    fn try_from(value: Point) -> Result<Self> {
        finite_point(value.x, value.y)?;
        Ok(Self {
            x: value.x,
            y: value.y,
        })
    }
}

impl TryFrom<domain::FieldAssessment> for FieldAssessment {
    type Error = AppError;

    fn try_from(value: domain::FieldAssessment) -> Result<Self> {
        Ok(Self {
            state: value.state.into(),
            polygon: value
                .polygon
                .into_iter()
                .map(TryInto::try_into)
                .collect::<Result<_>>()?,
            frame: value.frame,
            reasons: value.reasons,
            // Option<T>'s JSON decoder folded Some(null) into None.
            confirmed_value: value
                .confirmed_value
                .filter(|value| !value.is_null())
                .map(TryInto::try_into)
                .transpose()?,
            confirmed_at: value.confirmed_at,
        })
    }
}

impl TryFrom<FieldAssessment> for domain::FieldAssessment {
    type Error = AppError;

    fn try_from(value: FieldAssessment) -> Result<Self> {
        Ok(Self {
            state: value.state.into(),
            polygon: value
                .polygon
                .into_iter()
                .map(TryInto::try_into)
                .collect::<Result<_>>()?,
            frame: value.frame,
            reasons: value.reasons,
            confirmed_value: value
                .confirmed_value
                .map(Value::from)
                .filter(|value| !value.is_null()),
            confirmed_at: value.confirmed_at,
        })
    }
}

impl From<Issue> for domain::Issue {
    fn from(value: Issue) -> Self {
        Self {
            code: value.code,
            message: value.message,
            field: value.field,
            blocking: value.blocking,
        }
    }
}

impl From<domain::Metadata> for Metadata {
    fn from(value: domain::Metadata) -> Self {
        Self {
            clinic: value.clinic,
            department: value.department,
            address: value.address,
            contact: value.contact,
            treatment_code: value.treatment_code,
            preparation: value.preparation,
            document_reference: value.document_reference,
            appointment_notes: value.appointment_notes,
        }
    }
}

impl From<Metadata> for domain::Metadata {
    fn from(value: Metadata) -> Self {
        Self {
            clinic: value.clinic,
            department: value.department,
            address: value.address,
            contact: value.contact,
            treatment_code: value.treatment_code,
            preparation: value.preparation,
            document_reference: value.document_reference,
            appointment_notes: value.appointment_notes,
        }
    }
}

impl From<domain::FieldOrigin> for FieldOrigin {
    fn from(value: domain::FieldOrigin) -> Self {
        Self {
            kind: value.kind,
            evidence: value.evidence,
            source: value.source,
        }
    }
}

impl From<FieldOrigin> for domain::FieldOrigin {
    fn from(value: FieldOrigin) -> Self {
        Self {
            kind: value.kind,
            evidence: value.evidence,
            source: value.source,
        }
    }
}

impl TryFrom<domain::CompletionSuggestion> for CompletionSuggestion {
    type Error = AppError;

    fn try_from(value: domain::CompletionSuggestion) -> Result<Self> {
        Ok(Self {
            id: value.id,
            field: value.field,
            value: value.value.try_into()?,
            source: value.source,
            status: value.status,
        })
    }
}

impl From<CompletionSuggestion> for domain::CompletionSuggestion {
    fn from(value: CompletionSuggestion) -> Self {
        Self {
            id: value.id,
            field: value.field,
            value: value.value.into(),
            source: value.source,
            status: value.status,
        }
    }
}

impl From<domain::ApprovalSnapshot> for ApprovalSnapshot {
    fn from(value: domain::ApprovalSnapshot) -> Self {
        Self {
            values_hash: value.values_hash,
            approved_at: value.approved_at,
        }
    }
}

impl From<ApprovalSnapshot> for domain::ApprovalSnapshot {
    fn from(value: ApprovalSnapshot) -> Self {
        Self {
            values_hash: value.values_hash,
            approved_at: value.approved_at,
        }
    }
}

impl TryFrom<domain::Appointment> for Appointment {
    type Error = AppError;

    fn try_from(value: domain::Appointment) -> Result<Self> {
        Ok(Self {
            id: value.id,
            fields: value
                .fields
                .into_iter()
                .map(|(key, field)| Ok((key, field.try_into()?)))
                .collect::<Result<_>>()?,
            row_polygon: value
                .row_polygon
                .into_iter()
                .map(TryInto::try_into)
                .collect::<Result<_>>()?,
            section_id: value.section_id,
            metadata: value.metadata.into(),
            origins: value
                .origins
                .into_iter()
                .map(|(key, origin)| (key, origin.into()))
                .collect(),
            suggestions: value
                .suggestions
                .into_iter()
                .map(TryInto::try_into)
                .collect::<Result<_>>()?,
            approval: value.approval.map(Into::into),
            calendar_event_id: value.calendar_event_id,
            ics_event_id: value.ics_event_id,
            calendar_saved_hash: value.calendar_saved_hash,
            ics_exported_hash: value.ics_exported_hash,
            date: value.date,
            start: value.start,
            end: value.end,
            end_date: value.end_date,
            duration_minutes: value.duration_minutes,
            title: value.title,
            location: value.location,
            therapist: value.therapist,
            notes: value.notes,
            included: value.included,
            provenance: value.provenance.into_iter().collect(),
            issues: value.issues.into_iter().map(Into::into).collect(),
        })
    }
}

impl TryFrom<Appointment> for domain::Appointment {
    type Error = AppError;

    fn try_from(value: Appointment) -> Result<Self> {
        Ok(Self {
            id: value.id,
            fields: value
                .fields
                .into_iter()
                .map(|(key, field)| Ok((key, field.try_into()?)))
                .collect::<Result<_>>()?,
            row_polygon: value
                .row_polygon
                .into_iter()
                .map(TryInto::try_into)
                .collect::<Result<_>>()?,
            section_id: value.section_id,
            metadata: value.metadata.into(),
            origins: value
                .origins
                .into_iter()
                .map(|(key, origin)| (key, origin.into()))
                .collect(),
            suggestions: value.suggestions.into_iter().map(Into::into).collect(),
            approval: value.approval.map(Into::into),
            calendar_event_id: value.calendar_event_id,
            ics_event_id: value.ics_event_id,
            calendar_saved_hash: value.calendar_saved_hash,
            ics_exported_hash: value.ics_exported_hash,
            date: value.date,
            start: value.start,
            end: value.end,
            end_date: value.end_date,
            duration_minutes: value.duration_minutes,
            title: value.title,
            location: value.location,
            therapist: value.therapist,
            notes: value.notes,
            included: value.included,
            provenance: value.provenance.into_iter().collect(),
            issues: value.issues.into_iter().map(Into::into).collect(),
        })
    }
}

impl From<domain::Document> for Document {
    fn from(value: domain::Document) -> Self {
        Self {
            schema_version: value.schema_version,
            id: value.id,
            source_hash: value.source_hash,
            filename: value.filename,
            width: value.width,
            height: value.height,
            orientation: value.orientation,
            imported_at: value.imported_at,
            source: value.source,
        }
    }
}

impl From<domain::Stage> for Stage {
    fn from(value: domain::Stage) -> Self {
        Self {
            name: value.name,
            status: value.status,
            duration_ms: value.duration_ms,
            detail: value.detail,
            artifacts: value.artifacts,
        }
    }
}

#[cfg(test)]
#[path = "review_projections_tests.rs"]
mod tests;
