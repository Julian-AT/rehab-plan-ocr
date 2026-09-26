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
- [x] Shared external-edit, invitation, recurrence and alarm protection.
- [x] Replacement-preview invalidation on changed inputs and calendar snapshots.
- [x] Local erasure despite calendar access loss, with restoration limitations.
- [x] Aggregate retention including PDF originals; no expired-page resurrection.
- [x] Correct Today deep links.
- [x] Unreadable day boundaries and neighboring-column reread contamination.
- [x] Preserve field uncertainty, blanks, missing/cropped/contradictory evidence in extraction v10.
- [x] Invalid spoken dates, corrections, negations and partial-change regressions.
- [x] Explicit conversation states and current-request-preserving recovery implementation.
- [ ] Actual older-iOS inference and complete conversation/UI acceptance.
- [ ] Regression tests, simulator appearance and persistent-data verification.

### 2. Clean platform and responsive interactions

- [x] Mechanical moves to apps/packages/ml/tooling/config/docs/.github.
- [x] Consumer inventory, documentation consolidation and verified private migration.
- [x] Separate make targets for restore/generate/convert/build/test/package.
- [x] Read-only normal-build manifest verification and identity-based caches.
- [x] Independent locked training and app-tooling environments.
- [x] Discoverable isolated tests and portable/native/simulator/policy/package CI definitions.
- [ ] Successful hosted execution of all required jobs on the candidate revision.
- [x] First content independent of reminder reconciliation; coalesced refreshes.
- [x] Typed timestamp projections, indexed archive summaries and pagination.
- [x] Background image/audio processing, bounded buffers and waveform updates.
- [ ] Paired measurements for latency, memory, energy, thermal and session reuse.

### 3. Custom OCR

- [ ] Verified references, reviewer provenance, crop approval and privacy masks.
- [ ] Freeze source-related development groups before augmentation.
- [x] Collection/consent drafts and local intake/label validation tooling.
- [ ] Complete responsible-party details, consent review and unseen-data collection.
- [x] Geometry-aware augmentation and pixel-checked reproducible synthetic plans.
- [x] Matching PP-OCRv6 Small checkpoint, training/export/desktop-runtime smoke test.
- [x] Frozen-backbone versus full fine-tuning, resumable lineage and validation stop.
- [x] ONNX parity comparison before quantization (frozen passes; full adaptation rejected).
- [x] Experimental custom OCR checkpoint, deployment artifact and model card.
- [x] Baseline/custom simulator app import, native rereading, warm sessions and persistence compatibility.
- [ ] Grouped real-photo critical-field/correction evaluation and shipping iOS route.
- [ ] Qualified OCR improvement against the corrected pretrained baseline.

### 4. Assistant, voice and qualification

- [x] Qwen3-0.6B LoRA/fusion/export desktop smoke test (quality gate failed).
- [ ] Checked German structured-intent data and independent dialogue families.
- [x] Common provider contract, typed output and isolated custom-model app integration.
- [x] Evaluated custom assistant checkpoint/model card (quality and GGUF parity rejected).
- [x] Offline complete-rule fallback with unavailable assets/providers.
- [ ] Paired rules/Apple/untuned/tuned comparison through the shipping interface.
- [ ] Qualified custom assistant and complete offline capability-tier acceptance.
- [ ] Real German speech, natural-pause and local-voice listening comparisons.
- [ ] Resolve eSpeak-NG distribution dependency before public packaging.
- [ ] Device performance, permission/offline/Bluetooth/background/stability tests.
- [ ] Privacy/support/license inventory and release candidate.
- [ ] New simulator previews and listening samples approved by the user.
- [ ] Fresh backup, update without uninstalling and persistent-data comparison.
- [ ] Internal acceptance and small TestFlight pilot before public submission.

## External prerequisites

Checked implementation items above identify completed code/tooling evidence, not
whole-milestone acceptance. Open quality, UI, physical and human-review gates are
kept separate; experimental artifacts do not count as promoted models.

Human approval of transcription/crops cannot be manufactured by training tools.
The [German collection guide](../product/research/collection-guide.md) and a consent
draft are prepared. Responsible-party details and the actual consent process still
require completion before collection. New local intake verifies consent scope,
receipt hashes, retention and original copies without granting annotation approval.
Unseen schedules, consented speech, patient comprehension/listening tests and
physical devices are required for the corresponding acceptance gates. The intended
Git remote now resolves to `https://github.com/Julian-AT/rehab-plan-ocr.git`; hosted
verification of the latest local changes remains pending.
Do not promote a model from synthetic-only quality scores or correlated derivatives.

## Verification record

