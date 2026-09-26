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
- [ ] Replacement-preview invalidation on changed inputs and calendar snapshots.
- [x] Local erasure despite calendar access loss, with restoration limitations.
- [x] Aggregate retention including PDF originals; no expired-page resurrection.
- [x] Correct Today deep links.
- [x] Unreadable day boundaries and neighboring-column reread contamination.
- [ ] Preserve field uncertainty, blanks, missing/cropped/contradictory evidence.
- [ ] Invalid spoken dates, corrections, negations and partial changes.
- [ ] Explicit conversation states and older-iOS current-request recovery.
- [ ] Regression tests, simulator appearance and persistent-data verification.

### 2. Clean platform and responsive interactions

- [ ] Mechanical moves to apps/packages/ml/tooling/config/docs/.github.
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
broader cache work, private working-asset migration and cleanup remain open.
Agenda event projections now cache parsed timestamps, with wire values preserved
through edits and encoding. Two targeted agenda/voice UI tests passed. A five-pair
desktop microbenchmark is recorded in
[the projection experiment](../ml/experiments/2026-09-26-s16-calendar-projection.md).
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
See [the experiment record](../ml/experiments/2026-09-26-s16-checkpoint-compatibility.md).
This is a synthetic pipeline smoke test, not a promoted OCR checkpoint or a
real-photo quality result. Qwen3 completed eight LoRA steps, fusion, GGUF export and
local runtime execution with hashes and lineage. Its first-token fusion probe
passed 12/12 cases; full-answer parity is unverified. Both base and tuned artifacts
failed all 12 strict structured-output cases and remain unqualified. See
[the assistant experiment](../ml/experiments/2026-09-26-s16-assistant-compatibility.md).
The portable Python tooling tests include eight intent-contract tests and exact
screenshot comparison checks. No new whole-app visual or device-performance claim
follows from the isolated archive verification.

The known iPhone 17 was unavailable during the read-only device inventory. No
device was updated. No real-device speed, energy, thermal or usability improvement
has been claimed. Milestones 1–4 remain open until their complete exit gates pass.
