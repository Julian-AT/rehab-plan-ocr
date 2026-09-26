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

## Result: failed at the first case

Protocol/tool commit before execution: `22344a7`. Private run:
`.local/runs/ocr-convolution-stage-20260926-s18-001/`.

The original control reproduced its previous result. On the first frozen case,
`plan-020:day-20-0-date-0` at width 320, the candidate still fails one of 748,400
values. CTC tokens agree. Maximum absolute error is 0.0000680088996887207;
original deployment error is 0.00007063150405883789. The unmodified unfused
control passes this case with maximum error 0.00004106760025024414.

Execution stopped after this one case, as predeclared. The remaining eleven cases
and the full-model/full-corpus gates were **not run**. All original source hashes
are unchanged. A smaller maximum error is not a pass. The successful isolated
operation therefore does not establish complete-model equivalence; the copied
candidate is retained solely as a reproducible failed experiment. No deployment
artifact, threshold, selected model or historical report has been replaced.

Four construction/geometry tests pass, including dynamic batch/odd-width integer
runtime oracles. Further work must first identify the earliest remaining operation
or optimization difference in this retained full-graph failure. It must not tune
or relax the existing numerical gate on this observed output.

Protocol SHA-256: `c11b79035e610c11260d46c52b973f60ea611ab8ce55a867feb54aa0f311add0`.

Report SHA-256: `e59c054bd2817c40b315f3bb3243e0fd6aee39325e0c6e9c23b45f36e3d8c04b`.
