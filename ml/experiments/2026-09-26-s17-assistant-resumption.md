> Historical record: technical findings retained from the archived development sequence. Project dates, build labels and source references have been normalized. This record is not a new test, delivery approval or signing attestation; unaltered evidence and original validity dates are held in the external private archive.

# Qwen3 intent adaptation: resume and full-answer export

The development trainer uses the pinned Qwen3-0.6B, MLX-LM 0.31.3 / MLX 0.32.2,
separate locked Transformers export environment and pinned llama.cpp runtime.
All examples are invented development text pending human German-language review.
No participant recording, final holdout or calendar operation was used.

The proof dataset has 28 training and 10 separate validation scenario families,
one case each. Two epochs perform 28 Adam steps with rank-8 LoRA on four layers,
learning rate 0.0001 and zero dropout. No sequence was truncated. The expanded
prepared dataset has four parameter combinations per family (152 cases); these
are still 38 families, not 152 independent dialogues.

Run `assistant-resume-proof-002` paused after the first atomic epoch checkpoint,
then resumed in a new process. `assistant-continuous-proof-002` ran uninterrupted.
All 171 adapter/optimizer/random tensors, final selection state and complete
validation outputs match exactly. Restoring the random state also reproduces 32
random draws. Checkpoint publication ignores incomplete directories; a portable
regression rejects altered optimizer data. A subsequent real SIGTERM proof is recorded below.

The initial proof run (`001`) exposed MLX 0.32's read-only random-state sentinel.
It is preserved as failed evidence. Run `002` restores the two-word Threefry key
through the public 64-bit seed API and checks its exact round trip. See the pinned
[MLX random implementation](https://github.com/ml-explore/mlx/blob/v0.32.2/python/src/random.cpp)
and [MLX-LM training implementation](https://github.com/ml-explore/mlx-lm/blob/v0.31.3/mlx_lm/tuner/trainer.py).

The selected second-epoch adapter was fused, its tokenizer semantically checked
and restored byte-for-byte from the pin, then exported to F16 GGUF. All ten
complete greedy answers match between adapter, fused MLX model and the GGUF
runtime. This replaces the earlier first-token-only check for this artifact.
Untuned/tuned GGUF execution alternates per case; the elapsed process times are
not a device latency benchmark.

| Desktop GGUF route | Valid schema | Exact operation | Unsafe proposed mutation |
|---|---:|---:|---:|
| Untuned | 5/10 | 1/10 | 2/10 |
| Tuned | 10/10 | 4/10 | 1/10 |

The untuned MLX training baseline separately produced 3/10 schema-valid and 0/10
exact outputs. It is not interchangeable with the GGUF baseline. The tuned
adapter/fusion/runtime outputs agree, but the candidate still fails quality
acceptance. Nothing was executed or promoted. Physical iOS runtime, real dialogues,
German listening, resource/latency and comprehension gates remain open.

The [artifact card](../registry/assistant-resume-proof-002.json) records hashes,
denominators, full-answer parity and limits. Private weights and detailed outputs
remain under `.local/runs/assistant-resume-proof-002`.

## Mid-epoch termination and replay

`make verify-assistant-interruption` copies the first complete checkpoint into a
new ignored proof run, validates lineage and starts only its own trainer process.
`assistant-sigterm-proof-001` sends SIGTERM after step 16 (two steps into epoch two).
The process exits with -15 before publishing epoch two; the first checkpoint retains
its exact hash. A new process resumes from the complete epoch and replays it.
All 171 adapter/optimizer/random tensors and validation outputs match the original
uninterrupted two-epoch run, including the 32-draw random-state round trip.
The model card records the interruption receipt and complete parity report.

```sh
make verify-assistant-interruption \
  SOURCE_RUN=.local/runs/assistant-resume-proof-002 \
  CONTINUOUS_RUN=.local/runs/assistant-continuous-proof-002 \
  RUN=.local/runs/assistant-sigterm-proof-001
```

Choose a new `RUN` directory when repeating the proof. Existing runs/checkpoints
are never overwritten. This verifies recovery, not model quality or iOS deployment.
