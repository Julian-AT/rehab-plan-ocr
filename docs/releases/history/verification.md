> Historical record: technical findings retained from the archived development sequence. Project dates, build labels and source references have been normalized. This record is not a new test, delivery approval or signing attestation; unaltered evidence and original validity dates are held in the external private archive.

> Historical record. Commands, installed versions and acceptance claims below describe their original date only. The [current implementation ledger](../../development/implementation-plan.md) governs ongoing work. Retired media is recoverable from Git; see [the archive inventory](retired-assets.json).

# Verification — Next.js workbench, 2026-09-26

These checks verify the development implementation. They do not establish clinic-wide accuracy or physical iPhone acceptance. Private logs, screenshots, and run outputs are under `artifacts/private/refactor/`.

## Current checks

| Check                                                  | Result                                                                                                         |
| ------------------------------------------------------ | -------------------------------------------------------------------------------------------------------------- |
| Next.js 16.3.4 static production export                | Passed; Tauri packages `out/`                                                                                  |
| ESLint, TypeScript, Prettier, Rust formatting, Ruff    | Passed                                                                                                         |
| Frontend unit tests                                    | 8 passed                                                                                                       |
| Chromium and mobile WebKit tests against static export | 8 passed                                                                                                       |
| Rust core tests with ONNX feature                      | 36 passed                                                                                                      |
| Core and Tauri Clippy, warnings denied                 | Passed                                                                                                         |
| Dataset integrity and frozen split tests               | 4 passed; synthetic temporary data only                                                                        |
| Independent iCalendar parser                           | Passed: approval gate, seven selected events, repeated appointments, stable UIDs, UTC, escaping, UTF-8 folding |
| macOS native bundle                                    | Built: `target/release/bundle/macos/Reha Calendar Lab.app`                                                     |
| iPhone 17 / iOS 26.4 simulator bundle                  | Built and installed; Next.js hydration and native IPC exercised                                                |
| Packaged simulator XCTest                              | 2 passed, 0 skipped: portable OCR/persistence; EventKit creation and duplicate prevention                      |
| Linux arm64, network disabled                          | 8 appointments, 32 observations, 1,255 ms including model load                                                 |
| macOS portable CLI synthetic scan                      | 8 appointments, 32 observations, 956 ms including model load                                                   |

The simulator calendar test creates seven invented events, confirms a second import creates no duplicates, and removes its created events afterward. Browser tests cover review invalidation, therapist edits, repeated items, source highlights, unavailable trace stages, offline edits, annotation verification, and absence of external content requests.

Single-run timings are functional measurements, not p95 or model comparisons. A simulator cold run displayed 4,638 ms; simulator performance does not substitute for physical-device evidence.

## Extraction regression

Recorded OCR from the reported retained scan was re-extracted locally, without changing the stored scan or raw observations. The revised parser recovers 10 timed rows versus 7 previously, supplies the reported treatment date on all 10, removes `*Neu` from structured values, and joins three multiline therapist fields. The check covers one known problematic input and is not a paper-verified accuracy benchmark.

Committed synthetic tests cover split weekday headings, conflicting dates and weekday disagreement, invalid dates, `Neurologie` preservation, multiline therapist/title columns, parallel appointments, and timed treatments containing header-like words such as “Blutdruck” and “Aufnahme”. Room numbers are excluded from time parsing when column headers are known. Legacy annotations default the additive therapist field to empty; calendar notes preserve new therapist values.

## Native evidence

- Simulator archive: `artifacts/private/refactor/ios-simulator.xcarchive`.
- Simulator build log: `ios-simulator-build.log`.
- Successful XCTest result: `native-next-fixed.xcresult`; log: `native-next-fixed.log`.
- Desktop build log: `macos-build.log`.
- Device archive/export log: `ios-device-build.log`.
- Original signed private IPA: `artifacts/private/builds/rehab-plan-ocr-lab-0.1.0.ipa`; `codesign --verify --deep --strict` passed after extraction outside the synced workspace. Profile expires **2026-09-26 10:57 UTC**. Verification: `signing-check.json`.

Build environment: Apple M4 Pro / 24 GiB, Rust 1.98.1, Node 22.22.3, npm 11, Xcode 26.4 (17E192), Swift 6.3, ONNX Runtime 1.22.0, `ort` 2.0.0-rc.10. Deployment minimum is iOS 17. Native models use the portable CPU adapter; no Apple recognition is required.

