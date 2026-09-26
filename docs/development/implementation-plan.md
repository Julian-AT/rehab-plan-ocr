> Historical record: technical findings retained from the archived development sequence. Project dates, build labels and source references have been normalized. This record is not a new test, delivery approval or signing attestation; unaltered evidence and original validity dates are held in the external private archive.

# Offline rehabilitation calendar — implementation ledger

Source baseline: `53ddd32` (2026-09-26). This ledger implements the four-milestone
plan supplied by the user. It replaces historical status claims where they conflict
with the live repository; older reports remain evidence of their original runs.

## Fixed contract

Preserve the installed Zitrus & Olive appearance, bundle identifiers, App Groups,
database paths, existing preferences, approved evidence and recovery journals.
Support iOS 26.0, offline operation after setup, natural German conversational
pauses and visible confirmation for every calendar mutation. Visible calendars
govern agenda, ordinary voice answers and widgets; save destination and reminders
are independent. New installations default to 30-day completed-source retention.
Both custom models must be trained and evaluated before the project is complete.

## Delivery checklist

### 1. Reliable baseline

- [ ] Record source/build/toolchain/model/schema/device and visual baseline.
- [x] Reconcile current dataset, reference approvals and grouping.
- [x] Immutable calendar scope; explicit empty selection; stale-result rejection.
- [x] Resolve repaired identities without rewriting historical approved values.
- [x] Durable save outcomes independent of reminder/widget failures.
- [ ] Shared external-edit, invitation, recurrence and alarm protection.
- [x] Replacement-preview invalidation on changed inputs and calendar snapshots.
- [x] Local erasure despite calendar access loss, with restoration limitations.
- [x] Aggregate retention including PDF originals; no expired-page resurrection.
- [x] Correct Today deep links.
- [x] Unreadable day boundaries and neighboring-column reread contamination.
- [ ] Preserve field uncertainty, blanks, missing/cropped/contradictory evidence.
- [ ] Invalid spoken dates, corrections, negations and partial changes.
- [ ] Explicit conversation states and older-iOS current-request recovery.
- [ ] Regression tests, simulator appearance and persistent-data verification.

### 2. Clean platform and responsive interactions

- [x] Mechanical moves to apps/packages/ml/tooling/config/docs/.github.
- [ ] Consumer inventory, documentation consolidation and verified private migration.
- [x] Separate make targets for restore/generate/convert/build/test/package.
- [ ] Read-only normal-build manifest verification and identity-based caches.
- [x] Independent locked training and app-tooling environments.
- [ ] Discoverable isolated tests and portable/native/simulator/policy/package CI.
- [x] First content independent of reminder reconciliation; coalesced refreshes.
- [x] Typed timestamp projections, indexed archive summaries and pagination.
- [ ] Background image/audio processing, bounded buffers and waveform updates.
- [ ] Paired measurements for latency, memory, energy, thermal and session reuse.

### 3. Custom OCR

- [ ] Verified references, reviewer provenance, crop approval and privacy masks.
- [ ] Freeze source-related development groups before augmentation.
- [ ] Collection/consent guide and local intake/label validation.
- [ ] Geometry-aware augmentation and pixel-checked reproducible synthetic plans.
- [ ] Matching PP-OCRv6 Small training/export/runtime smoke test.
- [ ] Frozen-backbone versus full fine-tuning, resumable lineage and validation stop.
- [ ] Grouped critical-field/correction evaluation; ONNX parity before quantization.
- [ ] Evaluated custom checkpoint, deployment artifact and model card.

### 4. Assistant, voice and qualification

- [x] Qwen3-0.6B LoRA/fusion/export desktop smoke test (quality gate failed).
- [ ] Checked German structured-intent data and independent dialogue families.
- [ ] Common provider contract; compare rules/Apple/untuned/tuned models.
- [ ] Evaluated custom checkpoint and supported offline capability fallbacks.
- [ ] Real German speech, natural-pause and local-voice listening comparisons.
- [ ] Resolve eSpeak-NG distribution dependency before public packaging.
- [ ] Device performance, permission/offline/Bluetooth/background/stability tests.
- [ ] Privacy/support/license inventory and release candidate.
- [ ] New simulator previews and listening samples approved by the user.
- [ ] Fresh backup, update without uninstalling and persistent-data comparison.
- [ ] Internal acceptance and small TestFlight pilot before public submission.

## External prerequisites

Human approval of transcription/crops cannot be manufactured by training tools.
The [German collection guide](../product/research/collection-guide.md) and a consent
draft are prepared. Responsible-party details and the actual consent process still
require completion before collection. New local intake verifies consent scope,
receipt hashes, retention and original copies without granting annotation approval.
Unseen schedules, consented speech, patient comprehension/listening tests and
physical devices are required for the corresponding acceptance gates. The intended
Git remote is not configured. Do not activate hosted CI against an invented remote.
Do not promote a model from synthetic-only quality scores or correlated derivatives.

