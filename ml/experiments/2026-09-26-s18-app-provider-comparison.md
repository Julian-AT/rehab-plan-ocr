> Historical record: technical findings retained from the archived development sequence. Project dates, build labels and source references have been normalized. This record is not a new test, delivery approval or signing attestation; unaltered evidence and original validity dates are held in the external private archive.

# Development interpretation comparison in the simulator app

All four routes receive the same 40 existing invented validation cases, using the
same app binary (`447c40f106a99c5b1397a8d518e5734144706916dc571744b18060c5d991de12`),
iPhone 17 / iOS 26.4 simulator and evaluator sources. The registered untuned and
tuned GGUFs use the same native runtime and prompt. Normal production selection
is unchanged; experimental packages remain excluded from regular release packaging.

| Interpretation route | Interpreted | Exact operations | Incorrect mutation proposals | Other outcomes |
| --- | ---: | ---: | ---: | --- |
| Complete calendar rules | 4/40 | 4/40 | 0 | 36 unmatched |
| Rules + Apple | 4/40 | 4/40 | No model answers measured | 36 system errors |
| Rules + untuned Qwen | 16/40 | 4/40 | 2 | 24 rejected answers |
| Rules + tuned Qwen | 39/40 | 17/40 | 11 | 1 rejected answer |

Four conversational next-event queries select complete rules in each route. The
Apple provider advertises availability, but every attempted model request fails
with FoundationModels/SensitiveContentAnalysisML error 15 and missing underlying
data (NSCocoaErrorDomain 4865). This is recorded as a runtime failure, not a model
answer, successful fallback or proof of physical-device unavailability.

The tuned route has eleven **newly** incorrect mutation proposals: the untuned
route's two affected cases improve, while eleven others regress. The existing
paired auditor also flags changed wrong operations and one new rejection, giving
23 cases needing review. All cases share one speaker-group label, so the grouped
audit supplies no confidence interval. Better exact-match totals do not qualify
the tuned model. Neither model is promoted.

The untuned artifact is the original retained GGUF from the September 26, 2026 export,
SHA-256 `cf3244d20b79dd454f06fb9be8744c5beecf76b9e75a7cc581f17d6c29b09220`,
1,509,347,584 bytes. Its new [registry card](../registry/assistant-untuned-001.json)
preserves the original export's failed overall parity status; its baseline-export
stage alone succeeded. The builder permits only registered experimental variants
and checks size, hash, format and private artifact location before bundling.
Four new model-selection regressions, all 179 tool tests and lint pass. The normal
and untuned trial builds pass. Completed Rust debug intermediates were inventoried
before removal to restore disk reserve; original data, backups, weights, app
products and evidence remain intact.

Evidence directories are `.local/runs/assistant-app-40-<route>-20260926-s18-001`:

| Route | Report SHA-256 |
| --- | --- |
| rules | `7fd415658807a6369e0dcc77b43659e17bdf653ecdfa3815910485ad25b6a097` |
| apple | `4768325400772294cdeaa98451aff1099a2bd39b56e29c452c3b9ccef09c284c` |
| untuned | `3c29afea66e2869531daa211ff10cdb327dee2147d030b09a543386f4f784ec5` |
| custom (tuned) | `af0622a3af739ca28e2917efa689e576b2cad7ae4636b7f0cd4fc323f25fb8d3` |

The paired input and summary are retained under
`.local/runs/assistant-app-40-paired-20260926-s18-001`, summary SHA-256
`4c0a11ae4d40fc9255344b1a050e25c301cf2c51be64787d5ff9c9032496bed7`.
The recorded `paired.py` implementation's `summarize(cases, groups)` reproduces
the metrics/regression section from that input; input report hashes and the
summarizer hash remain in the summary.

This probe covers the actual interpretation router and typed boundary. It does
not execute `VoiceModel`'s earlier cancellation/invalid-date/mutation rules,
conversation state, calendar reads/writes, confirmation or speech. “Rules” therefore
does not mean the complete spoken workflow. No calendar operation or audio session
is opened. Runs are serial, not interleaved latency comparisons; timing observations
are not cold/warm, first-audio, energy or physical performance measurements.

Ten selected, unreviewed families remain development data, with no new independent
dialogues or final holdout. Eligible Apple hardware, human German review and full
conversation/device qualification remain open. Reproduction is in the
[evaluation guide](../evaluation/conversation/README.md).