The starting working tree was clean. About 61 GiB was available, superseding the
older low-disk-space report. `make test` was started against the baseline; subsequent
entries must distinguish portable/native tests, simulator builds, physical evidence
and unperformed validation. No device update is authorized by this ledger.

## Recent verification

### Synthetic tables connected to OCR training — 2026-09-26

`make prepare-ocr-synthetic` now converts the pixel-verified generator's tables
into the trainer's immutable crop contract. It validates images, labels, glyphs,
font/generator identities, source groups and exact crops before preparation and
again before training/resume/export. Groups are assigned before selection; identical
training pixels are excluded from validation. Negative/unusable inputs and document
headings cannot become positive recognition targets. No private reference approval
is changed.

The final prepared dataset `.local/datasets/ocr-synthetic-development-002` uses
180 invented schedules plus ten non-plan and ten unusable inputs. Of 10,596
eligible source lines, 2,435 duplicate validation crops are excluded. Selection
retains 512 training crops from 129 groups and 91 validation crops from 42 groups.
Validation has 56 dates, 26 endings, three starts and six therapist lines; it has
no novel title/location/notes pixels. These gaps and the single font/generator
prevent real-photo or complete-field quality claims. Dataset 001 remains an
earlier preparation receipt before import formatting changed the adapter hash.

Six new regressions cover reproducibility, grouping, target/source/pixel tampering,
rehashed false labels and output preservation. All 197 tool tests and repository
lint pass. This closes the generator-to-trainer connection, not the OCR quality gate.

### Row-level recognition regression gate — 2026-09-26

The comparison formerly detected additional missing/invented appointments by total
count, allowing a changed error on the same photo to hide behind an improvement.
Versioned evaluator output now retains unmatched reference IDs and calendar-value
fingerprints with multiplicity for invented rows. Comparison reports the affected
source and repeat, and blocks newly missing or changed/additional invented facts
even at equal totals. Generated detection IDs and geometry do not create spurious
new identities. Older count-only reports remain readable, but must be rescored
from retained predictions before entering this gate.

Regression tests first reproduce the missing gate. All 177 Rust workspace tests,
191 tool tests and repository lint then pass, including twelve comparison cases
and Rust matching/duplicate/legacy-serialization coverage. No reference approval,
inference result, patient-data change or model promotion follows from this fix.

### Signed private archive and documentation gate — 2026-09-26

The signed archive and IPA at `21ff054` pass all four component/signature/profile
checks, model/dictionary, privacy and notice verification. The 79 archive files
and 340,933,354-byte IPA are preserved with source/copy hash equality. The earliest
profile expires at 11:56:33 UTC on September 26, 2026; signing must be rechecked before
any approved installation. See the [package record](../releases/history/2026-09-26-s18-signed-package.md).
No physical update or release qualification follows from this technical check.

Hosted attempt 35294496763 stops in both test jobs because the newly added hosted
report omitted its required “Historical record” marker. The report is corrected;
the failed logs remain in `.local/runs/hosted-ci-20260926-s18-005`. No native/UI test
ran in that attempt. Full candidate CI remains required.

### Hosted UI findings and focused regressions — 2026-09-26

The fourth hosted attempt passes portable checks and all Apple stages before UI,
then reaches the job's 90-minute deadline. Logs retain 59 passed, three failed and
one skipped UI case out of 66 declared; one is interrupted and two have not started.
No artifact survives the job timeout. Three formerly affected audio cases and the
new rejected-creation regression pass on the hosted environment. Full UI acceptance
remains open.

The midnight fixture now stays on its civil day through whole-second timestamps;
63 date/timezone/DST cases and the fixed 00:10 UI regression pass. Automatic completion
is observed after a not-yet-ended appointment. Speech permission handling remains
active for late system prompts; the fresh local prompt flow passes. Photo cancellation
waits for actionable controls and restored navigation; both appearances pass locally.
The simulator build and repository lint pass. See the [hosted report](../releases/history/2026-09-26-s18-hosted-ui.md)
for exact results, retained failures and evidence identities. Candidate hosted
verification is still required.

### Current device package and model-card evidence — 2026-09-26

The current normal Release iPhone build passes without installation. Shared
verification checks all four components, assets/dictionary, dependency notices and
privacy manifests. Simulator-only assistant/OCR probe switches are absent from
the main executable. Evidence: `.local/runs/device-bundle-20260926-s18-004`, verifier
SHA-256 `5600d8081b50bda9c9ea8097a7d0f5a9a0e57460996e51acbebfa996ad83b500`;
main binary `871deff9d9cd234abe1a43b69d53364826112570368333c81bd90d44500f350c`.
This is unsigned package verification, not a signed archive or device acceptance.

