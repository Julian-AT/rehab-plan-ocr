> Historical record: technical findings retained from the archived development sequence. Project dates, build labels and source references have been normalized. This record is not a new test, delivery approval or signing attestation; unaltered evidence and original validity dates are held in the external private archive.

# Cumulative OCR export diagnosis and preprocessing findings

The cumulative BatchNorm/2×2/Tile16 candidate still fails the unchanged numerical
export gate. No deployed graph, weight, provider or threshold was changed.
This is a diagnostic result on twelve fixed historical cases at two optimization
levels, not a complete-corpus or real-plan qualification.

| Graph | Numeric successes / 24 |
|---|---:|
| Historical explicit BatchNorm division | 18 |
| Historical BatchNorm + two 2×2 lowerings | 18 |
| A: BatchNorm + Conv.3 Tile16, without the two 2×2 lowerings | 14 |
| B: cumulative BatchNorm + both 2×2 lowerings + Conv.3 Tile16 | 17 |

B repairs five A cells and introduces two numerical regressions. Against the two
historical BatchNorm arms it preserves 33 of 36 prior success cells, including
all eight original pass cells. An improved count against A alone is therefore
not a safe export improvement. All 48 final token comparisons and all 64 reload
comparisons pass; equal text does not override the numerical failures.

The six original 2×2 primitive checks, ten Tile16 primitive checks, 36 original
pixel/native/ORT controls and 24 exact A-output replays pass. Inputs, complete
runtime-file bindings and the fixed distribution inventory are unchanged.
The private run is `.local/runs/ocr-tile16-fullgraph-20260926-s21-002`, protocol SHA256
`26865dcf2a734931c8325fbcc1fc7bc55078f3a0ca27c8be2f97eb43a9d1b02f`,
report SHA256 `db5d00a31ea38f7fd2fde292e852d9d8bc0bfd4b099891b527c1a953e6996bae`.

The earlier 001 run remains failed. Its final package-discovery check changed
because importing Paddle exposes Setuptools' bundled metadata on `sys.path`,
although every bound package file stayed byte-identical. The separately frozen
002 inventory identifies installed and bundled distributions by their actual
metadata locations; loaded-module observations are recorded separately. Its
control arm preserves the exact 001 graph and output bytes. This bookkeeping
correction does not turn 001 or either graph into a qualified export.

In B's controlled trace, the first 17 mapped outputs, including Conv.3, are
byte-identical. The next mapped depthwise convolution receives identical inputs
and weights, but 18,950 of 184,320 output values differ in their bits; maximum
absolute difference is 3.5762786865234375e-07. None violates the fixed tolerance.
Earlier unmapped outputs remain disclosed. This is neither proof of the earliest
actual difference nor proof that this operation causes the final failing values.
The next bounded proposal compares the original isolated operators and fixed
integer geometry controls; no replacement kernel is selected.

## Static preprocessing review before the native-input comparison

All 18 validation note crops and the new critical therapist-error crop are
visually complete and match their synthetic source polygons and target glyphs.
This is an assistant review of synthetic data, not human reference approval.
The note errors are predominantly deleted characters. The therapist regression
changes an uppercase I to a lowercase l and is separate from the width issue.

At height 48, the note lines need proportional widths 530–765. The fixed 320-pixel
training/validation policy squeezes them to 42–60% of their relative width. Nine
would still be squeezed at 640. The actual app preserves proportional width up
to 3200 and pads to a multiple of eight, with a minimum padded width of 320.
OpenCV linear and Rust Triangle interpolation also differ; their pixel equality
has not been established. There are only 40 output positions at fixed width 320,
while the note targets require 33–38 CTC positions including repeated-character
blanks. At that stage this was a plausible source of errors, without a controlled
preprocessing measurement.

All 73 training notes have 18–29 characters; all 18 validation notes have 32–38.
Held-out wording and length are therefore confounded. The validation notes cover
six strings, 15 distinct PNGs and 15 synthetic groups. Existing parity reports
retain no 640-pixel decoded text or token IDs: `same_tokens` only compares Paddle
against ONNX within one width. No accuracy improvement at 640 follows from it.

The private source-bound review is
`.local/maintenance/ocr-v3-note-errors-20260926-s21-001/report.json`, SHA256
`dfa243182a290180e255a028e73d255f4fd06ff8f7ed9d02131a9480e4f5a92d`.
Its prospective two-arm comparison fixes five existing checkpoints and all 128
validation targets, including all 110 critical fields. It first requires legacy
text replay, then app-generated tensors from a shared Rust helper. Inference had
not run at the time of that review. The [later completed comparison](2026-09-26-s21-ocr-app-preprocessing-results.md)
reproduces all 640 historical strings and makes all 18 notes correct for every
checkpoint with native preprocessing, without new training. The pretrained and
both frozen models reach 128/128; both full models retain one distinct critical
error. Width and interpolation change jointly, so width-only causality remains
unidentified. Historical 320 scores and numerical export failures stay unchanged.
