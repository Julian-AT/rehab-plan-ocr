# Private reference dataset

Original plan photos, transcriptions, draft polygons and error annotations belong
in private storage. A draft is unapproved until each required human review passes.
Synthetic smoke artifacts do not qualify a clinical model or an independent final
test. See the [retained findings](../../ml/experiments/findings.md) for historical
scope and the [verification record](verification.md) for current source checks.

New collections follow the [collection guide](../product/research/collection-guide.md)
and its consent draft. `make intake` copies a checked incoming batch without
changing existing originals, references or group assignments. Intake never grants
annotation approval, train/validation assignment or privacy-mask approval.

The historical `dataset.py relocate` command now makes verified copies and never
removes source files. Its legacy name remains for compatibility. Existing target
copies and `inventory.json` stay unchanged; a separate immutable
`copy-receipt.json` records the copied hashes and zero source deletions. A changed
source or conflicting destination stops verification without deleting either file.

## Review and approval

Use the [local reference CLI](reference-cli.md). The former desktop lab is removed.
`lab list`, `lab get` and `lab image` expose the stored draft and original without
running OCR. Inspect the original and field crops locally before confirming labels.
The existing 20 originals remain development data and have zero approved references.

1. Check logical page, capture series and every treatment day for all originals.
   Alternative captures, revised plans and overlapping days belong together.
2. Run `reha lab freeze-groups ROOT` after confirming those relationships
   on every photo. Transitive overlap forms reproducible groups in four development
   folds. This resets overall approvals while preserving field-review progress.
3. Compare every row with the original, including meals, continuations and notes.
   Correct field cells, individual text polygons and row blocks; add missing rows
   or text lines and remove false ones. The table boundary must exclude the patient
   header and unrelated background sheets. Initial polygons are suggestions.
4. Classify fields as legible, not printed, illegible, cropped or contradictory.
   Preserve original spelling and partial printed text. Never copy a missing name
   from a similar plan. Confirm each row, complete coverage and resolve questions.
5. Save progress with `lab save`; confirm checked rows with `lab confirm-row` and
   complete coverage with `lab confirm-coverage`. `lab approve` is a separate,
   explicit human-review action. Later changes revoke the overall approval.

`.local/datasets/private/labels/provisional/<source-hash>.json` remains the per-original path
for drafts and approved references. The filename alone never grants approval.
`.local/datasets/private/visual-review.json` records the initial visual pass; old OCR seeds are
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

After source relationships are confirmed, the CLI can freeze
and describe variants:

```sh
.tools/bin/uv run --locked python ml/data/annotation/reference-data.py --root .local/datasets/private freeze
.tools/bin/uv run --locked python ml/data/annotation/reference-data.py --root .local/datasets/private recipes
```

There are exactly 40 recipes per original, including rotations, skews,
perspectives, shadows, brightness/contrast, blur, compression/resolution,
reflections, cropped or covered text, glare, noise and combined degradations.
Pixels are generated on request in a size-bounded cache, default
256 MiB. Geometry transforms accompany all row, cell and text polygons. Data
outside the confirmed table boundary are masked before any variant is generated.

Approved references, separately checked full text crops and an independent
privacy/use review are distinct gates. Field approval does not approve a crop;
neither approves the use or disclosure of an identity. Before export, prepare an
unapproved privacy-review draft without changing the references:

```sh
make reference-privacy-draft DATASET=.local/datasets/private
```

The private `privacy-review.json` is keyed by the original's source hash. For each
source, a human reviewer checks the complete table and header against the actual
image, then records:

- `table_privacy_reviewed: true` only after checking that no patient or unrelated
  person's identity remains outside the declared masks. Empty masks require the
  same explicit review; automatic identity detection is not claimed.
- `redactions` as `{ "reason": "patient_identity", "rect": [x0, y0, x1, y1] }`
  in original pixels. `unrelated_identity` is the other permitted reason. Masks
  include a two-pixel margin and are applied before resampling or augmentation.
- `authorization.intake_manifest`, relative to the dataset root or an absolute
  private path, its `intake_sha256`, and the exact `entry_id` from `make intake`.
  The verified copied original must match `original_hash`; both entry and active
  consent must include `ocr_training`, with an unexpired retention date.

After this human review, the explicit command records an opaque reviewer ID,
timestamp and content hash:

```sh
make reference-privacy-approve DATASET=.local/datasets/private SOURCE_SHA256=SOURCE_HASH REVIEWER=REVIEWER_ID
```

The command refuses an untouched draft. It does not approve references, crops,
consent, or group assignments. The intake receipt is the current authorization
record: the operator must record withdrawal or changed permitted uses there.
Changed receipts invalidate the old privacy approval; expired or withdrawn
consent blocks new exports. Any shared intake relationship must remain inside
one existing frozen source group, even when two different groups happen to have
the same fold. Incorrect grouping must be reviewed as a new dataset version.

