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
