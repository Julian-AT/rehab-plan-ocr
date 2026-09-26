# Repository history and private recovery

The project is `Julian-AT/rehab-plan-ocr`. Its rewritten development sequence
starts on September 26, 2026 at 14:08 Europe/Vienna. The original 525 mainline
commits and six additional branch commits retain their authors, parent
relationships and substantive changes. Migration follow-up commits appear after
that sequence. `main` is the sole active branch; the twelve completed side
branches are preserved in the external archive.

Five former side branches contained six commits outside the mainline ancestry.
Each has a patch-identical counterpart already on the original mainline, verified
with stable Git patch IDs and mapped into the rewritten mainline. A subsequent
history-only merge incorporated these branch histories without changing the
verified main tree. Every original rewritten commit remains reachable from
`main`, and the original commits retain their parent relationships. No additional
implementation is missing. The original main working tree was clean when checked.

Project chronology and repository references were normalized throughout the
historical trees, including deleted files. Date-bearing paths use stable sequence
suffixes. Calendar fixtures, deterministic seeds and upstream dependency/license
dates remain source data. App identifiers, App Groups, persisted preference keys,
calendar destinations and the `reha-calendar` URL scheme remain compatible with
the installed app.

Historical reports describe earlier technical findings. Their normalized dates
are not new measurements, device approvals, signature verification or certificate
validity. Original attestations, signed builds, device backups, Git metadata,
historical checkouts and GitHub run evidence belong to the external private
archive. Historical GitHub run links use `archive:github/run-<id>` to identify those
records; they do not refer to runs in the new repository.

## Recovery

The archive is at `~/Documents/Project Archives/rehab-plan-ocr/2026-09-26/`.
It contains a verified standalone Git bundle, the original Git metadata, the
original secondary worktree, GitHub records and the two downloaded Actions
artifacts. `recovery.json` identifies the original workspace data and recovery
maps; it records the old workspace location until its final move into the
archive. Original timestamps and original-to-rewritten mappings stay exclusively
in that archive.

`branch-cleanup/rewritten-before-cleanup.bundle` preserves all thirteen rewritten
branch tips before cleanup. It was restored into a separate bare repository and
passed Git integrity checks before the completed branches were removed.

Locate historical private evidence using its rewritten workspace path:

```sh
python3 tooling/dev/history_archive.py .local/runs/<record>/report.json
```

Pass `--sha256 <digest>` to verify the archived bytes before use. The command is
read-only and refuses ambiguous paths or symlinks escaping the archived workspace.
It does not copy original attestations into the active repository. Retired
versioned assets can be read directly from their rewritten revision with
`git show <revision>:<path>` and checked against
`docs/releases/history/retired-assets.json`.

Active data and model payloads were copied with independent, SHA-256-verified
APFS clones. Project metadata and dependent model-card hashes were regenerated;
model weights remain byte-identical. Python environments were recreated from the
committed locks. Build caches are generated at the new absolute workspace path.

## Verification record

The archive's `migration/` directory contains the complete inventory, individual
commit-message review, structural history checks, media metadata inspection,
clone hash comparisons, metadata updates and command logs. Fresh verification
results are recorded separately from historical reports. Hosted Actions remain
subject to the account billing restriction; local verification and remote clone
integrity are independent checks. This migration does not authorize or perform
device installation.

Local migration checks passed: historical graph/tree verification, Git integrity,
documentation checks, `make lint`, `make test`, `make test-ci-monitor`, native asset
verification, runtime inventory verification and the simulator build. The six
selected simulator tests passed for calendar links and error dismissal, persisted
calendar presentation, conversation without asset setup, and persisted/cancellable
navigation. The original XCTest result bundle was preserved and independently
checked for execution of every requested test.

The full simulator suite was not run: its declared 36-GiB free-space requirement
exceeded available storage. The selected run kept at least 21 GiB free, above the
20-GiB reserve. An earlier attempt was stopped by the reserve monitor. The second
run completed its tests but exposed a metadata-copy defect in result verification;
that defect was fixed, covered by the 16 APFS clone tests, and the retained result
then verified successfully. The nine result-verifier tests also passed. These
checks do not claim full simulator-suite or hosted Actions qualification.

Hosted verification is manual-only while account billing blocks runner startup.
The workflow retains `workflow_dispatch` with its full/portable inputs; push and
pull-request triggers have been removed. Manual execution still requires resolving
the account billing restriction.
