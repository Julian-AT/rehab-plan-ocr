use crate::{contracts::*, Error, Result};
use chrono::{DateTime, Duration, LocalResult, NaiveDate, NaiveTime, TimeZone, Utc};
use chrono_tz::Tz;
use std::collections::{BTreeMap, HashSet};

pub fn event_values(a: &Appointment, timezone: &str, reminder: Option<u32>) -> Result<EventValues> {
    let issues = crate::parser::validate(a);
    if let Some(issue) = issues.iter().find(|i| i.blocking) {
        return Err(Error::Invalid(issue.message.clone()));
    }
    if a.issues.iter().any(|i| {
        i.blocking
            && ![
                "missing_date",
                "missing_start",
                "missing_end",
                "invalid_end",
                "overnight_confirmation",
                "missing_title",
            ]
            .contains(&i.code.as_str())
    }) {
        return Err(Error::Invalid(
            "Ungeklärte Erkennungsprobleme zuerst bestätigen.".into(),
        ));
    }
    let zone: Tz = timezone
        .parse()
        .map_err(|_| Error::Invalid("Unbekannte Zeitzone.".into()))?;
    let date = NaiveDate::parse_from_str(a.date.as_deref().unwrap_or(""), "%Y-%m-%d")
        .map_err(|_| Error::Invalid("Ungültiges Datum".into()))?;
    let start = NaiveTime::parse_from_str(a.start.as_deref().unwrap_or(""), "%H:%M")
        .map_err(|_| Error::Invalid("Ungültige Zeit".into()))?;
    let resolve = |d| {
        match zone.from_local_datetime(&d) {
        LocalResult::Single(t)=>Ok(t.with_timezone(&Utc)),
        LocalResult::Ambiguous(_,_)=>Err(Error::Invalid("Zeit ist bei der Zeitumstellung doppeldeutig. In UTC mit geprüftem Zeitpunkt erfassen.".into())),
        LocalResult::None=>Err(Error::Invalid("Diese lokale Zeit existiert wegen der Zeitumstellung nicht.".into()))
    }
    };
    let start = resolve(date.and_time(start))?;
    let end = if let Some(end) = &a.end {
        let end_date = if let Some(d) = &a.end_date {
            NaiveDate::parse_from_str(d, "%Y-%m-%d")
                .map_err(|_| Error::Invalid("Enddatum ungültig".into()))?
        } else {
            date
        };
        let t = NaiveTime::parse_from_str(end, "%H:%M")
            .map_err(|_| Error::Invalid("Endzeit ungültig".into()))?;
        resolve(end_date.and_time(t))?
    } else {
        start + Duration::minutes(a.duration_minutes.unwrap_or(0) as i64)
    };
    if end <= start || end - start > Duration::hours(24) {
        return Err(Error::Invalid(
            "Dauer muss zwischen 1 Minute und 24 Stunden liegen.".into(),
        ));
    }
    if let Some(duration) = a.duration_minutes {
        if (end - start).num_minutes() != duration as i64 {
            return Err(Error::Invalid(
                "Gedruckte Dauer und Endzeit widersprechen sich.".into(),
            ));
        }
    }
    if reminder.is_some_and(|m| m > 10080) {
        return Err(Error::Invalid(
            "Erinnerung maximal sieben Tage vor Termin.".into(),
        ));
    }
    Ok(EventValues {
        title: a.title.trim().into(),
        start_utc: start.to_rfc3339_opts(chrono::SecondsFormat::Secs, true),
        end_utc: end.to_rfc3339_opts(chrono::SecondsFormat::Secs, true),
        timezone: timezone.into(),
        location: a.location.trim().into(),
        notes: if a.therapist.trim().is_empty() {
            a.notes.trim().into()
        } else {
            [
                format!("Therapeut: {}", a.therapist.trim()),
                a.notes.trim().into(),
            ]
            .into_iter()
            .filter(|part| !part.is_empty())
            .collect::<Vec<_>>()
            .join("\n")
        },
        reminder_minutes: reminder,
    })
}

pub fn schedule_fingerprint(events: &[EventValues]) -> String {
    let mut items: Vec<_> = events
        .iter()
        .map(|e| serde_json::to_string(e).unwrap())
        .collect();
    items.sort(); // Deliberately no deduplication: two identical appointments remain two.
    crate::hash(items.join("\n").as_bytes())
}

