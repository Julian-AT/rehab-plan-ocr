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
- New stores default to 30-day completed-source retention. Schema 9 adds durable
  aggregate deletion, including PDF originals, with interruption recovery.
- Recognition preserves unreadable day boundaries and rejects clipped column
  rereads. German date corrections and explicit conversation states have targeted
  regressions; broader dialogue and patient testing are still required.
- The Rust core passes 157 tests and workspace Clippy. Native calendar tests pass
  with one simulator-only skip. Current simulator builds pass. The full UI suite
  is still under verification; the ledger records failures and targeted reruns.

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

Custom model qualification, frozen real-data evaluation, human-authored dialogue
evaluation, local voice listening tests, complete offline capability tiers and
physical performance measurements remain open. The eSpeak-NG redistribution
dependency must be resolved before public packaging. No Git remote is configured;
hosted CI and public distribution have not been activated.

Older delivery reports describe their original builds and measurements. They do
not supersede the current ledger or establish new accuracy, latency or release
acceptance.
