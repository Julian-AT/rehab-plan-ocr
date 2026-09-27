# Assistant output branches

The physical-phone probe reproduced post-generation rejection of two basic
conversational questions in build 2026092703. Plain and small guided generation
worked. Raw failed output was not captured, so the exact conflicting field is
unknown.

Build 2026092704 uses a guided enum with one payload per interpretation action.
A conversation reply cannot also populate a calendar query, change or plan.
Calendar reads have their own calendar/clarify schema. Both map into the existing
validated interpretation boundary; current-request checks, live calendar reads,
and visible write confirmation still apply. Instructions explicitly distinguish
an empty previous-results page from a calendar with no appointments and describe
the app's actual capabilities. Victoria, microphone handling and presentation are
unchanged.

Provider regression checks cover branch conversion, invalid reply/field rejection,
unsupported deletion requests, deadlines and obsolete results. Voice-flow and the
37 shared assistant-boundary cases pass. Lint and the personal simulator build
pass. The private launch-only probe now retains generated output only for fixed
synthetic questions, alongside actual-router results. Phone generation and spoken
conversation still require verification; these host checks do not establish them.

Private evidence: `.local/runs/assistant-branches-20260927-001/`.

The signed 2704 package was installed in place from source `46359e8`; SHA-256
`a180d9193bd58dc4bc7f0c1ec378c8f2f5ad448c8c0b34b1888b2b9c5a087acf`.
All signatures, profiles and pinned Victoria files passed verification. The strict
post-install comparison found all 17 tables, schema 11, preferences and durable
files unchanged. The phone probe subsequently completed and normal launch succeeded.

Actual-router results: greeting and small talk succeeded; appointment count and
the exact-rule appointment list succeeded; negated deletion was safely clarified.
Capabilities, first appointment tomorrow and free time tomorrow unnecessarily
clarified. Raw synthetic output explains two failures: the capability question
generated an unrelated create proposal (blocked by current-request validation),
and the first-appointment search omitted the date and invented a generic title
filter. This build is not qualified for natural conversation despite structural
validation no longer throwing. It executed no calendar operations.

The 2705 follow-up classifies a request before generating its task-specific
payload. General answers use only a reply field; calendar extraction uses focused
instructions and the deterministic date interpretation already enforced by the
validator. A conflicting output is still rejected, never overwritten. Mutation
generation requires the current utterance to pass the existing explicit-intent
check first. Both model stages remain within one router deadline and cancellation
scope. Phone evaluation adds alternate phrasings rather than counting only the
original examples. Private evidence: `.local/runs/assistant-focused-20260927-001/`.

Build 2705 (source `bc10c8f`) was signed, installed in place, and checked against a
fresh backup: existing data remained unchanged. The physical phone completed the
expanded probe and reopened normally. All five conversational questions produced
replies in 0.82–1.28 seconds through the actual router. Exact-rule calendar queries
and negated-change rejection still passed. Three natural calendar questions still
unnecessarily clarified; raw generation omitted the requested date and introduced
an unrequested therapy filter. These are development examples, not a held-out
natural-dialogue evaluation or end-to-end speech latency measurement.

Build 2706 adds complete, anchored patterns for natural date placement in
first/next appointment, free-time and day-list questions. Extra constraints and
invalid dates still leave the exact-rule path. A distinct `first` detail includes
earlier appointments in the requested period, while `next` retains its upcoming
meaning. Model-generated calendar filters must occur in the current request;
generic appointment words cannot silently become title filters. This blocks false
empty-calendar answers from invented constraints. Raw model scores remain separate
from rule/router results; broader extraction quality is not qualified.
