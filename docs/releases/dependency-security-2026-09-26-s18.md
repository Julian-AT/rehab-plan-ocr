> Historical record: technical findings retained from the archived development sequence. Project dates, build labels and source references have been normalized. This record is not a new test, delivery approval or signing attestation; unaltered evidence and original validity dates are held in the external private archive.

# Dependency security review — 2026-09-26

The reviewed iOS dependency closure has no matching RustSec vulnerability entry.
Two maintenance warnings remain. A separate review of native dependencies found
missing SQLite fixes and upgraded the bundled engine from **3.50.2 to 3.53.2**.
ONNX Runtime remains **1.22.0**, with specific upstream hardening work recorded
below. This review does not qualify the final app, model quality, device behavior,
or distribution rights.

The [machine-readable evidence](dependency-security-2026-09-26-s18.json) records input
hashes, retrieval times and hashes, the RustSec commit, tool identity, original and
updated dependency results, model identities and verification logs. Raw public
responses and test output are retained under
`.local/audits/dependencies-2026-09-26-s18`. No patient data were read or uploaded.

## Scope and method

The active selection is `reha-ffi`, feature `onnx`, target `aarch64-apple-ios`, with
iOS 26.0 still the app minimum. The generated runtime inventory was checked before
the change, explicitly regenerated afterward and independently recomputed offline.
The updated closure contains **135 packages: 108 target dependencies and 27 build
dependencies**; two target packages are first-party. These counts describe Cargo
reachability, not code proven present in the linked executable. The complete
`Cargo.lock` was audited too: 232 entries before, 231 afterward, including inactive
platform/development dependencies.

