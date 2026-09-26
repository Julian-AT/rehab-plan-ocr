use crate::{contracts::*, geometry, Error, Result};
use image::{DynamicImage, ImageReader, RgbImage};
use std::{
    io::Cursor,
    path::Path,
    sync::atomic::{AtomicBool, Ordering},
    time::Instant,
};

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
    if bytes.len() > 40 * 1024 * 1024 {
        return Err(Error::Invalid("Foto größer als 40 MB.".into()));
    }
    if !(320..=2560).contains(&config.detector_side)
        || !config.detector_threshold.is_finite()
        || !(0.05..=0.95).contains(&config.detector_threshold)
        || !config.box_threshold.is_finite()
        || !(0.05..=0.99).contains(&config.box_threshold)
    {
        return Err(Error::Invalid("Ungültige Erkennungskonfiguration.".into()));
    }
    let start = Instant::now();
    let reader = ImageReader::new(Cursor::new(bytes)).with_guessed_format()?;
    let (w, h) = reader.into_dimensions()?;
    if w == 0 || h == 0 || w as u64 * h as u64 > 50_000_000 {
        return Err(Error::Invalid(
            "Bildabmessungen nicht unterstützt (maximal 50 Megapixel).".into(),
        ));
    }
    let mut decoded = image::load_from_memory(bytes)?;
    let orientation = exif::Reader::new()
        .read_from_container(&mut Cursor::new(bytes))
        .ok()
        .and_then(|e| {
            e.get_field(exif::Tag::Orientation, exif::In::PRIMARY)
                .and_then(|f| f.value.get_uint(0))
        })
        .unwrap_or(1);
    decoded = match orientation {
        2 => decoded.fliph(),
        3 => decoded.rotate180(),
        4 => decoded.flipv(),
        5 => decoded.rotate90().fliph(),
        6 => decoded.rotate90(),
        7 => decoded.rotate90().flipv(),
        8 => decoded.rotate270(),
        _ => decoded,
    };
    // Original display frame is the EXIF-upright photograph; bytes are preserved separately.
    let ow = decoded.width();
    let oh = decoded.height();
    std::fs::create_dir_all(dir)?;
    std::fs::write(dir.join("source.bin"), bytes)?;
    decoded.save(dir.join("original.png"))?;
    let decode_ms = start.elapsed().as_millis() as u64;
    let correction_started = Instant::now();
    let mut transform = geometry::rotation(config.quarter_turns, ow, oh);
    let mut page = match config.quarter_turns % 4 {
        1 => decoded.rotate90(),
        2 => decoded.rotate180(),
        3 => decoded.rotate270(),
        _ => decoded,
    }
    .to_rgb8();
    let mut detail =
        "EXIF orientation applied; original bytes retained. No automatic page-boundary claim."
            .to_string();
    if let Some(corners) = &config.page_corners {
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
        corners.rotate_right((config.quarter_turns % 4) as usize);
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
        detail="User-specified page corners; perspective corrected. Corner order: top-left, top-right, bottom-right, bottom-left.".into();
    }
    page.save(dir.join("page.png"))?;
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
    let small = DynamicImage::ImageRgb8(page.clone())
        .thumbnail(512, 512)
        .to_luma8();
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
    let stages=vec![Stage{name:"decode".into(),status:"complete".into(),duration_ms:decode_ms,detail:format!("{w}×{h}; EXIF {orientation}; upright {ow}×{oh}"),artifacts:vec!["original.png".into()]},Stage{name:"preprocessing".into(),status:"complete".into(),duration_ms:correction_ms,detail,artifacts:vec!["page.png".into()]},Stage{name:"quality".into(),status:"complete".into(),duration_ms:quality_started.elapsed().as_millis() as u64,detail:format!("Resolution and contrast heuristic (variance {variance:.1}); blur, shadow and handwritten-change classifiers unavailable."),artifacts:vec![]}];
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

pub struct RecognitionOutput {
    pub engine: String,
    pub manifest: serde_json::Value,
    pub regions: Vec<Region>,
    pub observations: Vec<Observation>,
    pub stages: Vec<Stage>,
    pub cache_used: bool,
}
pub fn assemble(
    prepared: Prepared,
    output: RecognitionOutput,
    cancel: &AtomicBool,
) -> Result<PipelineRun> {
    let RecognitionOutput {
        engine,
        manifest,
        mut regions,
        observations,
        stages,
        cache_used,
    } = output;
    let config = prepared.config.clone();
    if cancel.load(Ordering::Relaxed) {
        return Err(Error::Invalid("Verarbeitung abgebrochen.".into()));
    }
    let start = Instant::now();
    let (appointments, mut issues, unassigned) =
        crate::parser::extract(&prepared.document.id, &observations, &regions);
    crate::parser::add_layout(
        &observations,
        &mut regions,
        prepared.page.width(),
        prepared.page.height(),
    );
    issues.extend(prepared.issues);
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
    let mut all_stages = prepared.stages;
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
    all_stages.push(Stage {
        name: "selective_reread".into(),
        status: "unavailable".into(),
        duration_ms: 0,
        detail: "No retry adapter configured; difficult fields require review.".into(),
        artifacts: vec![],
    });
    let total_ms = all_stages.iter().map(|s| s.duration_ms).sum();
    Ok(PipelineRun {
        schema_version: SCHEMA_VERSION,
        extraction_version: crate::parser::EXTRACTION_VERSION,
        id: uuid::Uuid::new_v4().to_string(),
        document: prepared.document,
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
}
#[cfg(feature = "onnx")]
pub fn run(
    engine: &mut crate::ocr::OnnxEngine,
    input: ScanInput<'_>,
    cancel: &AtomicBool,
    cache_used: bool,
) -> Result<PipelineRun> {
    let ScanInput {
        bytes,
        filename,
        id,
        now,
        config,
        dir,
    } = input;
    let start = Instant::now();
    crate::ocr::check_cancel(cancel)?;
    let prepared = prepare(bytes, filename, id, now, &config, dir)?;
    let (regions, observations, stages) = engine.recognize(&prepared.page, &config, cancel, dir)?;
    let mut run = assemble(
        prepared,
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
    run.total_ms = start.elapsed().as_millis() as u64;
    Ok(run)
}

#[cfg(test)]
mod tests {
    use super::*;
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
