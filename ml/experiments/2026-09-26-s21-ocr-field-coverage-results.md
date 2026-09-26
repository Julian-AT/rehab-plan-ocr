> Historical record: technical findings retained from the archived development sequence. Project dates, build labels and source references have been normalized. This record is not a new test, delivery approval or signing attestation; unaltered evidence and original validity dates are held in the external private archive.

# OCR field-coverage study results

Both predeclared adaptations finished after five epochs / 1,280 steps and selected
epoch two by the unchanged validation policy. Neither improves the pretrained
control on these 128 known synthetic validation crops. Neither export passes its
numerical gate. No application asset or provider selection was changed.

The following training/validation scores use the historical OpenCV linear
preprocessing at fixed width 320. They are not measurements of the app's native
input policy. A [later comparison with shared Rust preprocessing](2026-09-26-s21-ocr-app-preprocessing-results.md)
reproduces all historical strings before evaluating that separate policy;
the original scores and generated model card remain unchanged.

The [prospective protocol](2026-09-26-s21-ocr-field-coverage.md) and
[generated model card](../registry/ocr-synthetic-development-002.json) bind the
dataset, selected checkpoints, complete training states and export evidence.
All four serial training/export stages completed with their frozen sources
unchanged. Failed numerical exports are complete results, not interrupted
training. Best and latest checkpoints, including optimizers, remain retained.

| Model on the same 128 crops | Exact crops | Critical errors / 110 | Group mean error | Character errors / 1,951 |
|---|---:|---:|---:|---:|
| Pretrained | 114 | 0 | 0.130094 | 45 |
| Previous frozen adaptation, separate control | 116 | 0 | 0.116581 | 48 |
| Previous full adaptation, separate control | 109 | 1 | 0.169348 | 60 |
| New frozen adaptation | 112 | 0 | 0.146825 | 56 |
| New full adaptation | 111 | 1 | 0.150204 | 45 |

Under that fixed-width-320 policy, the new frozen model misses 16 of 18 notes.
The new full model misses the same number of notes and one therapist field that
the pretrained control gets right.
Thus its lower character-error total than the frozen model does not make it safe
to select. Date, start, end, location and title validation fields are all exact
for both new candidates. The old full control's critical error is an end time;
these are different errors, not a repaired critical case without regression.

| New deployment export | Numerical passes / 1,280 | Equal token sequences / 1,280 | Maximum absolute difference |
|---|---:|---:|---:|
| Frozen | 1,266 | 1,280 | 0.0005645900964736938 |
| Full | 1,261 | 1,280 | 0.005029350519180298 |

Each export covers all 640 crops at both widths 320 and 640, using pinned
ONNX Runtime 1.22.0 and unchanged `rtol=0.001`, `atol=0.00001`. Equal decoded
tokens do not override the failed numerical checks. Exports and previous failures
remain preserved. The private serial evidence is
`.local/runs/ocr-v3-training-20260926-s21-001-evidence`; previous models on the same
new validation set are in `ocr-v3-comparison-20260926-s21-003/execution-001`.

There are 37 synthetic validation source groups, not 128 independent real plans.
All seven field categories have at least 18 validation crops; training contains
512 crops from 136 disjoint source groups. No human-approved references or unseen
final real test set were added. Generalization uncertainty is not established;
these development scores cannot establish 99% real critical-field accuracy or
90% complete-plan accuracy. No speed, energy, usability or physical-device claim
is made from this study.

## Separate export diagnosis

After the study finished, the previously frozen Conv.3 Tile16 experiment passed
all ten primitive comparisons and all ten optimized-graph reload comparisons.
The four fixed integer geometry controls and every one of the 92,160 saved
Paddle reference values are byte-identical, including signed zero. The original
Conv control first reproduced the saved ONNX Runtime result. Input/source/runtime
hashes were unchanged before and after execution.

Evidence: `.local/runs/ocr-conv3-tile16-20260926-s21-001/report.json`, protocol SHA256
`3a38a125498895855f5b688ddb5dd5c8143525beeaafa93e951fe6ee88d97823`.
This is one isolated operation with fixed tile size 16. It does not repair or
qualify either complete export. The subsequent [cumulative complete-graph comparison](2026-09-26-s21-ocr-cumulative-export-results.md)
also fails its numerical gate. It preserves exact tokens but introduces regressions
against earlier successful cells. No full-corpus promotion follows. The same
report records the earlier static preprocessing review for long notes. The later
native-input comparison linked above measures that concern separately and does
not repair either numerical export.
