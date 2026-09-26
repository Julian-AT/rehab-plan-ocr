//! Bounded, source-linked local rereading. Conflicts never compete on confidence score.
use crate::geometry;
use crate::{contracts::*, review, Result};
#[cfg(feature = "onnx")]
use std::collections::BTreeMap;
use std::collections::HashSet;

pub type Reading = RefinementReading;
/// Require two independent preprocessing attempts to agree on a missing value.
/// Printed contradictions stay visible and block approval; edits always win.
pub fn apply_readings(run: &mut PipelineRun, readings: &[Reading]) -> Result<()> {
    for a in &mut run.appointments {
        for field in review::FIELDS {
            if a.origins
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
            let attempts: HashSet<_> = matches.iter().map(|r| &r.attempt).collect();
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
                }
                a.approval = None;
            } else if review::empty(&current) && attempts.len() >= 2 {
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
fn appointment_bounds(a: &Appointment, run: &PipelineRun) -> Option<(f64, f64, f64, f64)> {
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
    use std::{sync::atomic::Ordering, time::Instant};
    let started = Instant::now();
    let available = || !cancel.load(Ordering::Relaxed) && Instant::now() < deadline;
    let mut targets = vec![];
    for a in &run.appointments {
        let weak = a.provenance.values().flatten().any(|id| {
            run.observations
                .iter()
                .any(|o| &o.id == id && o.score.is_some_and(|s| s < 0.8))
        });
        if (!crate::parser::validate(a).is_empty()
            || !a.issues.is_empty()
            || weak
            || a.location.is_empty())
            && a.included
        {
            if let Some((x, y, r, b)) = appointment_bounds(a, run) {
                let section = run
                    .sections
                    .iter()
                    .find(|s| Some(&s.id) == a.section_id.as_ref())
                    .map(|s| geometry::bounds(&s.polygon));
                targets.push((
                    Some(a.id.clone()),
                    section.map_or(x, |s| s.0),
                    y,
                    section.map_or(r, |s| s.2),
                    b,
                ));
            }
        }
    }
    // Undecoded detector regions and unassigned apparent times must not disappear silently.
    for region in run
        .regions
        .iter()
        .filter(|r| r.kind == "text" || r.kind == "uncertain_text")
    {
        let obs = run
            .observations
            .iter()
            .find(|o| o.region_ids.contains(&region.id));
        if obs.is_none()
            || obs.is_some_and(|o| run.unassigned.contains(&o.id) && apparent_time(&o.text))
        {
            let (x, y, r, b) = geometry::bounds(&region.polygon);
            targets.push((None, x, y, r, b));
        }
    }
    let mut readings = vec![];
    let mut discovered: BTreeMap<String, Vec<(String, Appointment)>> = BTreeMap::new();
    let original = if available() && !targets.is_empty() {
        Some(image::open(dir.join("original.png"))?.to_rgb8())
    } else {
        None
    };
    for (target, x, y, r, b) in targets.into_iter().take(24) {
        let Some(original) = &original else {
            break;
        };
        let height = (b - y).max(12.);
        let polygon = geometry::rect(
            (x - height).max(0.),
            (y - height * 0.6).max(0.),
            (r - x + height * 2.).min(run.page_width as f64),
            (b - y) + height * 1.2,
        );
        let points: Vec<_> = polygon
            .iter()
            .map(|p| geometry::map(&run.page_to_original, p))
            .collect();
        let (ox, oy, or, ob) = geometry::bounds(&points);
        let ox = (ox.floor().max(0.) as u32).min(original.width().saturating_sub(1));
        let oy = (oy.floor().max(0.) as u32).min(original.height().saturating_sub(1));
        let cw = (or.ceil().max(0.) as u32)
            .min(original.width())
            .saturating_sub(ox)
            .max(1);
        let ch = (ob.ceil().max(0.) as u32)
            .min(original.height())
            .saturating_sub(oy)
            .max(1);
        for variant in 0..2 {
            if !available() {
                break;
            }
            let attempt_started = Instant::now();
            let mut crop = image::imageops::crop_imm(original, ox, oy, cw, ch).to_image();
            crop = match run.config.quarter_turns % 4 {
                1 => image::imageops::rotate90(&crop),
                2 => image::imageops::rotate180(&crop),
                3 => image::imageops::rotate270(&crop),
                _ => crop,
            };
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
                &[1., 0., ox as f64, 0., 1., oy as f64, 0., 0., 1.],
                &geometry::multiply(
                    &geometry::inverse(&geometry::rotation(run.config.quarter_turns, cw, ch))?,
                    &[1. / scale, 0., 0., 0., 1. / scale, 0., 0., 0., 1.],
                ),
            );
            let to_page = geometry::multiply(&run.original_to_page, &to_original);
            let id = format!("reread-{:04}", run.refinement_attempts.len());
            let mut attempt = RefinementAttempt {
                id: id.clone(),
                target_ids: target.iter().cloned().collect(),
                reason: if target.is_some() {
                    "Unvollständige oder unsichere Zeile"
                } else {
                    "Nicht zugeordnete Region"
                }
                .into(),
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
            match engine.recognize_until(&crop, &config, cancel, dir, Some(deadline)) {
                Ok((mut regions, mut observations, stages)) => {
                    let complete = stages.iter().all(|s| s.status == "complete");
                    if !complete {
                        attempt.status = "partial".into();
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
                    if complete {
                        if let Some(target) = &target {
                            if candidates.len() == 1 {
                                for field in review::FIELDS {
                                    let candidate = &candidates[0];
                                    let evidence = candidate
                                        .provenance
                                        .get(*field)
                                        .cloned()
                                        .unwrap_or_default();
                                    if evidence.iter().any(|e| e.starts_with(&id)) {
                                        readings.push(Reading {
                                            appointment_id: target.clone(),
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
                        } else {
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
        run.appointments.push(candidate);
    }
    let artifact = serde_json::to_vec(&run.refinement_readings.iter().map(|r|serde_json::json!({"appointment_id":r.appointment_id,"field":r.field,"value":r.value,"evidence":r.evidence,"attempt":r.attempt})).collect::<Vec<_>>())?;
    // Detailed readings are retained even without large debug rasters and expire with the scan.
    std::fs::write(dir.join("refinement-readings.json"), artifact)?;
    run.stages.push(Stage {
        name: "selective_reread".into(),
        status: if cancel.load(Ordering::Relaxed) {
            "cancelled"
        } else if Instant::now() >= deadline {
            "budget_exhausted"
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
#[cfg(feature = "onnx")]
fn apparent_time(text: &str) -> bool {
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
    for (old, candidates) in previous.appointments.iter().zip(&matches) {
        if candidates.len() == 1
            && matches
                .iter()
                .filter(|m| m.contains(&candidates[0]))
                .count()
                == 1
        {
            let a = &mut next.appointments[candidates[0]];
            a.id = old.id.clone();
            a.included = old.included;
            a.calendar_event_id = old.calendar_event_id.clone();
            a.ics_event_id = old.ics_event_id.clone();
            a.calendar_saved_hash = old.calendar_saved_hash.clone();
            a.ics_exported_hash = old.ics_exported_hash.clone();
            a.suggestions = old.suggestions.clone();
            for field in review::FIELDS {
                if old
                    .origins
                    .get(*field)
                    .is_some_and(|o| ["manual", "suggested"].contains(&o.kind.as_str()))
                {
                    review::set_value(a, field, review::value(old, field))?;
                    a.origins
                        .insert((*field).into(), old.origins[*field].clone());
                }
            }
            if review::values_hash(a) == review::values_hash(old) {
                a.approval = old.approval.clone();
            }
        } else if old.approval.is_some()
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
