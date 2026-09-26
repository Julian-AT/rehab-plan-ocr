use crate::{contracts::*, geometry::bounds};
use chrono::{Datelike, NaiveDate, NaiveTime};
use regex::Regex;
use std::{
    collections::{BTreeSet, HashSet},
    sync::LazyLock,
};

pub const EXTRACTION_VERSION: u32 = 3;

static DATE: LazyLock<Regex> = LazyLock::new(|| {
    Regex::new(r"\b(\d{1,2})[./](\d{1,2})[./](\d{4})\b|\b(\d{4})-(\d{2})-(\d{2})\b").unwrap()
});
static TIME: LazyLock<Regex> =
    LazyLock::new(|| Regex::new(r"\b([01]?\d|2[0-3])[:.]([0-5]\d)\b").unwrap());
static DURATION: LazyLock<Regex> =
    LazyLock::new(|| Regex::new(r"(?i)\b(\d{1,3})\s*(?:min(?:uten)?|')\b").unwrap());
static LOCATION: LazyLock<Regex> =
    LazyLock::new(|| Regex::new(r"(?i)\b(?:Raum|Zimmer|Ort|Saal|Room)\s*:?\s*(.*)").unwrap());
static WEEKDAY: LazyLock<Regex> = LazyLock::new(|| {
    Regex::new(r"(?i)^\s*(montag|dienstag|mittwoch|donnerstag|freitag|samstag|sonntag)\s*,?\s*(?:der\s*)?$").unwrap()
});
static NEW_MARKER: LazyLock<Regex> = LazyLock::new(|| Regex::new(r"(?i)\*\s*neu\b\s*\*?").unwrap());

fn clean(text: &str) -> String {
    NEW_MARKER
        .replace_all(text, "")
        .split_whitespace()
        .collect::<Vec<_>>()
        .join(" ")
}

fn row_text(row: &Row<'_>) -> String {
    row.observations
        .iter()
        .map(|o| o.text.as_str())
        .collect::<Vec<_>>()
        .join(" ")
}

fn metadata(text: &str) -> bool {
    static HEADER: LazyLock<Regex> = LazyLock::new(|| {
        Regex::new(
        r"(?i)^\s*(?:gedruckt|ausdruck|druck(?:datum|zeit)?|print(?:ed)?|aufnahme(?:datum)?|eintritt(?:sdatum)?|geburt(?:sdatum)?|admission|patient(?:en)?(?:name|nummer|nr)?|versicher(?:ungsnummer)?|geb\.?|diagnose|kostenträger|fallnummer|fallnr)\b"
    ).unwrap()
    });
    HEADER.is_match(text)
}

fn date_value(c: &regex::Captures<'_>) -> Option<String> {
    let s = if c.get(1).is_some() {
        format!("{}-{:0>2}-{:0>2}", &c[3], &c[2], &c[1])
    } else {
        format!("{}-{}-{}", &c[4], &c[5], &c[6])
    };
    NaiveDate::parse_from_str(&s, "%Y-%m-%d")
        .ok()
        .map(|d| d.to_string())
}
#[derive(Debug)]
struct Row<'a> {
    observations: Vec<&'a Observation>,
    y: f64,
    bottom: f64,
    height: f64,
}
fn rows<'a>(obs: &'a [Observation], regions: &[Region]) -> Vec<Row<'a>> {
    let mut positioned: Vec<_> = obs
        .iter()
        .filter_map(|o| {
            let pts: Vec<_> = o
                .region_ids
                .iter()
                .filter_map(|id| regions.iter().find(|r| &r.id == id))
                .flat_map(|r| r.polygon.clone())
                .collect();
            if pts.is_empty() {
                return None;
            }
            let (x, y, _, b) = bounds(&pts);
            Some((o, x, y, b))
        })
        .collect();
    positioned.sort_by(|a, b| a.2.total_cmp(&b.2).then(a.1.total_cmp(&b.1)));
    let mut result: Vec<Row> = vec![];
    for (o, _x, y, b) in positioned {
        let height = b - y;
        if let Some(row) = result
            .last_mut()
            .filter(|r| (y - r.y).abs() < height.min(r.height) * 0.55)
        {
            row.observations.push(o);
            row.bottom = row.bottom.max(b);
        } else {
            result.push(Row {
                observations: vec![o],
                y,
                bottom: b,
                height,
            });
        }
    }
    for row in &mut result {
        row.observations.sort_by(|a, b| {
            let x = |o: &Observation| {
                o.region_ids
                    .first()
                    .and_then(|id| regions.iter().find(|r| &r.id == id))
                    .map(|r| bounds(&r.polygon).0)
                    .unwrap_or(0.)
            };
            x(a).total_cmp(&x(b))
        });
    }
    result
}

