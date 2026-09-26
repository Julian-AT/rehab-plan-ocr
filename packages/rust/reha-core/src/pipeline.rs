use crate::{contracts::*, geometry, Error, Result};
use image::{DynamicImage, RgbImage};
use std::{path::Path, sync::atomic::AtomicBool, time::Instant};

pub struct Prepared {
    pub config: PipelineConfig,
    pub document: Document,
    pub page: RgbImage,
    pub original_to_page: [f64; 9],
    pub stages: Vec<Stage>,
    pub issues: Vec<Issue>,
}

pub fn prepare(
    bytes: &[u8],
    filename: &str,
    id: &str,
    now: i64,
    config: &PipelineConfig,
    dir: &Path,
) -> Result<Prepared> {
    uuid::Uuid::parse_str(id).map_err(|_| Error::Invalid("Invalid document ID".into()))?;
    if bytes.len() > crate::photo_source::MAX_BYTES {
        return Err(Error::Invalid("Foto größer als 40 MB.".into()));
    }
    if !(1..=8).contains(&config.recognition_batch_size)
        || !(320..=2560).contains(&config.detector_side)
        || !config.detector_threshold.is_finite()
        || !(0.05..=0.95).contains(&config.detector_threshold)
        || !config.box_threshold.is_finite()
        || !(0.05..=0.99).contains(&config.box_threshold)
    {
        return Err(Error::Invalid("Ungültige Erkennungskonfiguration.".into()));
    }
    let start = Instant::now();
    let crate::photo::DecodedPhoto {
        image: decoded,
        source_width: w,
        source_height: h,
        orientation,
        source_is_png,
    } = crate::photo::decode(bytes)?;
    // Original display frame is the EXIF-upright photograph; bytes are preserved separately.
    let ow = decoded.width();
    let oh = decoded.height();
    std::fs::create_dir_all(dir)?;
    std::fs::write(dir.join("source.bin"), bytes)?;
    // The decoded, validated upright PNG already contains the original pixels.
    // Re-encoding a full-resolution photograph here adds no information.
    if source_is_png && orientation == 1 {
        std::fs::write(dir.join("original.png"), bytes)?;
    } else {
        decoded.save(dir.join("original.png"))?;
    }
    let original_is_rgb8 = matches!(decoded, DynamicImage::ImageRgb8(_));
    let decode_ms = start.elapsed().as_millis() as u64;
    let correction_started = Instant::now();
    let mut transform = geometry::rotation(config.quarter_turns, ow, oh);
    let mut page = match config.quarter_turns % 4 {
        1 => decoded.rotate90(),
        2 => decoded.rotate180(),
        3 => decoded.rotate270(),
        _ => decoded,
    }
    .into_rgb8();
    if config.mirrored {
        let flip = [-1., 0., page.width() as f64, 0., 1., 0., 0., 0., 1.];
        page = image::imageops::flip_horizontal(&page);
        transform = geometry::multiply(&flip, &transform);
    }
    let mut detail =
        "EXIF orientation applied; original bytes retained. No automatic page-boundary claim."
            .to_string();
    let automatic = if config.page_corners.is_none() {
        geometry::paper_quad(&page)
    } else {
        None
    };
    let auto_original = automatic.map(|q| {
        q.map(|p| {
            geometry::map(
                &geometry::inverse(&transform).unwrap_or(geometry::IDENTITY),
                &p,
            )
        })
    });
    if let Some(corners) = config.page_corners.as_ref().or(auto_original.as_ref()) {
        if corners.iter().any(|p| {
            !p.x.is_finite()
                || !p.y.is_finite()
                || p.x < 0.
                || p.y < 0.
                || p.x > ow as f64
                || p.y > oh as f64
        }) {
            return Err(Error::Invalid(
                "Seitenpunkte liegen außerhalb des Fotos.".into(),
            ));
        }
        let mut corners = corners.map(|p| geometry::map(&transform, &p));
        // Preserve the requested rotation when mapping original-frame page corners.
        // After a clockwise turn the original bottom-left becomes the new top-left.
        if automatic.is_none() {
            corners.rotate_right((config.quarter_turns % 4) as usize);
        }
        if config.mirrored && automatic.is_none() {
            corners.swap(0, 1);
            corners.swap(2, 3);
        }
        let distance = |a: &Point, b: &Point| ((a.x - b.x).powi(2) + (a.y - b.y).powi(2)).sqrt();
        let pw = distance(&corners[0], &corners[1])
            .max(distance(&corners[2], &corners[3]))
            .round() as u32;
        let ph = distance(&corners[1], &corners[2])
            .max(distance(&corners[3], &corners[0]))
            .round() as u32;
        if pw < 64 || ph < 64 || pw as u64 * ph as u64 > 50_000_000 {
            return Err(Error::Invalid(
                "Seitenpunkte ergeben keinen gültigen Ausschnitt.".into(),
            ));
        }
        let target: [Point; 4] = geometry::rect(0., 0., pw as f64, ph as f64)
            .try_into()
            .unwrap();
        let m = geometry::homography(&corners, &target)?;
        let projection =
            imageproc::geometric_transformations::Projection::from_matrix(m.map(|v| v as f32))
                .ok_or_else(|| Error::Invalid("Seitenpunkte sind nicht eindeutig.".into()))?;
        let mut corrected = RgbImage::new(pw, ph);
        imageproc::geometric_transformations::warp_into(
            &page,
            &projection,
            imageproc::geometric_transformations::Interpolation::Bilinear,
            image::Rgb([255, 255, 255]),
            &mut corrected,
        );
        transform = geometry::multiply(&m, &transform);
        page = corrected;
        detail=if automatic.is_some() {"Four high-contrast page edges found; perspective corrected. All coordinates map back to original pixels."} else {"User-specified page corners; perspective corrected. Corner order: top-left, top-right, bottom-right, bottom-left."}.into();
    }
    if transform == geometry::IDENTITY && original_is_rgb8 {
        std::fs::copy(dir.join("original.png"), dir.join("page.png"))?;
    } else {
        page.save(dir.join("page.png"))?;
    }
    let correction_ms = correction_started.elapsed().as_millis() as u64;
    let quality_started = Instant::now();
    let mut issues = vec![Issue::new(
        "page_completeness",
        "Vollständige Seite und mögliche handschriftliche Änderungen mit dem Papier vergleichen.",
        None,
        false,
    )];
    if w.min(h) < 600 {
        issues.push(Issue::new(
            "low_resolution",
            "Kleine Aufnahme: feine Schrift könnte fehlen. Näher fotografieren.",
            None,
            false,
        ));
    }
    let small = quality_thumbnail(&page);
    let values: Vec<f64> = small.pixels().map(|p| p[0] as f64).collect();
    let mean = values.iter().sum::<f64>() / values.len() as f64;
    let variance = values.iter().map(|v| (v - mean).powi(2)).sum::<f64>() / values.len() as f64;
    if variance < 120. {
        issues.push(Issue::new(
            "low_contrast",
            "Wenig Kontrast. Lesbarkeit prüfen oder erneut fotografieren.",
            None,
            false,
        ));
    }
    let mut laplacian = vec![];
    for y in 1..small.height().saturating_sub(1) {
        for x in 1..small.width().saturating_sub(1) {
            laplacian.push(
                4. * small.get_pixel(x, y)[0] as f64
                    - small.get_pixel(x - 1, y)[0] as f64
                    - small.get_pixel(x + 1, y)[0] as f64
                    - small.get_pixel(x, y - 1)[0] as f64
                    - small.get_pixel(x, y + 1)[0] as f64,
            );
        }
    }
    let sharpness = laplacian.iter().map(|v| v * v).sum::<f64>() / laplacian.len().max(1) as f64;
    if sharpness < 35. {
        issues.push(Issue::new(
            "blur",
            "Wenig scharfe Kanten: Schrift vergrößern und starke Unschärfe prüfen.",
            None,
            false,
        ));
    }
    let stages=vec![Stage{name:"decode".into(),status:"complete".into(),duration_ms:decode_ms,detail:format!("{w}×{h}; EXIF {orientation}; upright {ow}×{oh}"),artifacts:vec!["original.png".into()]},Stage{name:"preprocessing".into(),status:"complete".into(),duration_ms:correction_ms,detail,artifacts:vec!["page.png".into()]},Stage{name:"quality".into(),status:"complete".into(),duration_ms:quality_started.elapsed().as_millis() as u64,detail:format!("Resolution, contrast (variance {variance:.1}) and edge sharpness ({sharpness:.1}) heuristics; no diagnostic probability."),artifacts:vec![]}];
    Ok(Prepared {
        config: config.clone(),
        document: Document {
            schema_version: SCHEMA_VERSION,
            id: id.into(),
            source_hash: crate::hash(bytes),
            filename: Path::new(filename)
                .file_name()
                .unwrap_or_default()
                .to_string_lossy()
                .into_owned(),
            width: ow,
            height: oh,
            orientation,
            imported_at: now,
            source: "import".into(),
        },
        page,
        original_to_page: transform,
        stages,
        issues,
    })
}

