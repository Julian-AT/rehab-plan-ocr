> Historical record: technical findings retained from the archived development sequence. Project dates, build labels and source references have been normalized. This record is not a new test, delivery approval or signing attestation; unaltered evidence and original validity dates are held in the external private archive.

# PP-OCRv6 Small checkpoint compatibility

The official trainable checkpoint in `registry/ocr-base.json` loads into the
matching official configuration at PaddleOCR revision
`dab3fe35379033fdcb2d0e9572fac0b36c9a9ebf` using PaddlePaddle 3.3.1 on arm64 macOS.

Measured by `training/ocr/preflight.py`: 422 state tensors, 31,216,454 values,
zero missing keys, unexpected keys or shape mismatches. The training model
includes the auxiliary NRTR head; these counts are not the deployed CTC model's
installed size. The complete ordered CTC dictionary exactly matches the pinned
iOS dictionary (SHA-256 `e6948b0b16c8d2c1255403b884fb9b3ecc3e5dea0ddafdfebe7276ef41520a08`).

```sh
make restore-ocr-training
python3 ml/training/ocr/restore.py
.local/envs/ocr/bin/python ml/training/ocr/preflight.py \
  --report .local/runs/ocr-preflight/report.json
```

No patient images are read by this check. It establishes checkpoint loading only.

## Synthetic training and export smoke test

`training/ocr/smoke.py` completed one epoch (four optimizer steps), exported the
CTC inference graph and converted it to ONNX opset 17. It used eight invented
training lines and four different invented validation lines, with recorded font,
dataset, environment, configuration, source and checkpoint hashes. The maximum
verified label length was 15; no label was truncated. Checkpoints include the
upstream optimizer and training-state files. This short smoke runner is separate
from the still-pending resumable, validation-stopped training workflow.

`evaluation/recognition/export_parity.py` compared Paddle evaluation output with
ONNX Runtime 1.22.0 CPU output for all 12 lines at widths 320 and 640:
**24/24 cases passed**, with identical CTC token sequences, `rtol=1e-3` and
`atol=1e-5`. Maximum absolute probability difference was 0.0002783. Export SHA-256:
`afeb29060b848d22c43363c1dd5584ebbe61d0946e4355084425a0848550b401`.

```sh
.local/envs/ocr/bin/python ml/training/ocr/smoke.py \
  --output .local/runs/ocr-smoke-001 \
  --font /System/Library/Fonts/Supplemental/Arial.ttf --execute
OMP_NUM_THREADS=1 .local/envs/ocr/bin/python \
  ml/evaluation/recognition/export_parity.py --run .local/runs/ocr-smoke-001
```

The output directory must be new. Run records and per-stage logs survive a failed
stage. All 12 examples are synthetic; the independent real-photo denominator is
zero. This is neither a quality comparison nor an iOS device parity measurement.
The artifact remains experimental and is not bundled into the app. Substantial
fine-tuning, grouped evaluation, correction-effort measurement and full shipping
route verification remain required.

The independent MLX-LM 0.31.3 environment also imports and runs a Metal computation.
Its built-in `fuse --export-gguf` supports only llama/mistral/mixtral in this
version. Qwen3 needs a separately verified converter or a safetensors runtime
after adapter fusion; do not advertise the built-in GGUF flag as a supported path.
