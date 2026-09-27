# Additional training for known assistant failure families

This protocol precedes the new training run. The earlier 40 validation cases have
already influenced diagnosis and this expansion. They remain **known development
controls**, not a new holdout, unseen dialogue set or proof of generalization.
No human language approval, participant recording or calendar write is created.

The unchanged original 112 training/40 validation rows are retained byte-for-byte
at the data-value level, with the original source file hash recorded. Twenty added
training families provide eight examples each: short/negated room questions,
follow-ups, corrected dates, upper/lower bounds, optional-duration creations with
explicit dates, minimal updates, cancellation, impossible dates and help. Values
and paired wording vary deterministically. All related new rows stay in training;
the existing synthetic speaker groups remain shared. Parameter combinations do
not count as independent people or conversations. Every review remains pending.

Run **one** Qwen3-0.6B LoRA candidate with the pinned existing base, tokenizer,
prompt, environment, seed and previous training settings: eight adapted layers,
rank eight, scale twenty, no dropout, batch two, learning rate 0.0001, maximum twenty
epochs and patience three. Select lexicographically by unsafe mutations, exact
errors, family error and loss as before. Keep selected and latest complete adapter,
optimizer and random states. No changed score weights, gate or post-hoc checkpoint
selection is allowed. The additional data are the intended intervention.

Before training, portable tests verify unchanged validation, grouping, minimal
fields, date arithmetic including leap day, negative/query distinctions and no
fabricated review. Training/export must use a quiet model window and at least
twenty GiB free storage plus the documented operation allowance. Model artifacts
stay private. Bind sources, environment, inputs and resulting evidence by hashes.

After training, evaluate the unchanged complete development set, fuse the selected
adapter, convert with the pinned native converter, and compare all complete greedy
answers for adapter, fused and native models. Retain every error and any new unsafe
proposal; a better aggregate cannot hide these. Use the corrected binary prompt
boundary. Full-answer export parity is unchanged. A failed gate remains failed.
The public provider selection is unchanged regardless of this development result.

```sh
make prepare-assistant-development-data \
  SOURCE_DATASET=.local/datasets/assistant-development-001/dataset.json \
  DATASET=.local/datasets/assistant-development-002
make train-assistant DATASET=.local/datasets/assistant-development-002 \
  RUN=.local/runs/assistant-development-002
make export-assistant RUN=.local/runs/assistant-development-002
```

Real-plan/dialogue approval, independent evaluation, native app conversation,
physical latency/resources, human listening and final product qualification remain
separate requirements. This experiment cannot complete them.
