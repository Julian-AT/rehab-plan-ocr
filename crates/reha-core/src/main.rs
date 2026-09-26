use reha_core::{contracts::*, Error, Result};

fn main() {
    if let Err(error) = execute() {
        eprintln!("{error}");
        std::process::exit(1);
    }
}

fn execute() -> Result<()> {
    let args: Vec<_> = std::env::args().collect();
    match args.get(1).map(String::as_str) {
        #[cfg(feature = "onnx")]
        Some("scan") if (5..=6).contains(&args.len()) => scan(&args)?,
        Some("experiment-crop") if args.len() == 4 => {
            let path=std::path::Path::new(&args[2]);
            let run:PipelineRun=serde_json::from_slice(&std::fs::read(path)?)?;
            reha_core::refinement::experiment_crop(&run,path.parent().unwrap_or(std::path::Path::new(".")),std::path::Path::new(&args[3]))?;
        }
        Some("extract") if args.len() == 4 => {
            let run: PipelineRun = serde_json::from_slice(&std::fs::read(&args[2])?)?;
            let (appointments, issues, unassigned) = reha_core::parser::extract(&run.document.id, &run.observations, &run.regions);
            let result = serde_json::json!({
                "extraction_version": reha_core::parser::EXTRACTION_VERSION,
                "source_hash": run.document.source_hash,
                "appointments": appointments, "issues": issues, "unassigned": unassigned,
            });
            std::fs::write(&args[3], serde_json::to_vec_pretty(&result)?)?;
            println!("{} appointments; extraction saved locally.", appointments.len());
        }
        Some("evaluate") if args.len() == 5 => {
            let annotation = serde_json::from_slice(&std::fs::read(&args[2])?)?;
            let run: PipelineRun = serde_json::from_slice(&std::fs::read(&args[3])?)?;
            let metrics = reha_core::evaluation::compare(&annotation, &run.appointments, false)?;
            std::fs::write(&args[4], serde_json::to_vec_pretty(&metrics)?)?;
            println!("Reference {}, predictions {}, fully correct {}.", metrics.reference_count, metrics.predicted_count, metrics.fully_correct_count);
        }
        Some("ics") if (4..=5).contains(&args.len()) => {
            let mut run: PipelineRun = serde_json::from_slice(&std::fs::read(&args[2])?)?;
            reha_core::review::migrate(&mut run)?;
            let selection:Vec<String> = if let Some(path) = args.get(4) { serde_json::from_slice(&std::fs::read(path)?)? } else { run.appointments.iter().filter(|a| a.included).map(|a| a.id.clone()).collect() };
            let events = reha_core::calendar::selected_events(std::slice::from_ref(&run), &selection, &run.config.timezone, None)?;
            std::fs::write(&args[3], reha_core::calendar::ics(&events, chrono::Utc::now())?)?;
            println!("ICS created locally.");
        }
        _ => return Err(Error::Invalid("Usage: reha scan INPUT OUTPUT_DIRECTORY MODEL_DIRECTORY [CONFIG.json] | extract RUN_JSON OUTPUT_JSON | evaluate LABEL RUN REPORT | ics APPROVED_RUN OUTPUT.ics [SELECTION.json]\nDesktop inference requires --features onnx-download.".into())),
    }
    Ok(())
}

#[cfg(feature = "onnx")]
fn scan(args: &[String]) -> Result<()> {
    use reha_core::pipeline::{self, ScanInput};
    use std::{path::Path, sync::atomic::AtomicBool, time::Instant};

    let bytes = std::fs::read(&args[2])?;
    let output = Path::new(&args[3]);
    std::fs::create_dir_all(output)?;
    let mut config = if let Some(path) = args.get(5) {
        serde_json::from_slice(&std::fs::read(path)?)?
    } else {
        PipelineConfig::default()
    };
    let started = Instant::now();
    let mut engine = reha_core::ocr::OnnxEngine::load(Path::new(&args[4]))?;
    let load_ms = started.elapsed().as_millis() as u64;
    let expected = format!(
        "portable-{}",
        engine.name.strip_prefix("PP-OCRv6_").unwrap_or("unknown")
    );
    if args.get(5).is_some() && config.engine != expected {
        return Err(Error::Invalid(
            "Configured engine does not match model directory.".into(),
        ));
    }
    config.engine = expected;
    let mut run = pipeline::run(
        &mut engine,
        ScanInput {
            bytes: &bytes,
            filename: &args[2],
            id: &uuid::Uuid::new_v4().to_string(),
            now: chrono::Utc::now().timestamp(),
            config,
            dir: output,
            deadline: started + std::time::Duration::from_secs(30),
        },
        &AtomicBool::new(false),
        false,
    )?;
    run.stages.insert(
        0,
        Stage {
            name: "model_load".into(),
            status: "complete".into(),
            duration_ms: load_ms,
            detail: "Hash-verified ONNX models; CPU execution; two intra-op threads.".into(),
            artifacts: vec![],
        },
    );
    run.total_ms = started.elapsed().as_millis() as u64;
    std::fs::write(output.join("run.json"), serde_json::to_vec_pretty(&run)?)?;
    println!(
        "{} appointments, {} observations, {} ms. Review required.",
        run.appointments.len(),
        run.observations.len(),
        run.total_ms
    );
    Ok(())
}
