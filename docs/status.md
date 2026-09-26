> Historical record: technical findings retained from the archived development sequence. Project dates, build labels and source references have been normalized. This record is not a new test, delivery approval or signing attestation; unaltered evidence and original validity dates are held in the external private archive.

# Development status

The current interface is a technical workbench, following the September 26, 2026 request to replace the earlier product UI. Next.js static export replaces Vite; shadcn/ui supplies standard controls. No production server, hosted recognition, accounts, or marketing UI is included.

## Implemented

- Portable PP-OCRv6 small/tiny/medium CPU inference, pinned models/runtime, preprocessing, source transforms, field provenance, and stage records.
- Weekday date headings, separate room/therapist fields, multiline continuations, `*Neu` cleanup, and versioned extraction cache invalidation. Raw OCR remains unchanged. Metadata detection no longer drops timed treatments containing “Blutdruck” or “Aufnahme”.
- Editable appointments, explicit review, source overlays, trace inspection, rotation/crop controls, batch image import, and retained history.
- Dataset inventory, annotation editing, local batch execution, saved experiment manifests, comparison, and evaluation. Held-out data stays locked in interactive scoring.
- EventKit proposals and approvals, three-way reconciliation, duplicate multiplicity, uncertain-write recovery, and UTC iCalendar export. Therapist values are included in exported notes.
- SQLite retention and import ledger, launch/resume cleanup, separate research storage, and native storage protection.

Native commands are split into scan, calendar, dataset, settings, state, and inference modules. Frontend workflows live under `src/features/`; shared domain components and shadcn primitives live under `src/components/`.

## Data and verification boundaries

Retained app OCR was inspected locally for the reported extraction bugs. Private source material was neither moved into the research dataset nor committed. An incoming `verify/` directory contains 22 photos with 21 unique byte hashes. It is excluded from Git and Docker contexts; files remain unchanged and uninspected pending classification as development or held-out data. The research inventory still lacks the agreed, grouped, paper-verified development/holdout dataset. The parser regression check is not an independent accuracy benchmark.

Physical iPhone 17 remains paired but unavailable. Its last-reported OS is iOS 26.6 (23G71); live device behavior and supported stable-release status must be recorded when connected. Simulator and build evidence are recorded separately in `verification.md`.

No training, final holdout, physical p95, peak-memory claim, or clinical accuracy claim has been made. Original targets remain ≥99% critical date/time accuracy, ≥99% appointment precision/recall, ≥90% schedules without correction, and physical iPhone p95 ≤30 seconds.

## Remaining validation

- Establish verified day/page/capture groups and development references before model comparison or tuning.
- Test on a connected iPhone: camera/HEIC, calendar permissions and revisions, accessibility, backgrounding, memory pressure, repeated scans, and content-network isolation.
- Check `.ics` imports in Apple Calendar and Google Calendar.
- Automatic page detection, selective rereading, memory measurements, and VLM adapters remain unimplemented. Small is packaged; other OCR tiers are source-tree experiments.

Keep content-bearing outputs under ignored private paths. Use the documented verification commands after changes; do not interpret successful compilation as device acceptance.
