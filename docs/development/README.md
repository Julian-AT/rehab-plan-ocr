# Development

Follow the [root setup](../../README.md#prerequisites-and-setup) from either a
checkout or an extracted submission. Workspace paths are resolved centrally by
`tooling/dev/workspace.py`; `.local` holds tools, environments, builds, models,
data and runs. `make doctor` checks the exact toolchain. `make check-workspace`
checks the storage layout. Paths with spaces are supported.

## Commands

| Command | Scope |
| --- | --- |
| `make format` | First-party Rust, Swift, Python and shell formatting |
| `make lint` | Formatting, Python/shell lint, Clippy and runtime provenance |
| `make test` | Rust, tool tests, ICS and selected native probes |
| `make test-tools` | Automatically discovered Python tool and research tests |
| `make test-ios` | EventKit integration and synthetic app UI tests |
| `make check-bindings` | Regenerate and compare committed UniFFI Swift bindings |
| `make inventory-repository` | Account for every source file and its consumers |
| `make verify-runtime-inventory` | Check committed runtime inputs and notice hashes |
| `make check-runtime-inventory` | Recompute runtime dependency closure offline |
| `make build TARGET=simulator` | Unsigned simulator app |
| `make build TARGET=device` | Unsigned arm64 device app; no installation |

Common entry points are in `Makefile`; `tooling/make/{build,checks,research,maintenance}.mk`
keep their full recipes and supported arguments. `make test-<probe>` selects the
corresponding script under `tooling/checks`. Native probes require macOS and the
pinned Xcode toolchain. Do not run multiple simulator or model jobs concurrently.
Generated bindings and vendored C sources are excluded from first-party formatting.

Run `python3 tooling/checks/tests/test-documentation.py` for documentation links,
visual-reference hashes and byte-exact notices. An ownership inventory is not a
complete code review. Model quality and human research approval remain separate.

## Storage and offline work

The [retention policy](artifact-retention.md) requires a 20 GiB reserve plus each
operation's peak. Ordinary builds and compiling checks reserve another 4 GiB;
simulator checks reserve 16 GiB. Do not reduce these guards to force a build.

After explicit setup, use `CARGO_NET_OFFLINE=true UV_OFFLINE=true make build`.
Native Cargo builds use `--offline`. Missing crates require `make restore-rust`.
No ordinary build downloads or replaces a model. Frozen locks remain authoritative.
See [build details](build-reproducibility.md) and [dependency audits](dependency-audit.md).

The [verification record](verification.md) describes this cleanup's evidence.
Historical reports are available through [Git recovery](recovery.md).
