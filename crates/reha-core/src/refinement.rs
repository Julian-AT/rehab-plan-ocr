//! Bounded, source-linked local rereading. Conflicts never compete on confidence score.
use crate::geometry;
use crate::{contracts::*, review, Result};
use std::collections::BTreeMap;
use std::collections::HashSet;

pub type Reading = RefinementReading;

/// A field crop can contain a clipped fragment of its neighboring column.
/// Keep that evidence for review, but never join it into an asserted field value.
fn contained_field_text(
    observations: &[Observation],
    regions: &[Region],
    width: u32,
    height: u32,
) -> Option<String> {
    if observations.is_empty() {
        return None;
    }
    for observation in observations {
        if observation.region_ids.is_empty() {
            return None;
        }
        for id in &observation.region_ids {
            let region = regions.iter().find(|r| &r.id == id)?;
            if region.polygon.len() < 4
                || region.polygon.iter().any(|p| {
                    !p.x.is_finite()
                        || !p.y.is_finite()
                        || p.x <= 1.0
                        || p.x >= f64::from(width) - 1.0
                        || p.y < 0.0
                        || p.y > f64::from(height)
                })
            {
                return None;
            }
        }
    }
    let text = observations
        .iter()
        .map(|o| o.text.as_str())
        .collect::<Vec<_>>()
        .join(" ");
    (!text.trim().is_empty()).then_some(text)
}