fn quality_thumbnail(page: &RgbImage) -> image::GrayImage {
    // Match DynamicImage::thumbnail's rounded aspect-preserving dimensions,
    // without cloning the entire photograph merely to borrow its pixels.
    let ratio = 512. / f64::from(page.width().max(page.height()));
    let width = (f64::from(page.width()) * ratio).round().max(1.) as u32;
    let height = (f64::from(page.height()) * ratio).round().max(1.) as u32;
    DynamicImage::ImageRgb8(image::imageops::thumbnail(page, width, height)).into_luma8()
}

pub struct RecognitionOutput {
    pub engine: String,
    pub manifest: serde_json::Value,
    pub regions: Vec<Region>,
    pub observations: Vec<Observation>,
    pub stages: Vec<Stage>,
    pub cache_used: bool,
}
pub fn assemble(
    prepared: &Prepared,
    output: RecognitionOutput,
    cancel: &AtomicBool,
) -> Result<PipelineRun> {
    let check_cancel = || {
        if cancel.load(std::sync::atomic::Ordering::Relaxed) {
            Err(Error::Invalid("Verarbeitung abgebrochen.".into()))
        } else {
            Ok(())
        }
    };
    check_cancel()?;
    let RecognitionOutput {
        engine,
        manifest,
        mut regions,
        observations,
        stages,
        cache_used,
    } = output;
    let config = prepared.config.clone();
    let start = Instant::now();
    let (mut appointments, mut issues, unassigned) =
        crate::parser::extract(&prepared.document.id, &observations, &regions);
    check_cancel()?;
    let text_heights: Vec<_> = regions
        .iter()
        .filter(|r| r.kind == "text")
        .map(|r| {
            let (_, y, _, b) = geometry::bounds(&r.polygon);
            b - y
        })
        .collect();
    if !text_heights.is_empty()
        && text_heights.iter().filter(|h| **h < 16.).count() * 3 > text_heights.len()
    {
        issues.push(Issue::new(
            "small_text",
            "Viele sehr kleine Schriftzeilen: näher fotografieren oder Ausschnitt korrigieren.",
            None,
            false,
        ));
    }
    for a in &mut appointments {
        check_cancel()?;
        for (field, f) in &mut a.fields {
            let ids = a.provenance.get(field).cloned().unwrap_or_default();
            let clipped = observations
                .iter()
                .filter(|o| ids.contains(&o.id))
                .flat_map(|o| &o.region_ids)
                .filter_map(|id| regions.iter().find(|r| &r.id == id))
                .any(|r| {
                    r.polygon.iter().any(|p| {
                        p.x < 3.
                            || p.y < 3.
                            || p.x > prepared.page.width() as f64 - 3.
                            || p.y > prepared.page.height() as f64 - 3.
                    })
                });
            if clipped {
                f.state = PrintedState::Cropped;
                f.reasons
                    .push("Text berührt den Bildrand; möglicherweise abgeschnitten.".into());
            }
        }
    }
    if appointments.is_empty() {
        issues.push(Issue::new("orientation_review", "Keine sichere Tabellenorientierung: Drehung, Spiegelung und Ausschnitt am Foto prüfen.", None, false));
    }
    check_cancel()?;
    crate::parser::add_layout(
        &observations,
        &mut regions,
        prepared.page.width(),
        prepared.page.height(),
    );
    check_cancel()?;
    issues.extend(prepared.issues.clone());
    if observations
        .iter()
        .any(|o| o.score.is_some_and(|s| s < 0.8) || o.text.trim().is_empty())
    {
        issues.push(Issue::new(
            "weak_recognition",
            "Textstellen mit schwachen Erkennungssignalen prüfen.",
            None,
            false,
        ));
    }
    let mut all_stages = prepared.stages.clone();
    all_stages.extend(stages);
    all_stages.push(Stage{name:"layout_and_fields".into(),status:"complete".into(),duration_ms:start.elapsed().as_millis() as u64,detail:"Geometric line grouping; explicit date labels; printed times only. Unassigned observations retained.".into(),artifacts:vec![]});
    all_stages.push(Stage {
        name: "validation".into(),
        status: "complete".into(),
        duration_ms: 0,
        detail: format!(
            "{} appointments; {} unassigned observations; {} document issues",
            appointments.len(),
            unassigned.len(),
            issues.len()
        ),
        artifacts: vec![],
    });
    let total_ms = all_stages.iter().map(|s| s.duration_ms).sum();
    let sections = crate::parser::sections(&observations, &regions);
    check_cancel()?;
    Ok(PipelineRun {
        schema_version: SCHEMA_VERSION,
        sections,
        refinement_attempts: vec![],
        refinement_readings: vec![],
        extraction_version: crate::parser::EXTRACTION_VERSION,
        id: uuid::Uuid::new_v4().to_string(),
        document: prepared.document.clone(),
        config,
        engine,
        model_manifest: manifest,
        stages: all_stages,
        regions,
        observations,
        appointments,
        issues,
        unassigned,
        original_to_page: prepared.original_to_page,
        page_to_original: geometry::inverse(&prepared.original_to_page)?,
        page_width: prepared.page.width(),
        page_height: prepared.page.height(),
        complete_page_confirmed: false,
        review_confirmed: false,
        total_ms,
        peak_memory_bytes: None,
        cache_used,
    })
}

