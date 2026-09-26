> Historical record: technical findings retained from the archived development sequence. Project dates, build labels and source references have been normalized. This record is not a new test, delivery approval or signing attestation; unaltered evidence and original validity dates are held in the external private archive.

# Private working storage migration

`tooling/dev/migrate-private.py` relocates the existing project-managed collections:

| Old location | Canonical storage |
|---|---|
| `data/private` | `.local/datasets/private` |
| `models/private` | `.local/models/runtime` |
| `artifacts` | `.local/runs/legacy` |

This is for an existing checkout with those collections. Do not run it during
training, annotation, model restoration or artifact generation.

```sh
make inventory-private
make migrate-private
```

The first command inventories every regular file with SHA-256 and records modes,
directories and symlink targets. Its manifest stays in ignored `.local/migrations`
with owner-only permissions. It refuses existing destinations and changing files.
Use `MIGRATION=.local/migrations/another-name.json` to retain an earlier inventory.

The second command verifies the inventory again, atomically renames each directory
on the same volume, creates a compatibility symlink and verifies all contents at
the destination. No second full copy of weights/backups is required. External
originals are never traversed or moved. Relative symlinks escaping their collection
require an explicit relocation mapping; absolute external links retain their targets.

The progress journal and filesystem state support restart after interruption.
Existing collections are never merged or overwritten. A post-move mismatch restores
the original directory, preserving the unexpected contents for investigation.
Completed journal entries are not rolled back when later normal work adds or edits
files; reruns check their locations and preserve subsequent work.

Compatibility links intentionally preserve historical absolute/relative references
and the linked llama.cpp worktree. They must remain until consumers and saved
references have been migrated and verified. Changing active default paths, moving
toolchains/build caches and removing obsolete previews are separate follow-up work.
Private inventories, backups, sources and model weights remain excluded from Git.

## Verified relocation — 2026-09-26

All three collections were moved and verified against inventory SHA-256
`05023991f697fc7e67ede09c211dd26cbad1e93c45171eb5ee5f28c98335b75d`.
The ignored progress journal records each collection as verified.

| Collection | Regular files | Bytes | Internal symlinks |
|---|---:|---:|---:|
| Dataset | 488 | 623,104,630 | 0 |
| Model/runtime working files | 12,905 | 7,359,138,423 | 4 |
| Previous artifacts, including backups | 25,177 | 38,677,402,500 | 0 |

All 38,570 regular files retained their hashes. The four internal links retained
their targets. Legacy compatibility links and `.local/` are explicitly ignored;
no private file lists or contents are included in this report.
