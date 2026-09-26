//! Typed, validated output from a local interpretation model; no calendar writes.

use crate::AppError;
use reha_core::conversation as core;

#[derive(Clone, Debug, PartialEq, uniffi::Enum)]
pub enum AssistantRequest {
    Calendar {
        query: AssistantQuery,
    },
    Create {
        change: AssistantChange,
    },
    Update {
        reference: String,
        change: AssistantChange,
    },
    Remove {
        reference: String,
    },
    Cancel,
    Help {
        topic: AssistantHelpTopic,
    },
    Clarify {
        problem: AssistantProblem,
    },
}

#[derive(Clone, Debug, PartialEq, uniffi::Record)]
pub struct AssistantQuery {
    pub detail: AssistantDetail,
    pub date: Option<String>,
    pub reference: Option<String>,
    pub after_minutes: Option<u16>,
    pub before_minutes: Option<u16>,
}

#[derive(Clone, Debug, PartialEq, uniffi::Record)]
pub struct AssistantChange {
    pub title: Option<String>,
    pub date: Option<String>,
    pub time_minutes: Option<u16>,
    pub duration: Option<u16>,
}

#[derive(Clone, Debug, PartialEq, uniffi::Enum)]
pub enum AssistantDetail {
    Next,
    List,
    Count,
    Room,
    Therapist,
    Start,
    End,
    Duration,
}

#[derive(Clone, Debug, PartialEq, uniffi::Enum)]
pub enum AssistantHelpTopic {
    Capture,
    Calendars,
    Archive,
    Voice,
    Privacy,
}

#[derive(Clone, Debug, PartialEq, uniffi::Enum)]
pub enum AssistantProblem {
    InvalidDate,
    Ambiguous,
    MissingDate,
    MissingTime,
    MissingTitle,
    MissingEvent,
    Unsupported,
}

impl From<core::Change> for AssistantChange {
    fn from(value: core::Change) -> Self {
        Self {
            title: value.title,
            date: value.date,
            time_minutes: value.time.as_deref().and_then(core::clock_minutes),
            duration: value.duration,
        }
    }
}

#[uniffi::export]
pub fn decode_assistant_request(
    json: String,
    visible_references: Vec<String>,
) -> Result<AssistantRequest, AppError> {
    let request = core::decode(&json, &visible_references).map_err(|_| AppError::Validation {
        message: "Die Modellantwort enthält keinen gültigen Kalenderauftrag.".into(),
    })?;
    Ok(match request {
        core::AssistantRequest::Calendar { query } => AssistantRequest::Calendar {
            query: AssistantQuery {
                detail: match query.detail {
                    core::Detail::Next => AssistantDetail::Next,
                    core::Detail::List => AssistantDetail::List,
                    core::Detail::Count => AssistantDetail::Count,
                    core::Detail::Room => AssistantDetail::Room,
                    core::Detail::Therapist => AssistantDetail::Therapist,
                    core::Detail::Start => AssistantDetail::Start,
                    core::Detail::End => AssistantDetail::End,
                    core::Detail::Duration => AssistantDetail::Duration,
                },
                date: query.date,
                reference: query.reference,
                after_minutes: query.after.as_deref().and_then(core::clock_minutes),
                before_minutes: query.before.as_deref().and_then(core::clock_minutes),
            },
        },
        core::AssistantRequest::Create { change } => AssistantRequest::Create {
            change: change.into(),
        },
        core::AssistantRequest::Update { query, change } => AssistantRequest::Update {
            reference: query.reference,
            change: change.into(),
        },
        core::AssistantRequest::Remove { query } => AssistantRequest::Remove {
            reference: query.reference,
        },
        core::AssistantRequest::Cancel {} => AssistantRequest::Cancel,
        core::AssistantRequest::Help { topic } => AssistantRequest::Help {
            topic: match topic {
                core::HelpTopic::Capture => AssistantHelpTopic::Capture,
                core::HelpTopic::Calendars => AssistantHelpTopic::Calendars,
                core::HelpTopic::Archive => AssistantHelpTopic::Archive,
                core::HelpTopic::Voice => AssistantHelpTopic::Voice,
                core::HelpTopic::Privacy => AssistantHelpTopic::Privacy,
            },
        },
        core::AssistantRequest::Clarify { problem } => AssistantRequest::Clarify {
            problem: match problem {
                core::Problem::InvalidDate => AssistantProblem::InvalidDate,
                core::Problem::Ambiguous => AssistantProblem::Ambiguous,
                core::Problem::MissingDate => AssistantProblem::MissingDate,
                core::Problem::MissingTime => AssistantProblem::MissingTime,
                core::Problem::MissingTitle => AssistantProblem::MissingTitle,
                core::Problem::MissingEvent => AssistantProblem::MissingEvent,
                core::Problem::Unsupported => AssistantProblem::Unsupported,
            },
        },
    })
}
