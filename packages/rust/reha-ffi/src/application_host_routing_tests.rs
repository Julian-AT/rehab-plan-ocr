use super::errors::platform_failure;
use super::*;
use crate::{CalendarLinkResult, CalendarLinkState};
use reha_core::service::Platform;
type HostCalls = Arc<Mutex<Vec<(String, Value)>>>;
#[derive(Default)]
pub(super) struct Host {
    failure: Option<service::ServiceError>,
    calls: Option<HostCalls>,
    response: Option<Value>,
    recognition: Option<TextRecognitionResult>,
    overlap_response: Vec<CalendarOverlap>,
}
impl AppleHost for Host {
    fn recognize_text(&self, request: TextRecognitionRequest) -> Result<TextRecognitionResult> {
        if let Some(calls) = &self.calls {
            calls.lock().unwrap().push((
                "typedRecognition".into(),
                json!({
                    "image":request.image,"budget_ms":request.budget_ms
                }),
            ));
        }
        if let Some(error) = &self.failure {
            return Err(failure(error.clone()));
        }
        Ok(self
            .recognition
            .clone()
            .expect("Recognition fixture missing"))
    }
    fn calendar_status(&self) -> Result<CalendarPlatformStatus> {
        if let Some(error) = &self.failure {
            return Err(failure(error.clone()));
        }
        Ok(CalendarPlatformStatus {
            access: crate::CalendarAccessStatus::FullAccess,
            last_read_at: None,
            calendars: vec![],
            unavailable_calendar_ids: vec![],
        })
    }

