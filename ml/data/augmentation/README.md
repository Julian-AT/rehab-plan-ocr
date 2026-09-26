# Geometry-aware augmentation

`variants.py` owns the pixel transformations and the corresponding geometry and
visibility rules. The reference exporter retains its version 2 approval schema;
augmentation is independently versioned at 3. The original 24 recipes remain and
16 add shear, tint, noise, glare, cropped margins/headings, row colors and combined
distortions. Transforms compose in turn/mirror/angle/perspective/shear/scale/crop order.

Projected polygons retain inverse mapping to the source. Visible polygons are
clipped to the output; zero-area detections are omitted. Privacy masking, cropping
and obstructions remove complete text targets. Blank fields are assessed by their
own polygons even when they have no text lines. Original field states remain in
`source_state`. A projected text edge below six pixels is conservatively marked
illegible; this heuristic does not certify human readability under other distortions.

Real exports still require human-approved fields/crops and frozen source groups.
Generator, environment, source, reference and recipe identities prevent reuse of
stale artifacts. Mirrored text is excluded from recognition training. Training
packages are not application dependencies.

To verify all recipes without approving real patient data:

```sh
make generate-synthetic DATASET=.local/datasets/synthetic-example
make verify-augmentation SOURCE_DATASET=.local/datasets/synthetic-example \
  RUN=.local/runs/augmentation-example
make test-tools
```

The verifier checks the synthetic source pixels against their labels, renders each
recipe twice and compares pixels, labels, transforms and encoded JPEG bytes. Its
report is a reproducibility check, not an approved training export or model score.
`SYNTHETIC_SOURCES` defaults to two; use a new output directory for each run.
The source font must match the synthetic manifest (`FONT` can select it).
