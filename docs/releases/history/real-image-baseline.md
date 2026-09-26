> Historical record: technical findings retained from the archived development sequence. Project dates, build labels and source references have been normalized. This record is not a new test, delivery approval or signing attestation; unaltered evidence and original validity dates are held in the external private archive.

> Historical record. Commands, installed versions and acceptance claims below describe their original date only. The [current implementation ledger](../../development/implementation-plan.md) governs ongoing work. Retired media is recoverable from Git; see [the archive inventory](retired-assets.json).

# Real-image baseline — 2026-09-26

The user supplied real schedule photographs for local exploratory testing. This run measures the current implementation before any changes driven by these images. No recognition model, parser or threshold was tuned during the run. Images and OCR content remained local; only aggregate diagnostics are recorded here.

## Inputs and conversion

- `verify/`: 21 HEIC files, containing 20 distinct byte hashes, plus one existing PNG. The duplicate HEIC maps to the same output; the existing PNG was not included in the baseline.
- Converted files: `data/private/converted/verify-2026-09-26-s10/`, with 20 PNGs and a manifest linking every original to its derivative.
- All original HEIC hashes verified unchanged. Each PNG was reopened and its decoded pixels compared with the conversion buffer. EXIF/XMP removed; ICC profile retained where present.
- All 20 originals required orientation handling. Output dimensions: 16 at 4284 × 5712, four at 3024 × 4032. No resizing. All source images reported 8-bit depth, so no HDR bit-depth reduction was needed.
- Pillow 12.1.1, pillow-heif 1.7.0, libheif 1.23.3. PNG compression is lossless for the decoded RGB pixels; HEIC originals are preserved separately.

These are 20 distinct images, not 20 verified distinct treatment days. Multiple date headings appear in several images. No automatic day grouping or final holdout split was created from predictions.

## Measured results

PP-OCRv6 small, ONNX Runtime 1.22.0, portable CPU adapter, extraction version 2, default detector configuration. Each image used a fresh CLI process on the Apple M4 Pro Mac. The CLI was rebuilt from application commit `4fecb47` / documentation commit `f179aff`. Every inference process ran under `sandbox-exec` with `deny network*`; no Apple Vision or hosted recognition was used.

| Diagnostic                                   |   Count |
| -------------------------------------------- | ------: |
| Images processed successfully                | 20 / 20 |
| Extracted draft items                        |     193 |
| OCR observations                             |   1,289 |
| Images with unresolved treatment dates       |  9 / 20 |
| Draft items missing a date                   |     109 |
| Draft items missing a start time             |       0 |
| Draft items missing end time or duration     |      10 |
| Draft items with an empty title              |      17 |
| Draft items with a therapist field           |      88 |
| Therapist fields using multiple observations |      29 |
| Structured items still containing `*Neu`     |       0 |
| Images with blocking validation issues       | 14 / 20 |

Cold pipeline time, including model loading and intermediate artifact generation: median **1,748.5 ms**, nearest-rank p95 **2,355 ms**, maximum **2,374 ms**. Complete CLI process wall time: median **1,810 ms**, p95 **2,445 ms**, maximum **2,454 ms**. HEIC conversion is excluded. These are single-pass Mac measurements, not physical iPhone performance.

No precision, recall, critical-field accuracy or whole-schedule correctness score is available. Predictions have not been checked against reference annotations; missing fields are diagnostic failures, while populated fields may still be incorrect. The original acceptance targets remain unevaluated.

## Findings and next checks

Local analysis of raw OCR found multiple weekday headings in six of the nine images with unresolved dates. Five contain multiple distinct, syntactically valid weekday/date headings. The parser currently selects one treatment date for the entire image and treats multiple dates as conflicting; date assignment needs to be scoped to schedule sections. The other failures also require examination of OCR errors and row grouping. None should be resolved by guessing a date.

Empty titles and missing end/duration values need comparison against the source rows before deciding whether detection, recognition or field association is responsible. Successful `*Neu` removal and populated therapist fields do not establish that their surrounding text is correct. Unassigned OCR remains available for checking possible omissions.

Create verified references through the Dataset workflow before calculating accuracy. Keep pages and alternate captures of the same treatment day together. Record these inputs as exploratory data; do not claim a later evaluation on them is an unopened independent holdout.

## Private evidence and reproducibility

- `artifacts/private/verify-baseline-2026-09-26-s10/review.html`: local image/field comparison for all 20 documents.
- `report.json`: aggregate diagnostics and timing.
- `manifest.json`: source/conversion/model/binary/runner hashes, platform, configuration and per-document outcomes.
- `document-*/`: original display images, corrected pages, OCR geometry, observations, extracted fields, timings and process logs.
- `heading-diagnostics.json`: local heading-count analysis and full process timings, derived from OCR rather than verified reference text.

See [dataset commands](../../development/dataset.md#heic-conversion-and-exploratory-checks) to reproduce conversion and the baseline in new output directories. Five synthetic tooling tests cover original preservation, duplicate handling, output collisions, orientation/metadata, diagnostic multiplicity and HTML escaping. The local review report was checked without uploading its images or text.
