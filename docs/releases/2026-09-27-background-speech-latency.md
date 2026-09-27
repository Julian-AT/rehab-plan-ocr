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

## Phone delivery and measured preparation

Build **2026092707** (0.3.0) was archived from clean source `fbda80c`, signed,
verified with all three extensions and 15 pinned speech files, and installed
in place on the connected phone. The full native archive and `make lint` passed.
No uninstall, calendar write, appearance change, or voice preference change was
performed. The app was relaunched normally after the private timing probe.

The fixed-text Victoria probe completed 13 renderings: one cold short sentence,
then six paired warm comparisons across three phrases, counterbalancing order.
Whole-buffer preparation was **1.22–3.13 seconds**; the corresponding first
phrase required **0.45–1.87 seconds**. The median paired reduction was **49.7%**.
The cold short sentence still required **2.72 seconds**. These are renderer
preparation measurements on this phone at rate 1.15, not microphone-to-answer
latency, natural-dialogue accuracy, a sustained thermal test, or proof that
background speakers are rejected. The two longer first phrases contain actual
appointment/app information; the short fixture is a greeting. Subsequent phrases
are still rendered and played; no answer text is discarded.

The fresh pre-install backup and strict post-install comparison matched all
persistent data. After relaunch, schema 11, all 17 original table projections,
preferences, original source files and all other existing durable contents were
unchanged. The separately reviewed differences were 21 routine diagnostic records
replacing the oldest 21 at the 5,000-record limit, plus one completed fixed-text
speech report. All 4,979 retained diagnostic records were unchanged.

Private evidence: `.local/runs/background-speech-20260927-001/`, including
`external-build.json`, signature/package and install checks, fresh backup,
`after-install-comparison.json`, `speech-timing-comparison.json`,
`after-launch-comparison.json`, `after-launch-review.json`, and native/lint logs.
The signed archive remains outside synchronized storage and the IPA is retained
under `.local/releases/background-speech-20260927-001/`.

Storage cleanup was verified before building. The first stale cleanup plan was
rejected without removal; the replacement plan completed with protected hashes
unchanged. Three additional completed-generation compiler caches were explicitly
added to the retention policy and removed with all other generation files checked
unchanged. The previous private build's module cache and verified temporary
installation extraction were also removed. Two identical static-library copies
were replaced by independent APFS clones with unchanged bytes, paths and recorded
modification times. Receipts remain under `.local/maintenance/background-*`.
The configured 20 GiB reserve and 6 GiB build allowance were satisfied before the
archive. No models, originals, backups, archives, symbols or test reports were
deleted. No new simulator visual run or real microphone/background-speech
qualification is claimed for this delivery.
