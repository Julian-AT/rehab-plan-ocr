> Historical record: technical findings retained from the archived development sequence. Project dates, build labels and source references have been normalized. This record is not a new test, delivery approval or signing attestation; unaltered evidence and original validity dates are held in the external private archive.

# Isolated strided-convolution replay

This protocol is fixed before execution. The controlled
[activation trace](2026-09-26-s20-ocr-batchnorm-trace.md) first differs at
`p2o.pd_op.conv2d.3.0`, with a byte-identical concatenation input. Its retained
report SHA-256 is
`197b54e49f2bf92ab848d2d87c34c10ea1bdc1229c3864ea8585dd7c1da06bca`.
This is one previously used synthetic development case, not independent evidence.

First require identical saved inputs from both runtimes, unchanged converted and
native FP32 weights, and a direct Paddle convolution reproducing its saved graph
output byte for byte. Isolate the original ONNX Constant/Conv nodes with unchanged
attributes; ORT_DISABLE_ALL must reproduce its retained graph output byte for
byte. A failed control stops the experiment before any correction claim.

The only proposed change is an explicit patch-to-matrix transformation for this
3×3, stride-two, group-one, NCHW convolution with symmetric padding one and
dilation one. Slice padded input at stride two in channel/kernel-row/kernel-column
order; multiply by the constant transposed FP32 weight matrix and reshape back.
Neither operand, summation precision nor reference output changes. Reject other
geometry, dtype, shapes, bias, nonfinite values or changed weights.

Before the retained case, check four independent exact integer stencils: zero,
ramp and impulses in the upper-left and lower-right corners, with odd and even
spatial dimensions and distinct channel weights. All candidate outputs must
equal these independent sums byte for byte. Then the retained candidate must
equal saved Paddle byte for byte, at both ORT_DISABLE_ALL and ORT_ENABLE_ALL.
Save and reload each optimized graph; every reload must be byte-identical to its
initial output. Use the pinned CPU provider, two intra-op/one inter-op threads,
host and package identities. Preserve inputs, outputs and all candidate graphs.

The existing numeric contract remains rtol=1e-3, atol=1e-5. A numeric pass cannot
override a byte-control failure. Any candidate failure stops this lowering; do
not tune the protocol or automatically apply it to the complete graph. Even a
successful isolated result requires a separate full-graph protocol, all twelve
previously selected controls (including prior passes), and eventually the full
corpus. No export, model or real-plan qualification follows from this experiment.

```sh
make prepare-ocr-strided-convolution DIAGNOSTIC_RUN=.local/runs/<new-run>
make diagnose-ocr-strided-convolution DIAGNOSTIC_RUN=.local/runs/<prepared-run>
```

Preparation performs no inference. Commit the tested implementation and protocol
before execution. Execution requires 20 GiB free reserve plus four GiB planned
peak and a quiet window without simulator or other model work. The source inputs
are hash-bound and checked again on exit, including failures. Existing reports,
originals, weights and deployed models remain unchanged.

## Observed result (20 September 2026)

Execution at clean source `b00f3a8` completed in the quiet window after the four
UI regressions. All four original controls reproduced byte for byte, including
the 737,280-value input, 41,472 weights and both 92,160-value primitive outputs.
This confirms that the runtime difference also exists in an isolated operation
with identical inputs and weights. It does not establish the cause of the final
full-graph tolerance failure.

All eight integer-geometry comparisons and all ten optimized-graph reloads pass
byte for byte. The retained MatMul candidate differs from Paddle at both levels:
maximum absolute error 7.62939453125e-05, with zero values outside the unchanged
numeric tolerance. The predeclared byte gate therefore **fails**. This lowering
is stopped; no full-graph candidate was generated or selected. A smaller maximum
error alone does not establish a valid deployment export.

All 106 frozen sources and 27 generated artifacts were rechecked.
The private run is `.local/runs/ocr-strided-convolution-20260926-s20-001`, with
protocol SHA-256 `bc19e3fae350fe038870307abfe49e5f217b8e5ee893b1336dfef28805caff59` and
report SHA-256 `aebaedfa6d8d0d2ca4ace1702376d64323070243570b5b20abb2fa40fa1a46a9`.
The development directory retains the clean source archive, six successful
geometry/gate tests, documentation checks and execution log. Model qualification
remains failed/open; historical model weights and reports were not changed.
