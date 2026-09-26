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
and the linked llama.cpp worktree. They must remain while saved references still use
the old names. Active dataset, model restoration, evaluation and app-resource paths
now use `.local/` directly. New phonemizer caches live in `.local/builds/phonemizer`;
the old cache contents remain preserved with the migrated collection. Moving other
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

After switching active paths, offline phonemizer conversion for host/simulator/device,
all 15 bundled voice-asset hashes, native model/runtime/notice verification, 54 Python
tests, the pinned VAD speech probe and an offline simulator build passed. The linked
llama.cpp checkout retained its revision and clean status; all eight pinned Qwen base
files passed verification. Dataset readiness remains 20 originals and zero approvals.

## Retired root-level workspace remnants — 2026-09-26

The old Tauri-generated API/workspaces, Xcode user state, Python bytecode, test
result marker, TypeScript build metadata, empty former source directories and two
obsolete design references now live in `.local/runs/retired-root-20260926-s18-001/contents`.
This separate relocation preserves all 55 regular files (2,003,942 bytes), their
paths, modes and SHA-256 values. Inventory, source verification, same-volume renames
and destination verification completed before the root paths were retired.
Receipt SHA-256: `f089f0f2199dfc2cdc117b3935c52924c8a1390e97f4e770c1ec6fb41f57e366`.
No active training, model, dataset or app-product path was relocated.

The sole tracked obsolete image, `image.png`, has no current runtime/build consumer.
It is a former travel-app design reference, not the selected calendar baseline.
Its 1,310,633 bytes have SHA-256
`bfb1b67736722879781af6a2df95a7117b86a8f721496f00e6f7078309168acb` and remain
recoverable from Git revision `9c8d31ca627b2bfd86e0bb55bedb515c1792fcea` as well as
the verified local copy. Historical documentation identifies that old reference.
All 22 selected calendar baseline PNGs remain unchanged. The required `artifacts`,
`data/private` and `models/private` compatibility links still resolve normally.

Separately, 1,890 completed native Rust dependency intermediates were inventoried
and removed to make room for retained training/CI evidence. The six top-level
native libraries were hashed before and after and remain identical; app products,
content-addressed FFI artifacts and every checkpoint remain intact. That cleanup
receipt is `.local/runs/completed-native-rust-intermediates-cleanup-20260926-s18-001.json`,
SHA-256 `66672a098b19d71856d99a19cc623780bfb6c47dc11e9d1a2b9555876e928f54`.
