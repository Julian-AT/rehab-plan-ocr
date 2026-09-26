> Historical record: technical findings retained from the archived development sequence. Project dates, build labels and source references have been normalized. This record is not a new test, delivery approval or signing attestation; unaltered evidence and original validity dates are held in the external private archive.

# Development status — 2026-09-26

All four milestones in the [implementation ledger](implementation-plan.md) remain
open. The application is native SwiftUI with Rust, SQLite, UniFFI and Apple services.
Training both custom models has produced experimental artifacts; neither model has
qualified for production. No physical device was updated during this work.

The [Zitrus & Olive appearance](../product/visual-baseline/README.md) remains the
visual contract. The last documented physical installation is build 2026092624;
the device was unavailable for a fresh inventory. Simulator evidence does not
establish current device behavior or authorize an update.

## Implemented and verified

- Explicit calendar selection, immutable query scope/revisions and obsolete-result
  rejection apply to agenda, ordinary voice queries and widgets. Save destination
  and reminders remain independent. The save/undo UI regression passes.
- Committed writes survive reminder/widget maintenance failures, including native
  alarm-journal failures. Current ownership resolves repaired event identities
  without rewriting approved historical values. Replacement previews reject stale
  comparisons/resolutions and clear deletion approval after invalidation.
- Shared final-write protections cover import/revision/undo and manual/voice edits.
  Compact imports protect externally added all-day/location geometry/availability;
  proximity alarms retain ownership. The native metadata regression passes.
- New stores default to 30-day completed-source retention. Aggregate/PDF deletion
  has a recovery journal; unfinished reviews and existing preferences survive.
  Schemas 10–11 add disposable summaries, indexed batch membership and typed
  archive pagination. The archive retains content during refresh.
- Unreadable day boundaries and neighboring-column rereads have regressions.
  Dates, minimal voice changes and explicit conversation state have native probes.
  Time constraints survive pagination; “Und danach?” rereads the visible anchor.
  Explicit dates are retained when resolving references. Both typed-query UI tests pass.
- German month names/ordinals, invalid dates, mixed-format self-corrections and
  negated field values have executable regressions. Short rejections drop pending
  mutations. The corresponding new UI scenario is still blocked by audio aborts.
- Timestamp projections avoid repeated parsing. Microphone delivery is ordered and
  bounded, with waveform publication limited to 20 Hz. Existing natural-pause
  thresholds are unchanged. Output PCM validation/decoding and camera reading/JPEG
  conversion run off the main actor and reject late canceled results.
- Sources are grouped under apps/packages/ml/tooling/config/docs/.github. All
  38,570 project-managed private files passed relocation hash checks. Normal builds
  verify pinned assets; archive/XCFramework caches verify complete input/output
  identities. Locked training environments remain separate from app dependencies.
- The runtime inventory records the selected iOS dependency graph and retained
  notices. Normal builds check its committed inputs without regeneration; native
  packaging verifies the actual bundled inventory and license texts. Public
  distribution still needs the eSpeak-NG and publisher/rights decisions.
- Targeted Rust/native/probe/UI checks pass as recorded in the ledger. The latest
  broad Rust evidence is 173 tests; native EventKit evidence is 17 tests with one
  simulator-only skip. The archive screenshot matches its pre-change fixture
  exactly below the system status bar. These are not a whole-app visual pass.

The broad simulator UI run completed 64 tests: 58 passed, five failed and one
requires a separate reduced-motion simulator setting. All five failures correspond
to CoreAudio RPC aborts while constructing the output engine. Earlier isolated
audio checks passed; the cause remains unexplained. The broad run used the build
at `53c6fe5`, before extraction v10 and the common interpretation provider. Host
clamshell sleep inflated some test durations, so they are not latency measurements.
The complete UI/audio release gate remains open.
The five affected cases now pass in separate current-build runs; the later two
passed during serial simulator use. This does not resolve the intermittent abort
or establish a complete UI pass. The [run record](../releases/history/2026-09-26-s17-ui-audio.md)
distinguishes the crashes from a separately canceled creation flow.

A subsequent complete serial run of the current runtime again ends with 58 passed,
five CoreAudio failures and one setting skip. Immediately afterwards, a minimal
independent AVAudioEngine app reproduces the same abort at mixer creation. This
establishes reproduction outside the app, but does not close the audio gate or
prove the behavior on physical hardware.

The common interpretation contract now validates capabilities, availability,
bounded requests/output, cancellation and deadlines. Rules and Apple Intelligence
share the contract; custom GGUF execution is not yet registered in the app.
All four privacy manifests pass built-bundle verification. Privacy/support drafts
are prepared; publisher/contact information and public distribution review remain open.

## Dataset and custom models

There are **20 real originals, zero approved references/crops, no frozen source
groups and no independent final holdout**. All existing images remain development
data. The [collection guide](../product/research/collection-guide.md) and consent
materials need responsible-party details and human approval before collection.
Local intake and annotation/export tooling cannot grant that approval.

Synthetic generation now validates complete text against rendered pixels and
reproduces 200 invented inputs. Geometry-aware augmentation has 40 recipes;
80 rendered variants repeat exactly, with unavailable targets removed and blank
fields assessed after cropping. These checks do not approve real references.

PP-OCRv6 Small has a matching trainable checkpoint, resumable frozen/full adaptation
and an actual interruption proof matching 902 model/optimizer tensors. Frozen
export passes 24/24 desktop parity cases; full adaptation passes 22/24 and is
rejected. Both retain 4/4 correctness on tiny synthetic validation already achieved
by the baseline. See the [OCR experiment](../../ml/experiments/2026-09-26-s17-ocr-resumption.md).

Qwen3-0.6B has a resumable LoRA trainer, validation-based selection, fusion and
complete-answer GGUF export checks. The two-process proof matches 171 tensors and
10/10 complete deployment answers, but still fails quality. The expanded run uses
112 invented training cases and 40 validation cases from separate families; it
stops after seven epochs and selects epoch four. Tuned GGUF gets 17/40 operations
exact, with 11 unsafe proposals versus seven for the baseline, and 34/40 complete
answers equal to MLX. Both quality and parity gates fail. See the
[development experiment](../../ml/experiments/2026-09-26-s17-assistant-development.md).
No calendar operation was executed by these evaluations and no provider was promoted.

The [listening preparation](../../ml/evaluation/speech/README.md) now produces 100
host previews: ten invented texts through Victoria and nine available German
system voices. Its anonymous browser form and audio-integrity checks pass. No
human listener has scored the set; no voice is selected or qualified for iPhone
release by these exports.

## Still required

Complete uncertainty/dialogue regressions,
full simulator/visual and persistence gates; remaining cleanup, CI/packaging and
paired device performance; reviewed/grouped OCR data and qualified deployment;
checked German dialogues, provider comparisons and shipping custom-model integration;
local speech/voice comparison, natural-pause and patient comprehension tests;
eSpeak-NG distribution resolution, privacy/support/release qualification and pilot.

Physical hardware, reviewed references, consented unseen data, human listening and
patient tests are external prerequisites. The intended Git remote remains unset.
These gates do not block independent implementation. Device updates require fresh
preview/listening approval, a fresh backup, update without uninstalling and a
persistent-data comparison. Historical approvals do not authorize a new update.
