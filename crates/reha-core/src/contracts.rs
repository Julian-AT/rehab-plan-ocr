use serde::{Deserialize, Serialize};
use std::collections::BTreeMap;

pub const SCHEMA_VERSION: u32 = 3;
/// A missing OCR value is not evidence that the printed cell is empty.
#[derive(Clone, Debug, Default, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum PrintedState {
    #[default]
    Unreviewed,
    Legible,
    NotPrinted,
    Illegible,
    Cropped,
    Contradictory,
}
#[derive(Clone, Debug, Default, Serialize, Deserialize, PartialEq)]
#[serde(default)]
pub struct FieldAssessment {
    pub state: PrintedState,
    pub polygon: Vec<Point>,
    pub frame: String,
    pub reasons: Vec<String>,
    pub confirmed_value: Option<serde_json::Value>,
    pub confirmed_at: Option<i64>,
}
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct RefinementReading {
    pub appointment_id: String,
    pub field: String,
    pub value: serde_json::Value,
    pub evidence: Vec<String>,
    pub attempt: String,
}
#[derive(Clone, Copy, Debug, Serialize, Deserialize, PartialEq)]
pub struct Point {
    pub x: f64,
    pub y: f64,
}
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct Region {
    pub id: String,
    pub polygon: Vec<Point>,
    pub frame: String,
    pub kind: String,
    pub parent: Option<String>,
    pub children: Vec<String>,
}
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct Observation {
    pub id: String,
    pub text: String,
    pub region_ids: Vec<String>,
    pub engine: String,
    pub score: Option<f32>,
    pub alternatives: Vec<String>,
}
#[derive(Clone, Debug, Serialize, Deserialize, PartialEq)]
pub struct Issue {
    pub code: String,
    pub message: String,
    pub field: Option<String>,
    pub blocking: bool,
}
impl Issue {
    pub fn new(code: &str, message: &str, field: Option<&str>, blocking: bool) -> Self {
        Self {
            code: code.into(),
            message: message.into(),
            field: field.map(str::to_owned),
            blocking,
        }
    }
}
/// Calendar-safe metadata. Administrative/patient details remain in document observations.
#[derive(Clone, Debug, Default, Serialize, Deserialize, PartialEq)]
#[serde(default)]
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
#[derive(Clone, Debug, Serialize, Deserialize, PartialEq)]
pub struct FieldOrigin {
    pub kind: String,
    pub evidence: Vec<String>,
    pub source: String,
}
#[derive(Clone, Debug, Serialize, Deserialize, PartialEq)]
pub struct CompletionSuggestion {
    pub id: String,
    pub field: String,
    pub value: serde_json::Value,
    pub source: String,
    pub status: String,
}
#[derive(Clone, Debug, Serialize, Deserialize, PartialEq)]
pub struct ApprovalSnapshot {
    pub values_hash: String,
    pub approved_at: i64,
}
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct ScheduleSection {
    pub id: String,
    pub date: Option<String>,
    pub polygon: Vec<Point>,
    pub heading_ids: Vec<String>,
    pub observation_ids: Vec<String>,
    pub columns: BTreeMap<String, f64>,
    pub metadata: Metadata,
}
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct RefinementAttempt {
    pub id: String,
    pub target_ids: Vec<String>,
    pub reason: String,
    pub variant: String,
    pub crop_to_original: [f64; 9],
    pub crop_to_page: [f64; 9],
    pub width: u32,
    pub height: u32,
    pub duration_ms: u64,
    pub status: String,
    pub observation_ids: Vec<String>,
    pub detail: String,
}
#[derive(Clone, Debug, Serialize, Deserialize, PartialEq)]
pub struct CompletionDefault {
    pub id: String,
    pub clinic: String,
    pub treatment: String,
    pub field: String,
    pub value: serde_json::Value,
}
#[derive(Clone, Debug, Serialize, Deserialize, PartialEq)]
pub struct Appointment {
    pub id: String,
    #[serde(default)]
    pub fields: BTreeMap<String, FieldAssessment>,
    #[serde(default)]
    pub row_polygon: Vec<Point>,
    #[serde(default)]
    pub section_id: Option<String>,
    #[serde(default)]
    pub metadata: Metadata,
    #[serde(default)]
    pub origins: BTreeMap<String, FieldOrigin>,
    #[serde(default)]
    pub suggestions: Vec<CompletionSuggestion>,
    #[serde(default)]
    pub approval: Option<ApprovalSnapshot>,
    #[serde(default)]
    pub calendar_event_id: Option<String>,
    #[serde(default)]
    pub ics_event_id: Option<String>,
    #[serde(default)]
    pub calendar_saved_hash: Option<String>,
    #[serde(default)]
    pub ics_exported_hash: Option<String>,
    pub date: Option<String>,
    pub start: Option<String>,
    pub end: Option<String>,
    pub end_date: Option<String>,
    pub duration_minutes: Option<u32>,
    pub title: String,
    pub location: String,
    #[serde(default)]
    pub therapist: String,
    pub notes: String,
    pub included: bool,
    #[serde(default)]
    pub provenance: BTreeMap<String, Vec<String>>,
    #[serde(default)]
    pub issues: Vec<Issue>,
}
impl Appointment {
    pub fn empty(id: String) -> Self {
        Self {
            id,
            fields: BTreeMap::new(),
            row_polygon: vec![],
            section_id: None,
            metadata: Metadata::default(),
            origins: BTreeMap::new(),
            suggestions: vec![],
            approval: None,
            calendar_event_id: None,
            ics_event_id: None,
            calendar_saved_hash: None,
            ics_exported_hash: None,
            date: None,
            start: None,
            end: None,
            end_date: None,
            duration_minutes: None,
            title: String::new(),
            location: String::new(),
            therapist: String::new(),
            notes: String::new(),
            included: true,
            provenance: BTreeMap::new(),
            issues: Vec::new(),
        }
    }
}
#[derive(Clone, Debug, Serialize, Deserialize)]
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
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct Stage {
    pub name: String,
    pub status: String,
    pub duration_ms: u64,
    pub detail: String,
    pub artifacts: Vec<String>,
}
#[derive(Clone, Debug, Serialize, Deserialize, PartialEq)]
pub struct PipelineConfig {
    #[serde(default = "default_engine")]
    pub engine: String,
    pub timezone: String,
    pub detector_side: u32,
    pub detector_threshold: f32,
    pub box_threshold: f32,
    pub detailed_debug: bool,
    pub quarter_turns: u8,
    #[serde(default)]
    pub mirrored: bool,
    pub page_corners: Option<[Point; 4]>,
}
fn default_engine() -> String {
    "portable-small".into()
}
impl Default for PipelineConfig {
    fn default() -> Self {
        Self {
            engine: default_engine(),
            timezone: "Europe/Vienna".into(),
            detector_side: 1280,
            detector_threshold: 0.3,
            box_threshold: 0.6,
            detailed_debug: false,
            quarter_turns: 0,
            mirrored: false,
            page_corners: None,
        }
    }
}
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct PipelineRun {
    pub schema_version: u32,
    #[serde(default)]
    pub sections: Vec<ScheduleSection>,
    #[serde(default)]
    pub refinement_attempts: Vec<RefinementAttempt>,
    #[serde(default)]
    pub refinement_readings: Vec<RefinementReading>,
    #[serde(default)]
    pub extraction_version: u32,
    pub id: String,
    pub document: Document,
    pub config: PipelineConfig,
    pub engine: String,
    pub model_manifest: serde_json::Value,
    pub stages: Vec<Stage>,
    pub regions: Vec<Region>,
    pub observations: Vec<Observation>,
    pub appointments: Vec<Appointment>,
    pub issues: Vec<Issue>,
    pub unassigned: Vec<String>,
    pub original_to_page: [f64; 9],
    pub page_to_original: [f64; 9],
    pub page_width: u32,
    pub page_height: u32,
    pub complete_page_confirmed: bool,
    #[serde(default)]
    pub review_confirmed: bool,
    pub total_ms: u64,
    pub peak_memory_bytes: Option<u64>,
    pub cache_used: bool,
}
#[derive(Clone, Debug, Serialize, Deserialize, PartialEq)]
pub struct EventValues {
    pub title: String,
    pub start_utc: String,
    pub end_utc: String,
    pub timezone: String,
    pub location: String,
    pub notes: String,
    pub reminder_minutes: Option<u32>,
}
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct ImportRecord {
    pub id: String,
    pub schedule_id: String,
    pub calendar_id: String,
    pub external_id: Option<String>,
    pub approved: EventValues,
    pub status: String,
    pub operation_id: String,
}
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct CalendarOverlap {
    pub appointment_id: String,
    pub external_id: String,
    pub title: String,
    pub start_utc: String,
    pub end_utc: String,
}
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct CalendarOperation {
    pub kind: String,
    pub id: String,
    pub calendar_id: String,
    pub external_id: Option<String>,
    pub before: Option<EventValues>,
    pub after: Option<EventValues>,
    pub requires_resolution: bool,
    pub reason: String,
}
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct CalendarResult {
    pub id: String,
    pub status: String,
    pub external_id: Option<String>,
    pub error: Option<String>,
}
