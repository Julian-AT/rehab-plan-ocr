# Complete recognized questions despite quiet background noise

The reported failure occurs before playback: the app keeps listening after the
question. The latest content-free phone trace contains recognized text followed
by no endpoint or finalization before the user stops the turn. It does not
establish the acoustic source or the number of accepted VAD frames.

Three deterministic reproductions identified defects in the app policy:

- Three accepted 20 ms frames could reach recognition, but a recognized short
  reply never ended because the endpoint required at least five frames.
- A single false speech frame every half-second kept resetting the entire pause.
- Repeated recognition callbacks counted as progress even when the words did not
  change, preventing the progress watchdog from expiring.

The endpoint now uses the input gate's existing three-in-five-frame onset
confirmation. Isolated noise cannot acquire speech or reset a completed pause.
A candidate word at the pause boundary has time to establish its onset; a short
rejected burst adds at most its own observation time. Recognized words or numbers
allow a quiet short reply to finish without the extra five-frame requirement.
The existing 1.2-second normal pause and 2.5-second hesitation pause remain.

Only changed words or numbers count as recognition progress. Four seconds with
recognized text but no new content requests explicit end-of-input finalization.
This is a recovery deadline, not a promise to finish answering within four
seconds. Finalization still has its separate two-second bound, and only the
provider's finalized outcome can become a request. Incomplete or failed results
retain the existing error and clarification paths. A new word or corrected
number resets the progress deadline. Silence alone never starts it.

Endpoint requests share one idempotent path. Diagnostic endpoint reason 1 is the
normal pause, 2 the existing maximum turn duration, and 3 unchanged recognized
content. No transcript content is added to routine diagnostics. Stop, background
handling, confirmed calendar writes, Victoria, speech rate, TTS preparation and
all visible controls/layouts remain unchanged.

The host regressions cover short replies, isolated and repeated noise bursts,
noise exactly at the pause boundary, genuine resumed speech, hesitation pauses,
punctuation-only results, duplicate snapshots, corrected words/numbers, typed
final versus provisional outcomes, PCM ownership, ordered finalization, pre-roll
and cancellation. These tests qualify the state-machine behavior; they do not
constitute a natural-speech or speaker-identification benchmark.

Private evidence: `.local/runs/noise-endpoint-20260927-001/`, including the
pre-change reproduction, content-free phone diagnostics and targeted test logs.

Build 2026092709 was archived from clean source `2ec3e79`. The three original
failure reproductions now pass, as do the conversation-rules, speech-input and
recognition-turn probes, strict formatting checks and runtime inventory check.
The private package verifies all four signed components, their phone provisioning
profiles and all 15 pinned Victoria files. No fresh simulator visual run or
real-microphone qualification is claimed for this state-machine change.

The Swift-only archive reused the previous build's verified native artifacts;
native source, generated bindings, runtime binaries and asset identities were
checked before reuse. The build retained the 20 GiB storage reserve with a
separate 2.5 GiB allowance for this bounded Swift build and packaging. Managed
compiler-cache cleanup retained private originals, backups, models, archives and
debug symbols. Build receipts and the signed IPA remain in ignored local storage.

A fresh scoped backup of the app and both App Groups was reverified immediately
before the authorized in-place update. Build 2026092709 is installed. The strict
post-install comparison passed: schema 11, all 17 original table projections,
preferences, durable files and all 30 original source files are unchanged.
The normal launch attempt, without diagnostic arguments, was rejected by iOS
because the phone was locked. Opening the app and replaying the reported room
noise remain pending; synthetic endpoint tests do not establish physical-phone
conversational reliability.