/// Refresh the version-5/6 column checks from retained OCR when row identities
/// stay unambiguous. Structural changes still require a full explicit reprocess.
pub fn refresh_cached_mapping(run: &mut PipelineRun) -> Result<bool> {
    if ![5, 6, 7, 8].contains(&run.extraction_version) || run.observations.is_empty() {
        return Ok(false);
    }
    let observations: Vec<_> = run
        .observations
        .iter()
        .filter(|o| !o.id.starts_with("reread-"))
        .cloned()
        .collect();
    let source_regions: HashSet<_> = observations.iter().flat_map(|o| &o.region_ids).collect();
    let regions: Vec<_> = run
        .regions
        .iter()
        .filter(|r| source_regions.contains(&r.id))
        .cloned()
        .collect();
    let (appointments, issues, unassigned) =
        crate::parser::extract(&run.document.id, &observations, &regions);
    if appointments.len() != run.appointments.len() {
        return Ok(false);
    }
    let mut next = run.clone();
    next.appointments = appointments;
    next.extraction_version = crate::parser::EXTRACTION_VERSION;
    next.sections = crate::parser::sections(&observations, &regions);
    next.unassigned = unassigned;
    // Preserve capture-quality warnings, including clipping added after parsing.
    for issue in issues {
        if !next.issues.contains(&issue) {
            next.issues.push(issue);
        }
    }
    preserve_review(run, &mut next)?;
    let old_ids: HashSet<_> = run.appointments.iter().map(|a| &a.id).collect();
    if next.appointments.len() != old_ids.len()
        || next.appointments.iter().any(|a| !old_ids.contains(&a.id))
    {
        return Ok(false);
    }
    for a in &mut next.appointments {
        let old = run.appointments.iter().find(|old| old.id == a.id).unwrap();
        for (field, assessment) in &old.fields {
            for reason in assessment
                .reasons
                .iter()
                .filter(|r| r.starts_with("Text berührt den Bildrand"))
            {
                let f = a.fields.entry(field.clone()).or_default();
                f.state = PrintedState::Cropped;
                if !f.reasons.contains(reason) {
                    f.reasons.push(reason.clone());
                }
            }
        }
    }
    next.refinement_readings.clear();
    next.refinement_attempts.clear();
    next.review_confirmed = false;
    next.complete_page_confirmed = false;
    next.stages.push(Stage {
        name: "column_mapping_refresh".into(), status: "complete".into(), duration_ms: 0,
        detail: "Spaltenprüfung aus gespeichertem OCR aktualisiert. Manuelle Angaben und Kalenderbindungen erhalten; alte Nachlesungen verworfen. Unklare Felder erneut am Foto prüfen.".into(),
        artifacts: vec![],
    });
    *run = next;
    Ok(true)
}
/// Repeated preprocessing uses the same model and supplies candidates, never proof.
/// Printed contradictions stay visible and block approval; edits always win.
pub fn apply_readings(run: &mut PipelineRun, readings: &[Reading]) -> Result<()> {
    for a in &mut run.appointments {
        for field in review::FIELDS {
            if review::field_confirmed(a, field)
                || a.origins
                    .get(*field)
                    .is_some_and(|o| ["manual", "suggested"].contains(&o.kind.as_str()))
            {
                continue;
            }
            let matches: Vec<_> = readings
                .iter()
                .filter(|r| {
                    r.appointment_id == a.id
                        && r.field == *field
                        && !r.evidence.is_empty()
                        && !review::empty(&r.value)
                })
                .collect();
            if matches.is_empty() {
                continue;
            }
            let distinct: HashSet<_> = matches.iter().map(|r| r.value.to_string()).collect();

            let current = review::value(a, field);
            let conflicting = distinct.len() > 1
                || (!review::empty(&current) && matches.iter().any(|r| r.value != current));
            if conflicting {
                let issue = Issue::new(
                    "reread_conflict",
                    "Widersprüchliche Lesarten: mit dem Foto vergleichen.",
                    Some(field),
                    true,
                );
                if !a.issues.contains(&issue) {
                    a.issues.push(issue);
                    let f = a.fields.entry((*field).into()).or_default();
                    f.state = PrintedState::Contradictory;
                    f.reasons.push("Widersprüchliche Nachlesungen.".into());
                }
                a.approval = None;
            } else if review::empty(&current) {
                let mut candidate = a.clone();
                review::set_value(&mut candidate, field, matches[0].value.clone())?;
                // Validate the specific field; unrelated missing fields remain pending.
                if crate::parser::validate(&candidate)
                    .iter()
                    .any(|i| i.field.as_deref() == Some(field) && i.blocking)
                {
                    continue;
                }
                *a = candidate;
                let evidence = matches
                    .iter()
                    .flat_map(|r| r.evidence.clone())
                    .collect::<Vec<_>>();
                a.provenance.insert((*field).into(), evidence.clone());
                a.origins.insert(
                    (*field).into(),
                    FieldOrigin {
                        kind: "printed".into(),
                        evidence,
                        source: "Lokale Nachprüfung am Foto".into(),
                    },
                );
                a.fields
                    .entry((*field).into())
                    .or_default()
                    .reasons
                    .push("Nachlesung desselben Modells: Wert am Foto bestätigen.".into());
                a.approval = None;
            }
        }
        a.issues.retain(|i| {
            ![
                "missing_date",
                "missing_start",
                "missing_end",
                "invalid_end",
                "overnight_confirmation",
                "missing_title",
            ]
            .contains(&i.code.as_str())
        });
        a.issues.extend(crate::parser::validate(a));
    }
    Ok(())
}
pub fn appointment_bounds(a: &Appointment, run: &PipelineRun) -> Option<(f64, f64, f64, f64)> {
    if !a.row_polygon.is_empty() {
        return Some(geometry::bounds(&a.row_polygon));
    }
    let ids: HashSet<_> = a
        .provenance
        .iter()
        .filter(|(f, _)| {
            !["date", "clinic", "department", "address", "contact"].contains(&f.as_str())
        })
        .flat_map(|(_, ids)| ids)
        .collect();
    let region_ids: HashSet<_> = run
        .observations
        .iter()
        .filter(|o| ids.contains(&o.id))
        .flat_map(|o| &o.region_ids)
        .collect();
    let points: Vec<_> = run
        .regions
        .iter()
        .filter(|r| region_ids.contains(&r.id))
        .flat_map(|r| r.polygon.clone())
        .collect();
    (!points.is_empty()).then(|| geometry::bounds(&points))
}

