> Historical record: technical findings retained from the archived development sequence. Project dates, build labels and source references have been normalized. This record is not a new test, delivery approval or signing attestation; unaltered evidence and original validity dates are held in the external private archive.

# Runtime notices and dependency inventory

`licenses/manifest.json` pins every notice bundled by `apps/ios/project.yml`.
Native packaging verifies those hashes and the bundled runtime inventory. Source-adjacent notices in the isolated
VoiceActivity package remain required for its copied C implementation.

`runtime-inventory.json` records the actual `reha-ffi` iOS dependency selection with
the `onnx` feature: 136 normal/build packages, including 109 packages reachable by
normal edges without procedural macros. Two are first-party workspace packages.
These are dependency-graph counts, not measurements of linked code or installed
size. Inactive optional Cargo metadata entries are excluded. Versions, archive
checksums, selected features, declared licenses, notice sources and target/build
scope are recorded per package. Shared texts are deduplicated in the bundled
`licenses/rust-dependencies.txt`; SQLite's amalgamation declaration is retained
separately from its Rust wrapper's MIT license.

`make inventory-runtime` explicitly regenerates the inventory offline using the
restored Cargo registry. `make check-runtime-inventory` recomputes it and rejects
any difference. `make verify-runtime-inventory` only reads committed source and
notice hashes; lint and normal native builds use this inexpensive check. Add
`APP_BUNDLE=<built-app>` to verify the actual copied inventory and complete notice
set. Packaging rejects a stale inventory, missing/extra/altered notices or a bundle
that differs from the reviewed sources. Generation is never part of a normal build.

The inventory pins runtime model locks, native source identities, vendored VAD
files and build declarations. Apple system models are recorded as OS-provided;
their weights are not exposed. Training environments and experimental checkpoints
are outside this app inventory. License expressions reflect upstream declarations,
and a checksum check does not decide redistribution compatibility. The workspace
declares MIT but does not yet have a publisher-approved root license notice;
publisher/rights review and the eSpeak-NG decision remain explicit release gates.

| Runtime component | Source of version/identity | Bundled notices |
|---|---|---|
| PP-OCRv6 recognizer/detector | `ml/registry/runtime/small.lock.json` | PaddleOCR |
| ONNX Runtime and Rust binding | `ios-runtime.lock.json`, `Cargo.lock` | ONNX Runtime, third-party notices, ort |
| Victoria/Kokoro and vocabulary | `kokoro.lock.json`, `victoria-source.lock.json` | Kokoro model/source and tokenizer |
| eSpeak-NG phonemizer | `tooling/build/build-phonemizer.py` | GPL text and Kokoro source/build notice |
| WebRTC VAD / libfvad | `packages/apple/VoiceActivity/README.md` | LICENSE, AUTHORS and PATENTS |
| UniFFI | `Cargo.lock` | MPL text and source notice |
| Unicode normalization | `Cargo.lock` | MIT notice |

This is an inventory of retained runtime notices, not public-distribution clearance.
The current native binary still includes eSpeak-NG. The public release gate in the
[ledger](../development/implementation-plan.md) remains open. Model-development
dependencies are separately locked under `ml/training` and are not app dependencies;
Qwen development artifacts remain unqualified and unbundled.

On 2026-09-26, a consumer inventory covered workspace manifests/lockfiles, Xcode
resources, tracked JavaScript/HTML, native/Rust sources, build/release scripts and
historical reports. The only retained HTML is the self-contained palette decision;
there is no React, Next, Radix, Tailwind, shadcn, Zod, Lucide or Tauri runtime/source.
Fourteen notices belonging solely to those removed implementations, including the
duplicate React texts, were removed from the active bundle. Their original hashes
and Git revision are in the [retirement inventory](../releases/history/retired-assets.json).