    fn query_calendar(&self, _: CalendarReadQuery) -> Result<CalendarReadResult> {
        if let Some(error) = &self.failure {
            return Err(failure(error.clone()));
        }
        Ok(CalendarReadResult {
            events: vec![],
            unavailable_calendar_ids: vec![],
            unavailable_events: vec![],
        })
    }
    fn resolve_calendar_event(
        &self,
        _: CalendarReadReference,
    ) -> Result<Option<CalendarReadEvent>> {
        if let Some(error) = &self.failure {
            return Err(failure(error.clone()));
        }
        Ok(None)
    }
    fn event_calendars(&self) -> Result<Vec<EventCalendarDestination>> {
        if let Some(error) = &self.failure {
            return Err(failure(error.clone()));
        }
        Ok(vec![])
    }
    fn mutate_event(&self, _: EventMutationRequest) -> Result<EventMutationResult> {
        if let Some(error) = &self.failure {
            return Err(failure(error.clone()));
        }
        Ok(service::calendar_mutations::MutationResult::uncertain().into())
    }
    fn calendar_event_call(&self, command: String, arguments: String) -> Result<String> {
        if let Some(calls) = &self.calls {
            calls
                .lock()
                .unwrap()
                .push((command.clone(), serde_json::from_str(&arguments).unwrap()));
        }
        if let Some(error) = &self.failure {
            return Err(failure(error.clone()));
        }
        Ok(self.response.clone().unwrap_or_else(|| json!({"received_command": command, "arguments": serde_json::from_str::<Value>(&arguments).unwrap()})).to_string())
    }
    fn resolve_owned_event(&self, record: AgendaOwnedRecord) -> Result<OwnedEventResolution> {
        if let Some(error) = &self.failure {
            return Err(failure(error.clone()));
        }
        if let Some(calls) = &self.calls {
            calls
                .lock()
                .unwrap()
                .push(("typedOwnedEvent".into(), json!(record)));
        }
        Ok(OwnedEventResolution::Unavailable)
    }
    fn inspect_calendar_links(
        &self,
        records: Vec<AgendaOwnedRecord>,
    ) -> Result<CalendarLinkInspection> {
        if let Some(error) = &self.failure {
            return Err(failure(error.clone()));
        }
        if let Some(calls) = &self.calls {
            calls
                .lock()
                .unwrap()
                .push(("typedCalendarLinks".into(), json!(records)));
        }
        Ok(CalendarLinkInspection {
            calendar_ids: vec!["visible".into()],
            results: records
                .into_iter()
                .map(|r| CalendarLinkResult {
                    id: r.id,
                    state: CalendarLinkState::Unavailable { reason: None },
                })
                .collect(),
        })
    }
    fn snapshot(&self, records: Vec<ImportRecord>) -> Result<LiveCalendar> {
        if let Some(error) = &self.failure {
            return Err(failure(error.clone()));
        }
        if let Some(calls) = &self.calls {
            calls
                .lock()
                .unwrap()
                .push(("typedSnapshot".into(), json!(records)));
        }
        Ok(LiveCalendar {
            current: records.into_iter().map(|r| (r.id, r.approved)).collect(),
            protected_ids: vec!["protected-series".into()],
        })
    }
    fn apply(&self, operation: CalendarOperation, recovery_only: bool) -> Result<CalendarResult> {
        if let Some(error) = &self.failure {
            return Err(failure(error.clone()));
        }
        if let Some(calls) = &self.calls {
            calls.lock().unwrap().push((
                "typedApply".into(),
                json!({"operation":operation,"recovery_only":recovery_only}),
            ));
        }
        Ok(CalendarResult {
            id: operation.id,
            status: if recovery_only {
                WriteStatus::Uncertain
            } else {
                WriteStatus::Saved
            },
            external_id: operation.external_id,
            error: recovery_only.then(|| "Unclear durable status".into()),
            maintenance_warnings: vec!["Separate maintenance warning".into()],
        })
    }
    fn decode_photo(&self, bytes: Vec<u8>) -> Result<Vec<u8>> {
        Ok(bytes.into_iter().rev().collect())
    }
    fn sync_agenda(&self, request: AgendaSyncRequest) -> Result<AgendaSyncResult> {
        if let Some(calls) = &self.calls {
            calls
                .lock()
                .unwrap()
                .push(("typedAgenda".into(), json!(request)));
        }
        if let Some(error) = &self.failure {
            return Err(failure(error.clone()));
        }
        Ok(AgendaSyncResult {
            maintenance_warnings: service::agenda::maintenance_warnings(
                self.response.as_ref().unwrap_or(&Value::Null),
            ),
        })
    }
    fn forget_calendar(&self) -> Result<()> {
        if let Some(calls) = &self.calls {
            calls
                .lock()
                .unwrap()
                .push(("typedForgetCalendar".into(), Value::Null));
        }
        if let Some(error) = &self.failure {
            return Err(failure(error.clone()));
        }
        Ok(())
    }
    fn overlaps(
        &self,
        events: HashMap<String, EventValues>,
        exclude: Vec<String>,
    ) -> Result<Vec<CalendarOverlap>> {
        if let Some(calls) = &self.calls {
            calls.lock().unwrap().push((
                "typedOverlaps".into(),
                json!({"events":events,"exclude":exclude}),
            ));
        }
        if let Some(error) = &self.failure {
            return Err(failure(error.clone()));
        }
        Ok(self.overlap_response.clone())
    }
}
#[test]
fn typed_forget_calendar_bypasses_and_rejects_the_string_effect() {
    let calls = Arc::new(Mutex::new(vec![]));
    let bridge = HostBridge {
        host: Box::new(Host {
            calls: Some(calls.clone()),
            ..Host::default()
        }),
        progress: Mutex::new(HashMap::new()),
        jobs: Arc::new(RecognitionJobs::default()),
    };
    bridge.forget_calendar().unwrap();
    assert!(matches!(
        bridge.call("forgetCalendar", json!({})),
        Err(service::ServiceError::Validation(_))
    ));
    assert_eq!(
        *calls.lock().unwrap(),
        [("typedForgetCalendar".into(), Value::Null)]
    );
}
#[test]
fn typed_overlap_effect_preserves_values_exclusions_and_response_order() {
    let calls = Arc::new(Mutex::new(vec![]));
    let bridge = HostBridge {
        host: Box::new(Host {
            calls: Some(calls.clone()),
            overlap_response: vec![
                CalendarOverlap {
                    appointment_id: "later".into(),
                    external_id: "native-later".into(),
                    title: "Spätere Überschneidung".into(),
                    start_utc: "2031-05-17T09:00:00Z".into(),
                    end_utc: "2031-05-17T09:30:00Z".into(),
                },
                CalendarOverlap {
                    appointment_id: "earlier".into(),
                    external_id: "native-earlier".into(),
                    title: "Frühere Überschneidung".into(),
                    start_utc: "2031-05-17T08:00:00Z".into(),
                    end_utc: "2031-05-17T08:30:00Z".into(),
                },
            ],
            ..Host::default()
        }),
        progress: Mutex::new(HashMap::new()),
        jobs: Arc::new(RecognitionJobs::default()),
    };
    let values = domain::EventValues {
        title: "Erfundene Therapie".into(),
        start_utc: "2031-05-17T08:00:00Z".into(),
        end_utc: "2031-05-17T08:30:00Z".into(),
        timezone: "Europe/Vienna".into(),
        location: "Raum 204".into(),
        notes: "Bestätigte Notiz\nmit zweiter Zeile".into(),
        reminder_minutes: Some(u32::MAX),
    };
    let events = std::collections::BTreeMap::from([
        ("with-reminder".into(), values.clone()),
        (
            "without-reminder".into(),
            domain::EventValues {
                reminder_minutes: None,
                ..values
            },
        ),
    ]);
    let exclusions = vec!["second".into(), "first".into(), "second".into()];
    let result = bridge.overlaps(events.clone(), exclusions.clone()).unwrap();
    assert_eq!(
        result,
        Some(vec![
            domain::CalendarOverlap {
                appointment_id: "later".into(),
                external_id: "native-later".into(),
                title: "Spätere Überschneidung".into(),
                start_utc: "2031-05-17T09:00:00Z".into(),
                end_utc: "2031-05-17T09:30:00Z".into(),
            },
            domain::CalendarOverlap {
                appointment_id: "earlier".into(),
                external_id: "native-earlier".into(),
                title: "Frühere Überschneidung".into(),
                start_utc: "2031-05-17T08:00:00Z".into(),
                end_utc: "2031-05-17T08:30:00Z".into(),
            },
        ])
    );
    assert_eq!(
        calls.lock().unwrap().as_slice(),
        [(
            "typedOverlaps".into(),
            json!({"events":events,"exclude":exclusions}),
        )]
    );
    let empty = HostBridge {
        host: Box::new(Host::default()),
        progress: Mutex::new(HashMap::new()),
        jobs: Arc::new(RecognitionJobs::default()),
    };
    assert_eq!(
        empty.overlaps(Default::default(), vec![]).unwrap(),
        Some(vec![])
    );
}
#[test]
fn typed_import_effects_preserve_identity_recovery_and_maintenance_warnings() {
    let calls = Arc::new(Mutex::new(vec![]));
    let bridge = HostBridge {
        host: Box::new(Host {
            calls: Some(calls.clone()),
            ..Host::default()
        }),
        progress: Mutex::new(HashMap::new()),
        jobs: Arc::new(RecognitionJobs::default()),
    };
    let values = domain::EventValues {
        title: "Erfundene Therapie".into(),
        start_utc: "2031-05-17T08:00:00Z".into(),
        end_utc: "2031-05-17T08:30:00Z".into(),
        timezone: "Europe/Vienna".into(),
        location: "Raum 204".into(),
        notes: "Bestätigte Notiz".into(),
        reminder_minutes: None,
    };
    let record = domain::ImportRecord {
        id: "owned".into(),
        schedule_id: "schedule".into(),
        calendar_id: "hidden".into(),
        external_id: Some("native-event".into()),
        approved: values.clone(),
        status: "saved".into(),
        operation_id: "durable-attempt".into(),
    };
    let snapshot = bridge.import_snapshot(vec![record.clone()]).unwrap();
    assert_eq!(snapshot.current["owned"], values);
    assert_eq!(snapshot.protected_ids, ["protected-series"]);
    let mut operation = domain::CalendarOperation {
        kind: "update".into(),
        id: record.id,
        calendar_id: record.calendar_id,
        external_id: record.external_id,
        before: Some(values.clone()),
        after: Some(values),
        requires_resolution: true,
        reason: "Fremde Änderung prüfen".into(),
    };
    for recovery_only in [false, true] {
        let result = bridge
            .apply_import(service::calendar_imports::ApplyRequest {
                operation: operation.clone(),
                recovery_only,
            })
            .unwrap();
        assert_eq!(result.id, "owned");
        assert_eq!(result.external_id.as_deref(), Some("native-event"));
        assert_eq!(
            result.status,
            if recovery_only { "uncertain" } else { "saved" }
        );
        assert_eq!(result.error.is_some(), recovery_only);
        assert_eq!(
            result.maintenance_warnings,
            ["Separate maintenance warning"]
        );
    }
    let observed = calls.lock().unwrap().clone();
    assert_eq!(observed.len(), 3);
    assert_eq!(observed[0].0, "typedSnapshot");
    assert_eq!(observed[0].1[0]["operation_id"], "durable-attempt");
    for (index, recovery_only) in [(1, false), (2, true)] {
        assert_eq!(observed[index].0, "typedApply");
        assert_eq!(
            observed[index].1,
            json!({"operation":operation,"recovery_only":recovery_only})
        );
    }
    for command in ["snapshot", "apply"] {
        assert!(bridge.call(command, json!({})).is_err());
    }
    operation.kind = "unsupported-kind".into();
    assert!(matches!(
        bridge.apply_import(service::calendar_imports::ApplyRequest {
            operation,
            recovery_only: false,
        }),
        Err(service::ServiceError::Storage(_))
    ));
    assert_eq!(
        calls.lock().unwrap().len(),
        3,
        "Invalid operation reached the host"
    );
}
#[test]
fn typed_recognition_keeps_binary_input_and_complete_evidence_without_legacy_calls() {
    let calls = Arc::new(Mutex::new(vec![]));
    let regions = vec![Region {
        id: "r1".into(),
        polygon: vec![Point { x: 1.25, y: 7.5 }],
        frame: "page".into(),
        kind: "text".into(),
        parent: Some("page".into()),
        children: vec!["r2".into()],
    }];
    let observations = vec![OcrObservation {
        id: "o1".into(),
        text: "Raum 204".into(),
        region_ids: vec!["r1".into()],
        engine: "Apple Vision".into(),
        score: Some(0.75),
        alternatives: vec!["Raum 2O4".into()],
    }];
    let bridge = HostBridge {
        host: Box::new(Host {
            calls: Some(calls.clone()),
            recognition: Some(TextRecognitionResult {
                regions: regions.clone(),
                observations: observations.clone(),
                duration_ms: 123,
                identity: crate::TextRecognitionIdentity {
                    engine: "Apple Vision".into(),
                    revision: 3,
                    system_version: "fixture".into(),
                    language_correction: false,
                },
            }),
            ..Host::default()
        }),
        progress: Mutex::new(HashMap::new()),
        jobs: Arc::new(RecognitionJobs::default()),
    };
    let input = service::text_recognition::Request {
        image: vec![0, 255, 128, 1],
        budget_ms: 1234,
    };
    let output = bridge.recognize_text(input.clone()).unwrap();
    assert_eq!(
        serde_json::to_value(output.regions).unwrap(),
        json!(regions)
    );
    assert_eq!(
        serde_json::to_value(output.observations).unwrap(),
        json!(observations)
    );
    assert_eq!(output.duration_ms, 123);
    assert_eq!(
        output.manifest,
        json!({"engine":"Apple Vision","revision":3,
        "system_version":"fixture","language_correction":false})
    );
    assert_eq!(
        calls.lock().unwrap().as_slice(),
        [(
            "typedRecognition".into(),
            json!({"image":[0,255,128,1],"budget_ms":1234})
        )]
    );
    for request in [
        service::text_recognition::Request {
            image: vec![],
            ..input.clone()
        },
        service::text_recognition::Request {
            budget_ms: 0,
            ..input.clone()
        },
        service::text_recognition::Request {
            budget_ms: 60_001,
            ..input
        },
    ] {
        assert!(bridge.recognize_text(request).is_err());
    }
    assert!(bridge.call("recognize", json!({})).is_err());
    assert_eq!(
        calls.lock().unwrap().len(),
        1,
        "Invalid/legacy input reached native host"
    );
}
#[test]
fn current_event_effect_reaches_the_legacy_callback() {
    let bridge = HostBridge {
        host: Box::new(Host::default()),
        progress: Mutex::new(HashMap::new()),
        jobs: Arc::new(RecognitionJobs::default()),
    };
    let args = json!({"external_id":"synthetic-event"});
    let result = bridge.call("editSystemEvent", args.clone()).unwrap();
    assert_eq!(result["received_command"], "editSystemEvent");
    assert_eq!(result["arguments"], args);
    for command in [
        "unregistered-effect",
        "recognize",
        "resolveOwnedEvent",
        "queryEvents",
        "getEvent",
        "eventCalendars",
        "mutateEvent",
        "calendarStatus",
    ] {
        assert!(bridge.call(command, json!({})).is_err());
    }
}
#[test]
fn domain_failure_identity_is_independent_of_its_preserved_diagnostic() {
    use service::{DomainFailure as D, ServiceError as E};
    for (kind, expected) in [
        (D::ExpiredScan, E::ExpiredScan),
        (D::StaleRevision, E::StaleRevision),
        (D::StaleProposal, E::StaleProposal),
        (D::Busy, E::Busy),
        (D::UncertainWrite, E::UncertainWrite),
    ] {
        for message in ["Unveränderter Journaltext", "Kalenderzugriff fehlt."] {
            let error = kind.with_message(message);
            assert_eq!(serde_json::to_value(&error).unwrap(), json!(message));
            assert_eq!(error.to_string(), message);
            // The unchanged AppError variant preserves the app's localized
            // presentation; original domain text stays in its journal projection.
            assert_eq!(platform_failure(failure(error)), expected);
        }
    }
}

