use reha_core::{
    contracts::*,
    readiness::{self, Readiness},
    service::{self, draft, Application, Platform},
    store::Store,
};
use serde_json::{json, Value};
use std::{
    collections::BTreeMap,
    sync::{Arc, Mutex},
};
struct Calendar {
    current: Mutex<BTreeMap<String, EventValues>>,
    writes: Mutex<usize>,
    uncertain: bool,
    state: Arc<Application>,
}
impl Platform for Calendar {
    fn progress(&self, _: Value) {}
    fn call(&self, command: &str, args: Value) -> service::Response<Value> {
        match command {
            "snapshot" => {
                let records: Vec<ImportRecord> =
                    serde_json::from_value(args["records"].clone()).unwrap();
                let current: BTreeMap<_, _> = self
                    .current
                    .lock()
                    .unwrap()
                    .iter()
                    .filter(|(id, _)| records.iter().any(|r| &r.id == *id))
                    .map(|(id, v)| (id.clone(), v.clone()))
                    .collect();
                Ok(json!({"current": current, "protected_ids": []}))
            }
            "agenda" => Ok(Value::Null),
            "apply" => {
                let op: CalendarOperation =
                    serde_json::from_value(args["operation"].clone()).unwrap();
                // User acceptance and all intents must already be durable before effects.
                let store = self.state.store.lock().unwrap();
                let count: i64 = store
                    .connection
                    .query_row("SELECT COUNT(*) FROM plan_acceptances", [], |r| r.get(0))
                    .unwrap();
                assert!(count > 0);
                assert!(!store.pending().unwrap().is_empty());
                drop(store);
                if self.uncertain || args["recovery_only"] == true {
                    return Err("interrupted".into());
                }
                *self.writes.lock().unwrap() += 1;
                if let Some(after) = op.after {
                    self.current.lock().unwrap().insert(op.id.clone(), after);
                } else {
                    self.current.lock().unwrap().remove(&op.id);
                }
                Ok(
                    json!({"id": op.id, "status": "saved", "external_id": format!("external-{}", op.id), "error": null}),
                )
            }
            _ => Err("unsupported".into()),
        }
    }
}
fn fixture(
    uncertain: bool,
) -> (
    tempfile::TempDir,
    Arc<Application>,
    Arc<Calendar>,
    PipelineRun,
) {
    let dir = tempfile::tempdir().unwrap();
    let mut run: PipelineRun =
        serde_json::from_str(include_str!("../../../public/sample-run.json")).unwrap();
    run.schema_version = SCHEMA_VERSION;
    run.document.schema_version = SCHEMA_VERSION;
    run.appointments = (0..3)
        .map(|i| {
            let mut a = Appointment::empty(uuid::Uuid::new_v4().to_string());
            a.title = format!("Therapie {i}");
            a.date = Some("2026-09-11".into());
            a.start = Some(format!("{:02}:00", 8 + i));
            a.end = Some(format!("{:02}:30", 8 + i));
            // Optional blank evidence stays unverified through acceptance.
            a.fields.insert(
                "location".into(),
                FieldAssessment {
                    state: PrintedState::Cropped,
                    reasons: vec!["Rand fehlt".into()],
                    ..Default::default()
                },
            );
            a.fields
                .insert("therapist".into(), FieldAssessment::default());
            a
        })
        .collect();
    run.review_confirmed = false;
    let store = Store::open(dir.path()).unwrap();
    store.save_run(&run).unwrap();
    let state = Arc::new(Application::new(store, "missing".into()));
    let calendar = Arc::new(Calendar {
        current: Mutex::new(BTreeMap::new()),
        writes: Mutex::new(0),
        uncertain,
        state: state.clone(),
    });
    (dir, state, calendar, run)
}
async fn preview(
    state: &Arc<Application>,
    calendar: Arc<Calendar>,
    id: &str,
) -> draft::DraftPreview {
    draft::preview(
        calendar,
        state,
        id.into(),
        "destination".into(),
        "Europe/Vienna".into(),
        None,
    )
    .await
    .unwrap()
}
#[tokio::test]
async fn one_action_accepts_a_clear_plan_without_fabricating_photo_verification() {
    let (_dir, state, calendar, run) = fixture(false);
    let p = preview(&state, calendar.clone(), &run.document.id).await;
    assert_eq!(p.assessment.ready_ids.len(), 3);
    assert!(p.assessment.questions.is_empty());
    {
        let store = state.store.lock().unwrap();
        assert!(store.batches().unwrap().is_empty());
        assert_eq!(
            serde_json::to_value(store.load_run(&run.document.id).unwrap()).unwrap(),
            serde_json::to_value(&run).unwrap()
        );
        assert_eq!(*calendar.writes.lock().unwrap(), 0);
    }
    let outcome = draft::accept_and_save(
        calendar.clone(),
        &state,
        p.proposal.unwrap().token,
        p.assessment.ready_ids,
        false,
    )
    .await
    .unwrap();
    assert_eq!(
        outcome
            .results
            .iter()
            .filter(|r| r.status == "saved")
            .count(),
        3
    );
    assert!(outcome.existing_ids.is_empty());
    let store = state.store.lock().unwrap();
    let saved = store.load_run(&run.document.id).unwrap();
    assert!(!saved.review_confirmed);
    for (old, new) in run.appointments.iter().zip(&saved.appointments) {
        assert!(new.approval.is_none());
        assert_eq!(old.fields, new.fields);
        assert_eq!(old.origins, new.origins);
        assert_eq!(
            new.calendar_saved_hash.as_ref(),
            Some(&reha_core::review::values_hash(new))
        );
    }
    let accepted: String = store
        .connection
        .query_row(
            "SELECT acceptance FROM plan_acceptances WHERE batch_id=?1",
            [&outcome.batch_id],
            |r| r.get(0),
        )
        .unwrap();
    let accepted: readiness::PlanAcceptance = serde_json::from_str(&accepted).unwrap();
    assert_eq!(accepted.policy_version, readiness::POLICY_VERSION);
    assert_eq!(accepted.value_hashes.len(), 3);
}
#[tokio::test]
async fn partial_save_retains_essential_uncertainties_and_cancellation() {
    let (_dir, state, calendar, mut run) = fixture(false);
    run.appointments[0].fields.insert(
        "date".into(),
        FieldAssessment {
            state: PrintedState::Illegible,
            ..Default::default()
        },
    );
    run.appointments[1].issues.push(Issue::new(
        "possible_cancellation",
        "Cancelled?",
        None,
        true,
    ));
    state.store.lock().unwrap().save_run(&run).unwrap();
    let p = preview(&state, calendar.clone(), &run.document.id).await;
    assert_eq!(p.assessment.ready_ids, vec![run.appointments[2].id.clone()]);
    assert_eq!(p.assessment.questions.len(), 2);
    let result = draft::accept_and_save(
        calendar,
        &state,
        p.proposal.unwrap().token,
        p.assessment.ready_ids,
        false,
    )
    .await
    .unwrap();
    assert_eq!(result.results.len(), 1);
    assert_eq!(result.remaining_ids.len(), 2);
    let saved = state
        .store
        .lock()
        .unwrap()
        .load_run(&run.document.id)
        .unwrap();
    assert!(saved.appointments[0].calendar_event_id.is_none());
    assert!(saved.appointments[1].calendar_event_id.is_none());
}
#[test]
fn essential_fields_and_inconsistent_duration_require_attention() {
    let (_dir, _state, _calendar, run) = fixture(false);
    for field in ["title", "date", "start", "end"] {
        let mut a = run.appointments[0].clone();
        a.fields.insert(
            field.into(),
            FieldAssessment {
                state: PrintedState::Cropped,
                ..Default::default()
            },
        );
        assert_eq!(
            readiness::appointment(&a, &run.document.id, "Europe/Vienna").state,
            Readiness::Attention,
            "{field}"
        );
    }
    let mut a = run.appointments[0].clone();
    a.duration_minutes = Some(20);
    assert_eq!(
        readiness::appointment(&a, &run.document.id, "Europe/Vienna").state,
        Readiness::Attention
    );
    a.duration_minutes = None;
    a.end = None;
    assert_eq!(
        readiness::appointment(&a, &run.document.id, "Europe/Vienna").state,
        Readiness::Attention
    );
}
#[test]
fn shared_date_questions_require_matching_heading_evidence_and_stale_answers_fail() {
    let (_dir, state, _calendar, mut run) = fixture(false);
    for a in &mut run.appointments {
        a.fields.insert(
            "date".into(),
            FieldAssessment {
                state: PrintedState::Illegible,
                ..Default::default()
            },
        );
        a.section_id = Some("same-label-is-not-proof".into());
    }
    assert_eq!(
        readiness::assess(&[run.clone()], "Europe/Vienna")
            .questions
            .len(),
        3
    );
    for a in &mut run.appointments[..2] {
        a.provenance
            .insert("date".into(), vec!["printed-header-region".into()]);
    }
    run.observations.push(Observation {
        id: "printed-header-region".into(),
        text: "11.09.2026".into(),
        region_ids: vec![],
        engine: "fixture".into(),
        score: Some(0.7),
        alternatives: vec![],
    });
    run.sections.push(ScheduleSection {
        id: "same-label-is-not-proof".into(),
        date: Some("2026-09-11".into()),
        polygon: vec![],
        heading_ids: vec!["printed-header-region".into()],
        observation_ids: vec![],
        columns: BTreeMap::new(),
        metadata: Metadata::default(),
    });
    state.store.lock().unwrap().save_run(&run).unwrap();
    let assessment = readiness::assess(&[run.clone()], "Europe/Vienna");
    assert_eq!(assessment.questions.len(), 2);
    let q = assessment
        .questions
        .iter()
        .find(|q| q.appointment_ids.len() == 2)
        .unwrap();
    draft::answer(
        &state,
        run.document.id.clone(),
        assessment.revision.clone(),
        q.id.clone(),
        Some(json!("2026-09-12")),
        "Europe/Vienna".into(),
    )
    .unwrap();
    let saved = state
        .store
        .lock()
        .unwrap()
        .load_run(&run.document.id)
        .unwrap();
    assert_eq!(saved.appointments[0].date.as_deref(), Some("2026-09-12"));
    assert_eq!(saved.appointments[1].date.as_deref(), Some("2026-09-12"));
    assert_eq!(saved.appointments[2].date, run.appointments[2].date);
    assert!(saved.appointments.iter().all(|a| a.approval.is_none()));
    assert!(draft::answer(
        &state,
        run.document.id,
        assessment.revision,
        q.id.clone(),
        None,
        "Europe/Vienna".into()
    )
    .is_err());
}
#[tokio::test]
async fn stale_edit_and_changed_calendar_abort_before_acceptance() {
    let (_dir, state, calendar, mut run) = fixture(false);
    let p = preview(&state, calendar.clone(), &run.document.id).await;
    run.appointments[0].title = "Edited".into();
    state.store.lock().unwrap().save_run(&run).unwrap();
    assert!(draft::accept_and_save(
        calendar.clone(),
        &state,
        p.proposal.unwrap().token,
        p.assessment.ready_ids,
        false
    )
    .await
    .is_err());
    assert!(state.store.lock().unwrap().batches().unwrap().is_empty());
    let p = preview(&state, calendar.clone(), &run.document.id).await;
    draft::accept_and_save(
        calendar.clone(),
        &state,
        p.proposal.unwrap().token,
        p.assessment.ready_ids,
        false,
    )
    .await
    .unwrap();
    let p = preview(&state, calendar.clone(), &run.document.id).await;
    calendar
        .current
        .lock()
        .unwrap()
        .values_mut()
        .next()
        .unwrap()
        .title = "External edit".into();
    assert!(draft::accept_and_save(
        calendar.clone(),
        &state,
        p.proposal.unwrap().token,
        p.assessment.ready_ids,
        false
    )
    .await
    .is_err());
    assert_eq!(state.store.lock().unwrap().batches().unwrap().len(), 1);
}
#[tokio::test]
async fn repeated_import_distinguishes_existing_and_undo_preserves_protections() {
    let (_dir, state, calendar, run) = fixture(false);
    let p = preview(&state, calendar.clone(), &run.document.id).await;
    let first = draft::accept_and_save(
        calendar.clone(),
        &state,
        p.proposal.unwrap().token,
        p.assessment.ready_ids,
        false,
    )
    .await
    .unwrap();
    let p = preview(&state, calendar.clone(), &run.document.id).await;
    let second = draft::accept_and_save(
        calendar.clone(),
        &state,
        p.proposal.unwrap().token,
        p.assessment.ready_ids,
        false,
    )
    .await
    .unwrap();
    assert!(second.results.is_empty());
    assert_eq!(second.existing_ids.len(), 3);
    assert_eq!(*calendar.writes.lock().unwrap(), 3);
    let undo = service::undo::prepare(calendar.clone(), &state, first.batch_id)
        .await
        .unwrap();
    assert!(service::calendar::approve_calendar(
        calendar.clone(),
        &state,
        undo.token.clone(),
        false
    )
    .await
    .is_err());
    service::calendar::approve_calendar(calendar.clone(), &state, undo.token, true)
        .await
        .unwrap();
    assert!(calendar.current.lock().unwrap().is_empty());
}
#[tokio::test]
async fn uncertain_write_is_never_reported_saved_and_survives_reopening() {
    let (dir, state, calendar, run) = fixture(true);
    let p = preview(&state, calendar.clone(), &run.document.id).await;
    let result = draft::accept_and_save(
        calendar.clone(),
        &state,
        p.proposal.unwrap().token,
        p.assessment.ready_ids,
        false,
    )
    .await
    .unwrap();
    assert!(result.results.iter().all(|r| r.status == "uncertain"));
    assert!(result.existing_ids.is_empty());
    assert!(state
        .store
        .lock()
        .unwrap()
        .load_run(&run.document.id)
        .unwrap()
        .appointments
        .iter()
        .all(|a| a.calendar_saved_hash.is_none()));
    drop(calendar);
    drop(state);
    let store = Store::open(dir.path()).unwrap();
    assert_eq!(store.pending().unwrap().len(), 3);
    assert_eq!(store.batches().unwrap()[0].id, result.batch_id);
}
#[tokio::test]
async fn failed_intent_transaction_rolls_back_acceptance_and_bindings() {
    let (_dir, state, calendar, run) = fixture(false);
    let p = preview(&state, calendar.clone(), &run.document.id).await;
    state.store.lock().unwrap().connection.execute_batch("CREATE TRIGGER fail_intent BEFORE INSERT ON operations BEGIN SELECT RAISE(ABORT, 'disk write failure'); END;").unwrap();
    assert!(draft::accept_and_save(
        calendar.clone(),
        &state,
        p.proposal.unwrap().token,
        p.assessment.ready_ids,
        false
    )
    .await
    .is_err());
    let store = state.store.lock().unwrap();
    assert!(store.batches().unwrap().is_empty());
    assert_eq!(
        store
            .connection
            .query_row("SELECT COUNT(*) FROM plan_acceptances", [], |r| r
                .get::<_, i64>(0))
            .unwrap(),
        0
    );
    assert!(store
        .load_run(&run.document.id)
        .unwrap()
        .appointments
        .iter()
        .all(|a| a.calendar_event_id.is_none()));
    assert_eq!(*calendar.writes.lock().unwrap(), 0);
}

