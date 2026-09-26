> Historical record: technical findings retained from the archived development sequence. Project dates, build labels and source references have been normalized. This record is not a new test, delivery approval or signing attestation; unaltered evidence and original validity dates are held in the external private archive.

# Development status — 2026-09-26

All four milestones in the [implementation ledger](implementation-plan.md) remain
open. Completed implementation and experimental artifacts are recorded separately
from human, physical-device and release acceptance. Important verified slices are
committed individually. No physical device was updated during this work.

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
| Portable/native logic | 178 macOS Rust tests, 174 Linux Rust tests, 206 tool tests and twelve CI-monitor tests pass. Four HEIF cases require macOS. Portable lint passes on the latest tooling candidate; headless Swift probes are recorded in the ledger. |
| EventKit | 17 native tests, with one simulator-only file-protection skip. |
| Hosted CI | Run 35295159442 tests `0597aab`; portable and pre-UI Apple stages pass, full UI is running. Run 35297619578 tests the later evaluation/tooling candidate `a303bc2` on a separate branch. No complete candidate pass is claimed yet. |
| Portable CI scope | Run 35299521071 passes at `9c8d31c`, with its Apple job explicitly skipped. Full remains the default for manual dispatch and the required push/PR scope. This tool-development run does not qualify native behavior. |
| Prior hosted UI | 59 passes, three failures and one skip before the old job timeout; three cases incomplete. Focused midnight/permission/picker corrections pass locally. See the [retained report](../releases/history/2026-09-26-s18-hosted-ui.md). |
| Local audio/UI | Full local runs reproduce CoreAudio aborts, also seen in an independent minimal app. Three affected cases pass on the hosted environment. Combining isolated passes does not establish whole-suite acceptance. |
| Reduced motion | The actual simulator Settings switch, usable speaking control, stationary app pixels and setting restoration pass without a skip. System-clock pixels are excluded from animation comparisons. |
| Appearance | All 22 original PNGs are unchanged. Exact repeated comparisons match 15/22 then 13/22; large-text scroll positions and small system-rendering differences remain unresolved. No baseline replacement or tolerance hides these differences. |
| Persistence | Ten synthetic backup-comparison tests cover schemas 8–11, original columns, sources, preferences and App Group journals. A fresh complete physical backup/update comparison remains pending. |
| Packaging | Signed private archive/IPA at `21ff054` passes four-component signature/profile, model, notice and privacy checks. Earliest profile expiry is September 26, 2026 at 11:56:33 UTC. See the [package record](../releases/history/2026-09-26-s18-signed-package.md); recheck signing before any approved update. |

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

Pixel-verified synthetic tables now feed the actual trainer. Whole source groups
are assigned before selecting crops; identical training pixels are excluded from
validation. The larger experiment has 512 training crops from 129 groups and 91
validation crops from 42 groups. Validation contains dates/times/therapist lines,
with no novel title/location/notes pixels. Frozen and full training are running;
these experiments cannot qualify real-photo recognition. Critical-field metric
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

Ten local voices have 100 anonymous host listening previews and zero human scores.
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
- Publisher/contact details, eSpeak-NG/public-distribution and branding-rights decisions,
  complete privacy/support materials, internal acceptance and a small TestFlight pilot.
- Explicit current preview/listening approval, then a fresh complete backup,
  in-place installation and persistent-data comparison. Historical approvals cover
  their historical updates only.

The intended remote is `https://github.com/Julian-AT/rehab-plan-ocr.git`. CI branches
are separate from remote main. Detailed completed slices, failures and private
report identities remain in the implementation ledger and linked experiment records.