During the initial build checks, the paired physical iPhone 17 was unavailable. Subsequent installation evidence is recorded below. No physical latency percentile, memory-pressure, thermal, or repeated-scan acceptance result is claimed.

## Data and remaining checks

After the workbench refactor, the user authorized exploratory processing of the images in `verify/`. All 20 unique HEIC originals were converted to full-resolution PNG and processed locally; an exact HEIC duplicate and the existing PNG were excluded from the denominator. Originals remain unchanged. [The real-image baseline](real-image-baseline.md) records the results, conversion checks and private review artifacts. This was not a verified accuracy benchmark or final holdout evaluation.

No verified development benchmark, final holdout, training, or VLM qualification has been performed. Physical camera/HEIC and calendar flows, full accessibility testing, native revision/failure fault injection, Apple/Google `.ics` imports, and device-level content-network inspection remain open. Earlier synthetic robustness probes are retained privately but have not been rerun as a fresh accuracy benchmark for this refactor.

Original targets remain unchanged: ≥99% critical date/time accuracy, ≥99% appointment precision/recall, ≥90% schedules without correction, and physical iPhone p95 ≤30 seconds.

## Version 0.1.1 — dedicated iOS calendar

The iOS app now creates or reuses **Reha Calendar** for new imports, with its account shown in the destination selector. A saved calendar is reused after renaming; unavailable or ambiguous calendars require resolution instead of creating duplicates. Existing imports keep their recorded destination. Clearing app data also clears the local calendar reference without deleting calendar events.

Fresh checks on September 26, 2026:

- Next.js production export and both iOS builds passed. ESLint, eight frontend unit tests, and eight Chromium/WebKit browser tests passed.
- Core/Tauri Clippy with warnings denied passed. Swift formatting passed; the new helper and native tests also passed strict Swift lint. The existing bridge retains snake-case wire-contract property names, which the default Swift naming lint flags.
- **Three iPhone 17 / iOS 26.4 simulator tests passed, zero skipped.** Tests exercised native OCR/persistence; creation of a separate calendar; seven sample events saved there rather than in the system default; repeated import without duplicates; calendar reuse after relaunch and rename; unchanged system default; and failure without calendar creation when a saved destination is unavailable. Test-created events and calendars were removed afterward.
- Signed `artifacts/private/builds/rehab-plan-ocr-lab-0.1.1.ipa`: 37,343,104 bytes; SHA256 `8534ce72bd0ef87739ba7586b65bcaa1d0f15bd453d96c437fd42df4088284da`. Bundle version 0.1.1 and identifier `at.rehakalender.personal` verified. `codesign --verify --deep --strict` passed. The profile covers the paired iPhone 17 and expires **September 26, 2026, 10:57 UTC**. The unversioned IPA alias pointed to this build at the time of packaging.

Evidence is under `artifacts/private/dedicated-calendar/`: `ios-simulator-build.log`, `ios-device-build.log`, `native-tests.log`, `native-tests.xcresult`, and `signing-check.json`. See [installation and calendar visibility instructions](../ios-installation.md).

## Physical installation — September 26, 2026

The connected device reports **iPhone 17 (iPhone18,3), iOS 26.6 (23G71)**, with Developer Mode enabled. The IPA hash, signature, profile expiry and device eligibility were checked before installation. `devicectl device install app` succeeded, and querying installed applications confirmed **Reha Calendar Lab 0.1.1**, bundle version 0.1.1.

The initial launch was denied by iOS with a signing/entitlements/developer-trust security error. The package's local signature verification passed; the user was directed to trust the developer certificate under Settings → General → VPN & Device Management. The subsequent launch command was accepted at 15:57 local time, but the app immediately aborted. This was incorrectly reported as a successful launch. Device crash reports and an attached console later confirmed SIGABRT during startup.

Private evidence: `physical-install.json`, `installed-app.json`, `physical-device.json`, `physical-launch.json` (initial denial), and `physical-launch-retry.json` (launch accepted, followed by a crash) under `artifacts/private/dedicated-calendar/`.

## Version 0.1.2 — physical startup crash

