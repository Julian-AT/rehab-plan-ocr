> Historical record: technical findings retained from the archived development sequence. Project dates, build labels and source references have been normalized. This record is not a new test, delivery approval or signing attestation; unaltered evidence and original validity dates are held in the external private archive.

# Development status — 2026-09-26

## Continuation from 8d81c4c

The [completion ledger](completion.md) tracks the full remaining user plan.
This continuation is **not complete product acceptance**. Storage is no longer
blocking work: after the user's cleanup, the reserve check measured 93.12 GiB
free and passed the additional 8 GiB peak allowance. Subsequent builds and the
verified workspace migration retained more than 80 GiB free.

Current verified implementation slices:

- Repository files have explicit consumer/ownership groups; a complete content
  audit remains open. Proven obsolete service wrappers and tools are removed,
  while distinct executable experiments and original visual references remain.
- Guarded cleanup removed 5,102 compiler/cache intermediates with protected-file
  hash checks. The measured first volume gain was 129.1 MiB. Hash-addressed GGUF
  copies preserve independent writes; no disk saving is claimed for APFS clones.
- Tools, the shared Python environment, Cargo and Xcode products now live under
  `.local`. A resumable hash/mode/link-checked migration preserved every inventoried
  entry and compatibility symlinks. The relocated environment passes `make doctor`.
  Candidate `026430a` now passes the full isolated app build and an offline repeat;
  the two simulator bundles are byte/mode/link-identical. The repeat took 3.17 s,
  with at least 96.49 GiB observed free. Full evidence is retained under
  `.local/runs/fresh-offline-app-20260926-s18-001/`; later changes need their own build.
- Typed native calendar reads preserve scope, occurrence identity and selection
  revision through the real Swift–Rust–Swift boundary (`b0e804e`). Recognition
  attempts now have registered, independently revocable lifetimes (`f8a3191`);
  early errors, cancellation before start, dropped callers and worker cleanup
  pass fourteen FFI tests and the native bindings probe.
- Calendar mutation requests/results now remain typed from the visible confirmation
  through the native write (`026430a`), with unchanged journal/metadata contracts:
  224 core/FFI tests, Clippy, generated bindings and actual native/voice-flow probes pass.
- Permission, reminder status and one-off notification receipts now cross Swift
  queues as typed values (`662f84f`). Seventy-one agenda/contract checks and the
  full iOS 26 native-service/integration-source typecheck pass under Swift 6 strict
  concurrency with warnings as errors. The integrated app builds at `a52d38b`;
  actual EventKit run `eventkit-20260926-s18-002` passes 18 tests with one expected
  simulator file-protection skip, including the typed notification race scenarios.
- Shared receipt publication has a visible cancellation action, a provider
  deadline and an atomic publication fence (`eadde06`). Interrupted new copies
  cannot reappear through recovery; complete receipts and originals remain intact.
  Swift scan attempts now have bounded producer/worker leases (`c9412b4`);
  2,000 controlled cycles leave no retained registrations. A timed-out native
  worker keeps its lease until actual completion. Its integrated app compilation,
  and that of the cancellation-aware image/PDF preview, pass at `026430a`;
  complete device/UI behavior remains separate.
- Typed native errors distinguish read timeouts from uncertain calendar writes.
  Binary photo decoding covers all eight orientations and the primary HEIF image.
  Request completion, stale settings replies, temporary-file erasure and partial
  intake recovery have focused native regressions.
- Durable calendar writes and saved preferences remain successful when later
  maintenance fails. Atomically recorded local bookkeeping is repaired on reopen
  without repeating calendar effects. Eight new recovery tests and thirteen
  event-mutation tests pass on the recorded slice.
- The public build no longer enables or packages the experimental Kokoro/eSpeak
  path. Both actual simulator bundles at `026430a` pass runtime/notice/privacy
  checks across all twelve embedded Mach-O files, with no Kokoro/eSpeak remnants.
  Installed German system voices now render through the app's shared audio
  graph. Host rendering, word progress, cancellation and restart pass; human
  voice selection and physical offline/audio-route qualification remain open.