The OCR, tuned-assistant and untuned-comparator model cards now link their later
native-app reports and hashes without replacing earlier desktop results. Report
and artifact identities were rechecked; all qualification flags remain false.

### Bounded hosted UI execution and retained console evidence — 2026-09-26

The fourth hosted run has passed restore, all headless tests, binding checks,
both builds/package checks and EventKit. Its full UI step has exceeded 50 minutes;
the original 90-minute job gives no separate deadline for collecting failures.
The next candidate uses a 120-minute job, a 75-minute UI step and a ten-minute
evidence-upload limit. Each XCTest case has a 300-second ceiling. These are hang
limits, not product latency objectives. Console output is retained with the result
bundle; Bash pipeline failure propagation keeps failed tests red. Upload is also
attempted after cancellation, subject to the runner's remaining lifetime.

Current GitHub syntax and installed Xcode help were checked. YAML structure,
pinned action identities and repository lint pass. Hosted execution of these new
limits remains pending; the ongoing run continues under its original configuration.

### Real reduced-motion setting without a skipped test — 2026-09-26

The existing accessibility UI case now opens Settings on the disposable simulator,
enables Reduce Motion and waits for both the switch and `UIAccessibility` to confirm
it. The speaking control remains usable and the orb pixels stay unchanged over a
one-second observation. Teardown restores the original switch value, including
after test failure. Physical test destinations cannot run the setting change.

The first run exposed an ineffective center-of-row tap. Targeting the switch and
waiting for its value fixes the test setup. Run 002 passes one test with zero
failures/skips in 30.106 seconds, including restoration from on to off. Evidence:
`.local/runs/reduced-motion-20260926-s18-002.xcresult`. The discoverable command is
`make test-reduced-motion`; the case also remains in the full UI suite. Swift/shell
format checks pass. This closes the formerly skipped isolated setting check, not
the separate real-audio, whole-suite or physical usability gates.

A subsequent run exposed that the voice-state screenshot includes the system
clock: its failing one-second comparison crossed a minute boundary. Both stationary
and moving-orb comparisons now exclude the same top 160 system pixels as the visual
baseline, retaining strict equality for all remaining app pixels. Full before/after
images remain attached. Instrumented runs 005 and three iterations in 006 pass;
the final corrected comparison passes run 007 with the 300-second XCTest ceiling.
Run 004 remains a recorded failure. No production appearance or animation changed.

### Custom OCR in the actual app import pipeline — 2026-09-26

The normal Debug simulator app now has an isolated recognition probe that forbids
calendar access and exercises ordinary import, native rereading and stored-review
APIs. Baseline and parity-passing frozen weights each complete two forced imports
of one public synthetic source, yielding eight appointments each and twelve native
rereading calls per variant. Warm model sessions are reused without reusing image
results. Exact source/model/dictionary/manifest/binary/runtime identities survive
in the retained report. Full adaptation remains excluded after failed export parity.

Nine new isolated regressions, all 188 tool tests, lint, the simulator build and
bundle verification pass. Final evidence is `.local/runs/ocr-app-provider-20260926-s18-004`,
report SHA-256 `c1f29eefb48e636b8a58c05916c5d5532d3fd829c7f09e968599109e1dfb3f4f`.
The [experiment record](../../ml/experiments/2026-09-26-s18-ocr-app-provider.md) documents
earlier failed validation and simulator storage retirement. No physical update,
real-photo quality result, paired speed claim or model promotion follows from this
single-source compatibility check. Those acceptance gates remain open.

### Untuned and tuned models in the same app binary — 2026-09-26

The trial builder can now select the retained, hash-verified untuned development
GGUF as well as the tuned checkpoint. Four model-selection regressions, all 179
tool tests, lint and both simulator builds pass. The untuned route interprets
16/40 cases (including four rule matches), with four exact operations, two wrong
mutation proposals and 24 strict rejections. The tuned route remains 17 exact,
eleven wrong proposals and one rejection. Both use the identical app binary,
prompt/native runtime, dataset and evaluator on the same simulator.

All eleven wrong tuned proposals are new relative to this untuned app run; its
two earlier wrong proposals improve. The paired auditor flags 23 cases overall
and supplies no interval because the data has one connected speaker component.
No provider is promoted. These are interpretation-segment results: earlier
VoiceModel rules, state, speech and calendar execution are outside the probe.
Apple model attempts still fail in the simulator. The complete physical workflow
and latency comparison remain open. See the [comparison record](../../ml/experiments/2026-09-26-s18-app-provider-comparison.md).

### Forty development cases through the app interpretation route — 2026-09-26

