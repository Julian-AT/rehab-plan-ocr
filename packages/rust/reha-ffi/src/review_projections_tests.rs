use super::*;
use serde::{de::DeserializeOwned, Serialize};
use std::collections::BTreeMap;

fn legacy<T: Serialize, U: DeserializeOwned>(value: &T) -> U {
    serde_json::from_value(serde_json::to_value(value).unwrap()).unwrap()
}

fn field() -> domain::FieldAssessment {
    domain::FieldAssessment {
        state: domain::PrintedState::Legible,
        polygon: vec![
            domain::Point { x: -0.0, y: 0.125 },
            domain::Point { x: 450.5, y: 90.25 },
        ],
        frame: "page".into(),
        reasons: vec!["Geprüft".into(), "Synthetisches Beispiel".into()],
        confirmed_value: Some(Value::String("Raum 9".into())),
        confirmed_at: Some(i64::MAX),
    }
}

fn appointment() -> domain::Appointment {
    domain::Appointment {
        id: "appointment-fixture".into(),
        fields: BTreeMap::from([
            ("location".into(), field()),
            (
                "title".into(),
                domain::FieldAssessment {
                    state: domain::PrintedState::Cropped,
                    confirmed_value: None,
                    confirmed_at: None,
                    ..field()
                },
            ),
        ]),
        row_polygon: vec![
            domain::Point { x: 2.5, y: 12.25 },
            domain::Point { x: 80.5, y: 16.125 },
        ],
        section_id: Some("section-fixture".into()),
        metadata: domain::Metadata {
            clinic: "Testklinik".into(),
            department: "Testabteilung".into(),
            address: "Synthetische Adresse".into(),
            contact: "Kontaktfixture".into(),
            treatment_code: "Codefixture".into(),
            preparation: "Vorbereitungfixture".into(),
            document_reference: "Dokumentfixture".into(),
            appointment_notes: "Terminnotizfixture".into(),
        },
        origins: BTreeMap::from([(
            "location".into(),
            domain::FieldOrigin {
                kind: "future-origin-kind".into(),
                evidence: vec!["evidence-z".into(), "evidence-a".into()],
                source: "Manuell eingegeben".into(),
            },
        )]),
        suggestions: vec![domain::CompletionSuggestion {
            id: "suggestion-fixture".into(),
            field: "location".into(),
            value: Value::String("Raum 10".into()),
            source: "Vorlage".into(),
            status: "future-status".into(),
        }],
        approval: Some(domain::ApprovalSnapshot {
            values_hash: "approval-fixture".into(),
            approved_at: i64::MIN,
        }),
        calendar_event_id: Some("calendar-event-fixture".into()),
        ics_event_id: Some("ics-event-fixture".into()),
        calendar_saved_hash: Some("calendar-saved-fixture".into()),
        ics_exported_hash: Some("ics-exported-fixture".into()),
        date: Some("2026-09-21".into()),
        start: Some("09:00".into()),
        end: Some("09:30".into()),
        end_date: Some("2026-09-21".into()),
        duration_minutes: Some(30),
        title: "Physiotherapie".into(),
        location: "Raum 9".into(),
        therapist: "Synthetische Person".into(),
        notes: "Zeile 1\nZeile 2".into(),
        included: false,
        provenance: BTreeMap::from([(
            "title".into(),
            vec!["observation-2".into(), "observation-1".into()],
        )]),
        issues: vec![
            domain::Issue::new("fixture-code", "Hinweis", None, false),
            domain::Issue::new("missing-value", "Zu prüfen", Some("location"), true),
        ],
    }
}

#[test]
fn scalar_projections_preserve_numeric_identity_and_future_unsigned_values() {
    for text in [
        "null",
        "true",
        "false",
        "\"Raum\"",
        "\"\"",
        "0",
        "-12",
        "30",
        "30.0",
        "-0.0",
        "0.25",
        "9223372036854775807",
        "9223372036854775808",
        "18446744073709551615",
    ] {
        let source: Value = serde_json::from_str(text).unwrap();
        let expected: FieldValue = legacy(&source);
        let actual = FieldValue::try_from(source).unwrap();
        assert_eq!(actual, expected, "{text}");
        let projected = Value::from(actual.clone());
        let expected: Value = legacy(&actual);
        assert_eq!(projected, expected, "{text}");
        assert_eq!(serde_json::to_string(&projected).unwrap(), text);
    }
    for native in [
        FieldValue::Unsigned { value: 30 },
        FieldValue::Unsigned { value: u64::MAX },
        FieldValue::Integer { value: i64::MIN },
        FieldValue::Number { value: f64::MAX },
        FieldValue::Number {
            value: f64::MIN_POSITIVE,
        },
    ] {
        assert_eq!(Value::from(native.clone()), legacy::<_, Value>(&native));
    }
}

