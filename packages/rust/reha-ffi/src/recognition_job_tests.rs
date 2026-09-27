use super::{host_routing_tests::Host, *};
use reha_core::service::Platform;
use std::sync::atomic::{AtomicBool, Ordering};

async fn application() -> (tempfile::TempDir, Arc<NativeApplication>) {
    let dir = tempfile::tempdir().unwrap();
    let app = open_application(
        dir.path().to_string_lossy().into(),
        "missing".into(),
        Box::new(Host::default()),
    )
    .await
    .unwrap();
    (dir, app)
}
fn request(id: &str, path: &std::path::Path) -> PhotoRequest {
    PhotoRequest {
        id: id.into(),
        path: path.to_string_lossy().into(),
        timezone: "Europe/Vienna".into(),
        quarter_turns: 0,
        mirrored: false,
        page_corners: vec![],
        force: false,
    }
}
async fn drained(app: &NativeApplication) {
    tokio::time::timeout(std::time::Duration::from_secs(2), async {
        while app.bridge.jobs.len() != 0 {
            tokio::task::yield_now().await;
        }
    })
    .await
    .expect("recognition lease not released");
}
#[tokio::test]
async fn early_photo_errors_and_prestart_cancel_release_every_registration() {
    let (dir, app) = application().await;
    let id = uuid::Uuid::new_v4().to_string();
    let absent = dir.path().join("absent");
    let first = app.register_job(id.clone()).unwrap();
    app.cancel_job(first.attempt_id()).unwrap();
    assert!(matches!(
        app.import_photo(request(&id, &absent), first.clone()).await,
        Err(AppError::Cancelled)
    ));
    assert_eq!(app.bridge.jobs.len(), 0);
    assert!(!app.recognition_busy());
    assert!(matches!(
        app.job_progress(id.clone()).unwrap().state,
        JobState::Cancelled
    ));

    for trace in [false, true] {
        let retry = app.register_job(id.clone()).unwrap();
        assert_ne!(first.attempt_id(), retry.attempt_id());
        app.cancel_job(first.attempt_id()).unwrap();
        app.cancel_job(uuid::Uuid::new_v4().to_string()).unwrap();
        first.cancel();
        first.close();
        let result = if trace {
            app.import_trace_photo(request(&id, &absent), retry.clone())
                .await
        } else {
            app.import_photo(request(&id, &absent), retry.clone()).await
        };
        assert!(matches!(result, Err(AppError::Storage { .. })));
        assert_eq!(app.bridge.jobs.len(), 0);
        assert!(!app.recognition_busy());
        assert!(matches!(
            app.job_progress(id.clone()).unwrap().state,
            JobState::Failed
        ));
    }
    // Metadata succeeds for a directory; reading its bytes is a separate early error.
    let read_error = app.register_job(id.clone()).unwrap();
    assert!(matches!(
        app.import_photo(request(&id, dir.path()), read_error).await,
        Err(AppError::Storage { .. })
    ));
    assert_eq!(app.bridge.jobs.len(), 0);
    let invalid = dir.path().join("not-a-photo");
    std::fs::write(&invalid, b"synthetic").unwrap();
    let job = app.register_job(id.clone()).unwrap();
    let mut photo = request(&id, &invalid);
    photo.page_corners.push(Point { x: 0.0, y: 0.0 });
    assert!(matches!(
        app.import_photo(photo, job).await,
        Err(AppError::Validation { .. })
    ));
    assert_eq!(app.bridge.jobs.len(), 0);
    let huge = dir.path().join("sparse-oversized");
    std::fs::File::create(&huge)
        .unwrap()
        .set_len(40 * 1024 * 1024 + 1)
        .unwrap();
    let job = app.register_job(id.clone()).unwrap();
    assert!(matches!(
        app.import_photo(request(&id, &huge), job).await,
        Err(AppError::Validation { .. })
    ));
    assert_eq!(app.bridge.jobs.len(), 0);
}
#[tokio::test]
async fn staging_and_retry_enforce_original_size_before_acknowledgement() {
    let (dir, app) = application().await;
    let id = uuid::Uuid::new_v4().to_string();
    let path = dir.path().join("sparse-original");
    let maximum = reha_core::photo_source::MAX_BYTES as u64;
    std::fs::File::create(&path)
        .unwrap()
        .set_len(maximum + 1)
        .unwrap();
    assert!(matches!(
        app.stage_photo(id.clone(), path.to_string_lossy().into())
            .await,
        Err(AppError::Validation { .. })
    ));
    assert!(app
        .state
        .store
        .lock()
        .unwrap()
        .intakes()
        .unwrap()
        .is_empty());

    std::fs::write(&path, b"controlled original").unwrap();
    app.stage_photo(id.clone(), path.to_string_lossy().into())
        .await
        .unwrap();
    let retained = app.state.store.lock().unwrap().source_path(&id).unwrap();
    // Corrupt only this test's disposable retained copy, never a real original.
    std::fs::File::options()
        .write(true)
        .open(&retained)
        .unwrap()
        .set_len(maximum + 1)
        .unwrap();
    let job = app.register_job(id.clone()).unwrap();
    assert!(matches!(
        app.retry_capture(id.clone(), job).await,
        Err(AppError::Validation { .. })
    ));
    assert!(!app.recognition_busy());
    assert_eq!(app.bridge.jobs.len(), 0);
    assert_eq!(std::fs::metadata(retained).unwrap().len(), maximum + 1);
    let store = app.state.store.lock().unwrap();
    let intakes = store.intakes().unwrap();
    assert_eq!(intakes.len(), 1);
    assert_eq!(intakes[0].id, id);
    assert_eq!(intakes[0].status, "stored");
    assert_eq!(
        intakes[0].source_hash,
        reha_core::hash(b"controlled original")
    );
}

