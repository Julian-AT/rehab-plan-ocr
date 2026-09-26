> Historical record: technical findings retained from the archived development sequence. Project dates, build labels and source references have been normalized. This record is not a new test, delivery approval or signing attestation; unaltered evidence and original validity dates are held in the external private archive.

# ARM64 reciprocal diagnosis

This protocol is frozen before executing retained model tensors. The previous
[affine-contraction diagnostic](2026-09-26-s19-ocr-batchnorm-fma.md) left the first
BatchNorm difference unresolved. This experiment changes only reciprocal
arithmetic on that same saved synthetic crop, with the same input, parameters,
FP32 epsilon, offset grouping and separate final multiplication/addition.

The [Paddle 3.3.1 Eigen pin](https://github.com/PaddlePaddle/Paddle/blob/v3.3.1/cmake/external/eigen.cmake)
is `f612df273689a19d25b45ca4f8269463207c4fee`; the
[ONNX Runtime 1.22.0 pin](https://github.com/microsoft/onnxruntime/blob/v1.22.0/cmake/deps.txt)
is `1d8b82b0740839c0de7f1242a3585e3390ff5f33`. In the latter's
[NEON implementation](https://gitlab.com/libeigen/eigen/-/blob/1d8b82b0740839c0de7f1242a3585e3390ff5f33/Eigen/src/Core/arch/NEON/PacketMath.h),
packet reciprocal uses an estimate and exactly two refinement steps. Hardware
division is a distinct instruction sequence. Source files, URLs and hashes are
retained in `.local/runs/ocr-eigen-research-20260926-s19-001`.

Static inspection of the installed ARM64 libraries supports that hypothesis:
Paddle's FP32 CPU BatchNorm coefficient loop uses `fsqrt` then `fdiv`; ORT's
uses `fsqrt`, `frecpe` and two `frecps`/`fmul` steps. The bounded function listings,
library hashes and commands are retained. Static inspection alone does not trace
runtime dispatch; exact saved-tensor controls remain mandatory.

Exactly two modes are declared:

| Mode | Inverse standard deviation | Remaining arithmetic |
| --- | --- | --- |
| Reciprocal control | Hardware square root; NEON estimate and two refinements | `scale * inverse`; `bias - ((mean * inverse) * scale)`; separate affine output |
| Hardware division | Hardware square root; `1 / sqrt(variance + epsilon)` | Identical grouping and separate affine output |

Both use ARM64 FP32 instructions, FE_TONEAREST, no FP32 flushing and
`-fno-fast-math -ffp-contract=off`. The fixed shape is `1×48×24×160` and each
parameter contains 48 channels. Invalid, nonfinite and subnormal inputs are
rejected. Independent exact synthetic arithmetic and invalid-input controls
must pass before saved model tensors run.

The first mode must reproduce all three saved affine coefficients from the FMA
diagnostic and both its separate C output and the earlier primitive graph output
byte-for-byte. Any mismatch stops before the second mode. Both modes are compared
with the original saved Paddle and ONNX tensors using strict byte equality and
the unchanged `rtol=1e-3`, `atol=1e-5` contract. No search, precision change,
epsilon change, threshold change, export modification or corpus expansion occurs.

```sh
make prepare-ocr-batchnorm-reciprocal DIAGNOSTIC_RUN=.local/runs/<new-run>
make diagnose-ocr-batchnorm-reciprocal DIAGNOSTIC_RUN=.local/runs/<prepared-run>
```

Preparation freezes code, machine/compiler, library identities, previous reports,
artifacts and upstream provenance without tensor execution. Commit implementation
and this protocol before execution. The execution target requires twenty GiB
reserve plus two GiB peak capacity and a serial diagnostic window. Output must be
a new private run directory. All earlier sources are hash-checked before and after;
the run retains its C++ source/library, compiler invocation, coefficients, outputs
and report, including failed controls. No Paddle or ORT inference session is run.

Even byte-exact agreement establishes only this intermediate diagnostic. A later
export correction still requires its own frozen protocol, full intended corpus
including previous successes, deployment runtime checks and the independent
quality gates. No model is promoted by this experiment.

## Actual result

Implementation/protocol commit before execution: `038fa30`. The run
`.local/runs/ocr-batchnorm-reciprocal-20260926-s19-001` passes all five byte-exact
controls: three affine coefficients, the retained primitive graph output and
the earlier separate C output. All protected source hashes remain unchanged.

Hardware division reproduces **all 184,320 saved Paddle values byte-for-byte**,
with zero maximum error. The reciprocal control retains the previous maximum
Paddle difference of `9.5367431640625e-7`; hardware division differs from the
saved native ONNX output by that same maximum. Both remain within the unchanged
intermediate tolerance. No native inference session or full-model/corpus run
was executed, and no deployment graph or model was changed.

This identifies the reciprocal arithmetic as the remaining explanation for this
first BatchNorm tensor when the Paddle offset grouping is retained. It does not
prove that every later operation or optimized deployment graph has the same
cause. An ONNX-level correction must separately reproduce the native control,
survive the deployment optimizer and pass the entire intended corpus.

Seven independent arithmetic/rejection tests passed before execution. Compiler,
machine, library/source identities, prepared human protocol, all four coefficient
vectors per mode and both outputs are retained. The development checks and clean
source archive are in `.local/runs/ocr-reciprocal-development-20260926-s19-001`.

Protocol SHA-256:
`6d9b242b86a30c7d2552027a58973850e59709a26ed936fdd75112440182ec91`.

Report SHA-256:
`2c0dee07dcb9fc4f3da274ef867621e2458bc9f636b79110d0111580f88c40e0`.
