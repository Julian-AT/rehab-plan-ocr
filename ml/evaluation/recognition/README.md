# Recognition evaluation

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

Each variant imports the same public synthetic plan twice into a fresh isolated
store. `force: true`, distinct document IDs and completed inference stages verify
fresh recognition. The trace's historical `cache_used` field means **model-session
reuse**, not duplicate-image result reuse: the second import must reuse warm model
sessions. Recognition, selective rereading and native Apple Vision refinement stay
in the normal pipeline. Review and trace APIs reread the persisted results.

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