#[test]
fn native_non_finite_scalars_keep_null_and_optional_none_semantics() {
    for number in [f64::NAN, f64::INFINITY, f64::NEG_INFINITY] {
        let value = FieldValue::Number { value: number };
        assert_eq!(Value::from(value.clone()), legacy::<_, Value>(&value));
        assert_eq!(Value::from(value.clone()), Value::Null);
        let mut native: Appointment = legacy(&appointment());
        native.fields.get_mut("location").unwrap().confirmed_value = Some(value.clone());
        native.suggestions[0].value = value;
        let expected: domain::Appointment = legacy(&native);
        let actual = domain::Appointment::try_from(native).unwrap();
        assert_eq!(actual, expected);
        assert_eq!(actual.fields["location"].confirmed_value, None);
        assert_eq!(actual.suggestions[0].value, Value::Null);
    }
}

#[test]
fn printed_states_and_field_geometry_survive_both_directions() {
    for state in [
        domain::PrintedState::Unreviewed,
        domain::PrintedState::Legible,
        domain::PrintedState::NotPrinted,
        domain::PrintedState::Illegible,
        domain::PrintedState::Cropped,
        domain::PrintedState::Contradictory,
    ] {
        let original = domain::FieldAssessment { state, ..field() };
        let expected: FieldAssessment = legacy(&original);
        let native = FieldAssessment::try_from(original.clone()).unwrap();
        assert_eq!(native, expected);
        assert_eq!(native.polygon[0].x.to_bits(), (-0.0_f64).to_bits());
        assert_eq!(domain::FieldAssessment::try_from(native).unwrap(), original);
    }
}

#[test]
fn appointments_keep_every_field_identity_approval_and_provenance() {
    for original in [
        appointment(),
        domain::Appointment::empty("empty-fixture".into()),
    ] {
        let expected: Appointment = legacy(&original);
        let native = Appointment::try_from(original.clone()).unwrap();
        assert_eq!(native, expected);
        let expected: domain::Appointment = legacy(&native);
        let roundtrip = domain::Appointment::try_from(native).unwrap();
        assert_eq!(roundtrip, expected);
        assert_eq!(roundtrip, original);
        assert_eq!(
            reha_core::review::values_hash(&roundtrip),
            reha_core::review::values_hash(&original)
        );
    }
}

#[test]
fn null_confirmations_fold_to_none_without_erasing_timestamps_or_empty_values() {
    for value in [
        None,
        Some(Value::Null),
        Some(Value::String(String::new())),
        Some(Value::Bool(false)),
        Some(Value::Number(0.into())),
    ] {
        let original = domain::FieldAssessment {
            confirmed_value: value,
            ..field()
        };
        let expected: FieldAssessment = legacy(&original);
        let native = FieldAssessment::try_from(original).unwrap();
        assert_eq!(native, expected);
        let expected: domain::FieldAssessment = legacy(&native);
        assert_eq!(domain::FieldAssessment::try_from(native).unwrap(), expected);
    }
    let mut native: FieldAssessment = legacy(&field());
    native.confirmed_value = Some(FieldValue::Empty);
    let expected: domain::FieldAssessment = legacy(&native);
    let actual = domain::FieldAssessment::try_from(native).unwrap();
    assert_eq!(actual, expected);
    assert_eq!(actual.confirmed_value, None);
    assert_eq!(actual.confirmed_at, Some(i64::MAX));
}

#[test]
fn structured_field_values_fail_at_every_native_review_boundary() {
    for invalid in [
        serde_json::json!([]),
        serde_json::json!(["not scalar"]),
        serde_json::json!({}),
        serde_json::json!({"value": "not scalar"}),
    ] {
        assert!(matches!(
            FieldValue::try_from(invalid.clone()),
            Err(AppError::Storage { .. })
        ));
        for suggestion in [false, true] {
            let mut source = appointment();
            if suggestion {
                source.suggestions[0].value = invalid.clone();
            } else {
                source.fields.get_mut("location").unwrap().confirmed_value = Some(invalid.clone());
            }
            assert!(
                serde_json::from_value::<Appointment>(serde_json::to_value(&source).unwrap())
                    .is_err()
            );
            assert!(matches!(
                Appointment::try_from(source),
                Err(AppError::Storage { .. })
            ));
        }
    }
}

