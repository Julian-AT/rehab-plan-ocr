"""Summarize paired, physical-device voice trials; never promote an artifact.

Input consists of reviewed measurement records, not transcripts. Metrics include
failed turns and endpoint waiting. Synthetic/simulator runs remain useful controls
but cannot pass release gates. This audits supplied evidence, not its authenticity.
"""

import argparse
import hashlib
import json
import math
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
SCENARIOS = {
    "airplane_after_setup_and_reboot",
    "missing_assets",
    "intelligence_disabled",
    "microphone_denied",
    "bluetooth_change",
    "phone_interruption",
    "background_foreground",
    "silence",
    "background_speech",
    "quiet_speech",
    "long_pause",
    "repeated_correction",
    "dst",
    "midnight",
    "stale_calendar_selection",
    "memory_pressure",
    "combined_workload",
    "sustained_thermal",
    "spoken_interruption",
    "repeat_return_to_listening",
}
COUNTS = (
    "critical_field_errors",
    "wrong_target_writes",
    "unconfirmed_writes",
    "fabricated_facts",
    "empty_turns",
    "stuck_turns",
    "stale_results",
)


def number(value):
    if (
        isinstance(value, bool)
        or not isinstance(value, (int, float))
        or not math.isfinite(value)
        or value < 0
    ):
        raise ValueError("Measurements must be finite nonnegative numbers")
    return value


def p95(values):
    return sorted(values)[math.ceil(len(values) * 0.95) - 1] if values else None


def summarize(run):
    if run.get("schema_version") != 1 or not run.get("turns"):
        raise ValueError("A schema-1 trial with turns is required")
    artifact = run["artifact"]
    for key in (
        "provider",
        "provider_version",
        "runtime_version",
        "hardware",
        "os_version",
        "conversion_settings",
    ):
        if not isinstance(artifact.get(key), str) or not artifact[key]:
            raise ValueError(f"Missing artifact identity: {key}")
    if type(artifact.get("system_managed")) is not bool:
        raise ValueError("System-managed identity must be explicit")
    if not artifact["system_managed"]:
        digest = artifact.get("model_sha256", "")
        if len(digest) != 64 or any(c not in "0123456789abcdef" for c in digest):
            raise ValueError("Converted artifacts require their model hash")
    rows = run["turns"]
    keys = set()
    groups = {}
    sources = {}
    sums = dict.fromkeys(COUNTS, 0)
    warm, cold, stops, spoken_stops, feedback, memory, energy = [], [], [], [], [], [], []
    tasks = clarifications = unnecessary = raw_success = raw_count = 0
    physical = True
    incomplete_timings = False
    for cycle_index, row in enumerate(rows):
        if type(row.get("cycle_index")) is not int or row["cycle_index"] != cycle_index:
            raise ValueError("Consecutive cycle indices are required")
        key = (row["case_id"], row["repeat"])
        if key in keys or type(row["repeat"]) is not int or row["repeat"] < 0:
            raise ValueError("Case/repeat identities must be unique")
        keys.add(key)
        for field in ("speaker_id", "dialogue_id", "source_sha256"):
            if not isinstance(row.get(field), str) or not row[field]:
                raise ValueError(f"Missing grouping/provenance: {field}")
        if len(row["source_sha256"]) != 64 or any(
            c not in "0123456789abcdef" for c in row["source_sha256"]
        ):
            raise ValueError("Invalid source digest")
        if row["partition"] not in {"development", "holdout"}:
            raise ValueError("Unknown partition")
        for group in (
            "speaker_" + row["speaker_id"],
            "dialogue_" + row["dialogue_id"],
            "source_" + row["source_sha256"],
        ):
            if groups.setdefault(group, row["partition"]) != row["partition"]:
                raise ValueError("Related speech crosses development/holdout partitions")
        if sources.setdefault(row["case_id"], row["source_sha256"]) != row["source_sha256"]:
            raise ValueError("Source changed between repeats")
        for field in COUNTS:
            if type(row[field]) is not int or row[field] < 0:
                raise ValueError("Failure counts must be nonnegative integers")
            sums[field] += row[field]
        for field in (
            "task_success",
            "clarified",
            "unnecessary_clarification",
            "physical_device",
            "natural_speech",
            "human_reviewed",
        ):
            if type(row[field]) is not bool:
                raise ValueError("Trial flags must be explicit booleans")
        physical &= (
            row["physical_device"]
            and row["natural_speech"]
            and row["human_reviewed"]
            and row["partition"] == "holdout"
        )
        tasks += row["task_success"]
        if row["raw_model_success"] is not None:
            if type(row["raw_model_success"]) is not bool:
                raise ValueError("Raw model result must be boolean or null for rules-only turns")
            raw_success += row["raw_model_success"]
            raw_count += 1
        clarifications += row["clarified"]
        unnecessary += row["unnecessary_clarification"]
        if row["unnecessary_clarification"] and not row["clarified"]:
            raise ValueError("Unnecessary clarification must also count as clarification")
        if row["temperature"] not in {"warm", "cold"}:
            raise ValueError("Every turn must identify cold/warm start")
        if row.get("meaningful_audio_ms") is None:
            incomplete_timings = True
        else:
            # speech_end_ms is annotated actual speech end, BEFORE endpoint waiting.
            duration = number(row["meaningful_audio_ms"]) - number(row["speech_end_ms"])
            if duration < 0:
                raise ValueError("Playback precedes annotated speech end")
            (warm if row["temperature"] == "warm" else cold).append(duration)
        feedback.append(number(row["microphone_feedback_ms"]))
        if row.get("explicit_stop_ms") is not None:
            stops.append(number(row["explicit_stop_ms"]))
        if row.get("spoken_interruption_ms") is not None:
            spoken_stops.append(number(row["spoken_interruption_ms"]))
        memory.append(number(row["peak_memory_mb"]))
        energy.append(number(row["energy_mj"]))
    scenarios = run.get("scenarios", {})
    gate_failures = []
    if not physical:
        gate_failures.append("not_reviewed_heldout_natural_physical_speech")
    if len(rows) < 100 or any(
        sums[field] for field in ("empty_turns", "stuck_turns", "stale_results")
    ):
        gate_failures.append("100_reliable_cycles")
    if tasks / len(rows) < 0.95:
        gate_failures.append("task_success_below_95_percent")
    if any(
        sums[field] for field in ("wrong_target_writes", "unconfirmed_writes", "fabricated_facts")
    ):
        gate_failures.append("unsafe_or_ungrounded_result")
    if incomplete_timings or not warm or not cold or p95(warm) > 3_000 or p95(cold) > 5_000:
        gate_failures.append("end_to_audio_latency")
    if max(feedback) > 150:
        gate_failures.append("microphone_feedback")
    if not stops or max(stops) > 250:
        gate_failures.append("explicit_stop_latency")
    if not spoken_stops:
        gate_failures.append("spoken_interruption_unmeasured")
    if any(scenarios.get(name) != "passed" for name in SCENARIOS):
        gate_failures.append("environment_or_sustained_coverage")
    return {
        "artifact": artifact,
        "turn_count": len(rows),
        "distinct_cases": len(sources),
        "speaker_count": len({r["speaker_id"] for r in rows}),
        "dialogue_count": len({r["dialogue_id"] for r in rows}),
        "task_success_rate": tasks / len(rows),
        "raw_model_success_rate": raw_success / raw_count if raw_count else None,
        "raw_model_count": raw_count,
        "clarification_rate": clarifications / len(rows),
        "unnecessary_clarification_rate": unnecessary / len(rows),
        "failures": sums,
        "warm_p95_ms": p95(warm),
        "cold_p95_ms": p95(cold),
        "explicit_stop_max_ms": max(stops, default=None),
        "spoken_interruption_p95_ms": p95(spoken_stops),
        "spoken_interruption_count": len(spoken_stops),
        "peak_memory_mb": max(memory),
        "mean_energy_mj": sum(energy) / len(energy),
        "release_gate_failures": gate_failures,
        "observed_gates_passed": not gate_failures,
        "qualified": False,
        "promotion": "requires_review_of_paired_independent_evidence",
    }


