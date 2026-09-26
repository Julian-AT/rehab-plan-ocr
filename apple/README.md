# Termine for iPhone

Native SwiftUI shell for iOS 26+, using the same local Rust workflows and Apple services as the Tauri app. macOS and the research workbench remain in Tauri.

- `Termine/`: feature-scoped presentation models and system SwiftUI navigation.
- `Packages/RehaCore/`: generated UniFFI 0.32.1 bindings, headers and the local XCFramework reference.
- `Packages/AppleServices/`: the shared EventKit, reminder journal, background refresh, camera/photo and widget presentation implementation. The old Tauri plugin forwards to this package.
- `../crates/reha-core/src/service/`: shared scan jobs, settings, review, ICS and calendar transactions.
- `../crates/reha-ffi/`: typed records, errors, callbacks and the native shell's long-lived Tokio runtime.

## Build and test

Use Xcode 26.4 or later, an arm64 Mac, Rust (validated with 1.98.1), `xcodegen`, `uv` and the existing Node dependencies. Install the Rust targets once:

```sh
rustup target add aarch64-apple-ios aarch64-apple-ios-sim
sh scripts/build-native.sh simulator
sh scripts/build-native.sh device
sh scripts/build-native.sh integration
sh scripts/build-native.sh test
sh scripts/build-native.sh check-bindings
```

Run commands from the repository root. `test` creates and removes its own simulator and seeds only the public synthetic plan. `integration` compiles a real Swift 6 host against Rust and tests appointments, scalar/geometry conversion, revisions, approval, ICS identities, cancellation and write recovery. `check-bindings` fails if committed bindings differ from generated output.

`framework` creates separate arm64 iOS and arm64 simulator XCFramework variants. Each combines the Rust library with the checksum-pinned ONNX Runtime 1.22.0 static library. Models and licence files are bundled; no model loads before the UI appears. Simulator and device libraries are never combined into one platform slice.

`project.yml` is the source for the Xcode project. Generated projects and build products are ignored. CI runs the same entry point; ordinary PR checks do not sign or deploy.

## Private archive

```sh
sh scripts/build-native.sh archive
```

This uses the existing signing team and generates `apple/build/Termine.xcarchive`, `Termine.ipa` and `package-verification.json`. Packaging verifies signatures, app/extension identities, App Group entitlements, profile validity, model checksums and bundled licences. The validation copy is made outside the file-provider-managed workspace to avoid Finder metadata invalidating strict signature checks.

Use `package-verification.json` for the actual profile expiry dates. Rebuild and sign before the earliest expiry, then install in place. Do not uninstall the existing app: its data intentionally remains local and excluded from iCloud backup.

If Xcode keeps an expiring profile, open the generated project, connect the registered iPhone, and use the existing team with automatic signing to renew the app and both extension profiles. Then run `archive` again and confirm that the report shows renewed dates before installing.

## Migration and cutover

The production identity remains `at.rehakalender.personal`, with the existing widget and notification extension IDs and `group.at.rehakalender.personal`. `AppStorage.prepare()` still resolves `Library/Application Support/at.rehakalender.personal`. SQLite schema version 6 adds plan acceptance records; version 7 adds the separate confirmed event-mutation journal. Both preserve stored pipeline JSON, historical approval hashes, calendar ownership markers, UserDefaults and recovery journals.

An unavailable calendar is displayed as unavailable; it is not treated as proof of deletion. Calendar comparison records no human approval. One save action accepts the displayed ready selection and durably journals its write intent; unresolved appointments remain for later. Pending and uncertain operations are reconciled before a new proposal. Swift cancellation signals the individual job, while approved calendar transactions retain an owned runtime task to finish bookkeeping.

Physical-device acceptance is still a release gate. See [migration evidence and remaining checks](../docs/native-iphone-migration.md). Keep the Tauri release available until that gate passes.

See [one-confirmation behavior and verification](../docs/one-confirmation.md).

Build 2026092605 adds per-plan calendar selection, separate display preferences, external event editing/undo and local German voice assistance. It is installed on the iPhone 17, with backup and schema-7 data retention verified. See [implementation, test results and remaining device acceptance](../docs/calendar-voice-implementation.md).

Build 2026092606 replaces system TTS with bundled German Supertonic 3 voices and repairs menu presentation and playback actions. See [UI refresh and verification](../docs/ui-voice-refresh.md).

Build 2026092607 adds the monochrome native interface with a dedicated Sprechen tab and checksum-pinned offline Kokoro/Martin (24 kHz). It is installed on the iPhone 17 after approval, backup and data-retention verification. See [device delivery and remaining audio acceptance](../docs/kokoro-device-update.md) and [preview and verification](../docs/apple-voice-preview.md). eSpeak-NG is statically linked for phonemes only; the corresponding-source and GPL notices are in `licenses/kokoro-source.txt`.

Build 2026092608 adds the native weekly day timeline, quiet voice surface and ordered immediate settings persistence. See [implementation and verification](../docs/native-minimal-iphone.md). It is installed on the iPhone 17 after explicit approval, a fresh backup and a successful [retained-data comparison](../docs/native-minimal-device-update.md).

Build 2026092609 adds the requested offline Victoria voice, green appointment blocks and a 06:00–18:00 timeline. Ten UI tests, the calendar projection probe and 60 core tests passed. [Preview and implementation](../docs/victoria-calendar-update.md). Build 2026092609 is installed on the iPhone 17 without uninstalling; a fresh backup, successful launch and full retained-data comparison are verified.

Build 2026092610 adds day swipes, complete location/therapist labels, persistent calendar density, a green fluid audio-reactive orb, direct on-device dictation without an app-managed speech asset installer, local free conversation and the native Apple camera. [Implementation and preview acceptance](../docs/fluid-calendar-voice.md). The device update awaits preview approval.
