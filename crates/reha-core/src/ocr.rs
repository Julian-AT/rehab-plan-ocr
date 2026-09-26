//! Portable CPU inference; contains no Apple APIs and never performs network I/O.
use crate::{contracts::*, geometry, Error, Result};
use image::{imageops::FilterType, RgbImage};
use ort::{
    session::{RunOptions, Session},
    value::Tensor,
};
use std::{
    collections::VecDeque,
    path::Path,
    sync::atomic::{AtomicBool, Ordering},
    time::Instant,
};

fn err(e: impl std::fmt::Display) -> Error {
    Error::Invalid(format!("Local model inference failed: {e}"))
}
pub struct OnnxEngine {
    detector: Session,
    recognizer: Session,
    dictionary: Vec<String>,
    pub manifest: serde_json::Value,
    pub name: String,
}
impl OnnxEngine {
    pub fn load(directory: &Path) -> Result<Self> {
        let manifest: serde_json::Value =
            serde_json::from_slice(&std::fs::read(directory.join("manifest.json"))?)?;
        let files = manifest["files"]
            .as_array()
            .ok_or_else(|| err("Missing model hashes"))?;
        for item in files {
            let name = item["path"]
                .as_str()
                .ok_or_else(|| err("Missing model path"))?;
            if ![
                "det-inference.onnx",
                "rec-inference.onnx",
                "det-inference.yml",
                "rec-inference.yml",
            ]
            .contains(&name)
            {
                return Err(err("Unexpected model path"));
            }
            let digest = crate::hash(&std::fs::read(directory.join(name))?);
            if item["sha256"].as_str() != Some(&digest) {
                return Err(err("Model checksum mismatch"));
            }
        }
        let dict = std::fs::read(directory.join("dictionary.json"))?;
        if manifest["dictionary_sha256"].as_str() != Some(&crate::hash(&dict)) {
            return Err(err("Dictionary checksum mismatch"));
        }
        let load = |name: &str| {
            Session::builder()
                .map_err(err)?
                .with_intra_threads(2)
                .map_err(err)?
                .with_inter_threads(1)
                .map_err(err)?
                .commit_from_file(directory.join(name))
                .map_err(err)
        };
        Ok(Self {
            detector: load("det-inference.onnx")?,
            recognizer: load("rec-inference.onnx")?,
            dictionary: serde_json::from_slice(&dict)?,
            name: manifest["engine"].as_str().unwrap_or("PP-OCRv6").into(),
            manifest,
        })
    }
    pub fn recognize(
        &mut self,
        page: &RgbImage,
        config: &PipelineConfig,
        cancel: &AtomicBool,
        artifacts: &Path,
    ) -> Result<(Vec<Region>, Vec<Observation>, Vec<Stage>)> {
        self.recognize_until(page, config, cancel, artifacts, None)
    }
    pub fn recognize_until(
        &mut self,
        page: &RgbImage,
        config: &PipelineConfig,
        cancel: &AtomicBool,
        artifacts: &Path,
        deadline: Option<Instant>,
    ) -> Result<(Vec<Region>, Vec<Observation>, Vec<Stage>)> {
        let options = RunOptions::new().map_err(err)?;
        std::thread::scope(|scope| {
            let (done, finished) = std::sync::mpsc::channel::<()>();
            let options_ref = &options;
            scope.spawn(move || loop {
                if cancel.load(Ordering::Relaxed) || deadline.is_some_and(|d| Instant::now() >= d) {
                    let _ = options_ref.terminate();
                    break;
                }
                match finished.recv_timeout(std::time::Duration::from_millis(5)) {
                    Err(std::sync::mpsc::RecvTimeoutError::Timeout) => {}
                    _ => break,
                }
            });
            let result =
                self.recognize_with_options(page, config, cancel, artifacts, deadline, &options);
            let _ = done.send(());
            result
        })
    }
    fn recognize_with_options(
        &mut self,
        page: &RgbImage,
        config: &PipelineConfig,
        cancel: &AtomicBool,
        artifacts: &Path,
        deadline: Option<Instant>,
        options: &RunOptions,
    ) -> Result<(Vec<Region>, Vec<Observation>, Vec<Stage>)> {
        let start = Instant::now();
        if cancel.load(Ordering::Relaxed) || deadline.is_some_and(|d| Instant::now() >= d) {
            return Ok((
                vec![],
                vec![],
                vec![Stage {
                    name: "recognition".into(),
                    status: "budget_exhausted".into(),
                    duration_ms: 0,
                    detail: "No inference scheduled after deadline/cancellation.".into(),
                    artifacts: vec![],
                }],
            ));
        }
        let (w, h) = page.dimensions();
        let ratio = (config.detector_side as f64 / w.max(h) as f64).min(1.);
        let dw = ((w as f64 * ratio / 32.).round() as u32 * 32).max(32);
        let dh = ((h as f64 * ratio / 32.).round() as u32 * 32).max(32);
        let resized = image::imageops::resize(page, dw, dh, FilterType::Triangle);
        let mut input = vec![0f32; 3 * (dw * dh) as usize];
        let mean = [0.485, 0.456, 0.406];
        let std = [0.229, 0.224, 0.225];
        for (x, y, p) in resized.enumerate_pixels() {
            for c in 0..3 {
                input[c * (dw * dh) as usize + (y * dw + x) as usize] =
                    (p[2 - c] as f32 / 255. - mean[c]) / std[c];
            }
        }
        let tensor = Tensor::from_array(([1, 3, dh as usize, dw as usize], input)).map_err(err)?;
        let outputs = match self
            .detector
            .run_with_options(ort::inputs![tensor], options)
        {
            Ok(output) => output,
            Err(_)
                if cancel.load(Ordering::Relaxed)
                    || deadline.is_some_and(|d| Instant::now() >= d) =>
            {
                return Ok((
                    vec![],
                    vec![],
                    vec![Stage {
                        name: "detection".into(),
                        status: "interrupted".into(),
                        duration_ms: start.elapsed().as_millis() as u64,
                        detail: "Lokales Zeitbudget oder Abbruch erreicht.".into(),
                        artifacts: vec![],
                    }],
                ));
            }
            Err(e) => return Err(err(e)),
        };
        let (shape, scores) = outputs[0].try_extract_tensor::<f32>().map_err(err)?;
        if shape.len() != 4 || shape[0] != 1 || shape[1] != 1 {
            return Err(err("Unsupported detector output shape"));
        }
        let mw = shape[3] as usize;
        let mh = shape[2] as usize;
        let boxes = components(
            scores,
            mw,
            mh,
            config.detector_threshold,
            config.box_threshold,
        );
        let mut regions = vec![];
        for (index, (polygon, score)) in boxes.iter().enumerate() {
            regions.push(Region {
                id: format!("region-{index:04}"),
                polygon: polygon
                    .iter()
                    .map(|p| Point {
                        x: p.x.clamp(0., mw as f64) * w as f64 / mw as f64,
                        y: p.y.clamp(0., mh as f64) * h as f64 / mh as f64,
                    })
                    .collect(),
                frame: "page".into(),
                kind: if *score < config.box_threshold {
                    "uncertain_text"
                } else {
                    "text"
                }
                .into(),
                parent: Some("page".into()),
                children: vec![],
            });
        }
        if regions.len() > 1500 {
            return Err(err(
                "Too many regions; use a closer, clearer daily-plan photo",
            ));
        }
        let mut stages = vec![Stage {
            name: "detection".into(),
            status: "complete".into(),
            duration_ms: start.elapsed().as_millis() as u64,
            detail: format!(
                "CPU / {dw}×{dh} / {} regions. DB minimum-area polygons, polygon scores, unclip 1.4; perspective line crops.",
                regions.len()
            ),
            artifacts: vec![],
        }];
        drop(outputs);
        let start = Instant::now();
        let mut observations = vec![];
        let batch_limit = config.recognition_batch_size.clamp(1, 8);
        let mut scheduled: Vec<_> = regions.iter().collect();
        if batch_limit > 1 {
            scheduled.sort_by_key(|r| crop_width(&r.polygon));
        }
        let mut cursor = 0;
        while cursor < scheduled.len() {
            if cancel.load(Ordering::Relaxed) || deadline.is_some_and(|d| Instant::now() >= d) {
                break;
            }
            let width = crop_width(&scheduled[cursor].polygon);
            let count = scheduled[cursor..]
                .iter()
                .take(batch_limit)
                .take_while(|r| crop_width(&r.polygon) == width)
                .count();
            let batch = &scheduled[cursor..cursor + count];
            cursor += count;
            let mut inputs = Vec::new();
            let mut recognized = Vec::new();
            let mut padded = 0;
            for region in batch {
                if cancel.load(Ordering::Relaxed) || deadline.is_some_and(|d| Instant::now() >= d) {
                    break;
                }
                let crop = match geometry::rectify(page, &region.polygon) {
                    Ok(crop) => crop,
                    Err(_) => continue,
                };
                if config.detailed_debug {
                    crop.save(artifacts.join(format!("{}.png", region.id)))?;
                }
                let (rw, pw) = recognition_width(crop.width(), crop.height());
                if padded != 0 && padded != pw {
                    return Err(err("Inconsistent exact-width recognition batch"));
                }
                padded = pw;
                let resized = image::imageops::resize(&crop, rw, 48, FilterType::Triangle);
                let offset = inputs.len();
                inputs.resize(offset + 3 * (padded * 48) as usize, 0f32);
                for (x, y, p) in resized.enumerate_pixels() {
                    for c in 0..3 {
                        inputs[offset + c * (padded * 48) as usize + (y * padded + x) as usize] =
                            (p[2 - c] as f32 / 255. - 0.5) / 0.5;
                    }
                }
                recognized.push(*region);
            }
            if recognized.is_empty() {
                continue;
            }
            let tensor = Tensor::from_array(([recognized.len(), 3, 48, padded as usize], inputs))
                .map_err(err)?;
            let outputs = match self
                .recognizer
                .run_with_options(ort::inputs![tensor], options)
            {
                Ok(output) => output,
                Err(_)
                    if cancel.load(Ordering::Relaxed)
                        || deadline.is_some_and(|d| Instant::now() >= d) =>
                {
                    break
                }
                Err(e) => return Err(err(e)),
            };
            let (shape, data) = outputs[0].try_extract_tensor::<f32>().map_err(err)?;
            if shape.len() != 3
                || shape[0] as usize != recognized.len()
                || shape[1] < 1
                || shape[2] as usize != self.dictionary.len()
            {
                return Err(err(format!(
                    "Recognizer/dictionary mismatch: shape {:?}, dictionary {}",
                    shape,
                    self.dictionary.len()
                )));
            }
            for (region, scores) in recognized
                .iter()
                .zip(data.chunks_exact((shape[1] * shape[2]) as usize))
            {
                let (text, score) = ctc(scores, shape[2] as usize, &self.dictionary);
                observations.push(Observation {
                    id: format!("obs-{}", region.id),
                    text,
                    region_ids: vec![region.id.clone()],
                    engine: self.name.clone(),
                    score,
                    alternatives: vec![],
                });
            }
        }
        if batch_limit > 1 {
            let order: std::collections::HashMap<_, _> = regions
                .iter()
                .enumerate()
                .map(|(i, r)| (&r.id, i))
                .collect();
            observations
                .sort_by_key(|o| order.get(&o.region_ids[0]).copied().unwrap_or(usize::MAX));
        }
        stages.push(Stage{name:"recognition".into(),status:if observations.len() == regions.len() { "complete" } else { "partial" }.into(),duration_ms:start.elapsed().as_millis() as u64,detail:"CTC greedy decoding. Mean token scores are engine signals, not appointment-correctness probabilities. Alternatives unavailable.".into(),artifacts:if config.detailed_debug{regions.iter().map(|r|format!("{}.png",r.id)).collect()}else{vec![]}});
        Ok((regions, observations, stages))
    }
}
fn recognition_width(width: u32, height: u32) -> (u32, u32) {
    let resized = ((48. * width as f64 / height.max(1) as f64).ceil() as u32).clamp(8, 3200);
    (resized, resized.max(320).div_ceil(8) * 8)
}
fn crop_width(polygon: &[Point]) -> u32 {
    if polygon.len() != 4 {
        return 0;
    }
    let mut w = geometry::distance(&polygon[0], &polygon[1])
        .max(geometry::distance(&polygon[3], &polygon[2]))
        .ceil() as u32;
    let mut h = geometry::distance(&polygon[0], &polygon[3])
        .max(geometry::distance(&polygon[1], &polygon[2]))
        .ceil() as u32;
    if h as f64 / w.max(1) as f64 >= 1.5 {
        std::mem::swap(&mut w, &mut h);
    }
    recognition_width(w, h).1
}
pub fn check_cancel(cancel: &AtomicBool) -> Result<()> {
    if cancel.load(Ordering::Relaxed) {
        Err(Error::Invalid("Verarbeitung abgebrochen.".into()))
    } else {
        Ok(())
    }
}
fn ctc(data: &[f32], classes: usize, dictionary: &[String]) -> (String, Option<f32>) {
    let mut text = String::new();
    let mut prev = 0;
    let mut scores = vec![];
    for step in data.chunks_exact(classes) {
        let (index, score) = step
            .iter()
            .enumerate()
            .max_by(|a, b| a.1.total_cmp(b.1))
            .unwrap();
        if index != 0 && index != prev {
            text.push_str(&dictionary[index]);
            scores.push(*score);
        }
        prev = index;
    }
    let score = if scores.is_empty() {
        None
    } else {
        Some(scores.iter().sum::<f32>() / scores.len() as f32)
    };
    (text, score)
}
fn components(
    scores: &[f32],
    w: usize,
    h: usize,
    threshold: f32,
    box_threshold: f32,
) -> Vec<(Vec<Point>, f32)> {
    let mut visited = vec![false; w * h];
    let mut result = vec![];
    for seed in 0..w * h {
        if visited[seed] || scores[seed] < threshold {
            continue;
        }
        let mut q = VecDeque::from([seed]);
        visited[seed] = true;
        let (mut left, mut right, mut top, mut bottom) = (seed % w, seed % w, seed / w, seed / w);
        let mut points = vec![];
        let mut count = 0;
        while let Some(i) = q.pop_front() {
            let x = i % w;
            let y = i / w;
            left = left.min(x);
            right = right.max(x);
            top = top.min(y);
            bottom = bottom.max(y);
            points.push(imageproc::point::Point::new(x as i32, y as i32));
            count += 1;
            for ny in y.saturating_sub(1)..=(y + 1).min(h - 1) {
                for nx in x.saturating_sub(1)..=(x + 1).min(w - 1) {
                    let n = ny * w + nx;
                    if !visited[n] && scores[n] >= threshold {
                        visited[n] = true;
                        q.push_back(n);
                    }
                }
            }
        }
        if count >= 6 && right - left >= 3 && bottom - top >= 2 {
            let box_points = imageproc::geometry::min_area_rect(&points).map(|p| Point {
                x: p.x as f64,
                y: p.y as f64,
            });
            let width = geometry::distance(&box_points[0], &box_points[1]);
            let height = geometry::distance(&box_points[0], &box_points[3]);
            if width.min(height) < 3. {
                continue;
            }
            let mut total = 0.;
            let mut n = 0;
            let (l, t, r, b) = geometry::bounds(&box_points);
            for y in (t.floor().max(0.) as usize)..=(b.ceil() as usize).min(h - 1) {
                for x in (l.floor().max(0.) as usize)..=(r.ceil() as usize).min(w - 1) {
                    if geometry::inside(
                        &box_points,
                        &Point {
                            x: x as f64,
                            y: y as f64,
                        },
                    ) {
                        total += scores[y * w + x];
                        n += 1;
                    }
                }
            }
            let score = total / n.max(1) as f32;
            if score < box_threshold {
                continue;
            }
            // For a rectangle, the minimum-area box around a round polygon offset
            // expands each edge by the same area/perimeter distance as DB unclip.
            let pad = width * height * 1.4 / (2. * (width + height));
            let ux = (box_points[1].x - box_points[0].x) / width;
            let uy = (box_points[1].y - box_points[0].y) / width;
            let vx = (box_points[3].x - box_points[0].x) / height;
            let vy = (box_points[3].y - box_points[0].y) / height;
            let expanded: Vec<Point> = box_points
                .iter()
                .zip([(-1., -1.), (1., -1.), (1., 1.), (-1., 1.)])
                .map(|(p, (u, v))| Point {
                    x: p.x + pad * (u * ux + v * vx),
                    y: p.y + pad * (u * uy + v * vy),
                })
                .collect();
            result.push((expanded, score));
        }
    }
    result.sort_by(|(a, _), (b, _)| a[0].y.total_cmp(&b[0].y).then(a[0].x.total_cmp(&b[0].x)));
    result
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn scheduled_width_matches_rotated_and_perspective_crops() {
        let page = image::RgbImage::new(600, 600);
        for polygon in [
            geometry::rect(5., 5., 520., 31.),
            geometry::rect(10., 10., 23., 430.),
            vec![
                Point { x: 20., y: 20. },
                Point { x: 401., y: 40. },
                Point { x: 398., y: 67. },
                Point { x: 18., y: 49. },
            ],
        ] {
            let crop = geometry::rectify(&page, &polygon).unwrap();
            assert_eq!(
                crop_width(&polygon),
                recognition_width(crop.width(), crop.height()).1
            );
        }
    }
    #[test]
    fn ctc_blank_separates_repeated_letters() {
        let d = vec!["".into(), "A".into(), "B".into()];
        let (text, _) = ctc(
            &[0., 1., 0., 0., 1., 0., 1., 0., 0., 0., 1., 0., 0., 0., 1.],
            3,
            &d,
        );
        assert_eq!(text, "AAB");
    }
}
