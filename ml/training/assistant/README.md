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

These agent-authored examples await human German-language review. They are not
independent test dialogues. The smoke trainer does not yet provide optimizer-state
resume, validation stopping, a full corpus, capability selection or iOS deployment.
The fusion probe checks only the greedy next token, not complete-answer parity.
See [the experiment and limits](../../experiments/2026-09-26-s16-assistant-compatibility.md).
