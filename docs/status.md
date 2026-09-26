> Historical record: technical findings retained from the archived development sequence. Project dates, build labels and source references have been normalized. This record is not a new test, delivery approval or signing attestation; unaltered evidence and original validity dates are held in the external private archive.

# Development status — 2026-09-26

The application is native SwiftUI with Rust, SQLite, UniFFI and Apple services.
The former web/Tauri interface is no longer the product. The current work follows
the [four-milestone implementation ledger](implementation-plan.md).

The installed visual baseline remains
[Zitrus & Olive](preview/2026-09-26-s14-zitrus-olive/README.md). The last documented
physical installation is build 2026092624; the device was unavailable for a fresh
installed-build check. Simulator builds are development evidence and do not update
the phone. Every device update still requires explicit preview/listening approval,
a fresh backup and a persistent-data comparison without uninstalling.

## Current evidence

- Calendar reads/caches carry a selection revision; empty selection means no
  calendars. Agenda display is independent of reminder maintenance. Widgets use
  the same selected calendars as the agenda and ordinary voice questions.
- Durable saves survive maintenance failures. Current ownership resolves repaired
  event identities while historical approved records remain intact. Changed
  calendar snapshots invalidate pending previews.
  Native alarm-journal failures now preserve successful import and event-edit
  receipts, with separate warnings carried through Rust and Swift. The actual
  EventKit failure/replay regression passes without duplicating events.
- New stores default to 30-day completed-source retention. Schema 9 adds durable
  aggregate deletion, including PDF originals, with interruption recovery.
- Schema 10 caches compact scan summaries with transactional backfill and
  invalidation on recognition changes. Original evidence and preferences survive
  migration. Schema 11 adds indexed, typed archive pages; the list retains visible
  rows on refresh and rejects obsolete results. Full evidence loads in detail views.
- Recognition preserves unreadable day boundaries and rejects clipped column
  rereads. German date corrections and explicit conversation states have targeted
  regressions; broader dialogue and patient testing are still required.
- The Rust workspace passes 172 tests and Clippy. Native calendar tests pass
  (15 tests, one simulator-only skip). Current simulator builds pass. The full UI suite
  is still under verification; the ledger records failures and targeted reruns.
- The archive/cold-launch UI regression and asynchronous pagination probe pass.
  Its fixed synthetic screenshot has zero changed app pixels against the capture
  before pagination, excluding only the changing system status bar.
- The save/undo UI regression passes with explicit calendar visibility selection;
  saving and undoing keep that selection independent of the destination. Real
  speech output and spoken-confirmation UI runs still abort on a CoreAudio RPC
  timeout and require investigation before release qualification.
- iOS sources now live by feature; Apple and Rust packages, model development,
  tooling, runtime model manifests and notices have dedicated locations. Normal
  builds verify assets/bindings without restoring or converting them. An offline
  simulator build passed. All 38,570 private files were relocated to `.local/` with
  their hashes preserved; active paths use that storage. Historical references use
  ignored compatibility links. Other build-cache moves and documentation cleanup remain.
- Agenda timestamps are parsed once per event value. A paired desktop projection
  microbenchmark improved from 220.14 ms to 13.37 ms median including construction;
  this does not establish real-device or full-interaction performance.
- Audio observations use one bounded, ordered consumer with explicit overflow
  failure. PCM work and waveform updates are bounded without shortening endpoint
  pauses. Native probes and two input UI tests pass; the separate output UI test
  aborted on a simulator CoreAudio RPC timeout before playback. Full audio/device
  qualification remains open.

## Dataset and models

The live reference readiness check reports **20 original photos, zero approved
references, no independent final holdout and accuracy changes disabled**. Related
source groups still require review and freezing. Historical augmented counts and
transcription drafts are not independent approved examples.

The bundled OCR model remains pinned PP-OCRv6 Small; Victoria/Kokoro remains the
existing voice. Neither is being replaced based on synthetic smoke measurements.
Separate OCR and MLX-LM environments are locked under `ml/training/`. A matching
trainable OCR checkpoint loads and has completed a synthetic training/export
smoke test with 24/24 ONNX parity cases. See the
[model experiment](../ml/experiments/2026-09-26-s16-checkpoint-compatibility.md).
The resumable OCR trainer now compares frozen-backbone and full adaptation, with
atomic optimizer checkpoints and validation stopping. Its synthetic interruption
test matches all 902 model/optimizer tensors. Frozen-backbone export passes 24/24
desktop parity cases; full adaptation fails 2/24 and remains rejected. Both retain
4/4 correctness on the tiny synthetic validation set, already achieved by the base.
No real-photo improvement follows. See the
[resumption experiment](../ml/experiments/2026-09-26-s17-ocr-resumption.md).
Qwen3-0.6B also completed an eight-step LoRA/fusion/GGUF smoke run and local runtime
execution. Both untuned and briefly tuned models failed the 12-case structured
output diagnostic: all outputs were rejected. The artifacts remain experimental,
with no app provider change. See the
[assistant experiment](../ml/experiments/2026-09-26-s16-assistant-compatibility.md).

Custom model qualification, frozen real-data evaluation, human-authored dialogue
evaluation, local voice listening tests, complete offline capability tiers and
physical performance measurements remain open. The eSpeak-NG redistribution
dependency must be resolved before public packaging. No Git remote is configured;
hosted CI and public distribution have not been activated.

Older delivery reports describe their original builds and measurements. They do
not supersede the current ledger or establish new accuracy, latency or release
acceptance.

Replacement-preview concurrency now has a dedicated passing regression probe:
changed inputs, late resolutions, A→B→A changes and calendar invalidation cannot
restore an old preview or its deletion approval. The simulator build passes.

The assistant development trainer now preserves full epoch optimizer/random state
and selects checkpoints with unsafe-mutation and grouped operation-error gates.
The new proof matches 171 tensors after resume and 10/10 complete answers through
fusion/GGUF. Its 4/10 correct development operations and one unsafe proposal still
fail acceptance; it is not integrated as the app's provider. The expanded invented
corpus still awaits human review and is not an independent real dialogue set.
