> Historical record: technical findings retained from the archived development sequence. Project dates, build labels and source references have been normalized. This record is not a new test, delivery approval or signing attestation; unaltered evidence and original validity dates are held in the external private archive.

# Experimental Apple assistant runtime — 2026-09-26

The custom GGUF now executes through `packages/apple/LocalAssistant` on macOS and
the iOS simulator. The CPU static library also compiles for physical iOS devices;
no physical installation or execution occurred. The app's production provider and
bundle do not yet include this package or the unqualified model.

The run is `.local/runs/assistant-native-20260926-s17-002`. Report SHA-256:
`b3cf9cbc0b384fe43fbda3a641f3f3f9cd332639ef2bced498d9a4eac32992bf`.
The source tree starts at `327384f`; the report records the exact additional source,
compiler, SDK, library, model and test-input hashes. Swift wrapper identity:
`d94c6c16a2c8a0d7141b6e2cc645bdafb7e25bfd960fbb1a3b45994584a9fbc0`.
Host and simulator completion reports are identical:
`63a8896f6ea60449580fb04ec81d831bfb3c1c8d267853353d2e4fa38d73f78b`.

| Check | Host | iOS 26.4 simulator |
|---|---|---|
| Complete output equals prior desktop GGUF | 2/2 | 2/2 |
| Exact expected operation | 0/2 | 0/2 |
| Unsafe mutation proposals | 1/2 | 1/2 |
| Native cancellation and deadline | Pass | Pass |
| Context/output limit rejects partial answers | Pass | Pass |
| Same answer after abandoned requests | Pass | Pass |

The two prompts are the existing `correct-date` and `room-follow-up` development
cases. These are two scenario families, not four independent examples. The first
answer uses the wrong corrected day; the second turns a room question into an
update proposal. No operation is executed by the probe. Matching the desktop's
wrong answers establishes transport/runtime compatibility only. The candidate
continues to fail its quality and complete 40-case export-parity gates.

The first native run (`001`) found that a remaining deadline below one millisecond
was rounded to zero and returned `invalidRequest`. The Swift boundary now rounds
positive native timeout budgets upward and rechecks the exact monotonic deadline
before returning. The repeated actual native run passes the deadline regression.

The C boundary uses the pinned unmodified llama.cpp revision, fresh KV/sampler
state for each generation, a reusable model and independent atomic cancellation
ownership. Swift verifies model bytes off the UI thread and uses a serial queue.
CPU limits are 2,048 context tokens, 192 output tokens and 8,192 output bytes;
truncated/canceled generations expose no partial output. Generated libraries have
verified source/toolchain/architecture/output identities and retained MIT notices.

The Swift 6 host compile passes complete-concurrency checks with warnings as
errors. The actual simulator app builds and completes its report. The probe uses
two deprecated UIKit window conveniences; these affect the isolated harness and
remain separate from the app's visual contract. Synthetic boundary checks reject
bad assets/input and expired requests; a Python regression rejects missing, stale,
incomplete or empty native completion reports. All 126 tool tests pass.

Still required: app structured-output/provider integration, full provider comparison,
qualified German model data/artifacts, Metal/quantization parity and resource
comparison, physical memory/energy/thermal/latency evaluation and patient studies.
This test makes no real-device latency or offline-in-airplane-mode claim.
