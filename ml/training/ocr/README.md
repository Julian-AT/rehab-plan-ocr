# Local PP-OCRv6 Small adaptation

The registry pins the official trainable checkpoint, source revision and exact
shipping CTC dictionary. Model development stays outside app dependencies. Restore
once online; preparation, adaptation, export and parity then use local files.

```sh
make restore-ocr-assets
make prepare-ocr-smoke DATASET=.local/datasets/ocr-example
make train-ocr DATASET=.local/datasets/ocr-example RUN=.local/runs/ocr-example-frozen
make resume-ocr RUN=.local/runs/ocr-example-frozen
make export-ocr RUN=.local/runs/ocr-example-frozen
```

The smoke dataset contains eight invented training lines and four validation lines.
It proves mechanics only. `FONT` can select another local font; its hash is recorded.
Training uses CPU and defaults to two numerical-library threads. There is no eight-hour cap.
`OCR_EPOCHS` is the maximum epoch count (default 100); `OCR_PATIENCE` defaults to five
validation epochs without improvement. These are recorded before training.

## Synthetic table development

The pixel-checked table generator can supply a larger experimental dataset:

```sh
make generate-synthetic DATASET=.local/datasets/synthetic-v3-example SYNTHETIC_COUNT=200
make prepare-ocr-synthetic SOURCE_DATASET=.local/datasets/synthetic-v3-example \
  DATASET=.local/datasets/ocr-synthetic-v3-example
```

Use the same `FONT` as the source generator. The adapter verifies every original
image, label, rendered glyph and generator/font hash. Whole source groups receive
deterministic development partitions before crop selection. Repeated identical
crop pixels are excluded from validation if they occur anywhere in training;
source groups are never moved to accommodate a score. Negatives, unusable inputs,
headers and blank cells supply no positive text target.

Selection balances the available fields using a fixed seed, with defaults of
512 training and 128 validation crops. The `prepare.py` CLI exposes the limits
and seed. These are maximums. Version 3 requires date, start/end, title,
room, therapist and note coverage in both partitions, with at least the requested
partition limit divided by seven (rounded down, at least one) crops per field.
It also requires novel validation text for title, room and notes relative to
**all** training-source crops. Missing
coverage fails rather than silently producing a weaker validation set. The
partition seed is fixed before rendering and cannot be changed during preparation.
The receipt retains per-field sample, independent source-group and distinct/novel
text counts, complete source group assignments, exclusions,
source/label/crop identities and geometry. Crops have four pixels of uniform
background padding and no unrecorded augmentation. Source pixels and labels are
rechecked before training, resume and export; altered prepared targets, partitions
or source evidence fail. No patient reference or crop is approved by this route.

The frozen [v2 adapter](compat/synthetic_data_v1.py) and
[v2 generator](../../data/synthesis/compat/synthetic_plans_v2.py) replay existing
version 2 dataset receipts byte-for-byte. This compatibility path does not add
coverage claims to historical results. Historical training identities are retained;
the current reference/privacy contract remains mandatory for later training and export.

Synthetic validation measures development robustness only. Repeated text, fonts
and generator patterns prevent any claim of unseen real-photo accuracy; real
grouped references, separate augmentation comparisons and device gates still apply.

The verified v3 development preparation on 2026-09-26 uses 200 generated sources
(180 schedules, 10 non-plans, 10 unusable images). The selected 512 training crops
cover 136 source groups; 128 validation crops cover 37 groups, with 18–19 crops per
field. There are no cross-partition group, source-image or crop-image intersections.
Validation contains 9 distinct title, 11 room and 6 note targets absent from every
training-source crop. Local evidence is
`.local/runs/ocr-synthetic-v3-qualification-20260926-s18-002/report.json`, for dataset
`ocr-synthetic-development-004` (SHA-256
`463743f227578148be5f517dd15410dc2eea08374bfc67582fbc4c7db87234dd`).
No training or human language/clinical approval is implied.

## Reviewed data

The real-data adapter uses the existing reference exporter and crop materializer:

```sh
make prepare-ocr-data SOURCE_DATASET=.local/datasets/private \
  DATASET=.local/datasets/ocr-reviewed-fold0 FOLD=0
```

It requires human-approved references, separately reviewed complete text crops and
an independent privacy/purpose review bound to active OCR-training consent and
frozen source-related development groups. It fails on the current unapproved photo
collection. It never changes approval or assigns a final holdout. Each prepared
crop retains source/reference/crop/privacy-review hashes, its group, field, variant
and partition. Materialization must retain the exact privacy-review hash exported
with that crop; changed masks cannot silently reuse an earlier export.
Time fields `start` and `end` become canonical `start_time` and `end_time`.

