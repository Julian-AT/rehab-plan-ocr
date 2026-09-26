use crate::{OcrObservation, Region};
use reha_core::{contracts as domain, service::text_recognition as core};

#[derive(Clone, Debug, uniffi::Record)]
pub struct TextRecognitionRequest {
    pub image: Vec<u8>,
    pub budget_ms: u64,
}
#[derive(Clone, Debug, uniffi::Record)]
pub struct TextRecognitionIdentity {
    pub engine: String,
    pub revision: u64,
    pub system_version: String,
    pub language_correction: bool,
}
#[derive(Clone, Debug, uniffi::Record)]
pub struct TextRecognitionResult {
    pub regions: Vec<Region>,
    pub observations: Vec<OcrObservation>,
    pub duration_ms: u64,
    pub identity: TextRecognitionIdentity,
}
impl From<core::Request> for TextRecognitionRequest {
    fn from(value: core::Request) -> Self {
        Self {
            image: value.image,
            budget_ms: value.budget_ms,
        }
    }
}
impl From<TextRecognitionResult> for core::Output {
    fn from(value: TextRecognitionResult) -> Self {
        Self {
            regions: value
                .regions
                .into_iter()
                .map(|r| domain::Region {
                    id: r.id,
                    polygon: r
                        .polygon
                        .into_iter()
                        .map(|p| domain::Point { x: p.x, y: p.y })
                        .collect(),
                    frame: r.frame,
                    kind: r.kind,
                    parent: r.parent,
                    children: r.children,
                })
                .collect(),
            observations: value
                .observations
                .into_iter()
                .map(|o| domain::Observation {
                    id: o.id,
                    text: o.text,
                    region_ids: o.region_ids,
                    engine: o.engine,
                    score: o.score,
                    alternatives: o.alternatives,
                })
                .collect(),
            duration_ms: value.duration_ms,
            // The persisted pipeline manifest deliberately retains its existing schema.
            manifest: serde_json::json!({
                "engine":value.identity.engine,
                "revision":value.identity.revision,
                "system_version":value.identity.system_version,
                "language_correction":value.identity.language_correction,
            }),
        }
    }
}