The isolated simulator trial now accepts the complete invented validation partition
for rules-only, Apple or custom-provider evaluation. It records actual routing,
provider identity, no-match/unavailable/error states and every operation. Expected
answers stay outside the app. Extra app constraints survive serialization and fail
compact-schema/exact comparison; malformed proposed mutations remain visible.
Context that cannot be preserved is rejected. Source, fixture, dataset and binary
identities are retained, and source changes during evaluation invalidate the run.

Eight tool regressions and a native probe pass, including all ten valid shared
compact-schema round trips, unique-reference resolution, extra-constraint retention
and invalid fixtures. All 175 tool tests, repository lint and both the normal and
experimental simulator builds pass. Forty cases run in each of three serial trials:
rules answer four correctly and leave 36 unmatched; Apple reports available but
all 36 model attempts fail inside the simulator's missing SensitiveContentAnalysisML
component (the four rule answers still pass); custom routing yields 17/40 exact
operations and 11 unsafe proposals, with one rejected interpretation. No calendar
operation or audio session is opened and no model is promoted.

Runs are `.local/runs/assistant-app-40-{rules,apple,custom}-20260926-s18-001`.
Report SHA-256, respectively:
`7fd415658807a6369e0dcc77b43659e17bdf653ecdfa3815910485ad25b6a097`,
`4768325400772294cdeaa98451aff1099a2bd39b56e29c452c3b9ccef09c284c`,
`af0622a3af739ca28e2917efa689e576b2cad7ae4636b7f0cd4fc323f25fb8d3`.
These remain the same ten invented families connected by one speaker-group label.
The broader compatibility check does not supply human review, an independent
holdout, an untuned app comparison or paired physical end-to-end performance.

### Fresh read-only physical baseline — 2026-09-26

The known iPhone reconnects with DDI services available. Fresh device/app queries
confirm iPhone 17, iOS 26.6 (23G71), Laßnitzhöhe 0.3.0/build 2026092624. The main app
is not running at either process check. Only its 4,648,960-byte database and
848,344-byte technical log are copied; remote metadata is unchanged before/after
and no WAL/SHM/journal sidecar is present. The copied database passes integrity and
foreign-key checks: schema 8, 15 tables, 29 scans and 27 stored recognition runs.
Stored model-manifest identities and table/operation-status summaries are retained
privately. The 4,901 existing diagnostic events include historical stage durations;
they are uncontrolled observations, not paired cold/warm or end-to-end measurements.

Evidence is in `.local/runs/device-readonly-20260926-s18-001`, summary SHA-256
`e043f7f6146a86c1734774e940457d334e2ae9a2133e6ec697181de01edc8bae`.
No app launch/termination, calendar operation, installation or update was performed.
This partial baseline is not a fresh complete backup for installation. Actual voice
capabilities, installed model bytes, device latency/energy/thermal measurements,
current preview/listening approval and post-approval backup/update remain pending.

### Reusable retained-data comparison — 2026-09-26

The former private delivery check now has a maintained local-copy implementation:
`make snapshot-persistence` / `make compare-persistence`. It verifies schemas 8–11,
all 15 original persistent tables, typed row associations, preferences, original
files and App Group journals. SQLite/WAL/SHM reads use disposable copies; every
original backup file is reverified before comparison. Additive schema projections
are reported separately and cannot silently approve migrations. Changed diagnostics
remain review items. Outputs stay private, immutable and outside source containers.

Ten synthetic regressions cover unchanged data, modified backups, ownership,
pending operations, source/preference loss, schema additions, swapped row values,
WAL-only records, content serialization, incomplete copies and private output.
All 167 tool tests and repository lint pass. The retained September 26, 2026 copies also
pass the immediate post-install check: 15 tables, existing preferences, 90 durable
files and 18 originals are unchanged. The historical post-launch comparison flags
the changed diagnostics file as expected; 88 other files are byte-identical and
one JSON file is semantically identical. This rechecks old evidence and performs
no new device capture, update or acceptance.

Local evidence is in `.local/runs/persistence-audit-20260926-s18-001`. Snapshot SHA-256:
`9bd76e1cc8a90547e57f6b58d4e8806094796ae7e7f56528e59b9e75a9ec1ae0`;
post-install report: `cb7aa96f51a532df3b5dd4b349666d697d68220e3ffd53571ccfe4b30be8f421`;
post-launch review report: `6749aea5e6ac0e441567e3d4d463a1a650d3d8e0ad052cf0a63538ac22ddc37d`.

### Paired assistant errors and dependency-aware uncertainty — 2026-09-26

`make audit-assistant-pairs` verifies the existing model-card/run/dataset/decoder
identities and redecodes every recorded answer. Complete validation coverage,
boolean outcomes, aggregate counts and full-answer parity are rechecked. Paired
resampling retains connected family/scenario/paraphrase/speaker groups; it refuses
an interval when fewer than two components exist. Case-level regressions cannot
be hidden by an improved aggregate. No inference or calendar operation is run.

