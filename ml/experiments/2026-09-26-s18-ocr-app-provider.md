> Historical record: technical findings retained from the archived development sequence. Project dates, build labels and source references have been normalized. This record is not a new test, delivery approval or signing attestation; unaltered evidence and original validity dates are held in the external private archive.

# Custom OCR through the app import route — 2026-09-26

The corrected pretrained PP-OCRv6 Small and the parity-passing frozen-backbone
adaptation both complete the actual simulator app import, native rereading and
persistence route. No model is promoted and no physical device is changed.

The final run is `.local/runs/ocr-app-provider-20260926-s18-004`, report SHA-256
`c1f29eefb48e636b8a58c05916c5d5532d3fd829c7f09e968599109e1dfb3f4f`.
Its base revision is `650387ae18ad418e94d014a5fe5c975ab1d66dee`; the report retains
the exact source changes under test and evaluator hashes. App binary SHA-256:
`0b623f5711b476e6a9063b2269e6e9a33fbe5d1d9b84914463da3faaad91be6a`.
Host: macOS 26.5.2 arm64; Xcode 26.4 (17E192); iPhone 17 simulator on iOS 26.4.

| Observation | Pretrained baseline | Frozen adaptation |
| --- | --- | --- |
| Forced imports / independent synthetic sources | 2 / 1 | 2 / 1 |
| Persisted appointment counts | 8, 8 | 8, 8 |
| Import seconds, first / warm | 3.336440 / 3.203483 | 3.260626 / 3.273069 |
| Native rereading calls across both imports | 12 | 12 |
| Attempted calendar calls | 0 | 0 |
| Inference stage status | All complete | All complete |

The second import reuses model sessions while forcing new recognition and retaining
a distinct document. `cache_used` in the existing trace represents this session
reuse. Fresh roots, `force: true`, unique IDs, `duplicate: false` and inference stages
are checked independently. Review/trace APIs read the persisted results.

The custom recognizer is the retained `ocr-adaptation-smoke-002` frozen export,
SHA-256 `c40a2cfb53e00e9e00e736e60961fa2c96fb8c19d9d41ed161b21c101b09347b`.
The detector, deployment dictionary and configuration stay unchanged. Manifest
identities distinguish the experimental weights while retaining the architecture
name required by ordinary warm-session reuse. Full fine-tuning remains rejected
for its earlier desktop parity failure and is not selected by this runner.

Run 001 stopped at the build's disk-space reserve. Run 002 completed the baseline
imports but exposed a validator error: it mistook session reuse for cached result
reuse. The corrected validator and its regression tests pass. Run 003 completed
both variants; run 004 repeats after adding explicit host/runtime/helper lineage
and cleanup bookkeeping. Neither failed run was overwritten.

Before these runs, the previous disposable simulator was retired after copying and
hash-checking all 34 files in the app container and both App Groups. Its receipt is
`.local/runs/disposable-simulator-retirement-20260926-s18-001`. Earlier screenshots,
audio, model artifacts and evaluation reports remain preserved outside that device.

Nine new isolated tool regressions cover result/lineage validation, session reuse,
model staging and disposable installation. All 188 tool tests, repository lint,
the normal simulator build and built-bundle verification pass.

These are compatibility observations from a serial synthetic development run.
The timing includes import, pipeline and persistence, but excludes camera/picker
startup and first visible content. It supplies no p50/p95, interleaved speed claim,
real-photo correctness, human correction effort or physical-device qualification.
The full OCR acceptance and quality gates remain open.
