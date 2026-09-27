# Model development

This workspace retains reusable data preparation, training, export, evaluation,
runtime manifests and model cards. The app's selected runtime assets are pinned in
`registry/runtime`; experimental cards never implicitly replace the default.

| Area | Responsibility |
| --- | --- |
| `data/annotation` | Private intake, human reference review and approval |
| [data/augmentation](data/augmentation/README.md) | Geometry-preserving variants |
| [data/synthesis](data/synthesis/README.md) | Synthetic tables with pixel/label checks |
| [training/ocr](training/ocr/README.md) | Pinned OCR training, resumption and export |
| [training/assistant](training/assistant/README.md) | MLX training, resumption and separate conversion |
| [evaluation/recognition](evaluation/recognition/README.md) | Critical fields, omissions, hallucinations and export parity |
| [evaluation/conversation](evaluation/conversation/README.md) | Strict app interpretation and bounded native trials |
| [evaluation/speech](evaluation/speech/README.md) | Speech/listening measurements |
| [registry](registry/README.md) | Runtime pins and experimental provenance |
| [experiments](experiments/findings.md) | Retained findings and active protocols |

```sh
make restore-ocr-training
make restore-assistant-training
make restore-assistant-export
```

These explicit setup commands create ignored `.local/envs` environments. The
assistant environment requires Apple Silicon. Its converter is separate because
the pinned llama.cpp converter and MLX-LM use different Transformers versions.
Upstream checkouts require Git and exact pinned revisions. Model restoration is
explicit; private source data, model weights, checkpoints and logs stay in `.local`.

OCR parity uses the app's pinned ONNX Runtime 1.22.0 and deployment dictionary.
Do not truncate labels, change thresholds or replace reference groups to hide
failures. Preserve train/validation lineage and resumable optimizer state. Real
references require explicit human review and approval before training export.
See the [dataset contract](../docs/development/dataset.md).

Both custom model paths remain experimental. Synthetic development results,
compatibility checks and session reuse do not establish real-photo accuracy,
real-speech reliability or independent generalization. Retired one-off diagnostic
commands are cataloged in [recovery](../docs/development/recovery.md).