The actual development record still has 4/40 versus 17/40 exact operations and
7/40 versus 11/40 unsafe proposals. Seven cases have newly unsafe proposals while
three previous cases improve. There are 17 cases requiring regression review,
including 16 changed incorrect operations and one new schema rejection; categories
overlap. Ten families share one declared speaker group, so only one dependency
component exists and no confidence interval is justified by this audit. The six
GGUF parity failures remain. No candidate is promoted.

Ten isolated regressions, all 153 tool tests and repository lint pass. Two complete
audits produce byte-identical reports. The final report is retained at
`.local/runs/assistant-paired-20260926-s18-002/report.json`, SHA-256
`7a23eb72a78b318e5577902d8b36ee5e88720b8d9da4a3eff868dc40a8658a45`.
The [evaluation guide](../../ml/evaluation/conversation/README.md) records the
method, estimand and limits; this remains selected, invented development evidence.

### Hosted CI access and exact-revision monitoring — 2026-09-26

The configured GitHub repository is reachable. The latest existing run,
`35263622297` at `683ce5f`, failed formatting on both hosts before tests began;
the affected files are already corrected and locally lint-clean in the current
implementation. The pinned checkout action resolves to its recorded commit.

`tooling/dev/ci_monitor.cjs` provides observable repository/run/commit identities,
job results and failed logs. Manual dispatch checks the remote branch against a
required full commit first. Six isolated tests cover read-only commands, argument
isolation, stale-branch rejection and pinned action verification. The helper is
optional developer tooling (Node.js 22+ and authenticated GitHub CLI), available
through `make ci-status` and `make test-ci-monitor`; no app dependency is added.
The first new [hosted run](archive:github/run-35284272361)
at `75ff16f` passes the complete portable job. Apple passes bootstrap/lint but
fails restoring assets: Apple's Make cannot locate a bare executable using its
newly exported PATH. A clean-PATH regression reproduces the failure locally.
Direct uv/cargo recipes now use `env` to resolve the inherited recipe path; the
regression passes, along with all 143 tool tests, seven monitor tests and lint.
CI builds/verifies both unsigned bundles before native/UI tests, avoiding a
secondary missing-bundle error after failed setup. Completed-job logs can be read
while the other job runs, after verifying their run identity. Full Apple hosted
qualification remains pending. Raw evidence is retained in
`.local/runs/hosted-ci-20260926-s18-001`.

The Apple workflow now retains explicit synthetic XCTest result paths and valid
JSON bundle reports for 14 days, named by commit and run attempt. The upload action
is pinned to its verified v7.0.1 commit. No app binaries, model assets or private
working storage are selected. Local checks parse the workflow and actual emitted
bundle JSON; successful hosted artifact capture remains to be observed.

The monitor also lists retained artifacts and downloads only the expected native
evidence for a completed, explicitly identified commit/run/attempt. Expired,
mismatched or ambiguous artifacts and existing destinations fail. A local receipt
retains the remote metadata and hashes every extracted file; interrupted downloads
stay marked incomplete. The service's archive digest is recorded but not claimed
as independently verified. Eleven isolated monitor tests pass. Actual hosted
evidence retrieval remains pending until a run reaches the artifact-upload step.

The second [hosted run](archive:github/run-35284918453)
at `4b765d0` again passes Linux and confirms the Apple restore fix. Apple then
passes Rust, all tool tests, ICS and the first 21 Swift probes, stopping at a legacy
VAD probe that assumes ffmpeg and a private local preview recording. A clean-PATH
local reproduction fails identically. The default VAD test now synthesizes harmonic
bursts in C, checks initial/final silence and invalid frames, and is included on
both platforms. Its 164/350 positive frames and the optional retained local audio's
504/547 frames pass; these are detector regressions, not speech-quality evidence.
The remaining native-binding integration and repository lint pass locally. The
second run's logs and identities are retained in `.local/runs/hosted-ci-20260926-s18-002`.

The third [hosted run](archive:github/run-35285868259)
at `a17447a` passes Linux, the complete Apple test stage and generated-binding
verification. The clean device build exposes another setup defect: extracting only
the XcodeGen executable omits its sibling `share/xcodegen/SettingPresets` tree.
The tool still returns a correct version and successful generation, but default
product names are absent and all three extensions collide at `.appex`.

