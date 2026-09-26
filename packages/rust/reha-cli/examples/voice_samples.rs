//! Invented listening samples through the same SpeechEngine as the iOS binding.
//! Desktop synthesis timing excludes playback and is not an iOS latency result.
use reha_core::{speech::SpeechEngine, Error, Result};
use serde_json::json;
use std::{collections::HashSet, path::Path, sync::atomic::AtomicU64, time::Instant};

fn main() {
    if let Err(error) = run() {
        eprintln!("{error}");
        std::process::exit(1);
    }
}

fn run() -> Result<()> {
    let args: Vec<_> = std::env::args().collect();
    if args.len() != 4 {
        return Err(Error::Invalid(
            "Usage: voice_samples MODEL_DIRECTORY PROMPTS_JSON NEW_OUTPUT".into(),
        ));
    }
    let request: serde_json::Value = serde_json::from_slice(&std::fs::read(&args[2])?)?;
    let samples = request["samples"]
        .as_array()
        .filter(|v| !v.is_empty() && v.len() <= 100)
        .ok_or_else(|| Error::Invalid("Missing or excessive listening samples".into()))?;
    let mut ids = HashSet::new();
    for sample in samples {
        let id = sample["id"].as_str().unwrap_or("");
        if id.is_empty()
            || id.len() > 64
            || !id
                .bytes()
                .all(|b| b.is_ascii_alphanumeric() || b == b'-' || b == b'_')
            || !ids.insert(id)
            || sample["text"]
                .as_str()
                .is_none_or(|t| t.trim().is_empty() || t.chars().count() > 2000)
        {
            return Err(Error::Invalid("Invalid listening sample ID or text".into()));
        }
    }
    let output = Path::new(&args[3]);
    std::fs::create_dir(output)?;
    let start = Instant::now();
    let mut engine = SpeechEngine::load(Path::new(&args[1]))?;
    let load_ms = start.elapsed().as_secs_f64() * 1000.0;
    let latest = AtomicU64::new(1);
    let mut records = Vec::new();
    for sample in samples {
        let id = sample["id"].as_str().unwrap();
        let text = sample["text"].as_str().unwrap();
        let start = Instant::now();
        let render = engine.render_timed(text, "victoria", 0.95, 1, &latest)?;
        let synthesis_ms = start.elapsed().as_secs_f64() * 1000.0;
        let path = format!("{id}.wav");
        std::fs::write(output.join(&path), &render.audio)?;
        records.push(json!({
            "id": id, "text": text, "spoken_text": reha_core::speech_text::normalize(text),
            "path": path, "sha256": reha_core::hash(&render.audio),
            "duration_seconds": render.duration, "synthesis_ms": synthesis_ms, "marks": render.marks,
        }));
    }
    let report = json!({
        "schema_version": 1, "route": "host-shared-speech-engine", "shipping_ios_route": false,
        "audio_startup_measured": false, "voice": "victoria", "speed": 0.95,
        "model_manifest_sha256": reha_core::hash(include_bytes!("../../../../ml/registry/runtime/kokoro.lock.json")),
        "model_load_ms": load_ms, "samples": records,
    });
    std::fs::write(
        output.join("manifest.json"),
        serde_json::to_vec_pretty(&report)?,
    )?;
    println!(
        "{} synthetic listening samples rendered; human assessment pending",
        samples.len()
    );
    Ok(())
}
