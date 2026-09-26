> Historical record: technical findings retained from the archived development sequence. Project dates, build labels and source references have been normalized. This record is not a new test, delivery approval or signing attestation; unaltered evidence and original validity dates are held in the external private archive.

# Private reference dataset

The 20 distinct original photos have been visually transcribed into **188 row
occurrences**. Alternate captures and revised plans remain separate references.
These are **unapproved drafts**, including proposed text polygons and error causes;
no verified clinical accuracy, trained checkpoint or independent final test exists.
Personal data and every content-bearing artifact remain in ignored private storage.

## Review and approval

Open **Einstellungen → Entwickleransicht öffnen → Dataset → Annotations &
evaluation → Foto gegen Referenz prüfen** in the native desktop app. The inventory
and references load without running OCR. Each original has a full-image overlay,
field enlargement with neighboring rows, editable field values and printed states.

1. Check logical page, capture series and every treatment day for all originals.
   Alternative captures, revised plans and overlapping days belong together.
2. Click **Bestätigte Seitengruppen einfrieren** after confirming those relationships
   on every photo. Transitive overlap forms reproducible groups in four development
   folds. This resets overall approvals while preserving field-review progress.
3. Compare every row with the original, including meals, continuations and notes.
   Correct field cells, individual text polygons and row blocks; add missing rows
   or text lines and remove false ones. The table boundary must exclude the patient
   header and unrelated background sheets. Initial polygons are suggestions.
4. Classify fields as legible, not printed, illegible, cropped or contradictory.
   Preserve original spelling and partial printed text. Never copy a missing name
   from a similar plan. Confirm each row, complete coverage and resolve questions.
5. Save progress at any time. **Referenz ausdrücklich für Training und Bewertung
   freigeben** is the separate final action for that photo. Later changes revoke it.

`data/private/labels/provisional/<source-hash>.json` remains the per-original path
for drafts and approved references. The filename alone never grants approval.
`data/private/visual-review.json` records the initial visual pass; old OCR seeds are
archived under `labels/ocr-seed-v1`. Calendar values and old OCR are comparison
material, never the source of the transcription.

## Contracts and isolation

Reference schema **2** records original HEIC and upright PNG hashes, logical page,
capture series, treatment days, table boundary, text polygons, appointment/field
links, field states and confirmations. `verified`, `reviewed_at`, `content_hash`
and `approval_hash` are controlled on save. Numeric hash normalization preserves
identical coordinates across Python/Rust/JSON serialization. Field text, geometry,
coverage and source relationships participate in the content hash.

Split schema **3** uses a transitive union of shared days, logical pages, capture
series and original/source hashes, then seed `reha-development-folds-v2`. Every
original and derivative inherits one group and fold. Fewer than four independent
groups blocks splitting. Changed frozen relationships block evaluation/export;
archive the experiment and create a new dataset version rather than reshuffling.
The old `dataset.py freeze` day-only interface is disabled. These previously
inspected photos are all development data; `benchmark.py --final` rejects them.
New, untouched plans are needed for independent final acceptance.

The core CLI validates a reference with `reference-check FILE [--approved]` and
prints its content hash. `reference-groups DATASET_ROOT` previews confirmed groups
without changing files. No command can turn an OCR seed into verified truth.

## Variants and exports

After source relationships are confirmed, the desktop action or the CLI can freeze
and describe variants:

```sh
uv run scripts/reference-data.py --root data/private freeze
uv run scripts/reference-data.py --root data/private recipes
```

There are exactly 24 recipes per original: unchanged, three quarter turns, four
small skews, two perspectives, two shadows, brightness/contrast, mild blur,
compression/resolution, horizontal/vertical reflection, a cut column and covered
characters. Pixels are generated on request in a size-bounded cache, default
256 MiB. Geometry transforms accompany all row, cell and text polygons. Data
outside the confirmed table boundary are masked before any variant is generated.

Approved references are required for export and raster materialization:

```sh
uv run scripts/reference-data.py --root data/private export artifacts/private/fold-0 --fold 0
uv run scripts/reference-data.py --root data/private materialize RECIPE_ID
uv run scripts/reference-data.py --root data/private materialize-line RECIPE_ID LINE_ID
```

Exports contain separate `detection.jsonl`, `recognition.jsonl`,
`table-assignment.jsonl` and `orientation.jsonl` adapters plus provenance, fold,
recipe/reference/file hashes and transforms. A consumer requests the recipe ID
through the materializer; text lines are perspective-rectified from the variant.
Detection labels use `###` for ignored unreadable text. Recognition excludes
cropped/occluded labels and mirrored writing. Table labels remove full values when
the variant destroys their evidence. Mirrored images support orientation tests
only. Maximum label lengths are exported, never silently truncated.

