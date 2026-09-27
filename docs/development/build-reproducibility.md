# Build contracts

Tool versions and download hashes are pinned in `config/toolchains/versions.json`;
Cargo and Python use committed lockfiles. `make bootstrap` installs local tools
and environments; `make restore` explicitly restores OCR assets, iOS runtime and
dependencies. `make convert TARGET=all` verifies deployment artifacts. See the
[root setup](../../README.md) for the complete sequence.

`workspace.py` resolves canonical `.local/tools`, `.local/envs/tools`,
`.local/builds/rust` and `.local/builds/ios` paths. Historical compatibility aliases
remain supported for retained consumers. An extracted source archive needs none
of the original workspace's private directories.

Native assembly caches include source, model/runtime, headers, architecture,
compiled archive and toolchain identities. Every cache hit verifies output hashes.
The ignored XCFramework link exposes an atomically published verified product.
A native-input lease serializes shared project/framework preparation. Changed
resource contracts preserve earlier products as a separate generation rather than
merging stale bundle resources into a current app.

`make build TARGET=device` is unsigned. Signed archives instead require a new
`RELEASE_RUN` below `.local/releases`; existing archive and packaging evidence
cannot be overwritten. An existing archive may be repackaged only with an explicit
`RELEASE_ARCHIVE` into a new run. Packaging checks provisioning, entitlements,
App Groups, dSYM identities, notices, privacy and runtime resources. Use local
unsynchronized output storage if a File Provider adds signing-breaking metadata.

Builds check the [storage reserve](artifact-retention.md). Explicit restore and
normal offline build are distinct steps. The default app excludes experimental
speech weights/phonemizer. The [personal profile](personal-victoria.md) adds them
only through its explicit overlay and separate verification contract.
