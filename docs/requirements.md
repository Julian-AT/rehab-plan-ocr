> Historical record: technical findings retained from the archived development sequence. Project dates, build labels and source references have been normalized. This record is not a new test, delivery approval or signing attestation; unaltered evidence and original validity dates are held in the external private archive.

# Development-tool interface amendment — 2026-09-26

The current interface is a minimal technical workbench using Next.js App Router and shadcn/ui. It replaces the earlier product-oriented React/Vite interface. Use technical labels, kebab-case project filenames, focused modules, and no marketing copy. Preserve local recognition, review, evidence, experiments, retention, and calendar safeguards below. Parse weekday headings such as “Donnerstag, der 30.04.2026”, remove `*Neu` markers from structured values, and retain multiline `Therapeut` values as one field.

# Rehab Plan OCR — product requirements

Status: implementation in progress. Approved source: execution handoff supplied by the user. Requirements below remain acceptance targets until supported by evidence in verification.md.

## Purpose and scope

Convert photographs of printed rehabilitation schedules into accurate calendar appointments for one person, initially on an iPhone 17 with a supported stable iOS release. The real device model and OS must be recorded during testing. Use Tauri 2, Next.js/React/TypeScript with shadcn/ui, a shared Rust core and SQLite. Android is a later application release; the portable recognition path must run on a non-Apple platform during development.

The workflow is **photograph/import → recognize locally → compare with paper → approve → save**. Recognition, evaluation and any training stay local. The mobile app requires neither Python, a server nor a reachable computer. Apple Vision and hardware acceleration are optional; a complete portable engine remains available. No accounts, clinic administration, clinical interpretation, recommendations, translation, hosted AI or direct provider OAuth are included.

## Capture and recognition

- Camera and photo/file import; JPEG, PNG and iPhone HEIC; distinct documents for batch imports.
- Guide complete-page capture; allow rotation and crop/perspective adjustment, explain poor capture quality and offer recapture.
- Explicit confirmation when multiple pages form one day. Never silently merge distinct days.
- Extract every timed item, including therapies, exercises, consultations, meals and breaks. Preserve printed language and terminology.
- Treatment date outranks printing/admission/header timestamps and photo metadata. Missing, ambiguous or contradictory dates require confirmation.
- Keep repeated and overlapping appointments. Associate wrapped titles, locations and preparation notes with source rows conservatively.
- No invented appointments, dates, times, durations or clinical meanings. Never derive an end from the next start.
- Uncertain cancellation/handwritten edits become review issues. Preserve unassigned text and possible omissions.
- Essential fields must be resolved before saving an included item. Default timezone Europe/Vienna, configurable; handle midnight and daylight-saving transitions explicitly.

Pipeline stages: decode/orient; quality/page boundary; correction; text detection; text recognition; rows/columns/reading order; date/field extraction; validation; optional selective reread; review/calendar proposal. Keep originals intact and derived images separate. Every available stage records actual output, configuration, versions, timings, failures and fallbacks. Mark unavailable evidence honestly. Engine scores are signals, not calibrated correctness probabilities.

Versioned contracts cover documents, coordinate regions, observations, appointment drafts with provenance, pipeline runs and import records. Coordinate transformations between upright original, corrected page and crops must support accurate source overlays. The original byte hash is independent of preprocessing.

## Review and calendar

Always review before any calendar change. Include/exclude each item; edit, add missed items and remove false detections. Selecting fields highlights their source. Make unresolved fields, unassigned regions and possible omissions prominent. Controls support large text, screen readers, keyboard focus and non-color indicators.

On iOS select a writable configured calendar, defaulting to the system default. Request full EventKit access for reading and revisions. Declining access leaves ICS export available. Save approved title, start/end, location, notes and optional reminders.

Maintain stable internal identities, identical-image detection and equivalent-schedule detection preserving multiplicity. Persist write intent before native writes, record each outcome, reconcile uncertainty before retrying creation and recover from partial failures. Updates and deletions are restricted to app-owned events. A preview must be invalidated when either draft data or current calendar values change.

Revision review shows unchanged, added, moved/changed and removed items. Match unchanged events first, then unambiguous candidates; require resolution for ambiguity. Three-way comparison uses last approved, current calendar and newly extracted values to preserve user edits. Incomplete/cropped replacements cannot propose deletions. Removals need separate confirmation.

ICS export uses stable UIDs, UTC instants derived from the configured timezone, text escaping, CRLF and UTF-8-safe 75-octet folding. Cross-application repeated-file reconciliation is not promised. Check actual imports in Apple Calendar and Google Calendar before release.

## Inspector and desktop lab

