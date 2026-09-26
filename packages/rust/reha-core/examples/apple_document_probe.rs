//! Desktop-only comparison through the same preparation and extraction pipeline.
//! Usage matches `reha scan INPUT OUTPUT PROBE_DIRECTORY CONFIG` for the harness.
#[cfg(target_os = "macos")]
fn main() -> Result<(), Box<dyn std::error::Error>> {
    use reha_core::{contracts::*, pipeline};
    use std::{path::Path, process::Command, sync::atomic::AtomicBool, time::Instant};
    let args: Vec<_> = std::env::args().collect();
    if args.len() != 6 || args[1] != "scan" {
        return Err("Expected scan INPUT OUTPUT PROBE_DIRECTORY CONFIG".into());
    }
    let started = Instant::now();
    let bytes = std::fs::read(&args[2])?;
    let output = Path::new(&args[3]);
    let config: PipelineConfig = serde_json::from_slice(&std::fs::read(&args[5])?)?;
    let mode = match config.engine.as_str() {
        "apple-documents" => "documents",
        "apple-text" => "text",
        _ => return Err("Expected an Apple comparison engine".into()),
    };
    let directory = Path::new(&args[4]);
    let manifest: serde_json::Value =
        serde_json::from_slice(&std::fs::read(directory.join("manifest.json"))?)?;
    if manifest["probe_sha256"].as_str()
        != Some(&reha_core::hash(&std::fs::read(
            directory.join("document-probe"),
        )?))
    {
        return Err("Native probe checksum changed".into());
    }
    let prepared = pipeline::prepare(
        &bytes,
        &args[2],
        &uuid::Uuid::new_v4().to_string(),
        chrono::Utc::now().timestamp(),
        &config,
        output,
    )?;
    let recognition_started = Instant::now();
    let mut child = Command::new(directory.join("document-probe"))
        .arg(mode)
        .arg(output.join("page.png"))
        .arg(output.join("recognition.json"))
        .spawn()?;
    loop {
        if let Some(status) = child.try_wait()? {
            if !status.success() {
                return Err("Native document request failed".into());
            }
            break;
        }
        if started.elapsed().as_secs() >= 60 {
            child.kill()?;
            child.wait()?;
            return Err("Native document request exceeded complete processing budget".into());
        }
        std::thread::sleep(std::time::Duration::from_millis(10));
    }
    let mut result: serde_json::Value =
        serde_json::from_slice(&std::fs::read(output.join("recognition.json"))?)?;
    // Preserve table cells for the structural comparison; this variant uses the
    // unchanged coordinate parser so OCR and table-assignment effects stay separate.
    result["manifest"]["tables"] = result["tables"].clone();
    let mut run = pipeline::assemble(
        &prepared,
        pipeline::RecognitionOutput {
            engine: format!("Apple Vision {mode}"),
            manifest: result["manifest"].clone(),
            regions: serde_json::from_value(result["regions"].clone())?,
            observations: serde_json::from_value(result["observations"].clone())?,
            cache_used: false,
            stages: vec![Stage {
                name: "recognition".into(),
                status: "complete".into(),
                duration_ms: recognition_started.elapsed().as_millis() as u64,
                detail:
                    "Single local Vision request including native process startup and JSON output."
                        .into(),
                artifacts: vec!["recognition.json".into()],
            }],
        },
        &AtomicBool::new(false),
    )?;
    run.total_ms = started.elapsed().as_millis() as u64;
    std::fs::write(output.join("run.json"), serde_json::to_vec_pretty(&run)?)?;
    Ok(())
}

#[cfg(not(target_os = "macos"))]
fn main() {
    eprintln!("Apple document comparison requires macOS 26.");
    std::process::exit(2);
}
