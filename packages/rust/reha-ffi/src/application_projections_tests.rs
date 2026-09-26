use super::*;
use crate::{CalendarOperation, OperationKind};
use serde::{de::DeserializeOwned, Serialize};
use std::collections::BTreeMap;

// The removed conversion is an independent compatibility oracle for native
// fields, optionals and nested enum validation, not a production dependency.
fn legacy<T: Serialize, U: DeserializeOwned>(value: &T) -> U {
    serde_json::from_value(serde_json::to_value(value).unwrap()).unwrap()
}

macro_rules! assert_fields {
    ($actual:expr, $expected:expr, $($field:ident),+ $(,)?) => {
        $(assert_eq!($actual.$field, $expected.$field, stringify!($field));)+
    };
}

fn values() -> domain::EventValues {
    domain::EventValues {
        title: "Physiotherapie – üben".into(),
        start_utc: "2026-09-21T09:00:00Z".into(),
        end_utc: "2026-09-21T09:30:00Z".into(),
        timezone: "Europe/Vienna".into(),
        location: "Raum 4".into(),
        notes: "Zeile 1\nZeile 2".into(),
        reminder_minutes: Some(u32::MAX),
    }
}

fn operation(kind: &str, populated: bool) -> domain::CalendarOperation {
    domain::CalendarOperation {
        kind: kind.into(),
        id: format!("operation-{kind}"),
        calendar_id: "calendar-fixture".into(),
        external_id: populated.then(|| "external-fixture".into()),
        before: populated.then(values),
        after: populated.then(|| domain::EventValues {
            notes: "Geändert".into(),
            reminder_minutes: None,
            ..values()
        }),
        requires_resolution: populated,
        reason: "Prüfung erforderlich".into(),
    }
}

fn result(status: &str, populated: bool) -> domain::CalendarResult {
    domain::CalendarResult {
        id: format!("result-{status}"),
        status: status.into(),
        external_id: populated.then(|| "external-result".into()),
        error: populated.then(|| "Konfliktbeschreibung".into()),
        maintenance_warnings: vec!["Erinnerung ausstehend".into(), "Widget ausstehend".into()],
    }
}

fn proposal(populated: bool) -> service::Proposal {
    service::Proposal {
        token: "proposal-token".into(),
        document_id: "document-1".into(),
        document_ids: vec!["document-1".into(), "document-2".into()],
        run_hash: "private-run-hash".into(),
        schedule_id: "private-schedule".into(),
        fingerprint: "private-fingerprint".into(),
        operations: [
            "create",
            "update",
            "remove",
            "unchanged",
            "keep",
            "protected",
            "ambiguous",
            "conflict",
        ]
        .into_iter()
        .map(|kind| operation(kind, populated))
        .collect(),
        protected_event_ids: vec!["private-protected".into()],
        bindings: BTreeMap::from([
            ("appointment-b".into(), "event-b".into()),
            ("appointment-a".into(), "event-a".into()),
        ]),
        undo_of: Some("private-undo".into()),
        resume_batch: Some("private-resume".into()),
        overlaps: populated.then(|| {
            vec![domain::CalendarOverlap {
                appointment_id: "appointment-overlap".into(),
                external_id: "external-overlap".into(),
                title: "Besprechung".into(),
                start_utc: "2026-09-21T08:55:00Z".into(),
                end_utc: "2026-09-21T09:05:00Z".into(),
            }]
        }),
        comparison_events: BTreeMap::from([("private-comparison".into(), values())]),
        overlap_exclusions: vec!["private-excluded".into()],
        draft: None,
    }
}

fn assert_proposal(actual: &Proposal, expected: &Proposal) {
    assert_fields!(actual, expected, bindings, token, document_id, operations);
    assert_eq!(
        actual.overlaps.as_ref().map(Vec::len),
        expected.overlaps.as_ref().map(Vec::len)
    );
    for (actual, expected) in actual
        .overlaps
        .iter()
        .flatten()
        .zip(expected.overlaps.iter().flatten())
    {
        assert_fields!(
            actual,
            expected,
            appointment_id,
            external_id,
            title,
            start_utc,
            end_utc
        );
    }
}

