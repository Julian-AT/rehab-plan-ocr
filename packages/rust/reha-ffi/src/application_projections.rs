//! Native history and calendar projections without intermediate JSON payloads.
use crate::{
    application::storage, AppError, AppointmentAssessment, BatchOperation, CalendarOverlap,
    CalendarResult, DraftAssessment, DraftPreview, ImportBatch, IntakeSummary, Issue, Plan, Point,
    Proposal, Readiness, ReadinessQuestion, SaveOutcome, ScanSummary, WriteStatus,
};
use reha_core::{contracts as domain, readiness, service, store};

type Result<T> = std::result::Result<T, AppError>;

impl TryFrom<store::ScanSummary> for ScanSummary {
    type Error = AppError;

    fn try_from(value: store::ScanSummary) -> Result<Self> {
        Ok(Self {
            id: value.id,
            imported_at: value.imported_at,
            retained: value.retained,
            item_count: value.item_count.try_into().map_err(storage)?,
            pending_count: value.pending_count.try_into().map_err(storage)?,
            dates: value.dates,
            schedule_id: value.schedule_id,
        })
    }
}

impl From<store::Intake> for IntakeSummary {
    fn from(value: store::Intake) -> Self {
        Self {
            id: value.id,
            filename: value.filename,
            imported_at: value.imported_at,
            status: value.status,
            error: value.error,
        }
    }
}

impl From<store::Plan> for Plan {
    fn from(value: store::Plan) -> Self {
        Self {
            id: value.id,
            imported_at: value.imported_at,
            page_ids: value.page_ids,
        }
    }
}

impl TryFrom<domain::CalendarResult> for CalendarResult {
    type Error = AppError;

    fn try_from(value: domain::CalendarResult) -> Result<Self> {
        let status = match value.status.as_str() {
            "saved" => WriteStatus::Saved,
            "failed" => WriteStatus::Failed,
            "uncertain" => WriteStatus::Uncertain,
            "conflict" => WriteStatus::Conflict,
            _ => return Err(storage("Unbekanntes Kalenderergebnis.")),
        };
        Ok(Self {
            id: value.id,
            status,
            external_id: value.external_id,
            error: value.error,
            maintenance_warnings: value.maintenance_warnings,
        })
    }
}

impl TryFrom<store::BatchOperation> for BatchOperation {
    type Error = AppError;

    fn try_from(value: store::BatchOperation) -> Result<Self> {
        Ok(Self {
            attempt_id: value.attempt_id,
            operation: value.operation.try_into()?,
            status: value.status,
            result: value.result.map(TryInto::try_into).transpose()?,
        })
    }
}

impl TryFrom<store::ImportBatch> for ImportBatch {
    type Error = AppError;

    fn try_from(value: store::ImportBatch) -> Result<Self> {
        Ok(Self {
            id: value.id,
            document_ids: value.document_ids,
            schedule_id: value.schedule_id,
            created_at: value.created_at,
            undo_of: value.undo_of,
            undone_by: value.undone_by,
            operations: value
                .operations
                .into_iter()
                .map(TryInto::try_into)
                .collect::<Result<_>>()?,
        })
    }
}

impl From<domain::CalendarOverlap> for CalendarOverlap {
    fn from(value: domain::CalendarOverlap) -> Self {
        Self {
            appointment_id: value.appointment_id,
            external_id: value.external_id,
            title: value.title,
            start_utc: value.start_utc,
            end_utc: value.end_utc,
        }
    }
}

impl TryFrom<service::Proposal> for Proposal {
    type Error = AppError;

    fn try_from(value: service::Proposal) -> Result<Self> {
        // The remaining service fields are private acceptance/recovery state,
        // which is also deliberately absent from the public UniFFI record.
        Ok(Self {
            bindings: value.bindings.into_iter().collect(),
            token: value.token,
            document_id: value.document_id,
            operations: value
                .operations
                .into_iter()
                .map(TryInto::try_into)
                .collect::<Result<_>>()?,
            overlaps: value
                .overlaps
                .map(|overlaps| overlaps.into_iter().map(Into::into).collect()),
        })
    }
}

impl From<domain::Issue> for Issue {
    fn from(value: domain::Issue) -> Self {
        Self {
            code: value.code,
            message: value.message,
            field: value.field,
            blocking: value.blocking,
        }
    }
}

impl From<readiness::Readiness> for Readiness {
    fn from(value: readiness::Readiness) -> Self {
        match value {
            readiness::Readiness::Ready => Self::Ready,
            readiness::Readiness::Attention => Self::Attention,
            readiness::Readiness::Excluded => Self::Excluded,
        }
    }
}

impl From<readiness::AppointmentAssessment> for AppointmentAssessment {
    fn from(value: readiness::AppointmentAssessment) -> Self {
        Self {
            id: value.id,
            document_id: value.document_id,
            state: value.state.into(),
            issues: value.issues.into_iter().map(Into::into).collect(),
            warnings: value.warnings.into_iter().map(Into::into).collect(),
        }
    }
}

impl TryFrom<readiness::ReadinessQuestion> for ReadinessQuestion {
    type Error = AppError;

    fn try_from(value: readiness::ReadinessQuestion) -> Result<Self> {
        let polygon = value
            .polygon
            .into_iter()
            .map(|point| {
                // The previous JSON decoder rejected non-finite coordinates.
                // A direct projection must not admit them into the UI either.
                if !point.x.is_finite() || !point.y.is_finite() {
                    return Err(storage("Nicht endliche Seitenkoordinate."));
                }
                Ok(Point {
                    x: point.x,
                    y: point.y,
                })
            })
            .collect::<Result<_>>()?;
        Ok(Self {
            id: value.id,
            document_id: value.document_id,
            appointment_ids: value.appointment_ids,
            field: value.field,
            message: value.message,
            polygon,
        })
    }
}

impl TryFrom<readiness::DraftAssessment> for DraftAssessment {
    type Error = AppError;

    fn try_from(value: readiness::DraftAssessment) -> Result<Self> {
        Ok(Self {
            revision: value.revision,
            policy_version: value.policy_version,
            appointments: value.appointments.into_iter().map(Into::into).collect(),
            questions: value
                .questions
                .into_iter()
                .map(TryInto::try_into)
                .collect::<Result<_>>()?,
            ready_ids: value.ready_ids,
            unprocessed_page_ids: value.unprocessed_page_ids,
        })
    }
}

impl TryFrom<service::draft::DraftPreview> for DraftPreview {
    type Error = AppError;

    fn try_from(value: service::draft::DraftPreview) -> Result<Self> {
        Ok(Self {
            assessment: value.assessment.try_into()?,
            proposal: value.proposal.map(TryInto::try_into).transpose()?,
        })
    }
}

impl TryFrom<service::draft::SaveOutcome> for SaveOutcome {
    type Error = AppError;

    fn try_from(value: service::draft::SaveOutcome) -> Result<Self> {
        Ok(Self {
            batch_id: value.batch_id,
            results: value
                .results
                .into_iter()
                .map(TryInto::try_into)
                .collect::<Result<_>>()?,
            existing_ids: value.existing_ids,
            remaining_ids: value.remaining_ids,
        })
    }
}

#[cfg(test)]
#[path = "application_projections_tests.rs"]
mod tests;
