# Recovery of retired source and evidence

The source cleanup preserves Git history. Before removal, all refs were bundled
and `git bundle verify` confirmed a complete recovery bundle. The private copy is
`.local/maintenance/source-cleanup/recovery.bundle`; it is intentionally outside
the submission. The initial revision is
`edd7967e08c98788afa5e1d84f4c2c176b6e638a`.

[retired-source.json](retired-source.json) lists removed paths, original byte sizes
and SHA-256 hashes with their recoverable source revision. It covers superseded
release diaries, migration narratives, status ledgers and completed isolated OCR
operator/token-parity investigations with their exclusive tests. Reusable data,
training, export, evaluation, model cards and active protocols remain in `ml`.
The [findings summary](../../ml/experiments/findings.md) retains their limitations.

In a checkout, inspect a retired file with `git show <source_revision>:<path>`.
To recover independently, clone the private bundle into a new directory and check
out the initial revision. Do not overwrite the current source or private storage.
The bundle includes the original material; later cleanup commits remain in the
working repository's history.

[retired-assets.json](retired-assets.json) preserves the earlier visual/notice
recovery catalog unchanged. Required current generated bindings, synthetic
fixtures, vendored notices, icons and visual references remain in the source.
Historical evidence and old model cards retain their original identities; they
are not current verification claims or normal setup prerequisites. Private
recordings, documents, weights, backups and historical products were not deleted.
