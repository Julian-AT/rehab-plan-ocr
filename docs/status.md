> Historical record: technical findings retained from the archived development sequence. Project dates, build labels and source references have been normalized. This record is not a new test, delivery approval or signing attestation; unaltered evidence and original validity dates are held in the external private archive.

# Development status

The current interface is a technical workbench, following the September 26, 2026 request to replace the earlier product UI. Next.js static export replaces Vite; shadcn/ui supplies standard controls. No production server, hosted recognition, accounts, or marketing UI is included.

## Implemented

- Portable PP-OCRv6 small/tiny/medium CPU inference, pinned models/runtime, preprocessing, source transforms, field provenance, and stage records.
- Weekday date headings, separate room/therapist fields, multiline continuations, `*Neu` cleanup, and versioned extraction cache invalidation. Raw OCR remains unchanged. Metadata detection no longer drops timed treatments containing “Blutdruck” or “Aufnahme”.
- Editable appointments, explicit review, source overlays, trace inspection, rotation/crop controls, batch image import, and retained history.
- Dataset inventory, annotation editing, local batch execution, saved experiment manifests, comparison, and evaluation. Held-out data stays locked in interactive scoring.
- EventKit proposals and approvals, three-way reconciliation, duplicate multiplicity, uncertain-write recovery, and UTC iCalendar export. Therapist values are included in exported notes.
- iOS setup creates or reuses a separate Reha Calendar, remembers it across reconnects and renames, and selects it for new imports. Visibility is controlled in Apple Calendar's calendar list; existing imports retain their recorded destination.
- SQLite retention and import ledger, launch/resume cleanup, separate research storage, and native storage protection.

Native commands are split into scan, calendar, dataset, settings, state, and inference modules. Frontend workflows live under `src/features/`; shared domain components and shadcn primitives live under `src/components/`.

## Data and verification boundaries

Retained app OCR was inspected locally for the reported extraction bugs. The user subsequently authorized exploratory testing of `verify/`: 21 HEIC files contain 20 distinct originals, plus an existing PNG. All originals remain unchanged. Full-resolution PNG derivatives and local OCR outputs are excluded from Git and Docker contexts. The first real-image baseline completed all 20 inputs but exposed unresolved dates in nine images, including pages with multiple date headings that the current single-date-per-image parser cannot handle. It produced 193 draft items, 17 empty titles and 10 missing end/duration values; these are diagnostic counts, not verified accuracy. See [the baseline report](real-image-baseline.md).

The research dataset still needs paper-verified annotations, explicit day/page/capture identities, and a frozen development/holdout split. These 20 exploratory images have been inspected through local OCR; they must not be described as an unopened final holdout.

The physical iPhone 17 connected on September 26, 2026. Device inspection confirmed iOS 26.6 (23G71) and Developer Mode enabled. Version 0.1.1 installed and launched successfully. The first launch required resolving iOS developer trust on the phone; a subsequent launch succeeded. Physical recognition/calendar acceptance, performance and supported stable-release status remain unverified. Simulator, build and installation evidence are recorded separately in `verification.md`.

No training, final holdout, physical p95, peak-memory claim, or clinical accuracy claim has been made. Original targets remain ≥99% critical date/time accuracy, ≥99% appointment precision/recall, ≥90% schedules without correction, and physical iPhone p95 ≤30 seconds.

## Remaining validation

- Establish verified day/page/capture groups and development references before model comparison or tuning. Address multiple date sections per image and investigate title/row association errors exposed by the baseline.
- Test on a connected iPhone: camera/HEIC, calendar permissions and revisions, accessibility, backgrounding, memory pressure, repeated scans, and content-network isolation.
- Check `.ics` imports in Apple Calendar and Google Calendar.
- Automatic page detection, selective rereading, memory measurements, and VLM adapters remain unimplemented. Small is packaged; other OCR tiers are source-tree experiments.

Keep content-bearing outputs under ignored private paths. Use the documented verification commands after changes; do not interpret successful compilation as device acceptance.
