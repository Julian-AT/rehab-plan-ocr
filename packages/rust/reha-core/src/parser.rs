use crate::{contracts::*, geometry::bounds};
use chrono::{Datelike, NaiveDate, NaiveTime};
use regex::Regex;
use std::{
    collections::{BTreeSet, HashSet},
    sync::LazyLock,
};

pub const EXTRACTION_VERSION: u32 = 10;

/// Robust text baselines supply table skew even when no page edge is visible.
/// Header anchors are a fallback for old axis-aligned observations.
fn table_transform(observations: &[Observation], regions: &[Region]) -> [f64; 9] {
    let mut slopes = vec![];
    for r in regions
        .iter()
        .filter(|r| r.polygon.len() == 4 && (r.kind == "text" || r.kind == "uncertain_text"))
    {
        let p = &r.polygon;
        for (a, b) in [(p[0], p[1]), (p[3], p[2])] {
            let dx = b.x - a.x;
            let dy = b.y - a.y;
            if dx.abs() > 50. && dy.abs() / dx.abs() < 0.25 {
                slopes.push(dy / dx);
            }
        }
    }
    if slopes.iter().filter(|s| s.abs() > 0.0001).count() < 4 {
        slopes.clear();
        let headers: Vec<_> = observations
            .iter()
            .filter(|o| {
                ["uhrzeit", "therapie", "raum", "therapeut"]
                    .contains(&o.text.trim().to_lowercase().as_str())
            })
            .collect();
        for (i, a) in headers.iter().enumerate() {
            let (ax, ay, _, ab) = observation_bounds(a, regions);
            for b in headers.iter().skip(i + 1) {
                let (bx, by, _, bb) = observation_bounds(b, regions);
                let dx = bx - ax;
                let dy = (by + bb - ay - ab) / 2.;
                if dx.abs() > 100. && dy.abs() / dx.abs() < 0.2 {
                    slopes.push(dy / dx);
                }
            }
        }
    }
    slopes.sort_by(f64::total_cmp);
    let slope = slopes.get(slopes.len() / 2).copied().unwrap_or(0.);
    [1., 0., 0., -slope, 1., 0., 0., 0., 1.]
}
fn transformed_regions(regions: &[Region], m: &[f64; 9]) -> Vec<Region> {
    regions
        .iter()
        .cloned()
        .map(|mut r| {
            r.polygon = r
                .polygon
                .iter()
                .map(|p| crate::geometry::map(m, p))
                .collect();
            r
        })
        .collect()
}

/// Residual baseline slope varies down a curved/perspective table. A local
/// median only applies with enough independent text boxes; sparse pages retain
/// the global/header fallback. Coordinates remain invertible to source pixels.
struct TableAlignment {
    base: [f64; 9],
    samples: Vec<(f64, f64)>,
}
impl TableAlignment {
    fn new(observations: &[Observation], regions: &[Region]) -> Self {
        let base = table_transform(observations, regions);
        let aligned = transformed_regions(regions, &base);
        let samples: Vec<(f64, f64)> = aligned
            .iter()
            .filter(|r| r.polygon.len() == 4 && r.kind == "text")
            .filter_map(|r| {
                let p = &r.polygon;
                let dx = p[1].x - p[0].x;
                let slope = (p[1].y - p[0].y) / dx;
                (dx > 70. && slope.abs() < 0.06).then_some(((p[0].y + p[2].y) / 2., slope))
            })
            .collect();
        if samples.len() < 12 {
            return Self {
                base,
                samples: vec![],
            };
        }
        let width = aligned
            .iter()
            .flat_map(|r| r.polygon.iter())
            .map(|p| p.x.abs())
            .fold(1., f64::max);
        let mut positions: Vec<_> = samples.iter().map(|s| s.0).collect();
        positions.sort_by(f64::total_cmp);
        let mut knots: Vec<(f64, f64)> = vec![];
        for i in 0..5 {
            let y = positions[i * (positions.len() - 1) / 4];
            if knots.last().is_some_and(|k| (k.0 - y).abs() < 1.) {
                continue;
            }
            let mut nearest = samples.clone();
            nearest.sort_by(|a, b| (a.0 - y).abs().total_cmp(&(b.0 - y).abs()));
            let mut values: Vec<_> = nearest.iter().take(12).map(|s| s.1).collect();
            values.sort_by(f64::total_cmp);
            let mut slope = if values[values.len() * 3 / 4] - values[values.len() / 4] > 0.025 {
                0.
            } else {
                values[values.len() / 2]
            };
            if let Some((py, ps)) = knots.last() {
                // Bound the derivative so the warp cannot fold rows at any x.
                let change = (y - py) * 0.25 / width;
                slope = slope.clamp(ps - change, ps + change);
            }
            knots.push((y, slope));
        }
        Self {
            base,
            samples: knots,
        }
    }
    fn slope(&self, y: f64) -> f64 {
        let Some(first) = self.samples.first() else {
            return 0.;
        };
        if y <= first.0 {
            return first.1;
        }
        for pair in self.samples.windows(2) {
            let (a, b) = (pair[0], pair[1]);
            if y <= b.0 {
                return a.1 + (b.1 - a.1) * (y - a.0) / (b.0 - a.0);
            }
        }
        self.samples.last().unwrap().1
    }
    fn forward(&self, p: &Point) -> Point {
        let mut p = crate::geometry::map(&self.base, p);
        p.y -= self.slope(p.y) * p.x;
        p
    }
    fn backward(&self, p: &Point) -> Point {
        let mut q = *p;
        if let Some(first) = self.samples.first() {
            q.y = p.y + self.samples.last().unwrap().1 * p.x;
            if p.y <= first.0 - first.1 * p.x {
                q.y = p.y + first.1 * p.x;
            } else {
                for pair in self.samples.windows(2) {
                    let (a, b) = (pair[0], pair[1]);
                    if p.y <= b.0 - b.1 * p.x {
                        let k = (b.1 - a.1) / (b.0 - a.0);
                        q.y = (p.y + p.x * (a.1 - k * a.0)) / (1. - k * p.x);
                        break;
                    }
                }
            }
        }
        crate::geometry::map(
            &crate::geometry::inverse(&self.base).unwrap_or(crate::geometry::IDENTITY),
            &q,
        )
    }
    fn regions(&self, regions: &[Region]) -> Vec<Region> {
        regions
            .iter()
            .cloned()
            .map(|mut r| {
                r.polygon = r.polygon.iter().map(|p| self.forward(p)).collect();
                r
            })
            .collect()
    }
}

