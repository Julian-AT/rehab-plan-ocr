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
and performs no calendar operation. No result promotes a model. Human review,
untuned-model comparison through this route, eligible Apple hardware and physical
end-to-end measurements remain required.
