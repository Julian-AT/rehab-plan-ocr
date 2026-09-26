> Historical record: technical findings retained from the archived development sequence. Project dates, build labels and source references have been normalized. This record is not a new test, delivery approval or signing attestation; unaltered evidence and original validity dates are held in the external private archive.

# Recognition, reference review and calendar corrections — 2026-09-26

This delivery implements the pre-training stage of the agreed plan. Twenty
original photos were visually transcribed into 188 row occurrences. **None is
user-approved ground truth yet.** Reference polygons and error-cause assignments
remain reviewable proposals. The 200 independently composed synthetic plans are
local artifacts. Training, small/medium accuracy comparison and independent final
acceptance remain after joint reference approval.

## Recognition and review

The portable detector now scores oriented minimum-area text polygons and expands
them using DB's area/perimeter rule. Recognition and field rereading rectify
quadrilaterals instead of enclosing axis-aligned crops. The adapter retains its
connected-component contour approximation and configurable detection thresholds;
it is not claimed to be byte-identical to PaddleOCR's OpenCV postprocessor.
BGR normalization and recognizer normalization were checked against the packaged
model configs; model weights and character lists remain unchanged.

Four clear contrasting page edges permit automatic perspective correction.
Otherwise, robust text/header slopes and bounded local baseline interpolation
align the table. Clock cells anchor appointment blocks; column margins tolerate
perspective drift and cell text keeps its original vertical reading order.
Administrative preambles and meal-service footers do not become appointments.
An unreadable earlier date section remains separate instead of inheriting a later
date. Uncertain column inference, mixed fields, several rooms, isolated degrees,
weak readings and cropped columns require review. Alternative readings from the
same model remain candidates and never count as independent proof.

Room and therapist are visible in ordinary appointment review and the plan list.
Field buttons show source crops with neighboring rows. Users can choose a reading,
correct a value or explicitly confirm a nonprinted room/therapist. Native rules
block approval of affected appointments while complete siblings remain savable.
Photo controls offer rotation, reflection correction and four-corner cropping;
resolution, contrast, sharpness and cropped-text hints give reasons, not percentages.

The native automatic pass has a 60-second total budget including image decoding,
model loading and preparation. It publishes stages and retained initial drafts,
permits cancellation and uses ONNX Runtime termination for an in-flight run.
Import and retry return the last retained draft at the deadline. Uninterruptible
native decoding/session construction may finish unwinding afterward; its cancelled
worker cannot overwrite the returned review. A model-loading failure without a new
draft leaves the previously opened plan intact; a later failure returns the saved
new draft with the failure reason. Desktop CLI timing starts before
model loading; HEIC conversion in the separate batch checker is outside CLI timing.

Run schema 3 and extraction version 7 preserve old edits and calendar/ICS bindings,
invalidate obsolete extraction caches, and retire legacy room/therapist approval.
Changed geometry does not inherit a geometrically reviewed status just because
its field string remains identical.

The subsequent column-warning fix selects a coherent table-header band so a
patient-header `Zimmer` cannot become the room column. Assignment tolerance is
separate from crop boundaries derived from text spacing; DB box padding and a
combined start/end reading no longer imply a mixed field. A surviving name or
degree line adjusts the local room/name crop boundary under perspective drift.
Re-extracting the 20 retained OCR traces preserved all 188 date/time/title tuples.
On the reported ten-row scan, cross-column warnings fell from 22 to the one
genuinely merged room/name area. Blank cells remain subject to explicit source
confirmation. These are regression diagnostics, not approved accuracy metrics.

The debug table now opens the normal **Am Foto prüfen** field editor. Opening
retained version-5/6 scans refreshes their column mapping when identities remain
unambiguous, preserves manual values and calendar bindings, and expires old
geometry approvals and reread candidates. Structural changes require explicit
reprocessing. This path makes no calendar writes.

