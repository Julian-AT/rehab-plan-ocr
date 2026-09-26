# German listening development set

## File recognition on the host

Prepare Apple SpeechTranscriber assets explicitly, then transcribe the existing
invented listening set through the installed German module:

```sh
make setup-speech-evaluation RUN=.local/runs/<new-setup>
make transcribe-listening LISTENING=.local/runs/listening-20260926-s17-003 \
  RUN=.local/runs/<new-transcription>
```

Setup may download the system model on the Mac. Transcription never downloads
assets, requests microphone/speech permission or changes the iPhone. The CLI also
accepts `--locale de-DE`; its default is de-AT. Both Make commands accept
`SPEECH_LOCALE=de-DE`. Each locale needs its own installed-asset check; successful
de-AT setup does not establish de-DE readiness. Inventory records the legacy speech
recognizer's authorization and local-model availability without requesting access.
Missing assets fail before processing the corpus.

Every audio file and final segment is checked against its run ID, locale, checksum
and bounded timestamps. Per-file logs, raw transcripts, prepared reference text,
binary/source/platform identities and failures remain private. A new recognizer
process is used for each file; shared system models may remain resident. File
analysis time excludes microphone capture, conversational pauses, interpretation
and playback. It cannot demonstrate the app's first-audio or interruption targets.

An orthographic match ignores case and punctuation only. Spoken numbers rendered
as digits are therefore marked different even when they express the same facts;
the retained text pairs need semantic review. These machine-generated voices are
not real speaker samples, listening judgments or an independent voice-quality
benchmark. No voice or ASR provider is selected by this probe. Asset presence and
the local API do not replace shipping-device airplane-mode verification.

The implementation uses Apple's [audio-file analysis API](https://developer.apple.com/documentation/speech/speechanalyzer/analyzesequence(from:))
and separate [asset installation request](https://developer.apple.com/documentation/speech/assetinventory/assetinstallationrequest(supporting:)).

## Listening previews

Generate private host previews for every German voice enumerated by the same
`SystemSpeechRenderer` used by the app:

```sh
make prepare-listening RUN=.local/runs/listening-example
open .local/runs/listening-example/listening.html
```

The CLI compiles the product's `SystemSpeech.swift` and `OutputAudio.swift`, then
passes each prepared text unchanged into that renderer at the app's rate multiplier
0.95. It uses the same conversion to mono 24 kHz PCM as playback. Export writes
PCM16 little-endian WAV with quantization/clipping only, without gain normalization.
It does not request microphone access, playback or an explicit voice download.
The inventory records locally enumerated identities; completed synthesis establishes
their availability on this Mac for this run. Installed assets and airplane-mode
behavior on an iPhone remain separate checks.

Victoria is available only as an explicit development comparison:

```sh
make restore-experimental-speech convert-experimental-speech
make prepare-listening-experimental RUN=.local/runs/listening-experimental-example
```

That optional path needs the pinned Victoria assets and host eSpeak/ONNX libraries.
Its Cargo `voice` feature remains outside the public app's release path. A comparison
run records `includes_experimental_victoria`; no generated export promotes a voice.

The ten texts cover dates, times, room numbers, names, abbreviations, missing facts,
confirmation, correction, repetition and longer replies. They are invented,
machine-authored development prompts and remain marked `human_reviewed: false`.
The Rust preparation command uses the shared speech normalization; the resulting
text is passed unchanged to every system voice and remains identical to the
previous development prompts. Each export records rate, platform, voice identity,
audio checksums, durations, preparation timings and the renderer's word-progress
marks. These marks use system delegate/PCM buffer boundaries, not phoneme alignment.
They must cover the prepared text once, stay ordered and lie inside the audio.

Per-case manifests retain completed samples and errors after each attempt. Each
voice also has process logs, and a failed voice does not prevent attempts for the
remaining inventory. Only complete, validated voices enter the anonymous form;
any failed voice makes the overall generation command fail and remains listed in
`failed_voices`. Source, preparation, compiler and binary hashes are recorded and
rechecked after rendering. A source change rejects the comparison. Use a fresh run
directory; historical manifests and recordings are never rewritten.

The browser form uses anonymous labels in a fixed versioned random order. Its key
is in `manifest.json`, separate from the form. Keep the key away from listeners;
this is simple identity concealment, not a secure blind-trial system. Use the same
playback volume/equipment and short sessions with breaks. Counterbalance voice
order across participants in the actual study; the fixed generated order alone
does not do that. Record consent and a pseudonymous participant ID separately using
the [collection guide](../../../docs/product/research/collection-guide.md).

Listeners first transcribe the requested information, then rate comprehension and
naturalness. Opening the reference is recorded. The local JSON export preserves
partial responses and never marks human review complete. Input remains in browser
memory until exported; no server or network submission is present. Automated
browser checks must be labeled as such and never counted as listening judgments.

`make refresh-listening RUN=<existing-run>` verifies all blind audio hashes before
rebuilding only the form. `form.json` separately records its template, prompt,
HTML and original audio-manifest identities, so form changes need not regenerate
the audio. Original render lineage remains intact.

Passing generation means all expected texts have nonempty PCM16 files, matching
prepared text and valid hashes. It does **not** select the best voice. Ten voices
on ten texts are ten shared prompt families and zero human listeners, not 100
independent comprehension observations. Repeated exports do not increase that
denominator. Human scoring, new speech/speakers, iPhone provider availability,
interruption/repeat behavior, first audible response, energy/thermal measurements
and distribution suitability remain required before promotion. Host synthesis
times exclude audio startup and must not be used for the ≤3/≤5-second voice targets.

API references: [available voices](https://developer.apple.com/documentation/avfaudio/avspeechsynthesisvoice/speechvoices()),
[buffer synthesis](https://developer.apple.com/documentation/avfaudio/avspeechsynthesizer/write(_:tobuffercallback:)).
