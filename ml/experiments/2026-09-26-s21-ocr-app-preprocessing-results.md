> Historical record: technical findings retained from the archived development sequence. Project dates, build labels and source references have been normalized. This record is not a new test, delivery approval or signing attestation; unaltered evidence and original validity dates are held in the external private archive.

# OCR crop comparison with native app preprocessing

The shared Rust app preprocessing removes all observed note errors on the same
128 known synthetic validation crops. Under this common input policy, no
adapted checkpoint improves on the pretrained checkpoint. This later comparison leaves
the [historical fixed-width-320 results](2026-09-26-s21-ocr-field-coverage-results.md),
selected checkpoints and failed numerical exports unchanged.

The predeclared experiment completed all 1,280 cases: five fixed checkpoints,
128 identical targets and two input policies. Arm A uses the frozen OpenCV linear
320-pixel transform in singleton batches. All 640 A strings first reproduced the
historical batch-two strings exactly; only then did arm B run. B consumes the
hashed float32 tensors produced by the [shared Rust helper](../../docs/architecture/recognition-input.md),
with native proportional width, padding and Triangle interpolation. Python does
not recreate that preprocessing. Architecture, dictionary and decoder stay fixed.

| Checkpoint | A exact / 128 | B exact / 128 | Notes exact A → B / 18 | B critical errors / 110 |
|---|---:|---:|---:|---:|
| Pretrained | 114 | 128 | 4 → 18 | 0 |
| Previous frozen adaptation | 116 | 128 | 6 → 18 | 0 |
| Previous full adaptation | 109 | 127 | 0 → 18 | 1 |
| New frozen adaptation | 112 | 128 | 2 → 18 | 0 |
| New full adaptation | 111 | 127 | 2 → 18 | 1 |

All 76 previously wrong model/note pairs become correct; no previously correct
crop becomes wrong. The previous full model retains its end-time punctuation
error, and the new full model retains its therapist uppercase-I/lowercase-l error.
The pretrained and both frozen models produce identical correct B strings on
all 128 targets. Neither full adaptation matches that baseline.

This controlled intervention explains the observed note failures at the level of
the complete preprocessing policy. Width and interpolation change together;
it does not establish width alone as the cause. The 18 note rows contain only
six texts, 15 PNG identities and 15 synthetic source groups; all 128 crops span
37 synthetic groups. These already inspected development examples do not establish
unseen accuracy. No new training, checkpoint search or model selection occurred.

Every row retains raw CTC argmax tokens, decoded text, edit operations, actual
shapes, finite-value checks, dictionary coverage and measured CTC capacity. All
1,280 strings and character-error counts were independently checked from those
retained records without further inference. Source and physical runtime inventories
were unchanged. This is dynamic Paddle inference on native-preprocessed oracle
crops, not execution of the iOS/ONNX pipeline or a detector/complete-plan test.
Mean token scores are not calibrated probabilities. Earlier export failures and
`rtol=0.001`, `atol=0.00001` remain unchanged; no deployment is qualified.

Private evidence: `.local/runs/ocr-app-preprocessing-comparison-20260926-s21-001`.
The final protocol is `seal-003/protocol.json` under the same-named maintenance
preparation directory, SHA256
`f4b2447ad0fb0450669fafddb6e818f75b3bd2da717d0dd8cd15a375756c7699`.
Execution SHA256:
`a293d0216537d0d0f6320ac6bc0ca80eb4dfa4cc846a31e8a6c481d2283eb38d`.
Complete paired-results SHA256:
`09a27ca3aa1a0593afb533c45bdc88e865ab4d1899a74ee4f6650e4fc04bf3be`.
The separate read-only review is
`.local/maintenance/ocr-app-preprocessing-result-review-20260926-s21-001/result-review.json`.
