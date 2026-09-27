# Visual capture contract

The 22 original PNGs, catalog and exclusion of the top 160 system-status pixels
remain unchanged. Compare all four RGBA channels exactly, with no tolerance.
RGB input is interpreted as fully opaque. Reject different image dimensions;
never align, scale or search images for a closer match.

`CalmCalendarTests` uses synthetic appointments, `de_AT`, selected day 2026-09-26
and fixed clock `2026-09-26T12:08:00Z`. The local iPhone 17 / iOS 26.4 / 23E244
profile is 402 × 874 points, or 1206 × 2622 pixels at scale 3.

## Fixed large-text positions

| Image suffix | Exact appointment | Light card top, pixels | Dark card top, pixels |
| --- | --- | ---: | ---: |
| `large-…-0` and `large-…` | Frühstück I | 1169 | 1169 |
| `large-…-1` | Ärztliches Gespräch | 1338 | 1338 |
| `large-…-2` | Physiotherapie kurz | 782 | 774 |
| `large-…-3` | Anmeldung | 1467 | 1484 |
| `large-…-4` | Freier Termin | 669 | 686 |

The native list button includes 15 points of padding above the colored card;
its target is therefore 45 pixels above the card coordinates. Capture records the
accessibility frame and inset separately. End-time digits begin 273 pixels below
the card top; the first title line without umlauts begins 477 pixels below it.
These measurements explain the clipped original cards without changing their targets.

Bounded drags move the exact row toward its target and require three identical
frame measurements. Position tolerance is half a physical pixel for gesture
control only; image comparison stays exact. The frame must still match after
capture. Missing, unstable or unreachable rows fail. Gestures start in the free
left margin to avoid opening an appointment. For movements below 32 points, a
64-point overshoot followed by the reverse direction avoids tap recognition.
Measured gesture loss is bounded to 64 points; attempt limits remain fixed.

Cards, ordinary lists, legends and finished-day captures also record a stable
anchor, measured frame and scale. The two lower-list originals include a native
scroll indicator. Capture follows the original gesture immediately, checking
identical frames before/after rather than waiting for the indicator to disappear.
There is no special mask or tolerance for scroll indicators.

## Retained limitation

The historical full UI run passed 70 tests, but its strict visual comparison
remained failed at 17/22. Four differences were in the native scroll-indicator
track; the dark finished-day image had 1,559 differing pixels with maximum channel
difference four. This diagnosis did not make the comparison pass. The baseline
still declares `full_app_regression_qualified: false`.

Original images and comparisons remain recoverable in Git/private evidence.
See the [current verification](../../development/verification.md) for fresh checks;
do not treat this historical account as a new visual acceptance.
