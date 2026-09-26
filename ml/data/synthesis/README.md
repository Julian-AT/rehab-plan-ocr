# Invented schedule fixtures

Generate a new local dataset through the locked tooling environment:

```sh
make generate-synthetic DATASET=.local/datasets/synthetic-v2-example SYNTHETIC_COUNT=200
```

`FONT` selects a local font file; its checksum, size, generator checksum, Python,
Pillow and seeds are recorded. Version 2 exports lossless PNGs and JSON labels.
Existing version 1 JPEG datasets are historical and are not rewritten.

Dates and column headings are drawn and labeled once. Each appointment links to
its shared day heading. Row heights follow actual wrapped text, including long
unbroken names; glyph bearings remain inside their fields. All printed document
and column headings have line labels as well. Complete labels are checked against
the actual glyph pixels and field geometry before and after saving each image.
Export stops if text is covered, clipped, duplicated or contradicts a field value.

Each block of 20 seeds includes 18 schedules, one invented shopping list and one
unusable abstract image. Schedules vary one/two days, column order, font size,
row colors, duration, overlaps, repetitions, names, room values and notes. Blank
fields are explicitly `not_printed` and have no text-line target. Non-plan and
unusable inputs have no appointment targets.

All derivatives of a generated source must retain its `group`. These examples are
training/robustness data, never an independent real-photo holdout. Correct rendered
labels do not establish OCR accuracy, clinical plausibility or patient usability.
The [first v2 experiment](../../experiments/2026-09-26-s17-synthetic-layout.md) records
verification and its limits. Geometry/obstruction augmentation is a separate step.
