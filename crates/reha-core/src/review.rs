//! Review and completion rules shared by every interface. No model can approve a value.
use crate::{calendar, contracts::*, Error, Result};
use std::collections::{BTreeMap, HashSet};

pub const FIELDS: &[&str] = &[
    "date",
    "start",
    "end",
    "end_date",
    "duration_minutes",
    "title",
    "location",
    "therapist",
    "notes",
    "clinic",
    "department",
    "address",
    "contact",
    "treatment_code",
    "preparation",
    "document_reference",
    "appointment_notes",
];
pub const COMPLETABLE: &[&str] = &["duration_minutes", "location", "therapist", "preparation"];
pub fn value(a: &Appointment, field: &str) -> serde_json::Value {
    let json = serde_json::to_value(a).expect("appointment serialization");
    json.get(field)
        .or_else(|| json["metadata"].get(field))
        .cloned()
        .unwrap_or_default()
}
pub fn set_value(a: &mut Appointment, field: &str, value: serde_json::Value) -> Result<()> {
    if !FIELDS.contains(&field) {
        return Err(Error::Invalid("Unbekanntes Feld.".into()));
    }
    let mut json = serde_json::to_value(&*a)?;
    if json.get(field).is_some() {
        json[field] = value;
    } else {
        json["metadata"][field] = value;
    }
    *a = serde_json::from_value(json)?;
    Ok(())
}
pub fn empty(value: &serde_json::Value) -> bool {
    value.is_null() || value.as_str().is_some_and(|v| v.trim().is_empty())
}
pub fn values_hash(a: &Appointment) -> String {
    let values: BTreeMap<_, _> = FIELDS
        .iter()
        .map(|field| (*field, value(a, field)))
        .chain([("included", serde_json::json!(a.included))])
        .collect();
    crate::hash(&serde_json::to_vec(&values).expect("value serialization"))
}
pub fn approved(a: &Appointment) -> bool {
    a.included
        && a.approval
            .as_ref()
            .is_some_and(|s| s.values_hash == values_hash(a))
}
pub fn migrate(run: &mut PipelineRun) -> Result<()> {
    if run.schema_version > SCHEMA_VERSION || run.schema_version == 0 {
        return Err(Error::Invalid("Nicht unterstützte Datenversion.".into()));
    }
    if run.schema_version == 1 {
        for a in &mut run.appointments {
            for field in FIELDS {
                if !empty(&value(a, field)) {
                    a.origins.entry((*field).into()).or_insert(FieldOrigin {
                        // Old contracts did not track edits: protect all retained values.
                        kind: "manual".into(),
                        evidence: a.provenance.get(*field).cloned().unwrap_or_default(),
                        source: "Übernommener Bestandswert (vor Feldherkunft)".into(),
                    });
                }
            }
            if run.review_confirmed
                && a.included
                && calendar::event_values(a, &run.config.timezone, None).is_ok()
            {
                a.approval = Some(ApprovalSnapshot {
                    values_hash: values_hash(a),
                    approved_at: run.document.imported_at,
                });
            }
        }
        run.schema_version = SCHEMA_VERSION;
        run.document.schema_version = SCHEMA_VERSION;
    }
    Ok(())
}
pub fn approve_selection(run: &mut PipelineRun, ids: &[String], now: i64) -> Result<()> {
    let unique: HashSet<_> = ids.iter().collect();
    if unique.len() != ids.len() {
        return Err(Error::Invalid("Doppelte Auswahl.".into()));
    }
    for id in ids {
        let a = run
            .appointments
            .iter()
            .find(|a| &a.id == id)
            .ok_or_else(|| Error::Invalid("Termin fehlt.".into()))?;
        if !a.included {
            return Err(Error::Invalid("Ausgeschlossener Termin.".into()));
        }
        calendar::event_values(a, &run.config.timezone, None)?;
    }
    for a in &mut run.appointments {
        if unique.contains(&a.id) {
            a.approval = Some(ApprovalSnapshot {
                values_hash: values_hash(a),
                approved_at: now,
            });
        }
    }
    run.review_confirmed = run.appointments.iter().filter(|a| a.included).all(approved);
    Ok(())
}
/// Do not trust origin, approval, or event-binding claims received from the webview.
pub fn edit(old: Option<&Appointment>, mut next: Appointment) -> Result<Appointment> {
    let blank = Appointment::empty(next.id.clone());
    let old = old.unwrap_or(&blank);
    let requested_suggestions = next.suggestions.clone();
    next.origins = old.origins.clone();
    next.approval = old.approval.clone();
    next.calendar_event_id = old.calendar_event_id.clone();
    next.ics_event_id = old.ics_event_id.clone();
    next.calendar_saved_hash = old.calendar_saved_hash.clone();
    next.ics_exported_hash = old.ics_exported_hash.clone();
    next.section_id = old.section_id.clone();
    next.provenance = old.provenance.clone();
    next.suggestions = old.suggestions.clone();
    if normalized(&next.metadata.clinic) != normalized(&old.metadata.clinic)
        || normalized(&next.title) != normalized(&old.title)
    {
        next.suggestions.retain(|s| s.status != "pending");
    }
    for suggestion in &mut next.suggestions {
        if suggestion.status == "pending" {
            if let Some(request) = requested_suggestions.iter().find(|s| s.id == suggestion.id) {
                if request.status == "rejected" {
                    suggestion.status = "rejected".into();
                }
                if request.status == "accepted" {
                    // Acceptance is checked against the proposed value below.
                    suggestion.status = "accepted".into();
                }
            }
        }
    }
    for field in FIELDS {
        let v = value(&next, field);
        if v != value(old, field) {
            let suggestion = next
                .suggestions
                .iter()
                .find(|s| s.field == *field && s.status == "accepted" && s.value == v);
            next.origins.insert(
                (*field).into(),
                FieldOrigin {
                    kind: if suggestion.is_some() {
                        "suggested"
                    } else {
                        "manual"
                    }
                    .into(),
                    evidence: vec![],
                    source: suggestion
                        .map(|s| s.source.clone())
                        .unwrap_or_else(|| "Manuell eingegeben".into()),
                },
            );
        }
    }
    for s in &next.suggestions {
        if s.status == "accepted"
            && value(&next, &s.field) != s.value
            && old
                .suggestions
                .iter()
                .any(|o| o.id == s.id && o.status == "pending")
        {
            return Err(Error::Invalid(
                "Vorschlag und übernommener Wert stimmen nicht überein.".into(),
            ));
        }
    }
    if values_hash(&next) != values_hash(old) {
        next.approval = None;
    }
    Ok(next)
}
fn normalized(s: &str) -> String {
    s.split_whitespace()
        .collect::<Vec<_>>()
        .join(" ")
        .to_lowercase()
}
pub fn validate_default(d: &CompletionDefault) -> Result<()> {
    if d.clinic.trim().is_empty()
        || d.treatment.trim().is_empty()
        || !COMPLETABLE.contains(&d.field.as_str())
        || empty(&d.value)
    {
        return Err(Error::Invalid(
            "Vorgaben brauchen Klinik, Behandlung und einen erlaubten Ergänzungswert.".into(),
        ));
    }
    if d.field == "duration_minutes" {
        if !d.value.as_u64().is_some_and(|v| (1..=1440).contains(&v)) {
            return Err(Error::Invalid("Dauer: 1–1440 Minuten.".into()));
        }
    } else if !d.value.as_str().is_some_and(|s| s.len() <= 2000) {
        return Err(Error::Invalid("Ungültiger Ergänzungswert.".into()));
    }
    Ok(())
}
pub fn suggest(run: &mut PipelineRun, defaults: &[CompletionDefault], history: &[ImportRecord]) {
    for a in &mut run.appointments {
        if a.metadata.clinic.trim().is_empty() {
            continue;
        }
        let mut candidates: Vec<(String, serde_json::Value, String)> = vec![];
        for d in defaults.iter().filter(|d| {
            normalized(&d.clinic) == normalized(&a.metadata.clinic)
                && normalized(&d.treatment) == normalized(&a.title)
                && validate_default(d).is_ok()
        }) {
            candidates.push((
                d.field.clone(),
                d.value.clone(),
                format!("Vorgabe: {} / {}", d.clinic, d.treatment),
            ));
        }
        for record in history.iter().filter(|r| {
            r.status == "saved" && normalized(&r.approved.title) == normalized(&a.title)
        }) {
            let note = |label: &str| {
                record
                    .approved
                    .notes
                    .lines()
                    .find_map(|l| l.strip_prefix(label))
                    .unwrap_or("")
                    .trim()
            };
            if normalized(note("Klinik: ")) != normalized(&a.metadata.clinic) {
                continue;
            }
            let source = format!("Bestätigter Verlauf: {}", record.approved.start_utc);
            if let (Ok(s), Ok(e)) = (
                chrono::DateTime::parse_from_rfc3339(&record.approved.start_utc),
                chrono::DateTime::parse_from_rfc3339(&record.approved.end_utc),
            ) {
                candidates.push((
                    "duration_minutes".into(),
                    serde_json::json!((e - s).num_minutes()),
                    source.clone(),
                ));
            }
            for (field, value) in [
                (
                    "location",
                    if note("Raum: ").is_empty() {
                        record.approved.location.as_str()
                    } else {
                        note("Raum: ")
                    },
                ),
                ("therapist", note("Therapeut: ")),
                ("preparation", note("Vorbereitung: ")),
            ] {
                candidates.push((field.into(), serde_json::json!(value), source.clone()));
            }
        }
        for (field, v, source) in candidates {
            if !empty(&value(a, &field))
                || empty(&v)
                || (field == "duration_minutes" && a.end.is_some())
            {
                continue;
            }
            let id = crate::hash(
                format!(
                    "{}|{}|{field}|{v}|{source}",
                    normalized(&a.metadata.clinic),
                    normalized(&a.title)
                )
                .as_bytes(),
            );
            if !a.suggestions.iter().any(|s| s.id == id) {
                a.suggestions.push(CompletionSuggestion {
                    id,
                    field,
                    value: v,
                    source,
                    status: "pending".into(),
                });
            }
        }
    }
}