#[test]
fn non_finite_geometry_fails_for_rows_fields_and_native_photo_corners() {
    for coordinate in [f64::NAN, f64::INFINITY, f64::NEG_INFINITY] {
        for x_axis in [false, true] {
            let point = domain::Point {
                x: if x_axis { coordinate } else { 0.0 },
                y: if x_axis { 0.0 } else { coordinate },
            };
            assert!(matches!(
                Point::try_from(point),
                Err(AppError::Storage { .. })
            ));
            assert!(matches!(
                domain::Point::try_from(Point {
                    x: point.x,
                    y: point.y
                }),
                Err(AppError::Storage { .. })
            ));
            for row in [false, true] {
                let mut source = appointment();
                let mut native: Appointment = legacy(&source);
                if row {
                    source.row_polygon[0] = point;
                    native.row_polygon[0] = Point {
                        x: point.x,
                        y: point.y,
                    };
                } else {
                    source.fields.get_mut("location").unwrap().polygon[0] = point;
                    native.fields.get_mut("location").unwrap().polygon[0] = Point {
                        x: point.x,
                        y: point.y,
                    };
                }
                assert!(serde_json::from_value::<Appointment>(
                    serde_json::to_value(&source).unwrap()
                )
                .is_err());
                assert!(serde_json::from_value::<domain::Appointment>(
                    serde_json::to_value(&native).unwrap()
                )
                .is_err());
                assert!(matches!(
                    Appointment::try_from(source),
                    Err(AppError::Storage { .. })
                ));
                assert!(matches!(
                    domain::Appointment::try_from(native),
                    Err(AppError::Storage { .. })
                ));
            }
        }
    }
}

#[test]
fn document_and_stage_preserve_all_fields_and_integer_limits() {
    let document = domain::Document {
        schema_version: domain::SCHEMA_VERSION,
        id: "document-fixture".into(),
        source_hash: "hash-fixture".into(),
        filename: "fixture.heic".into(),
        width: u32::MAX,
        height: 0,
        orientation: 270,
        imported_at: i64::MIN,
        source: "camera-fixture".into(),
    };
    let expected: Document = legacy(&document);
    assert_eq!(Document::from(document), expected);
    let stage = domain::Stage {
        name: "fixture-stage".into(),
        status: "future-stage-status".into(),
        duration_ms: u64::MAX,
        detail: "Synthetischer Prüfbericht".into(),
        artifacts: vec!["artifact-z".into(), "artifact-a".into()],
    };
    let expected: Stage = legacy(&stage);
    assert_eq!(Stage::from(stage), expected);
}

#[test]
fn exported_review_helpers_preserve_field_decisions_and_external_identities() {
    let new = crate::new_appointment(Some("2026-09-21".into())).unwrap();
    assert_eq!(new.date.as_deref(), Some("2026-09-21"));
    assert!(!new.id.is_empty());
    assert!(new.fields.is_empty());
    assert!(new.approval.is_none());

    let native: Appointment = legacy(&appointment());
    let confirmed = crate::confirm_appointment_fields(native.clone()).unwrap();
    assert_eq!(confirmed.calendar_event_id, native.calendar_event_id);
    assert_eq!(confirmed.calendar_saved_hash, native.calendar_saved_hash);
    assert_eq!(confirmed.ics_event_id, native.ics_event_id);
    assert_eq!(confirmed.ics_exported_hash, native.ics_exported_hash);
    for field in reha_core::review::FIELDS {
        assert!(confirmed.fields[*field].confirmed_at.is_some());
    }
    for accept in [false, true] {
        let revised =
            crate::accept_suggestion(native.clone(), "suggestion-fixture".into(), accept).unwrap();
        assert_eq!(revised.location, if accept { "Raum 10" } else { "Raum 9" });
        assert_eq!(
            revised.suggestions[0].status,
            if accept { "accepted" } else { "rejected" }
        );
        assert_eq!(revised.approval, native.approval);
        assert_eq!(revised.calendar_event_id, native.calendar_event_id);
        assert_eq!(revised.ics_event_id, native.ics_event_id);
        let domain: domain::Appointment = legacy(&revised);
        let assessment = reha_core::readiness::appointment(&domain, "", "Europe/Vienna");
        let expected: Vec<Issue> = legacy(
            &assessment
                .issues
                .into_iter()
                .chain(assessment.warnings)
                .collect::<Vec<_>>(),
        );
        assert_eq!(
            crate::appointment_issues(revised, "Europe/Vienna".into()).unwrap(),
            expected
        );
    }
    assert!(matches!(
        crate::accept_suggestion(native, "missing-fixture".into(), true),
        Err(AppError::Validation { .. })
    ));
}
