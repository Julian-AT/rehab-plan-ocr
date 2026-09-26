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
Short training, deployment export and shipping-runtime parity remain required
before substantial fine-tuning. No accuracy or performance qualification follows
from this result.

The independent MLX-LM 0.31.3 environment also imports and runs a Metal computation.
Its built-in `fuse --export-gguf` supports only llama/mistral/mixtral in this
version. Qwen3 needs a separately verified converter or a safetensors runtime
after adapter fusion; do not advertise the built-in GGUF flag as a supported path.
