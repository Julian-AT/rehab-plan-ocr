> Historical record: technical findings retained from the archived development sequence. Project dates, build labels and source references have been normalized. This record is not a new test, delivery approval or signing attestation; unaltered evidence and original validity dates are held in the external private archive.

> Update: Laßnitzhöhe build 2026092602 is now installed on the iPhone, with the schema-2 → schema-5 migration and retained data verified. See [the current release record](lassnitzhoehe-release.md). The older binary must only be restored with its matching container backup; a binary-only rollback is no longer supported. The baseline record below describes the previous schema-2 release.

# Native iPhone migration — 11 September 2026

The native iOS 26+ app is implemented under `apple/`. It uses the production bundle identity and the existing local store. **Installed on the paired iPhone 17; launch and in-place data retention are verified. Full physical performance and accessibility acceptance remain pending.** The Tauri macOS, research, and iOS build paths remain available.

## Compatibility boundary

`reha-core::service` owns scan admission, cancellation, review validation, revisions, suggestions, settings, ICS, calendar proposals, ownership and write recovery. Tauri commands delegate to it with their existing names and payloads. The additional `revision` response and optional `expectedRevision` request field prevent the updated React client from overwriting newer reviews without changing persisted JSON.

`reha-ffi` exposes typed UniFFI 0.32.1 records and errors to Swift 6. Its runtime is process-wide; storage and inference run on workers. Explicit cancellation is tracked before job registration as well as during inference. The worker remains registered until inference actually stops, even if the 60-second budget returns a partial draft first. Job admission and destructive maintenance are serialized. Approved calendar transactions own their runtime task so disappearing UI cannot interrupt journal completion. Store locks are released before platform callbacks.

Field values preserve integer, unsigned integer, decimal, string, boolean and null JSON representations. This matters because stored values and approval hashes must survive the Swift round trip unchanged. Diagnostic model manifests remain opaque JSON. No SQLite schema migration was introduced; `user_version` remains 2.

`AppleServices` owns the existing EventKit queue, dedicated-calendar UserDefaults selection, reminder transfer journal, background refresh, camera/decoding and App Group snapshot. Both shells call it. Its shared presentation helper supplies current/next, all appointments today and stale status to SwiftUI and the Tauri iOS shell; browser previews retain their standalone mock calculation. Widgets and notification content reuse the same Swift presentation files and do not link OCR. Notification permission requests made from a settings draft do not activate scheduling until Save.

The app uses system Today/Plans tabs, separate navigation stacks, native forms and sheets, an editor dismissal guard, partial approval and calendar previews, source zoom/correction, ICS sharing and diagnostics. A completed scan offers a review action and leaves the current screen and any draft open. There is no long-lived display-image cache; source sheets load a downsampled image away from the main actor and release it with the sheet.

## Baseline preservation

The working tree already contained substantial changes. Before implementation, the complete tracked diff and untracked files were backed up locally to:

`/tmp/reha-native-baseline-20260926-s11-183501`

This includes `tracked.patch`, `untracked.tar.gz` and `status.txt`. Existing edits were not reverted or committed. Initial checks passed 71 Rust tests, 13 frontend unit tests and 52 Swift agenda policy checks.

## Verification evidence

The following checks are reproducible from the repository root:

| Check | Command / coverage |
| --- | --- |
| Shared core and FFI | `cargo test --locked -p reha-core -p reha-ffi`; includes retained data, stale approvals, journal reopen, numeric/hash compatibility and active-scan deletion protection |
| Existing frontend | `npm run verify`; lint, production build, frontend tests and core tests |
| Swift agenda policy | `sh scripts/test-agenda.sh`; 56 checks including completed events today, next-day appointments and DST boundaries |
| Swift/Rust integration | `sh scripts/build-native.sh integration`; real appointments/geometry, typed errors, revisions, partial approval, stable ICS identities, cancellation and uncertain-write reconciliation |
| Binding consistency | `sh scripts/build-native.sh check-bindings` |
| Native simulator UI | `sh scripts/build-native.sh test`; disposable simulator with public synthetic fixture, tabs/settings/cold launch, dirty draft preservation, source viewer and native ONNX recognition while changing tabs |
| Native unsigned linking | `sh scripts/build-native.sh device` |
| Legacy shell | `cargo check --locked -p rehab-plan-ocr`, `sh scripts/build-ios.sh simulator`, `sh scripts/build-ios.sh device` |
| Signed archive/package | `sh scripts/build-native.sh archive`; all app/extension signatures, identities, App Group, expiry, model and licence hashes checked by `scripts/package-native.py` |

