# Recognition evaluation

Critical-field metric version 2 covers date, start, end, overnight end date,
duration, title, location and therapist, consistent with the training objective.
Accuracy reports its explicit correct/printed-field counts. Each assessed printed
field contributes once; unknown fields and correctly empty cells do not inflate
that denominator. Inventing a value in an approved blank critical field still
produces a critical error and, if unflagged, a false acceptance. Historical
time-only accuracy is a different metric and must not be compared as equivalent.

`compare-recognition.py` retains case-level regressions even when overall scores
improve. The evaluator's version-1 row identities list missing reference IDs and
count unmatched predicted appointments by a hash of their calendar values.
Generated IDs, geometry and diagnostic messages are excluded from that hash;
duplicate invented appointments retain their multiplicity. New omissions or
changed/additional hallucinations block eligibility even when their totals stay
constant. Findings retain the source and process-repeat number.

Old count-only metrics remain readable by Rust, but cannot qualify a comparison.
Rescore the retained predictions with the current evaluator and the same approved
references into a new evidence directory; do not replace historical reports or
invent identity fields. These hashes remain private evaluation data, not an
anonymization guarantee. This gate never promotes a model to the shipping default.

Run the corrected pretrained baseline and the registered frozen-backbone experiment
through the ordinary simulator app's import, native field rereading and persistence:

```sh
make test-recognition-app-trial TEST_ARGS='--run .local/runs/<new-run> --simulator <disposable-id>'
```

Use a booted, disposable `Termine-Native-Test-*` simulator and run serially. Restore
the normal app dependencies first; the frozen artifact must exist at its registered
local training path. The runner builds the normal app and verifies source identities
before and after evaluation. It signs only a disposable copy, preserving all App
Group entitlements. This route is restricted to Debug simulator builds.

The original smoke card remains the default. To evaluate a later registered frozen
checkpoint, append `--model-card <filename.json>` to `TEST_ARGS`. Only a regular
file directly in `ml/registry` is accepted. Later cards must bind the selected
weights and complete successful export/parity receipts; absent, changed or failed
evidence stops before model copying. The card's hash is checked again after the
app run. The full-adaptation variant remains outside this frozen-model probe.

Each variant imports the same public synthetic plan twice into a fresh isolated
store. `force: true`, distinct document IDs and completed inference stages verify
fresh recognition. The trace's historical `cache_used` field means **model-session
reuse**, not duplicate-image result reuse: the second import must reuse warm model
sessions. Recognition, selective rereading and native Apple Vision refinement stay
in the normal pipeline. Review and trace APIs reread the persisted results.
The verifier requires a positive native reread count and completed Vision refinement
in each trace, so a result that silently skipped that branch cannot pass.

The host adapter allows photo decoding and native recognition calls only. Calendar
reads, writes and synchronization fail and invalidate the evaluation. Neither audio
sessions nor physical devices are used. Original runtime assets remain pinned;
only the experimental copy's recognizer changes. Model, dictionary, manifest,
training lineage, app binary, evaluation sources and simulator/toolchain identities
are retained privately with raw results and traces.

The [first app experiment](../../experiments/2026-09-26-s18-ocr-app-provider.md) passes
compatibility for both variants. One synthetic source and serial repeated imports
do not establish real-photo accuracy, paired latency, correction effort or model
promotion. Camera/picker interaction and first visible content are outside this
probe. Human-approved grouped references and complete physical-device measurements
remain required.
