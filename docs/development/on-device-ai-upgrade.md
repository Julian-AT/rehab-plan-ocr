# On-device AI upgrade — 2026-09-27

This is an implementation/qualification record, not a device release approval.
The app identity, persistent data, visual contracts and visible calendar confirmation
remain in force. Private speech, plans, weights and run artifacts stay under `.local`.

## Voice implementation

`VoiceRecording` remains the app boundary. `SpeechRecognitionProvider` adds explicit
on-device/phrase capabilities, locale readiness, timestamped stable/provisional
results and typed completion. Installed German `SpeechAnalyzer`/`SpeechTranscriber`
assets are preferred (de-AT, then a supported equivalent/de-DE). Missing assets or
unsupported hardware use the on-device legacy recognizer. No conversation starts
an asset download or uses server recognition. A failed active turn is not retried
through another provider. `--speech-legacy-trial` selects the control for paired tests.

The tap copies into a bounded/reusable PCM pool. A serial worker owns VAD,
conversion, pre-roll and recognizer input. Overflow invalidates the turn; it never
silently drops audio into an actionable transcript. Up to two seconds of pending
input preserve speech during provider preparation, including the 400 ms barge-in
pre-roll. The existing 1.2/2.5 second pause policy is unchanged.

Readiness has a ten-second deadline. Voiced input with no recognition progress
fails after twelve seconds. Finalization drains conversion/input and waits up to
two seconds; provisional text is never accepted after timeout. A format change
after speech invalidates the utterance rather than joining fragments across a gap.
The existing microphone watchdog retains its bounded restart for absent input.

Diagnostics record one turn ID through capture, interpretation, calendar answers
and synthesis/playback. New steps contain only enums, durations and counts:
provider 1=SpeechAnalyzer/2=legacy, locale 1=AT/2=German equivalent, endpoint
1=pause/2=maximum duration, PCM=`commonFormat.rawValue * 2 + interleaved`, and
voice processing 0=disabled trial/1=enabled. No transcript or arbitrary error text
enters this log. `--microphone-only-trial` disables voice processing for comparison;
it is an experimental graph mode, not a quality claim.

The actual iOS 26.4 SDK interfaces and current Apple Speech documentation were
checked via Context7. The implementation uses iOS 26.0 APIs; DictationTranscriber's
contextual phrase support is not attributed to SpeechTranscriber. The legacy
provider uses the existing bounded calendar vocabulary.

## Verification and remaining qualification

Host checks cover 100 **synthetic** provisional/final cycles, final-range overlap,
progress deadlines, ownership of copied PCM, ordered end-of-input, pre-roll,
cancellation, formats, voice flow, calendar confirmation and bounded diagnostics.
These do not satisfy the 100 physical microphone/answer cycles or natural-dialogue
accuracy target. Simulator builds are supporting evidence only.

Before release: approve a fresh simulator preview and listening samples, back up
the phone, install in place, compare persistent data, then run the guided real-speech
session. Include microphone-only/duplex comparison, airplane mode after setup and
reboot, missing assets, disabled Intelligence, permissions, Bluetooth/interruption,
foreground changes, quiet speech, dialect, long pauses, corrections, sustained
combined workloads and memory pressure. Capture cold/warm endpoint-to-audio p95,
stop latency, peak memory, energy/thermal behavior and task/clarification errors.

No challenger, custom adapter, neural VAD, TTS replacement or OCR acceleration is
qualified by these code changes. Adoption requires paired held-out real-device
measurements and the release gates in the user's implementation plan. Keep the
Apple and current OCR/CPU incumbents when evidence is absent or inconclusive.

## Grounded assistant implementation

Calendar insight queries (`freeTime`, `conflicts`, `totalDuration`, `dailySummary`)
use a fresh visible-selection snapshot with event IDs/fingerprints and read time.
Calculations clip intervals at civil boundaries, merge overlapping busy intervals,
exclude unknown all-day durations, and decline reliable free-time claims on partial
reads. Insight windows are limited to seven days/1,000 input records. Repeated or
nonexistent DST clock bounds require clarification. Total time is explicitly
**scheduled appointment time**; the app does not infer medical therapy categories
from arbitrary titles. `nur morgen nachmittags` retains the previous query kind.

A narrow room-only correction preserves time/title and resolves the last discussed
single appointment afresh. It produces the existing confirmation preview. General
ambiguous or compound room instructions still require clarification.