A standalone copy of the pinned release reproduces missing defaults locally.
Installing its verified preset tree restores distinct `First.appex`/`Second.appex`
products in actual Xcode build settings. Bootstrap now retains all release presets
and the tool license, records their hashes, and repairs incomplete/modified local
installations. Doctor checks resources as well as the version. Four regressions,
all 157 tool tests, lint, the normal simulator build and its bundle verification
pass using the newly installed pinned binary. The build's disk reserve was restored
by removing only the completed project's reproducible SDK module cache, with a
local receipt; products, logs and private data remain intact. Third-run hosted
evidence is retained in `.local/runs/hosted-ci-20260926-s18-003`. Full hosted Apple
build/UI/package acceptance still needs the next run.

### One civil clock through interpretation and confirmation — 2026-09-26

Each voice/text turn now captures its civil calendar and instant before awaiting
context generation. Rules, Apple structured decoding and custom-model prompts use
that captured clock. Context today/visible-reference dates agree with the request;
the custom prompt rejects a mismatched day or timezone. Pending mutations retain
their timezone through date/time collection, event lookup, date pickers and preview
construction, including the typed custom-model adapter.

Five targeted probes pass: common interpretation, custom provider, calendar
timezone, conversation state and German voice rules. New cases cover a New York
22:00 appointment while the host runs in Vienna, matching Apple/custom/rule date
conversion and rejection of stale prompt dates/zones. Repository lint, the regular
simulator build and built-bundle verification pass. The normal build initially
stopped at its disk reserve; verified duplicate download ranges and completed
compiler intermediates were removed with local receipts before rerunning it.
Authoritative weights, originals, backups, finished app products and result logs
remain intact. Physical timezone changes and full voice UI qualification remain
separate acceptance work.

### Shared unsigned and signed bundle verification — 2026-09-26

`make verify-bundle` checks the built app and all three extensions against the
stable identifiers, branding, executable names, common versions, iPhone platform
and iOS 26.0 floor. It verifies the exact OCR/speech manifests and contents,
including the formerly unchecked packaged OCR dictionary, all four privacy
declarations and all 15 license texts. Missing/extra components, altered contents,
symlinks and experimental assistant trials fail. Signed packaging calls the same
contract and retains its additional signature/profile/App Group checks; explicit
checks remain active under Python optimization.

Eight synthetic bundle regressions, all 142 tool tests and repository lint pass.
The existing normal simulator bundle and a fresh unsigned Release device build
both pass the real-content check. Reports are retained locally in
`.local/runs/bundle-verification-20260926-s18-001`: simulator SHA-256
`e12028df474a1fcea948b488f2b4ad94d47c7be4ceb9ad8d210cbe24a498d63d`, device
`1d6c02a789a3e8a9f06d0a2cbfa425ee1f9997ec7a29fd1d2117de3bd6ff43c2`.
No signed archive was created and no physical device was updated. CI now includes
both content checks; hosted execution remains pending. The configured `origin`
was confirmed read-only as `Julian-AT/rehab-plan-ocr`.

### Fixed calendar screenshot capture — 2026-09-26

`make test-visual-baseline` now builds/captures the 22 retained calendar views at
their original civil date, with synthetic data on disposable simulators. Original
references stay byte-identical. Missing, duplicate, failed or dimension-mismatched
captures fail; only the declared system-status region is excluded. The output
includes test/source identities, per-image differences and an offline comparison.

Two serial runs pass all three UI tests, but exact image matches vary from 15/22
to 13/22 with identical app code. Large-text scroll positions vary, and dark system
chrome differs by at most four channel levels in the inspected completion view.
No tolerance or image registration turns these into passes. A documentation-only
edit also correctly invalidated the initially overbroad second source snapshot;
future capture identities exclude Markdown while retaining all runtime/test inputs.
The [visual experiment](../../ml/experiments/2026-09-26-s18-visual-baseline.md) records
the remaining capture-stability gate. All 134 tool tests and repository lint pass;
the full visual and voice/device gates remain open.

### Captured conversation timezone — 2026-09-26

A new failing regression reproduced reuse of one calendar snapshot for two civil
days with the same start but different ends during a DST transition. Conversation
queries now carry the requested timezone through day boundaries, live-reference
checks, follow-up anchors, pagination and spoken date/time formatting. Cache keys
contain typed start/end instants and the timezone; the discussed civil date retains
its original zone. All complete rules retain an explicitly supplied calendar zone.

The regression passes for 23- and 25-hour days, Vienna/Lagos cache separation and
New York evening appointments while the host runs in Vienna. Reference lookup,
spoken start time and pagination preserve the chosen day. Existing calendar-answer,
agenda-projection and conversation-reply probes and the simulator build also pass.
This is deterministic timezone coverage, not a real-device travel test.

### Custom provider in the experimental app — 2026-09-26