fn assessment() -> readiness::DraftAssessment {
    readiness::DraftAssessment {
        revision: "revision-before-acceptance".into(),
        policy_version: u32::MAX,
        appointments: [
            readiness::Readiness::Ready,
            readiness::Readiness::Attention,
            readiness::Readiness::Excluded,
        ]
        .into_iter()
        .enumerate()
        .map(|(index, state)| readiness::AppointmentAssessment {
            id: format!("appointment-{index}"),
            document_id: format!("document-{index}"),
            state,
            issues: vec![domain::Issue::new(
                "issue",
                "Blockiert",
                Some("start"),
                true,
            )],
            warnings: vec![domain::Issue::new("warning", "Hinweis", None, false)],
        })
        .collect(),
        questions: vec![readiness::ReadinessQuestion {
            id: "question-1".into(),
            document_id: "document-1".into(),
            appointment_ids: vec!["appointment-2".into(), "appointment-1".into()],
            field: "date".into(),
            message: "Datum bestätigen".into(),
            polygon: vec![
                domain::Point { x: -0.0, y: 0.125 },
                domain::Point {
                    x: f64::MAX,
                    y: f64::MIN_POSITIVE,
                },
            ],
        }],
        ready_ids: vec!["appointment-0".into()],
        unprocessed_page_ids: vec!["page-z".into(), "page-a".into()],
    }
}

#[test]
fn history_summaries_preserve_native_fields_and_optionals() {
    for populated in [false, true] {
        let source = store::ScanSummary {
            id: "scan-fixture".into(),
            imported_at: i64::MIN,
            retained: populated,
            item_count: usize::MAX,
            pending_count: 0,
            dates: vec!["2026-09-22".into(), "2026-09-21".into()],
            schedule_id: populated.then(|| "schedule-fixture".into()),
        };
        let expected: ScanSummary = legacy(&source);
        let actual = ScanSummary::try_from(source).unwrap();
        assert_fields!(
            actual,
            expected,
            id,
            imported_at,
            retained,
            item_count,
            pending_count,
            dates,
            schedule_id
        );

        let source = store::Intake {
            id: "intake-fixture".into(),
            source_hash: "private-original-hash".into(),
            filename: "fixture.heic".into(),
            imported_at: i64::MAX,
            config: domain::PipelineConfig::default(),
            status: "awaiting_review".into(),
            error: populated.then(|| "Erkennungsfehler".into()),
        };
        let expected: IntakeSummary = legacy(&source);
        let actual = IntakeSummary::from(source);
        assert_fields!(actual, expected, id, filename, imported_at, status, error);

        let source = store::Plan {
            id: "plan-fixture".into(),
            imported_at: -4,
            page_ids: vec!["page-2".into(), "page-1".into(), "page-2".into()],
        };
        let expected: Plan = legacy(&source);
        let actual = Plan::from(source);
        assert_fields!(actual, expected, id, imported_at, page_ids);
    }
}

#[test]
fn batches_preserve_nested_operations_results_and_undo_identity() {
    for populated in [false, true] {
        let source = store::ImportBatch {
            id: "batch-fixture".into(),
            document_ids: vec!["page-z".into(), "page-a".into()],
            schedule_id: "schedule-fixture".into(),
            created_at: i64::MAX,
            undo_of: populated.then(|| "undo-fixture".into()),
            undone_by: populated.then(|| "undone-by-fixture".into()),
            operations: vec![store::BatchOperation {
                attempt_id: "attempt-fixture".into(),
                operation: operation("remove", populated),
                status: "pending-resolution".into(),
                result: populated.then(|| result("uncertain", true)),
            }],
        };
        let expected: ImportBatch = legacy(&source);
        let actual = ImportBatch::try_from(source).unwrap();
        assert_fields!(
            actual,
            expected,
            id,
            document_ids,
            schedule_id,
            created_at,
            undo_of,
            undone_by
        );
        assert_eq!(actual.operations.len(), expected.operations.len());
        for (actual, expected) in actual.operations.iter().zip(&expected.operations) {
            assert_fields!(actual, expected, attempt_id, operation, status, result);
        }
    }
}

#[test]
fn proposals_preserve_all_native_fields_and_every_operation_kind() {
    for populated in [false, true] {
        let source = proposal(populated);
        let expected: Proposal = legacy(&source);
        let actual = Proposal::try_from(source).unwrap();
        assert_proposal(&actual, &expected);
        assert_eq!(
            actual
                .operations
                .iter()
                .map(|op| op.kind.clone())
                .collect::<Vec<_>>(),
            vec![
                OperationKind::Create,
                OperationKind::Update,
                OperationKind::Remove,
                OperationKind::Unchanged,
                OperationKind::Keep,
                OperationKind::Protected,
                OperationKind::Ambiguous,
                OperationKind::Conflict
            ]
        );
    }
    let mut source = proposal(true);
    source.overlaps = Some(vec![]);
    let actual = Proposal::try_from(source).unwrap();
    assert!(actual.overlaps.unwrap().is_empty());
}

