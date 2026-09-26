> Historical record: technical findings retained from the archived development sequence. Project dates, build labels and source references have been normalized. This record is not a new test, delivery approval or signing attestation; unaltered evidence and original validity dates are held in the external private archive.

# Explicit FP32 contraction diagnosis

This protocol precedes execution. The [same-input BatchNorm replay](2026-09-26-s19-ocr-batchnorm-replay.md)
preserves identical input and parameters but rules out coefficient regrouping alone
as a demonstrated correction. This follow-up uses only those saved tensors from
the first BatchNorm on the same synthetic date crop at width 320. It supplies no
new independent plans and performs no full-model inference.

Both pinned CPU implementations end with an affine multiplication and addition.
Paddle also computes its offset from a product followed by subtraction. These are
two concrete contraction sites in the retained [Paddle source](https://github.com/PaddlePaddle/Paddle/blob/v3.3.1/paddle/phi/kernels/cpu/batch_norm_kernel.cc)
and [ONNX Runtime source](https://github.com/microsoft/onnxruntime/blob/v1.22.0/onnxruntime/core/providers/cpu/nn/batch_norm.h).
Explicit `std::fma` tests whether single-rounding arithmetic explains this tensor;
it does not prove how the distributed Paddle binary was compiled.

The unchanged Paddle-grouped primitive graph exposes its three affine
intermediates. Its original output must remain byte-identical to the saved output.
A C++ reference then uses these exact coefficients and the saved input in FP32.
Implicit contraction is disabled with `-fno-fast-math -ffp-contract=off`, in that
order; see the [Clang floating-point contract](https://clang.llvm.org/docs/UsersManual.html#controlling-floating-point-behavior).
Only explicit `std::fma` may fuse arithmetic. The separate C++ control must
reproduce the primitive graph byte-for-byte before candidate comparisons proceed.
FE_TONEAREST, the fixed NCHW shape and finite normal-or-zero operands are required.

Exactly four modes are fixed before execution:

| Mode | Offset | Final output |
| --- | --- | --- |
| Separate control | Retained primitive coefficient | Separate multiply and add |
| Fused output | Retained primitive coefficient | `fma(input, adjusted_scale, offset)` |
| Fused offset | `fma(-mean_times_inverse, scale, bias)` | Separate multiply and add |
| Both fused | Fused offset | Fused output |

No coefficient search, changed precision, epsilon or tolerance is permitted.
The existing `rtol=1e-3`, `atol=1e-5` comparisons are reported beside strict byte
equality. Any failed control stops the run. All four outputs are compared against
both saved native outputs; nonagreement remains explicit. Even exact agreement
qualifies only this diagnostic tensor, not an export or the complete model.

```sh
make prepare-ocr-batchnorm-fma DIAGNOSTIC_RUN=.local/runs/<new-run>
make diagnose-ocr-batchnorm-fma DIAGNOSTIC_RUN=.local/runs/<prepared-run>
```

Preparation freezes source hashes, packages, compiler identity and flags without
inference. Execution requires the untouched prepared directory, twenty GiB reserve
plus two GiB temporary capacity and a serial model window. It retains the native
reference source/library, compiler command, all coefficients/outputs and the report.
Original sources and previous reports are hash-checked before and after execution.
There is no automatic full-corpus run, model rewrite or promotion.
