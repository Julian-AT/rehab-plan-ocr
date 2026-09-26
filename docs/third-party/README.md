> Historical record: technical findings retained from the archived development sequence. Project dates, build labels and source references have been normalized. This record is not a new test, delivery approval or signing attestation; unaltered evidence and original validity dates are held in the external private archive.

# Runtime notices and dependency inventory

`licenses/manifest.json` pins every notice bundled by `apps/ios/project.yml`.
Native packaging verifies those hashes. Source-adjacent notices in the isolated
VoiceActivity package remain required for its copied C implementation.

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
