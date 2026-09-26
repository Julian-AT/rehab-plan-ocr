> Historical record: technical findings retained from the archived development sequence. Project dates, build labels and source references have been normalized. This record is not a new test, delivery approval or signing attestation; unaltered evidence and original validity dates are held in the external private archive.

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

The paired physical device is iPhone 17 (iPhone18,3), last-reported iOS 26.6 (23G71), and remains unavailable. No physical installation, live OS validation, latency percentile, memory-pressure, thermal, or repeated-scan acceptance result is claimed.

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
- Signed `artifacts/private/builds/rehab-plan-ocr-lab-0.1.1.ipa`: 37,343,104 bytes; SHA256 `8534ce72bd0ef87739ba7586b65bcaa1d0f15bd453d96c437fd42df4088284da`. Bundle version 0.1.1 and identifier `at.rehakalender.personal` verified. `codesign --verify --deep --strict` passed. The profile covers the paired iPhone 17 and expires **September 26, 2026, 10:57 UTC**. The unversioned IPA alias now points to this build.

Evidence is under `artifacts/private/dedicated-calendar/`: `ios-simulator-build.log`, `ios-device-build.log`, `native-tests.log`, `native-tests.xcresult`, and `signing-check.json`. The physical phone remains unavailable; no installation or physical-device acceptance is claimed. See [installation and calendar visibility instructions](ios-installation.md).