#[test]
fn misleading_diagnostics_never_change_validation_or_storage_identity() {
    use service::ServiceError as E;
    for message in [
        "Kalenderzugriff fehlt.",
        "stale_revision",
        "Vorschau abgelaufen.",
        "Prüfdaten wurden geändert.",
        "Scan wurde gelöscht oder ist noch nicht erkannt.",
        "Eine Verarbeitung läuft bereits.",
        "Unklare Schreibvorgänge zuerst abgleichen.",
    ] {
        for error in [E::Legacy(message.into()), E::Validation(message.into())] {
            assert_eq!(
                platform_failure(failure(error)),
                E::Validation(message.into())
            );
        }
        assert_eq!(
            platform_failure(failure(E::Storage(message.into()))),
            E::Storage(message.into())
        );
    }
    // Deliberately storage-mapped APIs retain their existing boundary policy.
    assert!(matches!(
        storage(reha_core::Error::MissingRun),
        AppError::Storage { message }
            if message == "Scan wurde gelöscht oder ist noch nicht erkannt."
    ));
    assert!(matches!(
        storage(reha_core::Error::UnresolvedCalendarWrites("Originaltext".into())),
        AppError::Storage { message } if message == "Originaltext"
    ));
}

#[test]
fn every_native_failure_preserves_identity_through_service_dispatch() {
    use service::ServiceError as E;
    for expected in [
        E::Validation("Kalenderzugriff fehlt.".into()),
        E::Storage("Vorschau abgelaufen; läuft bereits".into()),
        E::PermissionDenied,
        E::Timeout("queryEvents".into()),
        E::UncertainWrite,
        E::ExpiredScan,
        E::StaleRevision,
        E::StaleProposal,
        E::Busy,
        E::Cancelled,
    ] {
        let bridge = HostBridge {
            host: Box::new(Host {
                failure: Some(expected.clone()),
                ..Host::default()
            }),
            progress: Mutex::new(HashMap::new()),
            jobs: Arc::new(RecognitionJobs::default()),
        };
        let actual = bridge
            .query_calendar(service::calendar_reads::Query {
                calendar_ids: vec![],
                start_utc: "2026-09-18T00:00:00Z".into(),
                end_utc: "2026-09-19T00:00:00Z".into(),
                timezone: "Europe/Vienna".into(),
                selection_revision: 2,
                records: vec![],
            })
            .unwrap_err();
        assert_eq!(actual, expected);
        assert_eq!(
            bridge
                .resolve_calendar_event(service::calendar_reads::Reference {
                    calendar_id: "selected".into(),
                    external_id: "native".into(),
                    occurrence: "2026-09-18T08:00:00Z".into(),
                    expected_start_utc: "2026-09-18T08:00:00Z".into(),
                })
                .unwrap_err(),
            expected
        );
        assert_eq!(bridge.event_calendars().unwrap_err(), expected);
        assert_eq!(bridge.calendar_status().unwrap_err(), expected);
        assert_eq!(bridge.forget_calendar().unwrap_err(), expected);
        assert_eq!(
            bridge.overlaps(Default::default(), vec![]).unwrap_err(),
            expected
        );
        assert_eq!(
            bridge
                .recognize_text(service::text_recognition::Request {
                    image: vec![1],
                    budget_ms: 1234,
                })
                .unwrap_err(),
            expected
        );
        assert_eq!(platform_failure(failure(actual.clone())), expected);
        // Journal/maintenance projections keep their original string schema.
        assert_eq!(
            serde_json::to_value(actual).unwrap(),
            json!(expected.to_string())
        );
    }
}
#[test]
fn native_photo_uses_binary_callback_without_json_effect() {
    let bridge = HostBridge {
        // Any JSON effect would fail; only the binary photo callback succeeds.
        host: Box::new(Host {
            failure: Some(service::ServiceError::Cancelled),
            ..Host::default()
        }),
        progress: Mutex::new(HashMap::new()),
        jobs: Arc::new(RecognitionJobs::default()),
    };
    let bytes = [0, 255, 128, b'{', b'"', 0];
    assert_eq!(
        bridge.decode_photo(&bytes).unwrap(),
        bytes.into_iter().rev().collect::<Vec<_>>()
    );
}
#[tokio::test]
async fn saved_preferences_keep_widget_scope_and_separate_maintenance_failures() {
    for (failure, response, warned) in [
        (None, json!({}), false),
        (
            Some(service::ServiceError::PermissionDenied),
            json!({}),
            true,
        ),
        (
            None,
            json!({"reminders":{"error":"Synthetic notification failure"}}),
            true,
        ),
    ] {
        let directory = tempfile::tempdir().unwrap();
        let calls = Arc::new(Mutex::new(vec![]));
        let app = open_application(
            directory.path().to_str().unwrap().into(),
            "missing".into(),
            Box::new(Host {
                failure,
                calls: Some(calls.clone()),
                response: Some(response),
                recognition: None,
                ..Host::default()
            }),
        )
        .await
        .unwrap();
        for selected in [vec!["selected-calendar".to_string()], vec![]] {
            let mut preferences = app.preferences().await.unwrap();
            preferences.display_calendar_ids = selected.clone();
            preferences.appearance = "dark".into();
            let saved = app
                .save_preferences_detailed(preferences.clone())
                .await
                .unwrap();
            assert_eq!(
                serde_json::to_value(&saved.preferences).unwrap(),
                serde_json::to_value(&preferences).unwrap()
            );
            assert_eq!(!saved.maintenance_warnings.is_empty(), warned);
            assert_eq!(
                serde_json::to_value(app.preferences().await.unwrap()).unwrap(),
                serde_json::to_value(preferences).unwrap()
            );
            let call = calls.lock().unwrap().last().unwrap().clone();
            assert_eq!(call.0, "typedAgenda");
            assert_eq!(call.1["display_calendar_ids"], json!(selected));
        }
        assert_eq!(
            calls.lock().unwrap().len(),
            2,
            "Maintenance failure must not repeat a save"
        );
        let mut invalid = app.preferences().await.unwrap();
        invalid.timezone = "invalid-timezone".into();
        assert!(app.save_preferences_detailed(invalid).await.is_err());
        assert_eq!(
            calls.lock().unwrap().len(),
            2,
            "Rejected preferences must not change native caches"
        );
        assert_eq!(app.preferences().await.unwrap().timezone, "Europe/Vienna");
    }
}