Before training, resume, export, model registration and prepared-run parity
diagnosis, the shared input gate checks live references, crop review, privacy,
permitted use and grouping against the prepared snapshot. Altered text, removed
examples, changed partitions, revoked/expired consent, changed masks, revoked
approval and changed pixels stop the run. Data from new
collections also requires the human privacy and permitted-use review described in
the [collection guide](../../../docs/product/research/collection-guide.md); no
automatic consent-to-reference merge or withdrawal service is implemented.
Operators must keep the private intake/consent receipt current for these checks
to observe a withdrawal.

The [compatibility contract](compat/README.md) preserves only the original
synthetic training identities, with byte-identical source archives and current
validation guards. Historical real-data runs cannot use this exception. Resuming
an original synthetic run loads its actual archived training implementation and
records current guards separately; it never rewrites the original identity.
The complete 603-record v2 dataset and both existing adaptation runs were replayed
with the current guards on 2026-09-26, including checkpoint, selection and export
evidence. Historical JSON receipts remained unchanged and no training was started.
Local proof: `.local/runs/ocr-privacy-lineage-20260926-s18-001/report.json`
(SHA-256 `14a24d3d2f48a1aa8ef946f2839a252f88c4e66cb2a76820b5d3619ac21d2a08`).

Unusable, unreadable, blank, cropped and contradictory evidence cannot become full
recognition targets. Such cases remain part of schedule evaluation, not positive
text-crop training. Every label must fit the unchanged dictionary. Maximum sequence
length comes from the actual labels plus NRTR's start/end tokens; encoding and CTC
alignment capacity are checked without truncation. `--width 640` or `960` can support
longer crops; an insufficient width fails explicitly.

## Compare adaptation modes

Use the identical prepared dataset, seed, width and validation policy for each run:

```sh
make train-ocr DATASET=.local/datasets/ocr-reviewed-fold0 \
  RUN=.local/runs/ocr-frozen-fold0 OCR_MODE=frozen-backbone
make train-ocr DATASET=.local/datasets/ocr-reviewed-fold0 \
  RUN=.local/runs/ocr-full-fold0 OCR_MODE=full
```

Frozen mode fixes all backbone parameters and normalization buffers and uses a
constant learning rate of 1e-4. Full mode updates the whole model at 1e-5. The Adam
and L2 settings follow the pinned configuration; parameters with their own upstream
regularizer retain that regularizer. There is no additional unrecorded random
augmentation: variants are prepared with the data exporter. To change learning
rate, batch size, width or seed, use the same `train.py start --help` CLI directly.
Resume accepts only operational options and always uses its recorded settings.

Validation first minimizes critical-field crop errors, then mean group error and
character errors. Each group has equal weight in mean group error; derivative counts
are disclosed. Original crops and augmented robustness cases have separate reports.
The report also lists newly incorrect critical samples relative to the pretrained
baseline. A selected checkpoint is a development candidate, never automatic app
promotion. Human correction effort and complete schedule accuracy are not inferred
from crop character errors. A quality result still needs all end-to-end gates.

## Interruption and lineage

Every completed epoch writes weights, Adam state, metrics and validation-stop state
into a checksummed directory, published with an atomic rename. File contents and
the parent directory are synchronized before continuation. An incomplete directory
is ignored. A corrupted completed checkpoint fails explicitly. Keep the complete
run and its prepared dataset; do not rename or edit them during a run.

Each epoch has its recorded deterministic seed. An interrupted epoch replays from
the most recent complete epoch with the same optimizer and data order. A deliberate
pause is available as `--pause-after-epoch 1`; resume continues normally. There is
an exclusive local process lock. Low disk space stops further epochs while keeping
completed checkpoints. Checkpoints are retained; storage is not silently pruned.

`identity.json` binds dataset, settings, trainer/helper sources, upstream registry,
environment lock, installed key package versions, Python and platform. Changed
lineage requires a new run. `baseline.json`, per-epoch `checkpoint.json`,
`progress.json`, `selection.json` and stage logs retain the evidence. Selecting a
checkpoint binds the export configuration as well as its weights.

`verify_resume.py` compares every model and optimizer tensor between uninterrupted
and resumed runs and checks frozen backbone buffers against the original weights.
The [recorded experiment](../../experiments/2026-09-26-s17-ocr-resumption.md) states the
actual verification evidence and its limits.

## Export

`make export-ocr` requires a selected checkpoint and a new `deployment/` directory.
It runs the official Paddle export, ONNX opset 17 conversion with optional
post-optimization disabled (`--optimize_tool None` prevents automatic dependency
installation), and the pinned ONNX
Runtime 1.22.0 CPU comparator at widths 320 and 640 plus the configured width.
Raw CTC outputs must match within rtol 1e-3 / atol 1e-5, with identical argmax tokens.
Empty comparisons fail. File hashes and failed stages remain recorded. A failed
export can be retried with `export.py --output NEW_LOCAL_DIRECTORY`.

