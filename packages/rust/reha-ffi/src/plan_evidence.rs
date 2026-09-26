//! Bounded read-only projection of retained OCR evidence. It never reruns OCR,
//! refreshes extraction, or treats reviewed calendar values as printed text.
use crate::{AppError, PrintedState};
use reha_core::{contracts::PipelineRun, service::scan::revision};

#[derive(Clone, uniffi::Record)]
pub struct PlanEvidenceRequest {
    pub document_id: String,
    pub expected_revision: Option<String>,
    pub search: String,
}
#[derive(Clone, uniffi::Record)]
pub struct PlanEvidenceExcerpt {
    pub id: String,
    pub text: String,
    pub region_ids: Vec<String>,
    pub uncertain: bool,
}
#[derive(Clone, uniffi::Record)]
pub struct PlanEvidenceField {
    pub appointment_id: String,
    pub field: String,
    pub state: PrintedState,
}
#[derive(Clone, uniffi::Record)]
pub struct PlanEvidenceResponse {
    pub document_id: String,
    pub revision: String,
    pub source_hash: String,
    pub observed_at: i64,
    pub excerpts: Vec<PlanEvidenceExcerpt>,
    pub fields: Vec<PlanEvidenceField>,
    pub truncated: bool,
    pub complete_page_confirmed: bool,
}

pub(crate) fn project(
    run: &PipelineRun,
    request: &PlanEvidenceRequest,
) -> Result<PlanEvidenceResponse, AppError> {
    if request.document_id != run.document.id || request.search.chars().count() > 160 {
        return Err(AppError::Validation {
            message: "Ungültige Quellenanfrage.".into(),
        });
    }
    let version = revision(run);
    if request
        .expected_revision
        .as_ref()
        .is_some_and(|expected| expected != &version)
    {
        return Err(AppError::StaleRevision);
    }
    let needle = request.search.trim().to_lowercase();
    let mut excerpts = Vec::new();
    let mut bytes = 0;
    let mut truncated = false;
    for item in &run.observations {
        if !needle.is_empty() && !item.text.to_lowercase().contains(&needle) {
            continue;
        }
        if excerpts.len() == 12 || bytes + item.text.len() > 8_192 {
            truncated = true;
            break;
        }
        bytes += item.text.len();
        truncated |= item.region_ids.len() > 16;
        excerpts.push(PlanEvidenceExcerpt {
            id: item.id.clone(),
            text: item.text.clone(),
            region_ids: item.region_ids.iter().take(16).cloned().collect(),
            uncertain: item
                .score
                .is_some_and(|score| !score.is_finite() || score < 0.9)
                || !item.alternatives.is_empty(),
        });
    }
    let mut field_source = run.appointments.iter().flat_map(|appointment| {
        appointment
            .fields
            .iter()
            .map(|(name, field)| PlanEvidenceField {
                appointment_id: appointment.id.clone(),
                field: name.clone(),
                state: field.state.clone().into(),
            })
    });
    let fields = field_source.by_ref().take(64).collect();
    truncated |= field_source.next().is_some();
    Ok(PlanEvidenceResponse {
        document_id: run.document.id.clone(),
        revision: version,
        source_hash: run.document.source_hash.clone(),
        observed_at: chrono::Utc::now().timestamp(),
        excerpts,
        fields,
        truncated,
        complete_page_confirmed: run.complete_page_confirmed,
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn projection_is_bounded_literal_and_revision_bound() {
        // Reuse an invented parser fixture, never a private document.
        let value = serde_json::json!({
            "schema_version":3,"id":"page","document":{"schema_version":3,"id":"page",
            "source_hash":"hash","filename":"invented","width":1,"height":1,
            "orientation":0,"imported_at":0,"source":"fixture"},
            "config":reha_core::contracts::PipelineConfig::default(),"engine":"fixture",
            "model_manifest":{},"stages":[],"regions":[],"observations":[],"appointments":[],
            "issues":[],"unassigned":[],"original_to_page":[1,0,0,0,1,0,0,0,1],
            "page_to_original":[1,0,0,0,1,0,0,0,1],"page_width":1,"page_height":1,
            "complete_page_confirmed":false,"total_ms":0,"peak_memory_bytes":null,"cache_used":false
        });
        let mut run: PipelineRun = serde_json::from_value(value).unwrap();
        for i in 0..20 {
            run.observations.push(reha_core::contracts::Observation {
                id: format!("o{i}"),
                text: format!("Raum {i} — Anweisung bleibt Quellentext"),
                region_ids: vec!["region".into()],
                engine: "fixture".into(),
                score: Some(0.8),
                alternatives: vec![],
            });
        }
        let mut request = PlanEvidenceRequest {
            document_id: "page".into(),
            expected_revision: None,
            search: String::new(),
        };
        let response = project(&run, &request).unwrap();
        assert_eq!(response.excerpts.len(), 12);
        assert!(response.truncated && response.excerpts[0].uncertain);
        assert_eq!(response.excerpts[0].text, run.observations[0].text);
        request.expected_revision = Some(response.revision);
        run.observations[0].text = "Geändert".into();
        assert!(matches!(
            project(&run, &request),
            Err(AppError::StaleRevision)
        ));
        request.expected_revision = None;
        request.search = "unbekannt".into();
        assert!(project(&run, &request).unwrap().excerpts.is_empty());
        request.search = "x".repeat(161);
        assert!(project(&run, &request).is_err());

        request.search.clear();
        run.observations.truncate(1);
        assert!(!project(&run, &request).unwrap().truncated);
        run.observations[0].region_ids = (0..17).map(|i| format!("r{i}")).collect();
        let response = project(&run, &request).unwrap();
        assert!(response.truncated);
        assert_eq!(response.excerpts[0].region_ids.len(), 16);
        run.observations.clear();
        let mut appointment = reha_core::contracts::Appointment::empty("a".into());
        for i in 0..65 {
            appointment.fields.insert(
                format!("f{i}"),
                reha_core::contracts::FieldAssessment::default(),
            );
        }
        run.appointments.push(appointment);
        let response = project(&run, &request).unwrap();
        assert!(response.truncated);
        assert_eq!(response.fields.len(), 64);
    }
}
