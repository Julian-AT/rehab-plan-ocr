> Historical record: technical findings retained from the archived development sequence. Project dates, build labels and source references have been normalized. This record is not a new test, delivery approval or signing attestation; unaltered evidence and original validity dates are held in the external private archive.

# Private dataset and local experiments

No clinic images were present at implementation start. No clinical images have been moved or annotated, and no clinical accuracy result exists. The committed `synthetic-day.png` is drawn from invented content by `scripts/make-synthetic.py`; it contains eight timed rows, two identical treatments and one intentionally absent end time.

## Inventory and relocation

Supply the exact image directory. Run `python3 scripts/dataset.py inventory /absolute/image/directory`, inspect ignored `data/private/inventory.json`, then `python3 scripts/dataset.py relocate`. Only the inventoried JPEG/PNG/HEIC/HEIF images move. The script preserves names and bytes, checks all sources before starting, verifies each destination before removing its original, and resumes after interruption. Duplicate filenames in separate directories require disambiguating the input before relocation. Keep unrelated files untouched.

Do not place personal data in committed tests, documentation, screenshots or Git issues. `data/private/`, `artifacts/private/` and `models/private/` are ignored. Research originals and labels are deliberately retained for development; the app's separate 30-day rule does not erase them.

## Day, page and capture identities

Before tuning, identify 20 distinct treatment days. Multiple pages and alternate photographs of a day stay together. A **capture** is one complete set of page photographs. Alternate photographs are separate capture scenarios, never extra appointments:

```json
{
  "2026-09-26": {
    "captures": [
      {
        "id": "first-photo",
        "pages": { "page-1": "SHA256_A", "page-2": "SHA256_B" }
      },
      {
        "id": "second-photo",
        "pages": { "page-1": "SHA256_C", "page-2": "SHA256_B" }
      }
    ]
  }
}
```

Save the full 20-day mapping privately. `python3 scripts/dataset.py freeze data/private/grouping.json` validates hash ownership and complete page sets, then freezes four holdout days and 16 development days in four grouped folds. Split v2 records the seed, grouping hash and capture structure. The command refuses to overwrite an existing split. Crops and augmentations must inherit their source day; they are never additional evaluation days.

## Reference annotations

In the native desktop app, import a plan, open Labor, and create a provisional reference from the draft. Correct every printed item, including meals/breaks, titles, times, rooms and notes. Inspect the photograph and field evidence. Add missing items, remove false detections and resolve questions. Check the verification box only after comparing with the paper. Model output alone is never verified ground truth.

Canonical labels live at `data/private/labels/<day-id>.json`. A reference has `schema_version: 1`, `day_id`, **all** original `document_hashes` for that day, `verified`, `reviewed_at`, frozen `split`, `appointments` (the shared draft contract including provenance) and `uncertainty_notes`. For multi-page days, combine the verified appointment lists once per logical page and include all alternate source hashes. Reference inclusion toggles do not remove items from evaluation: every printed item counts. Missing facts in the paper must remain missing and be explained, not guessed.

## Reproducible batch comparison

1. Download a public pinned candidate: `uv run scripts/fetch-models.py --tier small` (or `tiny`, `medium`). Network access here downloads public model files only.
2. Build the local CLI: `cargo build --release -p reha-core --features onnx-download`.
3. Export an experiment configuration from app Settings. Keep its `engine` consistent with the model tier.
4. Run `python3 scripts/benchmark.py --models models/private/small --config data/private/config-small.json`.
5. Open the resulting `artifacts/private/benchmark-*/report.json` in Labor. Compare run JSON files side by side. Retain manifests and exact config/model/binary hashes.

Each complete capture is compared against its day's verified reference. Reports distinguish distinct days from correlated alternate captures, include raw counts, and do not pretend correction time or peak memory was measured. The report's p95 is from the recorded machine, not from a physical iPhone. Cold CLI launches include model loading; app runs additionally record session reuse.

After development-only selection, save a private JSON with `config_sha256` and `model_manifest_sha256`. Run the same command with `--final --selection <file>` once. A marker is created before inference so interruptions cannot silently reopen the holdout. If holdout errors influence tuning, record contamination and obtain fresh independent days. Never erase that marker to claim a new independent result.

No training is currently justified by verified data. Fine-tune only the component responsible for repeatable development errors, retain local checkpoints/early-stopping evidence, and evaluate independent days before selecting an adaptation.