fn merge_field<T: Eq + Clone>(old: &T, current: &T, new: &T) -> Option<T> {
    if current == old {
        Some(new.clone())
    } else if new == old || new == current {
        Some(current.clone())
    } else {
        None
    }
}
pub fn three_way(
    old: &EventValues,
    current: &EventValues,
    new: &EventValues,
) -> Option<EventValues> {
    // Start/end/timezone form one atomic field to avoid manufacturing an invalid interval.
    let (start_utc, end_utc, timezone) = merge_field(
        &(
            old.start_utc.clone(),
            old.end_utc.clone(),
            old.timezone.clone(),
        ),
        &(
            current.start_utc.clone(),
            current.end_utc.clone(),
            current.timezone.clone(),
        ),
        &(
            new.start_utc.clone(),
            new.end_utc.clone(),
            new.timezone.clone(),
        ),
    )?;
    Some(EventValues {
        title: merge_field(&old.title, &current.title, &new.title)?,
        start_utc,
        end_utc,
        timezone,
        location: merge_field(&old.location, &current.location, &new.location)?,
        notes: merge_field(&old.notes, &current.notes, &new.notes)?,
        reminder_minutes: merge_field(
            &old.reminder_minutes,
            &current.reminder_minutes,
            &new.reminder_minutes,
        )?,
    })
}

pub fn propose(
    old: &[ImportRecord],
    new: &[(String, EventValues)],
    current: &BTreeMap<String, EventValues>,
    calendar_id: &str,
    complete: bool,
) -> Vec<CalendarOperation> {
    let mut matches = vec![None; new.len()];
    let mut used = HashSet::new();
    // Exact values first; consume one old event per new row to preserve multiplicity.
    for (i, (_, value)) in new.iter().enumerate() {
        if let Some((j, _)) = old
            .iter()
            .enumerate()
            .find(|(j, o)| !used.contains(j) && o.approved == *value)
        {
            matches[i] = Some(j);
            used.insert(j);
        }
    }
    let candidate = |o: &EventValues, n: &EventValues| {
        (o.title == n.title && o.location == n.location)
            || (o.start_utc == n.start_utc && o.end_utc == n.end_utc)
    };
    for (i, (_, value)) in new
        .iter()
        .enumerate()
        .filter(|(i, _)| matches[*i].is_none())
        .collect::<Vec<_>>()
    {
        let candidates: Vec<_> = old
            .iter()
            .enumerate()
            .filter(|(j, o)| !used.contains(j) && candidate(&o.approved, value))
            .map(|(j, _)| j)
            .collect();
        if candidates.len() == 1 {
            let j = candidates[0];
            let competitors = new
                .iter()
                .enumerate()
                .filter(|(k, (_, n))| matches[*k].is_none() && candidate(&old[j].approved, n))
                .count();
            if competitors == 1 {
                matches[i] = Some(j);
                used.insert(j);
            }
        }
    }
    let mut operations = vec![];
    for (i, (id, value)) in new.iter().enumerate() {
        if let Some(j) = matches[i] {
            let record = &old[j];
            let live = current.get(&record.id);
            let merged = live.and_then(|live| three_way(&record.approved, live, value));
            let conflict = merged.is_none();
            let after = merged.unwrap_or_else(|| value.clone());
            let kind = if conflict {
                "conflict"
            } else if live == Some(&after) {
                "unchanged"
            } else {
                "update"
            };
            operations.push(CalendarOperation {
                kind: kind.into(),
                id: record.id.clone(),
                calendar_id: record.calendar_id.clone(),
                external_id: record.external_id.clone(),
                before: live.cloned(),
                after: Some(after),
                requires_resolution: conflict,
                reason: if live.is_none() {
                    "Kalendereintrag fehlt oder ist nicht lesbar."
                } else if conflict {
                    "Kalender und Papier ändern dasselbe Feld. Manuell auflösen."
                } else {
                    "Änderungen im Kalender werden feldweise erhalten."
                }
                .into(),
            });
        } else {
            let ambiguous = old
                .iter()
                .enumerate()
                .any(|(j, o)| !used.contains(&j) && candidate(&o.approved, value));
            operations.push(CalendarOperation {
                kind: if ambiguous { "ambiguous" } else { "create" }.into(),
                id: id.clone(),
                calendar_id: calendar_id.into(),
                external_id: None,
                before: None,
                after: Some(value.clone()),
                requires_resolution: ambiguous,
                reason: if ambiguous {
                    "Mehrere mögliche Zuordnungen. Vorherigen Plan und neuen Termin prüfen."
                } else {
                    "Neuer Termin"
                }
                .into(),
            });
        }
    }
    for (j, record) in old.iter().enumerate().filter(|(j, _)| !used.contains(j)) {
        let ambiguous = new
            .iter()
            .enumerate()
            .any(|(i, (_, n))| matches[i].is_none() && candidate(&old[j].approved, n));
        let live = current.get(&record.id);
        let conflict = live != Some(&record.approved);
        operations.push(CalendarOperation {
            kind: if complete && !ambiguous && !conflict {
                "remove"
            } else {
                "keep"
            }
            .into(),
            id: record.id.clone(),
            calendar_id: record.calendar_id.clone(),
            external_id: record.external_id.clone(),
            before: live.cloned(),
            after: None,
            requires_resolution: complete && (ambiguous || conflict),
            reason: if !complete {
                "Unvollständige Seite: keine Löschung ableiten."
            } else if ambiguous {
                "Zuordnung unklar: bisherigen Termin erhalten."
            } else if conflict {
                "Kalendereintrag wurde verändert oder fehlt. Erhalten."
            } else {
                "Nicht mehr im vollständig bestätigten Ersatzplan. Löschung separat bestätigen."
            }
            .into(),
        });
    }
    operations
}

