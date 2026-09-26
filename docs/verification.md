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
- Signed private IPA: `artifacts/private/builds/rehab-plan-ocr-lab.ipa`; `codesign --verify --deep --strict` passed after extraction outside the synced workspace. Profile expires **2026-09-26 10:57 UTC**. Verification: `signing-check.json`.

Build environment: Apple M4 Pro / 24 GiB, Rust 1.98.1, Node 22.22.3, npm 11, Xcode 26.4 (17E192), Swift 6.3, ONNX Runtime 1.22.0, `ort` 2.0.0-rc.10. Deployment minimum is iOS 17. Native models use the portable CPU adapter; no Apple recognition is required.

The paired physical device is iPhone 17 (iPhone18,3), last-reported iOS 26.6 (23G71), and remains unavailable. No physical installation, live OS validation, latency percentile, memory-pressure, thermal, or repeated-scan acceptance result is claimed.

## Data and remaining checks

An incoming `verify/` directory contains 22 images with 21 distinct byte hashes. Its contents were not opened or used for tuning; originals remain unchanged, with a private hash inventory. The folder is excluded from Git and Docker. It has not been classified or assigned to a frozen evaluation split.

No verified development benchmark, final holdout, training, or VLM qualification has been performed. Physical camera/HEIC and calendar flows, full accessibility testing, native revision/failure fault injection, Apple/Google `.ics` imports, and device-level content-network inspection remain open. Earlier synthetic robustness probes are retained privately but have not been rerun as a fresh accuracy benchmark for this refactor.

Original targets remain unchanged: ≥99% critical date/time accuracy, ≥99% appointment precision/recall, ≥90% schedules without correction, and physical iPhone p95 ≤30 seconds.
