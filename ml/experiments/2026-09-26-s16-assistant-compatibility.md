> Historical record: technical findings retained from the archived development sequence. Project dates, build labels and source references have been normalized. This record is not a new test, delivery approval or signing attestation; unaltered evidence and original validity dates are held in the external private archive.

# Qwen3 LoRA, fusion and GGUF compatibility

Run `assistant-smoke-003` completed the entire offline desktop path: pinned
Qwen3-0.6B → baseline GGUF execution → eight MLX-LM LoRA steps → adapter fusion →
tokenizer identity checks → F16 GGUF export → local llama.cpp execution. The earlier
failed run remains in `.local/runs/assistant-smoke-001`; its fused export exposed
the Transformers 5/4 special-token metadata incompatibility. The corrected runs
002 and 003 produced identical adapter and exported-model hashes.

- Base revision: `c1899de289a04d12100db370d81485cdf75e47ca`.
- Converter/runtime source: `41fc7584f0c1d72d9cc1ac46ccae8defc1587f0f`.
- Adapter SHA-256: `e82f3af39e8bb9f35d40742518a5a7cb2c97f4577b044276e9be4cdb7b193eb3`.
- F16 GGUF SHA-256: `49b2cf706c096ae1776ee888cc01cdc07d45f34ba04423b725dc086079abebae`.
- Trainable parameters: 0.721 million / 596.050 million (0.121%).
- Eight invented training cases, four separate invented validation families;
  170 target tokens trained. Human language review is pending.
- Maximum tokenized length 281, zero truncations, prompt masking checked.
- Reported validation loss: 3.513 → 2.575 → 1.279. This is not task accuracy.
- Reported MLX peak memory: 1.919 GB, not whole-process or device peak memory.

All 12 fusion probes agreed on the greedy **first generated token only**.
Maximum absolute logit differences ranged from 0.203125 to 0.3125 after bfloat16
fusion. This is partial compatibility evidence, not full-answer numerical parity.
No quantized artifact or shipping iOS runtime was evaluated.

## Structured-output diagnostic

The pinned desktop runtime executed both exported models on the same 12 prompts,
alternating model order by case. A strict validator checked the experimental
intent contract, known references, dates/times and exact expected operations.

| Model | Training examples valid / exact | Validation examples valid / exact |
|---|---:|---:|
| Untuned base | 0/8 / 0/8 | 0/4 / 0/4 |
| Eight-step LoRA | 0/8 / 0/8 | 0/4 / 0/4 |

Every output was rejected. Examples included unknown action/field names, invented
appointment details, a fabricated replacement for an invalid date and a removal
intent despite a negation. The absence of accepted unsafe mutations means these
outputs were blocked; it does **not** mean the model understood cancellation.

Quality gate: **failed; do not promote either artifact**. Independent real-dialogue
denominator: zero. These few, unreviewed development examples cannot estimate
population accuracy or establish model selection. No device latency, thermal,
energy, listening or usability claim follows from this run.

The [reproduction guide](../training/assistant/README.md) and
[artifact card](../registry/assistant-smoke-003.json) record the workflow and
lineage. Larger reviewed data, optimizer-state resume, validation stopping,
whole-output export checks, comparison with rules/Apple and real iOS evaluation
remain required. The app continues to use its existing providers and voice.
