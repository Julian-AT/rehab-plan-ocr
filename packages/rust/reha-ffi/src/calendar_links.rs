use reha_core::service::calendar_links as core;

#[derive(Clone, Debug, uniffi::Record)]
pub struct CalendarLinkInspection {
    pub calendar_ids: Vec<String>,
    pub results: Vec<CalendarLinkResult>,
}
#[derive(Clone, Debug, uniffi::Record)]
pub struct CalendarLinkResult {
    pub id: String,
    pub state: CalendarLinkState,
}
#[derive(Clone, Debug, uniffi::Enum)]
pub enum CalendarLinkState {
    Found {
        calendar_id: String,
        external_id: String,
        ownership_url: Option<String>,
    },
    Deleted {
        reason: Option<String>,
    },
    Unavailable {
        reason: Option<String>,
    },
}
impl From<CalendarLinkInspection> for core::Inspection {
    fn from(value: CalendarLinkInspection) -> Self {
        Self {
            calendar_ids: value.calendar_ids,
            results: value
                .results
                .into_iter()
                .map(|r| core::LinkResult {
                    id: r.id,
                    state: match r.state {
                        CalendarLinkState::Found {
                            calendar_id,
                            external_id,
                            ownership_url,
                        } => core::LinkState::Found {
                            calendar_id,
                            external_id,
                            ownership_url,
                        },
                        CalendarLinkState::Deleted { reason } => {
                            core::LinkState::Deleted { reason }
                        }
                        CalendarLinkState::Unavailable { reason } => {
                            core::LinkState::Unavailable { reason }
                        }
                    },
                })
                .collect(),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn ownership_evidence_and_missing_reasons_survive_typed_projection() {
        let result: core::Inspection = CalendarLinkInspection {
            calendar_ids: vec!["hidden-but-readable".into()],
            results: vec![
                CalendarLinkResult {
                    id: "found".into(),
                    state: CalendarLinkState::Found {
                        calendar_id: "hidden-but-readable".into(),
                        external_id: "actual-event".into(),
                        ownership_url: Some("reha-calendar://event/found".into()),
                    },
                },
                CalendarLinkResult {
                    id: "deleted".into(),
                    state: CalendarLinkState::Deleted { reason: None },
                },
                CalendarLinkResult {
                    id: "ambiguous".into(),
                    state: CalendarLinkState::Unavailable {
                        reason: Some("ambiguous".into()),
                    },
                },
            ],
        }
        .into();
        assert_eq!(result.calendar_ids, ["hidden-but-readable"]);
        assert_eq!(
            result
                .results
                .iter()
                .map(|r| r.id.as_str())
                .collect::<Vec<_>>(),
            ["found", "deleted", "ambiguous"]
        );
        match &result.results[0].state {
            core::LinkState::Found {
                calendar_id,
                external_id,
                ownership_url,
            } => {
                assert_eq!(calendar_id, "hidden-but-readable");
                assert_eq!(external_id, "actual-event");
                assert_eq!(
                    ownership_url.as_deref(),
                    Some("reha-calendar://event/found")
                );
            }
            _ => panic!("Found ownership evidence changed category"),
        }
        assert!(matches!(
            &result.results[1].state,
            core::LinkState::Deleted { reason: None }
        ));
        assert!(
            matches!(&result.results[2].state, core::LinkState::Unavailable { reason: Some(s) } if s == "ambiguous")
        );
    }
}
