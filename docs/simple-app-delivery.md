> Historical record: technical findings retained from the archived development sequence. Project dates, build labels and source references have been normalized. This record is not a new test, delivery approval or signing attestation; unaltered evidence and original validity dates are held in the external private archive.

# Simple app and bounded local refinement — 0.2.0

The app opens in German with **Foto aufnehmen**, **Importieren**, recent plans and
unfinished reviews. **Einstellungen → Entwickleransicht öffnen** loads the existing
workbench on demand. Both interfaces use one application state. Cold launches
always start in the simple interface; opening diagnostics never enables detailed
image artifacts. The iPhone display name is **Termine**. The bundle identifier
`at.rehakalender.personal` and the **Reha Calendar** destination are preserved.

## Review and calendar behavior

Appointments are grouped chronologically by treatment date. **Offene Angaben**
filters unfinished items. An appointment sheet keeps essential inputs first,
expandable metadata and photograph evidence below, and actions above the keyboard.
Closing a changed appointment or settings sheet requires explicitly saving or
discarding its edits. The source photograph and retained document text remain
available without development mode.

Calendar selection includes complete appointments; incomplete siblings remain
pending. The selected values must pass Rust validation and per-appointment approval
before a proposal or ICS is produced. Saving seven appointments and completing an
eighth later updates the existing schedule without recreating the first seven.
Calendar saved, ICS exported, ready, excluded and pending are distinct states.
Changing approved values invalidates their approval. A final calendar action follows
the selected destination and proposal review. Denied calendar access leaves ICS
available. Uncertain writes retain reconciliation records and block new writes until
resolved.

Calendar and ICS identities survive metadata changes and same-photograph
reprocessing. Identical appointments retain their multiplicity across partial
exports. Partial calendar selection never proposes removals. The workbench retains
explicit complete-replacement mode and separate removal approval. Existing
three-way reconciliation preserves manual calendar edits.

## Contract and retention

Contract version 2 adds spatial schedule sections, optional appointment metadata,
field origins, suggestions, refinement attempts/readings, approval snapshots and
calendar/ICS identity and status fields. Extraction version 4 invalidates recognition
caches produced by earlier extraction behavior.

Version 1 records are migrated when loaded. Because they did not record edit
origins, retained nonempty values are conservatively protected as manual values.
Existing document IDs, appointment IDs, bindings and import history remain intact.
Store updates use the existing JSON records and additive SQLite version migration.
The backend does not trust approval, origin or event-ID claims from the webview.

The existing 30-day cleanup removes retained source images, OCR observations,
refinement details and nested experiment results. Tests use an injected timestamp
and check the exact expiry boundary. Approved reconciliation identities and
explicit user defaults remain available; deleting all app data remains explicit.
Research datasets and exported development reports are private workspace files,
separate from the app's managed scan store.

Calendar metadata uses consistent German labels for clinic, department, contact,
therapist, treatment code, preparation, document reference and appointment notes.
Room/address become calendar location. Patient and administrative lines remain in
document evidence and are excluded from automatic appointment notes. No photographs
are attached and no external enrichment is performed. Metadata is scoped by spatial
section; ambiguous scope is left for review. Repeated contradictory labels cannot
restore a discarded candidate or fall back to a global clinic heading.

## Automatic pass

The automatic deadline starts before image decoding and model loading. The portable
PP-OCRv6 sessions are reused for up to 24 evidence targets with original-context and
bounded contrast/scale variants. Each attempt records its status, duration and
crop-to-original/page transforms. Additional crops stop being scheduled when the
30-second budget is exhausted. **Erneut prüfen** starts a cancellable pass with a
60-second budget. A currently executing CPU inference call is cooperative, so the
budget is a scheduling deadline, not a guarantee that an in-flight call can be
preempted at the exact millisecond. The retained draft survives refinement failure
or cancellation.

Two distinct preprocessing attempts must agree before filling a missing field.
Contradictory candidates remain visible and block approval; confidence scores do not
choose a winner. Spatially ambiguous reprocessing retains manual corrections and
marks both the old and competing rows for review. Historical values never supply a
date or start time, and the next appointment never supplies an end time.

