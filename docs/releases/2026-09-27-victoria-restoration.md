# Victoria restoration on the personal phone

The explicitly requested in-place update to **0.3.0 (2026092702)** restored the
original pinned Victoria voice and the saved 1.15× rate. The user confirmed the
voice is correct, but reported continued cancellations and failures on basic
questions. Conversation acceptance remains failed.

Source `38ea77e` includes German SpeechAnalyzer asset preparation (`3040aa6`).
The signed arm64 archive was built from a clean checkout outside synchronized
storage. Explicit private packaging verified all four signatures, provisioning
profiles, App Groups, executable/dSYM identities, 15 pinned speech files and the
supplemental native/notices inventory. IPA SHA-256:
`5f4c7416826f7ba044e597031e0c78c48a4e8250bcd88c3638fc5f2f7f180e56`.
Installation did not uninstall the app. Version and startup were checked.

Verification before installation: lint; speech asset/turn/input checks; Victoria
PCM validation; voice-flow regressions; 16 bundle, 3 bundle-manifest and 9 release
artifact tests; normal/private simulator builds; private bundle verification.
The simulator UI test actually executed and passed playback, stop, repeat and
background cancellation. Its screenshot shows Victoria and 1.15×. Three synthetic
host listening samples contain non-silent audio and word progress; these are not
physical performance or human listening results.

The fresh backup contains 154 files. Rechecking the device inventory and rehashing
the backup preceded installation. The first post-launch capture was rejected when
the app became active during transfer. A subsequent stable capture reused only
files with unchanged remote metadata across the complete original transfer and
the fresh inventory, verified copied hashes, recopied changed files, and checked
all three containers against their new inventories. Failed captures are retained.

The original strict comparison is retained with `review_required: true`. Review
confirms unchanged schema 11, all rows and columns of all 17 tables, 31 scans,
30 retained originals, preferences and durable files other than diagnostics.
Diagnostics appended 335 events and evicted 335 under the existing 5,000-event
cap; the retained 4,665 original events are unchanged.

Phone diagnostics establish installed German speech assets, provider 1
(SpeechAnalyzer), successive completed transcriptions and Victoria playback.
They also show interrupted replies. Existing cancellation and interpretation
logs do not identify every cause, so this evidence does not establish a reliable
conversation or correct natural-language answers. Further diagnosis is required.

Private evidence: `.local/runs/victoria-speech-fix-device-20260927-001/`,
`.local/runs/victoria-preview-20260927-001/`,
`.local/runs/victoria-listening-20260927-001/`. Package:
`.local/releases/victoria-speech-fix-20260927-001/`.
