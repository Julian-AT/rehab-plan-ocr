> Historical record: technical findings retained from the archived development sequence. Project dates, build labels and source references have been normalized. This record is not a new test, delivery approval or signing attestation; unaltered evidence and original validity dates are held in the external private archive.

# Development status — 2026-09-26

All four milestones in the [implementation ledger](implementation-plan.md) remain
open. The application is native SwiftUI with Rust, SQLite, UniFFI and Apple services.
Training both custom models has produced experimental artifacts; neither model has
qualified for production. No physical device was updated during this work.

The [Zitrus & Olive appearance](../product/visual-baseline/README.md) remains the
visual contract. A fresh read-only inventory reconfirms build 2026092624 on iPhone 17
with iOS 26.6. The device reconnected during the September 26, 2026 session; schema 8,
15 tables and 29 scans are verified from a copied database. Simulator evidence and
this inventory do not authorize an update or establish current candidate behavior.

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
- Local backup comparison is now reusable and tested: schemas 8–11, original table
  projections, preferences, sources and App Group journals are checked without
  opening the backup DB in place. Ten synthetic regressions and a recheck of the
  retained September copies pass; changed historical diagnostics are flagged.
  All 167 tool tests and lint pass. Fresh physical backup/update comparison remains pending.
- Unreadable day boundaries and neighboring-column rereads have regressions.
  Dates, minimal voice changes and explicit conversation state have native probes.
  Time constraints survive pagination; “Und danach?” rereads the visible anchor.
  Explicit dates are retained when resolving references. Both typed-query UI tests pass.
- Conversation day boundaries, live references, pagination and spoken times retain
  the request's timezone. A reproduced DST cache collision is fixed; deterministic
  23/25-hour and cross-zone regressions pass with the simulator build.
  Rules, Apple/custom interpretation and pending mutation confirmation now also
  retain one captured civil clock; stale custom prompt dates/zones are rejected.
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
- Shared package verification now checks the app, three extensions, exact model
  bundles including the OCR dictionary, privacy declarations and notices. The
  actual simulator and fresh unsigned device builds pass, as do 142 tool tests
  and lint. The first current hosted run passes the portable job; Apple reveals a
  clean-PATH Make failure now reproduced and fixed locally (143 tool tests pass).
  The second hosted run confirms the restore fix and passes all tests up to an old
  VAD probe's private-recording/ffmpeg dependency. Its default now uses reproducible
  C signals on both platforms; local detector and native-binding probes pass.
  The third hosted run passes all Apple tests and binding checks, then exposes
  missing XcodeGen preset resources on a clean machine. Bootstrap/doctor now retain
  and verify these resources. The reproduced extension-name collision is fixed;
  all 157 tool tests, lint and the local simulator build/bundle check pass.
  Full Apple hosted acceptance remains pending. A signed private archive and IPA
  now pass signature/profile, model, notice and privacy verification at `21ff054`;
  the earliest profile expires September 26, 2026 at 11:56:33 UTC. The [package record](../releases/history/2026-09-26-s18-signed-package.md)
  retains exact identities and limitations. This is not release or device approval.
  The fourth run now passes every Apple stage before UI. It records 59 UI passes,
  three failures and one skip before the 90-minute job deadline; three of 66 cases
  remain incomplete. The three failures have focused local corrections/tests for
  midnight fixtures, late speech permissions and picker dismissal. Whole-suite
  hosted acceptance remains pending; [the report](../releases/history/2026-09-26-s18-hosted-ui.md)
  preserves the unsuccessful run and its exact counts.
- Targeted Rust/native/probe/UI checks pass as recorded in the ledger. The latest
  broad Rust evidence is 175 tests; native EventKit evidence is 17 tests with one
  simulator-only skip. The archive screenshot matches its pre-change fixture
  exactly below the system status bar. These are not a whole-app visual pass.
- All 22 retained calendar views can now be captured at the reference date and
  compared without changing the baseline. Two serial runs pass three UI tests each;
  exact image matches vary from 15/22 to 13/22 because large-text scroll captures
  and small system-chrome differences remain unstable. The full visual gate stays open.

