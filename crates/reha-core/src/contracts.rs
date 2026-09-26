use serde::{Deserialize, Serialize};
use std::collections::BTreeMap;

pub const SCHEMA_VERSION: u32 = 1;
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
#[derive(Clone, Debug, Serialize, Deserialize, PartialEq)]
pub struct Appointment {
    pub id: String,
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
            page_corners: None,
        }
    }
}
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct PipelineRun {
    pub schema_version: u32,
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
