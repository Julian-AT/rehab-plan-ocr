# Retained research findings

These summarize completed development investigations. They are not new measurements
or evidence of production qualification. The full protocols, source, reports and
original scope remain recoverable from [Git history](../../docs/development/recovery.md).
Private evidence is deliberately absent from source submissions.

- OCR export remains unqualified. Isolated convolution/BatchNorm arithmetic
  investigations reproduced controls but did not resolve the full numerical gate.
  The cumulative candidate passed 17/24 numerical cells versus 18/24 for historical
  comparison arms. Equal decoded text did not override numeric failures; no default
  deployment graph or threshold changed.
- Explicit FMA contraction did not reproduce the saved Paddle BatchNorm output
  exactly. Sub-tolerance intermediate differences alone did not establish a cause
  of the final export failure.
- Assistant development-002 passed complete-answer export parity on its 40 known
  development cases, with 30 exact raw answers and four unsafe raw proposals.
  Rule-routed replay results must remain distinct from raw model results and real
  microphone-to-answer performance. The candidate remains unqualified.
- Native OCR provider compatibility on synthetic imports does not establish
  real-photo accuracy, correction effort or independent latency improvement.
- Simulator playback, speech endpoints and synthetic VAD signals do not qualify
  real speech, natural pauses, human listening or physical-device performance.

Reusable full-model export/stage/operation parity tools remain under
`ml/evaluation/recognition`. The isolated, completed operator diagnostic chain and
its exclusive commands/tests have been retired. Training dependencies are still
needed by retained exporters; their pinned versions remain unchanged.

Active bounded protocols include [critical-field coverage](2026-09-26-s21-ocr-field-coverage.md),
[assistant development](2026-09-26-s21-assistant-development-v2.md),
[VLM measurement](vlm/README.md), and
[device qualification](../evaluation/conversation/DEVICE-QUALIFICATION.md).
