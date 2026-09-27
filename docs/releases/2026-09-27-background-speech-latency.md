# Background input and Victoria response preparation

The physical-phone trace from build 2026092706 shows successful transcription,
roughly 1.1–1.4 seconds of interpretation, 0.04–0.11 seconds of finalization,
and 1.65–3.67 seconds preparing Victoria before playback. It also records a
speech-onset interruption during playback. These content-free observations do
not identify who spoke or establish recognition accuracy.

The input worker now requires sustained VAD and microphone-energy evidence
before passing a new request to recognition. It recovers the onset from the
existing 400 ms pre-roll. After onset, rejected input becomes equal-duration
silence, with 300 ms of tail protection for soft word endings. The pre-roll
retains the original PCM. Background monitoring never feeds an old request.
Interruption requires the existing 200 ms speech window plus a higher energy
floor relative to recent foreground speech. Monitoring cannot teach that
reference from Victoria's own playback. Queued observations predating a new
turn or monitoring interval are ignored.

Voice processing and echo cancellation stay enabled; automatic gain control is
disabled so it does not amplify the room between requests. Quiet speech retains
the existing absolute admission floor. This is energy-based admission, not
speaker identification: another sufficiently loud speaker can still be admitted.
Real quiet voices, television speech and speaking over playback require phone
comparison; synthetic policy checks do not qualify those conditions.

Victoria starts at a complete short sentence rather than waiting for 40
characters, and long sentences can start at a clause boundary. The existing
one-phrase lookahead prepares subsequent audio during playback. Written text,
normalization, actual heard-word tracking, stop/repeat behavior and the 1.2/2.5
second pause policy are retained. No visual controls or layouts change.
Each completed synthesis now records preparation duration and word-mark count,
without text. An explicit private fixed-text phone probe counterbalances whole
buffer versus first phrase synthesis; it reports renderer timing separately
from complete interaction latency and accesses neither microphone nor calendar.

Verification before packaging: speech-input ordering and overflow, synthetic
energy/admission policies, PCM conversion and watchdogs, queued PCM ownership,
noise muting without pre-roll mutation, finalization/cancellation, phrase/date/
abbreviation boundaries, reply normalization/replay, voice-flow confirmation and
heard-history tests, and Victoria PCM checks passed. Device timing and delivery
results will be recorded separately after installation.

Storage preflight exposed a cleanup-reader bug for a legitimate initial build
generation with no predecessor. The reader now accepts only an explicit empty
prior inventory, checks the receipt hashes and rejects unexpected prior files.
All 170 artifact tests passed. Retained products, models and private data remain
outside the compiler-cache removal policy.
