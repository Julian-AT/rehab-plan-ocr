> Historical record: technical findings retained from the archived development sequence. Project dates, build labels and source references have been normalized. This record is not a new test, delivery approval or signing attestation; unaltered evidence and original validity dates are held in the external private archive.

# Local interpretation providers

`InterpretationProvider` is the app's common contract for complete calendar rules
and Apple Intelligence, plus an explicitly experimental custom GGUF provider.
The router selects one provider before generation. It
does not race providers or reinterpret a failed generation with another model.
Calendar queries, event selection and mutation confirmation remain downstream.

| Contract | Meaning |
|---|---|
| Identity | Provider name, observable model identity and output schema version |
| Capabilities | Calendar interpretation, mutation proposals, general conversation, fixed app help |
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

The compact custom-model schema now has a strict portable Rust decoder and a typed
UniFFI result. Its 33 shared Rust/Python/Swift cases cover duplicate/unknown keys,
null versus missing values, canonical dates/times, visible reference membership,
bounded fields and minimal title/duration changes. Parsing never writes a calendar.
The app adapter preserves timezone and temporal bounds; existing live event and
snapshot checks still run downstream. A known but semantically wrong reference can
pass structural validation, so this boundary does not qualify the model's intent.

Cancellation is an explicit action with no attached query/change. App help selects
a topic from the existing help content, without model-generated explanation text.
The screen and spoken path share the same unchanged German passages. Clarification
retains a typed reason; invalid dates receive a specific correction prompt.

The 30-second generation deadline begins after speech finalization. It does not
shorten microphone endpoint thresholds or natural pauses. The deadline wrapper
returns even if a native implementation has not yet honored cancellation; a late
value cannot affect a subsequent answer. Runtime providers must perform blocking
image/audio/model computation away from the UI actor.

Input/output byte and field limits bound accepted work. On iOS 26.0–26.3, the Apple
provider's existing context recovery removes whole historical turns and retains
the current request. Newer available token-count APIs remain capability-checked.
Prewarming is still an explicit measurement trial, not a default optimization.

`CustomAssistantProvider` renders the exact pinned Qwen no-thinking prompt and
passes complete output through the typed Rust boundary. Context overflow removes
whole oldest history turns, retaining the current request. Missing assets preserve
complete-rule answers. Native model loading/generation and unloading run on the
package's serial background queue; discard frees weights after queued work ends.

Normal builds select Apple and do not link or bundle the custom model. The explicit
`make build-assistant-trial` overlay adds `LocalAssistant` and the verified GGUF to
a separate Debug simulator build. It requires `--assistant-model-trial` to select
the provider. Its manifest pins the model, prompt, native assembly and notices;
its build receipt hashes source files and the app binary. The builder restores the
normal generated Xcode project. Regular release packaging rejects the trial marker.

The provider probe verifies exact-rule fallback, single-provider selection, invalid
output rejection, capability limits, deadline/cancellation with an uncooperative
fake provider and isolation of later answers. The [app trial](../../ml/experiments/2026-09-26-s18-assistant-app-provider.md)
executes the actual provider selection/router in the app binary, with two synthetic
development prompts. It reproduces both known wrong outputs without executing a
calendar operation. It opens neither a calendar database nor an audio session;
this is not a complete spoken interaction. Actual Apple generation, full voice
workflow, paired provider quality/resources and physical-device qualification
remain open. The trained Qwen candidate is not a production provider.
