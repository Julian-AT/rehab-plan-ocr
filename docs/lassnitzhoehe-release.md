> Historical record: technical findings retained from the archived development sequence. Project dates, build labels and source references have been normalized. This record is not a new test, delivery approval or signing attestation; unaltered evidence and original validity dates are held in the external private archive.

# Laßnitzhöhe implementation — 11 September 2026

This extends the installed SwiftUI/shared-Rust restructure. The full accuracy and
minimal-review release is **not yet accepted**: new photos, human-approved labels
and physical iPhone acceptance are still required. The portable extraction and
existing explicit review remain active. No automatic field acceptance, fabricated
human confirmations, cloud extraction, model replacement or fine-tuning was added.

## Implemented scope

| Plan step | Implementation / remaining gate |
| --- | --- |
| 0 | Ordered transactional migrations through SQLite version 5, newer-version rejection, retained-data upgrade verification. The physical performance baseline remains a device gate. |
| 1 | Frozen portable baseline; negative/unusable reference classes; readiness counts and denominator reporting. Existing 20 references remain unapproved; approximately 20 additional plans and 10 negative/unusable inputs are missing. Final groups and policy cannot yet be frozen. |
| 2 | Laßnitzhöhe product/display names, native and fallback branding, Termine / Archiv / Mehr, separate native stacks and iOS 26 minimize-on-scroll. Persistent identifiers remain unchanged. The dedicated default calendar is renamed only through its saved destination, preserving user names and unavailable-calendar protections. |
| 3 | Immutable original bytes are durably staged before decoding/model loading. AVFoundation shutter opens results immediately; Photos uses the same intake. Failures and interrupted work retain originals and retry. Late callbacks preserve their source without changing current navigation. Retention defaults to until deleted, including existing scans; optional expiry skips unfinished work. |
| 4 | Durable import batches, original operation outcomes, archive import history and inverse previews. Undo removes creations, restores previous updates and can restore proven deletions. External edits, later imports, alarms and recurring events remain protected. Queued operations resume only when the journal proves they never started; uncertain operations reconcile first. Failed undo operations can be explicitly previewed again without repeating completed inverses. Historical source-to-batch relationships are not guessed. |
| 5 | Parent plans, ordered pages and processing attempts; legacy scans keep their appointment IDs and serialized approval records. Pages are stored immediately and OCR jobs run sequentially with the existing 60-second limit per page. Multiple dates remain separate; incomplete groups cannot prepare a replacement that removes missing appointments. Pages can be detached without deleting the source. |
| 6–8 | **Gated on step 1.** Parallel Vision evidence, changed interpretation/activity policies, all-day temporal contracts, tuned evidence thresholds and exception-only review are not enabled. Current explicit field review and calendar confirmation remain in force. |
| 9 | Existing exact reimports, identity matching and three-way comparison remain. Native UI allows explicit previous-plan association. Accessible-calendar overlaps are separate from ownership conflicts and are rechecked before writing. New automatic suggestions for revised captures await evaluated evidence rules. |
| 10 | Files intake, durable PDF originals, stable ordered PDF pages, retained PDFKit text/character geometry, portable OCR of pages, PDF source viewing, and a share extension that only stages receipts. PDFKit text does not bypass review or replace OCR; automatic text-layer interpretation and bidirectional field navigation await step 6. Real provider handoffs remain a physical acceptance gate. |

The share extension uses `group.at.rehakalender.personal.intake`. The existing
widget and notification group remains restricted to its existing payload. App,
widget and notification bundle IDs remain unchanged; the new share extension is
`at.rehakalender.personal.share`. Native build number is `2026092602`.
Intake currently accepts originals up to 40 MB and plans/PDFs up to 12 pages.

## Recovery and baseline evidence

The pre-existing tracked diff and untracked source files were preserved before
editing in `artifacts/private/lassnitzhoehe-baseline-20260926-s11-200014`. Existing
private device backups and both preserved IPAs remain under
`artifacts/private/native-iphone-update-20260926-s11-191945`. A fresh phone/container
backup was also taken before the in-place installation documented below.

The unchanged portable pipeline completed all 20 existing development photos on
the Mac. Reported pipeline times ranged from 2,232 to 6,125 ms. These are CLI
pipeline times, not full camera-to-result, physical iPhone or accuracy results.
Binary/config/model/source hashes and raw runs are preserved in
`artifacts/private/lassnitzhoehe-portable-baseline`.

An isolated copy of the previous device backup was upgraded from schema 2 to 5.
SQLite integrity remained `ok`; all serialized legacy table hashes and all 40
retained file hashes were unchanged: 11 scans, 44 imports, 44 operations,
5 schedules, 3 settings and 2 failures. The source backup was untouched. Evidence:
`artifacts/private/lassnitzhoehe-upgrade-result.json`. This is a retained-data
migration check, not a physical in-place installation test.

