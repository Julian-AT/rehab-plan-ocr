//! Plan acceptance is not a claim that any field was verified against a photo.
use crate::{calendar, contracts::*, review};
use serde::{Deserialize, Serialize};
use std::collections::BTreeMap;

pub const POLICY_VERSION: u32 = 1;
const ESSENTIAL: &[&str] = &[
    "title",
    "date",
    "start",
    "end",
    "end_date",
    "duration_minutes",
];
const VALUE_ISSUES: &[&str] = &[
    "missing_date",
    "missing_start",
    "missing_end",
    "invalid_end",
    "overnight_confirmation",
    "missing_title",
];

#[derive(Clone, Debug, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "snake_case")]
pub enum Readiness {
    Ready,
    Attention,
    Excluded,
}
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct AppointmentAssessment {
    pub id: String,
    pub document_id: String,
    pub state: Readiness,
    pub issues: Vec<Issue>,
    pub warnings: Vec<Issue>,
}
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct ReadinessQuestion {
    pub id: String,
    pub document_id: String,
    pub appointment_ids: Vec<String>,
    pub field: String,
    pub message: String,
    pub polygon: Vec<Point>,
}
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct DraftAssessment {
    pub revision: String,
    pub policy_version: u32,
    pub appointments: Vec<AppointmentAssessment>,
    pub questions: Vec<ReadinessQuestion>,
    pub ready_ids: Vec<String>,
    pub unprocessed_page_ids: Vec<String>,
}
#[derive(Clone, Serialize, Deserialize)]
pub struct PlanAcceptance {
    pub policy_version: u32,
    pub accepted_at: i64,
    pub value_hashes: BTreeMap<String, String>,
    pub proposal_revision: String,
}

