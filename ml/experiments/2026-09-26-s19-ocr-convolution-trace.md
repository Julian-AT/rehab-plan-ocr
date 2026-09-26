> Historical record: technical findings retained from the archived development sequence. Project dates, build labels and source references have been normalized. This record is not a new test, delivery approval or signing attestation; unaltered evidence and original validity dates are held in the external private archive.

# Retained convolution failure: bounded intermediate diagnosis

This protocol precedes execution. It investigates only the first failed case of
the [retained full-graph experiment](2026-09-26-s18-ocr-convolution-stage.md): frozen
`plan-020:day-20-0-date-0`, width 320. It creates no replacement deployment model.
Original weights, graphs, pixels and historical reports remain hash-checked.

First reproduce all three previous complete-output comparisons under the original
optimized runtime: deployment, unfused control and retained convolution candidate.
Then require the saved unfused Paddle program to equal the selected dynamic model
bit-for-bit on this input. A failed control ends the diagnosis.

Intermediate tracing uses copies, at most sixteen float32 outputs per batch and
ONNX graph optimization disabled. Each batch must retain the final output of both
its uninstrumented Paddle and ONNX control bit-for-bit. The first batch containing
a rounding difference ends the trace. Unmapped earlier outputs prevent a claim
to have established the earliest operation. Perturbed instrumentation supplies no
such claim at all. Temporary batch graphs are reproducible and removed; the
first differing tensors, control results, operation identities and hashes remain.

The diagnostic configuration is explicitly separate from deployment optimization.
Its first observed difference does not identify the first optimized-runtime
difference. Numeric thresholds remain `rtol=1e-3`, `atol=1e-5`, with exact CTC
tokens. This one synthetic development crop is not independent real-plan evidence,
and no outcome qualifies a model or starts a full-corpus run automatically.

```sh
make prepare-ocr-convolution-trace DIAGNOSTIC_RUN=.local/runs/<new-run>
make diagnose-ocr-convolution-trace DIAGNOSTIC_RUN=.local/runs/<prepared-run>
```

Preparation performs no inference. Execution runs serially after simulator work,
requires the twenty-GiB reserve plus two GiB temporary capacity, and refuses to
reuse a started run. Actual results remain pending until execution.
