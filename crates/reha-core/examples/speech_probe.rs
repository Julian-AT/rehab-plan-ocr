#[cfg(feature = "onnx")]
fn main() -> Result<(), Box<dyn std::error::Error>> {
    use std::{sync::atomic::AtomicU64, time::Instant};
    let args: Vec<String> = std::env::args().collect();
    let root = std::path::Path::new(args.get(1).expect("model directory"));
    let out = std::path::Path::new(args.get(2).expect("test output directory"));
    std::fs::create_dir_all(out)?;
    let started = Instant::now();
    let mut engine = reha_core::speech::SpeechEngine::load(root)?;
    println!("Model loaded in {:.2}s", started.elapsed().as_secs_f32());
    let latest = AtomicU64::new(1);
    for voice in ["F1", "M1"] {
        let started = Instant::now();
        let wav = engine.render(
            "Dein nächster Termin ist morgen um neun Uhr im Raum eins.",
            voice,
            0.95,
            1,
            &latest,
        )?;
        assert!(wav.starts_with(b"RIFF") && wav.len() > 44100);
        println!(
            "{voice}: {} audio bytes generated in {:.2}s",
            wav.len(),
            started.elapsed().as_secs_f32()
        );
        std::fs::write(out.join(format!("german-{voice}.wav")), wav)?;
    }
    assert!(engine
        .render("Dieser Beitrag wurde beendet.", "F1", 0.95, 2, &latest)
        .is_err());
    println!("Real model audio and cancellation passed");
    Ok(())
}
#[cfg(not(feature = "onnx"))]
fn main() {
    eprintln!("Requires --features onnx-download");
}
