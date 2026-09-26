# Physical conversation qualification

`device_qualification.py BASELINE.json CANDIDATE.json --output .local/runs/NAME/report.json`
audits **reviewed measurements**, not audio authenticity. It never downloads,
installs or promotes a model. Inputs must contain every paired turn, including
failed turns; silence/failure cannot disappear from timing or task denominators.
Keep raw recordings and reports private. A clean report still requires review of
independent held-out evidence before changing the incumbent.

Schema 1 input:

- `artifact`: provider, provider_version, runtime_version, hardware, os_version,
  conversion_settings (nonempty strings), system_managed (boolean), and model_sha256
  for non-system artifacts. Record the actual iPhone and runtime, not desktop export
  parity. System assets use the OS identity because their weight hash is unavailable.
- `turns`: ordered records with consecutive zero-based cycle_index, case_id,
  repeat (nonnegative integer), speaker_id, dialogue_id, source_sha256, and partition
  (`development` or `holdout`). Use the same immutable source and conditions for
  each paired candidate; related sources must stay in the same partition.
- Each turn has explicit task_success, clarified, unnecessary_clarification,
  physical_device, natural_speech and human_reviewed booleans. raw_model_success
  is a boolean for a model attempt, or null for rules-only turns. Score the raw
  output before the app's validation separately from the resulting app behavior.
- Each turn counts critical_field_errors, wrong_target_writes, unconfirmed_writes,
  fabricated_facts, empty_turns, stuck_turns and stale_results as nonnegative integers.
- `temperature` is `cold` or `warm`. speech_end_ms and meaningful_audio_ms use the
  same monotonic clock origin. Annotate actual speech end **before** endpoint
  waiting; first bytes or a generic filler are not meaningful audio. A missing
  answer uses null meaningful_audio_ms and fails the timing gate.
- microphone_feedback_ms measures action-to-feedback, explicit_stop_ms measures
  button-to-silence, and spoken_interruption_ms measures actual speech-onset-to-silence.
  Stop values may be null on turns without that action; at least one measurement of
  each kind is required. Report spoken interruption separately; it has no invented
  250 ms release threshold. Include measured peak_memory_mb and energy_mj per turn.
- `scenarios` maps every name in `SCENARIOS` to its reviewed outcome (`passed` to
  satisfy coverage). Keep the supporting thermal, route and interruption traces
  alongside the inputs. A status string alone is not independent evidence.

Nearest-rank p95 includes endpoint waiting. Incomplete timings, fewer than 100
consecutive cycles, task success below 95%, unsafe writes/facts, missing scenarios,
or exceeding the user's feedback/stop/cold/warm targets fail the observed gates.
Distinct case, speaker and dialogue counts prevent repeats from being hidden.
The tool always returns qualified=false and retains the incumbent pending review.
It is a conversation audit, not an OCR, listening-quality or battery qualification.

## Freeze source groups before augmentation

Use the existing local intake first. Evaluation permission does not permit training:
both the receipt and each speech entry must explicitly include `asr_training` or
`assistant_training` to authorize that purpose. `speech_evaluation` remains separate.
No existing receipt is broadened by these tools.

`ml/data/annotation/freeze_groups.py INTAKE/manifest.json REVIEW.json --output
.local/runs/NAME/frozen-groups.json` verifies source hashes and freezes reviewed
assignments. REVIEW maps every intake ID to partition plus speaker_id/dialogue_id
for speech, or plan_id/revision_family/layout_family for documents. Connected groups
include duplicate source hashes and intake relationships; transitive connections
cannot cross partitions. Every augmentation must inherit its original frozen group.
The output records the hashes of intake and review, cannot overwrite an existing
freeze, and grants no additional data-use permission.

The unit fixtures are invented measurements for parser/gate tests. They are not
published as evaluation results and do not satisfy physical-device acceptance.
