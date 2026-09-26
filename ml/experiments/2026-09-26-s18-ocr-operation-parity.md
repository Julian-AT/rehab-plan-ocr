> Historical record: technical findings retained from the archived development sequence. Project dates, build labels and source references have been normalized. This record is not a new test, delivery approval or signing attestation; unaltered evidence and original validity dates are held in the external private archive.

# OCR operation-level export diagnosis — 18 September 2026

This investigation does not qualify a deployment artifact. The original 1,206-case
reports, selected weights, saved Paddle graphs and ONNX exports remain unchanged.
The comparison still uses `rtol=1e-3`, `atol=1e-5` and exact CTC token agreement.

## First reproducible divergence

The first retained failing frozen-backbone case is a synthetic date crop at width
320. Appending intermediate fetches to a copy of the saved PIR graph maps 302
float32 outputs to the converter's ONNX output names. The original operators and
parameters are preserved. Direct `paddle.static.Executor` fetching crashes in the
pinned local Paddle 3.3.1 installation, including a one-output probe; loading the
copied graph through the existing `paddle.jit.load` route works.

In the initial all-output diagnostic, the input and first convolution agree
bit-for-bit. The second convolution, `p2o.pd_op.conv2d.1.0`, is the first rounding
difference: maximum absolute error 0.00000762939453125, still within the unchanged
comparison tolerance. Its 2×2 kernel uses stride one, dilation one and SAME
padding. The converted weights match the saved Paddle weights bit-for-bit.

An isolated ONNX graph with those exact weights and the same intermediate input
reproduces the difference. Direct Paddle convolution matches the saved graph
exactly. 72,596 output values differ between runtimes. Compared with a float64
convolution of the same float32 input and weights, maximum absolute errors are
0.000009658794272837667 for Paddle and 0.000007042129556822374 for ONNX. These
figures concern this operation and input only; they do not establish end-to-end
accuracy or justify replacing the reference runtime.

The first intermediate tolerance violation in that initial trace occurs later,
at `p2o.pd_op.depthwise_conv2d.6.0`; subsequent layers amplify the differences.
Identical parameters and same-input kernel replay establish arithmetic drift at
the first differing operation, rather than a changed export parameter. No export
correction or relaxed threshold follows from that observation.
This isolates the first divergence; it does not rule out independent differences
in later operators.

Private exploratory evidence is in
`.local/runs/ocr-operation-investigation-20260926-s18-001/`: source scripts, failed
Executor logs, intermediate summaries and `second-convolution.npz` with the
isolated ONNX graph. All inputs are existing synthetic development data.

## Reproducible tracing contract

[`operation_parity.py`](../evaluation/recognition/operation_parity.py) validates
existing training lineage, dataset pixels, checkpoint selection and full prior
parity evidence before tracing. It rejects unknown PIR serialization and retains
source hashes before and after execution. Additional fetches are tested to leave
the original operators, parameter identities and exporter ordinals unchanged.

The tool defaults to 32 intermediate outputs per batch and handles cases serially.
It reports fetched tensor bytes and host peak resident memory. Reproducible batch
graphs are removed after collecting their hashes; the minimal isolated operation,
tensors and final diagnostic report remain local. Uninstrumented controls expose
any change to CTC output caused by the instrumentation itself. Such a change is
reported explicitly and cannot silently become evidence about the original graph.

## Controlled retained-failure results

The completed traces use batches of 16 outputs, CPU execution, two intra-op
threads and one inter-op thread. All 302 mapped intermediates were compared for
each retained failure. Every instrumented CTC output is bitwise equal to its
uninstrumented provider control in every batch. The first rounding difference is
`p2o.pd_op.conv2d.1.0` in all 57 cases. Each run also reproduces its first case's
convolution with identical input and weights in isolation; direct Paddle matches
the saved graph bit-for-bit.

| Run | Traced crop/width cases | Source groups | Bitwise control comparisons | Numeric failures with graph optimization disabled | Peak host RSS |
| --- | ---: | ---: | ---: | ---: | ---: |
| Frozen backbone | 18 | 17 | 684 / 684 | 11 / 18 | 1,281,966,080 bytes |
| Full adaptation | 39 | 38 | 1,482 / 1,482 | 6 / 39 | 1,286,422,528 bytes |

The cases are synthetic development crops, not independent real plans; the two
runs share source data. All CTC argmax tokens agree. The disabled-optimization
counts concern only the retained failures and do not establish that the other
cases still pass in that runtime configuration. Original shipping-configuration
reports remain failed at 18/1,206 and 39/1,206 respectively. The original graphs,
weights, selection, dataset and reports were hash-checked before and after each
trace and remain unchanged. No alternative export or deployment candidate was
created, so there is no proposed correction to submit to a new full-corpus gate.

In the frozen run, the first intermediate tolerance violation occurs at
`conv2d.7.0` for 12 cases, `add.32.0` for three, and `depthwise_conv2d.6.0`,
`add.30.0` and `add.14.0` for one each. Full adaptation has 12 distinct first
tolerance-violation outputs; `conv2d.7.0` accounts for 12 cases. These later
violations do not change the first-operation finding or exclude additional
operator-specific differences later in the network.

The largest simultaneously fetched tensor payload was 43,678,784 bytes. Each
completed directory retains only its report, isolated ONNX operation and tensor
fixture: 3,476,317 bytes for frozen and 6,512,125 for full adaptation. Batch copies
were removed. These are host diagnostic memory figures, not iPhone performance
measurements.

Both runs also successfully revalidated all 603 existing synthetic v2 records,
pixel/receipt replay and the original training lineage. Dataset SHA-256:
`7314061c5104738dea1da2f627fea27fa30612372c4402968bfe700cce073ef6`.
This is the shared legacy-adapter compatibility check; it adds no real-data
approval or new validation coverage to the historical dataset.

Private reports and their SHA-256 identities:

| Report below `.local/runs/` | SHA-256 |
| --- | --- |
| `ocr-operation-smoke-20260926-s18-001/report.json` | `ae89d2967b49780d70dc67e6790aba8e01cd0d7a4d58a0c42d8a5c1882871a89` |
| `ocr-operation-frozen-20260926-s18-001/report.json` | `b17c28f4068cb5e02317ab443ad382b1c7d7be5249b028ae729a3b5781bcf67b` |
| `ocr-operation-full-20260926-s18-001/report.json` | `b82f3ce31b38f250b76a8255db2765a5b2e89e39d5629f83ac1fc46842752793` |

The full-adaptation trace ran through the documented Make entry point, including
its storage-reserve guard:

```sh
make diagnose-ocr-operation-parity RUN=.local/runs/ocr-synthetic-full-001 \
  DIAGNOSTIC_RUN=.local/runs/ocr-operation-full-<new> \
  OCR_TRACE_BATCH=16 ALL_FAILURES=1
```

Four portable regression tests cover immutable source operations, fresh fetch
identities, stable exporter ordinals across batches, rejected unsupported graphs,
and the distinction between first rounding difference and first tolerance
failure. Ruff and Python compilation pass. The resulting diagnostic remains
`qualified: false`; it cannot replace the full 1,206-case deployment gate or
physical iOS evaluation.