`uv run scripts/synthetic-plans.py NEW_OUTPUT_DIRECTORY` generates 200 reproducible
invented tables, images and exact text polygons. A generated set is available in
`data/private/synthetic-200`. Names, rooms and treatments are sampled independently;
examples include similar room numbers, long names/degrees, two therapists, blank
cells, overlapping times and identical events. Font/generator/image/label hashes
and seeds are recorded. Synthetics are training/robustness examples, not additional
real-world validation cases. Do not place them in the held-out development fold.

## Local evaluation and subsequent training

After approving all references and freezing groups, compare the unchanged small
and medium models with the same dataset and configuration choices:

```sh
cargo build --release -p reha-core --features onnx-download
python3 scripts/benchmark.py --models models/private/small --config data/private/config-small.json
python3 scripts/benchmark.py --models models/private/medium --config data/private/config-medium.json
```

The runner evaluates original photos separately, aggregates raw counts by group
and fold, and records config/model/binary/source/reference hashes. Variants cannot
inflate original-photo accuracy. Matching uses unique geometric assignment, never
room or therapist equality. Reports separate printed and empty-field denominators,
character errors, row/column swaps, missing/invented rows, date/time accuracy,
correct whole photos, review burden and automatically correct appointments.
Correction time is not claimed to have been measured.

Fine-tuning is deliberately **not started before joint reference approval**. First
inspect errors on correct text crops. If repeated recognition errors remain, use
official PP-OCRv6 small training weights and its dictionary, preserve full labels,
and compare frozen-backbone and full low-learning-rate recognition runs. The shared
budget is eight hours, at most 20 epochs per run and early stop after three
non-improving evaluations. Run PaddlePaddle on CPU on this Mac. Record the exact
configuration, elapsed time, data hashes and every checkpoint. Detection training
requires evidence that remaining failures originate in detection. Training
execution/configuration and ONNX parity measurement belong to this post-approval
stage; no untested training runner is presented as validated here.

An adapted model may replace the unchanged pipeline only after group-wide gains,
no additional critical date/time or missing/invented appointment errors, and
matching outputs after ONNX export. Independent acceptance still needs new plans.
The small pretrained model remains active until these conditions are demonstrated.

Implementation references: [PaddleOCR DB postprocessing](https://github.com/PaddlePaddle/PaddleOCR/blob/main/ppocr/postprocess/db_postprocess.py),
[official small recognition training configuration](https://github.com/PaddlePaddle/PaddleOCR/blob/main/configs/rec/PP-OCRv6/PP-OCRv6_small_rec.yml),
[PaddlePaddle macOS support](https://www.paddlepaddle.org.cn/documentation/docs/en/install/pip/macos-pip_en.html).

## Originals and existing tooling

`verify/` retains the supplied originals, including one byte-identical duplicate.
Upright PNGs, hashes and conversion records are in
`data/private/converted/verify-2026-09-26-s10/`; `data/private/raw/` is the review input.
Research data are separate from the app's capture archive, which now retains sources until deletion by default.
`convert-images.py` preserves pixel resolution and source hashes while stripping
EXIF/XMP from derived PNGs. `check-images.py` creates diagnostic reports and a local
image/data HTML view; on macOS its OCR subprocesses have network access denied.
These diagnostic reports are explicitly unverified. Never commit private images,
labels, screenshots, exported text or calendar values.

## Laßnitzhöhe evaluation gate

Target 40 real plan photos and approximately 10 non-plan/unusable inputs. The
existing 20 are development data only; none of their references is currently
approved. New captures, overlapping days and revisions must remain grouped. No
threshold tuning, activity rules, dual-reader acceptance, model replacement or
fine-tuning is enabled for this release without the approved evaluation set.
The training notes above are historical research directions, outside this release.

`uv run scripts/reference-data.py --root data/private readiness` reports counts
without publishing patient data or granting approval. References may explicitly
label `input_class` as `rehabilitation_plan`, `non_plan` or `unusable`; the optional
field preserves old reference hashes when absent. Non-plan references must have
zero appointments. Empty negative references still require source geometry,
relationship approval and full coverage confirmation. Use the full image as the
source region when there is no appointment table. Editing the class revokes
approval, just like editing any other label.

`benchmark.py --freeze-baseline NEW_PRIVATE_DIRECTORY --record-baseline-runs`
(with the normal model, config and binary arguments) preserves the portable binary,
configuration, model manifest and extraction-source hashes before accuracy work.
These raw runs and times do not constitute accuracy measurements. The frozen
20-photo run is under `artifacts/private/lassnitzhoehe-portable-baseline`.
Use `--evaluator` to score a frozen extraction binary with an evaluator supporting
new annotation fields; both binary hashes are recorded. Approved benchmarks report
raw precision/recall counts, plan-only whole-plan denominators, negative cases and
review burden separately. Unapproved references and the previously explored set
still cannot pass `--final` acceptance.

Keep 99% critical-field correctness, 99% appointment precision/recall, 90% whole-plan
correctness and zero observed critical false acceptances visible as targets, not
measured claims. Final acceptance and enabling automatic review still require new,
human-approved groups and a frozen policy. Forty plans cannot establish broad
reliability; report uncertainty alongside the observed results.
