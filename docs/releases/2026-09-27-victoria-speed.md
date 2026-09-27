# Victoria preparation and inference speed

Build 2026092708 retains Victoria's pinned model, voice embedding, German
frontend, pronunciation rules and saved speaking rate. The view layout and
spoken-word display are unchanged.

The voice engine now verifies and loads its assets on the native blocking worker
after microphone startup succeeds. Listening does not await voice preparation.
The existing mutex makes preparation and synthesis share one loaded engine;
request identifiers are rechecked after waiting for the mutex and after loading.
Stop invalidates preparation and playback together. An opportunistic preparation
failure is retried through the normal rendering error surface.

Inference uses four intra-operation CPU threads and one inter-operation thread,
with explicit bounded variants for phone qualification. The previous setting was
two intra-operation threads. PCM16 decoding uses one bounded buffer access with
unaligned little-endian reads; cancellation and format validation remain intact.

Playback already prepares the next phrase while playing the current phrase.
This remains phrase-level streaming: the current Kokoro graph returns the whole
waveform for each phrase. No claim of incremental sample generation or a new
streaming model is made. Changing to a split Neural Engine runtime would require
converting and qualifying Victoria's own German weights and word durations.

## Verification and delivery

The actual voice-flow checks pass, including preparation after microphone
readiness, failed microphone startup, obsolete turns, heard history, repeat and
calendar confirmation. Victoria PCM format/slice/corruption/cancellation checks,
the system-renderer checks, generated bindings and `make lint` pass. The private
native archive was built from clean source `86ccde8`; all four signed components
and all 15 pinned speech files were verified. No fresh simulator visual run is
claimed for this performance-only change.

A fresh scoped backup of the app and both App Groups preceded the in-place phone
update. The strict post-install comparison passed with no persistent-data
differences. Build 2026092708 is installed. The initial benchmark launch was
rejected by iOS because the device was locked; physical-phone timing is pending.

The private fixed-text probe compares two, four and six threads in three
counterbalanced orders. It separates asset preparation from first and warm
rendering, records thermal state and word marks, validates audio, and checks
obsolete requests. It does not capture the microphone, change preferences, or
read/write calendar records. Its results measure renderer preparation rather
than complete conversation latency.

Supporting Mac CPU profiling found convolution dominated generation. Median
warm preparation for the medium and longer synthetic phrases dropped from
0.997/1.862 seconds at two threads to 0.565/1.054 seconds at four, and
0.425/0.772 seconds at six. These desktop measurements do not establish the
best phone setting or real-conversation speed.

Private evidence and reproducible probe scripts are retained under
`.local/runs/victoria-speed-20260927-001/`; the signed IPA is under
`.local/releases/victoria-speed-20260927-001/`. Compiler-cache cleanup retained
referenced debug inputs, original model assets, backups, archives, symbols and
run evidence. The archive's preflight satisfied the 20 GiB reserve plus 6 GiB
build allowance.
