> Historical record: technical findings retained from the archived development sequence. Project dates, build labels and source references have been normalized. This record is not a new test, delivery approval or signing attestation; unaltered evidence and original validity dates are held in the external private archive.

# Expanded German intent development run

`assistant-development-001` uses the resumable trainer at `01256e3`, Qwen3-0.6B,
eight LoRA layers, rank eight, learning rate 0.0001 and batch size two. Its 112
training cases belong to 28 scenario families; 40 validation cases belong to ten
different families. Four parameter combinations per family are correlated invented
examples. Human German-language review is pending; no real dialogue or final
holdout was used.

Validation stopping selected epoch four and stopped after epoch seven (392 Adam
steps, three epochs without improvement). Selection prioritizes unsafe mutations,
then exact-operation errors, family error and loss. Training loss approaching zero
does not establish generalization to the separate validation families.

| Route | Valid schema | Exact operation | Unsafe proposed mutation |
|---|---:|---:|---:|
| Untuned GGUF | 18/40 | 4/40 | 7/40 |
| Tuned adapter MLX | 38/40 | 17/40 | 10/40 |
| Tuned fused MLX | 38/40 | 17/40 | 10/40 |
| Tuned GGUF | 37/40 | 17/40 | 11/40 |

Full-answer fusion parity passes 40/40. F16 GGUF parity passes only 34/40.
Divergences occur in three room follow-ups, two clock-constrained queries and one
invalid-April-date case. The exported model can propose a change while answering a
room question. No operation was executed. More exact operations cannot compensate
for more unsafe proposals; both quality and deployment parity gates fail.

The export command returns failure and retains all artifacts and raw answers.
Thresholds were not relaxed, and no production provider changed. More repetitions
of the same short templates would not supply independent linguistic evidence.
Future development requires broader checked training scenarios, hard negative
examples and explicit export diagnostics; candidate selection must remain separate
from the unopened final holdout.

The [model card](../registry/assistant-development-001.json) records selection,
denominators and hashes. Weights, checkpoints, conversion logs and detailed answers
remain in ignored `.local/runs/assistant-development-001`. These desktop results do
not qualify shipping iOS inference, speed, memory, natural pauses or comprehension.
