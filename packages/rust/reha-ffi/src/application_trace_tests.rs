use super::*;
#[test]
fn trace_artifacts_require_debug_evidence_and_a_local_filename() {
    let mut run: domain::PipelineRun = serde_json::from_str(include_str!(
        "../../../../ml/evaluation/fixtures/sample-run.json"
    ))
    .unwrap();
    run.stages[0].artifacts = vec![
        "region-1.png".into(),
        "../private.png".into(),
        "/private.png".into(),
    ];
    assert!(!allowed_trace_artifact(&run, "region-1.png"));
    run.config.detailed_debug = true;
    assert!(allowed_trace_artifact(&run, "region-1.png"));
    run.refinement_attempts.push(
        serde_json::from_value(serde_json::json!({
            "id": "reread-0000", "target_ids": [], "reason": "unclear", "variant": "crop",
            "crop_to_original": [1,0,0,0,1,0,0,0,1], "crop_to_page": [1,0,0,0,1,0,0,0,1],
            "width": 20, "height": 10, "duration_ms": 1, "status": "complete",
            "observation_ids": [], "detail": "Synthetic test"
        }))
        .unwrap(),
    );
    assert!(allowed_trace_artifact(&run, "region-reread-0000.png"));
    for name in [
        "../private.png",
        "/private.png",
        "unlisted.png",
        "ledger.sqlite",
        "",
        "region-1.png/extra",
        "region-reread-0001.png",
    ] {
        assert!(!allowed_trace_artifact(&run, name));
    }
}