def paired(baseline, candidate):
    def index(run):
        return {(r["case_id"], r["repeat"]): r for r in run["turns"]}

    before, after = summarize(baseline), summarize(candidate)
    left, right = index(baseline), index(candidate)
    if left.keys() != right.keys():
        raise ValueError("Candidates must cover the same case/repeat pairs, including failures")
    fields = ("source_sha256", "speaker_id", "dialogue_id", "partition", "temperature")
    if any(left[key][field] != right[key][field] for key in left for field in fields):
        raise ValueError("Paired source, grouping or warm/cold conditions differ")
    regressions = [
        list(key) for key in left if left[key]["task_success"] and not right[key]["task_success"]
    ]
    return {
        "baseline": before,
        "candidate": after,
        "task_regressions": regressions,
        "default_provider_changed": False,
        "decision": "retain_incumbent_pending_review",
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("baseline", type=Path)
    parser.add_argument("candidate", type=Path)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    output = args.output.resolve()
    if not output.is_relative_to(ROOT / ".local") or output.exists():
        raise ValueError("Choose a new private output below .local")
    inputs = [path.read_bytes() for path in (args.baseline, args.candidate)]
    result = paired(*(json.loads(data) for data in inputs))
    result["input_sha256"] = [hashlib.sha256(data).hexdigest() for data in inputs]
    output.parent.mkdir(parents=True, exist_ok=True)
    with output.open("x") as stream:
        json.dump(result, stream, indent=2)
        stream.write("\n")
    output.chmod(0o600)


if __name__ == "__main__":
    main()
