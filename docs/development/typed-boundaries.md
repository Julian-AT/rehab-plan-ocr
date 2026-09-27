# Typed native boundaries and serialization

`packages/rust/reha-ffi/src/application.rs` retains the exported UniFFI records,
callback interface and application methods. Internal host adaptation lives in
`application_host.rs`; `application_errors.rs` translates application/service
errors without changing their identities. Existing tests are in dedicated sibling
modules. Generated Swift bindings remain committed under `packages/apple/RehaCore`.

Calendar reads, mutations, imports, overlap queries, agenda synchronization and
recognition requests use typed records. The shared contracts validate requests
before platform effects. App settings and retained historical document JSON keep
their version-compatible serialization boundaries. Unknown preference keys,
defaults and explicit null behavior remain covered by storage tests.

Error categories preserve permission denial, timeout, uncertain writes, expired
scans, stale revisions/proposals, busy state, cancellation, validation and storage
failures. Presentation strings must not become machine-readable error identities.

Run `make test`, `make check-bindings` and `make test-native-bindings` after changes.
The generated comparison checks signatures; the native probe checks real Swift/Rust
calls, revision checks, calendar identities, confirmation and cancellation. These
checks require the pinned toolchain and adequate working reserve.