- The current interpretation boundary preserves requested dates, time bounds,
  intent and event references. Replaying the existing 40 historical outputs gives
  zero unsafe proposals (trained: 33 exact; untuned/rules: 24 exact). This is neither
  fresh inference nor complete conversation acceptance; the cases form one
  connected development group. See [assistant safety](assistant-safety.md).
- SQLite is updated to 3.53.2 with the existing unsigned-value conversions and
  cache behavior retained. The targeted slice passes 206 core tests, inventory
  checks and an iOS 26.0 compilation check. The current
  [dependency audit](../releases/dependency-security-2026-09-26-s18.md) records zero
  RustSec vulnerability matches and two maintenance warnings; native-runtime
  qualification and final bundle checks remain separate.
  A [pinned local audit workflow](dependency-audit.md) now repeats that review
  offline without depending on a Homebrew installation (`150edc9`).
- Xcode product generations preserve previous files before changing a resource
  contract (`d16dacb`); twelve controlled rotation/recovery tests pass. The first
  root-workspace rotation now preserves the previous product generation under
  `.local/builds/ios/generations/53e92e4a9ff04810b6f880d5d047f6fb/` with no deletion.
  The integrated app and twelve-Mach-O bundle check pass at `a52d38b`. Bundle policy checks embedded Mach-O
  files and static archives as well as the four main executables (`619dbe5`);
  ten packaging regressions pass. These are tooling results, not a current IPA approval.

The full combined `make lint` and `make test` commands now pass at `cf4e39d`,
including 232 Rust tests, 377 Python cases in 65 groups (seven explicit environment
skips), all scheduled native probes and the actual Swift–Rust–Swift integration.
The checkout is clean before and after both commands. Source archive, source
identity and complete logs are preserved under
`.local/runs/combined-verification-20260926-s18-002/`. This closes the earlier missing
shell-entrypoint failure; it is not complete UI, physical-device or model acceptance.
The earlier fresh isolated build at `026430a` and its offline repeat remain separate
historical evidence. Later source changes still need their own combined checks.

See [inventory decisions](inventory.md), [cleanup evidence](artifact-retention.md),
[workspace/build evidence](build-reproducibility.md) and
[native boundaries](typed-boundaries.md). All four milestones in the
[implementation ledger](implementation-plan.md) remain open. Human reference,
listening and usability reviews, unseen consented data, CI billing, publisher
information, physical-device tests and explicit approval of current previews and
samples remain outstanding. No physical device was updated or public version
released.

## September 26, 2026 common simulator evidence

The complete local UI run now passes **68 tests, zero failures and zero skips**
with photo/Files fixtures enabled. The tested product sources equal `f862d5a`:
base `06ae5a3` plus the retained capture patch, verified against all app, package,
build and runtime input paths. The source archive, patch, complete result bundle,
signed staging and executable products remain in
`.local/runs/ui-complete-20260926-s19-002/`. This includes the typed core import,
agenda synchronization and pending-notification link paths. The earlier run
interrupted by host sleep remains preserved; its day-navigation case passes
in 27.013 seconds in the successful run. No physical device was updated.

The separate strict image comparison is still **failed at 14/22**. All six
remaining scrolled-list differences are confined to the missing system scroll
indicator; the normal and large content positions now match exactly. The two
finished-day views retain 1,559/87 differing pixels with maximum channel deltas
4/1. The dark legend now matches. References and tolerances are unchanged.
Complete evidence is in `.local/runs/visual-baseline-20260926-s19-003/`.

Later changes remain separately scoped: `083f82d` preserves all post-commit
maintenance warnings in calendar-link cleanup (nine targeted Rust tests pass).
`8b188d2` types system-editor occurrence identity and completion; its actual
EventKit run passes 20 tests with one expected simulator file-protection skip and
zero failures. This later source still needs its common app build and combined
checks; it is not retrospectively covered by the 68-test candidate run.

## Application and data