The separate Debug simulator build now selects the verified custom GGUF through
the common provider/router and strict typed decoder. Its prompt matches the
recorded training template. Whole-turn context trimming keeps the current request;
missing assets preserve complete-rule questions. Session discard queues model
unloading; real host/simulator reload checks pass. The normal generated project is
restored after the trial build, and packaging rejects its experimental marker.

The [app experiment](../../ml/experiments/2026-09-26-s18-assistant-app-provider.md) completes
two existing invented development cases: 0/2 exact operations and one unsafe
proposal, matching the earlier native results. No calendar database or audio
session is opened; this is not complete voice/device qualification. The candidate
remains unqualified. Normal and experimental simulator builds, 131 tool tests,
common-provider/typed-boundary probes and actual regular-bundle privacy/notices
checks pass. The actual trial bundle is rejected by regular packaging.

### Experimental native assistant execution

`LocalAssistant` builds a verified pinned llama.cpp CPU boundary for host, simulator
and device architectures, with no training-code app dependency. Actual host and
simulator inference, cancellation, deadlines, context/output limits and state
isolation pass; two complete outputs match the previous desktop GGUF. Neither
matches the expected operation and one proposes an unwanted mutation. No operation
is executed and the candidate remains unqualified for production.
The [native experiment](../../ml/experiments/2026-09-26-s17-assistant-native.md) records
identities, the fixed sub-millisecond timeout defect and remaining integration gates.

### Typed custom-assistant requests

The compact model schema now crosses a strict Rust decoder and typed UniFFI enum
into `ConversationInterpretation`. Thirty-three shared Rust/Python/Swift cases
cover canonical dates/times, missing versus explicit null fields, duplicate and
unknown keys, visible references and minimal changes. An initial regression found
that Serde's unit cancellation variant accepted extra fields; the empty struct
variant now rejects them. No parser operation accesses or changes calendars.

The common provider distinguishes cancellation and fixed app help. Help text is
the unchanged existing German screen content; invalid-date clarification retains
its reason. Capability validation and canceled/late-result isolation pass. The
full workspace passes 175 Rust tests and warning-free Clippy; 127 tool tests pass.
The actual typed Swift boundary, provider/state probes and native persistence/FFI
integration pass, and the simulator app builds. Calendar write confirmation and
snapshot revalidation remain downstream. A semantically wrong known reference can
still satisfy the schema; the model remains unqualified and app trial selection
is a separate integration step.

### Bundled runtime dependencies

The selected iOS normal/build closure now has a reproducible inventory: 136 Rust
packages, with 109 normal target dependencies and 27 build-only packages. Two are
workspace packages; 134 external packages have pinned source checksums and retained
notice references. Metadata-only optional dependencies are excluded. Shared license
texts are bundled once, including SQLite's separate amalgamation declaration.
Model/native source locks and vendored VAD inputs are also recorded. These counts
describe dependency edges and do not establish installed binary size.

Normal builds and lint verify committed input/notice hashes without regeneration.
Explicit offline regeneration reproduces the inventory exactly. Packaging compares
the actual bundled inventory and complete notice set against reviewed source. Eight
synthetic regressions cover selection, deduplication, stale/missing/altered notices,
path confinement, read-only verification and old bundles. All tool tests and the
simulator build pass. The built app contains the matching inventory
`8d25ce5ff9ef8439e079fbb2f97e06d6a8701d71290b80000cdd3352b6cf5758`,
all 15 verified notice files and four verified privacy manifests. No signed archive
or physical installation was produced. The eSpeak-NG redistribution decision and
publisher-approved first-party rights/license notice remain open.

Git's automatic CRLF normalization was detected during the first inventory commit.
Bundled notices now use `-text`, and that attribute file is a verified input. A
fresh export of the staged Git tree, with no registry/model assets, passes the
read-only inventory check. Its corrected inventory identity is
`6e2c395af8baff1c06fa202bf42481c3a5821bb3ed03807561cb8fb7a6a8d6c3`.

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

UniFFI Cargo-metadata discovery is now enabled only by the explicit `bindgen`
feature. The actual iOS normal/build dependency closure falls from 139 to 136
packages; the target normal closure excluding procedural macros falls from 113
to 109. These counts use `cargo tree`, not the broader metadata resolver graph.
Committed Swift/header/module-map bindings remain byte-identical. The native
Swift/Rust integration probe, all 173 Rust tests and simulator app build pass.
No device latency or installed-size improvement is inferred from dependency counts.