#[tokio::test]
async fn retry_uses_a_new_attempt_and_observes_cancellation_before_reading_store() {
    let (_dir, app) = application().await;
    let id = uuid::Uuid::new_v4().to_string();
    let first = app.register_job(id.clone()).unwrap();
    first.cancel();
    assert!(matches!(
        app.retry_capture(id.clone(), first.clone()).await,
        Err(AppError::Cancelled)
    ));
    assert_eq!(app.bridge.jobs.len(), 0);
    let second = app.register_job(id.clone()).unwrap();
    first.cancel();
    app.cancel_job(first.attempt_id()).unwrap();
    assert!(matches!(
        app.retry_capture(id, second).await,
        Err(AppError::ExpiredScan)
    ));
    assert_eq!(app.bridge.jobs.len(), 0);
}
#[tokio::test]
async fn dropped_caller_cancels_but_worker_owns_cleanup_until_it_returns() {
    let (_dir, app) = application().await;
    let id = uuid::Uuid::new_v4().to_string();
    let job = app.register_job(id.clone()).unwrap();
    let (entered, entering) = tokio::sync::oneshot::channel();
    let (finish, finishing) = tokio::sync::oneshot::channel();
    let cloned = app.clone();
    let token = job.clone();
    let scan = id.clone();
    let caller = tokio::spawn(async move {
        cloned
            .recognition_job(token, scan, async move {
                entered.send(()).unwrap();
                finishing.await.unwrap();
                Ok(())
            })
            .await
    });
    entering.await.unwrap();
    assert!(app.recognition_busy());
    let worker_flag = app.bridge.cancellation_flag(&id).unwrap();
    // This is the same Arc that scan::import_image/retry_scan put into state.cancel.
    assert!(!worker_flag.load(Ordering::Relaxed));
    caller.abort();
    assert!(caller.await.unwrap_err().is_cancelled());
    assert!(worker_flag.load(Ordering::Relaxed));
    assert_eq!(app.bridge.jobs.len(), 1);
    job.close();
    assert!(matches!(app.register_job(id.clone()), Err(AppError::Busy)));
    finish.send(()).unwrap();
    drained(&app).await;
    assert!(!app.recognition_busy());
    let retry = app.register_job(id).unwrap();
    job.cancel();
    assert!(!retry.is_cancelled());
    retry.close();
}
#[tokio::test]
async fn successful_failed_and_panicking_workers_all_release_their_attempt() {
    let (_dir, app) = application().await;
    let id = uuid::Uuid::new_v4().to_string();
    let job = app.register_job(id.clone()).unwrap();
    app.recognition_job(job, id.clone(), async { Ok(()) })
        .await
        .unwrap();
    assert_eq!(app.bridge.jobs.len(), 0);
    assert!(app.job_progress(id.clone()).unwrap().state == JobState::Completed);
    let job = app.register_job(id.clone()).unwrap();
    assert!(matches!(
        app.recognition_job(job, id.clone(), async { Err::<(), _>(AppError::Busy) })
            .await,
        Err(AppError::Busy)
    ));
    assert_eq!(app.bridge.jobs.len(), 0);
    assert!(app.job_progress(id.clone()).unwrap().state == JobState::Failed);
    let job = app.register_job(id.clone()).unwrap();
    assert!(matches!(
        app.recognition_job(job, id.clone(), async {
            panic!("synthetic worker panic");
            #[allow(unreachable_code)]
            Ok(())
        })
        .await,
        Err(AppError::Storage { .. })
    ));
    assert_eq!(app.bridge.jobs.len(), 0);
    assert!(!app.recognition_busy());
    assert!(app.job_progress(id).unwrap().state == JobState::Failed);
}

