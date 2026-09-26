use crate::{
    contracts::{Appointment, Point, PrintedState},
    Error, Result,
};
use serde::{Deserialize, Serialize};
use std::collections::{BTreeMap, HashSet};

#[derive(Clone, Debug, Default, Serialize, Deserialize)]
#[serde(default)]
pub struct ReferenceSource {
    pub source_hash: String,
    pub original_hash: String,
    pub logical_page: String,
    pub capture_series: String,
    pub treatment_days: Vec<String>,
    pub width: u32,
    pub height: u32,
    pub table_polygon: Vec<Point>,
    pub relationships_confirmed: bool,
}
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct ReferenceLine {
    pub id: String,
    pub source_hash: String,
    pub appointment_id: String,
    pub field: String,
    pub text: String,
    pub polygon: Vec<Point>,
    pub state: PrintedState,
    #[serde(default)]
    pub error_causes: Vec<String>,
}
#[derive(Clone, Debug, Default, Serialize, Deserialize)]
pub struct Annotation {
    pub schema_version: u32,
    pub day_id: String,
    pub document_hashes: Vec<String>,
    pub verified: bool,
    pub reviewed_at: Option<String>,
    pub split: String,
    pub appointments: Vec<Appointment>,
    pub uncertainty_notes: Vec<String>,
    #[serde(default)]
    pub sources: Vec<ReferenceSource>,
    #[serde(default)]
    pub lines: Vec<ReferenceLine>,
    #[serde(default)]
    pub coverage_confirmed: bool,
    #[serde(default)]
    pub content_hash: Option<String>,
    #[serde(default)]
    pub approval_hash: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub input_class: Option<String>,
}
pub fn reference_hash(reference: &Annotation) -> String {
    let mut value = serde_json::to_value(reference).expect("annotation serialization");
    for key in ["verified", "reviewed_at", "content_hash", "approval_hash"] {
        value.as_object_mut().unwrap().remove(key);
    }
    canonical_hash(value)
}
/// Cross-language hash: JSON integer/float spellings and exponent formatting
/// must not invalidate a reference when Python, Rust and the webview round-trip it.
pub fn canonical_hash(mut value: serde_json::Value) -> String {
    fn normalize(v: &mut serde_json::Value) {
        match v {
            serde_json::Value::Number(n) => {
                *v = serde_json::json!({"$f64":format!("{:016x}", n.as_f64().unwrap().to_bits())})
            }
            serde_json::Value::Array(a) => a.iter_mut().for_each(normalize),
            serde_json::Value::Object(o) => o.values_mut().for_each(normalize),
            _ => (),
        }
    }
    normalize(&mut value);
    crate::hash(&serde_json::to_vec(&value).unwrap())
}
pub fn validate_reference(reference: &Annotation, approval: bool) -> Result<()> {
    if reference
        .input_class
        .as_deref()
        .is_some_and(|v| !["rehabilitation_plan", "non_plan", "unusable"].contains(&v))
    {
        return Err(Error::Invalid("Unbekannte Art der Referenzeingabe.".into()));
    }
    if reference.input_class.as_deref() == Some("non_plan") && !reference.appointments.is_empty() {
        return Err(Error::Invalid(
            "Eine Nicht-Plan-Referenz darf keine Termine enthalten.".into(),
        ));
    }
    if reference.schema_version != 2 {
        return Err(Error::Invalid(
            "Referenz zuerst auf Version 2 mit Originalgeometrie migrieren.".into(),
        ));
    }
    if reference.sources.is_empty()
        || reference.sources.iter().any(|s| {
            !reference.document_hashes.contains(&s.source_hash)
                || s.original_hash.len() != 64
                || s.width == 0
                || s.height == 0
                || s.table_polygon.len() != 4
        })
    {
        return Err(Error::Invalid(
            "Originalhash und Tabellengeometrie jeder Quelle erforderlich.".into(),
        ));
    }
    for source in &reference.sources {
        if !source.original_hash.chars().all(|c| c.is_ascii_hexdigit())
            || source.table_polygon.iter().any(|p| {
                !p.x.is_finite()
                    || !p.y.is_finite()
                    || p.x < 0.
                    || p.y < 0.
                    || p.x > source.width as f64
                    || p.y > source.height as f64
            })
            || crate::geometry::homography(
                &source.table_polygon.clone().try_into().unwrap(),
                &crate::geometry::rect(0., 0., 100., 100.)
                    .try_into()
                    .unwrap(),
            )
            .is_err()
        {
            return Err(Error::Invalid(
                "Ungültiger Originalhash oder Tabellenumriss.".into(),
            ));
        }
    }
    let mut ids = HashSet::new();
    if reference.appointments.iter().any(|a| !ids.insert(&a.id)) {
        return Err(Error::Invalid("Doppelte Referenztermin-ID.".into()));
    }
    let mut line_ids = HashSet::new();
    for line in &reference.lines {
        if !line_ids.insert(&line.id) {
            return Err(Error::Invalid("Doppelte Textzeilen-ID.".into()));
        }
        let source = reference
            .sources
            .iter()
            .find(|s| s.source_hash == line.source_hash)
            .ok_or_else(|| Error::Invalid("Textzeile ohne Quelle.".into()))?;
        if line.polygon.len() < 4
            || line.polygon.iter().any(|p| {
                !p.x.is_finite()
                    || !p.y.is_finite()
                    || p.x < 0.
                    || p.y < 0.
                    || p.x > source.width as f64
                    || p.y > source.height as f64
                    || !crate::geometry::inside(&source.table_polygon, p)
            })
            || !reference
                .appointments
                .iter()
                .any(|a| a.id == line.appointment_id)
            || !crate::review::FIELDS.contains(&line.field.as_str())
        {
            return Err(Error::Invalid(
                "Textpolygone müssen innerhalb der Termintabelle einem Feld zugeordnet sein."
                    .into(),
            ));
        }
    }
    if approval
        && (reference.sources.iter().any(|s| !s.relationships_confirmed)
            || !reference.coverage_confirmed
            || !reference.uncertainty_notes.is_empty()
            || (reference.appointments.is_empty()
                && !reference
                    .input_class
                    .as_deref()
                    .is_some_and(|v| ["non_plan", "unusable"].contains(&v)))
            || reference.appointments.iter().any(|a| {
                [
                    "date",
                    "start",
                    "end",
                    "title",
                    "location",
                    "therapist",
                    "notes",
                ]
                .iter()
                .any(|f| {
                    !a.fields.get(*f).is_some_and(|s| {
                        s.state != PrintedState::Unreviewed
                            && s.confirmed_at.is_some()
                            && s.confirmed_value.clone().unwrap_or_default()
                                == crate::review::value(a, f)
                            && (s.state != PrintedState::NotPrinted
                                || crate::review::empty(&crate::review::value(a, f)))
                            && s.frame == "original"
                            && s.polygon.len() >= 4
                    }) || (a
                        .fields
                        .get(*f)
                        .is_some_and(|s| s.state == PrintedState::Legible)
                        && !reference.lines.iter().any(|l| {
                            l.appointment_id == a.id
                                && l.field == *f
                                && l.state == PrintedState::Legible
                        }))
                })
            }))
    {
        return Err(Error::Invalid(
            "Jedes gedruckte Feld, leere Zellen und die Vollständigkeit zuerst am Foto bestätigen."
                .into(),
        ));
    }
    Ok(())
}