#[test]
fn draft_export_preserves_ics_identities_without_calendar_or_field_approval() {
    let (_dir, state, _calendar, run) = fixture(false);
    let a = draft::assess(&state, run.document.id.clone(), "Europe/Vienna".into()).unwrap();
    let first = draft::export_ics(
        &state,
        run.document.id.clone(),
        a.revision,
        "Europe/Vienna".into(),
        None,
        a.ready_ids,
    )
    .unwrap();
    let a = draft::assess(&state, run.document.id.clone(), "Europe/Vienna".into()).unwrap();
    let second = draft::export_ics(
        &state,
        run.document.id.clone(),
        a.revision,
        "Europe/Vienna".into(),
        None,
        a.ready_ids,
    )
    .unwrap();
    assert_eq!(
        first
            .lines()
            .filter(|l| l.starts_with("UID:"))
            .collect::<Vec<_>>(),
        second
            .lines()
            .filter(|l| l.starts_with("UID:"))
            .collect::<Vec<_>>()
    );
    let store = state.store.lock().unwrap();
    assert!(store.records(None).unwrap().is_empty());
    let saved = store.load_run(&run.document.id).unwrap();
    for (old, new) in run.appointments.iter().zip(&saved.appointments) {
        assert_eq!(old.fields, new.fields);
        assert!(new.approval.is_none());
        assert!(new.calendar_saved_hash.is_none());
        assert!(new.ics_exported_hash.is_some());
    }
}
#[tokio::test]
async fn unresolved_calendar_conflict_can_be_left_for_later_without_accepting_it() {
    let (_dir, state, calendar, mut run) = fixture(false);
    let p = preview(&state, calendar.clone(), &run.document.id).await;
    draft::accept_and_save(
        calendar.clone(),
        &state,
        p.proposal.unwrap().token,
        p.assessment.ready_ids,
        false,
    )
    .await
    .unwrap();
    run = state
        .store
        .lock()
        .unwrap()
        .load_run(&run.document.id)
        .unwrap();
    let conflicted = run.appointments[0].id.clone();
    calendar
        .current
        .lock()
        .unwrap()
        .get_mut(&conflicted)
        .unwrap()
        .title = "Calendar changed".into();
    run.appointments[0].title = "Paper changed".into();
    run.appointments[1].title = "Another change".into();
    state.store.lock().unwrap().save_run(&run).unwrap();
    let p = preview(&state, calendar.clone(), &run.document.id).await;
    assert!(p
        .proposal
        .as_ref()
        .unwrap()
        .operations
        .iter()
        .any(|op| op.requires_resolution));
    let selected = p
        .assessment
        .ready_ids
        .into_iter()
        .filter(|id| id != &conflicted)
        .collect();
    let result = draft::accept_and_save(
        calendar.clone(),
        &state,
        p.proposal.unwrap().token,
        selected,
        false,
    )
    .await
    .unwrap();
    assert_eq!(result.remaining_ids, vec![conflicted.clone()]);
    assert_eq!(result.results.len(), 1);
    assert_eq!(result.existing_ids.len(), 1);
    assert_eq!(
        calendar.current.lock().unwrap()[&conflicted].title,
        "Calendar changed"
    );
}
#[tokio::test]
async fn multi_page_readiness_and_replacement_preserve_incomplete_plan_safeguard() {
    let (_dir, state, calendar, mut run) = fixture(false);
    let mut page = run.clone();
    page.document.id = uuid::Uuid::new_v4().to_string();
    for a in &mut page.appointments {
        a.id = uuid::Uuid::new_v4().to_string();
        a.date = Some("2026-09-12".into());
    }
    {
        let mut store = state.store.lock().unwrap();
        store.save_run(&page).unwrap();
        store
            .group_pages(
                &run.document.id,
                &[run.document.id.clone(), page.document.id.clone()],
            )
            .unwrap();
    }
    let p = preview(&state, calendar.clone(), &run.document.id).await;
    assert_eq!(p.assessment.ready_ids.len(), 6);
    assert!(draft::preview_replacement(
        calendar.clone(),
        &state,
        run.document.id.clone(),
        "destination".into(),
        "Europe/Vienna".into(),
        None
    )
    .await
    .is_err());
    run.complete_page_confirmed = true;
    page.complete_page_confirmed = true;
    {
        let store = state.store.lock().unwrap();
        store.save_run(&run).unwrap();
        store.save_run(&page).unwrap();
    }
    assert!(draft::preview_replacement(
        calendar.clone(),
        &state,
        run.document.id.clone(),
        "destination".into(),
        "Europe/Vienna".into(),
        None
    )
    .await
    .is_ok());
    {
        let store = state.store.lock().unwrap();
        store
            .connection
            .execute("UPDATE scans SET run=NULL WHERE id=?1", [&page.document.id])
            .unwrap();
    }
    let p = preview(&state, calendar.clone(), &run.document.id).await;
    assert_eq!(p.assessment.ready_ids.len(), 3);
    assert_eq!(p.assessment.unprocessed_page_ids, vec![page.document.id]);
    assert!(draft::preview_replacement(
        calendar,
        &state,
        run.document.id,
        "destination".into(),
        "Europe/Vienna".into(),
        None
    )
    .await
    .is_err());
}
#[test]
fn cancellation_decision_expires_after_value_edits() {
    let (_dir, state, _calendar, mut run) = fixture(false);
    run.appointments[0].issues.push(Issue::new(
        "possible_cancellation",
        "Cancelled?",
        None,
        true,
    ));
    state.store.lock().unwrap().save_run(&run).unwrap();
    let assessment =
        draft::assess(&state, run.document.id.clone(), "Europe/Vienna".into()).unwrap();
    draft::answer(
        &state,
        run.document.id.clone(),
        assessment.revision,
        assessment.questions[0].id.clone(),
        None,
        "Europe/Vienna".into(),
    )
    .unwrap();
    let mut saved = state
        .store
        .lock()
        .unwrap()
        .load_run(&run.document.id)
        .unwrap();
    assert_eq!(
        readiness::appointment(&saved.appointments[0], &run.document.id, "Europe/Vienna").state,
        Readiness::Ready
    );
    saved.appointments[0].date = Some("2026-09-12".into());
    assert_eq!(
        readiness::appointment(&saved.appointments[0], &run.document.id, "Europe/Vienna").state,
        Readiness::Attention
    );
}

