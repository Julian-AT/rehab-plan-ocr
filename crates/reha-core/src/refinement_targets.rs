//! Scheduling is independent of OCR: spend the existing budget on omissions and
//! critical fields first, and read shared date headings only once.
use crate::{contracts::*, geometry, refinement::appointment_bounds, review};

#[derive(Clone, Debug)]
pub(crate) struct Target {
    pub appointments: Vec<String>,
    pub field: Option<String>,
    pub polygon: Vec<Point>,
    pub priority: u8,
    pub section: Option<String>,
    pub discover: bool,
}
impl Target {
    pub fn needs_contrast(&self, run: &PipelineRun, readings: &[RefinementReading]) -> bool {
        // A second transformation of the same reader is not independent evidence.
        // Spend it only where the original crop did not supply the requested fields.
        if self.discover || self.appointments.is_empty() {
            return true;
        }
        self.appointments.iter().any(|id| {
            let Some(a) = run.appointments.iter().find(|a| &a.id == id) else {
                return false;
            };
            let fields: Vec<&str> = self.field.as_deref().map_or_else(
                || {
                    ["start", "end", "title"]
                        .into_iter()
                        .filter(|f| {
                            uncertain(a, f) && (*f != "end" || a.duration_minutes.is_none())
                        })
                        .collect()
                },
                |field| vec![field],
            );
            fields.iter().any(|field| {
                !readings.iter().any(|reading| {
                    &reading.appointment_id == id
                        && reading.field == *field
                        && !review::empty(&reading.value)
                        && {
                            let mut candidate = a.clone();
                            review::set_value(&mut candidate, field, reading.value.clone()).is_ok()
                                && !crate::parser::validate(&candidate)
                                    .iter()
                                    .any(|i| i.field.as_deref() == Some(field) && i.blocking)
                        }
                })
            })
        })
    }
    pub fn reason(&self) -> &'static str {
        match self.priority {
            0 => "Möglicherweise fehlender Termin",
            1 => "Fehlendes oder unsicheres Abschnittsdatum",
            2 => "Fehlende oder unsichere Uhrzeit",
            3 => "Fehlende Terminbezeichnung",
            _ => "Unsichere Feldzuordnung",
        }
    }
}
fn protected(a: &Appointment, field: &str) -> bool {
    review::field_confirmed(a, field)
        || a.origins
            .get(field)
            .is_some_and(|o| ["manual", "suggested"].contains(&o.kind.as_str()))
}
fn uncertain(a: &Appointment, field: &str) -> bool {
    !protected(a, field)
        && (review::empty(&review::value(a, field))
            || a.fields.get(field).is_some_and(|f| !f.reasons.is_empty())
            || a.issues
                .iter()
                .any(|i| i.field.as_deref() == Some(field) && i.blocking))
}
fn padded(bounds: (f64, f64, f64, f64), run: &PipelineRun) -> Vec<Point> {
    let (x, y, r, b) = bounds;
    let h = (b - y).max(12.);
    let left = (x - h).max(0.);
    let top = (y - h * 0.6).max(0.);
    let right = (r + h).min(run.page_width as f64);
    let bottom = (b + h * 0.6).min(run.page_height as f64);
    geometry::rect(left, top, right - left, bottom - top)
}

