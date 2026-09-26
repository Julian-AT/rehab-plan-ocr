> Historical record: technical findings retained from the archived development sequence. Project dates, build labels and source references have been normalized. This record is not a new test, delivery approval or signing attestation; unaltered evidence and original validity dates are held in the external private archive.

# Architecture decisions

## ADR 001 — local shared semantics

Tauri 2 hosts a Next.js App Router static export with React and shadcn/ui. The packaged webview loads `out/`; no Next.js server runs on desktop or iOS. Browser APIs and IPC are confined to client components, with a server-safe native-environment snapshot. System fonts avoid network font loading. `crates/reha-core` is independently executable Rust with no platform or network imports. It owns contracts, image preparation, parser, validation, calendar proposals, ICS, evaluator and SQLite ledger. `src-tauri` orchestrates IPC and background workers; `plugins/calendar` bridges iOS camera, photo picker, HEIC decoding, optional Vision, EventKit and sharing.

No document data is sent to a server. Model downloads happen only through explicit development scripts reading public URLs; runtime inference has no download path. The release webview CSP restricts connections to local packaged resources and IPC. The packaged application loads no remote fonts, analytics, or hosted inference SDK.

## ADR 002 — source evidence and engine boundary

The original byte hash survives image conversion. The display's original-coordinate frame is the EXIF-upright original; `source.bin` preserves the exact imported bytes. Region polygons use corrected-page coordinates. `original_to_page` and its inverse are recorded, and overlays map back to the displayed upright original. User-selected page corners are expressed in that same original frame. Crops inherit their page polygon. Engine-internal stages that are unavailable are labeled as such.

Portable recognition pins checkpoint hashes, config and dictionary with native ORT. One pipeline at a time, two CPU intra-op threads, and cached sessions limit memory/concurrency. On cancellation/backgrounding, cooperative cancellation is checked before processing and between crops; a single native inference call is not currently preempted. Peak memory is explicitly unavailable until measured. No calibrated confidence percentages are shown.

## ADR 003 — review is authoritative

Editable drafts preserve field provenance and validation issues. Therapist is an additive, default-empty field for older stored runs and annotations; calendar notes include the value. Extraction version 2 invalidates cached recognition results from earlier parsing. Weekday headings must agree with their numeric date; ambiguous dates require confirmation. Standalone `*Neu` markers are removed only from structured values. Header-derived column boundaries keep therapist continuations out of rooms and titles. Essential-field/timezone validation runs in Rust at export/write preparation regardless of frontend controls. Additional recognition issues must be explicitly reviewed. Review confirmation is invalidated on edits. No appointment end is inferred from neighboring rows. Potentially missed text remains visible.

## ADR 004 — calendar operations are a recoverable local transaction

Rust matches exact events as a multiset first, then uniquely attributable moves/changes. Three-way merge preserves independent calendar edits; start/end/timezone merge atomically. User resolves competing changes. Only complete replacements may propose removals, and removals require separate approval.

The backend retains the proposal, hashes the reviewed draft and uses an opaque token for confirmation. The frontend cannot submit arbitrary write payloads. Each write intent is committed to SQLite before EventKit; results are recorded individually. Native updates compare current values to the preview's before-values and enforce an app marker URL plus destination identity. Unknown outcomes remain pending; reconciliation never creates. Outstanding uncertainty blocks new proposals. This favors duplicate prevention over speculative recovery.

## ADR 005 — retention versus research

Application storage holds `ledger.sqlite` and `scans/<uuid>/`. Detailed records and all scan files expire at 30×86400 seconds from original import, with launch/resume cleanup and injected-time tests. SHA256 hashes and approved import snapshots survive. SQLite secure deletion is enabled; app-owned data deletion leaves external calendars/Photos untouched. The iOS root is excluded from backup and uses file protection. Research data in repository `data/private/` is separately retained and ignored by Git.

## ADR 006 — experiments precede adaptation

Canonical versioned references are paper-verified, grouped by day and frozen before tuning. The evaluator rejects provisional references and ordinary holdout access. A one-shot batch runner requires frozen config/model selection for final holdout. Reports include raw counts and explicit unavailable workflow/device metrics. No adapted model or ensemble exists at this stage.

## Current boundaries

The browser build is a labeled, ephemeral synthetic preview; real OCR, persistence and calendar export require the native app or Rust CLI. It must never pretend to process an uploaded photo. Desktop HEIC decoding is not in the shared image crate; convert locally for CLI experiments or use the iPhone import path. Automatic robust page detection, advanced blur/handwriting classifiers, preemptible native inference and memory-pressure tuning need further work/evidence.