**Rollback requires a matching binary and container backup.** The old preserved
binary writes schema version 2 unconditionally and cannot safely open the migrated
database. The updated Tauri fallback uses the same new migrations and journal
states as SwiftUI. Do not uninstall as an upgrade or rollback step.

## Verification commands

Use `PATH="$HOME/.cargo/bin:$PATH"`, `CARGO_PROFILE_DEV_DEBUG=0` and
`CARGO_INCREMENTAL=0` in this environment to avoid duplicate debug artifacts.

```sh
cargo test --locked -p reha-core -p reha-ffi
npm run lint && npm run build && npm test
npx playwright test
uv run --with pillow==12.1.0 python tests/test-reference-data.py
uv run --with pillow==12.1.0 python tests/test-dataset.py
sh scripts/test-agenda.sh
sh scripts/build-native.sh integration
sh scripts/build-native.sh check-bindings
sh scripts/build-native.sh test
cargo check --locked -p rehab-plan-ocr
sh scripts/build-ios.sh simulator
sh scripts/build-ios.sh device
sh scripts/build-native.sh archive
```

## Local verification results

- All 93 shared Rust/core and FFI tests passed. They cover migrations, immutable intake, archive-index
  recovery, attempt-journal failure, stale reviews, ordered PDF identities, batch
  undo, failed/uncertain/queued undo recovery, and changed-overlap rejection.
- Frontend lint, production export, 13 unit tests and Chromium/WebKit browser
  checks passed. The new failed-capture deletion test verifies the explicit
  confirmation and that no calendar-write command is called.
- All 11 reference/dataset Python tests passed. Readiness remains 20 original
  plan photos, zero approved references and zero negative/unusable examples.
- All 56 Swift agenda policy checks passed. The strict Swift 6/Rust integration
  probe and regenerated UniFFI consistency checks passed.
- Native simulator checks passed for tabs/settings/cold launch, retained source
  viewing, preservation of unsaved edits, and real bundled ONNX recognition while
  switching tabs. Screenshots were inspected; physical visual acceptance remains
  pending.
- Native Release device linking and both Tauri iOS variants passed without
  provisioning. The Tauri host `cargo check` also passed.
- The isolated schema-2 backup upgrade preserved all legacy serialized records
  and retained source files, as described above.

The initial signed archive failed at provisioning. After the account became
available to the command-line build, Xcode refreshed the app and share-extension
profiles, including the separate intake App Group. Signed packaging and the
USB installation subsequently succeeded on 11 September 2026.

The package check also caught the Unicode executable being included in its own
resource seal. The product/display name remains Laßnitzhöhe; the internal
executable keeps its original ASCII name, `Termine`. The share extension now
explicitly targets iPhone, matching the main app. All four signatures, profile
entitlements, connected-device authorization, model and license hashes passed.

**Installed and launched on the connected iPhone 17:** version 0.3.0, build
2026092602. No uninstall was performed. Immediately after installation, all
legacy SQLite rows matched the fresh phone backup. After launch, the schema
upgraded from 2 to 5 with integrity `ok`; all legacy row hashes, settings and
retained source-image hashes remained unchanged. The same app process remained
running during the subsequent check. Recovery journals and the existing App
Group files were preserved. OS caches/scene state and the agenda snapshot changed
as expected on launch. This verifies installation and retained-data migration,
not the remaining physical camera, performance, accessibility or calendar gates.

The verified IPA and fresh app/container backups are under
`artifacts/private/lassnitzhoehe-iphone-update-20260926-s11-205122`. Package SHA256:
`a023563c216c2c1e8a126327615146d5f4adc8174522962bfdc062de3c02c58a`.
The earliest development profile expires on 18 September 2026 at 11:56:33 UTC;
re-sign before then to keep all extensions available.

Logs, dataset readiness and synthetic simulator screenshots are preserved locally
in `artifacts/private/lassnitzhoehe-verification`. Build checks were run locally;
the GitHub workflow was not executed in this session.

The signed archive path is `apple/build/Laßnitzhöhe.xcarchive`; packaging discovers
the product from archive metadata and verifies identities, versions, entitlements,
model/license hashes and every signature. The package is
`apple/build/Laßnitzhöhe.ipa`. This build additionally needs an intake App Group and
share-extension provisioning profile. Signing is restricted to explicit archive
mode; it does not install or publish the application.

Physical acceptance still covers 20 representative captures without losses or
growing memory, cold/warm latency and thermal behavior, tap feedback within
100 ms during OCR, real EventKit conflicts/undo/reminder recovery, share handoffs,
VoiceOver, large text, dark mode, reduced motion/transparency, widget deep links,
and a backed-up signed in-place upgrade. The 30-second p95 target and 60-second
per-page processing budget are distinct. Simulator checks cannot establish these
physical results.