The corrected complete CPU run of the reported image took 4.622 seconds and
retained ten appointments. Both separate field crops produced complete room/name
candidates without shifting the room suffix into the therapist. The original
merged reading remains flagged until explicitly resolved. Diagnostics are retained
under `artifacts/private/column-warning-fix/`; the debug app runs this correction,
while the earlier standalone release bundle requires rebuilding to include it.

## Debug performance

The running macOS debug app previously used unoptimized image codecs and CPU
pre/postprocessing. One retained 24 MP import recorded 40.704 seconds in the app.
A controlled scan of the same original with extraction version 7 took 34.629
seconds in the original debug CLI. Package-specific Cargo dev overrides now
optimize the OCR core, image processing/codecs and SHA-256. Debug symbols,
assertions, model checksums, models and recognition thresholds remain enabled
and unchanged.

Validated upright PNG input is reused as the original artifact. An unchanged RGB
page copies that artifact rather than encoding it again. Initial rereads borrow
the already decoded original pixels; retries still load the retained original.
Rotated, reflected or perspective-corrected pages keep their own image and
coordinate transform. The quality thumbnail no longer clones the full photograph,
and field-specific rereads no longer parse the entire table for unused candidates.
Native PNG/JPEG imports also avoid an input-buffer clone and redundant source writes.

| Same six-row photo, fresh model session | Before | After |
| --- | ---: | ---: |
| Model verification/loading | 1.064 s | 0.117 s |
| Decode and original artifact | 8.019 s | 0.181 s |
| Page preparation/artifact | 7.888 s | 0.030 s |
| Quality checks | 1.155 s | 0.029 s |
| Complete pipeline including 14 rereads | 34.629 s | 2.830 s |

This is a 12.2× shared-pipeline speedup on the local Mac. A second ten-row photo
completed in 4.573 seconds including 20 rereads. These are local debug CLI timings,
including model loading and image preparation, not camera/HEIC or GUI end-to-end
measurements and not a repeated-scan p95. The macOS debug app uses the same optimized
core. Previously loaded model sessions remain reusable in the app.

Both final runs match their prior version-7 results after excluding generated
identities, timestamps and source path/encoding differences: observations, scores,
polygons, appointments, warnings and alternative readings are unchanged. All four
original/page artifact pairs have identical decoded RGB pixels. No processing
version bump is needed for this equivalent-output optimization. The 60-second
deadline, cancellation, approval gates and calendar protections remain in place.

Validation: 68 Rust tests passed, including pixel-preserving artifacts across
PNG/JPEG, RGB/RGBA, quarter turns and reflections, unchanged quality-thumbnail
pixels, and the existing perspective, cancellation and review tests. Core Clippy
with warnings denied passed. Benchmark traces and comparisons stay under ignored
`artifacts/private/speed-fix/`. This does not establish accuracy against approved
references or change the pending training/acceptance work.

## HEIC/HEIF import on macOS

The normal importer, development workbench and saved-import photo association
accept `.heic`/`.heif` extensions as well as MIME types. This permits files whose
browser MIME type is empty or generic. Previously the native fallback called the
iOS-only photo plugin on macOS and failed.

The macOS shared core now decodes HEIC/HEIF directly with ImageIO, selecting the
primary photograph from multi-image containers and checking the 50 MP limit before
allocating decoded pixels. It requests the full original dimensions rather than
an embedded preview and applies the source orientation once. The orientation-aware
ImageIO options follow Apple's [image source documentation](https://developer.apple.com/library/archive/documentation/GraphicsImaging/Conceptual/ImageIOGuide/imageio_source/ikpg_source.html).
An 8-bit sRGB buffer enters the existing pipeline without an intermediate PNG
encode/decode. Original HEIC bytes, filename and SHA-256 are retained for reprocessing,
duplicate checks and saved-import review; source previews remain ordinary PNGs.
The 40 MB upload limit and 60-second automatic-pass budget still apply. No upload
service, conversion executable or additional user installation is required.

