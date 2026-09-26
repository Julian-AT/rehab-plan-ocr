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

## Full-corpus result — verified comparison, failed parity

Run `assistant-token-trace-20260926-s18-004` completed the corrected comparison on
all 40 original development cases. All 40 actual CLI input-token arrays match
the retained MLX inputs exactly. All six historical controls reproduce their
old complete answers and the last-input-token change from 271 to 198. The
orchestrator rechecked all 85 source/evidence identities before writing its
successful diagnostic report; weights and runtime retain the hashes above.

| Complete-answer comparison | Matches | Differences |
| --- | ---: | ---: |
| Historical CLI file boundary | 34/40 | 6/40 |
| Corrected identical prompt bytes | 38/40 | 2/40 |

Five historical differences disappear. `invalid-april-0002` remains different;
`invalid-april-0000` becomes a new **parity** failure. That second case was already
an incorrect update instead of the required invalid-date clarification in both
providers; its former text agreement never meant it was a correct answer. The
new difference is retained explicitly rather than hidden by the improved total.
These are the same selected development cases, not 40 newly independent examples.

## First differing token and raw logits

For both remaining cases, the unchanged CPU CLI and the instrumented C-API
reproduce the corrected desktop answer. The CPU trace receives exactly the same
prompt IDs. Teacher-forced replay uses only the identical shared prefix and
reproduces the free-generation top logits exactly on both sides.

| Case | Prompt tokens | First differing generated position (zero based) | MLX token | CPU token | MLX scores for those two tokens | CPU scores for those two tokens |
| --- | ---: | ---: | --- | --- | --- | --- |
| `invalid-april-0000` | 582 | 27 | 30975, JSON closing suffix | 2198, JSON field separator | 20.375 / 20.0 | 19.5234375 / 20.9609375 |
| `invalid-april-0002` | 583 | 23 | 19, `4` | 22, `7` | 20.875 / 20.875 | 20.720703125 / 20.880859375 |

For `invalid-april-0000`, MLX ends the update after date `2031-05-15`; the corrected
CLI continues with time `08:00`. Both should instead ask for a valid date. This
is a reversed ranking with a single MLX maximum, not an MLX tie. The maximum
absolute difference across that full next-token logit vector is 0.9609375.

For `invalid-april-0002`, the two highest BF16 MLX logits are exactly tied; MLX
chooses `4` and subsequently proposes the impossible date `2031-04-31`. CPU
chooses `7` and proposes `2031-07-28`. Both fail the expected clarification. The
maximum absolute logit difference is 0.216552734375.

This reaches the first differing generated token/logit on the identical context.
It does not identify the first differing internal arithmetic operation. The
untied first case rules out treating all remaining failures as only a final
BF16 argmax tie. No change to precision, tie-breaking, weights or the complete-
answer contract is justified by this evidence. **The export parity gate remains
failed at 2/40; the model remains unqualified.**

## Resource and evidence checks

The successful orchestration took 53.78 seconds, excluding the reused MLX run.
Maximum process RSS was 1,589,805,056 bytes (1.48 GiB). The earlier complete MLX
worker used 1,521,893,376 bytes peak RSS and 1,741,343,268 bytes peak MLX allocation
(1.62 GiB); the new two-case MLX replay peaked at 1,735,871,016 bytes allocation.
These host diagnostics under different load conditions are not paired latency,
energy, iPhone or shipping-runtime measurements. The 8-GiB expected peak plus
20-GiB storage reserve passed before execution.

`REUSE_MLX` accepted run `assistant-token-trace-20260926-s18-002` only after identical
model, environment, non-orchestrator source and request identities plus
AST-identical MLX worker/helper implementations. All 40 retained worker cases
reproduce both ordinary `generate` and the historical fused answers. CPU traces
were restricted to the two actual remaining differences. No model processes ran
in parallel. At 15:37:08 UTC on 2026-09-26, the process check found no remaining
model or diagnostic worker.

A separate post-run metadata audit reread all 40 actual CLI token arrays, raw
answers and per-case receipts, and checked the exact remaining-case set. Private
logs, prompts, source snapshots, binary identity and the four full logit vectors
remain in the new run. Evidence hashes:

- `report.json`: `728e1ba5e8b9b4375470590c4709262aa359da991303dd68464506c05a0256fe`.
- `sources.json`: `61c4f609b9a9e335230546fc13219a3045b90c9e48401e2624f21bd5a3dc3107`.
- `controls.json`: `e06ac5e49a89e6931a6689cc6bbcd46769e81e73829a9058b4f2585d5ba5b4b7`.
- `artifact-audit.json`: `4dce98a32b73ab4ad301b03f4ce62f8a00fb3811842e63091f140856a96022eb`.

Runs 001–003 remain unchanged: 001 exposed the prompt-boundary control failure;
002 completed MLX but its unnecessary full-corpus C-API trace was stopped under
host pressure; 003 preserved a parser failure on prefixed CLI INFO token logs.
Commit `e7313c2` added that exact pinned logging format while retaining strict
ID/count checks; the captured 579-token input was checked before run 004.

Eleven focused token/prompt/reuse regressions plus two CLI/intent diagnostic
regressions pass. The C++ helper compiled with `-Wall -Wextra -Werror`. Packages
were MLX 0.32.2, MLX-LM 0.31.3, NumPy 2.5.3 and Transformers 5.17.0. A successful
diagnostic command means the evidence was collected and checked; it does not
mean parity or product qualification passed.