#[cfg(feature = "onnx")]
pub fn refine(
    engine: &mut crate::ocr::OnnxEngine,
    run: &mut PipelineRun,
    dir: &std::path::Path,
    cancel: &std::sync::atomic::AtomicBool,
    deadline: std::time::Instant,
) -> Result<()> {
    refine_with_original(engine, run, dir, cancel, deadline, None)
}

/// Reuse original pixels from the initial pass. Explicit later retries still
/// load the retained photograph through `refine`.
#[cfg(feature = "onnx")]
pub(crate) fn refine_with_original(
    engine: &mut crate::ocr::OnnxEngine,
    run: &mut PipelineRun,
    dir: &std::path::Path,
    cancel: &std::sync::atomic::AtomicBool,
    deadline: std::time::Instant,
    original: Option<&image::RgbImage>,
) -> Result<()> {
    refine_with_reader(
        run,
        dir,
        cancel,
        deadline,
        original,
        &mut |crop, config, cancel, dir, deadline| {
            engine.recognize_until(crop, config, cancel, dir, deadline)
        },
    )
}

/// Both OCR readers return the same source-linked observations. Confidence never
/// resolves disagreement between printed values or overrides a confirmed field.
pub fn refine_with_reader<F>(
    run: &mut PipelineRun,
    dir: &std::path::Path,
    cancel: &std::sync::atomic::AtomicBool,
    deadline: std::time::Instant,
    original: Option<&image::RgbImage>,
    recognize: &mut F,
) -> Result<()>
where
    F: FnMut(
        &image::RgbImage,
        &PipelineConfig,
        &std::sync::atomic::AtomicBool,
        &std::path::Path,
        Option<std::time::Instant>,
    ) -> Result<(Vec<Region>, Vec<Observation>, Vec<Stage>)>,
{
    use std::{sync::atomic::Ordering, time::Instant};
    let started = Instant::now();
    let initial_attempts = run.refinement_attempts.len();
    let available = || !cancel.load(Ordering::Relaxed) && Instant::now() < deadline;
    let targets = crate::refinement_targets::schedule(run);
    let mut readings = vec![];
    let mut discovered: BTreeMap<String, Vec<(String, Appointment)>> = BTreeMap::new();
    let loaded;
    let original = if available() && !targets.is_empty() {
        if let Some(original) = original {
            Some(original)
        } else {
            loaded = image::open(dir.join("original.png"))?.into_rgb8();
            Some(&loaded)
        }
    } else {
        None
    };
    // Visit every selected critical crop before spending time on a second variant.
    let work: Vec<_> = if run.config.prioritized_rereads {
        (0..2)
            .flat_map(|variant| targets.iter().map(move |target| (variant, target)))
            .collect()
    } else {
        targets
            .iter()
            .flat_map(|target| (0..2).map(move |variant| (variant, target)))
            .collect()
    };
    let mut adjacent_crop = None;
    for (variant, target) in work {
        if run.config.prioritized_rereads && variant == 1 && !target.needs_contrast(run, &readings)
        {
            continue;
        }
        let Some(original) = &original else {
            break;
        };
        let polygon = &target.polygon;
        let (x, y, _, b) = geometry::bounds(polygon);
        let field = &target.field;
        let points: Vec<_> = polygon
            .iter()
            .map(|p| geometry::map(&run.page_to_original, p))
            .collect();
        if !available() {
            break;
        }
        // The exact field quadrilateral is rectified from original pixels. An
        // enclosing axis-aligned box can contain the neighboring name column.
        let cached = if variant == 1 && !run.config.prioritized_rereads {
            adjacent_crop.take()
        } else {
            adjacent_crop = None;
            None
        };
        let crop_result = cached
            .map(Ok)
            .unwrap_or_else(|| geometry::rectify_with_transform(original, &points));
        let Ok((source_crop, crop_to_original)) = crop_result else {
            continue;
        };
        if variant == 0 && !run.config.prioritized_rereads {
            adjacent_crop = Some((source_crop.clone(), crop_to_original));
        }
        {
            if !available() {
                break;
            }
            let attempt_started = Instant::now();
            let mut crop = source_crop;
            let scale = if variant == 0 { 1. } else { 1.5 };
            if variant == 1 {
                crop = image::imageops::contrast(&crop, 20.);
                crop = image::imageops::resize(
                    &crop,
                    (crop.width() as f64 * scale) as u32,
                    (crop.height() as f64 * scale) as u32,
                    image::imageops::FilterType::CatmullRom,
                );
            }
            let to_original = geometry::multiply(
                &crop_to_original,
                &[1. / scale, 0., 0., 0., 1. / scale, 0., 0., 0., 1.],
            );
            let to_page = geometry::multiply(&run.original_to_page, &to_original);
            let id = format!("reread-{:04}", run.refinement_attempts.len());
            let mut attempt = RefinementAttempt {
                id: id.clone(),
                target_ids: target.appointments.clone(),
                reason: target.reason().into(),
                variant: if variant == 0 {
                    "original-context"
                } else {
                    "contrast20-scale1.5"
                }
                .into(),
                crop_to_original: to_original,
                crop_to_page: to_page,
                width: crop.width(),
                height: crop.height(),
                duration_ms: 0,
                status: "complete".into(),
                observation_ids: vec![],
                detail: String::new(),
            };
            let mut config = run.config.clone();
            config.detailed_debug = false; // artifacts are written under unique attempt names below
            config.detector_side = 1920;
            match recognize(&crop, &config, cancel, dir, Some(deadline)) {
                Ok((mut regions, mut observations, stages)) => {
                    let complete = stages.iter().all(|s| s.status == "complete");
                    if !complete {
                        attempt.status = "partial".into();
                    }
                    let field_text = field.as_ref().and_then(|_| {
                        contained_field_text(&observations, &regions, crop.width(), crop.height())
                    });
                    if field.is_some() && !observations.is_empty() && field_text.is_none() {
                        attempt.detail = "Text am Spaltenrand oder ohne vollständige Geometrie: keine Feldübernahme.".into();
                    }
                    for region in &mut regions {
                        region.id = format!("{id}-{}", region.id);
                        region.parent = None;
                        region.polygon = region
                            .polygon
                            .iter()
                            .map(|p| geometry::map(&to_page, p))
                            .collect();
                    }
                    for o in &mut observations {
                        o.id = format!("{id}-{}", o.id);
                        o.region_ids = o.region_ids.iter().map(|r| format!("{id}-{r}")).collect();
                    }
                    attempt.observation_ids = observations.iter().map(|o| o.id.clone()).collect();
                    if complete && field.is_some() {
                        let text = field_text.as_deref().unwrap_or_default();
                        let value = if field.as_deref() == Some("date") {
                            field_text
                                .as_ref()
                                .and_then(|_| crate::parser::heading_date(&observations, &regions))
                                .map(serde_json::Value::String)
                        } else if matches!(field.as_deref(), Some("start" | "end")) {
                            crate::parser::clock_value(text).map(serde_json::Value::String)
                        } else {
                            (!text.trim().is_empty()).then_some(serde_json::json!(text))
                        };
                        if let Some(value) = value {
                            for appointment_id in &target.appointments {
                                readings.push(Reading {
                                    appointment_id: appointment_id.clone(),
                                    field: field.clone().unwrap(),
                                    value: value.clone(),
                                    evidence: attempt.observation_ids.clone(),
                                    attempt: id.clone(),
                                });
                            }
                        }
                    } else if complete {
                        let inside = |o: &Observation| {
                            let pts: Vec<_> = run
                                .regions
                                .iter()
                                .filter(|r| o.region_ids.contains(&r.id))
                                .flat_map(|r| r.polygon.clone())
                                .collect();
                            let (l, t, r, b) = geometry::bounds(&pts);
                            let center = Point {
                                x: (l + r) / 2.,
                                y: (t + b) / 2.,
                            };
                            let p = geometry::map(
                                &geometry::inverse(&to_page).unwrap_or(geometry::IDENTITY),
                                &center,
                            );
                            p.x >= 0.
                                && p.y >= 0.
                                && p.x < crop.width() as f64
                                && p.y < crop.height() as f64
                        };
                        let mut combined: Vec<_> = run
                            .observations
                            .iter()
                            .filter(|o| !o.id.starts_with("reread-") && !inside(o))
                            .cloned()
                            .collect();
                        combined.extend(observations.clone());
                        let mut all_regions = run.regions.clone();
                        all_regions.extend(regions.clone());
                        let (candidates, _, _) =
                            crate::parser::extract(&run.document.id, &combined, &all_regions);
                        let view = PipelineRun {
                            observations: combined,
                            regions: all_regions,
                            ..run.clone()
                        };
                        let candidates: Vec<_> = candidates
                            .into_iter()
                            .filter(|a| {
                                appointment_bounds(a, &view)
                                    .is_some_and(|(_, t, _, bottom)| t < b && bottom > y)
                            })
                            .collect();
                        let overlaps = |old: &Appointment, new: &Appointment| match (
                            appointment_bounds(old, run),
                            appointment_bounds(new, &view),
                        ) {
                            (Some((l, t, r, b)), Some((nl, nt, nr, nb))) => {
                                let area = (r - l) * (b - t);
                                let other = (nr - nl) * (nb - nt);
                                area > 0.
                                    && other > 0.
                                    && (r.min(nr) - l.max(nl)).max(0.)
                                        * (b.min(nb) - t.max(nt)).max(0.)
                                        / area.min(other)
                                        > 0.5
                            }
                            _ => false,
                        };
                        for target_id in &target.appointments {
                            let Some(old) = run.appointments.iter().find(|a| &a.id == target_id)
                            else {
                                continue;
                            };
                            let matched: Vec<_> =
                                candidates.iter().filter(|a| overlaps(old, a)).collect();
                            if matched.len() == 1
                                && run
                                    .appointments
                                    .iter()
                                    .filter(|a| overlaps(a, matched[0]))
                                    .count()
                                    == 1
                            {
                                let candidate = matched[0];
                                for field in review::FIELDS {
                                    let evidence = candidate
                                        .provenance
                                        .get(*field)
                                        .cloned()
                                        .unwrap_or_default();
                                    if evidence.iter().any(|e| e.starts_with(&id)) {
                                        readings.push(Reading {
                                            appointment_id: target_id.clone(),
                                            field: (*field).into(),
                                            value: review::value(candidate, field),
                                            evidence,
                                            attempt: id.clone(),
                                        });
                                    }
                                }
                            } else {
                                attempt.detail =
                                    "Zeilenzuordnung uneindeutig; keine automatische Übernahme."
                                        .into();
                            }
                        }
                        if target.discover {
                            for candidate in candidates {
                                discovered
                                    .entry(format!(
                                        "{x:.0}:{y:.0}:{}",
                                        review::values_hash(&candidate)
                                    ))
                                    .or_default()
                                    .push((id.clone(), candidate));
                            }
                        }
                    }
                    run.regions.extend(regions);
                    run.observations.extend(observations);
                }
                Err(error) => {
                    attempt.status = "failed".into();
                    attempt.detail = error.to_string();
                }
            }
            if run.config.detailed_debug {
                if let Err(error) = crop.save(dir.join(format!("region-{id}.png"))) {
                    attempt.detail = format!("{}; artifact: {error}", attempt.detail);
                }
            }
            attempt.duration_ms = attempt_started.elapsed().as_millis() as u64;
            run.refinement_attempts.push(attempt);
        }
    }
    apply_readings(run, &readings)?;
    run.refinement_readings.extend(readings.clone());
    for (_, candidates) in discovered {
        if candidates
            .iter()
            .map(|(id, _)| id)
            .collect::<HashSet<_>>()
            .len()
            < 2
        {
            continue;
        }
        let candidate = &candidates[0].1;
        let Some((x, y, r, b)) = appointment_bounds(candidate, run) else {
            continue;
        };
        if run.appointments.iter().any(|a| {
            appointment_bounds(a, run)
                .is_some_and(|(l, t, right, bottom)| l < r && right > x && t < b && bottom > y)
        }) {
            continue;
        }
        let mut candidate = candidate.clone();
        candidate.id = uuid::Uuid::new_v5(
            &uuid::Uuid::NAMESPACE_OID,
            format!("{}:recovered:{x:.0}:{y:.0}", run.document.id).as_bytes(),
        )
        .to_string();
        candidate.approval = None;
        candidate.issues.push(Issue::new(
            "recovered_row",
            "Zusätzliche Zeile aus Nachlesung: Existenz am Foto bestätigen.",
            None,
            true,
        ));
        run.appointments.push(candidate);
    }
    let artifact = serde_json::to_vec(&run.refinement_readings.iter().map(|r|serde_json::json!({"appointment_id":r.appointment_id,"field":r.field,"value":r.value,"evidence":r.evidence,"attempt":r.attempt})).collect::<Vec<_>>())?;
    // Detailed readings are retained even without large debug rasters and expire with the scan.
    std::fs::write(dir.join("refinement-readings.json"), artifact)?;
    let attempts = &run.refinement_attempts[initial_attempts..];
    let failures = attempts
        .iter()
        .filter(|attempt| attempt.status == "failed")
        .count();
    run.stages.push(Stage {
        name: "selective_reread".into(),
        status: if cancel.load(Ordering::Relaxed) {
            "cancelled"
        } else if Instant::now() >= deadline {
            "budget_exhausted"
        } else if !attempts.is_empty() && failures == attempts.len() {
            "failed"
        } else if failures > 0 {
            "partial"
        } else {
            "complete"
        }
        .into(),
        duration_ms: started.elapsed().as_millis() as u64,
        detail: format!(
            "{} attempts retained; conflicts require review; no history-based dates or times.",
            run.refinement_attempts.len()
        ),
        artifacts: vec!["refinement-readings.json".into()],
    });
    Ok(())
}
pub(crate) fn apparent_time(text: &str) -> bool {
    static TIME: std::sync::LazyLock<regex::Regex> =
        std::sync::LazyLock::new(|| regex::Regex::new(r"\b[0-2]?\d:[0-5]\d\b").unwrap());
    TIME.is_match(text) && !text.to_lowercase().contains("druck")
}

