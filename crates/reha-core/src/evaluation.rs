use crate::{contracts::Appointment, Error, Result};
use serde::{Deserialize, Serialize};
use std::collections::HashSet;

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct Annotation {
    pub schema_version: u32,
    pub day_id: String,
    pub document_hashes: Vec<String>,
    pub verified: bool,
    pub reviewed_at: Option<String>,
    pub split: String,
    pub appointments: Vec<Appointment>,
    pub uncertainty_notes: Vec<String>,
}
#[derive(Clone, Debug, Default, Serialize, Deserialize)]
pub struct Metrics {
    pub reference_count: usize,
    pub predicted_count: usize,
    pub matched_count: usize,
    pub fully_correct_count: usize,
    pub missed_count: usize,
    pub invented_count: usize,
    pub date_correct: usize,
    pub start_correct: usize,
    pub end_or_duration_correct: usize,
    pub title_correct: usize,
    pub location_correct: usize,
    pub therapist_correct: usize,
    pub notes_correct: usize,
    pub unresolved_count: usize,
    pub schedule_without_correction: bool,
    pub appointment_precision: Option<f64>,
    pub appointment_recall: Option<f64>,
    pub critical_field_accuracy: Option<f64>,
}
pub fn compare(
    reference: &Annotation,
    predicted: &[Appointment],
    allow_holdout: bool,
) -> Result<Metrics> {
    if reference.schema_version != 1
        || !reference.verified
        || reference.reviewed_at.is_none()
        || !reference.uncertainty_notes.is_empty()
    {
        return Err(Error::Invalid(
            "Ground truth is provisional; verify against paper before scoring.".into(),
        ));
    }
    if reference.split == "holdout" && !allow_holdout {
        return Err(Error::Invalid("Final holdout is locked. Use the explicit final-evaluation command after freezing configuration.".into()));
    }
    let mut m = Metrics {
        reference_count: reference.appointments.len(),
        predicted_count: predicted.len(),
        ..Default::default()
    };
    let mut used = HashSet::new();
    let equal = |a: &Appointment, b: &Appointment| {
        a.date == b.date
            && a.start == b.start
            && a.end == b.end
            && a.duration_minutes == b.duration_minutes
            && a.title == b.title
            && a.location == b.location
            && a.therapist == b.therapist
            && a.notes == b.notes
            && a.end_date == b.end_date
    };
    for truth in &reference.appointments {
        let exact = predicted
            .iter()
            .enumerate()
            .find(|(j, p)| !used.contains(j) && equal(truth, p));
        let candidate = exact.or_else(|| {
            let candidates: Vec<_> = predicted
                .iter()
                .enumerate()
                .filter(|(j, p)| {
                    !used.contains(j)
                        && ((p.title == truth.title && p.location == truth.location)
                            || (p.start == truth.start && p.date == truth.date))
                })
                .collect();
            if candidates.len() == 1 {
                Some(candidates[0])
            } else {
                None
            }
        });
        if let Some((j, p)) = candidate {
            used.insert(j);
            m.matched_count += 1;
            m.fully_correct_count += usize::from(equal(truth, p));
            m.date_correct += usize::from(truth.date == p.date && truth.date.is_some());
            m.start_correct += usize::from(truth.start == p.start && truth.start.is_some());
            m.end_or_duration_correct += usize::from(
                (truth.end.is_some() && truth.end == p.end && truth.end_date == p.end_date)
                    || (truth.end.is_none()
                        && truth.duration_minutes.is_some()
                        && truth.duration_minutes == p.duration_minutes),
            );
            m.title_correct += usize::from(truth.title == p.title);
            m.location_correct += usize::from(truth.location == p.location);
            m.therapist_correct += usize::from(truth.therapist == p.therapist);
            m.notes_correct += usize::from(truth.notes == p.notes);
        }
    }
    m.missed_count = m.reference_count - m.matched_count;
    m.invented_count = m.predicted_count - m.matched_count;
    m.unresolved_count = predicted
        .iter()
        .filter(|a| !crate::parser::validate(a).is_empty() || a.issues.iter().any(|i| i.blocking))
        .count();
    m.schedule_without_correction = m.fully_correct_count == m.reference_count
        && m.predicted_count == m.reference_count
        && m.unresolved_count == 0;
    m.appointment_precision =
        (m.predicted_count > 0).then(|| m.matched_count as f64 / m.predicted_count as f64);
    m.appointment_recall =
        (m.reference_count > 0).then(|| m.matched_count as f64 / m.reference_count as f64);
    m.critical_field_accuracy = (m.reference_count > 0).then(|| {
        (m.date_correct + m.start_correct + m.end_or_duration_correct) as f64
            / (3 * m.reference_count) as f64
    });
    Ok(m)
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn missing_predictions_count_in_denominator() {
        let mut a = Appointment::empty("a".into());
        a.date = Some("2026-09-10".into());
        let r = Annotation {
            schema_version: 1,
            day_id: "synthetic".into(),
            document_hashes: vec![],
            verified: true,
            reviewed_at: Some("synthetic".into()),
            split: "development".into(),
            appointments: vec![a],
            uncertainty_notes: vec![],
        };
        let m = compare(&r, &[], false).unwrap();
        assert_eq!(m.missed_count, 1);
        assert_eq!(m.critical_field_accuracy, Some(0.));
    }
    #[test]
    fn provisional_and_holdout_are_locked() {
        let mut r = Annotation {
            schema_version: 1,
            day_id: "synthetic".into(),
            document_hashes: vec![],
            verified: false,
            reviewed_at: None,
            split: "development".into(),
            appointments: vec![],
            uncertainty_notes: vec![],
        };
        assert!(compare(&r, &[], false).is_err());
        r.verified = true;
        r.split = "holdout".into();
        assert!(compare(&r, &[], false).is_err());
    }
}
