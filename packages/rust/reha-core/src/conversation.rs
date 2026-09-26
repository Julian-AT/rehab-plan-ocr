//! Strict model-output decoding. Interpretation never executes calendar operations.

use crate::{Error, Result};
use chrono::{Datelike, NaiveDate};
use serde::{Deserialize, Deserializer, Serialize};
use std::collections::HashSet;

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(tag = "action", rename_all = "snake_case", deny_unknown_fields)]
pub enum AssistantRequest {
    Calendar { query: Query },
    Create { change: Change },
    Update { query: Reference, change: Change },
    Remove { query: Reference },
    Cancel {},
    Help { topic: HelpTopic },
    Clarify { problem: Problem },
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Query {
    pub detail: Detail,
    #[serde(
        default,
        deserialize_with = "present",
        skip_serializing_if = "Option::is_none"
    )]
    pub date: Option<String>,
    #[serde(
        default,
        deserialize_with = "present",
        skip_serializing_if = "Option::is_none"
    )]
    pub reference: Option<String>,
    #[serde(
        default,
        deserialize_with = "present",
        skip_serializing_if = "Option::is_none"
    )]
    pub after: Option<String>,
    #[serde(
        default,
        deserialize_with = "present",
        skip_serializing_if = "Option::is_none"
    )]
    pub before: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Reference {
    pub reference: String,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Change {
    #[serde(
        default,
        deserialize_with = "present",
        skip_serializing_if = "Option::is_none"
    )]
    pub title: Option<String>,
    #[serde(
        default,
        deserialize_with = "present",
        skip_serializing_if = "Option::is_none"
    )]
    pub date: Option<String>,
    #[serde(
        default,
        deserialize_with = "present",
        skip_serializing_if = "Option::is_none"
    )]
    pub time: Option<String>,
    #[serde(
        default,
        deserialize_with = "present",
        skip_serializing_if = "Option::is_none"
    )]
    pub duration: Option<u16>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum Detail {
    Next,
    List,
    Count,
    Room,
    Therapist,
    Start,
    End,
    Duration,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum HelpTopic {
    Capture,
    Calendars,
    Archive,
    Voice,
    Privacy,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum Problem {
    InvalidDate,
    Ambiguous,
    MissingDate,
    MissingTime,
    MissingTitle,
    MissingEvent,
    Unsupported,
}

// A missing optional field is absent; explicit null is not a permitted value in
// the trained compact schema. Derivation also rejects duplicate and unknown keys.
fn present<'de, T: Deserialize<'de>, D: Deserializer<'de>>(
    deserializer: D,
) -> std::result::Result<Option<T>, D::Error> {
    T::deserialize(deserializer).map(Some)
}

fn require(value: bool) -> Result<()> {
    if value {
        Ok(())
    } else {
        // Do not echo model/user/calendar content into boundary errors.
        Err(Error::Invalid(
            "Invalid structured assistant request".into(),
        ))
    }
}

fn date(value: &str) -> bool {
    value.len() == 10
        && NaiveDate::parse_from_str(value, "%Y-%m-%d").is_ok_and(|date| {
            (1..=9999).contains(&date.year()) && date.format("%Y-%m-%d").to_string() == value
        })
}

pub fn clock_minutes(value: &str) -> Option<u16> {
    let bytes = value.as_bytes();
    if bytes.len() != 5
        || bytes[2] != b':'
        || ![0, 1, 3, 4].iter().all(|&i| bytes[i].is_ascii_digit())
    {
        return None;
    }
    let hour = (bytes[0] - b'0') as u16 * 10 + (bytes[1] - b'0') as u16;
    let minute = (bytes[3] - b'0') as u16 * 10 + (bytes[4] - b'0') as u16;
    (hour < 24 && minute < 60).then_some(hour * 60 + minute)
}

impl Change {
    fn validate(&self, create: bool) -> Result<()> {
        require(
            self.title.is_some()
                || self.date.is_some()
                || self.time.is_some()
                || self.duration.is_some(),
        )?;
        require(!create || (self.title.is_some() && self.date.is_some() && self.time.is_some()))?;
        require(
            self.title
                .as_ref()
                .is_none_or(|s| !s.trim().is_empty() && s.chars().count() <= 200),
        )?;
        require(self.date.as_deref().is_none_or(date))?;
        require(
            self.time
                .as_deref()
                .is_none_or(|s| clock_minutes(s).is_some()),
        )?;
        require(self.duration.is_none_or(|n| (1..=1440).contains(&n)))
    }
}

pub fn decode(text: &str, visible_references: &[String]) -> Result<AssistantRequest> {
    require(!text.is_empty() && text.chars().count() <= 4096 && text.len() <= 16_384)?;
    require(visible_references.len() <= 64)?;
    let references: HashSet<_> = visible_references.iter().collect();
    require(
        references.len() == visible_references.len()
            && visible_references
                .iter()
                .all(|r| !r.is_empty() && r.len() <= 128),
    )?;
    let request: AssistantRequest = serde_json::from_str(text)
        .map_err(|_| Error::Invalid("Invalid structured assistant JSON".into()))?;
    match &request {
        AssistantRequest::Calendar { query } => {
            require(query.date.is_some() || query.reference.is_some())?;
            require(query.date.as_deref().is_none_or(date))?;
            require(
                query
                    .reference
                    .as_ref()
                    .is_none_or(|r| references.contains(r)),
            )?;
            require(
                query
                    .after
                    .as_deref()
                    .is_none_or(|s| clock_minutes(s).is_some()),
            )?;
            require(
                query
                    .before
                    .as_deref()
                    .is_none_or(|s| clock_minutes(s).is_some()),
            )?;
            if let (Some(after), Some(before)) = (&query.after, &query.before) {
                require(after < before)?;
            }
        }
        AssistantRequest::Create { change } => change.validate(true)?,
        AssistantRequest::Update { query, change } => {
            require(references.contains(&query.reference))?;
            change.validate(false)?;
        }
        AssistantRequest::Remove { query } => require(references.contains(&query.reference))?,
        AssistantRequest::Cancel {}
        | AssistantRequest::Help { .. }
        | AssistantRequest::Clarify { .. } => {}
    }
    Ok(request)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn compact_contract_rejects_duplicate_unknown_null_and_unsafe_targets() {
        let fixtures: serde_json::Value = serde_json::from_str(include_str!(
            "../../../../ml/evaluation/conversation/fixtures/native-contract.json"
        ))
        .unwrap();
        for row in fixtures.as_array().unwrap() {
            let references: Vec<String> =
                serde_json::from_value(row["references"].clone()).unwrap();
            let result = decode(row["json"].as_str().unwrap(), &references);
            assert_eq!(
                result.is_ok(),
                row["valid"].as_bool().unwrap(),
                "{}: {result:?}",
                row["id"]
            );
            if let Ok(value) = result {
                assert_eq!(
                    serde_json::to_value(value).unwrap(),
                    serde_json::from_str::<serde_json::Value>(row["json"].as_str().unwrap())
                        .unwrap()
                );
            }
        }
    }

    #[test]
    fn reference_and_output_admission_is_bounded() {
        assert!(decode(r#"{"action":"cancel"}"#, &["r1".into(), "r1".into()]).is_err());
        assert!(decode(r#"{"action":"cancel"}"#, &["".into()]).is_err());
        assert!(decode(
            &format!("{}{{\"action\":\"cancel\"}}", " ".repeat(4096)),
            &[]
        )
        .is_err());
        assert!(decode(r#"{"action":"cancel"} [end of text]"#, &[]).is_err());
        assert_eq!(clock_minutes("23:59"), Some(1439));
        assert_eq!(clock_minutes("24:00"), None);
    }
}
