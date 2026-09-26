> Historical record: technical findings retained from the archived development sequence. Project dates, build labels and source references have been normalized. This record is not a new test, delivery approval or signing attestation; unaltered evidence and original validity dates are held in the external private archive.

# Development status — 0.2.0

The app opens in a minimal German interface with camera/import actions, recent
schedules and unfinished reviews. The existing development workbench loads through
**Einstellungen → Entwickleransicht öffnen**, sharing the active scan, edits and
processing state. Next.js static export, shadcn/ui and the neutral theme remain.
The iPhone label is **Termine**; the bundle identifier and **Reha Calendar**
destination are preserved. No hosted recognition or production server is needed.

## Implemented

- Portable PP-OCRv6 inference with multiple spatial date sections, wrapped fields,
  scoped metadata, field origins and original-resolution crop rereading. The automatic
  pass stops scheduling work at 30 seconds; explicit retry has a 60-second budget.
  In-flight CPU inference is cooperative and may finish after that deadline.
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

All 20 distinct development photographs were processed locally with network access
disabled. The exploratory portable run produced 199 proposals, including 25 missing
dates, 14 missing end/duration values and 17 empty titles. These are diagnostic
counts, not verified accuracy. The recorded baseline uses extraction version 3;
version 4 also fixes repeated contradictory metadata and invalidates earlier caches.

Twenty per-image provisional references and 16 conservative groups are available in
the development tools. Their references and day/page relationships remain unverified.
These previously explored images are development data, not an independent final
holdout. Accuracy evaluation refuses unverified references and grouping.

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
- Automatic page-boundary detection remains separate from the implemented spatial
  schedule-section detection. Other OCR tiers remain development experiments.

No training or final holdout evaluation has been performed. Original targets remain
at least 99% critical date/time accuracy, 99% appointment precision/recall, 90%
schedules without correction and physical iPhone p95 at most 30 seconds. Keep all
content-bearing evidence in ignored private storage.
