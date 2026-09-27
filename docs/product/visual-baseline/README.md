# Zitrus & Olive visual references

The 22 committed PNGs contain synthetic appointments and remain byte-exact.
[baseline.json](baseline.json) records their hashes and dimensions;
[contrast.json](contrast.json) records the selected palette's contrast findings.
The [palette source](../../decisions/calendar-palette.html) and app artwork are
retained. German labels, colors, spacing and layout are not changed by source cleanup.

| Category | Light accent | Dark accent |
| --- | --- | --- |
| Therapy | `#85A832` | `#99B653` |
| Medical | `#41A58B` | `#5FB39E` |
| Meals | `#EABC21` | `#EDC745` |
| Administration | `#E8883F` | `#EC9B5E` |
| Other | `#C97086` | `#D28799` |

The finished-day action retains green `AppPalette.tint`. References cover cards,
lists, legends, the largest text setting and finished-day states in light/dark
appearance. The minimum recorded card-text contrast is 4.97:1.

`make test-visual-baseline TEST_ARGS='--run .local/runs/visual-NEW'` captures on a
disposable simulator and compares all declared images. Only the declared system
status region is excluded. Never replace baselines to make a candidate pass.
Follow the [capture contract](capture-contract.md). The baseline explicitly retains
`full_app_regression_qualified: false`; hashes alone do not prove a fresh visual run.
See the [current verification](../../development/verification.md).