pub(crate) fn schedule(run: &PipelineRun) -> Vec<Target> {
    if !run.config.prioritized_rereads {
        return existing_schedule(run);
    }
    let mut targets = vec![];
    for a in run.appointments.iter().filter(|a| a.included) {
        let section = run
            .sections
            .iter()
            .find(|s| Some(&s.id) == a.section_id.as_ref());
        if uncertain(a, "date") {
            let polygon = a
                .fields
                .get("date")
                .filter(|f| !f.polygon.is_empty())
                .map(|f| f.polygon.clone())
                .or_else(|| {
                    section.map(|s| {
                        run.observations
                            .iter()
                            .filter(|o| s.heading_ids.contains(&o.id))
                            .flat_map(|o| &o.region_ids)
                            .filter_map(|id| run.regions.iter().find(|r| &r.id == id))
                            .flat_map(|r| r.polygon.clone())
                            .collect()
                    })
                })
                .unwrap_or_default();
            if !polygon.is_empty() {
                targets.push(Target {
                    appointments: vec![a.id.clone()],
                    field: Some("date".into()),
                    polygon: padded(geometry::bounds(&polygon), run),
                    priority: 1,
                    section: a.section_id.clone(),
                    discover: false,
                });
            }
        }
        let critical = ["start", "end", "duration_minutes"]
            .iter()
            .any(|f| uncertain(a, f));
        // A printed end is sufficient; an absent alternative duration is not an error.
        let critical = critical
            && (uncertain(a, "start")
                || (a.end.is_none() && a.duration_minutes.is_none())
                || ["start", "end"].iter().any(|f| {
                    a.fields.get(*f).is_some_and(|v| !v.reasons.is_empty()) && !protected(a, f)
                }));
        let title = review::empty(&review::value(a, "title")) && !protected(a, "title");
        let mut time_targets = 0;
        if critical {
            for field in ["start", "end"] {
                if uncertain(a, field) && (field != "end" || a.duration_minutes.is_none()) {
                    if let Some(f) = a.fields.get(field).filter(|f| f.polygon.len() == 4) {
                        targets.push(Target {
                            appointments: vec![a.id.clone()],
                            field: Some(field.into()),
                            polygon: f.polygon.clone(),
                            priority: 2,
                            section: a.section_id.clone(),
                            discover: false,
                        });
                        time_targets += 1;
                    }
                }
            }
        }
        if (critical && time_targets == 0) || title {
            if let Some((x, y, r, b)) = appointment_bounds(a, run) {
                let (x, r) = section
                    .map(|s| {
                        let (l, _, r, _) = geometry::bounds(&s.polygon);
                        (l, r)
                    })
                    .unwrap_or((x, r));
                targets.push(Target {
                    appointments: vec![a.id.clone()],
                    field: None,
                    polygon: padded((x, y, r, b), run),
                    priority: if critical { 2 } else { 3 },
                    section: a.section_id.clone(),
                    discover: false,
                });
            }
        }
        for field in ["location", "therapist"] {
            if uncertain(a, field) {
                if let Some(f) = a.fields.get(field).filter(|f| !f.polygon.is_empty()) {
                    targets.push(Target {
                        appointments: vec![a.id.clone()],
                        field: Some(field.into()),
                        polygon: f.polygon.clone(),
                        priority: 4,
                        section: a.section_id.clone(),
                        discover: false,
                    });
                }
            }
        }
    }
    for region in run.regions.iter().filter(|r| {
        ["text", "uncertain_text"].contains(&r.kind.as_str()) && !r.id.starts_with("reread-")
    }) {
        let obs = run
            .observations
            .iter()
            .find(|o| o.region_ids.contains(&region.id));
        if obs.is_none()
            || obs.is_some_and(|o| {
                run.unassigned.contains(&o.id) && super::refinement::apparent_time(&o.text)
            })
        {
            let (x, y, r, b) = geometry::bounds(&region.polygon);
            let section = run.sections.iter().find(|s| {
                let (l, t, right, bottom) = geometry::bounds(&s.polygon);
                x < right && r > l && y < bottom && b > t
            });
            let (x, r) = section
                .map(|s| {
                    let (l, _, r, _) = geometry::bounds(&s.polygon);
                    (l, r)
                })
                .unwrap_or((x, r));
            targets.push(Target {
                appointments: vec![],
                field: None,
                polygon: padded((x, y, r, b), run),
                priority: 0,
                section: section.map(|s| s.id.clone()),
                discover: true,
            });
        }
    }
    targets.retain(|t| {
        t.polygon.len() >= 4 && t.polygon.iter().all(|p| p.x.is_finite() && p.y.is_finite())
    });
    targets.sort_by(|a, b| {
        a.priority
            .cmp(&b.priority)
            .then_with(|| {
                geometry::bounds(&a.polygon)
                    .1
                    .total_cmp(&geometry::bounds(&b.polygon).1)
            })
            .then_with(|| {
                geometry::bounds(&a.polygon)
                    .0
                    .total_cmp(&geometry::bounds(&b.polygon).0)
            })
            .then_with(|| a.appointments.cmp(&b.appointments))
    });
    let mut merged: Vec<Target> = vec![];
    for target in targets {
        let (x, y, r, b) = geometry::bounds(&target.polygon);
        let existing = merged.iter_mut().find(|old| {
            if old.section != target.section || old.field != target.field {
                return false;
            }
            let (ox, oy, or, ob) = geometry::bounds(&old.polygon);
            if target.field.as_deref() == Some("date") {
                return (ox - x).abs() < 1.
                    && (oy - y).abs() < 1.
                    && (or - r).abs() < 1.
                    && (ob - b).abs() < 1.;
            }
            if target.field.is_some() {
                return false;
            }
            // Merge neighboring row context, bounded to avoid a new whole-page read.
            x < or
                && r > ox
                && y < ob
                && b > oy
                && b.max(ob) - y.min(oy) <= 2.5 * (b - y).min(ob - oy)
        });
        if let Some(old) = existing {
            let (ox, oy, or, ob) = geometry::bounds(&old.polygon);
            old.polygon = geometry::rect(
                x.min(ox),
                y.min(oy),
                r.max(or) - x.min(ox),
                b.max(ob) - y.min(oy),
            );
            old.appointments.extend(target.appointments);
            old.appointments.sort();
            old.appointments.dedup();
            old.discover |= target.discover;
        } else {
            merged.push(target);
        }
    }
    merged.truncate(24);
    merged
}