The same native decoder is available in the macOS CLI. iOS retains its existing
UIKit decoder; non-Apple desktop builds continue to support JPEG/PNG.

Validation: 73 Rust tests passed, covering all eight orientations, embedded-preview
avoidance, a non-first primary image, corrupt HEIC, size limits, original retention
and PNG/JPEG regressions. Two browser tests (Chromium and WebKit) transfer an invented
uppercase HEIC file without a MIME type through the import bridge and open review;
their native bridge is mocked, with actual decoding tested in Rust separately.
ESLint, TypeScript/static build and native/core Clippy with warnings denied passed.
A retained 24 MP clinic HEIC completed a full local CLI scan in 5.401 seconds with
ten appointments; upright dimensions, original bytes and source hash were checked.
This measurement ran alongside frontend build work and is not a latency benchmark.
Evidence is under ignored `artifacts/private/heic-import/`; committed fixtures in
`ml/evaluation/fixtures/heic/` contain only invented colored quadrants and a generator.

## Calendar corrections

**Gespeicherte Termine prüfen** rereads retained originals, preserving reviewed
manual values and uniquely matched calendar identities. If an original expired or
was deleted, the user can explicitly associate another photo with that import.
This local association performs no calendar write.

The subsequent calendar sheet displays old and proposed title, time, room and
therapist/notes values. Ambiguous identities can be explicitly associated with a
previous imported event. Existing three-way reconciliation protects manual edits;
partial selection never implies deletion. Confirmation is still required for
actual writes, and live values are checked again immediately beforehand.
Recurring events and detached exceptions are protected both in proposal generation
and in Swift immediately before a write. See Apple's
[detached-event property](https://developer.apple.com/documentation/eventkit/ekevent/isdetached).
No real calendar events were changed during implementation.

## Validation boundaries

Tests cover skewed rows, header drift, multi-line names, invalid/missing date
sections, footer exclusion, polygon round trips, reflection, uncertain populated
fields, approval expiry, partial saves, retained IDs and recurrence protection.
Python tests cover transitive grouping, deterministic variants, masking,
obscured/cropped labels, cache limits, cross-partition isolation and synthetic
reproducibility. Browser checks cover normal review, source crops and invalidation
on desktop Chromium and mobile WebKit. Reference hashes for all 20 draft files
were checked against the native serializer.

Validation on 2026-09-26: 66 Rust tests, 17 Python tests, 10 frontend unit tests
and 22 browser tests passed. Two browser cases exercise reference persistence and
approval invalidation through an invented in-memory native bridge; native source
and hash validation are checked separately. ESLint, TypeScript, core Clippy with warnings denied, Rust formatting and
the macOS application build passed. An independent iCalendar parser verified
approval blocking, seven invented events, repeated-event multiplicity, stable
UIDs, UTC values and UTF-8 escaping/folding. All 200 synthetic image/label pairs
matched their recorded hashes. The desktop bundle is available at
`target/release/bundle/macos/Reha Calendar Lab.app`.

The ignored diagnostic directories retain actual model runs and manifests. They
are never labeled verified accuracy. Counts matching a transcription do not prove
correct date/time, room or therapist assignment. Geometric suggestions still need
review, especially partial columns and multi-day headings.

The latest local CPU diagnostic batch is
`artifacts/private/polygon-v5-delivery/`: 20 completed photos, no failed runs,
188 proposals, median 4.273 seconds and maximum 6.676 seconds including cold model
loading but excluding prior HEIC conversion. One title, three dates and five end
times/durations remain missing. Additional populated fields also require review;
these counts are not a measure of correctness. All 20 source-linked reference
files remain unapproved and there is no measured accuracy claim.

No iPhone installation or signing was performed. Runtime EventKit recurrence
behavior, camera acquisition and physical-device timing still need device
acceptance. Existing simulator/device reports describe earlier deliveries and do
not validate this change. The new workflow and dataset commands are documented in
[dataset.md](dataset.md).