#[tokio::test]
async fn final_partial_selection_cannot_turn_replacement_into_implicit_deletion() {
    let (_dir, state, calendar, run) = fixture(false);
    let p = preview(&state, calendar.clone(), &run.document.id).await;
    draft::accept_and_save(
        calendar.clone(),
        &state,
        p.proposal.unwrap().token,
        p.assessment.ready_ids,
        false,
    )
    .await
    .unwrap();
    let mut changed = state
        .store
        .lock()
        .unwrap()
        .load_run(&run.document.id)
        .unwrap();
    changed.appointments.pop();
    changed.complete_page_confirmed = true;
    state.store.lock().unwrap().save_run(&changed).unwrap();
    let p = draft::preview_replacement(
        calendar.clone(),
        &state,
        run.document.id.clone(),
        "destination".into(),
        "Europe/Vienna".into(),
        None,
    )
    .await
    .unwrap();
    assert!(p
        .proposal
        .as_ref()
        .unwrap()
        .operations
        .iter()
        .any(|op| op.kind == "remove"));
    let token = p.proposal.unwrap().token;
    assert!(draft::accept_and_save(
        calendar.clone(),
        &state,
        token.clone(),
        vec![p.assessment.ready_ids[0].clone()],
        true
    )
    .await
    .is_err());
    assert!(draft::accept_and_save(
        calendar.clone(),
        &state,
        token,
        p.assessment.ready_ids,
        false
    )
    .await
    .is_err());
    assert_eq!(calendar.current.lock().unwrap().len(), 3);
    assert_eq!(state.store.lock().unwrap().batches().unwrap().len(), 1);
}
#[test]
fn correcting_cropped_essential_value_does_not_claim_legible_photo_evidence() {
    let (_dir, state, _calendar, mut run) = fixture(false);
    run.appointments[0].date = None;
    run.appointments[0].fields.insert(
        "date".into(),
        FieldAssessment {
            state: PrintedState::Cropped,
            reasons: vec!["Überschrift fehlt".into()],
            ..Default::default()
        },
    );
    state.store.lock().unwrap().save_run(&run).unwrap();
    let a = draft::assess(&state, run.document.id.clone(), "Europe/Vienna".into()).unwrap();
    draft::answer(
        &state,
        run.document.id.clone(),
        a.revision,
        a.questions[0].id.clone(),
        Some(json!("2026-09-12")),
        "Europe/Vienna".into(),
    )
    .unwrap();
    let saved = state
        .store
        .lock()
        .unwrap()
        .load_run(&run.document.id)
        .unwrap();
    let date = &saved.appointments[0].fields["date"];
    assert_eq!(date.state, PrintedState::Cropped);
    assert!(date.confirmed_at.is_none());
    assert_eq!(saved.appointments[0].origins["date"].kind, "manual");
    assert_eq!(
        readiness::appointment(&saved.appointments[0], &run.document.id, "Europe/Vienna").state,
        Readiness::Ready
    );
}