/// Reprocessing the same photograph carries reviewed fields and calendar identities
/// across detector/configuration changes using unique original-frame row overlap.
pub fn preserve_review(previous: &PipelineRun, next: &mut PipelineRun) -> Result<()> {
    if previous.document.source_hash != next.document.source_hash {
        return Ok(());
    }
    let original_bounds = |a: &Appointment, r: &PipelineRun| {
        appointment_bounds(a, r).map(|(x, y, right, bottom)| {
            geometry::bounds(
                &geometry::rect(x, y, right - x, bottom - y)
                    .iter()
                    .map(|p| geometry::map(&r.page_to_original, p))
                    .collect::<Vec<_>>(),
            )
        })
    };
    let overlaps = |a: &Appointment, b: &Appointment| match (
        original_bounds(a, previous),
        original_bounds(b, next),
    ) {
        (Some((x, y, r, bottom)), Some((nx, ny, nr, nb))) => {
            let intersection =
                (r.min(nr) - x.max(nx)).max(0.) * (bottom.min(nb) - y.max(ny)).max(0.);
            let smaller = ((r - x) * (bottom - y)).min((nr - nx) * (nb - ny));
            smaller > 0. && intersection / smaller > 0.65
        }
        _ => false,
    };
    let matches: Vec<_> = previous
        .appointments
        .iter()
        .map(|old| {
            next.appointments
                .iter()
                .enumerate()
                .filter(|(_, a)| overlaps(old, a))
                .map(|(i, _)| i)
                .collect::<Vec<_>>()
        })
        .collect();
    let mut identities = std::collections::HashMap::new();
    for (old, candidates) in previous.appointments.iter().zip(&matches) {
        if candidates.len() == 1
            && matches
                .iter()
                .filter(|m| m.contains(&candidates[0]))
                .count()
                == 1
        {
            let a = &mut next.appointments[candidates[0]];
            identities.insert(a.id.clone(), old.id.clone());
            a.id = old.id.clone();
            a.included = old.included;
            a.calendar_event_id = old.calendar_event_id.clone();
            a.ics_event_id = old.ics_event_id.clone();
            a.calendar_saved_hash = old.calendar_saved_hash.clone();
            a.ics_exported_hash = old.ics_exported_hash.clone();
            a.suggestions = old.suggestions.clone();
            for field in review::FIELDS {
                if review::field_confirmed(old, field)
                    || old
                        .origins
                        .get(*field)
                        .is_some_and(|o| ["manual", "suggested"].contains(&o.kind.as_str()))
                {
                    review::set_value(a, field, review::value(old, field))?;
                    if let Some(origin) = old.origins.get(*field) {
                        a.origins.insert((*field).into(), origin.clone());
                    }
                    if let Some(f) = a.fields.get_mut(*field) {
                        f.confirmed_at = None;
                        f.confirmed_value = None;
                        f.reasons
                            .push("Manuelle Angabe erhalten; neue Bildzuordnung prüfen.".into());
                    } else if let Some(f) = old.fields.get(*field) {
                        let mut f = f.clone();
                        if f.frame == "page" {
                            f.polygon = f
                                .polygon
                                .iter()
                                .map(|p| {
                                    geometry::map(
                                        &next.original_to_page,
                                        &geometry::map(&previous.page_to_original, p),
                                    )
                                })
                                .collect();
                        }
                        f.confirmed_at = None;
                        f.confirmed_value = None;
                        f.reasons
                            .push("Frühere manuelle Angabe am Foto prüfen.".into());
                        a.fields.insert((*field).into(), f);
                    }
                }
            }
            if next.extraction_version == previous.extraction_version
                && a.fields == old.fields
                && review::values_hash(a) == review::values_hash(old)
            {
                a.approval = old.approval.clone();
            }
        } else if old
            .fields
            .keys()
            .any(|field| review::field_confirmed(old, field))
            || old.approval.is_some()
            || old.calendar_event_id.is_some()
            || old.ics_event_id.is_some()
            || old
                .origins
                .values()
                .any(|o| ["manual", "suggested"].contains(&o.kind.as_str()))
            || !old.included
        {
            for index in candidates {
                next.appointments[*index].approval = None;
                next.appointments[*index].issues.push(Issue::new(
                    "retained_review",
                    "Mögliche Zuordnung zu einem bereits bearbeiteten Termin prüfen.",
                    None,
                    true,
                ));
            }
            // The new detector may reuse the old row ID despite an ambiguous
            // split/merge. Reserve that ID for the retained reviewed appointment.
            for (index, competing) in next.appointments.iter_mut().enumerate() {
                if competing.id == old.id {
                    competing.id = uuid::Uuid::new_v5(
                        &uuid::Uuid::NAMESPACE_OID,
                        format!("{}:competing:{}:{index}", next.document.id, old.id).as_bytes(),
                    )
                    .to_string();
                    competing.approval = None;
                    competing.calendar_event_id = None;
                    competing.ics_event_id = None;
                    competing.calendar_saved_hash = None;
                    competing.ics_exported_hash = None;
                    if !competing.issues.iter().any(|i| i.code == "retained_review") {
                        competing.issues.push(Issue::new(
                            "retained_review",
                            "Geänderte Zeilenzuordnung zu früherem Termin prüfen.",
                            None,
                            true,
                        ));
                    }
                }
            }
            let mut retained = old.clone();
            retained.issues.push(Issue::new(
                "retained_review",
                "Frühere Korrektur erhalten; Zuordnung nach neuer Erkennung prüfen.",
                None,
                true,
            ));
            retained.approval = None;
            next.appointments.push(retained);
        }
    }
    for reading in &mut next.refinement_readings {
        if let Some(id) = identities.get(&reading.appointment_id) {
            reading.appointment_id = id.clone();
        }
    }
    for attempt in &mut next.refinement_attempts {
        for target in &mut attempt.target_ids {
            if let Some(id) = identities.get(target) {
                *target = id.clone();
            }
        }
    }

    Ok(())
}

