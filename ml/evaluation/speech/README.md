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
accepts `--locale de-DE`; its default is de-AT. Inventory records the legacy speech
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

Generate private host previews with the shared Rust Victoria renderer and every
German voice returned by the Mac's local `AVSpeechSynthesisVoice.speechVoices()`:

```sh
make prepare-listening RUN=.local/runs/listening-example
open .local/runs/listening-example/listening.html
```

Initial setup needs the pinned Victoria assets and host eSpeak/ONNX libraries.
The optional CLI `voice` feature builds this evaluation example; it does not add
training packages or a voice selector to the app. System synthesis uses
`AVSpeechSynthesizer.write(_:toBufferCallback:)`, without microphone access or
playback. No explicit voice download is requested. Airplane-mode verification on
the shipping iOS route is a separate gate, not implied by successful Mac exports.

The ten texts cover dates, times, room numbers, names, abbreviations, missing facts,
confirmation, correction, repetition and longer replies. They are invented,
machine-authored development prompts and remain marked `human_reviewed: false`.
Victoria applies the shipping Rust speech normalization; the resulting prepared
text is passed unchanged to every system voice. Each export records rate, platform,
voice identity, complete audio checksums, durations and synthesis timings.
Victoria uses the app's default 0.95 speed; system voices use their native default.
No loudness normalization or other postprocessing is applied.

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