pub fn relationships_hash(references: &[Annotation]) -> String {
    let mut sources: Vec<_> = references.iter().flat_map(|r| r.sources.clone()).collect();
    sources.sort_by(|a, b| a.source_hash.cmp(&b.source_hash));
    canonical_hash(serde_json::to_value(sources).unwrap())
}

/// Previously inspected photos only support grouped development evaluation.
/// Overlap is transitive: a multi-day page joins every capture of any of its days.
pub fn development_groups(references: &[Annotation]) -> Result<serde_json::Value> {
    const SEED: &str = "reha-development-folds-v2";
    let sources: Vec<_> = references.iter().flat_map(|r| r.sources.iter()).collect();
    if sources.iter().any(|s| {
        !s.relationships_confirmed
            || s.logical_page.is_empty()
            || s.capture_series.is_empty()
            || s.treatment_days.is_empty()
            || s.treatment_days
                .iter()
                .any(|d| chrono::NaiveDate::parse_from_str(d, "%Y-%m-%d").is_err())
    }) {
        return Err(Error::Invalid(
            "Seiten, Aufnahmeserien und alle Behandlungstage zuerst bestätigen.".into(),
        ));
    }
    let mut groups: Vec<Vec<&ReferenceSource>> = vec![];
    for source in sources {
        let mut joined = vec![source];
        let mut index = 0;
        while index < groups.len() {
            if groups[index].iter().any(|a| {
                joined.iter().any(|b| {
                    a.source_hash == b.source_hash
                        || a.original_hash == b.original_hash
                        || a.logical_page == b.logical_page
                        || a.capture_series == b.capture_series
                        || a.treatment_days
                            .iter()
                            .any(|d| b.treatment_days.contains(d))
                })
            }) {
                joined.extend(groups.remove(index));
                index = 0;
            } else {
                index += 1;
            }
        }
        groups.push(joined);
    }
    if groups.len() < 4 {
        return Err(Error::Invalid("Mindestens vier getrennte Entwicklungsgruppen erforderlich; überlappende Seiten bleiben zusammen.".into()));
    }
    groups.sort_by_key(|g| {
        let mut hashes: Vec<_> = g.iter().map(|s| &s.original_hash).collect();
        hashes.sort();
        crate::hash(&serde_json::to_vec(&serde_json::json!([SEED, hashes])).unwrap())
    });
    let days: serde_json::Map<_,_> = groups.iter().enumerate().map(|(i,g)| {
        let mut hashes: Vec<_> = g.iter().map(|s|s.source_hash.clone()).collect(); hashes.sort();
        let dates: std::collections::BTreeSet<_> = g.iter().flat_map(|s|s.treatment_days.clone()).collect();
        // Sorting makes both input-file order and native/Python iteration irrelevant.
        let mut ordered = g.clone(); ordered.sort_by(|a,b|a.source_hash.cmp(&b.source_hash));
        let captures: Vec<_> = ordered.iter().map(|s|serde_json::json!({"id":s.capture_series,"pages":{&s.logical_page:&s.source_hash}})).collect();
        (format!("development-{:02}",i+1),serde_json::json!({"split":"development","fold":i%4,"grouping_verified":true,"document_hashes":hashes,"treatment_days":dates,"captures":captures}))
    }).collect();
    Ok(
        serde_json::json!({"schema_version":3,"seed":SEED,"kind":"previously_explored_development","grouping_verified":true,"final_holdout_available":false,"relationships_hash":relationships_hash(references),"days":days}),
    )
}
#[derive(Clone, Debug, Default, Serialize, Deserialize)]
pub struct Metrics {
    /// Versioned row identities distinguish relocated omissions/hallucinations
    /// from aggregate counts. Older reports must be rescored before comparison.
    #[serde(default)]
    pub row_identity_version: u32,
    #[serde(default)]
    pub missed_reference_ids: Vec<String>,
    #[serde(default)]
    pub invented_appointments: BTreeMap<String, usize>,
    /// Stable reference-row/field keys let comparisons detect new critical errors
    /// even when the total error count improves. They contain no printed text.
    pub critical_errors: Vec<String>,
    pub critical_false_acceptances: Vec<String>,
    pub printed_fields: BTreeMap<String, usize>,
    pub correct_printed_fields: BTreeMap<String, usize>,
    pub empty_fields: BTreeMap<String, usize>,
    pub correct_empty_fields: BTreeMap<String, usize>,
    pub character_errors: usize,
    pub reference_characters: usize,
    pub character_error_rate: Option<f64>,
    pub row_assignment_errors: usize,
    pub column_assignment_errors: usize,
    pub incorrect_unflagged_fields: usize,
    pub automatically_correct_count: usize,
    pub field_corrections_needed: usize,
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
    if reference.schema_version != 2
        || !reference.verified
        || reference.reviewed_at.is_none()
        || !reference.uncertainty_notes.is_empty()
    {
        return Err(Error::Invalid(
            "Ground truth is provisional; verify against paper before scoring.".into(),
        ));
    }
    validate_reference(reference, true)?;
    if reference.approval_hash.as_ref() != Some(&reference_hash(reference)) {
        return Err(Error::Invalid(
            "Referenz nach Freigabe geändert; erneut bestätigen.".into(),
        ));
    }
    if reference.split == "holdout" && !allow_holdout {
        return Err(Error::Invalid("Final holdout is locked. Use the explicit final-evaluation command after freezing configuration.".into()));
    }
    let mut m = Metrics {
        row_identity_version: 1,
        reference_count: reference.appointments.len(),
        predicted_count: predicted.len(),
        ..Default::default()
    };
    let fields = [
        "date",
        "start",
        "end",
        "title",
        "location",
        "therapist",
        "notes",
    ];
    let costs: Vec<Vec<f64>> = reference
        .appointments
        .iter()
        .map(|truth| {
            predicted
                .iter()
                .map(|p| match_cost(truth, p))
                .chain(std::iter::repeat_n(1000., reference.appointments.len()))
                .collect()
        })
        .collect();
    let matches = assignment(&costs);
    let mut matched_predictions = HashSet::new();
    for (i, truth) in reference.appointments.iter().enumerate() {
        let matched = matches
            .get(i)
            .copied()
            .filter(|j| *j < predicted.len() && costs[i][*j] < 1000.)
            .map(|j| {
                matched_predictions.insert(j);
                &predicted[j]
            });
        if matched.is_some() {
            m.matched_count += 1;
        } else {
            m.missed_reference_ids.push(truth.id.clone());
        }
        let mut full = matched.is_some()
            && fields.iter().all(|f| {
                truth.fields.get(*f).is_some_and(|s| {
                    matches!(s.state, PrintedState::Legible | PrintedState::NotPrinted)
                })
            });
        // Older approved schema-2 references may omit assessments for these
        // auxiliary fields. Nonempty values still participate in exactness.
        if let Some(p) = matched {
            full &= truth.end_date == p.end_date && truth.duration_minutes == p.duration_minutes;
        }
        for field in fields.into_iter().chain(["end_date", "duration_minutes"]) {
            let state = truth.fields.get(field).map(|f| &f.state).or_else(|| {
                // Legacy references still constrain auxiliary values: an invented
                // overnight ending cannot disappear from critical-error accounting.
                if !["end_date", "duration_minutes"].contains(&field) {
                    return None;
                }
                if !crate::review::empty(&crate::review::value(truth, field)) {
                    Some(&PrintedState::Legible)
                } else if matched
                    .is_some_and(|p| !crate::review::empty(&crate::review::value(p, field)))
                {
                    Some(&PrintedState::NotPrinted)
                } else {
                    None
                }
            });
            if !matches!(
                state,
                Some(PrintedState::Legible | PrintedState::NotPrinted)
            ) {
                continue;
            }
            let tv = crate::review::value(truth, field);
            let pv = matched.map(|p| crate::review::value(p, field));
            let correct = pv.as_ref() == Some(&tv);
            full &= correct;
            if state == Some(&PrintedState::NotPrinted) {
                *m.empty_fields.entry(field.into()).or_default() += 1;
                *m.correct_empty_fields.entry(field.into()).or_default() += usize::from(correct);
            } else {
                *m.printed_fields.entry(field.into()).or_default() += 1;
                *m.correct_printed_fields.entry(field.into()).or_default() += usize::from(correct);
                let t = tv
                    .as_str()
                    .map(str::to_owned)
                    .unwrap_or_else(|| tv.to_string());
                let p = pv.as_ref().and_then(|v| v.as_str()).unwrap_or("");
                m.reference_characters += t.chars().count();
                m.character_errors += edit_distance(&t, p);
            }
            if !correct {
                m.field_corrections_needed += 1;
                let critical =
                    ["date", "start", "end", "end_date", "duration_minutes"].contains(&field);
                let error_key = format!("{}:{field}", truth.id);
                if critical {
                    m.critical_errors.push(error_key.clone());
                }
                if let Some(p) = matched {
                    let flagged = !crate::review::field_problems(p).is_empty()
                        || p.issues.iter().any(|i| i.blocking)
                        || !crate::parser::validate(p).is_empty();
                    m.incorrect_unflagged_fields += usize::from(!flagged);
                    let field_flagged = crate::review::field_problems(p)
                        .iter()
                        .chain(p.issues.iter())
                        .chain(crate::parser::validate(p).iter())
                        .any(|issue| {
                            issue.blocking && issue.field.as_deref().is_none_or(|f| f == field)
                        });
                    if critical && !field_flagged {
                        m.critical_false_acceptances.push(error_key);
                    }
                    if ["location", "therapist"].contains(&field) {
                        m.row_assignment_errors +=
                            usize::from(reference.appointments.iter().enumerate().any(|(j, a)| {
                                j != i
                                    && !crate::review::empty(&crate::review::value(a, field))
                                    && Some(crate::review::value(a, field)) == pv
                            }));
                        let other = if field == "location" {
                            "therapist"
                        } else {
                            "location"
                        };
                        m.column_assignment_errors += usize::from(
                            !crate::review::empty(&crate::review::value(truth, other))
                                && Some(crate::review::value(truth, other)) == pv,
                        );
                    }
                }
            }
        }
        if let Some(p) = matched {
            let legible = |field: &str| {
                truth
                    .fields
                    .get(field)
                    .is_some_and(|f| f.state == PrintedState::Legible)
            };
            m.date_correct +=
                usize::from(legible("date") && truth.date == p.date && truth.date.is_some());
            m.start_correct +=
                usize::from(legible("start") && truth.start == p.start && truth.start.is_some());
            // One ending obligation is used in both numerator and denominator.
            m.end_or_duration_correct += usize::from(
                legible("end")
                    && (truth.end.is_some() && truth.end == p.end && truth.end_date == p.end_date)
                    || (truth.end.is_none()
                        && legible("duration_minutes")
                        && truth.duration_minutes.is_some()
                        && truth.duration_minutes == p.duration_minutes),
            );
            m.title_correct +=
                usize::from(legible("title") && !truth.title.is_empty() && truth.title == p.title);
            m.location_correct += usize::from(
                legible("location") && !truth.location.is_empty() && truth.location == p.location,
            );
            m.therapist_correct += usize::from(
                legible("therapist")
                    && !truth.therapist.is_empty()
                    && truth.therapist == p.therapist,
            );
            m.notes_correct +=
                usize::from(legible("notes") && !truth.notes.is_empty() && truth.notes == p.notes);
            m.fully_correct_count += usize::from(full);
            m.automatically_correct_count += usize::from(
                full && crate::review::field_problems(p).is_empty()
                    && !p.issues.iter().any(|i| i.blocking)
                    && crate::parser::validate(p).is_empty(),
            );
        }
    }
    m.character_error_rate = (m.reference_characters > 0)
        .then(|| m.character_errors as f64 / m.reference_characters as f64);
    m.missed_count = m.reference_count - m.matched_count;
    m.invented_count = m.predicted_count - m.matched_count;
    for (index, appointment) in predicted.iter().enumerate() {
        if !matched_predictions.contains(&index) {
            // Generated IDs, detection geometry and issue messages may change
            // between runs without changing the invented calendar facts.
            let fingerprint = canonical_hash(serde_json::json!([
                appointment.date,
                appointment.start,
                appointment.end,
                appointment.end_date,
                appointment.duration_minutes,
                appointment.title,
                appointment.location,
                appointment.therapist,
                appointment.notes,
            ]));
            *m.invented_appointments.entry(fingerprint).or_default() += 1;
        }
    }
    m.unresolved_count = predicted
        .iter()
        .filter(|a| {
            !crate::parser::validate(a).is_empty()
                || !crate::review::field_problems(a).is_empty()
                || a.issues.iter().any(|i| i.blocking)
        })
        .count();
    m.schedule_without_correction = m.fully_correct_count == m.reference_count
        && m.predicted_count == m.reference_count
        && m.unresolved_count == 0;
    m.appointment_precision =
        (m.predicted_count > 0).then(|| m.matched_count as f64 / m.predicted_count as f64);
    m.appointment_recall =
        (m.reference_count > 0).then(|| m.matched_count as f64 / m.reference_count as f64);
    let critical_total: usize = reference
        .appointments
        .iter()
        .map(|a| {
            let printed = |field: &str| {
                a.fields
                    .get(field)
                    .is_some_and(|f| f.state == PrintedState::Legible)
            };
            usize::from(printed("date"))
                + usize::from(printed("start"))
                + usize::from(
                    printed("end")
                        || (a.end.is_none()
                            && a.duration_minutes.is_some()
                            && printed("duration_minutes")),
                )
        })
        .sum();
    m.critical_field_accuracy = (critical_total > 0).then(|| {
        (m.date_correct + m.start_correct + m.end_or_duration_correct) as f64
            / critical_total as f64
    });
    Ok(m)
}
pub fn compare_run(
    reference: &Annotation,
    run: &crate::contracts::PipelineRun,
    allow_holdout: bool,
) -> Result<Metrics> {
    if !reference
        .document_hashes
        .contains(&run.document.source_hash)
    {
        return Err(Error::Invalid(
            "Referenz und Foto stimmen nicht überein.".into(),
        ));
    }
    let mut appointments = run.appointments.clone();
    for a in &mut appointments {
        a.row_polygon = a
            .row_polygon
            .iter()
            .map(|p| crate::geometry::map(&run.page_to_original, p))
            .collect();
    }
    compare(reference, &appointments, allow_holdout)
}
fn edit_distance(a: &str, b: &str) -> usize {
    let b: Vec<_> = b.chars().collect();
    let mut row: Vec<usize> = (0..=b.len()).collect();
    for (i, ca) in a.chars().enumerate() {
        let mut diagonal = row[0];
        row[0] = i + 1;
        for (j, cb) in b.iter().enumerate() {
            let old = row[j + 1];
            row[j + 1] = (row[j] + 1)
                .min(old + 1)
                .min(diagonal + usize::from(ca != *cb));
            diagonal = old;
        }
    }
    row[b.len()]
}
fn match_cost(a: &Appointment, b: &Appointment) -> f64 {
    if !a.row_polygon.is_empty() && !b.row_polygon.is_empty() {
        let (x, y, r, bottom) = crate::geometry::bounds(&a.row_polygon);
        let (nx, ny, nr, nb) = crate::geometry::bounds(&b.row_polygon);
        let vertical = ((y + bottom - ny - nb) / 2.).abs() / (bottom - y).max(nb - ny).max(1.);
        if vertical > 0.9 || x >= nr || nx >= r {
            return 1e6;
        }
        return vertical * 100.;
    }
    if a.date == b.date && a.start.is_some() && a.start == b.start {
        return 150. + if a.title == b.title { 0. } else { 10. };
    }
    if !a.title.is_empty() && a.title == b.title {
        return 250.;
    }
    1e6
}
/// Rectangular Hungarian assignment; dummy columns encode missing predictions.
/// Matching never consults the room or therapist being evaluated.
fn assignment(cost: &[Vec<f64>]) -> Vec<usize> {
    if cost.is_empty() {
        return vec![];
    }
    let n = cost.len();
    let m = cost[0].len();
    let (mut u, mut v, mut p, mut way) = (
        vec![0.; n + 1],
        vec![0.; m + 1],
        vec![0usize; m + 1],
        vec![0usize; m + 1],
    );
    for i in 1..=n {
        p[0] = i;
        let mut j0 = 0;
        let mut minv = vec![f64::INFINITY; m + 1];
        let mut used = vec![false; m + 1];
        loop {
            used[j0] = true;
            let i0 = p[j0];
            let mut delta = f64::INFINITY;
            let mut j1 = 0;
            for j in 1..=m {
                if !used[j] {
                    let cur = cost[i0 - 1][j - 1] - u[i0] - v[j];
                    if cur < minv[j] {
                        minv[j] = cur;
                        way[j] = j0;
                    }
                    if minv[j] < delta {
                        delta = minv[j];
                        j1 = j;
                    }
                }
            }
            for j in 0..=m {
                if used[j] {
                    u[p[j]] += delta;
                    v[j] -= delta;
                } else {
                    minv[j] -= delta;
                }
            }
            j0 = j1;
            if p[j0] == 0 {
                break;
            }
        }
        loop {
            let j1 = way[j0];
            p[j0] = p[j1];
            j0 = j1;
            if j0 == 0 {
                break;
            }
        }
    }
    let mut result = vec![m; n];
    for j in 1..=m {
        if p[j] > 0 {
            result[p[j] - 1] = j - 1;
        }
    }
    result
}
#[cfg(test)]
mod tests {
    use super::*;
    fn approved_fixture() -> Annotation {
        let hash = "a".repeat(64);
        let mut r = Annotation {
            schema_version: 2,
            day_id: "development-01".into(),
            document_hashes: vec![hash.clone()],
            verified: true,
            reviewed_at: Some("2026-09-11".into()),
            split: "development".into(),
            coverage_confirmed: true,
            sources: vec![ReferenceSource {
                source_hash: hash.clone(),
                original_hash: "b".repeat(64),
                width: 1000,
                height: 1000,
                logical_page: "one".into(),
                capture_series: "capture".into(),
                treatment_days: vec!["2026-09-10".into()],
                table_polygon: crate::geometry::rect(0., 0., 1000., 1000.),
                relationships_confirmed: true,
            }],
            ..Default::default()
        };
        for i in 0..2 {
            let mut a = Appointment::empty(format!("a{i}"));
            a.date = Some("2026-09-10".into());
            a.start = Some("08:00".into());
            a.end = Some("08:30".into());
            a.title = "Übung".into();
            a.location = format!("Raum {i}");
            a.therapist = format!("Person {i}");
            a.row_polygon = crate::geometry::rect(0., 100. + i as f64 * 100., 900., 40.);
            for field in [
                "date",
                "start",
                "end",
                "title",
                "location",
                "therapist",
                "notes",
            ] {
                let value = crate::review::value(&a, field);
                let state = if crate::review::empty(&value) {
                    PrintedState::NotPrinted
                } else {
                    PrintedState::Legible
                };
                a.fields.insert(
                    field.into(),
                    crate::contracts::FieldAssessment {
                        state: state.clone(),
                        frame: "original".into(),
                        polygon: a.row_polygon.clone(),
                        confirmed_value: Some(value.clone()),
                        confirmed_at: Some(100),
                        ..Default::default()
                    },
                );
                if state == PrintedState::Legible {
                    r.lines.push(ReferenceLine {
                        id: format!("{i}-{field}"),
                        source_hash: hash.clone(),
                        appointment_id: a.id.clone(),
                        field: field.into(),
                        text: value.as_str().unwrap().into(),
                        polygon: a.row_polygon.clone(),
                        state,
                        error_causes: vec![],
                    });
                }
            }
            r.appointments.push(a);
        }
        r.approval_hash = Some(reference_hash(&r));
        r
    }
    #[test]
    fn duration_only_reference_has_bounded_accuracy_and_catches_auxiliary_errors() {
        let mut r = approved_fixture();
        for a in &mut r.appointments {
            a.end = None;
            a.duration_minutes = Some(30);
            let end = a.fields.get_mut("end").unwrap();
            end.state = PrintedState::NotPrinted;
            end.confirmed_value = Some(serde_json::Value::Null);
            a.fields.insert(
                "duration_minutes".into(),
                crate::contracts::FieldAssessment {
                    state: PrintedState::Legible,
                    frame: "original".into(),
                    polygon: a.row_polygon.clone(),
                    confirmed_value: Some(serde_json::json!(30)),
                    confirmed_at: Some(100),
                    ..Default::default()
                },
            );
            r.lines.push(ReferenceLine {
                id: format!("{}-duration", a.id),
                source_hash: r.document_hashes[0].clone(),
                appointment_id: a.id.clone(),
                field: "duration_minutes".into(),
                text: "30".into(),
                polygon: a.row_polygon.clone(),
                state: PrintedState::Legible,
                error_causes: vec![],
            });
        }
        r.lines.retain(|line| line.field != "end");
        r.approval_hash = Some(reference_hash(&r));
        let metrics = compare(&r, &r.appointments, false).unwrap();
        assert_eq!(metrics.critical_field_accuracy, Some(1.));
        assert!(metrics.schedule_without_correction);
        let mut predicted = r.appointments.clone();
        predicted[0].duration_minutes = Some(45);
        predicted[1].end_date = Some("2026-09-11".into());
        let metrics = compare(&r, &predicted, false).unwrap();
        assert_eq!(metrics.fully_correct_count, 0);
        assert!(metrics.critical_errors.contains(&"a1:end_date".into()));
        assert!(!metrics.schedule_without_correction);
    }
    #[test]
    fn unrelated_uncertain_room_does_not_hide_a_falsely_accepted_time() {
        let r = approved_fixture();
        let mut predicted = r.appointments.clone();
        predicted.iter_mut().for_each(|a| a.fields.clear());
        predicted[0].start = Some("08:05".into());
        predicted[0].issues.push(crate::contracts::Issue {
            code: "room_unknown".into(),
            field: Some("location".into()),
            message: "Raum unleserlich".into(),
            blocking: true,
        });
        let m = compare(&r, &predicted, false).unwrap();
        assert_eq!(m.critical_errors, ["a0:start"]);
        assert_eq!(m.critical_false_acceptances, ["a0:start"]);
        predicted[0].issues[0].field = Some("start".into());
        let m = compare(&r, &predicted, false).unwrap();
        assert_eq!(m.critical_errors, ["a0:start"]);
        assert!(m.critical_false_acceptances.is_empty());
    }
    #[test]
    fn geometry_matching_exposes_swapped_rooms_with_identical_times() {
        let r = approved_fixture();
        let mut predicted = r.appointments.clone();
        predicted[0].location = "Raum 1".into();
        predicted[1].location = "Raum 0".into();
        predicted.iter_mut().for_each(|a| a.fields.clear());
        let m = compare(&r, &predicted, false).unwrap();
        assert_eq!(m.matched_count, 2);
        assert_eq!(m.location_correct, 0);
        assert_eq!(m.row_assignment_errors, 2);
        assert_eq!(m.incorrect_unflagged_fields, 2);
        assert_eq!(m.printed_fields["location"], 2);
        assert_eq!(m.empty_fields["notes"], 2);
        assert_eq!(m.notes_correct, 0);
    }
    #[test]
    fn missing_predictions_remain_in_denominators_and_edits_revoke_approval() {
        let mut r = approved_fixture();
        let m = compare(&r, &[], false).unwrap();
        assert_eq!(m.missed_count, 2);
        assert_eq!(m.row_identity_version, 1);
        assert_eq!(m.missed_reference_ids, ["a0", "a1"]);
        assert!(m.invented_appointments.is_empty());
        assert_eq!(m.printed_fields["therapist"], 2);
        assert_eq!(m.appointment_recall, Some(0.));
        assert!(!m.schedule_without_correction);
        r.lines[0].polygon[0].x += 1.;
        assert!(compare(&r, &[], false).is_err());
    }
    #[test]
    fn row_identities_retain_unmatched_references_and_duplicate_invented_facts() {
        let r = approved_fixture();
        let mut invented = r.appointments[0].clone();
        invented.id = "unstable-detection-id".into();
        invented.row_polygon = crate::geometry::rect(0., 900., 900., 40.);
        invented.title = "Erfundener Termin".into();
        let first = compare(&r, &[r.appointments[0].clone(), invented.clone()], false).unwrap();
        assert_eq!(first.missed_reference_ids, ["a1"]);
        assert_eq!(first.invented_count, 1);
        let fingerprint = first.invented_appointments.keys().next().unwrap();
        assert_eq!(fingerprint.len(), 64);

        invented.id = "new-id-for-same-facts".into();
        invented.row_polygon = crate::geometry::rect(0., 950., 900., 40.);
        invented.fields.clear();
        let second = compare(
            &r,
            &[
                invented.clone(),
                r.appointments[0].clone(),
                invented.clone(),
            ],
            false,
        )
        .unwrap();
        assert_eq!(second.invented_count, 2);
        assert_eq!(second.invented_appointments[fingerprint], 2);
        assert_eq!(second.invented_appointments.len(), 1);
        assert_eq!(second.missed_reference_ids, first.missed_reference_ids);

        invented.location = "Anderer Raum".into();
        let changed = compare(&r, &[r.appointments[0].clone(), invented], false).unwrap();
        assert_eq!(changed.invented_count, first.invented_count);
        assert_ne!(changed.invented_appointments, first.invented_appointments);
        let relocated = compare(&r, &[r.appointments[1].clone()], false).unwrap();
        assert_eq!(relocated.missed_count, first.missed_count);
        assert_eq!(relocated.missed_reference_ids, ["a0"]);
    }
    #[test]
    fn legacy_metrics_remain_readable_without_claiming_row_identity_evidence() {
        let r = approved_fixture();
        let mut json = serde_json::to_value(compare(&r, &[], false).unwrap()).unwrap();
        let object = json.as_object_mut().unwrap();
        for key in [
            "row_identity_version",
            "missed_reference_ids",
            "invented_appointments",
        ] {
            object.remove(key);
        }
        let legacy: Metrics = serde_json::from_value(json).unwrap();
        assert_eq!(legacy.row_identity_version, 0);
        assert_eq!(legacy.missed_count, 2);
        assert!(legacy.missed_reference_ids.is_empty());
    }
    #[test]
    fn unreadable_fields_do_not_count_as_correct_empty_fields() {
        let mut r = approved_fixture();
        let a = &mut r.appointments[0];
        a.therapist.clear();
        let f = a.fields.get_mut("therapist").unwrap();
        f.state = PrintedState::Cropped;
        f.confirmed_value = Some(serde_json::json!(""));
        r.approval_hash = Some(reference_hash(&r));
        let m = compare(&r, &r.appointments, false).unwrap();
        assert_eq!(m.printed_fields["therapist"], 1);
        assert!(!m.empty_fields.contains_key("therapist"));
        assert!(!m.schedule_without_correction);
    }
    #[test]
    fn cross_language_number_hash_does_not_depend_on_json_number_spelling() {
        assert_eq!(
            canonical_hash(serde_json::json!({"x":1})),
            canonical_hash(serde_json::json!({"x":1.0}))
        );
        let r = approved_fixture();
        let mut value = serde_json::to_value(&r).unwrap();
        value["sources"][0]["table_polygon"][0]["x"] = serde_json::json!(0);
        assert_eq!(
            reference_hash(&r),
            reference_hash(&serde_json::from_value(value).unwrap())
        );
    }
    #[test]
    fn matching_never_uses_room_or_therapist() {
        let mut a = Appointment::empty("a".into());
        a.title = "Therapie".into();
        a.location = "A1".into();
        a.therapist = "Person A".into();
        let mut b = a.clone();
        b.location = "Wrong".into();
        b.therapist = "Wrong".into();
        assert_eq!(match_cost(&a, &b), match_cost(&a, &a));
        assert_eq!(
            assignment(&[vec![10., 0., 1000.], vec![0., 10., 1000.]]),
            vec![1, 0]
        );
    }
    #[test]
    fn unicode_character_distance() {
        assert_eq!(edit_distance("Müller", "Muler"), 2);
    }
    #[test]
    fn provisional_and_legacy_references_are_locked() {
        assert!(compare(&Annotation::default(), &[], false).is_err());
        assert!(compare(
            &Annotation {
                schema_version: 1,
                verified: true,
                reviewed_at: Some("old".into()),
                ..Default::default()
            },
            &[],
            false
        )
        .is_err());
    }
}
