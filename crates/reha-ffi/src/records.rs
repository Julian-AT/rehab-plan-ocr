use serde::{Deserialize, Serialize};
use std::collections::HashMap;

#[derive(Clone, Debug, PartialEq, uniffi::Enum)]
pub enum FieldValue {
    Empty,
    Text { value: String },
    Integer { value: i64 },
    Unsigned { value: u64 },
    Number { value: f64 },
    Boolean { value: bool },
}
impl Serialize for FieldValue {
    fn serialize<S: serde::Serializer>(&self, serializer: S) -> Result<S::Ok, S::Error> {
        match self {
            Self::Empty => serializer.serialize_none(),
            Self::Text { value } => serializer.serialize_str(value),
            Self::Integer { value } => serializer.serialize_i64(*value),
            Self::Unsigned { value } => serializer.serialize_u64(*value),
            Self::Number { value } => serializer.serialize_f64(*value),
            Self::Boolean { value } => serializer.serialize_bool(*value),
        }
    }
}
impl<'de> Deserialize<'de> for FieldValue {
    fn deserialize<D: serde::Deserializer<'de>>(deserializer: D) -> Result<Self, D::Error> {
        let value = serde_json::Value::deserialize(deserializer)?;
        match value {
            serde_json::Value::Null => Ok(Self::Empty),
            serde_json::Value::String(value) => Ok(Self::Text { value }),
            serde_json::Value::Number(value) if value.is_i64() => Ok(Self::Integer {
                value: value.as_i64().unwrap(),
            }),
            serde_json::Value::Number(value) if value.is_u64() => Ok(Self::Unsigned {
                value: value.as_u64().unwrap(),
            }),
            serde_json::Value::Number(value) => value
                .as_f64()
                .filter(|v| v.is_finite())
                .map(|value| Self::Number { value })
                .ok_or_else(|| serde::de::Error::custom("Invalid field number")),
            serde_json::Value::Bool(value) => Ok(Self::Boolean { value }),
            _ => Err(serde::de::Error::custom("Field values must be scalar")),
        }
    }
}
#[derive(Clone, Debug, Serialize, Deserialize, PartialEq, uniffi::Enum)]
#[serde(rename_all = "snake_case")]
pub enum PrintedState {
    Unreviewed,
    Legible,
    NotPrinted,
    Illegible,
    Cropped,
    Contradictory,
}

#[derive(Clone, Debug, Serialize, Deserialize, PartialEq, uniffi::Record)]
pub struct FieldAssessment {
    pub state: PrintedState,
    pub polygon: Vec<Point>,
    pub frame: String,
    pub reasons: Vec<String>,
    pub confirmed_value: Option<FieldValue>,
    pub confirmed_at: Option<i64>,
}

#[derive(Clone, Debug, Serialize, Deserialize, PartialEq, uniffi::Record)]
pub struct Point {
    pub x: f64,
    pub y: f64,
}

#[derive(Clone, Debug, Serialize, Deserialize, PartialEq, uniffi::Record)]
pub struct Region {
    pub id: String,
    pub polygon: Vec<Point>,
    pub frame: String,
    pub kind: String,
    pub parent: Option<String>,
    pub children: Vec<String>,
}

#[derive(Clone, Debug, Serialize, Deserialize, PartialEq, uniffi::Record)]
pub struct OcrObservation {
    pub id: String,
    pub text: String,
    pub region_ids: Vec<String>,
    pub engine: String,
    pub score: Option<f32>,
    pub alternatives: Vec<String>,
}

#[derive(Clone, Debug, Serialize, Deserialize, PartialEq, uniffi::Record)]
pub struct Issue {
    pub code: String,
    pub message: String,
    pub field: Option<String>,
    pub blocking: bool,
}

#[derive(Clone, Debug, Serialize, Deserialize, PartialEq, uniffi::Record)]
pub struct Metadata {
    pub clinic: String,
    pub department: String,
    pub address: String,
    pub contact: String,
    pub treatment_code: String,
    pub preparation: String,
    pub document_reference: String,
    pub appointment_notes: String,
}