## Verification record

The starting working tree was clean. About 61 GiB was available, superseding the
older low-disk-space report. `make test` was started against the baseline; subsequent
entries must distinguish portable/native tests, simulator builds, physical evidence
and unperformed validation. No device update is authorized by this ledger.

## Verified implementation slices — 2026-09-26

Calendar queries now carry immutable selected IDs, timezone and a monotonically
increasing selection revision. Agenda caching rejects changes, including A→B→A,
and reminder maintenance no longer blocks first content. Widget display follows
the same calendar selection, including external events; reminders still use
ownership. A committed mutation returns a durable success with separate warnings.

Source retention now uses schema 9 and journaled aggregate deletion. New stores
receive 30 days; existing preferences and unfinished reviews are preserved. PDF
originals and their pages expire together; startup replays interrupted deletions
and deleted originals cannot be rasterized again. Repaired calendar identities
are resolved through current ownership without rewriting original approved values.
The full preview is revalidated before recording a new calendar write.

The parser preserves unreadable day boundaries and validates comma-separated
dates. Field rereads touching neighboring column edges cannot become accepted
values. Voice requests use explicit interaction states, validate dates and retain
the current request when older FoundationModels sessions exceed context limits.
Title/duration changes produce minimal patches. Broader German dialogue coverage
and actual older-iOS inference remain open.

Verification: 169 Rust workspace tests passed; workspace Clippy passed with warnings
as errors. The native calendar suite completed 14 tests with one simulator-only
skip and zero failures. Voice/date/state probes and four model-restoration tests
passed. The current simulator app builds. The Today-link UI regression passed.
A broad UI run found an audio timeout and an obsolete save-receipt assertion;
the isolated real-audio rerun passed. The completed conversation receipt now
survives a subsequent question; the save-confirmation UI regression passed after
correcting its obsolete wording. The full UI suite is not yet green.

Feature, Apple/Rust package, tooling and ML moves preserve source behavior and
resource contents. Build targets separate online restoration, offline conversion,
binding generation, compilation and packaging; normal builds verify pinned assets.
An offline simulator build passed. Source/toolchain caches cover phonemizer builds;
broader cache work and cleanup remain open. Private datasets, model/runtime working
files and previous artifacts/backups have moved to `.local/`: all 38,570 regular
files passed before/after SHA-256 checks. Active consumers use canonical paths;
ignored aliases preserve old references and the linked converter checkout. New
phonemizer caches build outside model storage, under `.local/builds`. Asset/VAD
checks, 54 Python tests and an offline simulator build passed after relocation.
Agenda event projections now cache parsed timestamps, with wire values preserved
through edits and encoding. Two targeted agenda/voice UI tests passed. A five-pair
desktop microbenchmark is recorded in
[the projection experiment](../../ml/experiments/2026-09-26-s16-calendar-projection.md).
Schema 10 adds disposable compact archive summaries, deterministic chronological
indexes and transactional backfill. Original runs/preferences remain unchanged;
four new cache/migration regressions, the workspace suite and simulator build pass.
Schema 11 adds indexed batch-document membership and typed keyset archive pages.
The archive reads 20 summaries per page and loads full evidence through existing
detail APIs. Refresh keeps the prior loaded range, coalesces matching requests and
rejects canceled/superseded results. Four more Rust regressions, the real generated
Swift/Rust binding probe, the isolated Swift archive state probe and the simulator
archive/cold-launch test pass. The archive screenshot matches the pre-pagination
capture exactly below the 160-pixel system status bar; the fixed reference is in
`apps/ios/Tests/Visual`. The first UI attempt stalled in simulator OS migration
before app tests started; a fresh disposable-simulator run completed successfully.

Training environments are separately locked and load successfully. The official
PP-OCRv6 Small training checkpoint matches all 422 state tensors and the exact
shipping dictionary. Four optimizer steps on eight invented training lines,
export and conversion to ONNX completed; 24/24 Paddle/ONNX parity cases passed.
See [the experiment record](../../ml/experiments/2026-09-26-s16-checkpoint-compatibility.md).
This is a synthetic pipeline smoke test, not a promoted OCR checkpoint or a
real-photo quality result. Qwen3 completed eight LoRA steps, fusion, GGUF export and
local runtime execution with hashes and lineage. Its first-token fusion probe
passed 12/12 cases; full-answer parity is unverified. Both base and tuned artifacts
failed all 12 strict structured-output cases and remain unqualified. See
[the assistant experiment](../../ml/experiments/2026-09-26-s16-assistant-compatibility.md).
The portable Python tooling tests include eight intent-contract tests and exact
screenshot comparison checks. No new whole-app visual or device-performance claim
follows from the isolated archive verification.

