> Historical record: technical findings retained from the archived development sequence. Project dates, build labels and source references have been normalized. This record is not a new test, delivery approval or signing attestation; unaltered evidence and original validity dates are held in the external private archive.

# Python dependency review — 2026-09-26

This review covers the five versioned Python lockfiles used by general tools,
OCR training/export, assistant training, assistant conversion and the isolated
Victoria experiment. These environments are development tools, not Python
components bundled in the iOS app. RustSec and the shipping native libraries have
separate review scopes.

The initial explicit [OSV batch query](https://google.github.io/osv.dev/api/post-v1-querybatch/)
covered 234 registry entries, deduplicated to **153 package/version pairs**.
Four local virtual projects were excluded. Platform branches remain in scope;
a match does not by itself establish use on the current Mac. All five lockfile
hashes stayed unchanged during the query. Raw requests, ordered responses and
complete advisory records are retained privately at
`.local/audits/python-osv-20260926-s21-001`.

The service returned **74 advisory IDs for eight package/version pairs**.
Connected aliases reduce these to **42 advisory groups**; the same group can
affect several package versions. No returned record was withdrawn. This is a
dated observation of the online service, not an atomic database commit or a
blanket exploitability assessment.

| Initial locked package | Consumer | Alias groups for this version | Decision at this review |
|---|---|---:|---|
| Pillow 12.1.1 | General image, fixture and comparison tools | 18 | Updated individually to 12.3.0; verification below. |
| ONNX 1.17.0 | OCR export and graph diagnosis | 9 | Running source-bound study retains its existing environment. Separately qualify a corrected tool version afterward. |
| ONNX 1.18.0 | Isolated Victoria conversion | 8 | Review with that experiment's converter; no public voice-provider promotion. |
| Protobuf 4.25.9 | Assistant conversion | 1 | Existing `<5` constraint needs explicit migration and conversion verification. |
| Setuptools 81.0.0 | Assistant conversion environment | 1 | Qualify the corrected packaging version separately. |
| PyTorch 2.11.0 | Assistant conversion | 1 | Qualify the corrected converter environment against retained weights and outputs. |
| PyTorch 2.8.0 | Isolated Victoria conversion | 8 | Qualify separately from assistant conversion; historical outputs remain immutable. |
| Transformers 4.57.6 | Assistant conversion | 5 | Major-version migration must preserve tokenizer semantics and complete native output parity. |

The reported fixes include model loading, conversion, packaging and image
processing paths. Existing hashes and restricted model-loading settings are
relevant controls; they do not remove a package from the advisory result.
The fixed-version availability query at
`.local/audits/python-upgrade-availability-20260926-s21-001` preserves official PyPI
metadata, Python requirements, wheel hashes and withdrawal flags. A published
version is not automatically an eligible target: the queried Transformers 5.10.0
wheel is marked withdrawn (`yanked`). No migration uses that observation as
approval to install it.

## Completed Pillow update

Only the general tooling dependency changed: **12.1.1 → 12.3.0**. All other
resolved root packages retain their versions. The
[official release notes](https://pillow.readthedocs.io/en/stable/releasenotes/12.3.0.html)
document the relevant image/font parsing and memory-safety corrections.
The new lock retains exact source/wheel hashes; setup downloaded the single
4.6-MiB Mac wheel before the subsequent offline test run. The separate OCR
environment already used Pillow 12.3.0 and was not modified.

Verification under `.local/runs/pillow-upgrade-20260926-s21-001`:

- Complete `make test-tools` passed: **600 cases in 91 groups, including 21
  explicit environment skips**. All 29 detected Pillow consumer files stayed
  unchanged during this dependency-specific check.
- Re-evaluating all 22 retained calendar image pairs with the current exact
  comparator reproduces every previous pixel count, bound and file identity.
  **17 matches and five known failures remain**; no reference, mask or tolerance
  was changed and no new app capture is claimed.
- A fresh OSV query for Pillow 12.3.0 returned no advisory IDs. The response and
  retrieval time are retained; this statement applies only to that query.
- The running OCR protocol's source, input and environment check still passed.

The first offline attempt correctly stopped because the new wheel was not yet
cached. A later intermediate run encountered the independently identified
calendar-4/calendar-5 evaluator mismatch; commit `5b84abc` corrected that identity.
Both failed attempts remain alongside the successful complete run. Concurrent
voice-harness work means this dependency check is not the final frozen joint app
verification. Native builds, simulator/device acceptance and remaining package
migrations still have their own gates.
