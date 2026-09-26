> Historical record: technical findings retained from the archived development sequence. Project dates, build labels and source references have been normalized. This record is not a new test, delivery approval or signing attestation; unaltered evidence and original validity dates are held in the external private archive.

# Local difficult-region experiment

The static `reha-vlm` adapter embeds llama.cpp/libmtmd. It has model loading,
image reading, cancellation and destruction functions; it has no application
state, approval, calendar, network or subprocess interface. The small CLI links
that library for repeatable desktop measurements.

The lock in `ml/registry/runtime/vlm-experiments.lock.json` pins the runtime revision, source
checkpoints, known upstream hashes, prompts, preprocessing and output limits.
Check every model file before invoking the library. `mtmd_init_from_file` checks
projector/text embedding compatibility; an image smoke test is also required.
Model-family support alone does not establish checkpoint compatibility.

Build from a clean checkout at the lock's revision:

```sh
cmake -S ml/experiments/vlm -B models/private/experiments/build \
  -DLLAMA_SOURCE="$PWD/models/private/llama.cpp" -DCMAKE_BUILD_TYPE=Release
cmake --build models/private/experiments/build --parallel 4
python3 ml/experiments/vlm/fetch-vlm.py
```

Convert the pinned Paddle checkpoint with that checkout's
`convert_hf_to_gguf.py --outtype f16`, once for the text model and once with
`--mmproj` for the projector. Record hashes of both artifacts and the converter.
Do not execute checkpoint Python code or use `trust_remote_code`.

`reha-vlm-read MODEL PROJECTOR FAMILY IMAGE OUTPUT_JSON` reads one source crop,
with a 60-second cooperative deadline including loading, up to 1,024 image tokens
and 256 greedy output tokens. There is no hosted service. The wrapper runner
additionally terminates the child at its wall-clock deadline. Limited or failed
readings cannot become approved fields. Checkpoint load and inference failures
are recorded; they do not replace the portable draft.

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
uv run --python 3.12 --with torch==2.11.0 --with numpy==2.2.6 \
  --with transformers==4.57.6 --with sentencepiece==0.2.1 \
  --with protobuf==4.25.8 --with pillow==12.1.1 \
  python ml/experiments/vlm/qualify-vlm.py
python3 ml/evaluation/recognition/compare-regions.py /path/to/retained/run.json \
  artifacts/private/my-comparison
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
portable draft or turn model text into approved calendar values. Import the photo in
**Dataset**, choose **Compare portable / GLM-OCR / PaddleOCR-VL-1.6**, and inspect
the result alongside the source and provisional annotation. Inconclusive or limited
output stays visible. Each reader has an independent 60-second limit.

The 20-photo exploratory run is recorded in `docs/simple-app-delivery.md`. No
verified appointment-level accuracy scores or physical-device qualification are
available, so neither additional model is shipped.

For an offline side-by-side report, run `python3 ml/evaluation/recognition/report-regions.py artifacts/private/my-batch artifacts/private/refinement-v3-baseline`. The generated `review.html` escapes readings and uses only local images.
