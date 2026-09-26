//! Render the factual Swift answer probe's JSON through the app's local voice.
#[cfg(feature = "kokoro")]
fn main() -> Result<(), Box<dyn std::error::Error>> {
    use std::{path::PathBuf, sync::atomic::AtomicU64, time::Instant};
    #[derive(serde::Deserialize, serde::Serialize)]
    struct Example {
        name: String,
        text: String,
        speech: String,
    }
    let args: Vec<_> = std::env::args().collect();
    let models = PathBuf::from(args.get(1).ok_or("Model directory required")?);
    let input = PathBuf::from(args.get(2).ok_or("Swift answer JSON required")?);
    let output = PathBuf::from(args.get(3).ok_or("Output directory required")?);
    let examples: Vec<Example> = serde_json::from_slice(&std::fs::read(input)?)?;
    let mut engine = reha_core::speech::SpeechEngine::load(&models)?;
    std::fs::create_dir_all(&output)?;
    let mut results = vec![];
    for example in examples {
        if example.name.is_empty()
            || !example
                .name
                .chars()
                .all(|c| c.is_ascii_alphanumeric() || c == '-')
        {
            return Err("Invalid sample name".into());
        }
        let started = Instant::now();
        let rendered =
            engine.render_timed(&example.speech, "victoria", 0.95, 1, &AtomicU64::new(1))?;
        assert!(!rendered.marks.is_empty());
        assert!(rendered.audio.starts_with(b"RIFF"));
        assert_eq!(
            u32::from_le_bytes(rendered.audio[24..28].try_into()?),
            24_000
        );
        let seconds = started.elapsed().as_secs_f64();
        std::fs::write(
            output.join(format!("{}.wav", example.name)),
            &rendered.audio,
        )?;
        results.push(serde_json::json!({"sample":example,"render_seconds":seconds,"audio_seconds":rendered.duration,"marks":rendered.marks}));
    }
    std::fs::write(
        output.join("samples.json"),
        serde_json::to_vec_pretty(&results)?,
    )?;
    println!(
        "{} factual answer samples rendered locally, 24 kHz.",
        results.len()
    );
    Ok(())
}
#[cfg(not(feature = "kokoro"))]
fn main() {
    eprintln!("Requires --features kokoro,onnx-download");
}
