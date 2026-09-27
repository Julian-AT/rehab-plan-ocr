# Conversation evaluation

`compare.py` evaluates the original invented smoke corpus. The later resumable
trainer's `export.py` records complete adapter/fused/baseline/GGUF answers in
`deployment/parity.json`. Neither route establishes real-dialogue quality.

Audit that recorded development comparison without repeating inference:

```sh
make audit-assistant-pairs \
  RUN=.local/runs/assistant-development-001 \
  MODEL_CARD=ml/registry/assistant-development-001.json \
  OUTPUT=.local/runs/assistant-paired-<new>
```

To isolate backend and batch settings on previously failed export cases:

```sh
make diagnose-assistant-parity \
  RUN=.local/runs/assistant-development-001 \
  DIAGNOSTIC_RUN=.local/runs/assistant-backend-parity-<new>
```

This offline diagnostic verifies the selected checkpoint, retained prompts, GGUF,
export receipt and pinned llama.cpp executable before repeating inference. It
compares automatic backend selection with explicit CPU execution, then changes
the CPU batch/microbatch sizes to the native adapter's 512/128. Environment
overrides for llama.cpp are excluded. Case order rotates the three variants;
raw outputs, errors, arguments and hashes stay in a new private directory.
Original parity evidence is never replaced. A successful diagnostic command means
the comparison completed, not that answers agree or a model qualifies. It uses
only earlier failures, adds no independent examples and cannot establish full
parity, iOS execution or physical latency. The historical
[six-case result](../../experiments/findings.md) reproduced
all six failures with each configuration. It used the old CLI file boundary,
which removed a final newline; the prompt-boundary diagnosis below supersedes
its interpretation without rewriting the retained evidence.

All desktop evaluators now use `--binary-file --no-escape`, preserving the full
rendered template, including final newlines and JSON backslashes. `-f` silently
removes one final newline in the pinned runtime. Equal input-token counts do not
prove identical inputs: the affected template ends in token 271 (two LF), whereas
that old boundary passed token 198 (one LF).

The completed token-level investigation found 38/40 matching answers for the older
candidate after repairing the prompt boundary. The two remaining differences
preserved the failed strict gate. Its one-off runner and commands are retired;
see [findings](../../experiments/findings.md) and
[source recovery](../../../docs/development/recovery.md). Current full export and
paired evaluation remain supported through the commands above.

The audit checks model-card/run/settings/dataset hashes, verifies the original
decoder/contract, covers every validation case exactly once and redecodes every
recorded answer. It recomputes counts and complete-text parity. Outputs are new,
immutable local reports; no training environment, model loading or calendar access
is required. It never opens a final holdout or qualifies a release.

Each baseline/candidate pair retains all declared family, scenario, paraphrase and
speaker relationships, including transitive links. Counts describe cases; related
cases do not increase the independent-group count. When at least two connected
groups exist, a fixed-seed percentile bootstrap resamples whole groups with
replacement, using the same draws for both providers. It reports case-weighted
rate differences and nearest-rank 2.5/97.5 percentiles over 10,000 draws. Positive
deltas improve exact/schema scores but worsen unsafe-proposal rates.

This is an exploratory grouped adaptation of paired resampling, whose general
evaluation motivation is described by [Koehn (2004)](https://aclanthology.org/W04-3250/).
Small selected development sets, declared rather than demonstrated independence,
population coverage and multiple comparisons limit interpretation. Zero-width
intervals are not proof of equivalence or zero risk. With fewer than two groups,
intervals are explicitly unavailable. The current invented corpus has ten
families but a single shared speaker-group label; the audit preserves that label.

Case-level records identify newly unsafe proposed mutations, lost correct
operations, new schema rejections and changed incorrect structured operations.
The last category is deliberately conservative: a different wrong operation
requires review even if the previous answer was also wrong. Better totals cannot
erase these records. Real German review, unseen dialogues, paired shipping-device
measurements and full voice/UI acceptance remain separate gates.

The experimental simulator app also evaluates every validation case through its
actual `InterpretationRouter`, selected provider and typed output boundary:

```sh
make build-assistant-trial
make test-assistant-app-trial TEST_ARGS='--run .local/runs/<new-run> --simulator <disposable-id> --dataset .local/datasets/assistant-development-001/dataset.json --mode custom'
```

Repeat serially with distinct output directories and `--mode rules` or `--mode apple`.
To evaluate the preserved untuned export, first run
`make build-assistant-trial ASSISTANT_TRIAL_MODEL=untuned`, then use `--mode custom`
with another output directory. The receipt identifies which registered GGUF was
bundled. Omit the build selector (or use `tuned`) to restore the tuned trial.
Rules mode records unmatched inputs; Apple/custom modes retain the normal complete
rule routing before generation. Availability, errors, the actual per-case provider,
all requested cases and dependency groups remain visible. An unavailable Apple model
is not a measured Apple answer. No expected answer enters the app fixture.

The adapter accepts only invented development data whose complete context it can
preserve. A unique previous-page selection can resolve a rule's conversational
reference; ambiguous selection or unsupported context is refused. App constraints
outside the compact model schema remain extra output fields and fail the schema/
exact-operation check instead of disappearing. An incorrect proposed mutation is
flagged even when such extra fields make the compact representation invalid.

Reports retain dataset/fixture/build/source/output hashes. Each case has a fresh
30-second request deadline; weights may remain warm within a run. These serial
simulator observations establish neither interleaved paired latency nor complete
voice/calendar behavior. The probe opens no application database or audio session
and performs no calendar operation. It covers the interpretation router; the
`VoiceModel` state machine and its earlier mutation/cancellation rules are outside
this segment. Thus `rules` means the router's complete calendar-question rules,
not every rule used in a full conversation. No result promotes a model. Human
review, eligible Apple hardware and physical end-to-end measurements remain required.