For diagnosis, `make diagnose-ocr-parity RUN=<run> PARITY_REPORT=<new-private-json>`
rechecks only the failed cases with ORT graph optimization disabled. Use
`PARITY_OPTIMIZATION=shipping` to retain the pinned runtime's normal optimization.
The earlier result and weights must match, report paths cannot be overwritten,
and subset/alternate-configuration results are explicitly diagnostic. Registration
and app loading reject those reports as deployment parity. Numeric tolerances and
token comparison remain unchanged. The runtime option is documented in the
[official ONNX Runtime API](https://onnxruntime.ai/docs/api/python/api_summary.html#onnxruntime.SessionOptions).

`make diagnose-ocr-baseline-parity RUN=<prepared-run> PARITY_REPORT=<new-private-json>`
compares the pinned pretrained checkpoint with the shipping small recognizer on
the same prepared crops and widths. Checkpoint, runtime and dictionary pins must
match. Its report is always diagnostic and cannot qualify an adapted checkpoint.
The new path preserves previous evidence, including failed comparisons.

`make diagnose-ocr-stage-parity RUN=<prepared-run> PARITY_REPORT=<new-private-json>`
isolates each failed case across the selected dynamic model, the upstream export's
`rep()` reparameterization, its saved Paddle graph and the shipping ONNX CPU route.
It revalidates the completed run, selected scores and full earlier parity evidence,
then records stage differences and all source identities. This is a failed-case
diagnostic only: no stage substitutes for complete deployment parity, and the
original tolerances, model files and reports remain unchanged.

Add `UNFUSED_EXPORT=<new-private-directory>` to compare a separate export without
the upstream `rep()` transformation, keeping the selected weights and original
Conv/BN branches:

```sh
make diagnose-ocr-stage-parity RUN=.local/runs/ocr-synthetic-frozen-001 \
  UNFUSED_EXPORT=.local/runs/ocr-unfused-<new> \
  PARITY_REPORT=.local/runs/ocr-unfused-<new>/report.json
```

The alternative uses `paddle.jit.to_static`/`save` with the same dynamic-width
float32 input shape, then the pinned converter at opset 17. Its saved Paddle graph
and ONNX outputs are compared with the original dynamic model. Both normal and
disabled ORT graph optimization are recorded separately. Artifacts, conversion
command/log and hashes stay in a new directory; the standard export, runtime and
earlier model card are untouched. Even a passing subset cannot qualify this
alternative architecture. See the [stage results](../../experiments/2026-09-26-s18-synthetic-ocr-development.md).

ONNX parity does not establish physical iOS parity, latency, recognition quality,
quantization safety or release readiness. The app continues using its existing
pinned model until those independent gates pass.

`make diagnose-ocr-operation-parity RUN=<run> DIAGNOSTIC_RUN=<new-private-directory>`
compares saved Paddle and ONNX intermediate outputs while retaining the original
graphs and checking instrumented outputs against immutable controls. `OCR_TRACE_BATCH`
defaults to 32; `ALL_FAILURES=1` selects all retained failures. This remains an
operation-level diagnostic, not deployment qualification. The
[recorded results](../../experiments/2026-09-26-s18-ocr-operation-parity.md) identify the
first reproducible rounding difference and preserve the original parity failures.

The bounded [Conv-to-MatMul experiment](../../experiments/2026-09-26-s18-ocr-convolution-lowering.md)
uses only the two saved operation fixtures and four exact integer geometry cases.
`make prepare-ocr-convolution-lowering DIAGNOSTIC_RUN=<new-private-directory>`
records its immutable protocol without inference. After scheduling the runtime
window, `make diagnose-ocr-convolution-lowering DIAGNOSTIC_RUN=<same-directory>`
executes that protocol. Both stored Paddle arrays must match byte-for-byte;
otherwise this approach stops. It never launches a full model or experiment 2.

## Register retained results

After training and export finish, create a new model card from their evidence:

```sh
make register-ocr RUN=.local/runs/ocr-frozen-fold0 \
  COMPARE_RUN=.local/runs/ocr-full-fold0 MODEL_CARD=ml/registry/ocr-fold0.json
```

`COMPARE_RUN` is optional. Compared runs must have the same dataset, seed, width,
batch and validation policy; adaptation mode and learning rate may differ. The
command checks current training lineage, labels and pixels, selected checkpoint
and baseline hashes, predicted-text scores, complete parity case coverage and
unchanged tolerances. Failed numeric/token parity remains a failed experimental
variant in the card. Incomplete training or export evidence cannot be registered.

Cards disclose train/validation field and source-group counts, newly incorrect
critical crops, selection, stop reason, hashes and export results. Private targets,
predictions and pixels stay in the run directory. Registration creates a new card
without overwriting an existing one or changing runtime locks. It never grants
human approval, physical verification or model promotion.
