> Historical record: technical findings retained from the archived development sequence. Project dates, build labels and source references have been normalized. This record is not a new test, delivery approval or signing attestation; unaltered evidence and original validity dates are held in the external private archive.

# Isolated ONNX Runtime upgrade comparison

The complete historical comparison of ONNX Runtime 1.22.0 against 1.30.0
finished all **3,618 cases** with passing technical controls, but **failed the
unchanged numerical gate**. Runtime 1.30.0 is not promoted. No active dependency
pin, environment, model, graph or registry was changed, and no native/iOS build
was performed.

The private Python candidate reused the reference's NumPy 2.5.3, Flatbuffers
25.12.19, Packaging 26.3 and Protobuf 7.36.1. Its official non-yanked macOS ARM64
ORT wheel was verified against the published SHA256 before installation. Each
of the pretrained, frozen and full historical models was evaluated on the same
603 images at widths 320 and 640. Weights, preprocessing, CPU provider,
`ORT_ENABLE_ALL`, two intra-op/one inter-op threads and serial execution order
were fixed. Every output value was compared using `rtol=1e-3`, `atol=1e-5`,
matching shapes, finite values and exact argmax tokens.

| Model | Cases | ORT 1.22 numerical passes | ORT 1.30 numerical passes | Old pass → new fail | Old fail → new pass |
|---|---:|---:|---:|---:|---:|
| Pretrained | 1206 | 1187 | 1180 | 8 | 1 |
| Frozen | 1206 | 1188 | 1188 | 3 | 3 |
| Full | 1206 | 1167 | 1173 | 0 | 6 |
| **Total** | **3618** | **3542** | **3541** | **11** | **10** |

There are 77 candidate failures: 66 previously failing cells plus 11 regressions;
10 previously failing cells now pass. All 11 regressions occur at width 640.
All 3,618 token comparisons, shape checks and finiteness checks pass. Equal tokens
do not override the numerical failures. The complete historical ORT 1.22
shape/allclose/token decision vectors are reproduced. All per-case metrics and
tensor hashes in each of the three comparison relations are identical between
the separately executed runs 001 and 002.

## Technical controls and evidence

Run 001 remains failed. Its final distribution-discovery dictionary changed when
Paddle imported Setuptools and exposed bundled metadata through `sys.path`,
although all package files remained identical. The separately frozen 002
inventory uses explicit `purelib`/`platlib` roots and unique metadata locations.
It records installed and bundled distributions separately; dynamic discovery
and actually loaded module origins are diagnostic observations.

In 002, both environment controls pass. The reference's 17,650 file/interpreter
hashes and the candidate's 1,363 hashes are unchanged before/after and equal to
001. All 706 bound inputs and execution bindings remain unchanged. Reference
discovery expands from 50 to 62 distribution records, while the fixed inventory
remains 50 installed plus 12 bundled distributions. The actually loaded Packaging
module remains version 26.3. This bookkeeping correction does not turn 001 or
the independently negative numerical result into a pass.

The complete private output is
`.local/runs/onnxruntime-130-historical-comparison-20260926-s21-002`:

- Protocol SHA256:
  `79004321b0da6197bab0bc2e2323244a43537c51d93125c761d79ff21489287d`.
- Report SHA256:
  `24d3160a0a5273fd87a7fcf3d430a7f00a3e02b75e859876c975b57bbf4f4e81`.
- Execution receipt at
  `.local/maintenance/onnxruntime-upgrade-20260926-s21-001/execution-20260926-s21-002/receipt.json`,
  SHA256 `242a9ba66566ebc3663074748f1c7ebad396e03d367b205f0e742d5ca9df361e`.

That receipt binds all 3,649 execution/evidence files. Its summary retains every
case transition, all 11 regression identities and the complete empty token-change
list. The 001 evidence and 002 preparation were separately verified unchanged.
The run returned exit 1 with `status=completed`, `complete=true`, `passed=false`.

This is numerical compatibility evidence for the Python runtime, not model
quality, native/iOS, security-remediation or deployment qualification. A bounded
LLVM read-only inventory ran concurrently under separate authorization, so no
timing or performance qualification follows. The acquired native archive was not
executed. Canonical promotion remains blocked by the numerical regressions;
the [dependency review](../../docs/development/dependency-audit.md) retains that
open status.
