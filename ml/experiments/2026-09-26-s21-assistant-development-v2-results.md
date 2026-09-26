> Historical record: technical findings retained from the archived development sequence. Project dates, build labels and source references have been normalized. This record is not a new test, delivery approval or signing attestation; unaltered evidence and original validity dates are held in the external private archive.

# Assistant development v2: trained and exported

The [predeclared experiment](2026-09-26-s21-assistant-development-v2.md) completed
without changed inputs, selection rules or parity thresholds. Training stopped
after eight epochs / 1,088 steps by patience three; the existing ordered score
selected epoch five. Both selected and latest complete optimizer checkpoints
remain private. The [model card](../registry/assistant-development-002.json)
binds the source, dataset, selected checkpoint, export and result evidence.

| Same 40 known development cases | Previous selected MLX adapter | New selected MLX adapter |
|---|---:|---:|
| Exact structured answers | 17 | 30 |
| Schema-valid answers | 38 | 36 |
| Unsafe mutation proposals | 10 | 4 |

The training set grew from 112 to 272 invented examples. The 40 validation rows
are unchanged, but already informed failure diagnosis and the new training data.
They are known development controls, not an untouched test set. They still form
one connected development group and represent zero independent real dialogues.
The lower schema-valid count is retained alongside the better exact-answer count.

Adapter fusion and the native F16 GGUF conversion now pass **40/40 complete-answer
comparisons**: adapter, fused and native candidate produce identical texts. The
native candidate therefore also scores 30 exact / 36 schema-valid / four unsafe.
All 40 old and new native prompt files are byte-identical; the current binary
prompt boundary is used. The fresh untuned native control scores zero exact,
ten schema-valid and two unsafe answers. Its results are kept separately from
older differently configured runtime controls and the MLX baseline.

The four unsafe candidate proposals all select a specific event for an ambiguous
deletion request. No calendar operation was executed. Passing export parity does
not resolve those errors or establish a safe model. Current Swift-router replay,
actual native app conversations, physical resource measurements and independent
human-reviewed examples remain separate checks. Public provider selection is
unchanged and `qualified` / `promoted` remain false.

Private evidence:

- `.local/runs/assistant-development-002`: baseline, all checkpoint states,
  selected metrics, complete export stages, prompts, raw answers and parity.
- `.local/runs/assistant-development-002-evidence`: source archive / patch,
  twenty input hashes, execution logs, successful training and export exit codes,
  and unchanged-input verification.

Earlier failed experiments remain unchanged. This result establishes an improved
development score and a passing export for this corpus, not product qualification.

The isolated simulator trial accepts the new artifact explicitly:

```sh
make build-assistant-trial ASSISTANT_TRIAL_MODEL=tuned-v2
```

The historical `tuned` and `untuned` selections retain their original identities.
All choices require intact registered experimental weights; the public bundle
continues to reject these assets. Building the trial does not update a device.
