> Historical record: technical findings retained from the archived development sequence. Project dates, build labels and source references have been normalized. This record is not a new test, delivery approval or signing attestation; unaltered evidence and original validity dates are held in the external private archive.

# Historical build evidence

These reports retain decisions, test results and device backup/update evidence from
their original dates. They are not current requirements or installation instructions.
In particular, the old React/Tauri workbench and discarded visual designs are retired.
Use the [current ledger](../../development/implementation-plan.md),
[architecture](../../architecture/overview.md) and
[device update procedure](../ios-installation.md).

The sole current visual reference is [Zitrus & Olive](../../product/visual-baseline/README.md).
Its images and contrast evidence are retained unchanged. App tests keep their own
fixed synthetic regression fixture under `apps/ios/Tests/Visual`.

The [retirement inventory](retired-assets.json) records the source revision,
original paths, byte lengths and SHA-256 of 450 obsolete preview assets and 14
unused web-shell notices. Historical preview reports retain their findings and
give `git show` references for removed media. The Git history was not rewritten;
private datasets, original files, models and backups were not part of this cleanup.

To inspect an old asset without restoring it to the active source tree:

```sh
mkdir -p .local/runs/historical-preview
git show fc1e934601b4:docs/preview/2026-09-26-s14-calm-voice/victoria-du.wav > .local/runs/historical-preview/victoria-du.wav
```

Match the restored file against its inventory SHA-256 before relying on it. Old
listening samples remain historical evidence, not approval of a future device update.
