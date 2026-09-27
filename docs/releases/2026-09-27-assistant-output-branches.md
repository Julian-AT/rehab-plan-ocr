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
