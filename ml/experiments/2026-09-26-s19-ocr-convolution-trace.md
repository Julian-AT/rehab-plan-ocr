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
reuse a started run.

## Actual result

Protocol/tool commit before inference: `73263f0`. Run
`.local/runs/ocr-convolution-trace-20260926-s19-001` reproduced all three historical
optimized comparisons exactly. The candidate still fails one of 748,400 values
with unchanged tokens; the original unfused control still passes this case.
Disabling optimization does not close the candidate gate: one value still fails,
with maximum absolute difference 0.00006449222564697266.

The selected dynamic Paddle output and saved unfused Paddle output are bitwise
equal. All sixteen fetched outputs in the first batch preserve both providers'
complete control output bit-for-bit. The first convolution is exact. The first
remaining rounding difference is the immediately following BatchNorm output
`p2o.pd_op.batch_norm_.0.0`, program index 340: maximum absolute difference
0.00000095367431640625 across 184,320 values, with no intermediate tolerance
violation. No earlier float output is unmapped. This identifies the earliest
operation in the explicitly unoptimized diagnostic configuration; it does not
attribute all later error to this operation or qualify the optimized deployment.

Execution stopped after the first sixteen of 302 mapped outputs as predeclared.
The report and first differing tensors are retained; temporary batch graphs are
removed. All protected source hashes remain unchanged. No new model, threshold
or full-corpus result was produced. The next bounded investigation should replay
this BatchNorm with identical operands and parameters before proposing a change.

Protocol SHA-256:
`0120c777ae5087a24b8da74665edad055664ebd4ead54d97c5c5967cf5454527`.

Report SHA-256:
`3445922ce35f5f1961df9e1db39a570acbd47b5c57c558f65391dd7cd44595ac`.
