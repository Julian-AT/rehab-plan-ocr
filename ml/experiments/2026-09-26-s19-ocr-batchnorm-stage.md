> Historical record: technical findings retained from the archived development sequence. Project dates, build labels and source references have been normalized. This record is not a new test, delivery approval or signing attestation; unaltered evidence and original validity dates are held in the external private archive.

# Complete graph division after the isolated BatchNorm correction

This protocol precedes saved-model candidate inference. The
[isolated ONNX experiment](2026-09-26-s19-ocr-batchnorm-onnx.md) reproduces the saved
first Paddle BatchNorm exactly at both optimizer levels. This bounded follow-up
tests that representation in both original full inference graphs, including
the effects of optimizer fusion. It does not change deployment resources.

Reuse the **exact twelve cases and order** frozen before the
[convolution experiment](2026-09-26-s18-ocr-convolution-stage.md): for each frozen/full
training run and width 320/640, the first previous failure, worst other failure,
and first prior success. The original selection protocol has SHA-256
`c11b79035e610c11260d46c52b973f60ea611ab8ce55a867feb54aa0f311add0`.
These are selected development cases, not an independent test set.

Exactly two graph variants are declared:

1. Replace all 58 FP32 NCHW inference BatchNorms with explicit division and
   Paddle's offset grouping, retaining every original parameter and epsilon.
   Preserve all other operations and public tensor identities.
2. Apply the same change and the two previously isolated, byte-exact 2×2
   convolution lowerings. No additional kernel replacement is permitted.

Validate every native Paddle BatchNorm's inference/statistics/layout attributes
against its original ONNX node. Reject unsupported shapes, trainable statistics,
nonconstant/nonfinite parameters, zero denominators or namespace collisions.
Independent dynamic-shape, arithmetic, source-preservation and rejection controls
must pass before the implementation/protocol commit and saved-model execution.

Run each variant with `ORT_DISABLE_ALL` and `ORT_ENABLE_ALL` on the same pinned
native ARM64 CPU runtime, two intra-op and one inter-op thread. For each training
run, first reproduce all six original deployed-model measurements against dynamic
Paddle: prior numeric/token outcome and exact maximum error. A failed control
stops execution. Save original inputs and outputs. Reload every serialized
optimized variant with optimization disabled and require byte-identical results
on all six inputs. A failed reload also stops execution. Serialized optimized
graphs remain host-specific diagnostic artifacts.

For candidate parity, retain the unchanged `rtol=1e-3`, `atol=1e-5` and exact
per-position CTC argmax contract. Complete all twelve cases despite candidate
failures and retain every output. No parameter, threshold, case-selection or
optimizer tuning is allowed after execution. A variant can advance only if
**all twelve controls and cases at both levels** pass. If both variants pass,
prefer the one changing fewer original operations. Missing, duplicated,
reordered, numerically failing or token-divergent evidence cannot advance it.

```sh
make prepare-ocr-batchnorm-stage DIAGNOSTIC_RUN=.local/runs/<new-run>
make diagnose-ocr-batchnorm-stage DIAGNOSTIC_RUN=.local/runs/<prepared-run>
```

Preparation freezes sources, previous reports, exact input identities, packages,
machine, this description and selection without inference. Execution requires
a new private directory and twenty GiB reserve plus four GiB peak allowance.
Run models serially; preserve all original artifacts. Check source and generated
artifact hashes again on exit, including on failure.

A successful bounded comparison only selects a graph for a **separately frozen
full intended corpus comparison**, including every previously successful case.
It does not qualify OCR accuracy, real plans, CoreML/iOS execution or model
distribution. No full-corpus run or deployment promotion starts automatically.

## Actual result

Implementation/protocol commit before inference: `a958c96`. Run
`.local/runs/ocr-batchnorm-stage-20260926-s19-001` completed all twelve original
controls and 48 exact serialized-graph reload controls. All 74 retained artifacts
and all original source hashes were rechecked successfully. Eight new independent
graph/decision tests passed before execution. Every original BatchNorm mapped to
its unchanged native inference attributes; both transformations retained all
original parameters and public tensor identities.

| Variant | Optimizer | Numeric and token passes | Values outside tolerance |
|---|---|---:|---:|
| Division | Disabled | 11/12 | 1 |
| Division | All | 7/12 | 7 |
| Division plus two convolutions | Disabled | 10/12 | 2 |
| Division plus two convolutions | All | 8/12 | 6 |

All 48 candidate text-token comparisons match. All four previously passing
cases remain passing in every configuration. This does not override the failed
numeric gate: **neither variant is selected for full-corpus evaluation**. The
frozen width-640 `plan-053` title fails both unoptimized variants; the first full
training-run location case fails both fully optimized variants. The isolated
BatchNorm correction therefore does not resolve full-graph parity, and optimizer
effects remain material. The next OCR step is a separately frozen intermediate
trace of the remaining failure, with unchanged final-output controls.

Complete logs, clean source archive and result verification remain in
`.local/runs/ocr-batchnorm-graph-development-20260926-s19-001`. No app model, original
report, threshold, selected checkpoint or deployment registry changed.

Protocol SHA-256:
`cfe6f5f8a198544e2e4973d84249ecec371eb13e078941b257b46f4984426ec2`.

Report SHA-256:
`46644e38da56f3758d58367fb9e0bd03390d31dd791993ae116ce2f3a31b9590`.
