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
Device build and delivery evidence will be recorded after the verified update.
