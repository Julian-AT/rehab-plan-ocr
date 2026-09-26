> Historical record: technical findings retained from the archived development sequence. Project dates, build labels and source references have been normalized. This record is not a new test, delivery approval or signing attestation; unaltered evidence and original validity dates are held in the external private archive.

# Augmentation geometry and visibility — 2026-09-26

Augmentation v3 expands the 24 recipes to 40 and shares the same transformations
and obstruction rectangles between rendered images and labels. The regression
first reproduced a cropped blank field retaining `not_printed`. Its exported state
is now `cropped`, with no full value target. Further regressions cover compound
geometry/inverse mapping, privacy-mask intersections, obstructions, deterministic
noise, tiny text, source-size mismatch and degenerate clipped detections.

Nine reference-export tests and nine geometry tests pass. The verification CLI
rendered all 40 recipes on two invented multi-day schedules twice: all 80 pixel,
geometry, label and JPEG comparisons matched. Across these correlated variants,
382 lines lost their complete target and 5,538 retained one. These counts are not
independent examples or an accuracy measurement. A small/noisy output was visually
inspected; no general legibility certification follows from the geometry heuristic.

The source is `.local/datasets/synthetic-v2-002`, with manifest SHA-256
`5c15c9b7cd3ba79c1da3fa1b29111b4b1864978962e94ab840926b589be9cea4`.
The report is `.local/runs/augmentation-v3-002/verification.json`, SHA-256
`34f5e697892bb6f4f6d014675f672f61bc87da2569175cfea1ab600183edb1fd`.
It records generator identity
`95c9e71f38d5af19238df163311120213c2ef086980b01e8d8c237683000f32b`
and verifier identity
`0b6c7b60608ef5290df49c70c6a5802416a0c0652d7bffc117911780461af3f0`.
The locked environment uses Python 3.12.13 and Pillow 12.1.1.

No real reference was approved, no related-source group was frozen and no model
was trained or promoted in this experiment. Real development data still require
human approval and grouping before their augmentation/export gates can pass.