#[tokio::test]
async fn late_progress_cannot_reopen_a_terminal_attempt() {
    let (_dir, app) = application().await;
    for expected in [JobState::Completed, JobState::Failed, JobState::Cancelled] {
        let id = uuid::Uuid::new_v4().to_string();
        let job = app.register_job(id.clone()).unwrap();
        let attempt = job.cancellation_flag();
        if expected == JobState::Cancelled {
            job.cancel();
        }
        let _ = app
            .recognition_job(job, id.clone(), async move {
                if expected == JobState::Failed {
                    Err(AppError::Busy)
                } else {
                    Ok(())
                }
            })
            .await;
        assert!(app.job_progress(id.clone()).unwrap().state == expected);
        app.bridge.update_progress(
            &attempt,
            service::progress::ProgressUpdate::new(&id, "Verspäteter Worker"),
        );
        assert!(
            app.job_progress(id.clone()).unwrap().state == expected,
            "late progress reopened a terminal attempt"
        );
        assert_eq!(app.bridge.jobs.len(), 0);
    }
}

#[tokio::test]
async fn late_progress_from_an_older_attempt_cannot_replace_a_retry() {
    let (_dir, app) = application().await;
    let id = uuid::Uuid::new_v4().to_string();
    let first = app.register_job(id.clone()).unwrap();
    let first_attempt = first.cancellation_flag();
    app.recognition_job(first.clone(), id.clone(), async { Ok(()) })
        .await
        .unwrap();
    let retry = app.register_job(id.clone()).unwrap();
    assert_ne!(first.attempt_id(), retry.attempt_id());
    let (entered, entering) = tokio::sync::oneshot::channel();
    let (finish, finishing) = tokio::sync::oneshot::channel();
    let worker = app.clone();
    let scan = id.clone();
    let task = tokio::spawn(async move {
        worker
            .recognition_job(retry, scan, async move {
                entered.send(()).unwrap();
                finishing.await.unwrap();
                Ok(())
            })
            .await
    });
    entering.await.unwrap();
    app.bridge.update_progress(
        &first_attempt,
        service::progress::ProgressUpdate::new(&id, "Verspäteter erster Versuch"),
    );
    app.bridge
        .finish_progress(&id, &first_attempt, JobState::Failed);
    let observed = app.job_progress(id).unwrap();
    // Drain the controlled worker before asserting, including on a red run.
    finish.send(()).unwrap();
    task.await.unwrap().unwrap();
    assert_eq!(app.bridge.jobs.len(), 0);
    assert_eq!(observed.stage, "Foto vorbereiten");
    assert!(observed.state == JobState::Running);
}

#[tokio::test]
async fn typed_progress_preserves_fields_and_ignores_unowned_or_legacy_updates() {
    let (_dir, app) = application().await;
    let id = uuid::Uuid::new_v4().to_string();
    let job = app.register_job(id.clone()).unwrap();
    let attempt = job.cancellation_flag();
    let worker = app.clone();
    let scan = id.clone();
    let observed = app
        .recognition_job(job, id.clone(), async move {
            let initial = worker.job_progress(scan.clone()).unwrap();
            assert_eq!(initial.id, scan);
            assert_eq!(initial.stage, "Foto vorbereiten");
            assert_eq!(initial.elapsed_ms, 0);
            assert_eq!(initial.budget_ms, 60_000);
            assert!(!initial.draft_available);
            assert!(initial.state == JobState::Running);
            worker.bridge.update_progress(
                &attempt,
                service::progress::ProgressUpdate {
                    id: scan.clone(),
                    stage: "Prüfbarer Entwurf".into(),
                    elapsed_ms: 1234,
                    budget_ms: 59_000,
                    draft_available: true,
                },
            );
            worker
                .bridge
                .progress(json!({"id":scan,"stage":"Legacy ohne Identität"}));
            worker.bridge.update_progress(
                &Arc::new(AtomicBool::new(false)),
                service::progress::ProgressUpdate::new(&scan, "Fremder Versuch"),
            );
            let unknown = uuid::Uuid::new_v4().to_string();
            worker.bridge.update_progress(
                &attempt,
                service::progress::ProgressUpdate::new(&unknown, "Unbekannter Scan"),
            );
            assert!(worker.job_progress(unknown).is_none());
            Ok(worker.job_progress(scan).unwrap())
        })
        .await
        .unwrap();
    assert_eq!(observed.id, id);
    assert_eq!(observed.stage, "Prüfbarer Entwurf");
    assert_eq!(observed.elapsed_ms, 1234);
    assert_eq!(observed.budget_ms, 59_000);
    assert!(observed.draft_available);
    assert!(observed.state == JobState::Running);
    assert!(app.job_progress(id).unwrap().state == JobState::Completed);
    assert_eq!(app.bridge.jobs.len(), 0);
}