Completion suggestions use exact normalized clinic and treatment matches from
approved import history or explicit editable defaults. Allowed suggested fields are
duration, room, therapist and preparation. They stay unapplied until accepted,
include their origin, and retain rejection. This is transcription/completion, not
clinical advice.

## Development comparison

`models/vlm-experiments.lock.json` pins llama.cpp/libmtmd, GLM-OCR Q8_0 and the
original PaddleOCR-VL-1.6 checkpoint. `experiments/vlm/` contains a narrow static C ABI
adapter with load/read/cancel/close operations and no application, approval or
calendar access. The desktop runner records hashes, exact runtime/converter
revisions, preprocessing, fixed prompts, output limits, latency and memory. It
executes with network access denied on macOS. Neither candidate is bundled in the
app.

`prepare-provisional.py` prepared 20 separate unverified per-image references and 16
conservative provisional groups. The inventory retains original-to-converted image
hash relationships. These images were already explored: all are development data
and there is no independent final holdout. The workbench loads and edits these
references. Corrections are saved per image until grouping is verified, so related
pages do not overwrite one another. Accuracy evaluation refuses unverified page
relationships or references.

An exploratory portable run on all 20 converted images completed with network
disabled using extraction version 3, before the final metadata-conflict guard. It produced 199 appointments, 25 missing dates, 14 missing end/duration
values and 17 empty titles. The earlier run had 193 appointments and 109 missing
dates. These are diagnostics, **not accuracy scores**: the six additional proposals
have not been verified as true appointments. Cold-process Mac latency was median
3,794.5 ms, p95 11,077 ms and maximum 18,000 ms, excluding HEIC conversion.
Detailed inputs, predictions, attempt evidence and hashes are retained privately in
`artifacts/private/refinement-v3-baseline/`.

Both GLM-OCR and PaddleOCR-VL-1.6 passed the invented-image compatibility check
with exact recovery of `08:00 - 08:30 Bewegung Raum 2`. GLM uses the pinned Q8_0
text/projector files; Paddle uses F16 files converted from the pinned original
checkpoint with the pinned runtime converter. The final compatibility runs took
4,464 ms / 2.09 GB RSS and 5,943 ms / 1.95 GB RSS respectively. An initial adapter
guard rejected Paddle's architecture name; the guard was corrected to the pinned
converter's `paddleocr` architecture before candidate admission. The rejected run
and corrected qualification are retained separately.

All 20 photographs then received one original-resolution difficult-region comparison
against their portable draft. The CPU adapter used two threads, a 4,096-token context,
at most 1,024 image tokens and 256 output tokens. Each independent reader had a
60-second limit and network access denied. Source hashes, crop transforms, exact
prompts, runtime/converter versions, model hashes and every reading remain private.

| Region reader | Completed / limited | Median | p95 | Maximum | Peak RSS | Model + projector |
| --- | --- | --- | --- | --- | --- | --- |
| GLM-OCR Q8_0 | 19 / 1 | 19,224 ms | 26,041 ms | 33,126 ms | 2.42 GB | 1.43 GB |
| PaddleOCR-VL-1.6 F16 | 20 / 0 | 34,718.5 ms | 55,195 ms | 56,350 ms | 2.28 GB | 1.82 GB |

The limited GLM reading exhausted its output budget. Completed means the reader
finished, **not that its transcription is correct**. These are cold Mac crop-reader
measurements with concurrent development work, not controlled iPhone timings.
Portable timings above cover whole photographs and are not directly comparable.
No VLM readings were applied, approved or written to calendars. Correct appointment,
missed/invented appointment and date/time error metrics remain unknown until the
provisional references and page relationships are verified.

`artifacts/private/vlm-region-comparison/review.html` contains all 20 source crops,
portable proposals and both readers side by side. It is an escaped, offline report
with no scripts or external URLs. `summary.json` contains aggregate measurements;
individual `comparison.json` records contain the provenance. Because the CLI was
rebuilt during development, four crop-tool hashes appear in the batch; all 20 crop
images and coordinate records were subsequently reproduced byte-for-byte with the
last comparison CLI. The workbench's
**Dataset** tools expose provisional reference review and desktop region experiments.