#[derive(Clone, Debug, Serialize, Deserialize, PartialEq, uniffi::Record)]
pub struct FieldOrigin {
    pub kind: String,
    pub evidence: Vec<String>,
    pub source: String,
}

#[derive(Clone, Debug, Serialize, Deserialize, PartialEq, uniffi::Record)]
pub struct CompletionSuggestion {
    pub id: String,
    pub field: String,
    pub value: FieldValue,
    pub source: String,
    pub status: String,
}

#[derive(Clone, Debug, Serialize, Deserialize, PartialEq, uniffi::Record)]
pub struct ApprovalSnapshot {
    pub values_hash: String,
    pub approved_at: i64,
}

#[derive(Clone, Debug, Serialize, Deserialize, PartialEq, uniffi::Record)]
pub struct CompletionDefault {
    pub id: String,
    pub clinic: String,
    pub treatment: String,
    pub field: String,
    pub value: FieldValue,
}

#[derive(Clone, Debug, Serialize, Deserialize, PartialEq, uniffi::Record)]
pub struct Appointment {
    pub id: String,
    pub fields: HashMap<String, FieldAssessment>,
    pub row_polygon: Vec<Point>,
    pub section_id: Option<String>,
    pub metadata: Metadata,
    pub origins: HashMap<String, FieldOrigin>,
    pub suggestions: Vec<CompletionSuggestion>,
    pub approval: Option<ApprovalSnapshot>,
    pub calendar_event_id: Option<String>,
    pub ics_event_id: Option<String>,
    pub calendar_saved_hash: Option<String>,
    pub ics_exported_hash: Option<String>,
    pub date: Option<String>,
    pub start: Option<String>,
    pub end: Option<String>,
    pub end_date: Option<String>,
    pub duration_minutes: Option<u32>,
    pub title: String,
    pub location: String,
    pub therapist: String,
    pub notes: String,
    pub included: bool,
    pub provenance: HashMap<String, Vec<String>>,
    pub issues: Vec<Issue>,
}

#[derive(Clone, Debug, Serialize, Deserialize, PartialEq, uniffi::Record)]
pub struct Document {
    pub schema_version: u32,
    pub id: String,
    pub source_hash: String,
    pub filename: String,
    pub width: u32,
    pub height: u32,
    pub orientation: u32,
    pub imported_at: i64,
    pub source: String,
}

#[derive(Clone, Debug, Serialize, Deserialize, PartialEq, uniffi::Record)]
pub struct Stage {
    pub name: String,
    pub status: String,
    pub duration_ms: u64,
    pub detail: String,
    pub artifacts: Vec<String>,
}

#[derive(Clone, Debug, Serialize, Deserialize, PartialEq, uniffi::Record)]
pub struct EventValues {
    pub title: String,
    pub start_utc: String,
    pub end_utc: String,
    pub timezone: String,
    pub location: String,
    pub notes: String,
    pub reminder_minutes: Option<u32>,
}

#[derive(Clone, Debug, Serialize, Deserialize, PartialEq, uniffi::Record)]
pub struct ImportRecord {
    pub id: String,
    pub schedule_id: String,
    pub calendar_id: String,
    pub external_id: Option<String>,
    pub approved: EventValues,
    pub status: String,
    pub operation_id: String,
}

#[derive(Clone, Debug, Serialize, Deserialize, PartialEq, uniffi::Record)]
pub struct CalendarOperation {
    pub kind: OperationKind,
    pub id: String,
    pub calendar_id: String,
    pub external_id: Option<String>,
    pub before: Option<EventValues>,
    pub after: Option<EventValues>,
    pub requires_resolution: bool,
    pub reason: String,
}

#[derive(Clone, Debug, Serialize, Deserialize, PartialEq, uniffi::Record)]
pub struct CalendarResult {
    pub id: String,
    pub status: WriteStatus,
    pub external_id: Option<String>,
    pub error: Option<String>,
}

