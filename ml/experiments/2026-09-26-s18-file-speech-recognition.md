> Historical record: technical findings retained from the archived development sequence. Project dates, build labels and source references have been normalized. This record is not a new test, delivery approval or signing attestation; unaltered evidence and original validity dates are held in the external private archive.

# German file recognition of synthetic listening previews

The host SpeechTranscriber completes 100/100 retained synthetic WAV files from
ten voices and ten shared prompt families. This is file-ASR development evidence,
with zero human speakers or listeners, no iPhone changes and no provider promotion.

Before setup, macOS 26.5.2 reports German SpeechTranscriber assets as supported but
not installed. The legacy recognizer has no authorized/local German route in this
host context. Explicit setup installs de-AT assets; the subsequent setup check
reconfirms installation but still requests an installation object. Its report
does not measure downloaded bytes. Transcription requires installed assets and never requests
microphone permission, speech authorization or an asset installation.

The compiled Swift 6 probe verifies input checksums, consumes only final segments
and finalizes the complete audio file. The Python runner checks unique run IDs,
locale/provider identities, finite timing and nonoverlapping in-file ranges.
Original audio and evaluator identities are rechecked after all 100 cases. A new
process handles each file; system-managed models may remain resident. The exposed
API does not provide a stable model-weight hash. Host OS, compiler, locale,
availability, binary and source hashes are retained instead.

All ten date transcripts read “Montag, dem 26. September 2026”. Other cases expose
substantive differences: one time transcript contains both 9:00 and 9:30; several
room cases corrupt “Ergotherapie”; person names and MTT vary between voices.
These observations do not assign the fault to synthesis or recognition and do not
establish human comprehension. Semantic scoring and real German speech remain open.
Only one full text matches after ignoring case/punctuation, largely because the
prepared references spell numbers while ASR often writes digits. That orthographic
comparison is not a factual accuracy or voice-quality score.

The de-DE configuration also completes the same 100 files after its separate
explicit asset setup. All 100 final transcripts are byte-identical to de-AT.
The original audio checksums, per-file result checksums and validated final
segments agree with both retained reports. This adds no human speakers or prompt
families and establishes no preference between the locales. The API does not
reveal whether the two locale configurations share underlying model weights.

The first de-DE attempt correctly fails before any transcription because only
de-AT assets are installed. That failure remains in
`speech-file-transcription-deDE-20260926-s18-001`; its report SHA-256 is
`f507e34f567965644d1b2ff1f2f0c948f88356006318b2cb6b3d8b57894d34ad`.
Explicit setup is retained in `speech-file-setup-deDE-20260926-s18-001`, report SHA-256
`064ca2f805fd254c9179cb21f15987bfb97d53531ea0600600f178b6541caf00`.
The successful `speech-file-transcription-deDE-20260926-s18-002` report has SHA-256
`ff9249ded38ee8f2b03755adad55bfdb1bccb4824f21a43c106ab20a2e9a30c2`.
The paired observation receipt `speech-file-locale-comparison-20260926-s18-001.json`
has SHA-256 `096e70fc80ec57501e10526d15de3797affd5929a2dfc9d9216c99e25c1374a8`.
All paths are below `.local/runs`. No timing comparison is made while unrelated
OCR training is active on the host.

The report and per-case inputs/results/logs are in
`.local/runs/speech-file-transcription-20260926-s18-001`. Report SHA-256:
`e5720b6cb778d49bac426b45b40cfa06f43c8c800456556e37b657c364b9aac8`.
The reusable setup receipt is `.local/runs/speech-file-setup-20260926-s18-002/report.json`,
SHA-256 `e270da9cf8e1a00eb6fe90f28abbd9b6dc823538b0d02a844b3f7da8c9d7e847`.
The initial actual installation and successful single-file canary remain in
`speech-file-setup-20260926-s18-001`.

The follow-up setup guard skips installation requests when assets are already
installed. Its actual compiled run `speech-file-setup-20260926-s18-003` confirms
installed → installed with `download_requested: false`. The 100-file transcription
evidence retains the preceding source implementation in Git (`ae237f8`); its
transcription branch is unchanged. No result was regenerated to replace that run.

Five new isolated verifier tests, all 202 tool tests, repository lint and actual
Swift compilation pass. The Make commands and API references are in the
[speech evaluation guide](../evaluation/speech/README.md). File analysis times
exclude capture, natural pauses, interpretation and playback, so they cannot be
used for the first-audio targets. Local APIs and installed assets do not establish
shipping-device airplane-mode behavior, Bluetooth handling or endpoint quality.
