> Historical record: technical findings retained from the archived development sequence. Project dates, build labels and source references have been normalized. This record is not a new test, delivery approval or signing attestation; unaltered evidence and original validity dates are held in the external private archive.

# German listening preparation — 2026-09-26

The final complete host export is `.local/runs/listening-20260926-s17-003`.
Its audio manifest SHA-256 is
`21d7abc83f2a5ec09cf646795ac00b891a62c0eba04a01503d3a6c397edf0351`.
The independently versioned form template SHA-256 is
`0ded22c5687bd4821faebd944c06b5f1ee77e1e47078b992a13b49f94a98aaed`.

Ten invented texts were rendered through Victoria and all nine available German
Mac system voices: 100 complete PCM16 files, with matching prepared text and
verified audio hashes. The durations range from 4.699 to 25.975 seconds. These are
speech lengths, not response latencies. The set has ten shared prompt families,
zero human listeners and no independent comprehension result. Earlier pipeline
runs do not add independent examples.

Victoria uses the shipping Rust SpeechEngine, model manifest and default 0.95 rate;
the system voices use AVSpeechSynthesizer's buffer-export API at their native
default rate. Python 3.12.13, Swift 6.3, Rust 1.98.1, host identity, source/binary
hashes and linkage are recorded. Host output excludes the iPhone audio graph and
must not be used to qualify the first-audible-response targets. No model or voice
was promoted, and no physical device was changed.

Four export-integrity regressions pass: omitted/duplicated/mismatched cases,
silent/truncated files, paths escaping the export and unsafe reference markup.
The Rust example passes Clippy with warnings denied; the Swift writer builds with
Swift 6 complete concurrency checking. The complete tooling test suite passes.

The same form template was exercised locally in Chrome using agent-browser 0.38.1
against export `002`. A muted browser playback advanced to 1.36 seconds in a valid
6.685-second file with no media error. Form inputs survived switching voices,
reference disclosure was recorded, and the downloaded JSON kept human review
incomplete. Test answers explicitly say “AUTOMATISCHER FORMULARTEST – keine
Hörbewertung”; they are not listening scores. The session was closed afterwards.

Human prompt checking, consented listening, counterbalanced study order, patient
comprehension, iPhone voice availability, offline/Bluetooth/interruption behavior,
resource measurements and distribution clearance remain required. See the
[workflow](../evaluation/speech/README.md) before using the local listening page.
