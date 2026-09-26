# Repository history and private recovery

The project is `Julian-AT/rehab-plan-ocr`. Its rewritten development sequence
starts on September 26, 2026 at 14:08 Europe/Vienna. The original 525 mainline
commits and six additional branch commits retain their authors, parent
relationships and substantive changes. Migration follow-up commits appear after
that sequence. Thirteen branches are retained.

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
original secondary worktree, original workspace data, GitHub records and the two
downloaded Actions artifacts. `recovery.json` identifies the archived workspace
and recovery maps. Original timestamps and original-to-rewritten mappings stay
exclusively in that archive.

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