The app remains SwiftUI with Rust, SQLite, UniFFI and native Apple services, with
iOS 26.0 compatibility and the existing [Zitrus & Olive appearance](../product/visual-baseline/README.md).
Bundle identifiers, App Groups, database locations, approved history and existing
preferences are preserved. A read-only September 26, 2026 check finds build 2026092624
on iPhone 17/iOS 26.6, with schema 8, 15 tables and 29 scans. That partial inventory
is not a complete pre-installation backup or evidence of current candidate behavior.

Implemented and covered by the tests recorded in the ledger:

- Visible calendar scope/revisions govern agenda, ordinary voice questions and
  widgets; empty selection stays empty. Save destination and reminders are independent.
- Durable writes survive reminder/widget maintenance failures. Repaired ownership
  preserves approved history; changed inputs/snapshots invalidate replacement previews.
- Shared protections cover external edits, invitations, recurrence, alarms,
  all-day/location geometry and availability across mutation paths.
- New stores use 30-day completed-document retention, including PDFs and recovery.
  Existing preferences and unfinished reviews survive. Erasure tolerates access loss.
- Schema 11 adds indexed archive summaries and pagination. Refreshes preserve
  content and reject obsolete results; typed projections avoid repeated date parsing.
- Extraction v10 preserves unreadable day boundaries, column isolation and field
  uncertainty. German corrections, negations, invalid dates and minimal changes
  have regressions. Conversation state and captured civil time remain explicit.
- Image/audio preparation runs off the main actor. Input delivery is ordered and
  bounded; waveform updates are limited to 20 Hz. Natural-pause thresholds remain unchanged.

The seven principal directories, locked environments, explicit restore/build/export
steps, identity-checked caches and Make commands are in place. All 38,570 migrated
private files passed hash verification. Runtime/model notices and privacy manifests
are checked against actual bundles. Synthetic fixtures are used in hosted CI.

## Verification status

| Area | Current evidence and limit |
| --- | --- |
| Portable/native logic | Full `make lint` / `make test` pass at `cf4e39d`: 232 Rust tests, 377 Python cases (seven environment skips) and all native probes; tracked files unchanged. Sixteen monitor tests have separate retained evidence. Linux and physical-device behavior remain separate. |
| EventKit | Run `.local/runs/eventkit-20260926-s18-004/` passes 19 of 20 tests, with one simulator-only file-protection skip and zero failures. This includes typed import recovery, committed writes despite alarm-journal failure, and a notification link retained after failed durable acknowledgement (`9d0c240`). Complete results and executable products are retained. |
| Hosted CI | Complete results confirm run 35295159442 at `0597aab` has 62 UI passes/four failures, and run 35297619578 at `a303bc2` has 65 passes/one failure, both with zero skips on iOS 26.5. Four focused picker/import cases pass locally after excluding the temporary same-label cancel control. See the [follow-up](../releases/history/2026-09-26-s18-native-ui-followup.md). No complete candidate pass is claimed. |
| Current CI prerequisite | The latest inspected run [35382848454](archive:github/run-35382848454) at `5718dd5` is still blocked by GitHub's payment/spending-limit check before either runner starts: zero executed steps. The account prerequisite remains unresolved. No retry, payment or limit change was made by this read-only check. |
| Portable CI scope | Runs 35299521071 (`9c8d31c`), 35300286611 (`b8d31a2`) and 35302894860 (`10c5f39`) pass with their Apple jobs explicitly skipped. The latest has 174 Rust, 211 tool and fourteen monitor tests. Full remains the default for manual dispatch and the required push/PR scope. These runs do not qualify native behavior. |
| Prior hosted UI | 59 passes, three failures and one skip before the old job timeout; three cases incomplete. Focused midnight/permission/picker corrections pass locally. See the [retained report](../releases/history/2026-09-26-s18-hosted-ui.md). |
| Local audio/UI | Real playback, advancing word display and cancellation pass in runs `ui-regressions-20260926-s18-002` and `003`. Large-font week/month navigation passes in run `003`; archive editing, retained title/room, cancellation and source access pass in run `004`. Test helpers now handle native date-picker values, covered tap points and virtualized fields (`9fffab3`, `cf4e39d`). Full-suite and physical latency/audio qualification remain open. Earlier failed attempts remain preserved. |
| Reduced motion | The actual simulator Settings switch, usable speaking control, stationary app pixels and setting restoration pass without a skip. System-clock pixels are excluded from animation comparisons. |
| Appearance | All 22 original PNGs are unchanged. Current common-run comparison remains failed at 14/22: six missing scroll indicators and the two retained small finished-day raster differences. All normal/large content positions and the dark legend now match. The original 15/22 and 13/22 reports remain separate historical evidence. No baseline replacement, image alignment or tolerance hides differences. |
| Persistence | Ten synthetic backup-comparison tests cover schemas 8–11, original columns, sources, preferences and App Group journals. A fresh complete physical backup/update comparison remains pending. |
| Packaging | Signed private archive/IPA at `21ff054` passes four-component signature/profile, model, notice and privacy checks. The earliest profile expired on September 26, 2026 at 11:56:33 UTC; this is historical package evidence, not current installation eligibility. See the [package record](../releases/history/2026-09-26-s18-signed-package.md); recheck signing before any approved update. |