/// One original-resolution row crop for the optional development-only VLM adapter.
/// Returned transforms link every reading back to retained source pixels.
pub fn experiment_crop(
    run: &PipelineRun,
    source_dir: &std::path::Path,
    output: &std::path::Path,
) -> Result<serde_json::Value> {
    let target = run
        .appointments
        .iter()
        .find(|a| {
            a.included
                && (!crate::parser::validate(a).is_empty() || a.issues.iter().any(|i| i.blocking))
        })
        .or_else(|| run.appointments.first());
    let image = image::open(source_dir.join("original.png"))?.to_rgb8();
    let polygon = target
        .and_then(|a| appointment_bounds(a, run))
        .map(|(x, y, r, b)| geometry::rect(x, y, r - x, b - y))
        .unwrap_or_else(|| geometry::rect(0., 0., run.page_width as f64, run.page_height as f64));
    let original: Vec<_> = polygon
        .iter()
        .map(|p| geometry::map(&run.page_to_original, p))
        .collect();
    let (x, y, r, b) = geometry::bounds(&original);
    let pad = ((b - y) * 0.2).max(12.);
    let x = ((x - pad).floor().max(0.) as u32).min(image.width() - 1);
    let y = ((y - pad).floor().max(0.) as u32).min(image.height() - 1);
    let w = ((r + pad).ceil().max(0.) as u32)
        .min(image.width())
        .saturating_sub(x)
        .max(1);
    let h = ((b + pad).ceil().max(0.) as u32)
        .min(image.height())
        .saturating_sub(y)
        .max(1);
    let crop = image::imageops::crop_imm(&image, x, y, w, h).to_image();
    std::fs::create_dir_all(output)?;
    crop.save(output.join("crop.png"))?;
    let result = serde_json::json!({"source_sha256":run.document.source_hash,"target_ids":target.map(|a|vec![a.id.clone()]).unwrap_or_default(),"crop_to_original":[1.,0.,x as f64,0.,1.,y as f64,0.,0.,1.],"width":w,"height":h,"crop_sha256":crate::hash(&std::fs::read(output.join("crop.png"))?),"approved":false});
    std::fs::write(
        output.join("crop.json"),
        serde_json::to_vec_pretty(&result)?,
    )?;
    Ok(result)
}

