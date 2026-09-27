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

The first tool-suite run exposed a pre-existing provenance mismatch: the Python
conversation evaluator expected `calendar-5`, while the current Swift provider
reports `calendar-6`. The evaluator now accepts the current identity and explicitly
rejects `calendar-5` alongside earlier identities; no app behavior changed.

The expanded tool run exposed another pre-existing fixture failure: XcodeGen's
resource-closure fixture omitted the existing signing scripts declared by the
unchanged project specification. The fixture now copies declared pre/post-build
script sources and reports generator stderr. Both normal/trial resource checks pass.

## Implemented and checked

The cleanup retains all six workspace areas, adds MIT licensing/editor settings,
splits Make recipes by responsibility, centralizes source discovery/identity,
and adds deterministic source packaging. The application host adapter, error
translation and existing test modules are separated without changing exported
UniFFI declarations. `VoiceModel.swift` is a byte-identical rename. The shared
conversation probe setup and existing response-file source list are reused.

The recovery catalog binds 145 retired files to original Git bytes. Exactly 23
commands exclusive to completed investigations were removed. Reusable training,
export, evaluation, runtime locks, model cards and active protocols remain.
Representative Make dry runs preserve supported commands and arguments.

| Check | Result |
| --- | --- |
| Rust formatting; Swift formatting; Python formatting/lint; shell formatting/lint | Passed |
| Python/tool programs | All 88 passed in an extracted tree with spaces and no `.git`; optional dependency/LLVM cases remain explicitly skipped |
| CI monitor | 16 tests passed |
| Documentation and recovery catalogs | Five tests passed; 145 recovery hashes independently checked against Git |
| Runtime inventory | Recomputed offline and verified; 135 dependency records |
| License notices and visual PNGs | Original manifest hashes unchanged |
| Repository ownership | 857 source files; 855 exported after excluding two local instruction files |
| Archive rejection tests | Eight tests passed, covering tampering, omissions, modes, duplicates, unsafe paths, symlinks, prohibited artifacts, dirty trees and setup aliases |
| Reproducibility | Repeated packaging of one commit produced identical bytes |
| Fresh archive setup | Bootstrap, doctor, explicit dependency/model restoration and `convert TARGET=all` passed |
| Source identity after setup | Passed; generated workspace aliases remain excluded |

The complete extracted tool run used implementation commit
`84093b83804d265ecf5a898dcdf74d2134c5f924`. Subsequent cleanup removes three unused
historical images/artwork files, updates ownership metadata and documentation, and
adds this record. The delivered archive has its own commit-bound manifest,
checksum sidecar and external verification receipt. Raw logs remain privately in
`.local/maintenance/source-cleanup`; they are not setup prerequisites.

## Blocked and unqualified

`make lint` and `make test` stop before compilation because the disk reserve is
insufficient. Their noncompiling style checks were run separately and passed.
Rust tests, Clippy, affected Swift probes and generated-binding comparison are
**not freshly verified**. Simulator and unsigned device builds also stop at the
reserve guard. A normal build needs 24 GiB free; simulator/UI/visual runs need
36 GiB. Observed capacity was about 14–17 GiB. No guard was lowered and no protected
private data or evidence was deleted.

Exported declarations and moved adapter/error/test bodies were compared with the
original source, allowing only module imports, scoped visibility and formatting.
This static comparison does not substitute for compilation. App identifiers,
project overlays, persistence formats, model/dependency locks, generated bindings
and visual baselines remain unchanged.

No fresh scan/review, calendar-confirmation, persistence, cancellation, speech
endpoint or playback integration run is claimed. Their existing native tests are
retained. The historical strict visual comparison remained 17/22, despite a
passing historical UI suite; references and tolerances were not changed. This
cleanup does not establish real-speech reliability or qualify experimental models.
No phone build was installed, repository published or dependency upgrade performed.