#[tokio::test]
async fn row_exceptions_can_be_resolved_without_photo_verification_and_expire_on_evidence_changes()
{
    let (_dir, state, calendar, mut run) = fixture(false);
    let id = run.document.id.clone();
    run.appointments[0].issues.push(Issue::new(
        "recovered_row",
        "Existenz am Foto bestätigen.",
        None,
        true,
    ));
    run.appointments[0].issues.push(Issue::new(
        "retained_review",
        "Zuordnung prüfen.",
        None,
        true,
    ));
    state.store.lock().unwrap().save_run(&run).unwrap();
    let original_fields = run.appointments[0].fields.clone();
    for field in ["issue:recovered_row", "issue:retained_review"] {
        let assessment = draft::assess(&state, id.clone(), "Europe/Vienna".into()).unwrap();
        let question = assessment
            .questions
            .iter()
            .find(|q| q.field == field)
            .unwrap();
        draft::answer(
            &state,
            id.clone(),
            assessment.revision,
            question.id.clone(),
            None,
            "Europe/Vienna".into(),
        )
        .unwrap();
    }
    let prepared = preview(&state, calendar, &id).await;
    assert_eq!(prepared.assessment.ready_ids.len(), 3);
    let mut saved = state.store.lock().unwrap().load_run(&id).unwrap();
    for (field, original) in original_fields {
        assert_eq!(saved.appointments[0].fields[&field], original);
    }
    assert!(saved.appointments[0].approval.is_none());
    assert_eq!(
        saved.appointments[0].fields["issue:recovered_row"].state,
        PrintedState::default()
    );
    saved.appointments[0]
        .row_polygon
        .push(Point { x: 1., y: 2. });
    state.store.lock().unwrap().save_run(&saved).unwrap();
    let assessment = draft::assess(&state, id, "Europe/Vienna".into()).unwrap();
    assert_eq!(assessment.questions.len(), 2);
    assert_eq!(assessment.ready_ids.len(), 2);
}

