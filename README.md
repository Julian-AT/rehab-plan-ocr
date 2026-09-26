# Rehab Plan OCR

Local development tool for extracting appointments from printed schedules. Next.js App Router and shadcn/ui provide the workbench; Tauri 2 hosts a shared Rust pipeline with PP-OCRv6 and ONNX Runtime. No server is required by the packaged app.

## Development

Requires Node 22.22+, npm 11, Rust, `uv`, and the platform's Tauri prerequisites. iOS builds require Xcode and XcodeGen.

```sh
source "$HOME/.cargo/env"
npx --yes npm@11 ci
uv run scripts/fetch-models.py --tier small
npm run tauri -- dev
```

`npm run dev` starts Next.js at port 1420. Browser mode loads recorded synthetic fixtures; OCR, persistence, and calendar export require Tauri. `npm run build` produces a static export in `out/`.

The workbench contains:

- **Run:** image input, engine selection, appointment editing, source coordinates, traces, and calendar operations.
- **Dataset:** private inventory, reference annotations, batch experiments, and evaluation.
- **History:** retained scans, import ledger, failed runs, uncertain-write recovery, and deletion.
- **Configuration:** timezone, reminders, intermediate images, and detector parameters.

Review confirmation is required before export or calendar writes. Edits invalidate approval. iOS uses full EventKit access; desktop supports `.ics`. Therapist values are stored separately and included as `Therapeut: …` in calendar notes.

## Layout

```text
src/app/                   Next.js entry points and global theme
src/components/            Shared domain views and shadcn/ui primitives
src/features/              Workbench, calendar, and dataset workflows
src/hooks/                 Native environment and artifact loading
src/lib/                   IPC helpers, contracts, validation
crates/reha-core/          Portable inference, extraction, evaluation, storage
src-tauri/src/             Native commands, inference adapters, application state
plugins/calendar/          Swift camera, Photos, Vision, EventKit integration
scripts/                   Local model setup, dataset and benchmark tools
models/                    Public checkpoint/runtime lock manifests
licenses/                  Distributed dependency and model notices
tests/                     Synthetic fixtures, browser and native tests
docker/                    Non-Apple execution environment
docs/                      Architecture, requirements, evidence, research
```

Project-authored filenames use kebab-case. Framework entry points and required conventions such as `Cargo.toml`, `Package.swift`, `README.md`, and `next.config.ts` retain their standard names. Private data, generated projects, model weights, and builds are ignored.

## Native builds

```sh
npm run tauri -- build --bundles app
npm run tauri -- ios init --ci
sh scripts/build-ios.sh simulator
```

Desktop output: `target/release/bundle/macos/Reha Calendar Lab.app`. The simulator archive is under `src-tauri/gen/apple/build/`. `sh scripts/build-ios.sh device` checks unsigned arm64 device linking. To export a signed private build, use your available signing team:

```sh
APPLE_DEVELOPMENT_TEAM=<team-id> IPHONEOS_DEPLOYMENT_TARGET=17.0 \
  npm run tauri -- ios build --target aarch64 --ci --export-method debugging \
  --features ios-onnx -- --no-default-features
```

The current signed development package is `artifacts/private/builds/rehab-plan-ocr-lab.ipa`; its profile expires September 26, 2026. Re-sign after expiration.

Edit native source in `plugins/calendar/ios/Sources/`, not generated Xcode files. If regenerating an existing iOS project, remove or relocate `src-tauri/gen/apple/` first: XcodeGen can otherwise include old static libraries as duplicate resources. The app identifier stays `at.rehakalender.personal`, preserving local storage and calendar ownership.

## CLI and experiments

```sh
cargo build --release -p reha-core --features onnx-download
target/release/reha scan tests/fixtures/synthetic-day.png artifacts/private/example models/private/small
target/release/reha extract artifacts/private/example/run.json artifacts/private/extraction.json
```

`extract` reruns field parsing from recorded OCR without loading a model. Other commands: `evaluate LABEL RUN REPORT` and `ics APPROVED_RUN OUTPUT.ics`. See [dataset workflow](docs/dataset.md) for inventory, verified labels, frozen day groups, and batch evaluation.

## Verification

```sh
npm run lint
npm run build
npm test
npm run test:e2e
cargo test -p reha-core --features onnx-download
cargo clippy -p rehab-plan-ocr -p reha-core --all-targets -- -D warnings
uvx ruff check scripts tests/*.py
python3 tests/test-dataset.py
uv run tests/verify-ics.py
```

Browser tests serve the exported `out/` build in Chromium and mobile WebKit. Native tests in `tests/ios/` exercise an installed simulator build; calendar writes use invented appointments and are removed afterward. Linux execution uses `docker/portable.dockerfile` with networking disabled during inference.

Read [verification](docs/verification.md) and [status](docs/status.md) for measured results and remaining checks. Physical iPhone performance and clinic accuracy are not established. No model has been trained, and no final holdout has been evaluated.