The known iPhone 17 was unavailable during the read-only device inventory. No
device was updated. No real-device speed, energy, thermal or usability improvement
has been claimed. Milestones 1–4 remain open until their complete exit gates pass.

## Verified implementation slices — 2026-09-26

The collection guide, consent draft and local intake copy verified incoming files
without replacing the reference inventory or granting approval. Purpose/receipt,
retention, speaker grouping, interrupted-copy and existing-inventory checks pass.
Actual participant access, completed consent materials and review remain external
prerequisites.

The OCR adapter materializes approved, separately reviewed crops with grouped
provenance and rechecks live approvals before training/resume/export. Its tests use
invented references; the 20 private originals remain unapproved. The CPU trainer
supports frozen-backbone and lower-rate full adaptation, label-derived lengths,
atomic epoch checkpoints, Adam-state resume and validation stopping without a time
cap. A SIGTERM after step five replayed the interrupted epoch; all 902 model and
optimizer tensors matched uninterrupted execution and all 295 frozen backbone
state tensors remained unchanged. Both synthetic modes stopped at epoch two and
selected epoch one with 4/4 validation crops, matching the pretrained baseline.

Frozen-backbone ONNX export passes 24/24 numerical/token comparisons. Full adaptation
passes 22/24 numerical comparisons and 24/24 token comparisons; its export is
rejected. Disabling runtime graph optimization does not resolve the two numerical
failures. Both conversions repeat identically with network access denied after
disabling the converter's optional automatic dependency installation. These are
pipeline mechanics, not clinical or physical-device qualification. The
[experiment](../../ml/experiments/2026-09-26-s17-ocr-resumption.md) and
[artifact card](../../ml/registry/ocr-adaptation-smoke-002.json) preserve the results.

Microphone observations now cross to the main actor through one ordered consumer
and a bounded 64-packet channel, replacing a task per level/VAD observation.
Overflow invalidates the input instead of silently dropping speech. PCM work is
bounded before conversion; VAD borrows each 20 ms frame instead of copying it.
Level smoothing retains every buffer while observable waveform updates are capped
at 20 Hz. The existing 1.2/2.5-second endpoint thresholds are unchanged.
The channel, PCM and conversation probes pass, including cancellation, conversion
failure, delayed pause evidence and buffer limits. The current simulator test build
passes. Waveform/stop/background and silent-input UI tests pass. The real-output UI
test fails: a CoreAudio RPC timeout aborts the simulator app in
`ConversationAudio.attachPlayer`, before playback. This does not establish a device
regression or a full UI pass; output and physical pause/latency qualification remain
open. The simulator fixture tests level publication; the separate channel probe
tests the production delivery mechanism.

Native import/manual/voice alarm-journal failures now return committed success with
separate maintenance warnings. The typed Rust/UniFFI result carries these warnings
through import, replacement, undo and reconciliation; old serialized results remain
readable. Event mutations preserve native warnings when later agenda maintenance
also fails. Existing success panels show a secondary maintenance notice.

A native regression blocks the alarm-journal destination after startup, verifies
both EventKit write paths, reopens the edit service and replays the durable receipt
without creating another event. The native suite passes 15 tests with one expected
simulator file-protection skip. Its relocated widget/notification sources are now
included explicitly, without their conflicting extension Info.plists; a portable
path check detects missing Xcode sources. A fresh simulator installation gets one
bounded retry for unavailable installation services. Rust import/undo, legacy
result, merged-warning and Swift/Rust binding regressions pass, as do Clippy and
the offline simulator build. The full UI gate remains open.

The save/undo UI regression now follows the visible-calendar contract: saving into
the destination leaves an empty display selection unchanged, explicit selection
shows each imported event once, and undo preserves that selection while removing
the events. It passes in a fresh disposable simulator (59.369 seconds). Targeted
calendar/voice runs can skip unrelated Photos/Files fixture setup with
`REHA_UI_MEDIA=0`; full runs keep those fixtures by default. Repeated real-output
and voice-confirmation UI runs still abort in CoreAudio's `AURemoteIO::Cleanup`
RPC timeout during `ConversationAudio.attachPlayer`. Their failures remain open;
the save/undo pass does not qualify speech output or the full UI suite.

