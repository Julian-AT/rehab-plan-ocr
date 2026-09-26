# Isolated audio runtime probe

This separate simulator app constructs a real AVAudioEngine, connects a 24 kHz mono
player, renders a quiet 250 ms tone and checks the player's render clock. It has no
calendar, OCR, speech recognition or model dependencies and is not part of the
shipping application. The workflow does not install anything on physical devices.

Run serially, with other simulator sessions stopped:

```sh
make test-audio-runtime TEST_ARGS='--run .local/runs/audio-runtime-example'
```

The command builds into the new ignored run directory, creates a disposable iPhone
17 simulator, launches three times and removes that simulator afterwards. To test
an existing failure state, pass `--simulator UUID` for a booted simulator named
`Termine-Native-Test-*` or `Reha-Audio-Test-*`; that simulator is retained. Use
`--attempts 1` for a single reproduction. Never run alongside app UI/audio tests.

The report records source/toolchain/runtime identity and separate attempts.
Success requires a new run ID and `passed` stage after real rendering. A zero
`simctl` status can also mean the child aborted and is insufficient. Failure logs
and the last stage stay in the run directory; related `AudioEngineProbe-*.ips`
crashes are in the host's DiagnosticReports directory. These elapsed durations
are diagnostic workflow evidence, not speech-latency or device-acceptance scores.