static DATE: LazyLock<Regex> = LazyLock::new(|| {
    Regex::new(r"\b(\d{1,2})[.,/](\d{1,2})[.,/](\d{4})\b|\b(\d{4})-(\d{2})-(\d{2})\b").unwrap()
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
// An unreadable date still ends the preceding day's scope. Do not recognize
// ordinary treatment names containing a weekday as a new day heading.
static DAY_BOUNDARY: LazyLock<Regex> = LazyLock::new(|| {
    Regex::new(r"(?i)^\s*(?:montag|dienstag|mittwoch|donnerstag|freitag|samstag|sonntag)\b\s*,?\s*(?:der\s*)?(?:[\d?x.,/ _-]+|unleserlich|nicht lesbar)?\s*$").unwrap()
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

fn column_header(text: &str) -> bool {
    [
        "uhrzeit",
        "zeit",
        "beginn",
        "von",
        "ende",
        "bis",
        "dauer",
        "therapie",
        "termin",
        "behandlung",
        "raum",
        "ort",
        "zimmer",
        "therapeut",
        "therapeutin",
        "therapeut/in",
        "hinweis",
        "hinweise",
        "bemerkung",
        "bemerkungen",
        "vorbereitung",
        "code",
        "leistung",
    ]
    .contains(&text.trim().to_lowercase().trim_end_matches(':'))
}
fn footer(text: &str) -> bool {
    static FOOTER: LazyLock<Regex> = LazyLock::new(|| {
        Regex::new(r"(?i)(?:frühstück|mittagessen|abendessen)\s+von\b|essenszeiten|seite\s*:")
            .unwrap()
    });
    FOOTER.is_match(text)
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
    // Clock cells anchor blocks. Perspective can leave a right-hand cell just
    // above its clock even after baseline correction. Attach that first line to
    // the nearby clock before processing continuations in reading order.
    let title_left = positioned
        .iter()
        .filter(|(o, _, _, _)| {
            ["therapie", "termin", "behandlung"].contains(&o.text.trim().to_lowercase().as_str())
        })
        .map(|(_, x, y, b)| *x - (b - y) * 1.5)
        .min_by(f64::total_cmp);
    if let Some(left) = title_left {
        let anchors: Vec<_> = positioned
            .iter()
            .filter(|(o, x, _, _)| {
                *x < left && TIME.is_match(&o.text) && !DATE.is_match(&o.text) && !metadata(&o.text)
            })
            .map(|(_, _, y, b)| (*y, *b))
            .collect();
        for (o, x, y, b) in &mut positioned {
            if *x < left || DATE.is_match(&o.text) || metadata(&o.text) {
                continue;
            }
            let height = *b - *y;
            if let Some((ay, ab)) = anchors
                .iter()
                .filter(|(ay, ab)| {
                    let tolerance = height.min(ab - ay);
                    *y >= ay - tolerance * 1.1 && *y <= ay + tolerance * 0.5
                })
                .min_by(|a, b| (*y - a.0).abs().total_cmp(&(*y - b.0).abs()))
            {
                let _ = ab;
                *y = *ay;
                *b = *ay + height;
            }
        }
    }
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

/// Assignment tolerates left drift; crop boundaries follow the actual whitespace.
/// These are deliberately different from the padded detector rectangles.
struct Columns(Vec<(&'static str, f64)>, bool, Vec<(&'static str, f64)>);
impl Columns {
    fn from_rows(
        rows: &[Row<'_>],
        position: &impl Fn(&Observation) -> (f64, f64, f64, f64),
    ) -> Self {
        let x = |o: &Observation| position(o).0;
        let header_field =
            |o: &Observation| match o.text.trim().to_lowercase().trim_end_matches(':') {
                "zeit" | "uhrzeit" | "beginn" | "von" | "time" => Some("start"),
                "ende" | "bis" => Some("end"),
                "dauer" | "duration" => Some("duration_minutes"),
                "termin" | "therapie" | "behandlung" | "appointment" => Some("title"),
                "ort" | "raum" | "zimmer" | "location" | "room" => Some("location"),
                "therapeut" | "therapeutin" | "therapeut/in" | "therapist" => Some("therapist"),
                "hinweis" | "hinweise" | "bemerkung" | "bemerkungen" | "notes" => Some("notes"),
                "vorbereitung" => Some("preparation"),
                "code" | "leistung" => Some("treatment_code"),
                _ => None,
            };
        // A patient-information "Zimmer" above the table is not a column header.
        // Require a coherent header band, then only consume nearby header cells.
        let header = rows
            .iter()
            .filter_map(|row| {
                let fields: HashSet<_> = row
                    .observations
                    .iter()
                    .filter_map(|o| header_field(o))
                    .collect();
                (fields.len() >= 2 || fields.contains("start") || fields.contains("title"))
                    .then_some((row, fields.len()))
            })
            .max_by_key(|(_, count)| *count)
            .map(|(row, _)| row);
        let mut columns = vec![];
        let mut anchors = vec![];
        for row in rows {
            if header.is_none_or(|h| (row.y - h.y).abs() > row.height.max(h.height) * 0.8) {
                continue;
            }
            for o in &row.observations {
                let Some(field) = header_field(o) else {
                    continue;
                };
                if !columns.iter().any(|(f, _)| *f == field) {
                    columns.push((field, x(o) - row.height * 1.5));
                    anchors.push((field, x(o)));
                }
            }
        }
        let mut inferred = false;
        if !columns.iter().any(|(f, _)| *f == "title") {
            if let Some((_, room_x)) = columns.iter().find(|(f, _)| *f == "location") {
                let candidate = rows
                    .iter()
                    .filter(|row| {
                        row.observations.iter().any(|o| {
                            TIME.is_match(&o.text) && !DATE.is_match(&o.text) && !metadata(&o.text)
                        })
                    })
                    .flat_map(|row| row.observations.iter().copied())
                    .filter(|o| {
                        !TIME.is_match(&o.text)
                            && !DATE.is_match(&o.text)
                            && !metadata(&o.text)
                            && !column_header(&o.text)
                            && x(o) < *room_x
                    })
                    .map(x)
                    .min_by(f64::total_cmp);
                if let Some(left) = candidate {
                    columns.push(("title", left - 10.));
                    inferred = true;
                }
            }
        }
        columns.sort_by(|a, b| a.1.total_cmp(&b.1));
        let mut result = Self(columns.clone(), inferred, columns);
        let body: Vec<_> = rows
            .iter()
            .filter(|row| header.is_none_or(|h| row.y > h.bottom))
            .filter(|row| !metadata(&row_text(row)) && !footer(&row_text(row)))
            .flat_map(|row| row.observations.iter().copied())
            .filter(|o| !DATE.is_match(&o.text) && header_field(o).is_none())
            .collect();
        for i in 1..result.0.len() {
            let (field, left) = result.0[i];
            let previous = result.0[i - 1].0;
            let anchor = anchors
                .iter()
                .find(|(f, _)| *f == field)
                .map_or(left, |(_, x)| *x);
            let height = header.map_or(20., |h| h.height);
            let mut next_lefts: Vec<_> = body
                .iter()
                .filter(|o| result.field(x(o)) == Some(field) && x(o) < anchor + height * 2.)
                .map(|o| x(o))
                .collect();
            next_lefts.sort_by(f64::total_cmp);
            let next_left = next_lefts
                .get(next_lefts.len() / 10)
                .copied()
                .unwrap_or(anchor);
            let mut previous_rights: Vec<_> = body
                .iter()
                .filter(|o| {
                    result.field(x(o)) == Some(previous)
                        || (previous == "start"
                            && result.field(x(o)).is_none()
                            && TIME.is_match(&o.text))
                })
                .map(|o| position(o).2)
                .filter(|right| *right < next_left)
                .collect();
            previous_rights.sort_by(f64::total_cmp);
            if let Some(right) = previous_rights.last() {
                result.2[i].1 = (right + next_left) / 2.;
            } else {
                // Sparse/merged cells: the next header's content start is a
                // stronger boundary than its generous assignment tolerance.
                result.2[i].1 = next_left - height * 0.35;
            }
            result.2[i].1 = result.2[i].1.max(result.2[i - 1].1 + 1.);
        }
        result
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

pub(crate) fn heading_date(observations: &[Observation], regions: &[Region]) -> Option<String> {
    treatment_date(&rows(observations, regions)).0
}

pub(crate) fn clock_value(text: &str) -> Option<String> {
    let captures = TIME.captures(text.trim())?;
    let matched = captures.get(0)?;
    (matched.start() == 0 && matched.end() == text.trim().len())
        .then(|| format!("{:0>2}:{}", &captures[1], &captures[2]))
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
        if DAY_BOUNDARY.is_match(&text) && !DATE.is_match(&text) {
            sources.extend(row.observations.iter().map(|o| o.id.clone()));
            invalid = true;
        }
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

fn assign_cell(a: &mut Appointment, field: &str, observations: &[&Observation]) {
    if field != "title" {
        assign(a, field, observations);
        return;
    }
    let (notes, title): (Vec<_>, Vec<_>) = observations.iter().copied().partition(|o| {
        let text = o.text.trim().to_lowercase();
        [
            "bitte ",
            "teilnahme ",
            "nüchtern",
            "armstudio",
            "mitbringen",
        ]
        .iter()
        .any(|p| text.starts_with(p))
    });
    assign(a, "title", &title);
    assign(a, "notes", &notes);
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
    let columns = Columns::from_rows(&rows, &|o| observation_bounds(o, regions));
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
        if DATE.is_match(&time_text) || metadata(&text) || footer(&text) {
            continue;
        }
        let times: Vec<_> = TIME.captures_iter(&time_text).collect();
        if !times.is_empty()
            && previous_timed_row.is_some_and(|previous| {
                row.y - rows[previous].bottom > row.height.max(rows[previous].height) * 10.
            })
        {
            // Footer service ranges separated by a large blank area are not
            // dated table appointments. Keep their observations available for review.
            issues.push(Issue::new(
                "outside_table_time",
                "Uhrzeit außerhalb des Tabellenblocks: Dokumentübersicht prüfen.",
                None,
                false,
            ));
            continue;
        }
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
                    assign_cell(a, field, &field_obs);
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
                assign_cell(&mut a, field, &field_obs);
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
        // Clock snapping changes grouping order, not printed reading order inside
        // a narrow cell. In particular an honorific must precede the name below it.
        if columns.has("title") {
            for field in ["title", "location", "therapist", "notes"] {
                if let Some(ids) = a.provenance.get(field) {
                    let mut lines: Vec<_> = observations
                        .iter()
                        .filter(|o| ids.contains(&o.id))
                        .collect();
                    lines.sort_by(|a, b| {
                        let ab = observation_bounds(a, regions);
                        let bb = observation_bounds(b, regions);
                        ab.1.total_cmp(&bb.1).then(ab.0.total_cmp(&bb.0))
                    });
                    if !lines.is_empty() {
                        let text = lines
                            .iter()
                            .map(|o| clean(&o.text))
                            .collect::<Vec<_>>()
                            .join(if field == "notes" { "\n" } else { " " });
                        let _ = crate::review::set_value(a, field, serde_json::json!(text));
                    }
                }
            }
        }
        assess_fields(a, &columns, observations, regions);
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

fn assess_fields(a: &mut Appointment, columns: &Columns, obs: &[Observation], regions: &[Region]) {
    let row_ids: HashSet<_> = a
        .provenance
        .iter()
        .filter(|(f, _)| f.as_str() != "date")
        .flat_map(|(_, ids)| ids)
        .collect();
    let row_points: Vec<_> = obs
        .iter()
        .filter(|o| row_ids.contains(&o.id))
        .flat_map(|o| o.region_ids.iter())
        .filter_map(|id| regions.iter().find(|r| &r.id == id))
        .flat_map(|r| r.polygon.clone())
        .collect();
    if row_points.is_empty() {
        return;
    }
    let (left, top, right, bottom) = bounds(&row_points);
    a.row_polygon = crate::geometry::rect(left, top, right - left, bottom - top);
    let mut cell_boundaries = columns.2.clone();
    // A perspective table can drift horizontally down the page. A surviving
    // name/degree line anchors the local name-column edge even when the line
    // above was detected together with the room. Keep both crops on that edge.
    if let Some(index) = cell_boundaries
        .iter()
        .position(|(field, _)| *field == "therapist")
    {
        let therapist_ids = a.provenance.get("therapist").cloned().unwrap_or_default();
        if let Some(local_left) = obs
            .iter()
            .filter(|o| therapist_ids.contains(&o.id))
            .map(|o| observation_bounds(o, regions).0)
            .filter(|x| columns.field(*x) == Some("therapist"))
            .min_by(f64::total_cmp)
        {
            cell_boundaries[index].1 = local_left;
        }
    }
    for field in [
        "date",
        "start",
        "end",
        "title",
        "location",
        "therapist",
        "notes",
    ] {
        let ids = a.provenance.get(field).cloned().unwrap_or_default();
        let evidence: Vec<_> = obs.iter().filter(|o| ids.contains(&o.id)).collect();
        let mut assessment = FieldAssessment {
            state: PrintedState::Legible,
            frame: "page".into(),
            ..Default::default()
        };
        let cell_left = cell_boundaries
            .iter()
            .find(|(f, _)| *f == field)
            .map(|(_, x)| *x);
        let cell_right = cell_left.and_then(|x| {
            cell_boundaries
                .iter()
                .find(|(_, p)| *p > x)
                .map(|(_, p)| *p)
        });
        if let Some(x) = cell_left {
            assessment.polygon = crate::geometry::rect(
                x,
                top,
                cell_right.unwrap_or(right.max(x + 20.)) - x,
                bottom - top,
            );
        } else {
            assessment.polygon = if ["location", "therapist"].contains(&field) {
                vec![]
            } else {
                a.row_polygon.clone()
            };
        }
        if columns.1 && ["title", "location", "therapist"].contains(&field) {
            assessment
                .reasons
                .push("Spaltenkopf unvollständig; Zuordnung aus Tabellenposition prüfen.".into());
        }
        if field == "date" {
            assessment.polygon = evidence
                .iter()
                .flat_map(|o| o.region_ids.iter())
                .filter_map(|id| regions.iter().find(|r| &r.id == id))
                .flat_map(|r| r.polygon.clone())
                .collect();
            if !assessment.polygon.is_empty() {
                let (x, y, r, b) = bounds(&assessment.polygon);
                assessment.polygon = crate::geometry::rect(x, y, r - x, b - y);
            }
        }
        if field == "therapist" && columns.has("location") && !columns.has("therapist") {
            assessment.state = PrintedState::Cropped;
            assessment
                .reasons
                .push("Therapeutenspalte nicht sicher erfasst: rechten Bildrand prüfen.".into());
        }
        if field == "location" {
            static ROOMS: LazyLock<Regex> = LazyLock::new(|| {
                Regex::new(r"(?i)(?:raum|therapie|psychologie|wartezone)\s*\d+").unwrap()
            });
            if ROOMS.find_iter(&a.location).count() > 1 {
                assessment.state = PrintedState::Contradictory;
                assessment
                    .reasons
                    .push("Mehrere Raumangaben: Zeilen- und Spaltenzuordnung prüfen.".into());
            }
        }
        if evidence.iter().any(|o| o.score.is_some_and(|s| s < 0.85)) {
            assessment.reasons.push("Unsichere Zeichenlesung.".into());
        }
        if let Some(boundary) = cell_right {
            if evidence.iter().any(|o| {
                let (x, y, right, bottom) = observation_bounds(o, regions);
                // DB unclip adds whitespace on every side of a text line.
                // A padded box grazing a separator does not prove mixed text.
                let padding = (bottom - y).min(right - x) * 0.25;
                let shared_time = field == "start"
                    && a.provenance
                        .get("end")
                        .is_some_and(|ids| ids.contains(&o.id))
                    && columns
                        .2
                        .iter()
                        .find(|(_, p)| *p == boundary)
                        .is_some_and(|(f, _)| *f == "end");
                !shared_time && right - padding > boundary + 4.
            }) {
                assessment.state = PrintedState::Contradictory;
                assessment.reasons.push(
                    "Textbereich überquert eine Spaltengrenze; getrennte Lesung prüfen.".into(),
                );
            }
        }
        if ["location", "therapist"].contains(&field)
            && crate::review::empty(&crate::review::value(a, field))
        {
            // An empty OCR string does not negate the stronger geometric evidence.
            // Only a previously legible assessment becomes an unreviewed blank.
            if assessment.state == PrintedState::Legible {
                assessment.state = PrintedState::Unreviewed;
            }
            assessment
                .reasons
                .push("Leer erkannt: am Foto bestätigen, ob nichts gedruckt ist.".into());
        }
        let text = crate::review::value(a, field)
            .as_str()
            .unwrap_or("")
            .to_string();
        if field == "location"
            && ["BSc", "MSc", "Mag.", "Dr.", "Fr.", "Hr."]
                .iter()
                .any(|s| text.contains(s))
        {
            assessment.state = PrintedState::Contradictory;
            assessment
                .reasons
                .push("Möglicher Namensrest in der Raumspalte.".into());
        }
        if field == "therapist"
            && ["bsc", "msc", "ba", "ma", "dr.", "mag."]
                .contains(&text.trim().to_lowercase().as_str())
        {
            assessment.state = PrintedState::Contradictory;
            assessment
                .reasons
                .push("Isolierter Titel: Namensfortsetzung und Nachbarzeile prüfen.".into());
        }
        if !assessment.reasons.is_empty() || !crate::review::empty(&crate::review::value(a, field))
        {
            a.fields.insert(field.into(), assessment);
        }
    }
}
fn printed_metadata(observations: &[Observation]) -> (Metadata, HashSet<&'static str>) {
    let mut result = Metadata::default();
    let mut conflicts = HashSet::new();
    for o in observations {
        let Some((label, text)) = o.text.split_once(':') else {
            continue;
        };
        let (field, target) = match label.trim().to_lowercase().as_str() {
            "klinik" | "einrichtung" => ("clinic", &mut result.clinic),
            "abteilung" => ("department", &mut result.department),
            "adresse" | "anschrift" => ("address", &mut result.address),
            "kontakt" | "telefon" | "e-mail" => ("contact", &mut result.contact),
            // Preparation and document references require appointment-level association.
            _ => continue,
        };
        let value = clean(text);
        if value.is_empty() || conflicts.contains(field) {
            continue;
        }
        if target.is_empty() {
            *target = value;
        } else if *target != value {
            target.clear();
            conflicts.insert(field);
        }
    }
    (result, conflicts)
}

/// Spatial sections prevent a second day's heading from changing the first day's rows.
/// Adjacent headings without intervening appointments remain competing evidence.
pub fn sections(observations: &[Observation], regions: &[Region]) -> Vec<ScheduleSection> {
    let (prepared, _) = crate::numeric_candidates::prepare(observations);
    let observations = prepared.as_ref();
    let alignment = TableAlignment::new(observations, regions);
    let mut result = sections_aligned(observations, &alignment.regions(regions));
    for s in &mut result {
        s.polygon = s.polygon.iter().map(|p| alignment.backward(p)).collect();
    }
    result
}
fn sections_aligned(observations: &[Observation], regions: &[Region]) -> Vec<ScheduleSection> {
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
                DATE.is_match(&o.text) && !treatment_date(&[single]).1.is_empty()
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
    let header_bottom = observations
        .iter()
        .filter(|o| column_header(&o.text))
        .map(|o| observation_bounds(o, regions).3)
        .max_by(f64::total_cmp);
    if let Some(header_bottom) = header_bottom {
        if observations.iter().any(|o| {
            let (_, y, _, _) = observation_bounds(o, regions);
            y > header_bottom
                && y < first_y
                && TIME.is_match(&o.text)
                && !DATE.is_match(&o.text)
                && !metadata(&o.text)
                && !footer(&o.text)
        }) {
            result.insert(
                0,
                ScheduleSection {
                    id: "section-unreadable-heading".into(),
                    date: None,
                    polygon: crate::geometry::rect(
                        0.,
                        header_bottom + 1.,
                        page_right + 1.,
                        first_y - header_bottom - 1.,
                    ),
                    heading_ids: vec![],
                    observation_ids: vec![],
                    columns: Default::default(),
                    metadata: Metadata::default(),
                },
            );
        }
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
                x >= left
                    && x < right
                    && ((y >= top && y < bottom) || (y < first_y && column_header(&o.text)))
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
            Columns::from_rows(&rows(&obs, regions), &|o| observation_bounds(o, regions))
                .2
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
        result[i].metadata = printed_metadata(&scoped_preamble).0;
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
        let (local, conflicts) = printed_metadata(&local);
        let m = &mut result[i].metadata;
        for (field, target, value) in [
            ("clinic", &mut m.clinic, local.clinic),
            ("department", &mut m.department, local.department),
            ("address", &mut m.address, local.address),
            ("contact", &mut m.contact, local.contact),
        ] {
            if conflicts.contains(field) {
                // Contradictory local evidence also prevents inheriting a heading.
                target.clear();
            } else if !value.is_empty() {
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
    let (prepared, candidates) = crate::numeric_candidates::prepare(observations);
    let observations = prepared.as_ref();
    let alignment = TableAlignment::new(observations, regions);
    let (mut appointments, issues, unassigned) =
        extract_aligned(document_id, observations, &alignment.regions(regions));
    for a in &mut appointments {
        for (field, evidence) in &a.provenance {
            let states: Vec<_> = evidence
                .iter()
                .filter_map(|id| candidates.get(id))
                .collect();
            if !states.is_empty() {
                let assessment = a.fields.entry(field.clone()).or_default();
                assessment.state = if states.contains(&&PrintedState::Contradictory) {
                    PrintedState::Contradictory
                } else {
                    PrintedState::Unreviewed
                };
                assessment
                    .reasons
                    .push("OCR-Zahlenalternativen: gedruckte Angabe am Foto bestätigen.".into());
                a.issues.push(Issue::new(
                    "numeric_candidate",
                    "Mehrdeutige Zahl aus vorhandenen OCR-Lesarten.",
                    Some(field),
                    true,
                ));
            }
        }
        a.row_polygon = a
            .row_polygon
            .iter()
            .map(|p| alignment.backward(p))
            .collect();
        for f in a.fields.values_mut() {
            f.polygon = f.polygon.iter().map(|p| alignment.backward(p)).collect();
        }
    }
    (appointments, issues, unassigned)
}
fn extract_aligned(
    document_id: &str,
    observations: &[Observation],
    regions: &[Region],
) -> (Vec<Appointment>, Vec<Issue>, Vec<String>) {
    let sections = sections_aligned(observations, regions);
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
    #[test]
    fn shared_headers_never_duplicate_preamble_times_or_copy_an_unreadable_days_date() {
        let cells = [
            (0., 0., "20:40"),
            (250., 0., "Therapieplan"),
            (0., 50., "Uhrzeit"),
            (250., 50., "Therapie"),
            (550., 50., "Raum"),
            (800., 50., "Therapeut"),
            (0., 100., "08:00 - 08:30"),
            (250., 100., "Erster Tag ohne lesbare Überschrift"),
            (0., 200., "Donnerstag, der 10.09.2026"),
            (0., 250., "09:00 - 09:30"),
            (250., 250., "Zweiter Tag"),
            (0., 350., "Freitag, der 11.09.2026"),
            (0., 400., "10:00 - 10:30"),
            (250., 400., "Dritter Tag"),
            (
                0.,
                900.,
                "Frühstück von 06:30 bis 08:00, Mittagessen von 11:30 bis 13 Uhr",
            ),
        ];
        let regions: Vec<_> = cells
            .iter()
            .enumerate()
            .map(|(i, (x, y, _))| Region {
                id: format!("r{i}"),
                polygon: crate::geometry::rect(*x, *y, 180., 20.),
                frame: "page".into(),
                kind: "text".into(),
                parent: None,
                children: vec![],
            })
            .collect();
        let obs: Vec<_> = cells
            .iter()
            .enumerate()
            .map(|(i, (_, _, t))| Observation {
                id: format!("o{i}"),
                text: t.to_string(),
                region_ids: vec![format!("r{i}")],
                score: None,
                engine: "fixture".into(),
                alternatives: vec![],
            })
            .collect();
        let a = extract("sections", &obs, &regions).0;
        assert_eq!(a.len(), 3);
        assert_eq!(a[0].date, None);
        assert_eq!(a[0].start.as_deref(), Some("08:00"));
        assert_eq!(a[1].date.as_deref(), Some("2026-09-10"));
        assert_eq!(a[2].date.as_deref(), Some("2026-09-11"));
        assert_eq!(a[1].title, "Zweiter Tag");
    }
    #[test]
    fn skewed_columns_keep_names_and_degree_continuations_with_time_anchors() {
        let cells = [
            (10., 10., "Donnerstag, der 10.09.2026"),
            (10., 50., "Uhrzeit"),
            (240., 50., "Therapie"),
            (600., 50., "Raum"),
            (850., 50., "Therapeut"),
            (10., 100., "08:00 - 08:30"),
            (220., 100., "Bewegung"),
            (600., 100., "Raum 107"),
            (850., 100., "Fr. A. Elandora"),
            (850., 125., "BSc"),
            (240., 125., "bitte feste Schuhe mitbringen"),
            (10., 180., "09:00 - 09:30"),
            (240., 180., "Gespräch"),
            (600., 180., "Raum 701"),
            (850., 180., "Hr. B. Belvara"),
        ];
        let regions: Vec<_> = cells
            .iter()
            .enumerate()
            .map(|(i, (x, y, text))| Region {
                id: format!("r{i}"),
                polygon: crate::geometry::rect(
                    *x,
                    *y,
                    if text.starts_with("Donnerstag") {
                        450.
                    } else {
                        180.
                    },
                    20.,
                )
                .iter()
                .map(|p| Point {
                    x: p.x,
                    y: p.y + 0.09 * p.x,
                })
                .collect(),
                frame: "page".into(),
                kind: "text".into(),
                parent: None,
                children: vec![],
            })
            .collect();
        let obs: Vec<_> = cells
            .iter()
            .enumerate()
            .map(|(i, (_, _, t))| Observation {
                id: format!("o{i}"),
                text: t.to_string(),
                region_ids: vec![format!("r{i}")],
                score: Some(0.99),
                engine: "fixture".into(),
                alternatives: vec![],
            })
            .collect();
        let a = extract("skew", &obs, &regions).0;
        assert_eq!(a.len(), 2);
        assert_eq!(a[0].location, "Raum 107");
        assert_eq!(a[1].location, "Raum 701");
        assert_eq!(a[0].therapist, "Fr. A. Elandora BSc");
        assert_eq!(a[1].therapist, "Hr. B. Belvara");
        assert_eq!(a[0].title, "Bewegung");
        assert_eq!(a[0].notes, "bitte feste Schuhe mitbringen");
        assert!(a[0].fields["location"].polygon[1].y > a[0].fields["location"].polygon[0].y);
    }
    #[test]
    fn patient_room_is_not_a_table_header_and_padding_is_not_mixed_text() {
        let cells = [
            (218., 10., 35., "Zimmer"),
            (278., 10., 30., "123"),
            (65., 60., 33., "Uhrzeit"),
            (130., 60., 38., "Therapie"),
            (254., 60., 23., "Raum"),
            (339., 60., 38., "Therapeut"),
            (50., 80., 200., "Donnerstag, der 10.09.2026"),
            (48., 110., 74., "*Neu 06:30 - 07:30"),
            (135., 110., 60., "Frühstück"),
            (48., 150., 74., "*Neu 08:00 - 08:30"),
            (135., 150., 110., "Lange Behandlung"),
            (256., 150., 155., "Raum 107 Hr. A. Beispiel"),
            (346., 162., 13., "BA"),
            (48., 200., 74., "*Neu 09:00 - 09:30"),
            (135., 200., 115., "Weitere lange Behandlung"),
            (256., 200., 78., "bitte im Zimmer bleiben"),
            (344., 200., 65., "Fr. B. Beispiel BSc"),
        ];
        let regions: Vec<_> = cells
            .iter()
            .enumerate()
            .map(|(i, (x, y, width, _))| Region {
                id: format!("r{i}"),
                polygon: crate::geometry::rect(*x, *y, *width, 10.),
                frame: "page".into(),
                kind: "text".into(),
                parent: None,
                children: vec![],
            })
            .collect();
        let observations: Vec<_> = cells
            .iter()
            .enumerate()
            .map(|(i, (_, _, _, text))| Observation {
                id: format!("o{i}"),
                text: text.to_string(),
                region_ids: vec![format!("r{i}")],
                score: Some(0.99),
                engine: "fixture".into(),
                alternatives: vec![],
            })
            .collect();
        let a = extract("header-and-padding", &observations, &regions).0;
        assert_eq!(a.len(), 3);
        for row in &a {
            assert!(
                row.fields["start"].reasons.is_empty(),
                "{:?}",
                row.fields["start"]
            );
            assert!(
                row.fields["title"].reasons.is_empty(),
                "{:?}",
                row.fields["title"]
            );
        }
        assert_eq!(a[2].location, "bitte im Zimmer bleiben");
        assert!(a[2].fields["location"].reasons.is_empty());
        assert!(a[2].fields["therapist"].reasons.is_empty());
        assert!(a[1].fields["location"]
            .reasons
            .iter()
            .any(|r| r.contains("Spaltengrenze")));
        assert!(a[1].fields["therapist"]
            .reasons
            .iter()
            .any(|r| r.contains("Isolierter Titel")));
        // The surviving degree locates this row's name-column edge; a global
        // separator would cut the room suffix into the therapist rereading.
        assert_eq!(a[1].fields["location"].polygon[1].x, 346.);
        assert_eq!(a[1].fields["therapist"].polygon[0].x, 346.);
        assert_eq!(a[0].fields["location"].state, PrintedState::Unreviewed);
        assert_eq!(a[0].fields["therapist"].state, PrintedState::Unreviewed);
    }
    #[test]
    fn empty_reading_does_not_erase_conflicting_column_evidence() {
        let mut appointment = Appointment::empty("blank-conflict".into());
        appointment
            .provenance
            .insert("location".into(), vec!["empty-reading".into()]);
        let observations = vec![Observation {
            id: "empty-reading".into(),
            text: "".into(),
            region_ids: vec!["crossing".into()],
            score: Some(0.4),
            engine: "fixture".into(),
            alternatives: vec![],
        }];
        let regions = vec![Region {
            id: "crossing".into(),
            polygon: crate::geometry::rect(100., 80., 120., 10.),
            frame: "page".into(),
            kind: "text".into(),
            parent: None,
            children: vec![],
        }];
        let boundaries = vec![("location", 100.), ("therapist", 160.)];
        let columns = Columns(boundaries.clone(), false, boundaries);
        assess_fields(&mut appointment, &columns, &observations, &regions);
        let field = &appointment.fields["location"];
        assert_eq!(field.state, PrintedState::Contradictory);
        assert!(field
            .reasons
            .iter()
            .any(|reason| reason.contains("Spaltengrenze")));
        assert!(field
            .reasons
            .iter()
            .any(|reason| reason.contains("Leer erkannt")));
        assert!(!crate::review::field_confirmed(&appointment, "location"));
        assert!(crate::review::field_problems(&appointment)
            .iter()
            .any(|issue| issue.field.as_deref() == Some("location") && issue.blocking));
    }
    #[test]
    fn a_single_time_range_may_span_start_and_end_columns() {
        let (a, _, _) = positioned(&[
            (0., 0., "Donnerstag, der 10.09.2026"),
            (0., 40., "Von"),
            (90., 40., "Bis"),
            (250., 40., "Therapie"),
            (0., 80., "08:00 - 08:30"),
            (250., 80., "Beispiel"),
        ]);
        assert_eq!(a.len(), 1);
        assert_eq!(a[0].end.as_deref(), Some("08:30"));
        assert!(a[0].fields["start"].reasons.is_empty());
    }
    #[test]
    fn varying_table_baselines_remain_invertible() {
        let alignment = TableAlignment {
            base: [1., 0., 0., -0.07, 1., 0., 0., 0., 1.],
            samples: vec![(0., 0.01), (500., -0.02), (1000., 0.03)],
        };
        for y in [-100., 0., 150., 500., 750., 1100.] {
            for x in [0., 100., 1200.] {
                let p = Point { x, y };
                let q = alignment.backward(&alignment.forward(&p));
                assert!((q.y - y).abs() < 1e-7 && (q.x - x).abs() < 1e-7);
            }
        }
    }
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
    fn unreadable_and_invalid_day_headings_never_inherit_previous_day() {
        for heading in [
            "Sonntag",
            "Sonntag, der ??.09.2026",
            "Sonntag, der unleserlich",
            "Sonntag, der 31.09.2026",
            "Sonntag, der 12.09.2026",
        ] {
            let (a, _, _) = parse(&[
                "Samstag, der 12.09.2026",
                "08:00 - 08:30 Erster Tag",
                heading,
                "09:00 - 09:30 Unklarer Tag",
                "Montag, der 14.09.2026",
                "10:00 - 10:30 Dritter Tag",
            ]);
            assert_eq!(a.len(), 3, "{heading}");
            assert_eq!(a[0].date.as_deref(), Some("2026-09-12"), "{heading}");
            assert_eq!(a[1].date, None, "{heading}");
            assert_eq!(a[2].date.as_deref(), Some("2026-09-14"), "{heading}");
            assert!(a[1]
                .issues
                .iter()
                .any(|i| i.blocking && i.field.as_deref() == Some("date")));
        }
    }
    #[test]
    fn comma_separated_day_is_validated_against_weekday_and_retains_evidence() {
        let (a, _, _) = parse(&[
            "Samstag, der 12.09.2026",
            "08:00 - 08:30 Erster Tag",
            "Sonntag, der 13,09.2026",
            "09:00 - 09:30 Zweiter Tag",
        ]);
        assert_eq!(a.len(), 2);
        assert_eq!(a[0].date.as_deref(), Some("2026-09-12"));
        assert_eq!(a[1].date.as_deref(), Some("2026-09-13"));
        assert_eq!(a[1].provenance["date"], ["o2"]);
        let (a, _, _) = parse(&["Montag, der 13,09.2026", "09:00 - 09:30 Therapie"]);
        assert!(a[0].date.is_none());
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
