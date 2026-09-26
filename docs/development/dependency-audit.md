> Historical record: technical findings retained from the archived development sequence. Project dates, build labels and source references have been normalized. This record is not a new test, delivery approval or signing attestation; unaltered evidence and original validity dates are held in the external private archive.

# Reproducible dependency security review

The optional audit entry uses cargo-audit **0.22.2** from the hash-pinned Homebrew
`arm64_tahoe` bottle. It supports ARM64 macOS 26 or newer and runs from
`.local/tools/bin/cargo-audit`; Homebrew is not required. Other host platforms need
a separately reviewed tool pin. The normal Rustup/Xcode setup remains unchanged.
Python, Git and curl use the documented development host environment.

The [tool policy](../../config/toolchains/cargo-audit.json) records the executable,
bottle, upstream source and formula identities retrieved on 2026-09-26 from
[Homebrew's public formula](https://formulae.brew.sh/api/formula/cargo-audit.json).
The verified executable links only to macOS system libraries. This is a development
tool; it is not bundled with the app. No dependency update or compiler is invoked
by any command below.

## Download and setup

After the normal workspace setup, download the 5.95 MB bottle explicitly, then
install it offline:

```sh
make download-dependency-audit
make setup-dependency-audit
```

Download writes `.local/downloads/cargo-audit-0.22.2-arm64_tahoe.tar.gz`. A valid
cached archive is reused. The anonymous GHCR header follows
[Homebrew's public download convention](https://github.com/Homebrew/brew/blob/master/Library/Homebrew/brew.sh);
no user token is read. Both archive and executable checksums must match. Setup
extracts only the exact regular executable member, never the full archive tree.
It reuses an identical installed executable and refuses to replace changed bytes.

An existing verified archive can be supplied without any network request:

```sh
make setup-dependency-audit AUDIT_ARCHIVE=/absolute/path/to/the/pinned-bottle.tar.gz
```

The workspace must already use canonical `.local` tool storage. For a legacy
checkout, use the separately documented
[verified workspace migration](build-reproducibility.md) first. The audit wrapper
does not move existing tools or fall back to a binary discovered on `PATH`.

## Explicit advisory update

Use a new directory for every refresh. The command fetches the current default
branch of the official [RustSec advisory database](https://github.com/RustSec/advisory-db),
then prints its exact commit and writes a sibling `.identity.json` receipt with
retrieval time, origin and SHA-256 of every tracked file. Existing snapshots and
their receipts are never overwritten.

```sh
make update-dependency-advisories AUDIT_DB=.local/audits/advisories-YYYYMMDD
```

Replace `YYYYMMDD` with a new snapshot identifier. Save the printed 40-character
commit for the next step. Refresh is separate from audit so a later run can use
the same evidence without fetching newer advisories.

## Offline audit

Pass the exact database commit and a new result directory:

```sh
make audit-dependencies \
  AUDIT_DB=.local/audits/advisories-YYYYMMDD \
  AUDIT_COMMIT=COMMIT_PRINTED_BY_THE_UPDATE \
  AUDIT_RUN=.local/audits/review-YYYYMMDD-01
```

This invokes `cargo-audit audit --no-fetch --no-yanked` using only the specified
snapshot. It reads the complete `Cargo.lock`, including build/development entries,
and verifies the current release runtime inventory separately. Target/build
relevance still requires review against that inventory. Offline mode deliberately
does not query crates.io for yanked versions; it does not claim that check passed.

The wrapper rejects a stale inventory, changed database files (including changes
hidden with Git's `assume-unchanged` flag), a different commit/origin, altered
executable, filtered audit settings or inputs changed during the run. It keeps
raw JSON and stderr. A completed `receipt.json` binds the report to the tool,
wrapper, policy, lockfile, inventory and all database file hashes. A failed tool
invocation keeps diagnostics but receives no completion receipt. A valid review
with vulnerabilities retains its receipt and returns exit code 1; findings are
never ignored automatically. Every result directory is immutable to this command.

No RustSec result supplies public release approval. Native libraries, Apple
frameworks, models, training environments, licensing and actual release binaries
need their own checks. The
[dated security review](../releases/dependency-security-2026-09-26-s18.md) records those
scope decisions and remaining work; historical reports remain unchanged.

## Verification

```sh
make test-dependency-audit
```

The synthetic tests cover archive/member checks, repeatable setup, cache integrity,
explicit refresh, database identity, hidden modifications, filtered results,
input races, retained vulnerability evidence and prevention of output overwrite.
They invoke neither the network nor a compiler and do not read private data.

On 2026-09-26 the existing verified bottle was installed under `.local/tools`
without Homebrew execution. A fresh explicit database retrieval produced commit
`2b34578f89884736e0fcbd42f7ba8d6b10b4a0ce`; its receipt is retained locally at
`.local/audits/dependencies-2026-09-26-s18/repro-rustsec.identity.json`.
Two offline reviews, including the Make entry, bound the same inputs and produced
byte-identical reports: 231 lockfile dependencies, 1,251 advisories, no reported
vulnerabilities and two unmaintained warnings (`paste` and `ttf-parser`). The
reports and receipts remain in `repro-offline-01` and `repro-offline-02` below that
audit directory. Report SHA-256 is
`3c65f9e81f53dd88e6c5fb37a91272a80b5072c471f77c7a46bedb963dc98f3b`;
the verified inventory SHA-256 is
`db182b42cbc5767cd519387a36277f8774b4a231afec0932ec6b1ff6bc26458e`.
All 14 synthetic audit tests, four documentation checks and Ruff checks passed.

On 2026-09-26 a fresh explicit retrieval produced RustSec commit
[`d5c17953a895cf19e8d3ce66eaa42b6fcfe1fb16`](https://github.com/RustSec/advisory-db/tree/d5c17953a895cf19e8d3ce66eaa42b6fcfe1fb16).
The subsequent offline Make audit again reports no matching vulnerabilities
across 231 lockfile dependencies and 1,251 advisories. The two maintenance
warnings remain: `paste 1.0.15` is in the build dependency closure and
`ttf-parser 0.25.1` in the target dependency closure. No dependency was changed.
Native components and registry yanks were not freshly audited by this run.
The immutable database, raw report and receipt are retained at
`.local/audits/advisories-20260926-s20-001` and `review-20260926-s20-001`; the separate
`.local/maintenance/dependency-review-summary-20260926-s20-001.json` records scope and
unchanged lockfile identity after integration. Earlier reports remain unchanged.

On 2026-09-26 a fresh explicit retrieval produced RustSec commit
[`a26d8486932e36fc3dd0f3bb7073233ed524baee`](https://github.com/RustSec/advisory-db/tree/a26d8486932e36fc3dd0f3bb7073233ed524baee).
The offline review completed successfully across 231 lockfile dependencies and
1,252 advisories, with zero reported vulnerabilities and the same two unmaintained
warnings. No dependency was changed. Its immutable inputs, raw output and receipt
are under `.local/audits/advisories-20260926-s21-001` and
`.local/audits/review-20260926-s21-001`. The receipt binds the inventory present at the
time of that run; subsequent inventory or package changes require their own
verification. Native libraries, Python environments and registry yanks are outside
this RustSec result.

## Python tooling and training locks

`tooling/release/audit_python.py` audits all registry packages in these five locks:
the root `uv.lock`, the assistant training, assistant export and OCR training
`uv.lock` files, and `tooling/build/export-victoria.py.lock`. This covers Python
development, training and conversion dependencies; it does not claim that Python
is shipped in the iOS app or replace the Rust/native review.

Retrieval is an explicit online operation. Use a new private directory:

```sh
.local/envs/tools/bin/python tooling/release/audit_python.py download \
  --output .local/audits/python-osv-YYYYMMDD-01
```

Only normalized public PyPI package names and locked versions, returned page
tokens and public advisory IDs are sent to `api.osv.dev`. No lockfile, source,
local path, environment credential or virtual-project record is uploaded.
Exactly `https://pypi.org/simple` registry sources are accepted; unknown registries,
Git/editable dependencies and unsupported sources stop the audit. Local virtual
projects are explicitly recorded as excluded. Names/versions are deduplicated
across locks; every occurrence and its lock/marker context remain in the snapshot.
Markers are retained rather than used to silently omit inactive platform entries.

The [OSV batch API](https://github.com/google/osv.dev/blob/master/docs/api/post-v1-querybatch.md)
returns results in request order. The tool records that order, requires one result
per query, follows every per-result page token and retrieves each full advisory
through `/v1/vulns/{id}`. Repeated/excessive pages, unexpected result fields,
changed advisory timestamps and mismatched package identities fail closed.
Raw requests/responses, full advisory records, all five locks and the audit source
are saved with hashes. The printed `snapshot_sha256` identifies `receipt.json`;
retain that value for the offline command.

```sh
.local/envs/tools/bin/python tooling/release/audit_python.py offline \
  --snapshot .local/audits/python-osv-YYYYMMDD-01 \
  --snapshot-sha256 SHA256_PRINTED_BY_DOWNLOAD \
  --output .local/audits/python-review-YYYYMMDD-01
```

Offline replay performs no network requests. It verifies the explicit receipt
hash, exact file closure, source, current and archived locks, inventory and the
complete ordered request/response sequence before producing a report. Inputs are
checked again on exit. Different current locks or audit code require a new query;
historical replay requires the recorded source and matching locks in an isolated
checkout (`--root` can select it), without rewriting original receipts.

The report preserves full advisories and withdrawal status. Connected advisory
IDs/aliases count as one vulnerability group; affected package/version pairs and
raw advisory records have separate counts. A withdrawn-only group remains visible
and does not count as an active finding. OSV's version-query verdict is replayed;
the tool does not independently reimplement each ecosystem's affected-range rules.

The declared limits are 30 seconds per network request, 8 MiB per response,
128 MiB total responses, 100 queries per batch, 20 pages per query, 2,000 unique
package/version pairs and 2,048 advisory records. Failed or incomplete retrievals
retain their received bytes and an incomplete receipt. Each request runs in an
owned HTTP-only child; the wall-clock deadline includes system DNS resolution,
with a further two seconds allowed for termination and reaping. Completed offline
evaluation
returns exit 0 for no active findings or exit 1 for active findings; an unavailable,
corrupt or incomplete audit returns exit 2 and cannot produce a passing report.
Existing output directories, destinations inside previous audit snapshots/reports
and symlinked paths are refused.

No command upgrades packages, updates environments/locks, grants an exception or
approves release. Findings require review of the relevant tooling/training usage
and separately validated remediation. Run the network-free synthetic regressions
with `.local/envs/tools/bin/python tooling/release/tests/test-audit-python.py`.
