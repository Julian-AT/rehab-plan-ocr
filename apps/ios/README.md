# Native iPhone application

XcodeGen creates the app and its three extensions from `project.yml`. Shared Apple
packages live in `packages/apple`, and the domain/FFI in `packages/rust`. Run all
commands from the source root; follow [setup](../../README.md#prerequisites-and-setup).

```sh
make convert TARGET=all
make build TARGET=simulator
make check-bindings
make build TARGET=device
make test-ios
```

The standard build links the pinned OCR/ONNX runtime and uses Apple system speech.
`make bindings` explicitly enables UniFFI's `bindgen` feature. `make check-bindings`
compares generated Swift and headers with committed files; the native binding
probe exercises actual Swift/Rust calls. Generated sources must not be edited.

The optional [Victoria profile](../../docs/development/personal-victoria.md) uses
`private-victoria.yml`, a separate generated RehaCore package and the original
stored voice key. Experimental assistant trials have their own project overlay.
Neither changes the default `make build` selection.

The identifier `at.rehakalender.personal`, extension IDs, App Groups and storage
under `Library/Application Support/at.rehakalender.personal` remain compatible.
SQLite schema 11 and JSON document schema 3 retain the existing migrations,
import evidence and settings. Calendar writes still require visible confirmation.

## Tests and builds

Simulator tests use synthetic fixtures and disposable iPhone 17 devices. The
local profile requires iOS 26.4 / 23E244; the explicit CI profile requires iOS 26.5 /
23F77. A missing runtime fails instead of selecting another version. These checks
do not establish minimum-iOS-26.0 coverage or physical-device reliability.

`make verify-bundle APP_BUNDLE="<app path>" TARGET=simulator` checks app and extension
resources, model hashes, privacy manifests and notices. Use `TARGET=device` for an
unsigned device build. Visual checks retain the
[existing references](../../docs/product/visual-baseline/README.md).

For explicitly authorized signed work, `make archive RELEASE_RUN=.local/releases/<new-name>`
reserves immutable output, and `make package` verifies it. Signed builds require
local signing configuration. No build command installs on a phone. Device updates
require approved previews/listening, a fresh backup, an update without uninstalling,
and comparison of persistent data. See [build contracts](../../docs/development/build-reproducibility.md).