pub(crate) fn issue_decision_hash(a: &Appointment, issue: &Issue) -> serde_json::Value {
    serde_json::json!(crate::hash(
        &serde_json::to_vec(&(review::values_hash(a), issue, &a.row_polygon, &a.provenance,))
            .unwrap()
    ))
}
fn manually_corrected(a: &Appointment, field: &str) -> bool {
    a.origins
        .get(field)
        .is_some_and(|o| o.kind == "manual" && o.source == "Manuell eingegeben")
}
fn resolved(a: &Appointment, field: &str) -> bool {
    review::field_confirmed(a, field) || manually_corrected(a, field)
}
fn relevant(a: &Appointment, field: &str) -> bool {
    match field {
        "end" => a.end.is_some() || a.duration_minutes.is_none(),
        "end_date" => a.end_date.is_some(),
        "duration_minutes" => a.duration_minutes.is_some() || a.end.is_none(),
        _ => ESSENTIAL.contains(&field),
    }
}
pub fn appointment(a: &Appointment, document_id: &str, timezone: &str) -> AppointmentAssessment {
    let mut issues = crate::parser::validate(a);
    let mut warnings = vec![];
    for issue in review::field_problems(a) {
        if issue
            .field
            .as_deref()
            .is_some_and(|f| relevant(a, f) && !resolved(a, f))
        {
            issues.push(issue);
        } else if !issue.field.as_deref().is_some_and(|f| resolved(a, f)) {
            warnings.push(Issue {
                blocking: false,
                ..issue
            });
        }
    }
    for issue in &a.issues {
        if VALUE_ISSUES.contains(&issue.code.as_str()) {
            continue;
        }
        // Cancellation needs an explicit exception decision, even after editing a title.
        if issue.code == "possible_cancellation" {
            if !a.fields.get("cancellation").is_some_and(|f| {
                f.confirmed_at.is_some()
                    && f.confirmed_value == Some(serde_json::json!(review::values_hash(a)))
            }) {
                issues.push(Issue::new(
                    "possible_cancellation",
                    "Möglicherweise abgesagt oder handschriftlich geändert.",
                    Some("cancellation"),
                    true,
                ));
            }
        } else if issue.blocking && issue.field.is_none() {
            let decision = format!("issue:{}", issue.code);
            if !a.fields.get(&decision).is_some_and(|f| {
                f.confirmed_at.is_some() && f.confirmed_value == Some(issue_decision_hash(a, issue))
            }) {
                issues.push(Issue {
                    field: Some(decision),
                    ..issue.clone()
                });
            }
        } else if issue.field.as_deref().is_some_and(|f| resolved(a, f)) {
            continue;
        } else if issue.blocking && issue.field.as_deref().is_none_or(|f| relevant(a, f)) {
            issues.push(issue.clone());
        } else {
            warnings.push(Issue {
                blocking: false,
                ..issue.clone()
            });
        }
    }
    if issues.is_empty() {
        if let Err(error) = calendar::validated_values(a, timezone, None) {
            issues.push(Issue::new(
                "validation",
                &error.to_string(),
                Some("end"),
                true,
            ));
        }
    }
    issues.dedup();
    warnings.dedup();
    AppointmentAssessment {
        id: a.id.clone(),
        document_id: document_id.into(),
        state: if !a.included {
            Readiness::Excluded
        } else if issues.is_empty() {
            Readiness::Ready
        } else {
            Readiness::Attention
        },
        issues,
        warnings,
    }
}
pub fn assess(runs: &[PipelineRun], timezone: &str) -> DraftAssessment {
    let mut appointments = vec![];
    let mut questions: BTreeMap<String, ReadinessQuestion> = BTreeMap::new();
    for run in runs {
        for a in &run.appointments {
            let assessment = appointment(a, &run.document.id, timezone);
            if assessment.state == Readiness::Attention {
                for issue in &assessment.issues {
                    let field = issue.field.as_deref().unwrap_or("title");
                    let source_points: Vec<Point> = a
                        .provenance
                        .get(field)
                        .into_iter()
                        .flatten()
                        .filter_map(|id| run.observations.iter().find(|o| &o.id == id))
                        .flat_map(|o| &o.region_ids)
                        .filter_map(|id| run.regions.iter().find(|r| &r.id == id))
                        .filter(|r| r.frame == "page")
                        .flat_map(|r| r.polygon.clone())
                        .collect();
                    let source_crop = if source_points.is_empty() {
                        a.row_polygon.clone()
                    } else {
                        let left = source_points
                            .iter()
                            .map(|p| p.x)
                            .fold(f64::INFINITY, f64::min);
                        let right = source_points
                            .iter()
                            .map(|p| p.x)
                            .fold(f64::NEG_INFINITY, f64::max);
                        let top = source_points
                            .iter()
                            .map(|p| p.y)
                            .fold(f64::INFINITY, f64::min);
                        let bottom = source_points
                            .iter()
                            .map(|p| p.y)
                            .fold(f64::NEG_INFINITY, f64::max);
                        vec![
                            Point { x: left, y: top },
                            Point { x: right, y: top },
                            Point {
                                x: right,
                                y: bottom,
                            },
                            Point { x: left, y: bottom },
                        ]
                    };
                    let polygon = a
                        .fields
                        .get(field)
                        .filter(|f| f.frame == "page")
                        .map(|f| f.polygon.clone())
                        .filter(|p| !p.is_empty())
                        .unwrap_or(source_crop);
                    // A date/section label alone is insufficient evidence of a shared heading.
                    let evidence = a.provenance.get("date").filter(|ids| {
                        !ids.is_empty()
                            && ids
                                .iter()
                                .all(|id| run.observations.iter().any(|o| &o.id == id))
                            && run.sections.iter().any(|section| {
                                a.section_id.as_ref() == Some(&section.id)
                                    && ids.len() == section.heading_ids.len()
                                    && ids.iter().all(|id| section.heading_ids.contains(id))
                            })
                    });
                    let identity = if let Some(evidence) = evidence.filter(|_| field == "date") {
                        let mut ids = evidence.clone();
                        ids.sort();
                        ids.dedup();
                        format!(
                            "{}:date:{}:{}",
                            run.document.id,
                            serde_json::to_string(&ids).unwrap(),
                            a.date.as_deref().unwrap_or("")
                        )
                    } else {
                        format!("{}:{}:{field}", run.document.id, a.id)
                    };
                    let id = crate::hash(identity.as_bytes());
                    let question = questions.entry(id.clone()).or_insert(ReadinessQuestion {
                        id,
                        document_id: run.document.id.clone(),
                        appointment_ids: vec![],
                        field: field.into(),
                        message: issue.message.clone(),
                        polygon,
                    });
                    if !question.appointment_ids.contains(&a.id) {
                        question.appointment_ids.push(a.id.clone());
                    }
                }
            }
            appointments.push(assessment);
        }
    }
    DraftAssessment {
        revision: crate::hash(&serde_json::to_vec(runs).unwrap()),
        policy_version: POLICY_VERSION,
        ready_ids: appointments
            .iter()
            .filter(|a| a.state == Readiness::Ready)
            .map(|a| a.id.clone())
            .collect(),
        appointments,
        questions: questions.into_values().collect(),
        unprocessed_page_ids: vec![],
    }
}