`cargo-audit 0.22.2` scanned all 1,251 advisories in RustSec commit
`2b34578f89884736e0fcbd42f7ba8d6b10b4a0ce`, committed on 2026-09-26. No advisory was
ignored and no target filter concealed other lockfile findings. The preserved
offline scan skips registry yank checks; a second normal scan gave the same
advisory result. No fresh registry-wide yank certification is claimed. RustSec
alone does not cover vulnerabilities inside the C/C++ sources bundled by a crate.
[RustSec database](https://github.com/RustSec/advisory-db/tree/2b34578f89884736e0fcbd42f7ba8d6b10b4a0ce),
[cargo-audit](https://github.com/rustsec/rustsec/tree/main/cargo-audit).

The active Swift packages are local `RehaCore`, `AppleServices` and `VoiceActivity`.
They introduce no fetched Swift package dependency. Apple's EventKit, Speech,
FoundationModels and audio services are OS components, not copied libraries with
an app-controlled version. Their deployed OS/voice identities still belong in the
device qualification record. The experimental `LocalAssistant` package,
Kokoro/eSpeak, training environments and host listening tools are outside the
public app selection. This review does not audit every Python training environment.

## SQLite change and data compatibility

The former `libsqlite3-sys 0.35.0` archive embeds SQLite 3.50.2 and enables FTS5.
Upstream identifies CVE-2025-7709 as fixed in 3.50.3, and the duplicate identifiers
CVE-2026-11822/CVE-2026-11824 as fixed in 3.53.2. The first requires a malicious FTS5
database; the second requires arbitrary SQL execution with FTS5 and defensive mode
disabled. The app creates its own ledger, uses no FTS tables, does not import
arbitrary SQLite files and does not expose a SQL interpreter. No app exploit was
demonstrated. Removing the old native implementation is nevertheless preferable
to relying indefinitely on those usage restrictions.
[SQLite's assessment](https://www.sqlite.org/cves.html).

The smallest published release pair containing both the native fixes and the
wrapper's savepoint-name escaping is **rusqlite 0.40.1 / libsqlite3-sys 0.38.1**:

| rusqlite release | Bundled SQLite | Decision |
|---|---|---|
| 0.38.0 | 3.51.1 | Does not include the 3.53.2 fixes |
| 0.39.0 | 3.51.3 | Does not include the 3.53.2 fixes |
| 0.40.0 | 3.53.1 | Does not include the 3.53.2 fixes or savepoint escaping |
| 0.40.1 | 3.53.2 | Selected |
| 0.40.2 | 3.53.2 | Only lowers the Rust minimum; unnecessary with pinned Rust 1.98.1 |

Sources: [0.38.0](https://github.com/rusqlite/rusqlite/releases/tag/v0.38.0),
[0.39.0](https://github.com/rusqlite/rusqlite/releases/tag/v0.39.0),
[0.40.0](https://github.com/rusqlite/rusqlite/releases/tag/v0.40.0),
[0.40.1](https://github.com/rusqlite/rusqlite/releases/tag/v0.40.1),
[0.40.2](https://github.com/rusqlite/rusqlite/releases/tag/v0.40.2).

The exact wrapper version and lockfile preserve that choice. Explicit `cache` and
`fallible_uint` features retain the existing statement cache and checked `u64` /
`usize` conversions; the new default WASM backend is unnecessary on supported
Apple targets. The app does not use the changed virtual-table APIs. The only
transitive changes are the required `hashlink`/`foldhash` updates and consolidation
onto the already present `hashbrown 0.17.1`. License bodies are byte-identical to
the former declarations; generated notices update package identities only.

No schema, stored JSON format, journal, file path or migration changed. SQLite
documents backward compatibility with existing database files; this is not
permission to downgrade an application's schema without its matching backup.
[SQLite file-format policy](https://www.sqlite.org/formatchng.html).

Verification used the existing workspace environment with one compiler job:

- All **206 reha-core tests passed**, with zero failures/ignored tests. These cover
  legacy migrations, rollback after failed migration, interrupted initialization,
  exact retained JSON/preferences, approvals, calendar journals, undo/recovery,
  archive backfills and reopening.
- Two new tests check the engine actually linked on the host meets SQLite 3.53.2
  and that unsigned archive counts reject negative/out-of-range values.
- Ten runtime-inventory tests passed. `make check-runtime-inventory` reproduced
  all inventory and notice bytes. A post-update RustSec scan retained zero
  vulnerability matches and the same two maintenance warnings.
- `cargo check --locked --offline -p reha-core --features onnx --target
  aarch64-apple-ios` passed with `IPHONEOS_DEPLOYMENT_TARGET=26.0` and one compiler
  job. It compiles the selected Apple-target dependencies without building an app.
- The final native bundle and device database update remain separate acceptance
  steps. Host tests do not establish the linked engine in a yet-unbuilt iOS app.

## Rust maintenance findings

| Finding | Active scope and evidence | Disposition |
|---|---|---|
| `paste 1.0.15`, RUSTSEC-2024-0436 | Build-only procedural macro through `simba → nalgebra → imageproc` | No published vulnerability in this notice. Track replacement through a qualified upstream dependency update. |
| `ttf-parser 0.25.1`, RUSTSEC-2026-0192 | Target dependency through `owned_ttf_parser → ab_glyph → imageproc` | No published vulnerability in this notice. Own code uses imageproc geometry/warping/contours and exposes no font parser/import. Link-time removal was not measured. Track removal or maintained upstream replacement. |

Neither warning is suppressed or described as fixed.
[paste notice](https://rustsec.org/advisories/RUSTSEC-2024-0436.html),
[ttf-parser notice](https://rustsec.org/advisories/RUSTSEC-2026-0192.html).

## Native OCR and VAD

The pinned iOS ONNX Runtime archive is 1.22.0, used through `ort/ort-sys
2.0.0-rc.10`. Its published dependency list pins ONNX 1.17.0, Protobuf 21.12 and
FlatBuffers 23.5.26. Public repository-advisory queries returned no entries for
ONNX Runtime or FlatBuffers. This is limited evidence: later ONNX Runtime releases
explicitly contain security fixes, so an empty advisory list is not clearance.
[Pinned source dependencies](https://github.com/microsoft/onnxruntime/blob/v1.22.0/cmake/deps.txt),
[ORT advisories](https://github.com/microsoft/onnxruntime/security/advisories),
[ORT 1.28 security changes](https://github.com/microsoft/onnxruntime/releases/tag/v1.28.0),
[ORT 1.30 changes](https://github.com/microsoft/onnxruntime/releases/tag/v1.30.0).

The two OCR model hashes match `small.lock.json`. Both graphs have no external
initializer files, local functions or nested graph attributes. The app loads
models from its bundle; document import cannot select a model. The detector input
is batch 1 with three channels and spatial sides bounded by 2,560. Recognition is
one to eight crops, three channels, height 48 and padded width at most 3,200.
Pixels do not control graph operator attributes or initializer metadata.

| Upstream finding | Applicability to this app selection |
|---|---|
| CPU convolution allocation overflow, ORT #29444 | Conv is used. The reported trigger needs extreme shape products; app tensor bounds and fixed model topology constrain them. No exploit shown. Include this fix in the next independently qualified ORT candidate. |
| Resize validation, ORT #28779 | The detector uses six Resize nodes; all scale inputs are fixed finite initializers, ROI initializers empty and no axes override. The reported malformed scale/ROI/axes inputs cannot come from a photo. |
| Nested graph depth, ORT #32344 | The bundled graphs have no nested graphs/functions; untrusted model loading is absent. |
| ONNX CVE-2026-14647 / #8051 | Shape/attribute validation in convolution shape inference. Graph ranks and attributes come from the pinned models, not document content. Remains part of runtime update qualification. |
| ONNX Python external-data/hub findings; version-converter findings | Those Python APIs and opset conversion are absent from the app. This conclusion does not qualify development conversion tools. |
| Protobuf CVE-2024-2410 | Upstream says the C++ JSON-stream defect was introduced in 4.22.0; the ORT source pin is 3.21.12 (tag v21.12), before that introduction. The app also exposes no Protobuf JSON-stream API. |
| Protobuf CVE-2026-0994 | Python JSON parser path, not the native iOS C++ reader. |

Sources: [convolution fix](https://github.com/microsoft/onnxruntime/pull/29444),
[Resize fix](https://github.com/microsoft/onnxruntime/pull/28779),
[depth fix](https://github.com/microsoft/onnxruntime/pull/32344),
[ONNX shape fix](https://github.com/onnx/onnx/pull/8051),
[ONNX advisories](https://github.com/onnx/onnx/security/advisories),
[Protobuf C++ advisory](https://github.com/protocolbuffers/protobuf/security/advisories/GHSA-h5g9-ghrj-76p5),
[Protobuf Python advisory](https://github.com/advisories/GHSA-7gcm-g887-7qv7).

This is source-based reachability assessment, not a complete native sanitizer
audit. An ORT update still requires the full fixed-model parity/quality corpus,
bounded-input failures, iOS minimum-version build and performance measurements.
Changing the binary without those checks would invalidate existing OCR evidence.
No ORT version was changed in this slice.

The vendored `libfvad` revision
`532ab666c20d3cfda38bca63abbb0f152706c369` equals upstream `master` at retrieval.
The public advisory list was empty. Its scope is the extracted VAD engine, not
WebRTC networking/video. `InputAudio` supplies exactly 320 PCM16 samples at 16 kHz
per call. General browser/WebRTC advisories cannot establish a match to this
subset; no specific published libfvad vulnerability was identified by these
sources. [Upstream source](https://github.com/dpirch/libfvad),
[public advisories](https://github.com/dpirch/libfvad/security/advisories).

## Reproduce the Rust review

Restore the pinned Cargo dependencies using the documented setup, install the
reviewed cargo-audit tool, and use a fresh local destination:

```sh
git clone https://github.com/RustSec/advisory-db.git .local/audits/rustsec-recheck
git -C .local/audits/rustsec-recheck checkout 2b34578f89884736e0fcbd42f7ba8d6b10b4a0ce
cargo-audit audit --no-fetch --no-yanked --db .local/audits/rustsec-recheck --file Cargo.lock --json
make check-runtime-inventory
```

For a new candidate, fetch a new advisory snapshot, record its exact commit and
repeat the native-source review. Do not silently overwrite this dated evidence.
