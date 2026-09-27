# Reproducible source archives

`make source-zip` requires a clean committed checkout, including untracked source.
It reads blobs from the commit, verifies working-tree bytes and executable bits,
and writes `.local/submissions/rehab-plan-ocr-<full-commit>.zip` plus a SHA-256
sidecar. Existing different outputs are never overwritten. Git is required only
for creation; archive verification uses the Python standard library.

```sh
make verify-source SOURCE_ZIP="/path with spaces/rehab-plan-ocr-<commit>.zip"
shasum -a 256 "/path with spaces/rehab-plan-ocr-<commit>.zip"
```

Verification rejects duplicate or unsafe paths, symlinks, submodules, prohibited
artifacts, missing/extra entries, changed bytes, incorrect modes and inconsistent
provenance. The manifest excludes itself from its file list. The commit object
and complete Git tree allow offline reconstruction of the claimed commit and
exported blobs. This proves internal consistency; compare the delivered ZIP
checksum or commit through a trusted channel to establish publisher authenticity.

The ZIP uses sorted paths, fixed 1980 timestamps and uncompressed entries to avoid
compressor-version differences. UTF-8 names and Unix executable modes are retained.
Local agent instructions are omitted; only their Git object identities remain in
the provenance tree. No private recordings, documents, weights, backups, cached
environments, generated Xcode projects or compiled products are included.

## Extract and verify

Use an extractor that preserves Unix modes, such as macOS `unzip`:

```sh
mkdir -p "/tmp/rehab source review"
unzip "/path/to/submission.zip" -d "/tmp/rehab source review"
cd "/tmp/rehab source review/rehab-plan-ocr"
python3 tooling/dev/source_zip.py directory
make bootstrap
make doctor
make restore
make convert TARGET=all
make lint
make test
make inventory-repository
make check-runtime-inventory
make check-bindings
make build TARGET=simulator
make build TARGET=device
```

Each extracted tree creates its own `.local` workspace. Model/tool downloads are
explicit and pinned; no original workspace paths are required. Setup needs the
same system prerequisites and disk reserve as a checkout. `directory` verifies
source bytes and modes again after extraction; generated ignored local products
are outside the source identity. Intentional source edits invalidate the original
manifest's provenance and should be developed in a Git checkout.

Historical baseline comparisons, signed-release reservation, Git history recovery,
CI remote monitoring and evidence-bound research trials still require Git where
their commands explicitly use commit history. Pinned training/runtime upstreams
also use their own Git checkouts. A submission does not include private evidence
needed by experimental trials.
