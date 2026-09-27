# Source cleanup verification

Starting source: `edd7967e08c98788afa5e1d84f4c2c176b6e638a`.

Before editing, a complete Git recovery bundle was created and verified with
`git bundle verify`. It is retained privately at
`.local/maintenance/source-cleanup/recovery.bundle`; it is excluded from submissions.
Git history is preserved.

Baseline checks on 2026-09-27:

| Check | Result |
| --- | --- |
| Working tree | Clean |
| Toolchain doctor | Passed; Xcode 26.4, build 17E192 |
| Documentation, visual reference hashes, exact third-party notices | Four tests passed |
| Repository inventory | 981 files accounted for in 17 groups |
| `make lint` and `make test` | Blocked by storage guard: 17.3 GiB free; 24 GiB required |

The storage policy requires a 20 GiB working reserve plus each operation's peak.
The permitted existing caches cannot recover enough capacity. Private evidence,
models, backups and retained products must remain intact. No storage checks are
bypassed. Source cleanup does not qualify experimental models or real speech.
