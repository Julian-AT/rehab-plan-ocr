//! Writes public synthetic data only. Refuses to touch an existing database.
use reha_core::{contracts::PipelineRun, store::Store};
fn main() {
    let root = std::path::PathBuf::from(std::env::args().nth(1).expect("fresh fixture directory"));
    assert!(
        !root.join("ledger.sqlite").exists(),
        "Refusing to replace an existing store"
    );
    let mut store = Store::open(&root).unwrap();
    let mut run: PipelineRun =
        serde_json::from_str(include_str!("../../../../tests/fixtures/sample-run.json")).unwrap();
    reha_core::review::migrate(&mut run).unwrap();
    run.document.imported_at = chrono::Utc::now().timestamp();
    run.document.filename = "synthetic-day.png".into();
    let dir = store.scan_dir(&run.document.id).unwrap();
    std::fs::create_dir_all(&dir).unwrap();
    for file in ["source.bin", "original.png", "page.png"] {
        std::fs::write(
            dir.join(file),
            include_bytes!("../../../../tests/fixtures/synthetic-day.png"),
        )
        .unwrap();
    }
    store.save_run(&run).unwrap();
    if std::env::args().any(|a| a == "--ui") {
        use reha_core::contracts::*;
        let mut clear = run.clone();
        clear.document.id = "11111111-1111-4111-8111-111111111111".into();
        clear.document.imported_at += 10;
        clear.extraction_version = reha_core::parser::EXTRACTION_VERSION;
        clear.appointments = (0..2)
            .map(|i| {
                let mut a = Appointment::empty(format!("22222222-2222-4222-8222-22222222222{i}"));
                a.date = Some(chrono::Utc::now().format("%Y-%m-%d").to_string());
                a.title = format!("Testtherapie {}", i + 1);
                a.start = Some(format!("{:02}:00", 8 + i));
                a.end = Some(format!("{:02}:30", 8 + i));
                a.fields
                    .insert("location".into(), FieldAssessment::default());
                a.fields
                    .insert("therapist".into(), FieldAssessment::default());
                a
            })
            .collect();
        let mut second = clear.clone();
        second.document.id = "33333333-3333-4333-8333-333333333333".into();
        second.document.imported_at -= 20;
        for a in &mut second.appointments {
            a.id = uuid::Uuid::new_v4().to_string();
        }
        let mut third = second.clone();
        third.document.id = "44444444-4444-4444-8444-444444444444".into();
        for a in &mut third.appointments {
            a.id = uuid::Uuid::new_v4().to_string();
            a.date = Some(
                (chrono::Utc::now() + chrono::Duration::days(2))
                    .format("%Y-%m-%d")
                    .to_string(),
            );
        }
        for page in [&clear, &second, &third] {
            let dir = store.scan_dir(&page.document.id).unwrap();
            std::fs::create_dir_all(&dir).unwrap();
            for file in ["source.bin", "original.png", "page.png"] {
                std::fs::write(
                    dir.join(file),
                    include_bytes!("../../../../tests/fixtures/synthetic-day.png"),
                )
                .unwrap();
            }
            store.save_run(page).unwrap();
        }
        store
            .group_pages(
                &second.document.id,
                &[second.document.id.clone(), third.document.id],
            )
            .unwrap();
        let failed = "55555555-5555-4555-8555-555555555555";
        store
            .stage_intake(
                failed,
                "unreadable.png",
                b"broken-image-fixture",
                &PipelineConfig::default(),
                run.document.imported_at - 30,
            )
            .unwrap();
        store
            .intake_status(failed, "failed", Some("Das Testbild ist beschädigt."))
            .unwrap();
    }
    println!("{}", run.document.id);
}
