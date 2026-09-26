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
not resolve those errors or establish a safe model. Actual native app
conversations, physical resource measurements and independent human-reviewed
examples remain separate checks. Public provider selection is
unchanged and `qualified` / `promoted` remain false.

The subsequent actual Swift host-router replay, before the explicit rename rule,
scores 24/40 exact for the untuned native control, 33/40 for the previous corrected
native candidate and **36/40 for the new candidate**. Each variant uses the same
24 complete rule responses and admits 16 recorded provider responses; none yields
an unsafe proposal after the router in this corpus. The new candidate fixes three
minimal-create cases without new wrong or unsafe post-router results relative to
the previous trained candidate. Its four remaining errors are clarification in
place of an explicitly requested rename following “Nicht löschen”.

The replay uses the current strict app grader and checks all original response,
prompt, model and source identities. Its 112 source inputs remained unchanged;
four deliberately corrupted grading inputs were rejected. It performs no fresh
inference, audio, calendar operation or complete voice workflow. The underlying
four unsafe missing-target answers remain visible in the raw comparison and are
new relative to the untuned control. All results remain one known development
group. The immutable private evidence is
`.local/runs/assistant-v2-router-replay-20260926-s21-001`.

After the separately tested, narrow explicit-rename rule (`calendar-4`), a second
actual host replay scores **28/40, 37/40 and 40/40** for those same three variants.
All have zero unsafe post-router proposals. The recording inputs are byte-identical
to the first replay. Each variant now uses 28 complete rule answers and 12 provider
answers: the four additional rename successes belong to the rule, while the new
model's three-case advantage over the previous candidate remains unchanged under
the same current rules. No new incorrect or unsafe post-router case appears.
The rule resolves one previously discussed live reference, proposes only the
explicit title, and still requires the visible confirmation button before writing.
Focused conversation tests cover stale/ambiguous targets, extra model fields,+cancellation and pending field collection; these are developer regressions.

The second replay's 115 pinned source inputs remained unchanged. Evidence is at
`.local/runs/assistant-v2-router-replay-20260926-s21-002`; neither replay is a complete
voice workflow or independent generalization test. The separately corrected
Python ASCII-time validator leaves all 200 retained raw strings' assessments
unchanged (`assistant-validator-contract-delta-20260926-s21-001`). Frozen training,
export and first-replay evidence retain their original validator identities.

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
