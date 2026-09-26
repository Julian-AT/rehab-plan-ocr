> Historical record: technical findings retained from the archived development sequence. Project dates, build labels and source references have been normalized. This record is not a new test, delivery approval or signing attestation; unaltered evidence and original validity dates are held in the external private archive.

# Development status — 0.2.0

The app opens in a minimal German interface with camera/import actions, recent
schedules and unfinished reviews. The existing development workbench loads through
**Einstellungen → Entwickleransicht öffnen**, sharing the active scan, edits and
processing state. Next.js static export, shadcn/ui and the neutral theme remain.
The iPhone label is **Termine**; the bundle identifier and **Reha Calendar**
destination are preserved. No hosted recognition or production server is needed.

## Implemented

- Clinic emblem app icons: rounded macOS ICNS/PNG with transparent margins and
  an opaque iOS catalog, automatically restored into generated Xcode projects.
  All 18 iOS sizes and desktop alpha margins were validated; Apple's asset compiler
  and ESLint passed, and the macOS debug app was rebuilt and restarted. The current
  version was also installed on the connected iPhone at the user's subsequent
  request. See [artwork](../src-tauri/icon-artwork/README.md) and
  [iPhone update verification](iphone-update-20260926-s11.md).
- Local HEIC/HEIF import on macOS through ImageIO, alongside the existing iOS
  decoder. File inputs accept extensions even without a MIME type. Full-resolution
  primary-image decoding applies orientation once and retains original bytes/hash.
- Portable PP-OCRv6 inference with multiple spatial date sections, wrapped fields,
  scoped metadata, field origins and original-resolution crop rereading. The automatic
  import and retry passes have a 60-second budget including native load/preparation,
  progress, cancellation and last-draft retention. ONNX inference can be terminated.
- Optimized native debug image processing and checksum verification, with lossless
  PNG reuse and shared original pixels for rereading. A same-photo debug pipeline
  comparison improved from 34.629 to 2.830 seconds including fresh model loading;
  recognized values, geometry, warnings and alternatives matched exactly.
- Protected manual corrections, visible conflicting evidence, and completion
  suggestions from approved matching clinic/treatment history or editable defaults.
  Suggestions require acceptance and never supply dates or start times.
- Appointment sheets, chronological review, pending filtering, metadata details,
  source access, selected calendar approval and ICS export. Complete appointments can
  be saved while unfinished siblings remain pending.
- Rust-enforced approval snapshots, stable calendar/ICS identities, duplicate
  multiplicity, metadata updates, partial imports, three-way reconciliation and
  uncertain-write recovery. Partial saves never imply removal.
- Contract migration, extraction-cache invalidation, SQLite retention and import
  ledger, 30-day artifact cleanup, storage protection and explicit user defaults.
- Lazy development tables, source overlays, traces, model/fixture/dataset tools,
  provisional reference editing and desktop difficult-region comparisons through a
  pinned llama.cpp/libmtmd adapter. GLM-OCR and PaddleOCR-VL-1.6 remain experiments.

## Data and verification boundaries

All 20 distinct original photographs now have visual transcription drafts: 188 row
occurrences across individual photos, including correlated alternate captures and
revisions. Reference schema 2 adds source hashes, field states and text polygons.
None is user-approved yet. Four reproducible development folds require confirmed
transitive day/page/capture grouping (split schema 3). No independent holdout exists.

The implementation adds polygon crops, local baseline/clock alignment, conservative
page-edge correction, native field approval gates and safe saved-import rechecks.
Run schema 3 and extraction version 7 invalidate legacy recognition approvals/caches.
See [the new delivery](recognition-review.md) for exact capabilities and boundaries.
Two hundred independently composed synthetic plans and a 24-recipe variant/export
pipeline are available; originals stay blocked from training until explicit approval.

Both additional model families passed checkpoint compatibility checks and each read
one difficult region from all 20 photographs. GLM finished 19 readings and reached
its output limit on one; Paddle finished 20. Correctness remains unscored. Neither
model qualifies for packaging without verified appointment-level comparisons and
20 consecutive physical scans meeting the 30-second p95 target without termination.
The delivered app therefore bundles the portable small model only.

Frontend, Rust, Python, browser, simulator and physical installation checks are
recorded in [the delivery report](simple-app-delivery.md). The physical XCTest runner
remains blocked by the free-signing app limit; no other installed apps were removed.
Build success and process survival do not establish camera acceptance, VoiceOver,
physical OCR accuracy, thermal/memory qualification or the 20-scan p95 target.

## Remaining validation

- Verify references and page relationships before accuracy comparison or tuning;
  collect independent final holdout data.
- Complete physical camera/HEIC, calendar revision, VoiceOver, large text, background,
  memory/thermal and repeated-scan acceptance checks. Inspect device-level document
  traffic; local desktop inference already runs with network access denied.
- Check exported ICS files in Apple Calendar and Google Calendar.
- Confirm conservative page-edge correction and table fallback on more clinic formats.
  Other OCR tiers remain development experiments.

No training or final holdout evaluation has been performed. Historical acceptance targets were
at least 99% critical date/time accuracy, 99% appointment precision/recall, 90%
schedules without correction and physical iPhone p95 at most 30 seconds. Keep all
content-bearing evidence in ignored private storage.

The current user contract allows 60 seconds for the automatic check, including
loading/preparation. Earlier 30-second delivery measurements and targets are
historical and do not change this budget. Installation/signing was excluded from
the original recognition plan; the user's subsequent September 26, 2026 request
authorized the [current iPhone update](iphone-update-20260926-s11.md).