## Data, models and speech

There are **20 real originals, 188 provisional row occurrences, zero approved
references/crops, no frozen source groups and no independent final holdout**.
Existing photos remain development data. Collection/consent drafts and local
intake/review/export tools are prepared; responsible-party information, consent
review, verified labels and unseen schedules/speakers remain external inputs.

The OCR pipeline loads the matching PP-OCRv6 Small checkpoint, resumes model and
optimizer state, compares frozen/full adaptation and exports through ONNX parity.
The original small synthetic experiment passes frozen parity and rejects full
adaptation parity. Both pretrained/frozen models also complete actual simulator
app imports, native rereading and persisted traces on one synthetic source.
That compatibility test does not measure real-photo accuracy or physical speed.

The current v3 synthetic dataset has 512 training and 128 validation crops from
136 and 37 source groups. All seven field types have 18–19 validation crops;
title, room and notes now include unseen vocabulary. All 200 source images and
640 crops pass pixel/provenance replay without source-group, source-image or crop
overlap (`571558a`). These are synthetic development observations, not independent
real schedules. Current real-data consumers require live privacy/consent review;
old synthetic runs retain explicitly verified original training sources and
checkpoint identities (`c2cdc04`).

The preceding v2 experiments used pixel-verified synthetic tables. Whole source groups
are assigned before selecting crops; identical training pixels are excluded from
validation. The larger experiment has 512 training crops from 129 groups and 91
validation crops from 42 groups. Validation contains dates/times/therapist lines,
with no novel title/location/notes pixels. The frozen run completes four epochs
and selects epoch one (91/91 exact crops versus 90/91 pretrained), but its complete
export fails 18 of 1,206 numeric checks despite identical token sequences. Its
[model card and experiment](../../ml/experiments/2026-09-26-s18-synthetic-ocr-development.md)
remain unqualified. Full adaptation finishes five epochs, selects epoch two at
91/91 exact crops, and fails 39/1,206 numeric export checks with identical token
sequences. The original pretrained route also fails 19 numeric comparisons.
Both completed experiments are registered with failed parity. These results cannot
qualify real-photo recognition. Stage diagnosis reproduces the saved Paddle graph
bit-for-bit after the official reparameterization on all 18/39 failed cases;
static-Paddle-to-ONNX differences remain separate and unresolved. An alternative
export without reparameterization eliminates dynamic/static differences on those
57 cases but still fails ONNX numeric parity; disabling optimization also leaves
failures. These alternatives remain diagnostic and excluded from the app.
The precommitted [bounded convolution experiment](../../ml/experiments/2026-09-26-s18-ocr-convolution-stage.md)
then fails its first full-graph case: one of 748,400 numeric values exceeds the
unchanged gate, despite matching tokens. The remaining eleven selected cases
and full corpus were not run. The isolated exact operation is insufficient; no
model was promoted and original weights/reports remain unchanged (`4ef8f3c`).
Critical-field metric
version 2 covers appointment identity, room and therapist as well as dates/times,
and row-level regression checks catch relocated missing/invented appointments.

