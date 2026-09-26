> Historical record: technical findings retained from the archived development sequence. Project dates, build labels and source references have been normalized. This record is not a new test, delivery approval or signing attestation; unaltered evidence and original validity dates are held in the external private archive.

# Calendar timestamp projection

Calendar values retain their original serialized strings and parse dates when
decoded, constructed or edited. Layout and calendar answers reuse these typed
values. The regression checks offset timestamps, edit invalidation, wire keys,
value-copy independence, invalid unavailable events and the existing DST cases.

Five paired, interleaved desktop runs compared revision `1a20779` with the cached
timestamp implementation, using 84 invented events and three projection passes
per run. Both binaries used Swift `-O` and produced the same checksum in every
run. Median construction plus projection time was **220.14 ms → 13.37 ms**.
Construction cost is included because parsing moved into object construction.

This is a focused macOS microbenchmark. It excludes EventKit, app startup,
rendering and speech and does not qualify iPhone latency, energy or usability.
The five samples do not establish a reliable p95. Source hashes, compiler,
individual measurements and copied sources remain in the local run report.

```sh
uv run --locked python ml/evaluation/device/compare-agenda.py \
  --output .local/runs/agenda-projection-comparison
make test-agenda-projection test-agenda-cache test-calendar-answers test-conversation-replies
make build
make test-native-ui TEST_ARGS='--built -only-testing:TermineUITests/AgendaPreviewTests/testWeekNavigationAndTimeline -only-testing:TermineUITests/VoiceSurfaceTests/testTypedCalendarFactsAndRepeatWithoutModel'
```

These four probes, the simulator build and both selected UI tests passed. The
existing calendar and voice presentation were retained.
