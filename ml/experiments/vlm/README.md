> Historical record: technical findings retained from the archived development sequence. Project dates, build labels and source references have been normalized. This record is not a new test, delivery approval or signing attestation; unaltered evidence and original validity dates are held in the external private archive.

# Local difficult-region experiment

The static `reha-vlm` adapter embeds llama.cpp/libmtmd. It has model loading,
image reading, cancellation and destruction functions; it has no application
state, approval, calendar, network or subprocess interface. The small CLI links
that library for repeatable desktop measurements.

The lock in `ml/registry/runtime/vlm-experiments.lock.json` pins the runtime revision, source
checkpoints, known upstream hashes, prompts, preprocessing and output limits.
Files without an upstream hash require their original `source-manifest.json`
download receipt when reused or converted. Existing bytes are never used to
recreate a missing receipt, and a changed file or receipt is not repaired in place.
Keep historical directories unchanged and explicitly fetch into a new directory
when provenance is missing, for example:

```sh
python3 ml/experiments/vlm/fetch-vlm.py \
  --destination .local/models/runtime/experiments/checkpoints-new
```

First acquisition downloads every file from the pinned repository revision and
records its hash; later reuse verifies that original identity without rewriting it.
Check every model file before invoking the library. `mtmd_init_from_file` checks
projector/text embedding compatibility; an image smoke test is also required.
Model-family support alone does not establish checkpoint compatibility.

The supported host build separates network restoration from offline compilation:

```sh
make restore-vlm-runtime
make build-vlm RUN=.local/runs/vlm-build-example
# Optional model download is a separate action:
make restore-vlm-models
```

The runtime source is shared with the assistant only while both registry pins
match. Restoration refuses a divergent pin or modified checkout. The offline
build uses CMake 3.31.6, checks the source revision, and retains compiler/SDK/source
identities and logs in the new run. Its `receipt.json` identifies the executable
under `.local/builds/vlm/products/<identity>/reha-vlm-read`; later builds verify
every cached output byte. Temporary compiler products are removed on completion.
A build requires the 20 GiB reserve plus 4 GiB peak allowance, including when
invoked directly with `python3 ml/experiments/vlm/build.py build --run ...`.
This is a disk-space check, independent of the cleanup lock; it is repeated after
waiting for the VLM product lock. Insufficient space stops before tools or new
build evidence are created. Eight CLI smoke
checks run on the actual executable without loading weights, including the input
size limit, missing models and preservation of existing reports. These checks
establish executable behavior, not checkpoint compatibility.

Every external VLM tool phase has a finite wall-clock limit. Git/toolchain
queries use 30 seconds; restoration, each download, configure, compilation and
each conversion use 900 seconds by default. The `build.py`, `fetch-vlm.py` and
`qualify-vlm.py` CLIs accept a positive finite `--phase-timeout-seconds` for those
long phases. Build and conversion receipts record that choice. The VLM product
lock uses the same phase deadline. Reader and individual CLI smoke limits remain
60 and 10 seconds respectively.

Each outer tool phase owns an isolated process group. Nested VLM wrappers and
their children remain in that group; a nested timeout cancels the containing
phase. A timeout or interruption terminates the group, allows up to ten seconds
for cleanup, then kills remaining members and reaps the direct child. The final
group kill covers descendants even if nested cleanup deadlines overlap.
Unrelated groups are never enumerated or signalled. Build/conversion logs
and failed receipts remain; old products and compatibility manifests are never
replaced by failed work. Download partials and interrupted restore staging remain
available for inspection, without becoming successful provenance receipts.

Convert the pinned Paddle checkpoint with that checkout's
`convert_hf_to_gguf.py --outtype f16`, once for the text model and once with
`--mmproj` for the projector. Record hashes of both artifacts and the converter.
Do not execute checkpoint Python code or use `trust_remote_code`.