The broad simulator UI run completed 64 tests: 58 passed, five failed and one
requires a separate reduced-motion simulator setting. All five failures correspond
to CoreAudio RPC aborts while constructing the output engine. Earlier isolated
audio checks passed; the cause remains unexplained. The broad run used the build
at `53c6fe5`, before extraction v10 and the common interpretation provider. Host
clamshell sleep inflated some test durations, so they are not latency measurements.
The complete UI/audio release gate remains open.
The formerly skipped reduced-motion case now controls the actual Settings switch
on a disposable simulator, verifies the system accessibility state, checks the
speaking control and still orb, and restores the previous setting. Its targeted
run passes with zero skips. It remains part of the full suite; this isolated result
does not resolve the audio failures below.
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
share the contract; a separate Debug trial selects the custom GGUF provider.
The separate `LocalAssistant` package now executes the custom GGUF on macOS and
the iOS simulator, with native cancellation/limits and isolation checks passing.
Two complete answers match the desktop; both remain wrong and one is an unsafe
mutation proposal. This verifies runtime compatibility without qualifying the model.
The custom-output adapter now decodes through Rust and typed UniFFI records;
33 shared cases reject malformed fields/dates and unknown references. Cancellation
and fixed app-help topics have explicit common-provider actions. Generated help
text cannot replace the unchanged existing help passages. The actual app-binary
trial passes provider selection, complete-rule routing, prompt generation, native
inference and typed decoding with two invented cases. It reproduces both known
errors, including one unsafe proposal; no calendar operation runs. Model unload
and reload also pass on host and simulator. Normal builds retain their provider
and dependencies; trial bundles cannot use regular release packaging. See the
[app experiment](../../ml/experiments/2026-09-26-s18-assistant-app-provider.md).
The actual app route now covers all 40 existing invented validation cases for
rules-only, Apple and tuned-custom selection. Eight new tool tests, the native
evaluation probe, all 175 tool tests, lint and both simulator builds pass. Rules
answer four cases exactly and leave 36 unmatched. Apple advertises availability,
but its 36 model attempts fail at a missing simulator system component; the four
rule answers still pass. Custom routing returns 17 exact operations, 11 unsafe
proposals and one rejected answer. The retained untuned export now runs through
the identical app binary: four exact operations, two wrong proposals and 24 rejected
answers. All eleven wrong tuned proposals are new relative to that app comparison.
Four model-selection tests, all 179 tool tests, lint and both simulator builds pass.
No operation executes. The same correlated, unreviewed corpus remains development
evidence. Earlier VoiceModel rules, full conversation and actual Apple/physical
qualification remain outside this probe. Run identities are in the ledger and
[comparison report](../../ml/experiments/2026-09-26-s18-app-provider-comparison.md).

All four privacy manifests pass built-bundle verification. Privacy/support drafts
are prepared; publisher/contact information and public distribution review remain open.

## Dataset and custom models

The recognition comparison now detects relocated omissions and changed or repeated
hallucinated appointments at individual-row level, even when total counts improve.
Versioned evidence is required; old retained predictions must be rescored without
replacing their historical reports. All 177 Rust tests, 191 tool tests and lint pass.

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
The corrected baseline and frozen export now also complete the actual simulator
app import, native rereading and persistence route. Each variant performs two
forced imports of one synthetic source, with eight appointments each, twelve native
rereads and zero calendar calls. Warm sessions are verified independently of result
caching. Nine new regressions, all 188 tool tests, lint, the simulator build and
bundle verification pass. This [app compatibility evidence](../../ml/experiments/2026-09-26-s18-ocr-app-provider.md)
does not establish real-photo quality, paired speed or physical acceptance.

Qwen3-0.6B has a resumable LoRA trainer, validation-based selection, fusion and
complete-answer GGUF export checks. The two-process proof matches 171 tensors and
10/10 complete deployment answers, but still fails quality. The expanded run uses
112 invented training cases and 40 validation cases from separate families; it
stops after seven epochs and selects epoch four. Tuned GGUF gets 17/40 operations
exact, with 11 unsafe proposals versus seven for the baseline, and 34/40 complete
answers equal to MLX. Both quality and parity gates fail. See the
[development experiment](../../ml/experiments/2026-09-26-s17-assistant-development.md).
No calendar operation was executed by these evaluations and no provider was promoted.

The paired recorded-answer audit now verifies lineage and every decoded outcome.
It identifies seven newly unsafe proposal cases despite a net increase of four,
and retains all 17 case-level regression flags. The ten development families share
one declared speaker group; the audit therefore reports one connected component
and no confidence interval. Two audits are byte-identical; ten focused regressions,
all 153 tool tests and lint pass. This adds evaluation discipline, not new model
quality or independent real-dialogue evidence.

The [listening preparation](../../ml/evaluation/speech/README.md) now produces 100
host previews: ten invented texts through Victoria and nine available German
system voices. Its anonymous browser form and audio-integrity checks pass. No
human listener has scored the set; no voice is selected or qualified for iPhone
release by these exports.

The host SpeechTranscriber now completes all 100 retained files after a separate
German model setup. Audio/provenance/final-segment checks and five new regressions
pass; all 202 tool tests and lint pass. The [file-ASR experiment](../../ml/experiments/2026-09-26-s18-file-speech-recognition.md)
records real transcript discrepancies without treating number formatting as a
factual error or selecting a voice from ASR behavior. Real speakers/listeners,
natural endpoints and the shipping iOS route remain untested by this file probe.

## Still required

Complete uncertainty/dialogue regressions,
full simulator/visual and persistence gates; remaining cleanup, CI/packaging and
paired device performance; reviewed/grouped OCR data and qualified deployment;
checked German dialogues, provider comparisons and shipping custom-model integration;
local speech/voice comparison, natural-pause and patient comprehension tests;
eSpeak-NG distribution resolution, privacy/support/release qualification and pilot.

Physical hardware, reviewed references, consented unseen data, human listening and
patient tests are external prerequisites. The intended Git remote now resolves to
`https://github.com/Julian-AT/rehab-plan-ocr.git`; hosted verification of the latest
local changes is still pending.
These gates do not block independent implementation. Device updates require fresh
preview/listening approval, a fresh backup, update without uninstalling and a
persistent-data comparison. Historical approvals do not authorize a new update.