#[derive(Clone, Debug, Serialize, Deserialize, PartialEq, uniffi::Enum)]
#[serde(rename_all = "snake_case")]
pub enum OperationKind {
    Create,
    Update,
    Remove,
    Unchanged,
    Keep,
    Protected,
    Ambiguous,
    Conflict,
}
#[derive(Clone, Debug, Serialize, Deserialize, PartialEq, uniffi::Enum)]
#[serde(rename_all = "snake_case")]
pub enum WriteStatus {
    Saved,
    Failed,
    Uncertain,
    Conflict,
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn field_values_preserve_json_numeric_identity() {
        for text in [
            "30",
            "30.0",
            "18446744073709551615",
            "-12",
            "0.25",
            "null",
            "true",
            "\"Raum\"",
        ] {
            let value: FieldValue = serde_json::from_str(text).unwrap();
            assert_eq!(serde_json::to_string(&value).unwrap(), text);
        }
        assert!(serde_json::from_str::<FieldValue>("{\"arbitrary\":true}").is_err());
    }
    #[test]
    fn appointment_roundtrip_keeps_approval_hashes_and_geometry() {
        let mut run: reha_core::contracts::PipelineRun =
            serde_json::from_str(include_str!("../../../public/sample-run.json")).unwrap();
        reha_core::review::migrate(&mut run).unwrap();
        let mut original = run.appointments.remove(0);
        original.duration_minutes = Some(30);
        for field in reha_core::review::FIELDS {
            let value = reha_core::review::value(&original, field);
            original
                .fields
                .entry((*field).into())
                .or_default()
                .confirmed_value = Some(value);
        }
        let wire: Appointment =
            serde_json::from_value(serde_json::to_value(&original).unwrap()).unwrap();
        let roundtrip: reha_core::contracts::Appointment =
            serde_json::from_value(serde_json::to_value(wire).unwrap()).unwrap();
        assert_eq!(
            serde_json::to_string(&original).unwrap(),
            serde_json::to_string(&roundtrip).unwrap()
        );
        assert_eq!(
            reha_core::review::values_hash(&original),
            reha_core::review::values_hash(&roundtrip)
        );
    }
}

#[derive(Clone, Debug, Serialize, Deserialize, PartialEq, uniffi::Enum)]
#[serde(rename_all = "snake_case")]
pub enum Readiness {
    Ready,
    Attention,
    Excluded,
}
#[derive(Clone, Debug, Serialize, Deserialize, PartialEq, uniffi::Record)]
pub struct AppointmentAssessment {
    pub id: String,
    pub document_id: String,
    pub state: Readiness,
    pub issues: Vec<Issue>,
    pub warnings: Vec<Issue>,
}
#[derive(Clone, Debug, Serialize, Deserialize, PartialEq, uniffi::Record)]
pub struct ReadinessQuestion {
    pub id: String,
    pub document_id: String,
    pub appointment_ids: Vec<String>,
    pub field: String,
    pub message: String,
    pub polygon: Vec<Point>,
}
#[derive(Clone, Debug, Serialize, Deserialize, PartialEq, uniffi::Record)]
pub struct DraftAssessment {
    pub revision: String,
    pub policy_version: u32,
    pub appointments: Vec<AppointmentAssessment>,
    pub questions: Vec<ReadinessQuestion>,
    pub ready_ids: Vec<String>,
    pub unprocessed_page_ids: Vec<String>,
}
#[derive(Clone, Deserialize, uniffi::Record)]
pub struct DraftPreview {
    pub assessment: DraftAssessment,
    pub proposal: Option<crate::Proposal>,
}
#[derive(Clone, Deserialize, uniffi::Record)]
pub struct SaveOutcome {
    pub batch_id: String,
    pub results: Vec<CalendarResult>,
    pub existing_ids: Vec<String>,
    pub remaining_ids: Vec<String>,
}
