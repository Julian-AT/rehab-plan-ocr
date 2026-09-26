# Local German assistant development

The fixed base and converter revisions are in `ml/registry/assistant-base.json`.
Weights, downloads, fused models, GGUF files and run logs stay in ignored `.local/`
storage. The training environment uses MLX-LM 0.31.3 / Transformers 5; the separate
conversion environment uses Transformers 4.57.6 and the pinned llama.cpp converter.
Training packages are not app dependencies.

On the configured Apple Silicon development machine:

```sh
make restore-assistant-assets
make build-assistant-runtime
make assistant-smoke RUN=.local/runs/assistant-smoke-new
make evaluate-assistant RUN=.local/runs/assistant-smoke-new
```

Restore is the networked setup step; valid local weights are reused after checksum
verification. Runtime compilation runs with `UV_OFFLINE=1`. Training, fusion,
conversion and evaluation use offline Hugging Face settings. Each run and evaluation
requires a new output directory; previous successes and failures remain intact.

The smoke runner first exports and executes the untuned model, then trains eight
LoRA steps on eight invented German examples, fuses the adapter, preserves the
original tokenizer after semantic identity checks, exports F16 GGUF and executes
that model. Four different scenario families provide a tiny development validation
set. Tokenization checks prompt masking and sequence length before training; no
example is silently truncated. Logs and run identities record pinned checkpoints,
environment locks, dataset, configuration, source hashes, commands and failures.

MLX fusion reserializes the tokenizer with Transformers 5. The pinned converter's
Transformers 4 cannot read that representation. `preserve_tokenizer` verifies the
complete vocabulary, added vocabulary, special IDs and chat template before
copying the byte-identical pinned tokenizer files. Model weights are retained.
This follows the documented [Transformers token metadata changes](https://github.com/huggingface/transformers/blob/main/MIGRATION_GUIDE_V5.md)
and [chat-template serialization](https://github.com/huggingface/transformers/blob/main/docs/source/en/chat_templating_writing.md).

`ml/evaluation/conversation/intent.py` rejects unknown fields, invented factual
answers, unknown references, invalid dates/times, contradictory bounds and stale
mutation fields on cancellation. Only compact intents pass. It does not execute
operations or replace the app's confirmation and snapshot checks. The comparator
records raw outputs and exact expected-operation matches separately for training
and validation examples. Invalid outputs are rejected, not repaired into successes.

These smoke examples await human German-language review. They are not independent
test dialogues. The original smoke runner remains a historical compatibility check;
its fusion probe checks only the greedy next token.
See [the experiment and limits](../../experiments/2026-09-26-s16-assistant-compatibility.md).

The development trainer now provides grouped validation and complete epoch resume:

```sh
make prepare-assistant-data DATASET=.local/datasets/assistant-new
make train-assistant DATASET=.local/datasets/assistant-new RUN=.local/runs/assistant-new
make resume-assistant RUN=.local/runs/assistant-new
make export-assistant RUN=.local/runs/assistant-new
```

`prepare.py` creates 28 training and 10 validation scenario families with versioned
seeds. Related scenarios, paraphrases and speakers cannot cross partitions. The
examples include corrections, negations, pauses represented in text, references,
minimal mutations, missing information, invalid dates and app help. They are
invented, agent-authored development examples pending human review. More parameter
combinations do not increase the number of independent families. No final holdout
is accepted by the trainer. Speech timing requires actual recordings and is not
measured by ellipses in a transcript.

`contract.py` validates expected operations and context visibility before training.
For reviewed input it requires a named reviewer, review date and content hash;
editing the transcript or label invalidates that approval. No workflow grants
approval to generated data. The intent schema includes start/end/count questions
as well as the original smoke query types.

`train.py` masks prompt tokens, disables Qwen thinking, checks every sequence before
training and never truncates labels. Epoch checkpoints atomically preserve adapter
weights, Adam state, random state, validation outputs and hashes. A crashed epoch
replays from the last complete checkpoint. Resume checks source, data, settings,
base weights and environment identity. MLX 0.32 random state is reconstructed using
the public seed API with a checked two-word key round trip. Validation selection
prioritizes unsafe mutations, exact operation errors and family error before loss.
Patience stops training; there is no eight-hour cap. A low-disk reserve protects
existing artifacts. A process lock prevents concurrent writes to one run.

Export verifies the complete receipt of the selected epoch, including its baseline,
run identity, epoch and all checkpoint files. Historical runs retain their original
source hashes: replay requires those recorded sources and the recorded environment.
Changing validation code does not update or relax an existing run's identity;
historical reports and weights remain unchanged.

`verify_resume.py` compares every adapter/optimizer/random tensor, validation
outputs and restored random draws against uninterrupted training. `export.py`
fuses the selected checkpoint, preserves the pinned tokenizer, converts both base
and tuned models to F16 GGUF and compares complete greedy answers for the adapter,
fused model and desktop runtime. Raw answers, strict schema rejection, exact
operations and unsafe mutations remain in the report. Any full-answer parity
difference fails the export gate. A passing export remains experimental until
human dialogue, shipping iOS runtime, resource and latency qualification pass.

`verify_interruption.py` limits each subprocess phase of its two-epoch proof to
30 minutes by default (`--phase-timeout-seconds` changes this proof-only limit).
Silent or incomplete child output still reaches the deadline, child processes are
reaped, and failed proofs retain their logs and checkpoint with a failure report.
The production trainer has no added wall-clock limit.

Desktop prompt files are passed with `--binary-file --no-escape` so llama.cpp
receives the same rendered template as MLX and the native adapter. The previous
`-f` boundary dropped one final LF; historical reports remain immutable. The
[full-corpus token diagnosis](../../experiments/2026-09-26-s18-assistant-token-parity.md)
checks actual input IDs and records remaining numerical differences separately.
