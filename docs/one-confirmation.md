> Historical record: technical findings retained from the archived development sequence. Project dates, build labels and source references have been normalized. This record is not a new test, delivery approval or signing attestation; unaltered evidence and original validity dates are held in the external private archive.

# Laßnitzhöhe: one confirmation

The native iPhone flow is capture → plan → **Termine speichern**. A saved
calendar destination is reused. The plan opens in the originating tab; Archiv
opens the same screen. Termine separates loading, unavailable access, empty days
and populated agendas. Mehr contains general settings, recognition completion
defaults, help and diagnostics. Archiv groups retained pages and import history under one
chronological plan entry. Original deletion and calendar undo remain separate.

## Acceptance and safety

`reha_core::readiness` defines policy version 1. Required values and uncertain
essential evidence produce typed questions; optional room/therapist evidence
remains inspectable without requiring confirmation. Shared date answers require
matching retained heading observations and section membership. A manual
correction preserves the original evidence state. Explicit acceptance of a valid
reading confirms only that exception. Cancellation decisions are tied to the
current appointment value hash and expire after edits. Recovered-row and reassignment
questions have separate `issue:*` decisions, bound to the values, warning and
source geometry/provenance. They never change a printed-field state.

`service::draft::{assess, preview}` are read-only with respect to human approval
and durable data. `accept_and_save` rechecks readiness, the run revision, calendar
contents and overlaps. Only the explicitly submitted ready selection is accepted;
unresolved calendar conflicts can remain for later. Acceptance policy, timestamp,
selection/value hashes, bindings and the complete operation journal are stored
atomically before EventKit effects. Failed or uncertain writes are not counted as
saved. Existing appointments are reported separately. Value edits racing final
bookkeeping are not marked saved by older operations.

SQLite schema 6 adds `plan_acceptances` without rewriting historical run JSON or
field approvals. Legacy approval/value hashes, event identities, reconciliation
and undo remain supported. Generated Swift bindings and additive Tauri commands
expose assessment, preview, exception answers, acceptance and export. Tauri wire
helpers are in `src/lib/draft.ts`; the visual redesign is native only.

ICS export applies the same readiness rules and preserves existing UID semantics.
Export acceptance is recorded separately under `export-acceptance:*`; it grants
neither photo verification nor calendar-save status. The secondary replacement
flow still requires complete-page confirmation, resolves ownership conflicts,
and requires explicit approval of displayed removals.

## Verification

Synthetic Rust tests cover optional blanks, essential uncertainty, shared date
evidence, cancellations, read-only preview, transaction rollback, stale edits,
changed calendar contents, partial saves, conflict deferral, duplicate saves,
ICS identities, multiple pages, incomplete replacement, uncertain writes,
reopening and undo. The Swift integration probe exercises the new typed boundary
as well as legacy callers.

Native UI tests use a disposable simulator and invented fixtures. Physical
camera, VoiceOver and a complete photo-to-save walkthrough must be distinguished
from simulator tests and package/data-preservation checks.

The installed application's schema-5 Library, including data and preferences, was
copied before updating. The App Group Library directories were also copied; full
App Group roots were captured after first launch. An isolated migration copy passed SQLite integrity and
preserved every row in all 12 legacy tables and all 22 retained source files.
Private backup, migration and installation evidence is stored under
`artifacts/private/one-confirmation-20260926-s11/`.

Recognition models, extraction version 7 and the pending reference-data evaluation
remain unchanged. This delivery makes no new recognition-accuracy claim.

## Release checks (September 26, 2026)

- Shared Rust and FFI: 108 passing tests; Clippy passes with warnings denied.
- Generated bindings match; the Swift 6 strict-concurrency integration probe passes.
- Tauri host compatibility and iOS device builds pass; TypeScript, ESLint,
  13 frontend tests and 56 native agenda checks pass.
- Seven native UI tests pass, including actual EventKit save/undo, empty and
  populated agendas, grouped archive/pages, retry, retained originals, edits,
  processing navigation and dark appearance at the largest accessibility text size.
- The native accessibility audit passes for element detection, descriptions and
  traits. Screenshots were inspected in light/dark mode and at large text sizes.
- Signed native package: version `0.3.0`, build `2026092603`; bundled models and
  app/extension signatures verified. Development profiles expire September 26, 2026.

The UI tests establish interaction and accessibility-tree behavior; they do not
substitute for a physical camera and VoiceOver walkthrough.

## Installed update

Build `2026092603` was installed in place on the connected iPhone 17 / iOS 26.6
and launched successfully. After first launch, schema 6 passed SQLite integrity;
every pre-existing row in all 12 legacy tables, the preferences plist and all 22
retained source files were preserved. Startup also recovered a previously queued
image as a new retained intake/failed attempt (existing 40 MB limit); no old row
was removed or modified. No calendar destination was configured before the update,
and that setting remains unchanged. Calendar setup is therefore still needed once
on this phone.

Four focused UI tests also pass after the final screen changes. Package SHA256:
`b37d44474de3295c9f4237be93b475acacdb609098672c6acf232acc45dbb389`.
The physical photo/save/undo and spoken VoiceOver walkthrough was requested from
the user and remains pending. The device's legacy screenshot service is unavailable.

### Empty-state alignment follow-up

Build `2026092604` centers the whole empty-state block in the visible agenda area:
calendar icon, message and import actions, with 40 points between the message and
actions. Large text and future appointments remain scrollable. The existing
save/undo UI test passes, and the updated empty-agenda screenshot was inspected.
The signed update was installed in place and launched on the iPhone. The
post-installation comparison confirms all 13 database tables, retained source
files and preferences are unchanged; SQLite integrity passes. Evidence is under
`artifacts/private/empty-state-block-center-20260926-s11/`.
