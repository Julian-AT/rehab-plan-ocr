# Rehab Plan OCR

Local app for extracting and reviewing appointments from printed schedules. It opens with a minimal German interface; the development workbench remains under **Einstellungen → Entwickleransicht öffnen**. Next.js static export and shadcn/ui share one application state; Tauri 2 hosts the Rust pipeline with PP-OCRv6 and ONNX Runtime. No server is required by the packaged app.

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

On iOS, **In Kalender übernehmen → Kalender verbinden** creates or reuses a separate calendar and selects it for new imports. Its events can be shown or hidden together in Apple Calendar's calendar list. Existing imports retain their recorded destination. See [iPhone installation and calendar setup](docs/ios-installation.md).

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

Signed development packages are stored under `artifacts/private/builds/`. See [iPhone installation](docs/ios-installation.md) for the current version and signing expiry.

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

## Simple review interface (0.2.0)

Cold launches open **Foto aufnehmen**, **Importieren** and recent plans. Use **Einstellungen → Entwickleransicht öffnen** for the existing workbench. Complete appointments can be saved while unfinished ones remain pending. The iPhone label is **Termine**; the existing bundle and calendar are preserved. See [delivery, migration and verification](docs/simple-app-delivery.md) and [local model experiments](experiments/vlm/README.md).
