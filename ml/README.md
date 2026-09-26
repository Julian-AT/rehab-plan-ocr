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
checkpoints, generated samples and run logs under `.local/`. The verified private
migration is complete; ignored aliases preserve historical references. Never put
patient records in hosted CI.

The assistant export environment is separate because the pinned llama.cpp
converter requires Transformers 4.57.6 while MLX-LM 0.31.3 requires Transformers
5 or later. It does not replace or change the training environment. The converter
revision is pinned by `ml/registry/assistant-base.json`; full conversion and
target-runtime checks are required before choosing the deployment route.

The OCR environment targets the official
[PP-OCRv6 Small training configuration](https://github.com/PaddlePaddle/PaddleOCR/blob/main/configs/rec/PP-OCRv6/PP-OCRv6_small_rec.yml).
ONNX parity must use the app's ONNX Runtime 1.22.0 and the unchanged deployment
dictionary. Derive maximum label length from verified examples; do not truncate.
The assistant environment targets Qwen3-0.6B using
[MLX-LM LoRA and adapter fusion](https://github.com/ml-explore/mlx-lm/blob/main/mlx_lm/LORA.md).

Both custom models have experimental trained artifacts; neither is qualified for
production. The [current status](../docs/development/status.md) records quality and
parity failures. Preserve train/validation lineage, resumable optimizer state and
grouped evaluation. Existing real references remain unapproved; the exporter keeps
them blocked from training. The [synthetic table generator](data/synthesis/README.md)
checks actual pixels and labels, but its counts cannot establish real-photo or
patient-conversation accuracy.