`planEvidence` is a typed Rust/UniFFI read with bounded literal OCR excerpts,
observation/region IDs, source hash, revision, read time and field states. It reads
retained data without refreshing extraction or running OCR. The assistant keeps a
five-plan catalog, asks which source when ambiguous, and invalidates removed sources.
Comparisons recheck the first revision after the second read and describe **OCR text
differences**, not asserted appointment additions/removals. Complete structured
revision matching remains a later qualification task. Missing, unreadable, cropped
and conflicting field states stay distinct in the evidence response.

Apple guided generation gains insight and plan-evidence requests; read-only calendar
questions use a smaller output schema. Custom Qwen's pinned compact contract and
historical evaluation scores remain unchanged. Prewarming remains an explicit trial
until physical latency/memory measurements justify enabling it.

Checks: calendar-insights, plan-evidence, calendar-answers, voice-flow (including
location-only patch/confirmation), assistant-request, Rust evidence bounds/revision
unit test and simulator build. Source evidence remains in conversation memory only;
it never enters routine diagnostics.

## Corpus and qualification tooling

Speech intake now separates evaluation, ASR training and assistant training purposes.
Both source entry and reviewed receipt must explicitly authorize each use. Frozen
development/holdout assignments verify original byte hashes and connect speakers,
dialogues, document/revision/layout families and intake relationships before any
augmentation. A freeze grants no training permission.

The [physical conversation audit](../../ml/evaluation/conversation/DEVICE-QUALIFICATION.md)
checks paired provenance, failed-turn denominators, raw-model versus app outcomes,
clarification rates, endpoint-inclusive cold/warm latency, separate button/spoken
interruption, energy, memory and scenario coverage. It always requires reviewed
independent evidence before promotion. Unit fixtures are not device measurements.

`ml/evaluation/speech/app-provider-file.sh WAV NEW_PRIVATE_JSON` exercises the
shipping SpeechInput/VoiceActivityDetector, conversion and progressive analyzer
through paced host-file input. Optional `--setup` explicitly installs the required
host progressive-transcription assets before evaluation. Normal mode never downloads.
The report records source hashes, actual input format, provisional/final counts,
voiced frames, result/finalization timings and typed outcome. Transcript stays in
the private report; no microphone or calendar access occurs. These generated-speech
controls remain distinct from natural dialogue or physical-device qualification.

## Verified preview and experiments

- Simulator build, focused audio/recognition/voice/calendar/evidence checks, Rust
  evidence projection, generated-binding parity and repository lint pass.
- 14 intake/group/qualification tests pass. They exercise permission separation,
  related-source leakage, failed-turn timing, unsafe results and paired identities.
- Generated German host files pass through the actual app audio/provider pipeline:
  correction sample 30 updates/1 final, 217 ms end-of-input to completion; long
  sample 90 updates/1 final, 157 ms. Long sample used installed assets without
  downloading. These two controls do not measure conversational accuracy or latency.
- Fresh visual run `ai-upgrade-visual-20260927-001`: 3 UI tests pass; **17/22 exact
  images, comparison fails**. Four differences are confined to the nine-pixel-wide
  scroll indicator. The dark completed-day view differs in 1,559 pixels with maximum
  channel delta four, matching the previously documented system-control pattern.
  Baselines and tolerances remain unchanged. Local `review.html` and `triage.json`
  retain the evidence; full appearance qualification remains open.
- `ai-upgrade-listening-20260927-001/listening.html` contains 90 host-rendered Apple
  samples (nine voices). Human preference/comprehension and phone playback are pending.
- [NVIDIA runtime feasibility](../../ml/experiments/2026-09-27-nemotron-ios-feasibility.md):
  ASR C/C++ and Metal libraries cross-compile for arm64 iOS 26. No inference,
  streaming-quality result, framework integration or phone qualification is implied.

Physical installation still requires explicit approval of these previews and
listening samples under AGENTS.md, followed by a fresh backup and in-place update.
The next critical step is the guided natural-speech session. Parakeet/Ultra,
WhisperKit, neural VAD, compact Qwen comparisons, Pocket TTS, whole-plan Apple OCR
and accelerated OCR remain unqualified; training awaits purpose-approved grouped
real data and measured residual errors. No replacement is silently selected.
