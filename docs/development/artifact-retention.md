# Local storage and retention

`config/storage/retention.json` is the authoritative policy. It protects datasets,
models, runs, releases, recovery material, upstream checkouts and retained build
products. Nothing is deleted based on age. Source cleanup does not authorize
removing original documents, recordings, model weights or backups.

`make check-storage PEAK_GIB=4` requires the 20 GiB reserve plus that peak budget.
Builds and tests enforce their own budgets. Report insufficient capacity instead
of lowering the guard. Logical file sizes do not measure reclaimable APFS space.

For explicitly listed rebuildable compiler caches, create and review a new plan:

```sh
make inventory-artifacts CLEANUP_MANIFEST=.local/maintenance/cleanup-NEW.json
make clean-artifacts CLEANUP_MANIFEST=.local/maintenance/cleanup-NEW.json
```

The tools bind the policy, sources and file identities, require a quiet workspace,
check open files, symlink/worktree consumers and binary references, and retain
immutable plans and restart receipts. Unknown artifacts remain protected. The
pinned LLVM reader is restored explicitly with `make artifact-reader-setup`.

Reusable maintenance commands retain their original arguments:

- `inventory-model-objects` / `coalesce-model-objects` use `MODEL_OBJECT_MANIFEST`.
- `inventory-archive-objects` uses `ARCHIVE_REVIEW` and `ARCHIVE_OBJECT_MANIFEST`;
  `coalesce-archive-objects` applies that exact plan with APFS clone checks.
- `inventory-checkpoints RUN=<training-run>` inventories retained checkpoints;
  `plan-checkpoints` and `clean-checkpoints` require `CHECKPOINT_MANIFEST`.

These operations retain content/provenance checks and fail closed. Git-dependent
maintenance guards require a checkout. Completed one-off smoke-export maintenance
and its historical execution diary are recoverable through [Git](recovery.md).