The German listening pipeline exports ten invented cases through the shared
Victoria SpeechEngine and every available German Mac system voice. Ten voices
produce 100 complete non-silent PCM16 samples with identical prepared text, hashes
and source/toolchain identity. An anonymous local form preserves per-voice answers,
records reference disclosure and exports draft JSON. Browser interaction and four
integrity regressions pass. No human listening score, voice promotion, offline-iOS
qualification or first-audible latency claim follows from these host exports.
See the [listening workflow](../../ml/evaluation/speech/README.md).

German date rules now accept month names and day ordinals, validate leap dates and
year lengths, and retain the latest explicit self-correction across time formats.
The reproduced “09:30, ich meine um zehn” error now yields 10:00. Negated field
values stay unset; “Habe ich keine Termine morgen?” retains tomorrow. Month/day
words are excluded from event-title matching. Short rejections such as “Nein danke”
discard a pending change through the existing conversation state. Voice, state,
endpoint and live-calendar answer probes pass; endpoint thresholds remain unchanged.
The added UI rejection regression is not yet qualified because simulator audio
aborts before the interaction can be verified. Full dialogue/device gates remain open.

Augmentation v3 expands the 24 recipes to 40, composes transformations and shares
privacy/crop/obstruction visibility with the labels. Cropped blank fields no longer
retain a complete blank target; unavailable text is removed. Nine geometry and
nine reference tests pass. All 80 variants of two invented sources repeat exactly
in pixels, labels, matrices and encoded JPEG bytes. Real approval/grouping gates
remain unchanged. See the [experiment](../../ml/experiments/2026-09-26-s17-augmentation-geometry.md).

Synthetic table generation v2 draws each shared date/column heading once, links
rows to day evidence and lays out actual wrapped glyphs without clipping. Lossless
exports validate complete text pixels and field values. Two exports of 200 inputs
(180 schedules, 10 non-plans, 10 unusable images; 1,950 invented appointments) match
in all 400 image/label files. Five new and eight existing reference tests pass.
This adds no independent real examples and does not approve real references or
qualify a model. See the [experiment](../../ml/experiments/2026-09-26-s17-synthetic-layout.md).

The shared import policy now also protects all-day semantics, location geometry
and availability that compact approvals cannot represent. Plain room text remains
eligible. Alarm ownership rejects proximity metadata in addition to absolute and
location alarms. A new actual EventKit regression first reproduced an incorrectly
accepted external-metadata update; update and removal now conflict without losing
the original event. The native suite passes 17 tests with one expected simulator
file-protection skip; 57 agenda/alarm policy checks and the current app build pass.
The [route matrix](../architecture/calendar-protection.md) records final checks,
metadata preservation and the remaining physical-account acceptance limits.

The app and its three extensions now carry audited privacy manifests. Packaging
rejects missing, altered, duplicate or unexpected declarations; a discoverable
`make verify-privacy` checks an existing bundle. Four packaging regressions pass.
The current simulator app builds and all four manifests match source. German
privacy/support drafts cover actual local data flows, retention, exports and
calendar-account synchronization. Publisher/contact completion and public review
remain open; this does not establish App Store acceptance.

The broad UI run on the `53c6fe5` build completed 64 cases: 58 passed, five failed
and one skipped for a missing reduced-motion setting. All five failures have
matching CoreAudio RPC aborts during output-engine initialization, including the
two typed-query cases. Earlier isolated passes do not close this gate. Host
clamshell sleep accounts for two roughly 900-second teardown delays; the test
durations cannot establish application latency. Extraction v10 and the common
provider contract have since been compiled together in the current simulator app;
their current-build UI checks remain pending.

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

A new parser regression reproduced loss of contradictory column evidence when the
recognized string was empty. Empty readings now change only a legible assessment
to an unreviewed blank; existing conflict/crop states and all reasons survive.
Extraction version 10 invalidates stale caches, and safe mapping refresh covers
versions 5–9 while retaining manual values, identities and capture-edge warnings.
The regression failed before the fix; the full Rust workspace now passes 173 tests
and Clippy passes with warnings denied. No reference approval or model promotion
was inferred from this business-logic correction.

Calendar rules and Apple Intelligence now implement one typed interpretation
contract with identity, capabilities, local availability, structured validation,
monotonic deadline and cancellation. Complete rules still work without model
assets. The Apple adapter distinguishes hardware/setup/readiness/German-language
limitations and keeps iOS 26.0 context recovery. A 30-second post-finalization
deadline cannot publish late native results into a later answer; it does not alter
speech endpoint pauses. The provider probe covers unavailable assets, complete
matching, one selected generator, invalid shapes/capabilities and uncooperative
cancellation/deadline completion. The simulator build in isolated DerivedData
passes. Full/targeted UI qualification and custom GGUF integration remain separate
gates; experimental Qwen checkpoints are not activated. See the [contract](../architecture/ai-providers.md).
