# Fixed archive appearance baseline

`archive-light.png` is the existing archive captured **before pagination** during
the 2026-09-26 feature-layout regression run. It contains four public synthetic
plans. The typed, paginated implementation matched every pixel below the top 160
pixels on the same iPhone 17 / iOS 26.4 simulator configuration. Only the changing
system status bar is excluded. `archive-light.json` records identities and results.

Reproduce the fixed fixture without touching a personal simulator or physical device:

```sh
REHA_FIXTURE_NOW=2026-09-26T12:08:00Z make test-native-ui \
  TEST_ARGS='-only-testing:TermineUITests/NativeFlowTests/testNativeTabsArchiveSettingsAndColdLaunch'
```

Export the `Archive chronological plans` attachment from the printed `.xcresult`
using `xcrun xcresulttool export attachments`. Compare its original PNG:

```sh
uv run --locked python tooling/checks/compare-screenshots.py \
  apps/ios/Tests/Visual/archive-light.png /path/to/attachment.png \
  --ignore-top 160 --report .local/runs/archive-visual/report.json
```

Any differing app pixel fails. Dimension mismatches and masks covering the entire
image are errors. This reference must not be automatically replaced by a failing
candidate. Other views, Dynamic Type and dark appearance need their own fixed
fixtures; this one passing view does not establish whole-app visual equivalence.

## Retained calendar appearance

The 22 [Zitrus & Olive references](../../../../docs/product/visual-baseline/README.md)
also have a discoverable capture/comparison command:

```sh
make test-visual-baseline TEST_ARGS='--run .local/runs/<new-run>'
```

It uses a disposable simulator, synthetic EventKit calendars and the reference
date `2026-09-26T12:08:00Z`. `REHA_TEST_SIMULATOR` may name an existing booted
`Termine-Native-Test-*` simulator. Run serially with all other simulator tests.
The explicit clock is compiled only into Debug simulator fixture launches;
ordinary app dates and physical devices retain the system clock.

All three UI tests must pass. Every reference requires exactly one fresh screenshot;
duplicates, missing/failed captures and different dimensions fail. Only the top
160 system pixels are excluded. Original reference files are never updated.
The report includes test status, source identities and per-image differences.
A successful calendar comparison still does not qualify every application screen.

An existing result can be compared without rerunning UI work:

```sh
uv run --locked python tooling/checks/compare-visual-suite.py \
  --xcresult /path/to/result.xcresult --run .local/runs/<new-comparison>
```

The retained large-text references include arbitrary scroll positions. Those must
match before claiming exact whole-image equivalence; different viewport positions
are reported as differences and are not silently registered or masked away.
