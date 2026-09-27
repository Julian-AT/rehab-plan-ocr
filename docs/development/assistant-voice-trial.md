# Integrated experimental voice trial

This trial exercises `VoiceModel`, the `tuned-v2` provider, proposal/confirmation
buttons and `SpeechOutput` using five fixed cases. Scripted transcripts replace
recognition; four cases use a calendar fake and one uses owned EventKit preview
calendars. It does not replace the normal UI suite.

```sh
make build-assistant-voice-trial
make test-assistant-voice-trial RUN=.local/runs/assistant-voice-NEW SIMULATOR=OWNED_FRESH_UUID SOURCE_COMMIT=EXACT_FULL_COMMIT
```

The build uses `--model tuned-v2 --voice-ui-tests` and restores the normal generated
project afterward. Restore the pinned assistant runtime and registered weights
first. The test consumes the already-built separate product and requires an exact
clean Git commit, source/model hashes and a disposable `Termine-Native-Test-*`
simulator. Other model selections are rejected.

Both commands enforce 44 GiB free: 24 GiB peak plus 20 GiB reserve, even if the
caller sets a lower generic peak. Run serially with no competing model work. A
shared native lease may wrap the sequential commands through
`python3 tooling/build/product_generation.py lease -- sh -eu <reviewed-script>`.

All five exact tests must run and pass. The grader rejects title/field loss,
provider bypass, writes before visible confirmation and missing responses. Each
required answer, including save confirmation, needs its own response identity,
prepared words, observed audio levels and natural playback completion. Earlier
successful audio cannot substitute for a later answer.

Results remain `qualified: false` and `full_voice_workflow: false`. They do not
measure real microphone recognition or human listening. Late cancellation holds
an already-completed response before delivery; it does not prove interruption of
an active native kernel. Actual model/App Group integration must pass in the run.
