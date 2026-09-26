> Historical record: technical findings retained from the archived development sequence. Project dates, build labels and source references have been normalized. This record is not a new test, delivery approval or signing attestation; unaltered evidence and original validity dates are held in the external private archive.

# Local interpretation providers

`InterpretationProvider` is the app's common contract for complete calendar rules
and Apple Intelligence. The router selects one provider before generation. It
does not race providers or reinterpret a failed generation with another model.
Calendar queries, event selection and mutation confirmation remain downstream.

| Contract | Meaning |
|---|---|
| Identity | Provider name, observable model identity and output schema version |
| Capabilities | Calendar interpretation, mutation proposals, general conversation |
| Availability | Available or a concrete local capability/setup reason |
| Request | Current text, calendar context, up to six historical turns, reference time and monotonic deadline |
| Result | Typed action/query/change/reply, provider identity and generation duration |
| Cancellation | Task cancellation ends delivery; late native results are rejected |

Calendar context remains serialized at the existing boundary during incremental
replacement of the old transport. The typed query carries date/time bounds and
event references; it carries no model-invented event facts. Typed changes contain
only requested fields. Every provider's output passes structural and capability
validation. Live calendar visibility/identity checks and visible confirmation are
still mandatory before mutations.

Exact complete calendar patterns work when Apple Intelligence is unavailable.
The Apple provider distinguishes ineligible hardware, disabled Intelligence and
assets that are not ready. Its observable identity includes the OS version because
Apple does not expose a weight checksum here; this must not be reported as an
exact model revision. The system provider still uses local `SystemLanguageModel`.

The 30-second generation deadline begins after speech finalization. It does not
shorten microphone endpoint thresholds or natural pauses. The deadline wrapper
returns even if a native implementation has not yet honored cancellation; a late
value cannot affect a subsequent answer. Runtime providers must perform blocking
image/audio/model computation away from the UI actor.

Input/output byte and field limits bound accepted work. On iOS 26.0–26.3, the Apple
provider's existing context recovery removes whole historical turns and retains
the current request. Newer available token-count APIs remain capability-checked.
Prewarming is still an explicit measurement trial, not a default optimization.

The provider probe verifies exact-rule fallback, single-provider selection, invalid
output rejection, capability limits, deadline/cancellation with an uncooperative
fake provider and isolation of later answers. Actual Apple generation, shipping
custom GGUF inference and paired provider quality/resource comparisons remain
separate acceptance gates. The trained Qwen candidates currently fail quality;
they are not registered as production providers.
