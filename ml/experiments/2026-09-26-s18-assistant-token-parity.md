> Historical record: technical findings retained from the archived development sequence. Project dates, build labels and source references have been normalized. This record is not a new test, delivery approval or signing attestation; unaltered evidence and original validity dates are held in the external private archive.

# Assistant prompt boundary and first-token diagnosis

This is a development-only diagnostic of the retained Qwen3-0.6B adapter export.
It introduces no independent examples, changes no model weights or acceptance
thresholds, and does not qualify a provider for the app.

## Confirmed prompt-boundary defect

The pinned llama.cpp revision is
`41fc7584f0c1d72d9cc1ac46ccae8defc1587f0f`. Its `common/arg.cpp` file handler
for `-f` removes exactly one final LF. The earlier complete-answer export and
three-configuration backend diagnostic used that option. MLX and the native
C-API receive the full rendered template, whose disabled-thinking suffix ends
in `</think>\n\n`.

For each of the six retained mismatches, that CLI transformation changes only
the last input token from 271 (two LF) to 198 (one LF). Input lengths remain
566, 583 or 576 tokens, so comparing token counts alone cannot detect the defect.
No prompt in these six cases contains a literal backslash.

The four desktop consumers now share `runtime_prompt.arguments`, which selects
`--binary-file --no-escape`. The binary reader retains final newlines; disabling
escape processing also protects literal backslashes in JSON/context. Neither
transformation belongs to the MLX/native prompt contract. Original prompts,
answers, export receipts and the historical model card remain unchanged.

On the single controlled room-follow-up case 0011, the unchanged executable
with the corrected boundary reproduces the MLX/C-API answer exactly. The old
`-f` route additionally proposed a title and time change. Disabling CLI warmup
alone preserved that old answer. The corrected answer still incorrectly
proposes an update for a room question; numerical agreement is not intent quality.

## Reproduction and retained evidence

```sh
make diagnose-assistant-token-parity \
  RUN=.local/runs/assistant-development-001 \
  DIAGNOSTIC_RUN=.local/runs/assistant-token-trace-<new> \
  WEIGHTS_EVIDENCE=.local/runs/assistant-token-diagnosis-20260926-s18-001/weights.json
```

The diagnostic validates the selected checkpoint, all 40 original validation
rows/prompts, source identities, pinned runtime and retained tensor comparison.
It saves exact diagnostic sources in a new private directory. Model processes
run serially. Instrumented MLX generation must preserve ordinary `generate`
answers; C-API generation must preserve the corrected CPU CLI answers. Automatic
desktop selection is checked on the entire 40-case corpus. Only remaining differences receive additional CPU 512/128
batching controls and C-API instrumentation. `--verbose-prompt` supplies actual
CLI token IDs for comparison, including on explicit historical `-f` controls for the six old failures.

Only remaining generated-token disagreements receive a teacher-forced replay.
Both sides must use the identical original prompt and common generated prefix;
the replay must preserve the original next-token rankings. Full float32 logit
vectors are retained only at those comparison points. No teacher-forced answer
is used as an ordinary generation or quality result.

Private run `assistant-token-trace-20260926-s18-001` preserves the earlier
instrumentation-control failure, the unchanged CLI and no-warmup controls, the
corrected single-case control and the six prompt-token comparisons. Its missing
final success report is intentional: the original C-API/CLI agreement check
failed, which led to discovering the unequal prompt boundary.

The upstream weight comparison covers all 310 tensor pairs and 596,049,920
values. Shapes and names agree; 78,026 values differ by at most
`2.9802322387695312e-08` because conversion to F16 rounds BF16 subnormals. That
observation alone neither proves inference equivalence nor attributes a logit
difference to those values. Source identities remain:

- Fused safetensors: `c3900b64d7ba3a2513172940da4db5f88f5d769f75064f23f82307742d5dc168`.
- GGUF: `c522352314c4291de620ec947653c272ab7622eb477edca8cac422d157f2651d`.
- Runtime: `07285dd33e2ade112ae1ced29183afb5f77dd6b57fa0d935b7b5b9fcd9592c86`.

## Full-corpus result

The corrected full-corpus CLI comparison is still pending. Run
`assistant-token-trace-20260926-s18-002` completed all 40 MLX controls: ordinary and
instrumented generation agree for every case; all 40 also reproduce the retained
fused answers. Host peak RSS was 1,521,893,376
bytes; MLX peak memory was 1,741,343,268 bytes. The subsequent C-API worker was
stopped during sustained host memory/I/O pressure; its unfinished trace is not a
full-corpus result and the run remains failed/incomplete.

The revised orchestration checks complete CLI answers and actual input token IDs
first, then traces only remaining disagreements. Optional `REUSE_MLX` validates
all retained model, environment, non-orchestrator source and request identities,
plus AST-identical MLX worker/helper implementations. It requires a complete
ordered worker result, retains the original report/source bytes, and records the
reused evidence hashes. A changed model, worker, prompt or incomplete result
forces fresh generation. CPU traces run in small packages; completed CLI cases
are written separately so an infrastructure interruption does not erase them.

The original six-case trace already identifies a candidate remaining difference
on `invalid-april-0002`: after 23 shared generated tokens, MLX chooses token 19
(`4`), with tokens 19 and 22 tied at BF16 logit 20.875. CPU chooses token 22 (`7`),
whose raw score is 20.880859375 versus 20.720703125 for token 19. This still needs
the corrected full-corpus CLI control and matched-prefix replay. It neither
establishes which arithmetic operation first differs nor justifies changing
precision, tie-breaking or the complete-answer gate. Both date answers are
incorrect for the intended invalid-date clarification.

Ten focused token/prompt/reuse regressions and two existing CLI/intent diagnostic
regressions cover source reuse, changed models/requests, incomplete evidence,
actual token identities, exact shared prefixes, request limits and EOS handling.
The C++ helper compiled against the pinned libraries with
`-Wall -Wextra -Werror`. A successful diagnostic command will remain distinct
from passing parity or qualifying the model.
