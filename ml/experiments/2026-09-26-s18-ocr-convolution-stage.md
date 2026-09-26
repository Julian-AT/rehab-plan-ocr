> Historical record: technical findings retained from the archived development sequence. Project dates, build labels and source references have been normalized. This record is not a new test, delivery approval or signing attestation; unaltered evidence and original validity dates are held in the external private archive.

# Bounded full-model convolution experiment

This protocol is committed before full-model inference. It follows the successful
[isolated operation experiment](2026-09-26-s18-ocr-convolution-lowering.md).
Selected weights, original exports, reports and the dynamic Paddle reference stay
unchanged. Numeric thresholds remain `rtol=1e-3`, `atol=1e-5`, with exact CTC tokens.

Only the two supported 2×2 stem convolutions in a copy of each unfused graph are
replaced by the validated patch/MatMul construction. Batch and spatial dimensions
remain dynamic. Original constants and every unrelated operation stay byte-identical.
The graph construction and a two-stage exact integer oracle exercise batch sizes
1/2 and odd widths 5/7 before the complete models are evaluated.

The immutable selection is six cases per frozen/full run: for each width 320/640,
the first previous failure, the worst other failure, and the first previous pass.
Preparation records exact IDs, image hashes, source groups, source artifacts and
package versions. It performs no model inference. Original deployment output must
reproduce its previous numeric and token result on every case.

The first failed control or candidate stops this experiment. All twelve cases must
pass before a separate full-corpus comparison may be prepared. There is no automatic
full-corpus run, no parameter sweep and no threshold adjustment. A successful small
experiment would still leave full-corpus, pretrained baseline, app/device resource
and real-plan qualification outstanding. `qualified` stays false.

Use `make prepare-ocr-convolution-stage DIAGNOSTIC_RUN=.local/runs/<new-run>` and,
separately, `make diagnose-ocr-convolution-stage DIAGNOSTIC_RUN=<prepared-run>`.
Execution preserves the protocol and refuses to reuse an already started directory.
The execution entry requires 20 GiB working reserve plus 2 GiB temporary capacity.
