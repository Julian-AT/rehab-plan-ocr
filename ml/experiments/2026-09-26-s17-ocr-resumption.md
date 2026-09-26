> Historical record: technical findings retained from the archived development sequence. Project dates, build labels and source references have been normalized. This record is not a new test, delivery approval or signing attestation; unaltered evidence and original validity dates are held in the external private archive.

# PP-OCRv6 adaptation, interruption recovery and export — 2026-09-26

The resumable trainer completed frozen-backbone and full fine-tuning smoke runs.
A forced mid-epoch interruption recovered exactly. The frozen-backbone artifact
passes the desktop export gate; the full-adaptation artifact fails two numerical
parity cases and remains rejected. Neither candidate qualifies for app promotion.

## Fixed experiment

The matching PP-OCRv6 Small base, source revision and dictionary remain those in
[`ocr-base.json`](../registry/ocr-base.json). The independently locked environment
uses Paddle 3.3.1, Paddle2ONNX 2.1.0 and ONNX Runtime 1.22.0 CPU. The prepared dataset
contains eight invented training lines and four validation lines, with no real
patient examples. Its SHA-256 is
`bacd059c1381da4d5d97597a49b81a3e23ad5b811c9ffbc3a7230570d7a582aa`.

Both modes used seed 20260917, batch size 2, width 320, maximum three epochs and
patience one. Frozen-backbone adaptation used constant LR 1e-4; full adaptation used
1e-5. Both stopped after epoch two without validation improvement and selected epoch
one. The base and selected candidates each read all four validation lines exactly.
This ceiling result provides no evidence of better recognition quality.

## Recovery evidence

Run `.local/runs/ocr-resume-smoke-002` paused after epoch one. Its first resume was
terminated with SIGTERM immediately after optimizer step five, during epoch two.
Only `epoch-0001` remained published. Resuming replayed epoch two and completed eight
steps. `.local/runs/ocr-continuous-smoke-002` ran the same settings uninterrupted.

`verify_resume.py` compared **902 model/optimizer tensors**, all exactly equal.
All **295 backbone state tensors**, including normalization buffers, remained equal
to the pretrained base. The selected checkpoint hashes are also identical. Evidence
is retained in `interruption-test.json`, both run directories and
`.local/runs/ocr-resume-parity-002.json`. The earlier `001` pause/resume experiment
also passed; `002` verifies the subsequent source/provenance checks and real process
termination. Only completed epoch boundaries are resumable; partial epochs replay.

## Export evidence

| Candidate | Exact development crops | Numerical parity | CTC argmax parity | Largest absolute difference |
|---|---:|---:|---:|---:|
| Frozen backbone | 4/4 | 24/24 | 24/24 | 0.0000343025 |
| Full adaptation | 4/4 | 22/24 | 24/24 | 0.000216067 |

The 24 parity cases are 12 invented lines at widths 320 and 640. The unchanged gate
is rtol 1e-3 / atol 1e-5 plus identical argmax tokens. Full adaptation fails on
`train-4` and `train-6` at width 640: one probability element in each output exceeds
the prescribed tolerance. Disabling ONNX Runtime graph optimization in a separate
local diagnostic still yields 22/24. That diagnostic did not change the shipping
route or tolerance. The conversion/runtime numerical difference remains unresolved.
The failed run and raw reports remain available for investigation.

The initial converter attempted to install a missing optional Polygraphy dependency.
Installation failed because the isolated environment has no pip; no dependency was
installed. Both export commands now use explicit `--optimize_tool None`, avoiding
that automatic-install branch. Both conversions were repeated with macOS network
access denied. Artifact hashes and parity outcomes remained identical, and the logs
contain no install attempt. See the upstream
[Paddle2ONNX CLI/configuration](https://github.com/PaddlePaddle/Paddle2ONNX/blob/develop/_autodocs/10_%E9%85%8D%E7%BD%AE%E4%B8%8E%E5%91%BD%E4%BB%A4%E8%A1%8C.md)
and [ONNX Runtime session options](https://onnxruntime.ai/docs/api/python/api_summary.html).

The machine-readable artifact card is
[`ocr-adaptation-smoke-002.json`](../registry/ocr-adaptation-smoke-002.json).
The app still uses its prior pinned OCR model. Real-photo field accuracy, missing or
invented appointments, correction effort, complete schedules, device parity,
performance and energy remain unmeasured for these candidates. No quantization was
attempted and no final holdout was opened.

## Infrastructure checks

Portable regressions reject overlapping source/group/pixel identities across folds,
partial evidence, unknown dictionary characters, changed images, missing validation,
final holdouts, unknown field names, corrupt checkpoints and altered approved
exports. The materialization adapter is exercised with invented reference fixtures,
including crop-review revocation. Actual private references remain unapproved.

The [trainer guide](../training/ocr/README.md) documents make targets, new-run versus
resume semantics, configuration identity, checkpoint storage, export and limits.