#[tokio::test]
async fn plan_destination_survives_default_change_and_partial_import() {
    let (_root, state, calendar, mut run) = fixture(false);
    run.appointments[2].end = None;
    state.store.lock().unwrap().save_run(&run).unwrap();
    {
        let store = state.store.lock().unwrap();
        store
            .set_setting(
                "preferences",
                &json!({"timezone":"Europe/Vienna","calendar_id":"old-default"}).to_string(),
            )
            .unwrap();
        assert_eq!(
            store.plan_calendar(&run.document.id).unwrap(),
            ("old-default".into(), false)
        );
        store
            .select_plan_calendar(&run.document.id, "destination")
            .unwrap();
        store
            .set_setting(
                "preferences",
                &json!({"timezone":"Europe/Vienna","calendar_id":"new-default"}).to_string(),
            )
            .unwrap();
        assert_eq!(
            store.plan_calendar(&run.document.id).unwrap(),
            ("destination".into(), false)
        );
    }
    let p = preview(&state, calendar.clone(), &run.document.id).await;
    let result = draft::accept_and_save(
        calendar.clone(),
        &state,
        p.proposal.unwrap().token,
        p.assessment.ready_ids,
        false,
    )
    .await
    .unwrap();
    assert_eq!(result.remaining_ids.len(), 1);
    let store = state.store.lock().unwrap();
    assert_eq!(
        store.plan_calendar(&run.document.id).unwrap(),
        ("destination".into(), true)
    );
    assert!(store
        .select_plan_calendar(&run.document.id, "new-default")
        .is_err());
}

#[test]
fn older_preferences_preserve_new_calendar_choices() {
    let (_root, state, _, _) = fixture(false);
    service::settings::settings_value(&state,Some(json!({"timezone":"Europe/Vienna","calendar_id":"destination","display_calendar_ids":["read-only","other"],"recent_calendar_ids":["destination"]}))).unwrap();
    let result = service::settings::settings_value(
        &state,
        Some(json!({"timezone":"Europe/Vienna","calendar_id":"changed-by-tauri"})),
    )
    .unwrap();
    assert_eq!(
        result["display_calendar_ids"],
        json!(["read-only", "other"])
    );
    assert_eq!(result["recent_calendar_ids"], json!(["destination"]));
}