fn existing_schedule(run: &PipelineRun) -> Vec<Target> {
    let mut targets = vec![];
    for a in &run.appointments {
        for field in ["location", "therapist"] {
            if let Some(f) = a
                .fields
                .get(field)
                .filter(|f| !f.polygon.is_empty() && !f.reasons.is_empty())
            {
                if !protected(a, field) {
                    targets.push(Target {
                        appointments: vec![a.id.clone()],
                        field: Some(field.into()),
                        polygon: f.polygon.clone(),
                        priority: 4,
                        section: a.section_id.clone(),
                        discover: false,
                    });
                }
            }
        }
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
                targets.push(Target {
                    appointments: vec![a.id.clone()],
                    field: None,
                    polygon: padded(
                        (section.map_or(x, |s| s.0), y, section.map_or(r, |s| s.2), b),
                        run,
                    ),
                    priority: 4,
                    section: a.section_id.clone(),
                    discover: false,
                });
            }
        }
    }
    for region in run
        .regions
        .iter()
        .filter(|r| ["text", "uncertain_text"].contains(&r.kind.as_str()))
    {
        let obs = run
            .observations
            .iter()
            .find(|o| o.region_ids.contains(&region.id));
        if obs.is_none()
            || obs.is_some_and(|o| {
                run.unassigned.contains(&o.id) && super::refinement::apparent_time(&o.text)
            })
        {
            targets.push(Target {
                appointments: vec![],
                field: None,
                polygon: padded(geometry::bounds(&region.polygon), run),
                priority: 0,
                section: None,
                discover: true,
            });
        }
    }
    targets.truncate(24);
    targets
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn omissions_and_shared_headings_precede_optional_fields() {
        let mut run: PipelineRun =
            serde_json::from_str(include_str!("../../../tests/fixtures/sample-run.json")).unwrap();
        run.config.prioritized_rereads = true;
        run.page_width = 1000;
        run.page_height = 3000;
        run.appointments.clear();
        run.regions.clear();
        run.observations.clear();
        run.sections.clear();
        for i in 0..30 {
            let mut a = Appointment::empty(format!("a{i}"));
            a.start = Some("08:00".into());
            a.end = Some("08:30".into());
            a.title = "Übung".into();
            a.fields.insert(
                "date".into(),
                FieldAssessment {
                    polygon: geometry::rect(10., 10., 600., 30.),
                    ..Default::default()
                },
            );
            a.fields.insert(
                "location".into(),
                FieldAssessment {
                    polygon: geometry::rect(700., 100. + i as f64 * 70., 100., 20.),
                    ..Default::default()
                },
            );
            run.appointments.push(a);
        }
        run.regions.push(Region {
            id: "unread".into(),
            polygon: geometry::rect(10., 2400., 100., 20.),
            frame: "page".into(),
            kind: "text".into(),
            parent: None,
            children: vec![],
        });
        let targets = schedule(&run);
        assert_eq!(targets.len(), 24);
        assert!(targets[0].discover);
        assert_eq!(targets[1].field.as_deref(), Some("date"));
        assert_eq!(targets[1].appointments.len(), 30);
        assert!(targets
            .iter()
            .skip(2)
            .all(|t| t.field.as_deref() == Some("location")));
    }
}