#[cfg(feature = "onnx")]
pub struct ScanInput<'a> {
    pub bytes: &'a [u8],
    pub filename: &'a str,
    pub id: &'a str,
    pub now: i64,
    pub config: PipelineConfig,
    pub dir: &'a Path,
    pub deadline: Instant,
}
#[cfg(feature = "onnx")]
pub fn run(
    engine: &mut crate::ocr::OnnxEngine,
    input: ScanInput<'_>,
    cancel: &AtomicBool,
    cache_used: bool,
) -> Result<PipelineRun> {
    run_with_progress(engine, input, cancel, cache_used, &|_, _| {})
}
#[cfg(feature = "onnx")]
pub fn run_with_progress(
    engine: &mut crate::ocr::OnnxEngine,
    input: ScanInput<'_>,
    cancel: &AtomicBool,
    cache_used: bool,
    progress: &impl Fn(&str, Option<&PipelineRun>),
) -> Result<PipelineRun> {
    let ScanInput {
        bytes,
        filename,
        id,
        now,
        config,
        dir,
        deadline,
    } = input;
    let start = Instant::now();
    crate::ocr::check_cancel(cancel)?;
    progress("Bildaufbereitung", None);
    let prepared = prepare(bytes, filename, id, now, &config, dir)?;
    progress("Text und Tabellenzeilen erkennen", None);
    let (regions, observations, stages) =
        engine.recognize_until(&prepared.page, &config, cancel, dir, Some(deadline))?;
    let mut run = assemble(
        &prepared,
        RecognitionOutput {
            engine: engine.name.clone(),
            manifest: engine.manifest.clone(),
            regions,
            observations,
            stages,
            cache_used,
        },
        cancel,
    )?;
    progress("Entwurf gesichert; unklare Felder nachlesen", Some(&run));
    // An unchanged page is already the original RGB image required by rereads.
    // For corrected pages free that buffer before loading the original frame.
    let original = if prepared.original_to_page == geometry::IDENTITY {
        Some(prepared.page)
    } else {
        drop(prepared.page);
        None
    };
    if let Err(error) = crate::refinement::refine_with_original(
        engine,
        &mut run,
        dir,
        cancel,
        deadline,
        original.as_ref(),
    ) {
        run.stages.push(Stage {
            name: "selective_reread".into(),
            status: "failed".into(),
            duration_ms: 0,
            detail: error.to_string(),
            artifacts: vec![],
        });
    }
    run.total_ms = start.elapsed().as_millis() as u64;
    progress("Prüfung beendet", Some(&run));
    Ok(run)
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::io::Cursor;

    #[test]
    fn cancelled_assembly_cannot_return_a_completed_run() {
        let prepared = Prepared {
            config: PipelineConfig::default(),
            document: Document {
                schema_version: SCHEMA_VERSION,
                id: "synthetic-cancellation".into(),
                source_hash: "synthetic".into(),
                filename: "synthetic.png".into(),
                width: 32,
                height: 32,
                orientation: 1,
                imported_at: 0,
                source: "test".into(),
            },
            page: RgbImage::new(32, 32),
            original_to_page: geometry::IDENTITY,
            stages: vec![],
            issues: vec![],
        };
        let output = || RecognitionOutput {
            engine: "synthetic".into(),
            manifest: serde_json::json!({}),
            regions: vec![],
            observations: vec![],
            stages: vec![],
            cache_used: false,
        };
        let active = assemble(&prepared, output(), &AtomicBool::new(false)).unwrap();
        assert!(active
            .stages
            .iter()
            .any(|s| s.name == "layout_and_fields" && s.status == "complete"));
        let cancelled = assemble(&prepared, output(), &AtomicBool::new(true));
        assert!(
            matches!(cancelled, Err(Error::Invalid(message)) if message == "Verarbeitung abgebrochen.")
        );
    }

    #[cfg(target_os = "macos")]
    #[test]
    fn heic_import_retains_source_identity_and_does_not_rotate_twice() {
        let bytes = include_bytes!("../../../../ml/evaluation/fixtures/heic/orientation-6.heic");
        for filename in ["photo.heic", "photo.HEIC", "photo.heif", "photo.HEIF"] {
            let temp = tempfile::tempdir().unwrap();
            let prepared = prepare(
                bytes,
                filename,
                &uuid::Uuid::new_v4().to_string(),
                100,
                &PipelineConfig::default(),
                temp.path(),
            )
            .unwrap();
            assert_eq!(prepared.page.dimensions(), (64, 96));
            assert_eq!(prepared.original_to_page, geometry::IDENTITY);
            assert_eq!(prepared.document.source_hash, crate::hash(bytes));
            assert_eq!(prepared.document.filename, filename);
            assert_eq!(
                std::fs::read(temp.path().join("source.bin")).unwrap(),
                bytes
            );
            for artifact in ["original.png", "page.png"] {
                let retained = image::open(temp.path().join(artifact)).unwrap().into_rgb8();
                assert!(retained == prepared.page);
            }
            // Clockwise rotation: original bottom-left blue becomes top-left.
            let pixel = prepared.page.get_pixel(16, 24);
            assert!(pixel[2] > 220 && pixel[0] < 40 && pixel[1] < 40);
        }
    }
    #[test]
    fn quality_thumbnail_matches_previous_pixels_without_full_size_clone() {
        for (width, height) in [(200, 300), (513, 217), (1500, 1999), (17, 1)] {
            let page = RgbImage::from_fn(width, height, |x, y| {
                image::Rgb([(x % 251) as u8, (y % 241) as u8, ((x + y) % 233) as u8])
            });
            let expected = DynamicImage::ImageRgb8(page.clone())
                .thumbnail(512, 512)
                .to_luma8();
            let actual = quality_thumbnail(&page);
            assert_eq!(actual.dimensions(), expected.dimensions());
            assert!(
                actual == expected,
                "thumbnail pixels changed for {width}×{height}"
            );
        }
    }

    #[test]
    fn reused_image_artifacts_preserve_pixels_across_formats_and_corrections() {
        let rgb = RgbImage::from_fn(200, 300, |x, y| {
            image::Rgb([(x % 171) as u8, (y % 163) as u8, 100])
        });
        for rgba in [false, true] {
            for format in [image::ImageFormat::Png, image::ImageFormat::Jpeg] {
                if rgba && format == image::ImageFormat::Jpeg {
                    continue;
                }
                let image = DynamicImage::ImageRgb8(rgb.clone());
                let image = if rgba {
                    DynamicImage::ImageRgba8(image.into_rgba8())
                } else {
                    image
                };
                let mut bytes = Cursor::new(vec![]);
                image.write_to(&mut bytes, format).unwrap();
                let expected = image::load_from_memory(bytes.get_ref())
                    .unwrap()
                    .into_rgb8();
                for turns in 0..4 {
                    for mirrored in [false, true] {
                        let temp = tempfile::tempdir().unwrap();
                        let prepared = prepare(
                            bytes.get_ref(),
                            "synthetic",
                            &uuid::Uuid::new_v4().to_string(),
                            100,
                            &PipelineConfig {
                                quarter_turns: turns,
                                mirrored,
                                ..Default::default()
                            },
                            temp.path(),
                        )
                        .unwrap();
                        let mut expected_page = match turns {
                            1 => image::imageops::rotate90(&expected),
                            2 => image::imageops::rotate180(&expected),
                            3 => image::imageops::rotate270(&expected),
                            _ => expected.clone(),
                        };
                        if mirrored {
                            expected_page = image::imageops::flip_horizontal(&expected_page);
                        }
                        assert_eq!(prepared.page, expected_page);
                        assert_eq!(
                            image::open(temp.path().join("page.png"))
                                .unwrap()
                                .into_rgb8(),
                            expected_page
                        );
                        assert_eq!(
                            image::open(temp.path().join("original.png"))
                                .unwrap()
                                .into_rgb8(),
                            expected
                        );
                        assert_eq!(
                            std::fs::read(temp.path().join("source.bin")).unwrap(),
                            *bytes.get_ref()
                        );
                        assert_eq!(prepared.document.source_hash, crate::hash(bytes.get_ref()));
                    }
                }
            }
        }
    }

    #[test]
    fn page_crop_preserves_rotation_and_original_coordinate_mapping() {
        let image = DynamicImage::ImageRgb8(RgbImage::from_fn(200, 300, |x, y| {
            image::Rgb([x as u8, (y / 2) as u8, 100])
        }));
        let mut bytes = Cursor::new(vec![]);
        image.write_to(&mut bytes, image::ImageFormat::Png).unwrap();
        for turns in 0..4 {
            let temp = tempfile::tempdir().unwrap();
            let config = PipelineConfig {
                quarter_turns: turns,
                page_corners: Some(geometry::rect(0., 0., 200., 300.).try_into().unwrap()),
                ..Default::default()
            };
            let prepared = prepare(
                bytes.get_ref(),
                "synthetic.png",
                &uuid::Uuid::new_v4().to_string(),
                100,
                &config,
                temp.path(),
            )
            .unwrap();
            assert_eq!(
                prepared.page.dimensions(),
                if turns % 2 == 0 {
                    (200, 300)
                } else {
                    (300, 200)
                }
            );
            let point = Point { x: 40., y: 80. };
            let mapped = geometry::map(&prepared.original_to_page, &point);
            let expected = geometry::map(&geometry::rotation(turns, 200, 300), &point);
            assert!((mapped.x - expected.x).abs() < 1e-6 && (mapped.y - expected.y).abs() < 1e-6);
            let pixel = prepared.page.get_pixel(mapped.x as u32, mapped.y as u32);
            assert!((pixel[0] as i32 - 40).abs() <= 1 && (pixel[1] as i32 - 40).abs() <= 1);
            assert_eq!(
                std::fs::read(temp.path().join("source.bin")).unwrap(),
                *bytes.get_ref()
            );
        }
    }
}
