#[cfg(feature = "kokoro")]
fn main() -> Result<(), Box<dyn std::error::Error>> {
    use std::{
        sync::atomic::{AtomicU64, Ordering},
        time::{Duration, Instant},
    };
    let args: Vec<String> = std::env::args().collect();
    let root = std::path::Path::new(args.get(1).expect("model directory"));
    let out = std::path::Path::new(args.get(2).expect("test output directory"));
    std::fs::create_dir_all(out)?;
    let started = Instant::now();
    let mut engine = reha_core::speech::SpeechEngine::load(root)?;
    println!("Model loaded in {:.2}s", started.elapsed().as_secs_f32());
    let latest = AtomicU64::new(1);
    for (name, text, speed) in [
        ("victoria-kalender", "Am 14.09.2026 um 09:15 Uhr beginnt deine Physiotherapie in Laßnitzhöhe. Bitte komm in Raum 2.14. Der Termin endet um 09:45 Uhr.", 0.95),
        ("victoria-langsam", "Am Dienstag, 15. September 2026, hast du um 13:05 Uhr Ergotherapie. Treffpunkt ist Raum 105. Danach geht es um 14:00 Uhr zur Rückengymnastik in den Turnsaal.", 0.75),
        ("victoria-lange-antwort", "Heute stehen mehrere Termine an. Um 08:30 Uhr beginnt die Physiotherapie im Raum 2.14 in Laßnitzhöhe. Sie dauert 30 Min. Um 10:15 Uhr folgt Ergotherapie in Raum 105. Dieser Termin endet um 11:00 Uhr. Am Nachmittag, um 13:05 Uhr, beginnt die Rückengymnastik im Turnsaal. Bitte prüfe die Angaben auf dem Bildschirm. Kalenderänderungen speichere ich erst, wenn du die Bestätigungsschaltfläche antippst.", 1.0),
    ] {
        let started = Instant::now();
        let wav = engine.render(text, "victoria", speed, 1, &latest)?;
        assert!(wav.starts_with(b"RIFF") && wav.len() > 48000);
        assert_eq!(u32::from_le_bytes(wav[24..28].try_into().unwrap()), 24_000);
        println!("{name}: {} bytes, {:.2}s audio, {:.2}s render", wav.len(), (wav.len() - 44) as f32 / 48_000.0, started.elapsed().as_secs_f32());
        std::fs::write(out.join(format!("{name}.wav")), wav)?;
    }
    let a = engine.render("Laßnitzhöhe.", "F1", 0.95, 1, &latest)?;
    let b = engine.render("Laßnitzhöhe.", "M1", 0.95, 1, &latest)?;
    let previous = engine.render("Laßnitzhöhe.", "martin", 0.95, 1, &latest)?;
    assert!(
        a.len() > 24_000
            && b.len() > 24_000
            && previous.len() > 24_000
            && a.len().abs_diff(b.len()) < 48_000,
        "Legacy IDs must render the sole bundled voice"
    );
    assert!(engine
        .render(
            "Dieser Beitrag wurde beendet.",
            "victoria",
            0.95,
            2,
            &latest
        )
        .is_err());
    let started = Instant::now();
    std::thread::scope(|scope| {
        scope.spawn(|| {
            std::thread::sleep(Duration::from_millis(200));
            latest.store(2, Ordering::Release);
        });
        assert!(engine.render("Ein längerer Beitrag zur Prüfung des Abbruchs während der Vorbereitung. Das Ergebnis darf nach dem Stopp nicht mehr ausgegeben werden.", "victoria", 0.95, 1, &latest).is_err());
    });
    assert!(started.elapsed() < Duration::from_secs(5));
    println!("24 kHz real Kokoro audio, long answer, legacy voice migration and in-flight inference cancellation passed");
    Ok(())
}
#[cfg(not(feature = "kokoro"))]
fn main() {
    eprintln!("Requires --features kokoro,onnx-download");
}