On-device inspector: original image/dimensions/orientation/hash; correction and transforms; regions and reading order; OCR text/scores/alternatives/crops; field provenance; validation, unassigned text and retry decisions; approved payloads, proposals and individual write results. Show model/runtime identity, config, stage durations, caching and available memory measurements. Ordinary metadata is recorded every run; large crops are opt-in.

Desktop lab: private dataset browser, reference annotation editor, originals/overlays, saved configs, local batch runs, verified-ground-truth comparisons, per-document errors and aggregate counts, side-by-side results and reproducible reports/manifests. Node editing, arbitrary rewiring and manual segmentation are deferred.

## Privacy and retention

App-managed source photos, derived images, full OCR text and detailed traces expire after 30 days. Cleanup runs at launch/resume and when OS scheduling allows; use an injectable clock for tests. Retain only minimal hashes/import ledger and approved snapshots necessary for updates and duplicate prevention. Provide immediate scan/all-data deletion. Never delete originals from Photos. Exclude retained content from automatic backup; do not log document content. Debug exports require an explicit user action.

The research dataset is separate and intentionally retained. Place only identified dataset images in `data/private/raw/`, preserving filenames/bytes and verifying hashes before/after movement. Keep annotations in `data/private/labels/`, outputs in `artifacts/private/`, models in `models/private/`; all ignored before use. Commit only invented/sanitized fixtures.

## Evaluation and training

Shortlist: PP-OCRv6 small baseline with tiny/medium comparisons; Apple Vision with shared downstream contracts; PaddleOCR-VL-1.6 and GLM-OCR if exact checkpoint/runtime compatibility is demonstrated; Qwen3-VL 2B, considering 4B only when justified. Keep the portable path regardless of native results. No unmeasured ensemble or adaptation ships.

Audit actual days, layout variation, duplicates, readability and handwriting. Annotate all timed items and sources; generated references remain provisional until paper-verified. With 20 distinct days freeze 16 development/4 final holdout before tuning; four grouped development folds. All pages/photos/crops/augmentations from a day stay together. Final content is excluded from training, prompts, dictionaries, thresholds and synthesis. Freeze candidate selection before opening holdout once. Tuning after final errors contaminates it and requires disclosure plus new evaluation days. Twenty days do not establish broad clinical coverage.

Report date/start/end/duration exactness, appointment precision/recall, fully correct appointments and complete schedules, title/room/note accuracy, unresolved and recapture counts. Report correction effort/time, import-to-review and cold/warm latency, peak memory/model size/repeated scans, calendar success, duplicates and revisions. Include counts and denominators; distinguish measurements, estimates and untested claims.

Selection priority: fewer missed/invented/critical-time errors; more correct whole days; less correction; then latency/memory/size. Targets stay **99% critical fields, 99% precision, 99% recall, 90% whole schedules**, with **physical iPhone 17 p95 ≤30 seconds** and responsive repeated scans without OS termination. Simulator numbers cannot satisfy device targets.

Optimize only observed failures: capture/geometry; detector resolution/crops; grouping; crop batching; session reuse/concurrency; selective rereads; quantization; acceleration; runtime/package reduction. Include model-load/preprocessing/validation overhead. Fine-tune only a repeatably failing pretrained component on verified development data, locally, with checkpoints/early stopping. Use LoRA where appropriate; retain adaptations only with independent improvement and deployability.

## Release gates

Test clean/rotated/skewed/blurred/shadowed/cropped/low-contrast inputs; wrapped/repeated/overlapping rows, missing fields and competing dates; midnight/DST; transformed overlays; duplicate/revised plans and calendar edits; denied access, partial/uncertain writes; actual ICS imports; offline native-disabled processing and Linux execution; failed models, cancellation, backgrounding/memory pressure; retention; and absence of content-bearing network traffic.

Deliver a signed private development build where signing allows, reproducible evaluation evidence, setup/install/annotation/experiment instructions and explicit unmet targets. App Store/TestFlight publication is a separate action.

## Dataset status at execution start

2026-09-26: repository contained only Git metadata, `.gitignore` and `.gitattributes`. No clinical images were present. Exact dataset location requested; none has been supplied during implementation so far. No patient images moved, no verified clinical labels, no frozen clinical split, no clinical benchmark, no model trained. The synthetic fixture is explicitly invented and includes eight timed rows, one wrapped note, repeated appointments and one intentionally absent end time.

## September 26, 2026 recognition and reference-review update

The current automatic-review budget is 60 seconds total, including loading and
preparation, with cancellation and retention of the last usable draft. Current
references are per-original schema 2, and all previously inspected photos belong
to development folds with transitive overlap isolation. Independent final testing
requires new photos. Refer to [the current implementation](recognition-review.md)
and [reference workflow](dataset.md); earlier 16/4 split and 30-second process-budget
instructions are superseded. iPhone installation and signing are outside this task.
