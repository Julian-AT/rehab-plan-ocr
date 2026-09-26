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
Complete result-bundle analysis remains pending at this record's creation.

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
