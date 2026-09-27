# OCR adaptation with complete synthetic field coverage

This protocol precedes training. The existing pixel-verified v3 development
dataset closes the earlier validation gap for titles, locations and notes. Use
`.local/datasets/ocr-synthetic-development-004/dataset.json`, SHA-256
`463743f227578148be5f517dd15410dc2eea08374bfc67582fbc4c7db87234dd`:
512 training crops from 136 source groups and 128 validation crops from 37 source
groups. All seven fields have at least 18 validation examples. Related source
pages stay together; synthetic groups are not independent real patients or plans.
This is development data, with no human reference approval or final holdout.

Compare one frozen-backbone and one full PP-OCRv6 Small adaptation, using the same
pinned pretrained weights, dictionary, CPU environment and current training
implementation. Match the previous experiments: batch two, width 320, seed
20260917, maximum 50 epochs, patience three, learning rates 0.0001 for the frozen
backbone and 0.00001 for full adaptation. Select by the existing ordered critical
error, group error and character error contract. Do not change settings or choose
a different checkpoint after seeing results. Keep complete selected and latest
checkpoint states, including optimizer and provenance.

Before training, repeat dataset provenance, pixel and grouping verification.
Run the model work serially after the assistant experiment, with the existing
twenty-GiB storage reserve plus the operation allowance. Bind source files,
dataset, environment and evidence by hash. Preserve earlier runs unchanged.

Each run measures its pretrained baseline on all 128 validation crops. Compare
the previous selected frozen/full checkpoints on that same set as a separate
development control. Report per-field errors and every newly wrong critical
crop; an aggregate improvement does not excuse new omissions. Earlier 91-crop
scores and new 128-crop scores are not directly comparable.

Export each newly selected checkpoint through the unchanged deployment route
and compare all 640 crops at widths 320 and 640: 1,280 numerical and token cases
per candidate, using ONNX Runtime 1.22.0 and the existing `rtol=0.001`,
`atol=0.00001` gate. This is a training/data experiment, not a claimed correction
of the unresolved convolution export difference. Preserve failed exports and
do not promote any failing candidate. No quantization or runtime substitution
is part of this comparison.

```sh
make train-ocr DATASET=.local/datasets/ocr-synthetic-development-004 \
  RUN=.local/runs/ocr-v3-frozen-001 OCR_MODE=frozen-backbone \
  OCR_EPOCHS=50 OCR_PATIENCE=3
make export-ocr RUN=.local/runs/ocr-v3-frozen-001
make train-ocr DATASET=.local/datasets/ocr-synthetic-development-004 \
  RUN=.local/runs/ocr-v3-full-001 OCR_MODE=full \
  OCR_EPOCHS=50 OCR_PATIENCE=3
make export-ocr RUN=.local/runs/ocr-v3-full-001
```

Even perfect synthetic crop scores would leave complete-plan accuracy, correction
effort, real reviewed references, app integration and physical performance open.
The public model selection remains unchanged by this experiment alone.