Qwen3-0.6B LoRA training, resumption, fusion and GGUF export produce experimental
artifacts. The tuned assistant fails quality and complete-output export parity.
In the same app binary on 40 invented development cases, untuned routing gives
four exact operations and two wrong mutation proposals; tuned gives 17 exact and
11 wrong proposals, all eleven newly wrong relative to that comparator. Rules
answer four cases; the simulator's Apple model route fails at a missing system
component. No evaluation executes a calendar operation or promotes a provider.
The [comparison](../../ml/experiments/2026-09-26-s18-app-provider-comparison.md) excludes
speech and earlier VoiceModel rules; complete shipping-workflow evaluation remains open.
An [explicit backend/batch diagnostic](../../ml/experiments/2026-09-26-s18-assistant-backend-parity.md)
reproduces all six prior export divergences with automatic backend selection and
both CPU batch configurations. Changing these settings supplies no parity or
quality fix; all original model gates remain open.
Subsequent [token diagnosis](../../ml/experiments/2026-09-26-s18-assistant-token-parity.md)
found that the old CLI text-file option removed a final newline, changing input
tokens despite unchanged token counts. All four consumers now preserve exact
prompt bytes (`2d38d8e`). All forty MLX instrumentation controls reproduce the retained fused answers.
The corrected complete CLI comparison finishes at 38/40 identical outputs; two
differences remain, so export parity still fails (`5e24ed8`). Replaying the forty
new native answers through the current Swift router gives 33 exact operations,
zero unsafe proposals and zero newly incorrect results relative to both retained
variants (`35269e1`): 24 rule answers and 16 admitted model answers. These cases
are one connected development group, without speech, independent real dialogs
or fresh inference in the replay; complete conversation acceptance stays open.

Nine installed German system voices now have 90 anonymous host previews rendered
by the actual product provider, with 1,782 checked word-progress markers and no
failed render. The retained evidence is
`.local/runs/listening-system-renderer-20260926-s18-001`; human scores and current
iPhone recordings are still absent. The earlier ten-voice, 100-preview experiment
also included the retired experimental voice and remains separate evidence.
A separate host SpeechTranscriber setup and [100-file ASR experiment](../../ml/experiments/2026-09-26-s18-file-speech-recognition.md)
finish successfully, exposing name/title/abbreviation discrepancies. Number
formatting differences are not factual error scores. No voice or speech provider
is selected from synthetic file recognition. A separately installed de-DE module
also completes the same files with 100/100 identical final transcripts to de-AT;
this comparison adds no independent speakers or prompt families. Human listening, actual speakers,
natural endpoints and the complete iPhone route remain required.

## Remaining acceptance

- Complete hosted/native UI and deterministic visual acceptance on the candidate.
- Reviewed and grouped real references, privacy masks, checked German dialogues
  and consented unseen evaluation data; qualified model improvements.
- Paired physical quality/latency/resource measurements, including first usable
  content, audio startup, natural pauses, interruptions, thermal and energy effects.
- Older iOS/non-Apple-Intelligence hardware and eligible Apple hardware; denied or
  revoked permissions, airplane mode, Bluetooth, backgrounding and long sessions.
- Human voice/comprehension and patient usability studies; a justified provider/voice choice.
  [Nine task cards and a session record](../product/research/usability-rounds.md)
  prepare the two rounds of at least five people; no sessions have been conducted.
- Publisher/contact details, final public-package rights and branding-rights checks,
  complete privacy/support materials, internal acceptance and a small TestFlight pilot.
- Explicit current preview/listening approval, then a fresh complete backup,
  in-place installation and persistent-data comparison. Historical approvals cover
  their historical updates only.

The intended remote is `https://github.com/Julian-AT/rehab-plan-ocr.git`. CI branches
are separate from remote main. Detailed completed slices, failures and private
report identities remain in the implementation ledger and linked experiment records.
