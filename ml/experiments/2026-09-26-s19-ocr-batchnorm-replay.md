> Historical record: technical findings retained from the archived development sequence. Project dates, build labels and source references have been normalized. This record is not a new test, delivery approval or signing attestation; unaltered evidence and original validity dates are held in the external private archive.

# Same-input BatchNorm diagnosis

This protocol precedes execution. The [retained controlled trace](2026-09-26-s19-ocr-convolution-trace.md)
finds its first remaining difference at `p2o.pd_op.batch_norm_.0.0`, after an exact
first convolution. Only that frozen synthetic date crop at width 320 is examined.
It supplies no independent real-plan evidence.

The official CPU implementations for the pinned versions use different grouping
when forming the affine offset: Paddle multiplies mean, inverse standard deviation
and scale in sequence; ONNX Runtime multiplies mean by the already computed scale
coefficient. This is a concrete rounding hypothesis, not proof of the observed
difference. Compiler fusion and reciprocal/square-root implementation may matter
as well. Sources: [Paddle 3.3.1](https://github.com/PaddlePaddle/Paddle/blob/v3.3.1/paddle/phi/kernels/cpu/batch_norm_kernel.cc),
[ONNX Runtime 1.22.0](https://github.com/microsoft/onnxruntime/blob/v1.22.0/onnxruntime/core/providers/cpu/nn/batch_norm.h).
The retrieved files and hashes remain in the private research run
`.local/runs/ocr-batchnorm-research-20260926-s19-001/`.

The replay first requires copied-graph final outputs to equal their uninstrumented
controls, BatchNorm outputs to equal the retained tensors, the preceding operands
to be identical, and all four ONNX parameters to equal the saved Paddle parameters.
Both isolated native operations must then reproduce their stored output exactly.
A failed control stops the diagnosis. Inference attributes and NCHW layout must
agree; no training interpretation or alternate parameter values are accepted.

Exactly two graphs express the source-derived grouping using float32 primitive
operations, with graph optimization disabled. Both are compared to both native
outputs. Even exact agreement establishes only this isolated diagnostic result;
it does not validate a full graph or optimized deployment. Nonagreement remains
explicit. There is no search over coefficients, precision, epsilon or thresholds.
The existing `rtol=1e-3`, `atol=1e-5` gates remain unchanged. No model replacement,
full-corpus run or promotion follows automatically.

```sh
make prepare-ocr-batchnorm-replay DIAGNOSTIC_RUN=.local/runs/<new-run>
make diagnose-ocr-batchnorm-replay DIAGNOSTIC_RUN=.local/runs/<prepared-run>
```

Preparation performs no inference. Execution requires twenty GiB reserve plus two
GiB temporary capacity and a separate serial model window after simulator work.
Originals and historical reports remain hash-checked. Complete controls, isolated
graphs, inputs, parameters and outputs are retained; copied full graphs are removed.