References and originals remain unchanged. Export-only copies remove complete
text targets for every field touched by a privacy mask, including other lines of
the same field. Masked lines cannot become recognition targets. Training exports
retain hashes of the privacy and consent evidence, not consent documents, paths,
reviewer IDs, free-form review diagnostics or identity text. A changed reference,
mask or authorization requires a new review and export; cache identities include
the privacy review.

Then export and materialize the reviewed data:

```sh
.tools/bin/uv run --locked python ml/data/annotation/reference-data.py --root .local/datasets/private export .local/datasets/exports/fold-0 --fold 0
.tools/bin/uv run --locked python ml/data/annotation/reference-data.py --root .local/datasets/private materialize RECIPE_ID
.tools/bin/uv run --locked python ml/data/annotation/reference-data.py --root .local/datasets/private materialize-line RECIPE_ID LINE_ID
```

Exports contain separate `detection.jsonl`, `recognition.jsonl`,
`table-assignment.jsonl` and `orientation.jsonl` adapters plus provenance, fold,
recipe/reference/file hashes and transforms. A consumer requests the recipe ID
through the materializer; text lines are perspective-rectified from the variant.
Detection labels use `###` for ignored unreadable text. Recognition excludes
cropped/occluded labels and mirrored writing. Table labels remove full values when
the variant destroys their evidence. Mirrored images support orientation tests
only. Maximum label lengths are exported, never silently truncated.

The exact former reference exporter is retained as
`ml/data/annotation/compat/reference-data-v2.py.source` solely for verified
historical synthetic training provenance. It is not a current entry point for
real-data exports and does not grant a privacy or consent exemption.

`.tools/bin/uv run --locked python ml/data/synthesis/synthetic-plans.py NEW_OUTPUT_DIRECTORY` generates 200 reproducible
invented tables, images and exact text polygons. A generated set is available in
`.local/datasets/private/synthetic-200`. Names, rooms and treatments are sampled independently;
examples include similar room numbers, long names/degrees, two therapists, blank
cells, overlapping times and identical events. Font/generator/image/label hashes
and seeds are recorded. Synthetics are training/robustness examples, not additional
real-world validation cases. Do not place them in the held-out development fold.

## Local evaluation and subsequent training

After approving all references and freezing groups, compare the unchanged small
and medium models with the same dataset and configuration choices:

```sh
cargo build --release -p reha-cli --features onnx-download
python3 ml/evaluation/recognition/benchmark.py --models .local/models/runtime/small --config .local/datasets/private/config-small.json
python3 ml/evaluation/recognition/benchmark.py --models .local/models/runtime/medium --config .local/datasets/private/config-medium.json
```

The runner evaluates original photos separately, aggregates raw counts by group
and fold, and records config/model/binary/source/reference hashes. Variants cannot
inflate original-photo accuracy. Matching uses unique geometric assignment, never
room or therapist equality. Reports separate printed and empty-field denominators,
character errors, row/column swaps, missing/invented rows, date/time accuracy,
correct whole photos, review burden and automatically correct appointments.
Correction time is not claimed to have been measured.

Real-photo training and accuracy comparisons require approved references and
frozen source groups. Synthetic compatibility runs do not grant those approvals.
The matching PP-OCRv6 Small checkpoint has already completed loading, a short
training run, export and 24/24 Paddle/ONNX comparisons; the artifact remains
experimental. See the [recorded smoke experiment](../../ml/experiments/findings.md).

The [adaptation trainer](../../ml/training/ocr/README.md) now supports frozen-backbone
and lower-rate full fine-tuning, the exact dictionary, label-derived sequence
lengths, atomic optimizer checkpoints and validation stopping. A forced mid-epoch
interruption reproduced the uninterrupted tensors exactly. The former eight-hour
cap is removed. The earlier small smoke comparison passes export parity for its
frozen candidate; its full-adaptation candidate fails two numerical cases.
Both later [v3 field-coverage exports](../../ml/experiments/findings.md)
fail their numerical gate. The separate [native-input crop comparison](../../ml/experiments/findings.md)
does not change those failures or qualify an app model.
Real-photo adaptation, critical-field/correction evaluation and device
parity remain open. Detection training stays conditional on measured errors.

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
`.local/datasets/private/converted/verify-2026-09-26-s10/`; `.local/datasets/private/raw/` is the review input.
Research data are separate from the app's capture archive, which gives new users 30-day retention for completed sources, while preserving
existing preferences and unfinished reviews.
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
Synthetic training/export smoke runs are separate from these real-photo gates.

`.tools/bin/uv run --locked python ml/data/annotation/reference-data.py --root .local/datasets/private readiness` reports counts
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
20-photo run is under `.local/runs/legacy/private/lassnitzhoehe-portable-baseline`.
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
