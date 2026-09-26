> Historical record: technical findings retained from the archived development sequence. Project dates, build labels and source references have been normalized. This record is not a new test, delivery approval or signing attestation; unaltered evidence and original validity dates are held in the external private archive.

# Reproducing the retained calendar appearance — 2026-09-26

The 22 original Zitrus & Olive PNGs remain byte-identical. Their catalog identity
is `81f4ba162819932a751692a1b6bd0fb4ecce3008094ffeffcacd8a839cbf2b37`.
Debug simulator fixtures now accept a fixed clock. Calendar selection, timeline
and EventKit fixture creation share `2026-09-26T12:08:00Z`, recreating the original
September 26, 2026/15 views. Ordinary launches and physical builds use the system clock.

| Run | UI tests | Exact screenshots |
|---|---|---|
| `.local/runs/visual-baseline-20260926-s18-001` | 3/3 passed | 15/22 |
| `.local/runs/visual-baseline-20260926-s18-002` | 3/3 passed | 13/22 |

Run 001 comparison SHA:
`b7d7a17daf27ef64a4d749655702e230197b59de49c00c0aeb62ad0501c7869b`.
Run 002 capture/comparison SHA:
`7f1a25baf907936bfd52be4dff4f964709a7e3ebd960caf14e81547a500303f0`.
Run 002 regenerated comparison SHA:
`51a54f820ad1cb1719525b6508480eba6e9cf34345d5444a9774a776fa1003ab`.
The offline side-by-side page is
`.local/runs/visual-baseline-20260926-s18-002/review/review.html`.

Both runs use the same app/test code on iPhone 17 / iOS 26.4 simulator build
23E244, Xcode 26.4 and macOS 26.5.2. The source revision starts at `c13ebeb`;
recorded source hashes describe the additional fixture/test implementation.
Run 002's initial broad snapshot includes a README edited during execution;
`sources_unchanged` is correctly false. That was the sole changed snapshot file.
No runtime/test source changed. Future snapshot collection excludes Markdown,
retaining source, configuration, resources, native inputs and dependency identities.

Cards, legend, ordinary lists and their lower scroll positions match exactly in
both appearances. Initial large-text views and several category captures also
match. Later large-text captures differ between repeated gestures with identical
code. In inspected dark crops, a one-pixel vertical alignment makes the sampled
text region identical; light scroll differences are larger. This diagnosis does
not change any comparison result or establish full-image equivalence.

The dark completed-day image differs in 1,559 pixels below the status bar, with a
maximum RGB channel delta of four around system controls. Its central content is
unchanged in visual inspection. The light counterpart is exact in the first run
and differs in 87 pixels in the repeat. No app-pixel tolerance has been added.

The comparison requires exactly one screenshot per reference, passing UI tests,
matching dimensions and exact pixels below the first 160 system pixels. Missing,
duplicate or changed captures fail, as verified by three isolated regressions.
The baseline is never overwritten. The final local HTML resolves all 44 images
without network resources. All 134 tool tests and repository lint pass.

Still open: deterministic large-row viewport positions and stable system rendering,
full-app visual coverage, the separate CoreAudio/voice gate, user preview/listening
approval and physical verification. Neither the test counts nor familiar-looking
screens authorize an iPhone update or establish complete visual qualification.

## Preserving result evidence during later comparisons

The comparator and focused native failure collector now share a verified
disposable-copy reader. `xcresulttool` may write a SQLite index even for a read
command; neither consumer exposes the retained original to that command. Every
source file is hashed before copying, the copy is verified before use, and the
original is checked again even if extraction fails. Nested output is rejected.

A real re-evaluation of run 002 preserves all 130 source files (84,994,477 bytes)
and reproduces the same **13/22** pixel matches with three passed UI tests. The
comparison still exits with failure because nine images differ. It adds no new
capture or visual acceptance. Evidence remains under
`.local/runs/visual-evidence-preservation-20260926-s18-001`: report SHA-256
`a2638126bf4412eaa2ccc156f76c8b3249698a39ed359338659a5777e759c691`,
source-result receipt SHA-256
`425c8fafce80e1297a1d04e32d6572812c375e9a8f6078df0bfece178513df18`.

Provided historical bundles now identify the current revision as the evaluator
revision and leave the tested app revision unknown; today's checkout is not
silently attributed to an older capture. Fresh captures retain their app-source
snapshot, now including Rust, build tooling, runtime manifests and toolchain/test
configuration. Six visual-tool tests and three native-collector tests cover
pixel failures, index creation, interrupted extraction, original-file changes,
nested destinations and historical-source attribution.
