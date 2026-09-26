> Historical record: technical findings retained from the archived development sequence. Project dates, build labels and source references have been normalized. This record is not a new test, delivery approval or signing attestation; unaltered evidence and original validity dates are held in the external private archive.

# Synthetic table integrity — 2026-09-26

The previous generator drew/labeled one day heading nine times in a reproduced
nine-row fixture. Version 2 draws it once and links rows to that evidence. The
new pixel/geometry check also caught Arial's negative left glyph bearing; placing
the ink inside the cell resolves it without widening or truncating the target.

Two local exports each contain 200 inputs: 180 schedules, 10 non-plans and 10
unusable images, with 1,950 invented appointments. All 400 PNG/label files compare
byte-for-byte between the exports. The second generator's inline Pillow pin was
aligned with the locked tooling environment; both actual runs use Pillow 12.1.1.
Their manifest identities differ because they record that generator-source change.

The current `.local/datasets/synthetic-v2-002/manifest.json` SHA-256 is
`5c15c9b7cd3ba79c1da3fa1b29111b4b1864978962e94ab840926b589be9cea4`.
All complete line pixels and field/date links are verified before and after each
lossless save. Five new regressions cover shared headings, contradictory targets,
covered/cropped text, long unbroken words and multi-day/negative/blank cases.
Eight existing reference-export tests also pass. A two-day output was visually
inspected for heading repetition, overlap and wrapping.

These are generator-integrity checks. No model was trained or promoted by this
experiment, and there is no new real-photo accuracy denominator. The 20 real
originals still need approved references/crops and frozen relationships. Do not
mix these synthetic counts into the 99% critical-field or 90% complete-schedule
targets.
