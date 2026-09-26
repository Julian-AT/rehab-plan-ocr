> Historical record: technical findings retained from the archived development sequence. Project dates, build labels and source references have been normalized. This record is not a new test, delivery approval or signing attestation; unaltered evidence and original validity dates are held in the external private archive.

# Native recognition input fixtures

`reha recognition-fixture CROP_PNG NEW_OUTPUT_DIRECTORY` uses the same crop
normalization as the Rust OCR engine. It does not load a model and works without
the `onnx` feature. Build/run it with the pinned workspace toolchain using
`make recognition-fixture CROP=path/to/crop.png FIXTURE_OUTPUT=.local/new-fixture`.
Input is an already rectified PNG text crop; this command does not detect text or
perform perspective rectification.

The shared core helper appends directly to the caller's batch. It resizes with
`image::imageops::FilterType::Triangle` to height 48 and width
`clamp(ceil(48 * width / height), 8, 3200)`. The tensor pads on the right with
normalized zero to an 8-pixel multiple of `max(320, resized_width)`. Channels are
BGR, layout NCHW, with the existing Rust `f32` expression
`(u8 as f32 / 255. - 0.5) / 0.5`. Crops above the 3200 width cap retain the app's
existing compression behavior. Equal padded widths are required within a batch.

The output directory must not exist. It receives `tensor.f32le` (little-endian
float32 bytes) and `manifest.json`, written last after the tensor. Existing paths
are never overwritten. A write failure can leave an incomplete directory; keep
that evidence or use a new destination. Consumers must require the complete
manifest, verify the tensor hash and byte count, and use its exact shape.

The manifest records input/tensor SHA-256, dimensions, normalization, producer
binary SHA-256, compiled-in source hashes, Cargo profile/target/features and the
compiler's verbose identity. Source identity belongs to the compiled host CLI;
it is not inferred from a later checkout. The corresponding source snapshot,
lockfile and binary must remain available to reproduce a fixture. Fixture IO and
producer identity are excluded from iOS; the app uses only the pure shared helper.

Inputs are regular PNG files limited to 16 MiB encoded, 16 million pixels and
32,768 pixels on either axis, with a 64 MiB decoder allocation budget. Validation
happens before output creation. Fixtures are developer artifacts and belong under
`.local`; the command does not approve references or qualify a model.

Historical OCR studies using OpenCV linear interpolation at fixed width 320 keep
that identity. These native Triangle fixtures must not be relabelled as legacy
inputs, nor recreated with a second Python resize implementation. A prospective
comparison must bind its own source/checkpoint/input identities and retain the
existing critical-field and export gates.