Replacement previews now retain the exact comparison inputs and reject late
comparison/resolution results after input changes, A→B→A changes, calendar-store
notifications or leaving the screen. Each suspension before subsequent preparation
writes checks the request again. Resolution retains visible rows while busy;
invalidations clear deletion approval. Failed commits discard the obsolete preview,
and successful committed receipts remain independent of later invalidation. The
new native state probe passes; the simulator app builds with Swift 6 checking.
Backend snapshot/revision validation remains the final write-time protection.

Native archive/XCFramework assembly now uses content-addressed storage under
`.local/builds/ffi`. Identities cover compiled archives, Rust sources, headers,
model/runtime pins, architecture, SDK and toolchains. Cache hits verify every
artifact hash and reject extra/missing/corrupt files. A package symlink exposes only
complete products; initial directory migration rolls back publication failures.
Seven isolated cache regressions pass. The first simulator build and warm repeat
both pass; the repeat took 5.604 seconds locally and preserved all five framework
file/link timestamps without Swift recompilation. This is a development-build
measurement, not device runtime performance. Existing legacy build products remain
available until their separate consumer-inventoried cleanup.

The German assistant now has a resumable development trainer and complete-answer
export gate. Thirty-eight disjoint invented scenario families cover calendar facts,
constraints, corrections, negations, minimal changes, cancellation and app help;
human language review remains pending. Data validation rejects family/speaker
leakage, hidden references, invalid labels, duplicate prompts, final holdout and
stale review hashes. Eight new contract/checkpoint tests and eight intent tests pass.
Two-process resume matches all 171 adapter/Adam/random tensors and validation
answers against uninterrupted training. Ten complete answers match across adapter,
fusion and desktop GGUF. The tuned model still has only 4/10 exact development
operations and one unsafe proposed mutation, so it remains unqualified. See the
[resumption experiment](../../ml/experiments/2026-09-26-s17-assistant-resumption.md).

Speech-output PCM validation/conversion now runs off the main actor. The decoder
checks the entire canonical PCM16/24 kHz/mono WAV header, declared lengths, alignment
and a five-minute per-phrase allocation bound before conversion. Cancellation is
checked during conversion; a superseded playback generation cannot start late.
Exact-sample, malformed-header, truncation, size-limit and cancellation probes pass.
The simulator build and both real-output/voice-confirmation UI regressions pass.
The UI launch helpers now wait for enabled tabs: the persistent-data recovery gate
already displayed disabled tabs, and the initial test tapped before that gate opened.

Before the PCM change, an independent minimal AVAudioEngine app and the two original
output UI cases also passed without changing the production audio setup. The earlier
CoreAudio RPC abort is therefore intermittent and remains unexplained; neither the
successful reruns nor off-main PCM decoding establish its resolution. No device,
latency, energy or pause-handling qualification follows from these simulator runs.

Calendar answers now preserve morning/afternoon and explicit clock bounds, including
pagination. Invalid or contradictory bounds are rejected; all-day events are not
given invented clock times. “Und danach?” resolves the previous event from live
visible records and selects following events without repeating it. An explicit
requested date survives reference resolution; an incompatible detail date asks
for clarification. A hidden/deleted anchor cannot drive a later page. The expanded
native conversation probe and simulator build pass, and both typed-calendar UI
regressions pass (127.642 seconds). The added cross-day reference regressions pass
in the final native probe. These checks do not qualify model interpretation or
physical speech latency.

Camera file reading and JPEG conversion now run on a detached worker. A single
accepted result is delivered on the main actor; dismissal cancels the worker and
rejects late success or failure. Duplicate delegate completion cannot import
another image. The synthetic concurrency probe verifies that the UI actor remains
responsive during blocked conversion, plus failure/cancellation/one-delivery
behavior. The Swift 6 simulator build and camera/Photos/Files entry-point UI test
pass (28.613 seconds). Actual camera capture still requires physical-device checks.

The expanded assistant training stopped after seven epochs and selected epoch four.
Its 40 validation cases represent ten invented families. Tuned GGUF achieves
17/40 exact operations, but produces 11 unsafe proposals versus 7 for the baseline.
Fusion agrees on 40/40 complete answers; GGUF agrees on only 34/40. Both gates fail;
the model remains experimental. See the [full development result](../../ml/experiments/2026-09-26-s17-assistant-development.md).

Documentation now follows product/architecture/development/releases/third-party
ownership, with dated reports explicitly historical. Twenty-two chosen visual
reference images retain their original bytes. The 450 retired preview assets and
14 unused web-shell notices have path/size/SHA-256 inventories; every removed blob
was recovered from the recorded Git revision and hash-verified before commit.
Private data, backups, history and runtime-required notices remain intact. Current
local links, baseline hashes and exact notice manifests have four portable policy
checks, included in normal tool tests. All tool tests, asset verification and the
simulator build pass; the built app contains exactly the 14 retained notices.