#[cfg(test)]
mod field_crop_tests {
    use super::*;

    #[test]
    fn clipped_neighbor_or_missing_geometry_never_becomes_a_field_value() {
        let observation = Observation {
            id: "read".into(),
            text: "B 12".into(),
            region_ids: vec!["box".into()],
            engine: "synthetic".into(),
            score: Some(1.0),
            alternatives: vec![],
        };
        let mut region = Region {
            id: "box".into(),
            polygon: geometry::rect(8.0, 4.0, 30.0, 12.0),
            frame: "crop".into(),
            kind: "text".into(),
            parent: None,
            children: vec![],
        };
        assert_eq!(
            contained_field_text(
                std::slice::from_ref(&observation),
                std::slice::from_ref(&region),
                100,
                30
            )
            .as_deref(),
            Some("B 12")
        );
        for polygon in [
            geometry::rect(0.0, 4.0, 30.0, 12.0),
            geometry::rect(80.0, 4.0, 20.0, 12.0),
            vec![],
        ] {
            region.polygon = polygon;
            assert!(contained_field_text(
                std::slice::from_ref(&observation),
                std::slice::from_ref(&region),
                100,
                30
            )
            .is_none());
        }
        assert!(contained_field_text(&[observation], &[], 100, 30).is_none());
    }
}
