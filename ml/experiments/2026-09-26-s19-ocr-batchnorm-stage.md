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
