//! Portable CPU inference; contains no Apple APIs and never performs network I/O.
use crate::{contracts::*, geometry, Error, Result};
use image::{imageops::FilterType, RgbImage};
use ort::{session::Session, value::Tensor};
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
        let start = Instant::now();
        check_cancel(cancel)?;
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
        let outputs = self.detector.run(ort::inputs![tensor]).map_err(err)?;
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
        for (index, (x, y, r, b, score)) in boxes.iter().enumerate() {
            let pad = ((*r - *x).min(*b - *y) as f64 * 0.7).max(2.);
            let left = (*x as f64 - pad).max(0.) * w as f64 / mw as f64;
            let top = (*y as f64 - pad).max(0.) * h as f64 / mh as f64;
            let right = (*r as f64 + pad).min(mw as f64) * w as f64 / mw as f64;
            let bottom = (*b as f64 + pad).min(mh as f64) * h as f64 / mh as f64;
            regions.push(Region {
                id: format!("region-{index:04}"),
                polygon: geometry::rect(left, top, right - left, bottom - top),
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
                "CPU / {dw}×{dh} / {} regions. DB connected components; axis-aligned crop boxes.",
                regions.len()
            ),
            artifacts: vec![],
        }];
        drop(outputs);
        let start = Instant::now();
        let mut observations = vec![];
        for region in &regions {
            check_cancel(cancel)?;
            let (x, y, r, b) = geometry::bounds(&region.polygon);
            let x = x.floor().max(0.) as u32;
            let y = y.floor().max(0.) as u32;
            let cw = (r.ceil() as u32).min(w).saturating_sub(x).max(1);
            let ch = (b.ceil() as u32).min(h).saturating_sub(y).max(1);
            let crop = image::imageops::crop_imm(page, x, y, cw, ch).to_image();
            if config.detailed_debug {
                crop.save(artifacts.join(format!("{}.png", region.id)))?;
            }
            let rw = ((48. * cw as f64 / ch as f64).ceil() as u32).clamp(8, 3200);
            let padded = rw.max(320).div_ceil(8) * 8;
            let resized = image::imageops::resize(&crop, rw, 48, FilterType::Triangle);
            let mut input = vec![0f32; 3 * (padded * 48) as usize];
            for (x, y, p) in resized.enumerate_pixels() {
                for c in 0..3 {
                    input[c * (padded * 48) as usize + (y * padded + x) as usize] =
                        (p[2 - c] as f32 / 255. - 0.5) / 0.5;
                }
            }
            let tensor = Tensor::from_array(([1, 3, 48, padded as usize], input)).map_err(err)?;
            let outputs = self.recognizer.run(ort::inputs![tensor]).map_err(err)?;
            let (shape, data) = outputs[0].try_extract_tensor::<f32>().map_err(err)?;
            if shape.len() != 3 || shape[0] != 1 || shape[2] as usize != self.dictionary.len() {
                return Err(err(format!(
                    "Recognizer/dictionary mismatch: shape {:?}, dictionary {}",
                    shape,
                    self.dictionary.len()
                )));
            }
            let (text, score) = ctc(data, shape[2] as usize, &self.dictionary);
            observations.push(Observation {
                id: format!("obs-{}", region.id),
                text,
                region_ids: vec![region.id.clone()],
                engine: self.name.clone(),
                score,
                alternatives: vec![],
            });
        }
        stages.push(Stage{name:"recognition".into(),status:"complete".into(),duration_ms:start.elapsed().as_millis() as u64,detail:"CTC greedy decoding. Mean token scores are engine signals, not appointment-correctness probabilities. Alternatives unavailable.".into(),artifacts:if config.detailed_debug{regions.iter().map(|r|format!("{}.png",r.id)).collect()}else{vec![]}});
        Ok((regions, observations, stages))
    }
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
    _box_threshold: f32,
) -> Vec<(usize, usize, usize, usize, f32)> {
    let mut visited = vec![false; w * h];
    let mut result = vec![];
    for seed in 0..w * h {
        if visited[seed] || scores[seed] < threshold {
            continue;
        }
        let mut q = VecDeque::from([seed]);
        visited[seed] = true;
        let (mut left, mut right, mut top, mut bottom) = (seed % w, seed % w, seed / w, seed / w);
        let mut sum = 0.;
        let mut count = 0;
        while let Some(i) = q.pop_front() {
            let x = i % w;
            let y = i / w;
            left = left.min(x);
            right = right.max(x);
            top = top.min(y);
            bottom = bottom.max(y);
            sum += scores[i];
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
            result.push((left, top, right + 1, bottom + 1, sum / count as f32));
        }
    }
    result.sort_by_key(|(x, y, _, _, _)| (*y, *x));
    result
}
#[cfg(test)]
mod tests {
    use super::*;
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