A candidate may be packaged only after verified grouped comparisons show more
fully correct appointments with no additional missed/invented appointments or
critical date/time errors, and physical-device p95 stays at or below 30 seconds
without termination over 20 consecutive scans. Ties use correction effort, latency,
memory, then package size. Unverified references cannot satisfy this gate. The
portable pipeline is therefore the delivered implementation; fine-tuning is deferred.

## Verification evidence

Private build and test evidence is under `artifacts/private/simple-delivery/`.
Frontend lint, static export, eight frontend unit tests and 16 Playwright tests pass
on Chromium and mobile WebKit. Browser tests cover the simple launch, 44-point
controls, shared edits, protected dismissal, source access, partial selection,
keyboard/focus behavior, large text, dark appearance and reduced motion.

All 50 Rust tests pass (36 existing tests and 14 review/refinement regressions),
and workspace Clippy passes with warnings denied. Ten Python tests cover dataset,
image tooling and provisional-reference isolation. Rust tests cover multiple spatial
date sections, competing headers, wrapped rows,
therapist continuations, repeated/overlapping appointments, metadata scope,
source-coordinate transforms, agreeing/conflicting rereads, retained edits,
suggestions, selected approvals, calendar/ICS identity, reconciliation, migration
and retention. The final metadata-conflict regression was observed failing before
the fix and passing afterward; it includes repeated candidates in different orders
and a conflicting local heading overriding inherited metadata.

On iPhone 17 / iOS 26.4 simulator, five tests passed with zero failures and one
explicit skip for hardware file-protection attributes. They exercise actual portable
recognition, persistence, partial calendar saves followed by later completion,
dedicated-calendar reuse, storage protection helpers and launch/resume. A separate
run after revoking calendar access passed the denial/ICS/pending-state test. These
full-suite results precede the final metadata-conflict correction; the final parser
is covered by the 50 Rust tests. A newly built and installed simulator package then
passed native portable recognition and persistence again (34.623 seconds, zero
failures), recorded in `native-parser-final.xcresult`. Both final iOS builds passed.

Physical XCTest remains unavailable because the free-signing app limit blocks its
separate runner. No installed application is removed to work around that limit.
Simulator and browser accessibility checks do not establish a physical VoiceOver
pass. Physical 20-scan p95, thermal/memory qualification and camera acceptance must
be reported separately from build, installation and launch checks.

## Signed package

The final package is `artifacts/private/builds/rehab-plan-ocr-lab-0.2.0.ipa`
(37,604,364 bytes), SHA256
`cf36e877aeba296ce71cb466b656ad2395b0b7ca76f11b2f798973ec6625e112`.
`codesign --verify --deep --strict` passes. The profile includes the paired iPhone
and expires **September 26, 2026, 10:57:56 UTC**. The package retains bundle
`at.rehakalender.personal`, signing team, and version 0.2.0, with **Termine** as its
display name. The unversioned private IPA alias points to this package. Neither VLM
checkpoint is included.

The first 0.2.0 update installed successfully on the physical iPhone 17 / iOS 26.6.
After the phone was unlocked, its process remained alive for over 142 seconds.
Comparing SQLite before and after launch confirmed migration from version 1 to 2,
all existing rows retained, unchanged six calendar imports and six operations,
unchanged schedule binding, and database integrity `ok`. The original scan and
setting remained; one additional scan and setting were present after launch.
This is preservation evidence, not an assertion that physical calendar or OCR flows
were fully tested. Detailed comparisons are in
`device-data-retained-at-install.json` and `device-data-retained-after-launch.json`.

That first installation used the build before the final metadata-conflict guard
(SHA256 `69bf9efbe7990ed028f51ddf242ba2925a8c94619b16c7100ec2c8289b67ce20`).
The final package above includes that guard and extraction version 4.

The final reinstall attempt found the physical device disconnected/unavailable.
The ready, signature-verified final package therefore still needs installation when
the phone reconnects. The first 0.2.0 installation and its data-retention evidence
remain valid; they are not presented as a successful installation of the later hash.
