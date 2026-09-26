# Local model development

Application code must not depend on this directory. App tooling uses the root
`pyproject.toml`/`uv.lock`; OCR and assistant training each have an independent
project and lockfile under `training/`.

```sh
make restore-ocr-training
make restore-assistant-training
make restore-assistant-export
```

The assistant environment requires an Apple Silicon Mac. Both commands install
dependencies under ignored `.local/envs/`. Keep original documents, model weights,
checkpoints, generated samples and run logs under `.local/`; existing private
directories have not yet been migrated. Never put patient records in hosted CI.

The assistant export environment is separate because the pinned llama.cpp
converter requires Transformers 4.57.6 while MLX-LM 0.31.3 requires Transformers
5 or later. It does not replace or change the training environment. The converter
revision remains pinned by `ml/registry/runtime/vlm-experiments.lock.json`; full conversion
and target-runtime checks are required before choosing the deployment route.

The OCR environment targets the official
[PP-OCRv6 Small training configuration](https://github.com/PaddlePaddle/PaddleOCR/blob/main/configs/rec/PP-OCRv6/PP-OCRv6_small_rec.yml).
ONNX parity must use the app's ONNX Runtime 1.22.0 and the unchanged deployment
dictionary. Derive maximum label length from verified examples; do not truncate.
The assistant environment targets Qwen3-0.6B using
[MLX-LM LoRA and adapter fusion](https://github.com/ml-explore/mlx-lm/blob/main/mlx_lm/LORA.md).

These environments do not constitute trained or qualified models. Before a
substantial run, pin the upstream code revision and checkpoint hashes, prove
checkpoint loading, short training, export and execution in the intended iOS
runtime. Preserve train/validation lineage, resumable optimizer state and grouped
evaluation. Existing references remain unapproved; the reference exporter keeps
them blocked from training. Synthetic smoke tests must be labeled as such and
cannot establish real-photo or patient-conversation accuracy.
