> Historical record: technical findings retained from the archived development sequence. Project dates, build labels and source references have been normalized. This record is not a new test, delivery approval or signing attestation; unaltered evidence and original validity dates are held in the external private archive.

# Trace the remaining corrected-graph OCR failure

This protocol is fixed before model execution. The previous
[complete graph comparison](2026-09-26-s19-ocr-batchnorm-stage.md) failed its unchanged
numeric contract even after explicit BatchNorm division and two convolution
lowerings. No candidate was selected for the full corpus. This experiment only
localizes the first remaining **mapped byte difference** in the unoptimized
corrected graph; it does not select or promote a new graph.

Select the first failing `division-convolution-ORT_DISABLE_ALL` case in the
unchanged twelve-case order. Require the complete, unique, correctly ordered
stage evidence, all original/reload controls and unchanged sources. The frozen
stage report SHA-256 is
`46644e38da56f3758d58367fb9e0bd03390d31dd791993ae116ce2f3a31b9590`.
This selects frozen-backbone `plan-053:synthetic-053-0-09-title-0`, width 640,
from the already used synthetic development group. It is not independent data.

Before tracing, reproduce the saved normalized input, deployed original ONNX
output with all optimizations, and corrected candidate output with optimization
disabled. Unfused static Paddle must reproduce the saved dynamic Paddle output.
Every comparison requires the same shape, dtype and **C-order bytes**, including
the sign of zero. A mismatch stops execution before any intermediate claims.
The pinned host, package versions, source graphs, parameters, inputs, saved
outputs and helper implementations remain unchanged and hash-bound.

Copy the retained unfused PIR and corrected ONNX graph; append only fetches for
16 aligned float outputs at a time. Use the existing name/SSA mapping, pinned
CPU provider and two intra-op/one inter-op threads. Disable ONNX graph rewrites
throughout intermediate diagnosis. After every batch, compare both complete
instrumented outputs against the unchanged complete-output controls byte for
byte. A perturbed control stops the trace and invalidates its localization.

Stop after the first batch containing any mapped byte difference, or after all
mapped outputs if none differs. Report omitted native outputs explicitly. An
unmapped earlier output prevents a claim that the earliest native operation was
established. Preserve all tensors, including final controls, and both instrumented
graphs for the stopping batch; identify original parameter files by hash.
Retain graph/fixture hashes and verify every frozen source again on exit,
including failed execution. Do not change parameters, operation grouping,
optimizer configuration, selection or thresholds during this experiment.

Numeric measurements retain `rtol=1e-3`, `atol=1e-5`; they do not override byte
controls. Final text-token parity and model qualification remain governed by the
previous contract. An early activation difference need not cause the final
out-of-tolerance value and is not itself proof of a defective operation. A
subsequent same-input primitive replay needs its own frozen comparison.

```sh
make prepare-ocr-batchnorm-trace DIAGNOSTIC_RUN=.local/runs/<new-run>
make diagnose-ocr-batchnorm-trace DIAGNOSTIC_RUN=.local/runs/<prepared-run>
```

Preparation runs no inference. Commit protocol and implementation before the
second command. Execution requires 20 GiB reserve plus four GiB planned peak;
run separately from simulator measurements and other model work. Existing
historical reports and hash-bound helper sources are preserved unchanged.
This is a bounded failure diagnosis, not OCR accuracy, export, real-plan or
physical-device acceptance. Full-corpus evaluation does not start automatically.
