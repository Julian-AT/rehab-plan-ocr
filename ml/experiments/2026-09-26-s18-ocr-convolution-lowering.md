> Historical record: technical findings retained from the archived development sequence. Project dates, build labels and source references have been normalized. This record is not a new test, delivery approval or signing attestation; unaltered evidence and original validity dates are held in the external private archive.

# Isolated OCR convolution lowering experiment

This protocol is declared before inference. It neither qualifies an OCR model nor
changes the selected weights, dynamic Paddle reference, original reports or
`rtol=1e-3` / `atol=1e-5` comparison. No training is involved.

The [operation diagnosis](2026-09-26-s18-ocr-operation-parity.md) retains two isolated
FP32 convolution fixtures with identical input/weights and different Paddle/ORT
outputs. The experiment uses only these saved arrays, without loading Paddle or
the archive's float64 reference. Report hashes fix the exact frozen/full fixtures.

## Hypothesis and fixed transformation

Paddle's CPU convolution expands image patches before BLAS GEMM. The installed
wheel links Apple Accelerate. ORT 1.22's segmented convolution uses a K-block size
of 128; the first divergent 2x2 convolution has K=192. Its packed MatMul path uses
K-blocks of 256. Avoiding the extra partial-sum boundary might reproduce the
Paddle FP32 result. This is a hypothesis, not a demonstrated cause or correction.

The only candidate expands the same patches using Pad/Slice/Concat and evaluates
`(Xcol.T @ W.T).T` with unchanged FP32 values and a constant right weight matrix.
Channel/kernel order and SAME_UPPER padding remain explicit. The original graph
and archive are hash-checked before and after. Both candidate and original-control
replays use ORT 1.22 CPU, two intra-op threads, one inter-op thread, graph
optimization disabled and default enabled weight prepacking. No settings sweep.

Primary sources:

- [Paddle CPU convolution](https://github.com/PaddlePaddle/Paddle/blob/7688495538f4d6c1893f084dd238a402e8f68ab6/paddle/phi/kernels/impl/conv_kernel_impl.h).
- [ORT segmented convolution](https://github.com/microsoft/onnxruntime/blob/v1.22.0/onnxruntime/core/mlas/lib/convolve.cpp#L500), [block sizes](https://github.com/microsoft/onnxruntime/blob/v1.22.0/onnxruntime/core/mlas/lib/mlasi.h), [packed GEMM](https://github.com/microsoft/onnxruntime/blob/v1.22.0/onnxruntime/core/mlas/lib/sgemm.cpp#L1333).
- [ORT constant-right-operand packing](https://github.com/microsoft/onnxruntime/blob/v1.22.0/onnxruntime/core/providers/cpu/math/matmul.cc#L160).

## Predeclared decision

Both retained Paddle output arrays must match byte-for-byte, including signed
zero. Four fixed integer geometry cases (zero, asymmetric ramp, top-left impulse,
bottom-right impulse) must match their exact integer stencil oracle. Original
ONNX replay must reproduce its stored ONNX output byte-for-byte; otherwise the
comparison is invalid. A merely smaller error or a passing allclose is insufficient.

Any failure stops this approach. Experiment 2 must not start. A pass only permits
planning that separate small experiment; it does not qualify a deployment export.
No experiment 2 is launched by this tool. Full-corpus and physical-device gates
remain required for any eventual deployment candidate.

`convolution_lowering.py prepare --output <new-private-run>` writes immutable input
identities, constructed graphs and `protocol.json` without inference. The separate
`execute --output <same-run>` phase verifies those identities before replay and
writes `report.json`. Interrupted/completed executions cannot silently be repeated
in the same directory. The two retained source directories are fixed in the tool.

## Result

The predeclared experiment passes. Both retained output arrays are byte-identical
to their saved Paddle reference, with no differing FP32 bit patterns:

| Fixture | Shape | Values | Candidate maximum error | Original Conv maximum error |
| --- | --- | ---: | ---: | ---: |
| Frozen | 1×24×24×160 | 92,160 | 0 | 0.00000762939453125 |
| Full | 1×24×24×320 | 184,320 | 0 | 0.00000762939453125 |

All four integer geometry cases are also byte-identical, including signed zero.
Both original-Conv controls reproduce their saved ONNX arrays byte-for-byte.
All source and prepared-artifact hashes remain unchanged. The tool runs no Paddle
model and does not load the stored float64 reference. No inference process remains.

Private evidence is in `.local/runs/ocr-convolution-lowering-20260926-s18-001`:

- Pre-inference protocol SHA-256: `654110b225a78e0576bc1c12b39ec3e423d7c238315ba3d82f4b911fc4300025`.
- Completed report SHA-256: `461952c1d6f4c01d0c075b82565ae24c93867732a22e38cd13423a2a46b8205b`.
- Protocol/tool commit before execution: `c41d65e`.

This establishes a successful lowering for these two saved operations only. It
does not isolate K-blocking from every other kernel/layout difference, establish
full-model parity, preserve dynamic-width export automatically or measure device
resources. The candidate graphs have the fixed fixture shapes. The separate
reparameterization difference and possible later runtime differences remain open.
The original 18/1,206 frozen, 39/1,206 full and 19/1,206 baseline parity failures
are unchanged. `qualified` remains false; experiment 2 has not started.

Seven new tests cover retained weight bytes, graph geometry, unsupported inputs,
integer-oracle boundaries, changed-source rejection and the strict decision rule.
Four existing operation tests, four documentation checks and Ruff pass.
