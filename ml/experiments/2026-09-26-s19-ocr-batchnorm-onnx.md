> Historical record: technical findings retained from the archived development sequence. Project dates, build labels and source references have been normalized. This record is not a new test, delivery approval or signing attestation; unaltered evidence and original validity dates are held in the external private archive.

# Explicit ONNX division after the ARM64 diagnosis

This protocol precedes saved-tensor execution. The
[hardware-division diagnostic](2026-09-26-s19-ocr-batchnorm-reciprocal.md) reproduces
the first saved Paddle BatchNorm output exactly. This follow-up tests one
ordinary ONNX representation on that same intermediate; no complete OCR model,
weights, app resource or registry selection changes.

Copy the retained Paddle-grouped primitive graph and replace only its sole
`Reciprocal(stddev)` with `Div(one, stddev)`, where `one` is scalar FP32 1.
Keep all original constants, epsilon, shape, node identities and other operations.
ONNX [Div](https://onnx.ai/onnx/operators/onnx__Div.html) supports scalar
broadcasting and retains the input element type. This mathematical contract
alone does not guarantee identical runtime rounding, which is measured here.

Run exactly two host configurations: `ORT_DISABLE_ALL` and `ORT_ENABLE_ALL`,
CPUExecutionProvider, two intra-op threads and one inter-op thread. First require
the original primitive graph at **both** levels to reproduce its saved output
byte-for-byte. Only then evaluate the copied division expression at both levels
against saved native Paddle and the exact C hardware-division output. Keep the
existing `rtol=1e-3`, `atol=1e-5` measurements beside strict byte equality.

For every run, retain the actual
[optimized graph](https://onnxruntime.ai/docs/performance/model-optimizations/graph-optimizations.html)
and reload it with optimization disabled. Reloading must reproduce the original
run byte-for-byte. These graphs describe this pinned host/runtime; they are not
portable deployment artifacts. A failed original or reload control stops the
diagnosis. Candidate disagreement is reported as failure to demonstrate the
correction, without trying other graph forms or adjusting thresholds.

```sh
make prepare-ocr-batchnorm-onnx DIAGNOSTIC_RUN=.local/runs/<new-run>
make diagnose-ocr-batchnorm-onnx DIAGNOSTIC_RUN=.local/runs/<prepared-run>
```

Preparation freezes the rule, source chain, previous report/outputs, packages,
machine/compiler and this human protocol without inference. Commit implementation
and protocol before executing saved tensors. Execution needs a new private run,
twenty GiB reserve plus two GiB peak allowance and a serial model window. Preserve
all outputs, original source hashes, graph identities and failures. Independent
synthetic arithmetic/broadcasting and transformation-rejection tests run first.

Even if both candidate outputs are exact, full-graph optimizer effects and the
complete intended corpus remain separate gates. No model promotion or automatic
full-corpus run follows from this intermediate diagnostic.