#[test]
fn draft_previews_preserve_readiness_geometry_and_optional_proposal() {
    for populated in [false, true] {
        let source = service::draft::DraftPreview {
            assessment: assessment(),
            proposal: populated.then(|| proposal(true)),
        };
        let expected: DraftPreview = legacy(&source);
        let actual = DraftPreview::try_from(source).unwrap();
        assert_eq!(actual.assessment, expected.assessment);
        assert_eq!(
            actual.assessment.questions[0].polygon[0].x.to_bits(),
            (-0.0_f64).to_bits()
        );
        assert_eq!(actual.proposal.is_some(), expected.proposal.is_some());
        if let (Some(actual), Some(expected)) = (&actual.proposal, &expected.proposal) {
            assert_proposal(actual, expected);
        }
    }
}

#[test]
fn save_outcomes_preserve_every_status_and_maintenance_warning() {
    for populated in [false, true] {
        let source = service::draft::SaveOutcome {
            batch_id: "batch-save".into(),
            results: ["saved", "failed", "uncertain", "conflict"]
                .into_iter()
                .map(|status| result(status, populated))
                .collect(),
            existing_ids: vec!["existing-2".into(), "existing-1".into()],
            remaining_ids: vec!["remaining-2".into(), "remaining-1".into()],
        };
        let expected: SaveOutcome = legacy(&source);
        let actual = SaveOutcome::try_from(source).unwrap();
        assert_fields!(
            actual,
            expected,
            batch_id,
            results,
            existing_ids,
            remaining_ids
        );
        assert_eq!(
            actual
                .results
                .iter()
                .map(|result| result.status.clone())
                .collect::<Vec<_>>(),
            vec![
                WriteStatus::Saved,
                WriteStatus::Failed,
                WriteStatus::Uncertain,
                WriteStatus::Conflict
            ]
        );
    }
}

#[test]
fn unknown_operation_and_result_states_fail_without_partial_success() {
    for invalid in ["", "SAVED", "saved ", "future-status"] {
        let source = result(invalid, true);
        assert!(
            serde_json::from_value::<CalendarResult>(serde_json::to_value(&source).unwrap())
                .is_err()
        );
        assert!(matches!(
            CalendarResult::try_from(source.clone()),
            Err(AppError::Storage { .. })
        ));
        assert!(matches!(
            BatchOperation::try_from(store::BatchOperation {
                attempt_id: "attempt".into(),
                operation: operation("create", true),
                status: "pending".into(),
                result: Some(source.clone()),
            }),
            Err(AppError::Storage { .. })
        ));
        assert!(matches!(
            SaveOutcome::try_from(service::draft::SaveOutcome {
                batch_id: "batch".into(),
                results: vec![result("saved", true), source],
                existing_ids: vec![],
                remaining_ids: vec![],
            }),
            Err(AppError::Storage { .. })
        ));
    }
    for invalid in ["", "CREATE", "create ", "future-operation"] {
        let mut source = proposal(true);
        source.operations.push(operation(invalid, true));
        assert!(
            serde_json::from_value::<Proposal>(serde_json::to_value(&source).unwrap()).is_err()
        );
        assert!(matches!(
            Proposal::try_from(source),
            Err(AppError::Storage { .. })
        ));
        assert!(matches!(
            CalendarOperation::try_from(operation(invalid, true)),
            Err(AppError::Storage { .. })
        ));
    }
}

#[test]
fn draft_projection_keeps_non_finite_geometry_a_storage_error() {
    for coordinate in [f64::NAN, f64::INFINITY, f64::NEG_INFINITY] {
        for x_axis in [false, true] {
            let mut source = assessment();
            if x_axis {
                source.questions[0].polygon[0].x = coordinate;
            } else {
                source.questions[0].polygon[0].y = coordinate;
            }
            assert!(serde_json::from_value::<DraftAssessment>(
                serde_json::to_value(&source).unwrap()
            )
            .is_err());
            assert!(matches!(
                DraftAssessment::try_from(source),
                Err(AppError::Storage { .. })
            ));
        }
    }
}