fn escaped(s: &str) -> String {
    s.replace('\\', "\\\\")
        .replace('\r', "")
        .replace('\n', "\\n")
        .replace(';', "\\;")
        .replace(',', "\\,")
}
fn fold(line: &str) -> String {
    let mut out = String::new();
    let mut count = 0;
    for c in line.chars() {
        let len = c.len_utf8();
        if count + len > 75 {
            out.push_str("\r\n ");
            count = 1;
        }
        out.push(c);
        count += len;
    }
    out.push_str("\r\n");
    out
}
pub fn ics(events: &[(String, EventValues)], now: DateTime<Utc>) -> Result<String> {
    let mut lines = vec![
        "BEGIN:VCALENDAR".into(),
        "VERSION:2.0".into(),
        "PRODID:-//Reha Calendar Lab//Local schedule import//EN".into(),
        "CALSCALE:GREGORIAN".into(),
    ];
    for (id, e) in events {
        let uid = uuid::Uuid::parse_str(id)
            .map_err(|_| Error::Invalid("Invalid stable event identifier".into()))?;
        let start = DateTime::parse_from_rfc3339(&e.start_utc)
            .map_err(|_| Error::Invalid("Invalid start".into()))?
            .with_timezone(&Utc);
        let end = DateTime::parse_from_rfc3339(&e.end_utc)
            .map_err(|_| Error::Invalid("Invalid end".into()))?
            .with_timezone(&Utc);
        if end <= start {
            return Err(Error::Invalid("Invalid event interval".into()));
        }
        lines.extend([
            "BEGIN:VEVENT".into(),
            format!("UID:{uid}@reha-calendar.local"),
            format!("DTSTAMP:{}", now.format("%Y%m%dT%H%M%SZ")),
            format!("DTSTART:{}", start.format("%Y%m%dT%H%M%SZ")),
            format!("DTEND:{}", end.format("%Y%m%dT%H%M%SZ")),
            format!("SUMMARY:{}", escaped(&e.title)),
            format!("LOCATION:{}", escaped(&e.location)),
            format!("DESCRIPTION:{}", escaped(&e.notes)),
            format!("X-REHA-TIMEZONE:{}", escaped(&e.timezone)),
        ]);
        if let Some(minutes) = e.reminder_minutes {
            lines.extend([
                "BEGIN:VALARM".into(),
                format!("TRIGGER:-PT{minutes}M"),
                "ACTION:DISPLAY".into(),
                format!("DESCRIPTION:{}", escaped(&e.title)),
                "END:VALARM".into(),
            ]);
        }
        lines.push("END:VEVENT".into());
    }
    lines.push("END:VCALENDAR".into());
    Ok(lines.iter().map(|l| fold(l)).collect())
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn therapist_is_preserved_in_calendar_description() {
        let mut a = app("2026-04-30", "08:00", "08:30");
        a.therapist = "Alex Beispiel MSc".into();
        a.notes = "Bring towel".into();
        let values = event_values(&a, "Europe/Vienna", None).unwrap();
        assert_eq!(values.notes, "Therapeut: Alex Beispiel MSc\nBring towel");
        let mut legacy = serde_json::to_value(&a).unwrap();
        legacy.as_object_mut().unwrap().remove("therapist");
        let decoded: Appointment = serde_json::from_value(legacy).unwrap();
        assert!(decoded.therapist.is_empty());
    }
    fn app(date: &str, start: &str, end: &str) -> Appointment {
        let mut a = Appointment::empty(uuid::Uuid::new_v4().to_string());
        a.date = Some(date.into());
        a.start = Some(start.into());
        a.end = Some(end.into());
        a.title = "Übung".into();
        a
    }
    fn event() -> EventValues {
        event_values(&app("2026-09-10", "08:00", "08:30"), "Europe/Vienna", None).unwrap()
    }
    fn old(e: EventValues) -> ImportRecord {
        ImportRecord {
            id: uuid::Uuid::new_v4().to_string(),
            schedule_id: "day".into(),
            calendar_id: "calendar".into(),
            external_id: Some("external".into()),
            approved: e,
            status: "saved".into(),
            operation_id: "op".into(),
        }
    }
    #[test]
    fn vienna_to_utc() {
        assert_eq!(event().start_utc, "2026-09-10T06:00:00Z");
    }
    #[test]
    fn dst_nonexistent_and_ambiguous_rejected() {
        for (d, s, e) in [
            ("2026-03-29", "02:10", "03:10"),
            ("2026-10-25", "02:10", "03:10"),
        ] {
            assert!(event_values(&app(d, s, e), "Europe/Vienna", None).is_err());
        }
    }
    #[test]
    fn midnight_requires_end_date() {
        let mut a = app("2026-09-10", "23:45", "00:15");
        assert!(event_values(&a, "Europe/Vienna", None).is_err());
        a.end_date = Some("2026-09-11".into());
        assert!(event_values(&a, "Europe/Vienna", None).is_ok());
    }
    #[test]
    fn duration_conflict_rejected() {
        let mut a = app("2026-09-10", "08:00", "08:30");
        a.duration_minutes = Some(20);
        assert!(event_values(&a, "Europe/Vienna", None).is_err());
    }
    #[test]
    fn duplicate_multiplicity() {
        assert_ne!(
            schedule_fingerprint(&[event()]),
            schedule_fingerprint(&[event(), event()])
        );
    }
    #[test]
    fn manual_notes_preserved() {
        let old = event();
        let mut live = old.clone();
        live.notes = "Eigene Notiz".into();
        let mut next = old.clone();
        next.location = "B2".into();
        let result = three_way(&old, &live, &next).unwrap();
        assert_eq!(result.notes, live.notes);
        assert_eq!(result.location, next.location);
    }
    #[test]
    fn competing_edit_conflicts() {
        let old = event();
        let mut live = old.clone();
        live.title = "My title".into();
        let mut next = old.clone();
        next.title = "Paper title".into();
        assert!(three_way(&old, &live, &next).is_none());
    }
    #[test]
    fn crop_never_removes() {
        let o = old(event());
        let live = BTreeMap::from([(o.id.clone(), o.approved.clone())]);
        assert_eq!(propose(&[o], &[], &live, "calendar", false)[0].kind, "keep");
    }
    #[test]
    fn repeated_exact_events_consumed_once() {
        let a = old(event());
        let b = old(event());
        let live = BTreeMap::from([
            (a.id.clone(), a.approved.clone()),
            (b.id.clone(), b.approved.clone()),
        ]);
        let p = propose(
            &[a, b],
            &[("1".into(), event()), ("2".into(), event())],
            &live,
            "calendar",
            true,
        );
        assert_eq!(p.len(), 2);
        assert!(p.iter().all(|x| x.kind == "unchanged"));
        assert_ne!(p[0].id, p[1].id);
    }
    #[test]
    fn ambiguous_moves_not_guessed() {
        let a = old(event());
        let b = old(event());
        let mut e = event();
        e.start_utc = "2026-09-10T07:00:00Z".into();
        let p = propose(
            &[a, b],
            &[("new".into(), e)],
            &BTreeMap::new(),
            "calendar",
            true,
        );
        assert_eq!(p[0].kind, "ambiguous");
        assert!(p.iter().all(|x| x.kind != "remove"));
    }
    #[test]
    fn ics_escapes_folds_utf8_and_stable_uid() {
        let mut e = event();
        e.title = "Ü".repeat(100);
        e.notes = "A,B;C\\D\nEND:VEVENT".into();
        let id = uuid::Uuid::new_v4().to_string();
        let text = ics(&[(id.clone(), e)], Utc::now()).unwrap();
        assert!(text.contains(&format!("UID:{id}@")));
        assert!(text.contains("A\\,B\\;C\\\\D\\nEND:VEVENT"));
        assert!(text.split("\r\n").all(|l| l.len() <= 75));
        assert!(text.contains("DTSTART:20260910T060000Z"));
    }
}