The physical phone reproduced an immediate SIGABRT in 0.1.1. Symbolication traced the abort to a Rust panic crossing the iOS launch callback. Live debugger inspection showed that Rust's `HOME` used `/private/var/...`, while `NSHomeDirectory()` used `/var/...`. Standardizing the not-yet-created application directory retained the first form. The native storage guard compared those strings, rejected the valid sandbox directory, and caused Tauri setup to fail.

Storage initialization now asks Foundation for the app's Application Support directory, creates the bundle-specific subdirectory with file protection and backup exclusion, and returns that path to Rust before SQLite opens. It uses the same underlying directory as the previous path; updating does not erase scans, the ledger, or calendar entries. The unused path-input contract was removed. [Foundation directory lookup](<https://developer.apple.com/documentation/foundation/filemanager/url(for:in:appropriatefor:create:)>)

Physical evidence from the connected **iPhone 17 / iOS 26.6 (23G71)**:

- Version 0.1.2 was signature-verified and installed as an ordinary update. The installed-app query confirmed the version.
- After launch at approximately 16:06:40, the same process was present in checks at 0, 15, and 30 seconds and again at 16:09:38. The old release aborted immediately.
- The separately signed XCTest runner could not install because the phone had reached the free developer profile limit of three apps. No existing apps were removed. Physical automated UI and file-protection assertions remain unverified.
- Signed package: `artifacts/private/builds/rehab-plan-ocr-lab-0.1.2.ipa`, 37,342,949 bytes, SHA256 `7c35c90e816adc4c074fc3d9a018b9f2105eae37d493d5482a87daa3e445b411`. Profile expiry remains September 26, 2026, 10:57 UTC. The unversioned package alias now points to 0.1.2.

The Next.js export and device/simulator builds passed. Tauri Clippy with warnings denied and Swift formatting passed. On the updated iPhone 17 / iOS 26.4 simulator, **three regression tests passed and one was explicitly skipped**, with zero failures: storage reuse/backup exclusion/old-path compatibility, repeated launch and resume, and portable OCR/persistence. The simulator does not expose iOS file-protection attributes, so that hardware-only assertion is not counted as passed. Evidence: `simulator-regression.log` and `simulator-regression.xcresult`.

Private evidence is under `artifacts/private/ios-crash/`: original `.ips` reports, startup console/syslog, signing verification, physical installation and process checks, build/test logs, and symbolication notes. This verifies the startup fix, not physical OCR accuracy, calendar acceptance, or performance targets.

## Version 0.2.0 — simple review and bounded refinement

The app now starts with the German camera/import interface and recent schedules.
The workbench remains under settings and shares application state. Structured
metadata, spatial date sections, bounded original-resolution rereading, explicit
completion suggestions and selected appointment approvals are implemented. Calendar
and ICS identities survive partial saves and later completion.

September 26, 2026 verification: 50 Rust tests, eight frontend unit tests, 16 Chromium/
mobile-WebKit tests and ten Python tests passed. Frontend lint/static export and
workspace Clippy with warnings denied passed. Native simulator checks passed five
tests and skipped the hardware-only file-protection assertion; a separate denied
calendar-access test also passed. After the final metadata-conflict correction,
both iOS builds passed and actual simulator OCR/persistence passed again.

The first signed 0.2.0 update was installed on the physical iPhone 17 / iOS 26.6.
Its process remained alive after 142 seconds. The database migrated to version 2
while retaining every existing row, including the original scan, six calendar
imports, six operations and the schedule binding. Physical XCTest is still blocked
by the free-signing app limit. No other installed apps were removed.

The final signed IPA includes an additional regression-tested guard for contradictory
metadata. It is ready at `artifacts/private/builds/rehab-plan-ocr-lab-0.2.0.ipa`; its
reinstall awaits reconnection of the currently unavailable phone. The installed
build and the final package have different hashes and are documented separately.

Both local VLM candidates passed checkpoint compatibility checks and each read a
difficult crop from all 20 development photographs. Provisional references and page
grouping remain unverified, so no accuracy benefit or packaging qualification is
claimed. The portable model remains the delivered pipeline.

See [the complete 0.2.0 delivery report](simple-app-delivery.md) for exact test
artifacts, package hashes, comparison measurements, retained-data checks and
unavailable physical/accessibility/performance checks. Earlier sections above are
historical records rather than descriptions of the current interface.