/// Header anchors delimit columns; values never consume a neighboring column.
struct Columns(Vec<(&'static str, f64)>);
impl Columns {
    fn from_rows(rows: &[Row<'_>], x: &impl Fn(&Observation) -> f64) -> Self {
        let mut columns = vec![];
        for row in rows {
            let text = row_text(row);
            if TIME.is_match(&text) && !DATE.is_match(&text) && !metadata(&text) {
                break;
            }
            for o in &row.observations {
                let field = match o.text.trim().to_lowercase().trim_end_matches(':') {
                    "zeit" | "uhrzeit" | "beginn" | "von" | "time" => "start",
                    "ende" | "bis" => "end",
                    "dauer" | "duration" => "duration_minutes",
                    "termin" | "therapie" | "behandlung" | "appointment" => "title",
                    "ort" | "raum" | "zimmer" | "location" | "room" => "location",
                    "therapeut" | "therapeutin" | "therapeut/in" | "therapist" => "therapist",
                    "hinweis" | "hinweise" | "bemerkung" | "bemerkungen" | "notes" => "notes",
                    "vorbereitung" => "preparation",
                    "code" | "leistung" => "treatment_code",
                    _ => continue,
                };
                if !columns.iter().any(|(f, _)| *f == field) {
                    columns.push((field, x(o) - row.height * 0.3));
                }
            }
        }
        columns.sort_by(|a, b| a.1.total_cmp(&b.1));
        Self(columns)
    }
    fn field(&self, x: f64) -> Option<&'static str> {
        self.0
            .iter()
            .rev()
            .find(|(_, left)| x >= *left)
            .map(|(f, _)| *f)
    }
    fn has(&self, field: &str) -> bool {
        self.0.iter().any(|(f, _)| *f == field)
    }
}

fn treatment_date(rows: &[Row<'_>]) -> (Option<String>, Vec<String>) {
    let mut dates = BTreeSet::new();
    let mut sources = vec![];
    let mut invalid = false;
    for row in rows {
        let text = row_text(row);
        if metadata(&text) {
            continue;
        }
        let explicit = [
            "therapieplan",
            "tagesplan",
            "behandlungsplan",
            "behandlungsdatum",
            "plandatum",
            "treatment date",
            "schedule date",
            "terminplan",
        ]
        .iter()
        .any(|label| text.to_lowercase().contains(label));
        for capture in DATE.captures_iter(&text) {
            let matched = capture.get(0).unwrap();
            let weekday = WEEKDAY.captures(text[..matched.start()].trim());
            // A weekday heading may be split into multiple OCR observations.
            let heading = weekday.is_some()
                && text[matched.end()..]
                    .trim_matches(|c: char| c.is_whitespace() || ".,:".contains(c))
                    .is_empty();
            if !explicit && !heading {
                continue;
            }
            sources.extend(row.observations.iter().map(|o| o.id.clone()));
            match date_value(&capture) {
                Some(date) => {
                    if heading {
                        let expected = [
                            "montag",
                            "dienstag",
                            "mittwoch",
                            "donnerstag",
                            "freitag",
                            "samstag",
                            "sonntag",
                        ]
                        .iter()
                        .position(|d| *d == weekday.as_ref().unwrap()[1].to_lowercase())
                        .unwrap();
                        let actual = NaiveDate::parse_from_str(&date, "%Y-%m-%d")
                            .unwrap()
                            .weekday()
                            .num_days_from_monday() as usize;
                        invalid |= expected != actual;
                    }
                    dates.insert(date);
                }
                None => invalid = true,
            }
        }
    }
    let date = (!invalid && dates.len() == 1).then(|| dates.first().unwrap().clone());
    (date, sources)
}

fn assign(a: &mut Appointment, field: &str, observations: &[&Observation]) {
    if observations.is_empty() {
        return;
    }
    let value = clean(
        &observations
            .iter()
            .map(|o| o.text.as_str())
            .collect::<Vec<_>>()
            .join(" "),
    );
    let target = match field {
        "title" => &mut a.title,
        "location" => &mut a.location,
        "therapist" => &mut a.therapist,
        "notes" => &mut a.notes,
        "preparation" => &mut a.metadata.preparation,
        "treatment_code" => &mut a.metadata.treatment_code,
        _ => return,
    };
    if !value.is_empty() {
        if !target.is_empty() {
            target.push(if field == "notes" { '\n' } else { ' ' });
        }
        target.push_str(&value);
    }
    a.provenance
        .entry(field.into())
        .or_default()
        .extend(observations.iter().map(|o| o.id.clone()));
}

fn extract_section(
    document_id: &str,
    observations: &[Observation],
    regions: &[Region],
) -> (Vec<Appointment>, Vec<Issue>, Vec<String>) {
    let rows = rows(observations, regions);
    let x = |o: &Observation| {
        o.region_ids
            .first()
            .and_then(|id| regions.iter().find(|r| &r.id == id))
            .map(|r| bounds(&r.polygon).0)
            .unwrap_or(0.)
    };
    let columns = Columns::from_rows(&rows, &x);
    let (date, date_sources) = treatment_date(&rows);
    let mut issues = vec![];
    let mut used = HashSet::new();
    if date.is_none() {
        issues.push(Issue::new(
            "date_confirmation",
            "Treatment date missing, conflicting, or inconsistent with weekday.",
            Some("date"),
            true,
        ));
    } else {
        used.extend(date_sources.iter().cloned());
    }
    let mut appointments: Vec<Appointment> = vec![];
    let mut previous_timed_row: Option<usize> = None;
    for (index, row) in rows.iter().enumerate() {
        let text = row_text(row);
        let time_text = if columns.has("title") {
            row.observations
                .iter()
                .filter(|o| matches!(columns.field(x(o)), Some("start" | "end") | None))
                .map(|o| o.text.as_str())
                .collect::<Vec<_>>()
                .join(" ")
        } else {
            text.clone()
        };
        if DATE.is_match(&time_text) || metadata(&text) {
            continue;
        }
        let times: Vec<_> = TIME.captures_iter(&time_text).collect();
        if times.is_empty() {
            let Some(previous) = previous_timed_row else {
                continue;
            };
            // Do not bridge large gaps or consume footers outside the table.
            let prev = &rows[index - 1];
            if row.y - prev.bottom > row.height * 1.6 {
                previous_timed_row = None;
                continue;
            }
            let a = appointments.last_mut().unwrap();
            if columns.has("title") {
                for field in [
                    "title",
                    "location",
                    "therapist",
                    "notes",
                    "preparation",
                    "treatment_code",
                ] {
                    let field_obs: Vec<_> = row
                        .observations
                        .iter()
                        .copied()
                        .filter(|o| columns.field(x(o)) == Some(field))
                        .collect();
                    assign(a, field, &field_obs);
                    used.extend(field_obs.iter().map(|o| o.id.clone()));
                }
            } else {
                let left = row
                    .observations
                    .iter()
                    .map(|o| x(o))
                    .fold(f64::INFINITY, f64::min);
                let anchor = rows[previous]
                    .observations
                    .iter()
                    .map(|o| x(o))
                    .fold(f64::INFINITY, f64::min);
                if left > anchor + row.height * 2. {
                    assign(a, "notes", &row.observations);
                    used.extend(row.observations.iter().map(|o| o.id.clone()));
                    a.issues.push(Issue::new(
                        "wrapped_text",
                        "Unlabeled continuation retained as notes; check field assignment.",
                        Some("notes"),
                        false,
                    ));
                }
            }
            continue;
        }
        let ids: Vec<_> = row.observations.iter().map(|o| o.id.clone()).collect();
        used.extend(ids.clone());
        let mut a = Appointment::empty(
            uuid::Uuid::new_v5(
                &uuid::Uuid::NAMESPACE_OID,
                format!("{document_id}:{}", ids.join("|")).as_bytes(),
            )
            .to_string(),
        );
        let time = |c: &regex::Captures<'_>| format!("{:0>2}:{}", &c[1], &c[2]);
        a.date = date.clone();
        a.start = Some(time(&times[0]));
        if times.len() >= 2 {
            let between =
                time_text[times[0].get(0).unwrap().end()..times[1].get(0).unwrap().start()].trim();
            if between.is_empty() || ["-", "–", "—", "bis"].contains(&between) {
                a.end = Some(time(&times[1]));
            }
        }
        a.duration_minutes = DURATION
            .captures(&time_text)
            .and_then(|c| c[1].parse().ok());
        for field in ["start", "end", "duration_minutes"] {
            a.provenance.insert(
                field.into(),
                row.observations
                    .iter()
                    .filter(|o| {
                        (TIME.is_match(&o.text) || DURATION.is_match(&o.text))
                            && (!columns.has("title")
                                || matches!(
                                    columns.field(x(o)),
                                    Some("start" | "end" | "duration_minutes") | None
                                ))
                    })
                    .map(|o| o.id.clone())
                    .collect(),
            );
        }
        a.provenance.insert("date".into(), date_sources.clone());
        if columns.has("title") {
            for field in [
                "title",
                "location",
                "therapist",
                "notes",
                "preparation",
                "treatment_code",
            ] {
                let field_obs: Vec<_> = row
                    .observations
                    .iter()
                    .copied()
                    .filter(|o| columns.field(x(o)) == Some(field))
                    .collect();
                assign(&mut a, field, &field_obs);
            }
            if let Some(o) = row
                .observations
                .iter()
                .find(|o| columns.field(x(o)) == Some("duration_minutes"))
            {
                a.duration_minutes = clean(&o.text).parse().ok().or(a.duration_minutes);
                a.provenance
                    .insert("duration_minutes".into(), vec![o.id.clone()]);
            }
        } else {
            let rest = TIME.replace_all(&text, "");
            let rest = DURATION.replace_all(&rest, "");
            let rest = clean(&rest)
                .trim_matches(|c: char| c.is_whitespace() || "-–—|".contains(c))
                .to_owned();
            if let Some(loc) = LOCATION.captures(&rest) {
                a.title = rest[..loc.get(0).unwrap().start()]
                    .trim_matches(|c: char| c.is_whitespace() || c == '|')
                    .into();
                if let Some((room, note)) = loc[1].split_once(" | ") {
                    a.location = room.trim().into();
                    a.notes = note.trim().into();
                } else {
                    a.location = loc[1].trim().into();
                }
            } else {
                a.title = rest;
            }
            for field in ["title", "location", "notes"] {
                a.provenance.insert(field.into(), ids.clone());
            }
        }
        if [
            "abgesagt",
            "entfällt",
            "gestrichen",
            "cancel",
            "handschrift",
        ]
        .iter()
        .any(|s| text.to_lowercase().contains(s))
        {
            a.issues.push(Issue::new(
                "possible_cancellation",
                "Possible cancellation or handwritten change.",
                None,
                true,
            ));
        }
        if times.len() > 2 {
            a.issues.push(Issue::new(
                "extra_times",
                "More than two times in one row; resolve field assignment.",
                Some("start"),
                true,
            ));
        }
        previous_timed_row = Some(index);
        appointments.push(a);
    }
    for a in &mut appointments {
        a.issues.extend(validate(a));
    }
    let unassigned: Vec<_> = observations
        .iter()
        .filter(|o| !used.contains(&o.id))
        .map(|o| o.id.clone())
        .collect();
    if !unassigned.is_empty() {
        issues.push(Issue::new(
            "unassigned_text",
            "Unassigned observations require inspection.",
            None,
            false,
        ));
    }
    if appointments.is_empty() {
        issues.push(Issue::new(
            "no_items",
            "No timed rows detected.",
            None,
            true,
        ));
    }
    (appointments, issues, unassigned)
}

fn observation_bounds(o: &Observation, regions: &[Region]) -> (f64, f64, f64, f64) {
    let points: Vec<_> = regions
        .iter()
        .filter(|r| o.region_ids.contains(&r.id))
        .flat_map(|r| r.polygon.clone())
        .collect();
    bounds(&points)
}
fn printed_metadata(observations: &[Observation]) -> Metadata {
    let mut result = Metadata::default();
    for o in observations {
        let Some((label, text)) = o.text.split_once(':') else {
            continue;
        };
        let target = match label.trim().to_lowercase().as_str() {
            "klinik" | "einrichtung" => &mut result.clinic,
            "abteilung" => &mut result.department,
            "adresse" | "anschrift" => &mut result.address,
            "kontakt" | "telefon" | "e-mail" => &mut result.contact,
            // Preparation and document references require appointment-level association.
            _ => continue,
        };
        if target.is_empty() {
            *target = clean(text);
        } else if *target != clean(text) {
            target.clear();
        } // competing scope is not guessed
    }
    result
}

/// Spatial sections prevent a second day's heading from changing the first day's rows.
/// Adjacent headings without intervening appointments remain competing evidence.
pub fn sections(observations: &[Observation], regions: &[Region]) -> Vec<ScheduleSection> {
    struct Heading {
        ids: Vec<String>,
        x: f64,
        y: f64,
        height: f64,
    }
    let grouped = rows(observations, regions);
    let mut headings = vec![];
    for row in &grouped {
        let individual: Vec<_> = row
            .observations
            .iter()
            .filter(|o| {
                let single = Row {
                    observations: vec![**o],
                    y: row.y,
                    bottom: row.bottom,
                    height: row.height,
                };
                !treatment_date(&[single]).1.is_empty()
            })
            .collect();
        if !individual.is_empty() {
            for o in individual {
                headings.push(Heading {
                    ids: vec![o.id.clone()],
                    x: observation_bounds(o, regions).0,
                    y: row.y,
                    height: row.height,
                });
            }
        } else if !treatment_date(&[Row {
            observations: row.observations.clone(),
            y: row.y,
            bottom: row.bottom,
            height: row.height,
        }])
        .1
        .is_empty()
        {
            headings.push(Heading {
                ids: row.observations.iter().map(|o| o.id.clone()).collect(),
                x: observation_bounds(row.observations[0], regions).0,
                y: row.y,
                height: row.height,
            });
        }
    }
    if headings.is_empty() {
        return vec![];
    }
    let page_right = regions
        .iter()
        .flat_map(|r| &r.polygon)
        .map(|p| p.x)
        .fold(0., f64::max);
    let page_bottom = regions
        .iter()
        .flat_map(|r| &r.polygon)
        .map(|p| p.y)
        .fold(0., f64::max)
        + 1.;
    let first_y = headings[0].y;
    let preamble: Vec<_> = observations
        .iter()
        .filter(|o| observation_bounds(o, regions).1 < first_y)
        .cloned()
        .collect();
    let mut result: Vec<ScheduleSection> = vec![];
    for h in &headings {
        let left = headings
            .iter()
            .filter(|other| (other.y - h.y).abs() < h.height && other.x < h.x - h.height * 2.)
            .map(|_| h.x - h.height)
            .next()
            .unwrap_or(0.);
        let right = headings
            .iter()
            .filter(|other| (other.y - h.y).abs() < h.height && other.x > h.x + h.height * 2.)
            .map(|other| other.x - h.height)
            .min_by(f64::total_cmp)
            .unwrap_or(page_right + 1.);
        let timed_between = |top: f64, bottom: f64| {
            observations.iter().any(|o| {
                let (x, y, _, _) = observation_bounds(o, regions);
                x >= left
                    && x < right
                    && y > top
                    && y < bottom
                    && TIME.is_match(&o.text)
                    && !DATE.is_match(&o.text)
                    && !metadata(&o.text)
            })
        };
        if let Some(previous) = result.iter_mut().rev().find(|s| {
            let (l, t, r, _) = bounds(&s.polygon);
            (l - left).abs() < h.height
                && (r - right).abs() < h.height
                && t < h.y
                && !timed_between(t, h.y)
        }) {
            previous.heading_ids.extend(h.ids.clone());
            continue;
        }
        result.push(ScheduleSection {
            id: format!("section-{}", h.ids.join("-")),
            date: None,
            polygon: crate::geometry::rect(left, h.y, right - left, page_bottom - h.y),
            heading_ids: h.ids.clone(),
            observation_ids: vec![],
            columns: Default::default(),
            metadata: Metadata::default(),
        });
    }
    for i in 0..result.len() {
        let (left, top, right, _) = bounds(&result[i].polygon);
        let bottom = result
            .iter()
            .skip(i + 1)
            .filter_map(|s| {
                let (l, t, r, _) = bounds(&s.polygon);
                (t > top && l < right && r > left).then_some(t)
            })
            .min_by(f64::total_cmp)
            .unwrap_or(page_bottom);
        result[i].polygon = crate::geometry::rect(left, top, right - left, bottom - top);
        let obs: Vec<_> = observations
            .iter()
            .filter(|o| {
                let (x, y, _, _) = observation_bounds(o, regions);
                x >= left && x < right && ((y >= top && y < bottom) || y < first_y)
            })
            .cloned()
            .collect();
        let heading_obs: Vec<_> = observations
            .iter()
            .filter(|o| result[i].heading_ids.contains(&o.id))
            .cloned()
            .collect();
        result[i].date = treatment_date(&rows(&heading_obs, regions)).0;
        result[i].observation_ids = obs.iter().map(|o| o.id.clone()).collect();
        result[i].columns =
            Columns::from_rows(&rows(&obs, regions), &|o| observation_bounds(o, regions).0)
                .0
                .into_iter()
                .map(|(k, v)| (k.into(), v))
                .collect();
        // A heading over the left column must not describe a different clinic's
        // schedule in the right column. Ambiguous global scope stays unassigned.
        let scoped_preamble: Vec<_> = preamble
            .iter()
            .filter(|o| {
                let (x, _, _, _) = observation_bounds(o, regions);
                x >= left && x < right
            })
            .cloned()
            .collect();
        result[i].metadata = printed_metadata(&scoped_preamble);
        let first_appointment = obs
            .iter()
            .filter(|o| TIME.is_match(&o.text) && !DATE.is_match(&o.text) && !metadata(&o.text))
            .map(|o| observation_bounds(o, regions).1)
            .min_by(f64::total_cmp)
            .unwrap_or(bottom);
        let local: Vec<_> = obs
            .iter()
            .filter(|o| {
                let y = observation_bounds(o, regions).1;
                y >= top && y < first_appointment
            })
            .cloned()
            .collect();
        let local = printed_metadata(&local);
        let m = &mut result[i].metadata;
        for (target, value) in [
            (&mut m.clinic, local.clinic),
            (&mut m.department, local.department),
            (&mut m.address, local.address),
            (&mut m.contact, local.contact),
        ] {
            if !value.is_empty() {
                *target = value;
            }
        }
    }
    result
}
pub fn extract(
    document_id: &str,
    observations: &[Observation],
    regions: &[Region],
) -> (Vec<Appointment>, Vec<Issue>, Vec<String>) {
    let sections = sections(observations, regions);
    let mut appointments = vec![];
    let mut issues = vec![];
    let mut used = HashSet::new();
    if sections.is_empty() {
        return extract_section(document_id, observations, regions);
    }
    for section in sections {
        let obs: Vec<_> = observations
            .iter()
            .filter(|o| section.observation_ids.contains(&o.id))
            .cloned()
            .collect();
        let (mut found, problems, unassigned) = extract_section(document_id, &obs, regions);
        used.extend(
            obs.iter()
                .filter(|o| !unassigned.contains(&o.id))
                .map(|o| o.id.clone()),
        );
        for a in &mut found {
            a.section_id = Some(section.id.clone());
            a.date = section.date.clone();
            a.provenance
                .insert("date".into(), section.heading_ids.clone());
            a.metadata.clinic = section.metadata.clinic.clone();
            a.metadata.department = section.metadata.department.clone();
            a.metadata.address = section.metadata.address.clone();
            a.metadata.contact = section.metadata.contact.clone();
            for field in crate::review::FIELDS {
                if !crate::review::empty(&crate::review::value(a, field)) {
                    a.origins.insert(
                        (*field).into(),
                        FieldOrigin {
                            kind: "printed".into(),
                            evidence: a
                                .provenance
                                .get(*field)
                                .cloned()
                                .unwrap_or_else(|| section.observation_ids.clone()),
                            source: "Foto".into(),
                        },
                    );
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
            a.issues.extend(validate(a));
        }
        appointments.extend(found);
        issues.extend(problems);
    }
    issues.sort_by(|a, b| a.code.cmp(&b.code));
    issues.dedup();
    let unassigned = observations
        .iter()
        .filter(|o| !used.contains(&o.id))
        .map(|o| o.id.clone())
        .collect();
    (appointments, issues, unassigned)
}

pub fn add_layout(
    observations: &[Observation],
    regions: &mut Vec<Region>,
    width: u32,
    height: u32,
) {
    let grouped = rows(observations, regions);
    let mut row_regions = vec![];
    for (index, row) in grouped.iter().enumerate() {
        let children: Vec<String> = row
            .observations
            .iter()
            .flat_map(|o| o.region_ids.clone())
            .collect();
        let points: Vec<_> = regions
            .iter()
            .filter(|r| children.contains(&r.id))
            .flat_map(|r| r.polygon.clone())
            .collect();
        let (x, y, r, b) = bounds(&points);
        row_regions.push(Region {
            id: format!("row-{index:04}"),
            polygon: crate::geometry::rect(x, y, r - x, b - y),
            frame: "page".into(),
            kind: "row".into(),
            parent: Some("page".into()),
            children,
        });
    }
    for row in &row_regions {
        for region in regions.iter_mut().filter(|r| row.children.contains(&r.id)) {
            region.parent = Some(row.id.clone());
        }
    }
    regions.push(Region {
        id: "page".into(),
        polygon: crate::geometry::rect(0., 0., width as f64, height as f64),
        frame: "page".into(),
        kind: "page".into(),
        parent: None,
        children: row_regions.iter().map(|r| r.id.clone()).collect(),
    });
    regions.extend(row_regions);
}

pub fn validate(a: &Appointment) -> Vec<Issue> {
    let mut issues = vec![];
    if a.date
        .as_ref()
        .and_then(|d| NaiveDate::parse_from_str(d, "%Y-%m-%d").ok())
        .is_none()
    {
        issues.push(Issue::new(
            "missing_date",
            "Gültiges Datum fehlt.",
            Some("date"),
            true,
        ));
    }
    let start = a
        .start
        .as_ref()
        .and_then(|s| NaiveTime::parse_from_str(s, "%H:%M").ok());
    let end = a
        .end
        .as_ref()
        .and_then(|s| NaiveTime::parse_from_str(s, "%H:%M").ok());
    if start.is_none() {
        issues.push(Issue::new(
            "missing_start",
            "Gültige Startzeit fehlt.",
            Some("start"),
            true,
        ));
    }
    if end.is_none() && a.duration_minutes.is_none_or(|d| d == 0 || d > 1440) {
        issues.push(Issue::new(
            "missing_end",
            "Endzeit oder Dauer am Papier ergänzen.",
            Some("end"),
            true,
        ));
    }
    if a.end.is_some() && end.is_none() {
        issues.push(Issue::new(
            "invalid_end",
            "Endzeit ungültig.",
            Some("end"),
            true,
        ));
    }
    if start.zip(end).is_some_and(|(s, e)| e <= s)
        && a.end_date
            .as_ref()
            .is_none_or(|d| Some(d) == a.date.as_ref())
    {
        issues.push(Issue::new(
            "overnight_confirmation",
            "Ende liegt vor Start: Enddatum ausdrücklich bestätigen.",
            Some("end_date"),
            true,
        ));
    }
    if a.title.trim().is_empty() {
        issues.push(Issue::new(
            "missing_title",
            "Bezeichnung fehlt.",
            Some("title"),
            true,
        ));
    }
    issues
}

#[cfg(test)]
mod tests {
    use super::*;
    fn positioned(cells: &[(f64, f64, &str)]) -> (Vec<Appointment>, Vec<Issue>, Vec<String>) {
        let regions: Vec<_> = cells
            .iter()
            .enumerate()
            .map(|(i, (x, y, _))| Region {
                id: format!("r{i}"),
                polygon: crate::geometry::rect(*x, *y, 100., 20.),
                frame: "page".into(),
                kind: "text".into(),
                parent: None,
                children: vec![],
            })
            .collect();
        let observations: Vec<_> = cells
            .iter()
            .enumerate()
            .map(|(i, (_, _, text))| Observation {
                id: format!("o{i}"),
                text: text.to_string(),
                region_ids: vec![format!("r{i}")],
                engine: "synthetic".into(),
                score: None,
                alternatives: vec![],
            })
            .collect();
        extract("fixture", &observations, &regions)
    }
    #[test]
    fn timed_items_are_not_print_metadata_and_room_numbers_are_not_times() {
        let (a, _, _) = positioned(&[
            (0., 0., "Uhrzeit"),
            (200., 0., "Therapie"),
            (500., 0., "Raum"),
            (700., 0., "Therapeut"),
            (0., 40., "Donnerstag, der 30.04.2026"),
            (0., 80., "*Neu 08:00 - 08:15"),
            (200., 80., "Blutdruckmessung"),
            (500., 80., "1.02"),
            (700., 80., "Alex Beispiel"),
            (700., 104., "MSc"),
            (0., 140., "08:00 - 08:25"),
            (200., 140., "Aufnahmegespräch"),
            (700., 140., "Kim Muster"),
            (700., 164., "BSc"),
        ]);
        assert_eq!(a.len(), 2);
        assert_eq!(a[0].start.as_deref(), Some("08:00"));
        assert_eq!(a[0].end.as_deref(), Some("08:15"));
        assert_eq!(a[0].title, "Blutdruckmessung");
        assert_eq!(a[0].location, "1.02");
        assert_eq!(a[0].therapist, "Alex Beispiel MSc");
        assert_eq!(a[1].title, "Aufnahmegespräch");
        assert_eq!(a[1].therapist, "Kim Muster BSc");
        assert!(a.iter().all(|a| a.issues.is_empty()));
    }
    #[test]
    fn weekday_heading_is_treatment_date_with_split_observations() {
        let (a, issues, _) = positioned(&[
            (0., 0., "Gedruckt am 29.04.2026 15:00"),
            (0., 40., "Donnerstag, der"),
            (200., 40., "30.04.2026"),
            (0., 80., "08:00 - 08:30 Übung"),
        ]);
        assert_eq!(a.len(), 1);
        assert_eq!(a[0].date.as_deref(), Some("2026-04-30"));
        assert_eq!(a[0].provenance["date"], ["o1", "o2"]);
        assert!(!issues.iter().any(|i| i.code == "date_confirmation"));
    }
    #[test]
    fn inconsistent_weekday_and_competing_headings_require_review() {
        for headings in [
            vec!["Freitag, der 30.04.2026"],
            vec!["Donnerstag, der 30.04.2026", "Freitag, der 01.05.2026"],
            vec!["Donnerstag, der 30.04.2026", "Tagesplan 31.04.2026"],
        ] {
            let mut lines = headings;
            lines.push("08:00 - 08:30 Übung");
            let (a, issues, _) = parse(&lines);
            assert!(a[0].date.is_none());
            assert!(issues.iter().any(|i| i.code == "date_confirmation"));
        }
    }
    #[test]
    fn new_markers_do_not_remove_neurology_or_new_words() {
        let (a, _, _) = parse(&[
            "Donnerstag, der 30.04.2026",
            "*Neu 08:00 - 08:30 Neurologie Raum Neu 2",
        ]);
        assert_eq!(a[0].title, "Neurologie");
        assert_eq!(a[0].location, "Neu 2");
    }
    #[test]
    fn multiline_therapists_and_titles_stay_in_their_columns() {
        let (a, _, unassigned) = positioned(&[
            (0., 0., "Uhrzeit"),
            (200., 0., "Therapie"),
            (500., 0., "Raum"),
            (700., 0., "Therapeut"),
            (0., 40., "Donnerstag, der 30.04.2026"),
            (0., 80., "*Neu 08:00 - 08:30"),
            (200., 82., "Bewegung"),
            (500., 84., "A 2"),
            (700., 79., "Alex Beispiel"),
            (200., 104., "im Wasser"),
            (700., 103., "MSc"),
            (0., 140., "*Neu 09:00 - 09:30"),
            (200., 143., "Neurologie"),
            (500., 142., "B 3"),
            (700., 139., "Kim Muster"),
            (700., 164., "Physiotherapie"),
            (0., 240., "Unassigned footer"),
        ]);
        assert_eq!(a.len(), 2);
        assert_eq!(a[0].title, "Bewegung im Wasser");
        assert_eq!(a[0].location, "A 2");
        assert_eq!(a[0].therapist, "Alex Beispiel MSc");
        assert_eq!(a[1].therapist, "Kim Muster Physiotherapie");
        assert_eq!(a[0].provenance["therapist"], ["o8", "o10"]);
        assert_eq!(a[1].provenance["therapist"], ["o14", "o15"]);
        assert!(a
            .iter()
            .all(|a| a.notes.is_empty() && !a.title.contains("Neu ")));
        assert!(unassigned.contains(&"o16".into()));
        assert!(!unassigned.contains(&"o10".into()));
    }
    fn parse(lines: &[&str]) -> (Vec<Appointment>, Vec<Issue>, Vec<String>) {
        let regions: Vec<_> = lines
            .iter()
            .enumerate()
            .map(|(i, _)| Region {
                id: format!("r{i}"),
                polygon: crate::geometry::rect(0., i as f64 * 40., 800., 20.),
                frame: "page".into(),
                kind: "text".into(),
                parent: None,
                children: vec![],
            })
            .collect();
        let obs = lines
            .iter()
            .enumerate()
            .map(|(i, t)| Observation {
                id: format!("o{i}"),
                text: t.to_string(),
                region_ids: vec![format!("r{i}")],
                engine: "synthetic".into(),
                score: None,
                alternatives: vec![],
            })
            .collect::<Vec<_>>();
        extract("sample", &obs, &regions)
    }
    #[test]
    fn printed_date_does_not_override_treatment() {
        let (a, _, _) = parse(&[
            "Gedruckt 09.09.2026 13:30",
            "Therapieplan 10.09.2026",
            "08:00 - 08:30 Bewegung Raum A2",
        ]);
        assert_eq!(a.len(), 1);
        assert_eq!(a[0].date.as_deref(), Some("2026-09-10"));
        assert_eq!(a[0].location, "A2");
    }
    #[test]
    fn repeated_and_overlapping_preserved() {
        let (a, _, _) = parse(&[
            "Tagesplan 10.09.2026",
            "08:00 - 09:00 Übung",
            "08:00 - 09:00 Übung",
            "08:30 - 08:45 Pause",
        ]);
        assert_eq!(a.len(), 3);
        assert_ne!(a[0].id, a[1].id);
    }
    #[test]
    fn never_infers_end() {
        let (a, _, _) = parse(&[
            "Tagesplan 10.09.2026",
            "08:00 Übung",
            "09:00 - 09:30 Frühstück",
        ]);
        assert!(a[0].end.is_none());
        assert!(a[0].issues.iter().any(|i| i.code == "missing_end"));
    }
    #[test]
    fn conflicting_dates_block() {
        let (a, i, _) = parse(&[
            "Tagesplan 10.09.2026",
            "Therapieplan 11.09.2026",
            "08:00 - 08:30 Übung",
        ]);
        assert!(a[0].date.is_none());
        assert!(i.iter().any(|i| i.code == "date_confirmation"));
    }
    #[test]
    fn unlabeled_date_requires_confirmation() {
        let (a, _, u) = parse(&[
            "10.09.2026",
            "08:00 - 08:30 Übung",
            "Bitte Wasser mitbringen",
        ]);
        assert!(a[0].date.is_none());
        assert_eq!(u.len(), 2);
    }
    #[test]
    fn duration_and_cancellation() {
        let (a, _, _) = parse(&["Tagesplan 10.09.2026", "08:00 Gymnastik 30 min entfällt"]);
        assert_eq!(a[0].duration_minutes, Some(30));
        assert!(a[0]
            .issues
            .iter()
            .any(|i| i.code == "possible_cancellation"));
    }
}
