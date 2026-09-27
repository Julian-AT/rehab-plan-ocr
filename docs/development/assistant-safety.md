# Conversation interpretation and confirmation

The conversation model captures the current request context, resolves bounded
calendar references and accepts only validated interpretation records. A provider
can propose an action; it cannot bypass the visible confirmation button. The
ordinary core revision checks and calendar write journal remain authoritative.

Rules may fully answer a supported request. Optional provider results must match
the current operation and schema, reject extra/invalid fields and respect deadlines,
cancellation and stale context. Ambiguous targets require clarification. Partial,
truncated or cancelled output is not a complete answer. Typed diagnostics record
fixed categories instead of calendar content or arbitrary exception strings.

`make test-voice-flow` exercises the real conversation state machine with controlled
effects. `test-assistant-request`, `test-custom-assistant-provider`,
`test-conversation-replies`, `test-calendar-answers` and contract probes retain
rejection cases. The evaluator binds the current rule identity; historical scores
must retain their original provider identity instead of being silently relabeled.

The [integrated experimental trial](assistant-voice-trial.md) adds actual model
inference and playback but substitutes scripted recognition. The
[device protocol](../../ml/evaluation/conversation/DEVICE-QUALIFICATION.md) is a
separate qualification step. Source cleanup does not qualify any model.
