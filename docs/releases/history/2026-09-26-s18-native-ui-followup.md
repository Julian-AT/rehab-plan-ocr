> Historical record: technical findings retained from the archived development sequence. Project dates, build labels and source references have been normalized. This record is not a new test, delivery approval or signing attestation; unaltered evidence and original validity dates are held in the external private archive.

# Native UI follow-up — September 26, 2026

Historical record. These results do not qualify the complete current candidate.
No physical device was updated.

## Hosted results

[Run 35295159442](archive:github/run-35295159442)
at `0597aab4c9858ddbe87fb018ff606fdd4d3f08fb` finishes with **62 passing,
four failing and zero skipped UI tests**, confirmed by the complete result bundle.
Its actual simulator is iPhone 17/iOS **26.5 (23F77)**; the selected Xcode 26.4.1
does not identify the runtime selected by `simctl create`.

- The address-persistence recording reaches the addressed date question, with
  the response row above the scrolled form's visible area.
- The neural-preview expectation misses playback. Retained element descriptions
  say `preparing` while their fresh query chains say `playing`; the simulator's
  audio log records the engine running from 02:26:08.429728 to 02:26:21.586121 UTC.
  This evidence does not support attributing that failure to the separate local
  CoreAudio abort. Rust synthesis already uses `spawn_blocking`.
- The compact-action test immediately reads `playing` after its stop tap. Its
  process is subsequently terminated by test teardown, not a recorded SIGABRT.
- The share test checks for Preview's Share button before it becomes accessible.
  The recording shows the bottom toolbar, while the earlier accessibility tree
  lacks Share. Preview's overflow is an image-editing menu, not the share sheet.

The source bundle is retained at
`.local/runs/hosted-ci-20260926-s18-006/evidence-002/contents/ci-ui.xcresult`.
The corrected collector reads a disposable clone, since `xcresulttool` can create
an index even during reads. The original files remain unchanged. Focused receipt
`triage-002/receipt.json` SHA-256:
`a0c9f3338815aad2a319b078b9678d27d7637689d3157e2918ea1e38eca87931`.
All four failed-case videos and filtered audio logs are retained separately.
The 562 exported diagnostic files were hash-verified before packing into
`diagnostics.tar.gz` (SHA-256
`9261e8987b87cedaa7e51f7ed1035a927d41a3163c0755aec7539d6cb044acc3`).

[Run 35297619578](archive:github/run-35297619578)
at `a303bc28a36da68945e9ab0c957b64fc2e2e30c4` also fails. Its console records
65 passes and one failure, in tracing's system-picker cancellation: XCTest
cannot compute a hit point for “Abbrechen” during the presentation transition.
The four cases above pass in that run without these proposed test corrections.
The downloaded result confirms **65 passes, one failure and zero skips** on
iOS 26.5/23F77. Its 3,573 files/1,338,436,304 bytes are retained under
`.local/runs/hosted-ci-20260926-s18-007/evidence/contents`; the receipt SHA-256 is
`8dc4e0357c8596e1df0f60f8e56fcddd94004ac65082aa7c12aebcb79ec495a2`.
Focused extraction preserves the source bundle; its receipt SHA-256 is
`cc6fefe1499711f57452726f1548d1d492f0097a80291c8f23cc93ec0c20b5a8`.

The failing description binds to `PUPickerUnavailableView`'s temporary cancel
button with frame `{{inf, inf}, {0, 0}}`, while the fresh hierarchy already exposes
the real `Cancel` button under the `Fotos` navigation bar with a 36 × 36 frame.
Photo-picker tests now wait for that specific loaded control, so the temporary
same-label element cannot satisfy their readiness check.

Four focused local cases pass with **zero failures and zero skips**: large-text
controls (49.696 s), light/dark tracing and diagnostics (58.131 s), recognition
evidence with unchanged archive (97.958 s), and actual public-image photo import
(15.098 s). The real iOS 26.4/23E244 simulator runtime was checked by the new
preflight. Results, source hashes and summary are retained under
`.local/runs/ci7-picker-readiness-20260926-s18-001`. The owned simulator was shut down
after testing; its data remains intact. These focused results do not qualify the
pending complete hosted candidate or minimum-iOS behavior.

## Verified share-test correction

The share test now waits for an existing, hittable Share button and excludes
Preview's `OverflowBarButtonItem` when locating the share sheet's “More” action.
The final source passes the actual simulator test in 31.474 seconds:
**one pass, zero failures, zero skips**, with the real extension accepting the
public synthetic plan. Evidence and source hash are retained in
`.local/runs/ci6-share-readiness-20260926-s18-005/verification.json`.

An initial local attempt used a reused OCR simulator lacking the archive fixture;
its overall failure remains recorded. A subsequent image-overflow workaround
failed and was removed. Neither attempt is counted as a passing test. The owned
simulator's original store was preserved and hash-verified before seeding the
complete public UI fixtures. Physical data and the visual baseline were unchanged.

## Voice-query candidates

The address test brings its response row back into view before checking the
addressed question. Playback tests now match the expected phase in a current
accessibility query, instead of polling the value on the retained button. The
playing deadlines remain 45/30 seconds. Stop/background checks wait for the
updated idle query; these UI synchronization checks do not measure the separate
250 ms interruption target.

All three changed test sources compile in an actual simulator test build, with
source hashes and the successful build log retained in
`.local/runs/ui-query-readiness-20260926-s18-001/verification.json`.
Their behavioral qualification remains pending the hosted suite. Local address
reproduction is blocked before the changed assertion by the independently
reproduced CoreAudio RPC abort; it is not recorded as a pass. Production audio
code, pause thresholds, visuals and test assertions about user behavior remain
unchanged.

## Candidate blocked before runner startup

[Run 35306312405](archive:github/run-35306312405)
was dispatched in full scope at
`404f68eb1baac694c7bb9cfab1d11f7bd4c1d815` on
`codex/offline-plan-ui-readiness-20260926-s18`. Both jobs fail with **zero executed
steps**, without a runner or downloadable job log. GitHub's check annotations
identify failed recent account payments or a spending limit requiring an increase.
This is an account-level execution block, not a test result for the candidate.

`ci_monitor.cjs annotations` now reads the exact run attempt's job/check metadata
and every annotation page. Repository, commit, attempt, check identity and counts
are verified; the command cannot follow a different repository's check URL. Sixteen
monitor regressions pass, including multi-page and identity-mismatch cases. Actual
annotations are retained under `.local/runs/hosted-ci-20260926-s18-008/annotations.json`.
The user was asked to resolve the GitHub billing/settings prerequisite. No billing
setting, payment or spending limit was changed, and no identical retry was started.

After completing the local tests, the owned synthetic-only simulator was retired.
All containers, documents, media, preferences, TCC state and simulator logs were
copied and hash-checked first: 1,935 entries and 577,159,345 bytes. Backup receipt
`.local/runs/disposable-simulator-retirement-20260926-s18-002/receipt.json` has SHA-256
`daefe2bfa11087fa56150224d21c80b532b9edf94120b6545eba7d2d0f16dd87`.
Original data, model artifacts, result bundles, other simulators and physical
devices remain preserved. This removes regenerated simulator system/cache storage,
not any acceptance requirement.