`reha-vlm-read MODEL PROJECTOR FAMILY IMAGE OUTPUT_JSON` reads one source crop,
with a 60-second cooperative deadline including loading, up to 1,024 image tokens
and 256 greedy output tokens. There is no hosted service. The wrapper runner
additionally terminates the child at its wall-clock deadline. Limited or failed
readings cannot become approved fields. Checkpoint load and inference failures
are recorded; they do not replace the portable draft. The CLI checks the 40 MiB
image limit before allocation and rejects a changed read. Result files are created
exclusively with private permissions; existing reports and symlinks are preserved,
and a failed write returns a nonzero exit. Qualification requires an explicitly
selected executable and a new output directory; it cannot overwrite old conversions
or their compatibility manifests.

`build-xcframework.sh` in the pinned runtime includes libmtmd for Apple builds.
This is a future packaging path, not evidence of iPhone qualification. Models
remain outside the app until verified grouped comparisons show more fully
correct appointments with no extra missed/invented events or critical date/time
errors, and physical-device p95 is at most 30 seconds with no termination in 20
consecutive scans. Then compare correction effort, latency, memory and size in
that order. Previously explored photographs cannot serve as final holdout data.

Runtime and model references: [libmtmd documentation](https://github.com/ggml-org/llama.cpp/blob/41fc7584f0c1d72d9cc1ac46ccae8defc1587f0f/docs/multimodal.md),
[GLM checkpoint](https://huggingface.co/ggml-org/GLM-OCR-GGUF/tree/65a42de1148dbed2297e922b5dbc7d9b70c36578),
[Paddle checkpoint](https://huggingface.co/PaddlePaddle/PaddleOCR-VL-1.6/tree/c5630abae1d940eafe0697512a0325494b02ab42).

Prepare a compatibility manifest using the pinned converter environment:

```sh
VLM_BINARY=$(python3 -c 'import json; print(json.load(open(".local/runs/vlm-build-example/receipt.json"))["binary"])')
uv run --python 3.12 --with torch==2.11.0 --with numpy==2.2.6 \
  --with transformers==4.57.6 --with sentencepiece==0.2.1 \
  --with protobuf==4.25.8 --with pillow==12.1.1 \
  python ml/experiments/vlm/qualify-vlm.py \
  --binary "$VLM_BINARY" \
  --output .local/models/runtime/experiments/conversion-example
python3 ml/evaluation/recognition/compare-regions.py /path/to/retained/run.json \
  .local/runs/my-comparison
```

The converter imports `gguf-py` from its own pinned checkout. Leave
`NO_LOCAL_GGUF` unset so the conversion does not use an unrelated installed version.

Qualification verifies source hashes, requires a clean runtime checkout, converts
Paddle text/projector artifacts to F16, and reads an invented control image with
network access denied. The control must be transcribed exactly before the candidate
is admitted to experiments. The resulting private `candidates.json` records source,
converter, adapter, model, projector and smoke-test hashes. It does not qualify a
candidate for the application. `--glm` and `--paddle` can point to existing verified
checkpoint directories.

The comparison chooses one unresolved appointment (or the first appointment when
complete) per photograph, retaining its original-resolution crop, transforms,
portable draft summary and both source-linked readings. It does not replace the
portable draft or turn model text into approved calendar values. The command-line
comparison retains the source crop, provisional annotation and readings for local
review. Each reader has an independent 60-second limit. The retired desktop Dataset
screen is not part of the current iOS application.

The 20-photo exploratory run is retained in the [historical delivery report](../../../docs/releases/history/simple-app-delivery.md). No
verified appointment-level accuracy scores or physical-device qualification are
available, so neither additional model is shipped.

For an offline side-by-side report, run `python3 ml/evaluation/recognition/report-regions.py .local/runs/my-batch .local/runs/refinement-v3-baseline`. The generated `review.html` escapes readings and uses only local images.

Historical models, manifests and compatibility aliases remain unchanged.
A new conversion needs a unique `--output`; pass its `candidates.json` to
`compare-regions.py --manifest` when selecting that experiment. The historical
comparison default still selects the retained historical manifest. A host build
neither re-converts nor re-qualifies an existing checkpoint. The CLI's eight
failure-path smoke checks and portable source/evidence/process guards can be repeated through
`make build-vlm RUN=<new-local-run>` and `make test-tools`, respectively.
