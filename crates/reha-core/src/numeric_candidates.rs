//! Use only alternatives actually returned by OCR. No character substitution,
//! dictionary completion or repeated-reader voting creates a printed number.
use crate::contracts::*;
use chrono::{Datelike, NaiveDate};
use regex::Regex;
use std::{borrow::Cow, collections::BTreeMap, sync::LazyLock};

fn signature(text: &str) -> Option<String> {
    static CLOCK: LazyLock<Regex> = LazyLock::new(|| {
        Regex::new(
            r"^\s*([01]?\d|2[0-3])[:.]([0-5]\d)(?:\s*[-–]\s*([01]?\d|2[0-3])[:.]([0-5]\d))?\s*$",
        )
        .unwrap()
    });
    static DAY: LazyLock<Regex> = LazyLock::new(|| {
        Regex::new(r"(?i)^\s*(montag|dienstag|mittwoch|donnerstag|freitag|samstag|sonntag),?\s*(?:der\s*)?(\d{1,2})[./](\d{1,2})[./](\d{4})\s*\.?$").unwrap()
    });
    if let Some(c) = CLOCK.captures(text) {
        return Some(format!(
            "{:0>2}:{}-{:0>2}:{}",
            &c[1],
            &c[2],
            c.get(3).map_or("", |s| s.as_str()),
            c.get(4).map_or("", |s| s.as_str())
        ));
    }
    let c = DAY.captures(text)?;
    let date = NaiveDate::from_ymd_opt(c[4].parse().ok()?, c[3].parse().ok()?, c[2].parse().ok()?)?;
    let weekday = [
        "montag",
        "dienstag",
        "mittwoch",
        "donnerstag",
        "freitag",
        "samstag",
        "sonntag",
    ]
    .iter()
    .position(|d| *d == c[1].to_lowercase())?;
    (date.weekday().num_days_from_monday() as usize == weekday).then(|| date.to_string())
}

fn numeric_like(text: &str) -> bool {
    static CLOCK_LIKE: LazyLock<Regex> = LazyLock::new(|| {
        Regex::new(
            r"(?i)^\s*[0-9oil]{1,2}[:.][0-9oil]{2}(?:\s*[-–]\s*[0-9oil]{1,2}[:.][0-9oil]{2})?\s*$",
        )
        .unwrap()
    });
    static DATE_LIKE: LazyLock<Regex> = LazyLock::new(|| {
        Regex::new(r"(?i)^\s*(montag|dienstag|mittwoch|donnerstag|freitag|samstag|sonntag),?\s*(?:der\s*)?[0-9oil]{1,2}[./][0-9oil]{1,2}[./][0-9oil]{4}\s*\.?$").unwrap()
    });
    CLOCK_LIKE.is_match(text) || DATE_LIKE.is_match(text)
}

pub(crate) fn prepare(
    observations: &[Observation],
) -> (Cow<'_, [Observation]>, BTreeMap<String, PrintedState>) {
    let mut output = Cow::Borrowed(observations);
    let mut changed = BTreeMap::new();
    for (index, observation) in observations
        .iter()
        .enumerate()
        .filter(|(_, o)| !o.alternatives.is_empty())
    {
        let alternatives: BTreeMap<_, _> = observation
            .alternatives
            .iter()
            .filter_map(|text| signature(text).map(|value| (value, text)))
            .collect();
        if alternatives.is_empty() {
            continue;
        }
        if let Some(primary) = signature(&observation.text) {
            if alternatives.keys().any(|value| value != &primary) {
                changed.insert(observation.id.clone(), PrintedState::Contradictory);
            }
        } else if alternatives.len() == 1 && numeric_like(&observation.text) {
            // An unrelated word must not become a clock merely because a low-ranked
            // OCR candidate contains one. Require printed-looking number punctuation.
            output.to_mut()[index].text = (*alternatives.values().next().unwrap()).clone();
            changed.insert(observation.id.clone(), PrintedState::Unreviewed);
        } else if alternatives.len() > 1 && numeric_like(&observation.text) {
            changed.insert(observation.id.clone(), PrintedState::Contradictory);
        }
    }
    (output, changed)
}

#[cfg(test)]
mod tests {
    use super::*;
    fn observation(text: &str, alternatives: &[&str]) -> Observation {
        Observation {
            id: "o".into(),
            text: text.into(),
            region_ids: vec!["r".into()],
            engine: "test".into(),
            score: None,
            alternatives: alternatives.iter().map(|s| (*s).into()).collect(),
        }
    }
    #[test]
    fn alternatives_never_change_originals_or_choose_between_valid_numbers() {
        let source = vec![observation("O8:3O", &["08:30", "08.30"])];
        let (prepared, flags) = prepare(&source);
        assert_eq!(signature(&prepared[0].text), signature("08:30"));
        assert_eq!(source[0].text, "O8:3O");
        assert_eq!(flags["o"], PrintedState::Unreviewed);
        let source = vec![observation("08:30", &["09:30"])];
        let (prepared, flags) = prepare(&source);
        assert_eq!(prepared[0].text, "08:30");
        assert_eq!(flags["o"], PrintedState::Contradictory);
        for text in ["Name", "Dr.", "Raum 8.30", "Abt./A"] {
            let source = vec![observation(text, &["08:30", "09:30"])];
            assert!(prepare(&source).1.is_empty());
            assert_eq!(prepare(&source).0[0].text, text);
        }
    }
    #[test]
    fn dates_need_real_calendar_and_matching_weekday() {
        assert!(signature("Samstag, der 08.05.2026").is_none());
        assert_eq!(
            signature("Samstag, der 09.05.2026").as_deref(),
            Some("2026-05-09")
        );
        assert!(signature("Montag, der 31.02.2026").is_none());
        assert!(signature("Raum 08:30").is_none());
        assert!(signature("24:15").is_none());
    }
}