Local results: **77 Rust tests, 13 frontend unit tests, 56 Swift policy checks, 12 agenda browser tests and 3 native simulator UI flows passed**. The strict Swift 6/Rust integration probe and binding consistency check passed. Native unsigned device linking and both legacy Tauri iOS build variants passed. The simulator recognition flow completed with the bundled ONNX model.

Local logs are in `/tmp/reha-*.log`. XCTest result bundles are under `apple/build/DerivedData/Logs/Test/`. Build products and logs are intentionally not tracked. The CI workflow in `.github/workflows/verify.yml` uses the same build entry points and keeps signing out of PR checks; it has not been run on GitHub during this session.

A real retained **simulator** installation was backed up before replacing its app bundle. Backup: `/tmp/reha-native-simulator-upgrade-20260926-s11-185348`, containing the previous application, private container, shared container and `before.json` / `after.json` database summaries. On native launch, `PRAGMA integrity_check` returned `ok`, and every serialized table hash matched before/after: 2 scans, 8 imports, 8 operations, 1 preferences row and 1 schedule. This establishes simulator in-place compatibility only; it does not establish physical-device acceptance.

The signed app preserves:

- App: `at.rehakalender.personal`
- Extensions: `.widgets` and `.notification-content`
- Team: `ZP2PFF43D2`
- App Group: `group.at.rehakalender.personal`
- Private storage: `Library/Application Support/at.rehakalender.personal`

The archive is `apple/build/Termine.xcarchive`; the installable package is `apple/build/Termine.ipa`. `apple/build/package-verification.json` records the verified package hash and actual provisioning expiry. The current profiles expire on 18 September 2026; re-sign and install before the earliest timestamp in that report. Keep the signing Mac and existing team access available for renewal.

## Remaining physical release gate

The initial build was completed while the iPhone was unavailable. The user subsequently connected it and explicitly requested the update. Native Termine 0.3.0, build 2026092601, was installed in place and launched successfully on 11 September 2026. The same native process remained running during the follow-up checks.

The complete private app directories and App Group contents were backed up to `artifacts/private/native-iphone-update-20260926-s11-191945`. That folder also preserves the previous signed Tauri 0.3.0 IPA and detailed installation/launch results. The package metadata was corrected to use the configured workspace version and build number; packaging now verifies those values for the app and both extensions.

At installation, all SQLite table rows matched the backup exactly: 11 scans, 44 imports, 44 operations, 5 schedules, 3 settings and 2 failures, with integrity `ok` and schema version 2. Forty-one persistent files were checked; only reminder-journal JSON key ordering differed, with identical decoded content. All 10 original photo files retained their hashes. After launch, all pre-existing scans and calendar records still matched. An additional scan and preference edits appeared after launch; those changes were retained.

The backup, installation and launch steps below are complete for this update. The remaining acceptance work is steps 3–5:

1. Back up the app's private container, preferences, reminder journal and App Group container locally using Xcode Devices and Simulators. Preserve the previous signed app. Confirm the backup can be read and retain it outside generated build folders. The app intentionally excludes its local store from ordinary iCloud backup.
2. Record SQLite integrity, table counts/hashes, calendar ownership IDs, dedicated-calendar defaults and both recovery journals. Install the verified signed package in place without uninstalling. Launch, resume and compare those records before performing real calendar writes.
3. Exercise camera and Photos imports, duplicate detection, cancellation/backgrounding with a retained draft, partial approval, stale edits, denied calendar/notification access, conflicts, explicit removals and uncertain-write reconciliation. Test widget and notification opening with the app warm and cold; confirm existing calendar alarms and app reminders recover without duplication.
4. Profile the Release build using Instruments SwiftUI, Time Profiler, Hangs and Hitches while scrolling and editing during recognition. Measure ordinary tap feedback against 100 ms; investigate every reproducible app-caused stall. Run 20 representative scans, recording recognition latency, peak/resident memory, thermal state and preservation of edits. Simulator UI tests are not performance measurements.
5. Check VoiceOver, largest Dynamic Type, dark mode, Reduce Motion, Reduce Transparency, hardware keyboard, interactive back navigation, source zoom/pan and the system camera/permission sheets. Record final visual acceptance on the physical device.

Keep the Tauri release path until all of these pass. If native acceptance fails, reinstall the preserved Tauri app in place; use the verified local container backup if restoration is required. Do not uninstall either shell as an upgrade or rollback step.
