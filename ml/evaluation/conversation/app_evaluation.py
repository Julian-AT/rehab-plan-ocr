"""Prepare invented development inputs and audit actual app interpretation observations."""

import math

from ml.evaluation.conversation.intent import InvalidIntent, validate
from ml.evaluation.conversation.paired import clusters
from ml.training.assistant.contract import validate_dataset

RULES_MODEL_IDENTITY = "calendar-5"


def prepare(path, run_id, mode):
    data = validate_dataset(path)
    # Participant material requires a separate approved intake/review route.
    if data["kind"] != "invented-development-dialogues" or mode not in {"rules", "apple", "custom"}:
        raise ValueError("Use invented development data and an explicit provider mode")
    rows = [row for row in data["samples"] if row["partition"] == "validation"]
    if not 1 <= len(rows) <= 200:
        raise ValueError("Use 1–200 complete validation cases")
    cases = []
    for row in rows:
        context = row["context"]
        refs = context["visible_references"]
        if set(context) - {"today", "timezone", "visible_references", "selected"} or (
            context.get("selected") != (refs[0] if len(refs) == 1 else None)
        ):
            raise ValueError("The app adapter cannot preserve this context without loss")
        cases.append(
            dict(
                id=row["id"],
                text=row["utterance"],
                today=context["today"],
                timezone=context["timezone"],
                references=refs,
                selected=context.get("selected"),
            )
        )
    return dict(run_id=run_id, mode=mode, cases=cases), rows


def evaluate(result, fixture, rows, model_identity):
    mode = fixture["mode"]
    providers = {
        "rules": "complete-rules",
        "apple": "apple-intelligence",
        "custom": "custom-qwen-trial",
    }
    if (
        result.get("run_id") != fixture["run_id"]
        or result.get("mode") != mode
        or result.get("stage") != "evaluated"
        or result.get("qualified") is not False
        or type(result.get("calendar_operations")) is not int
        or result["calendar_operations"] != 0
        or result.get("provider") != providers[mode]
        or not isinstance(result.get("model_identity"), str)
        or not result["model_identity"]
        or (mode == "custom" and result["model_identity"] != model_identity)
        or (mode == "rules" and result["model_identity"] != RULES_MODEL_IDENTITY)
    ):
        raise ValueError("Stale, incomplete or wrong-provider app evaluation")
    observations = result.get("cases")
    if (
        not isinstance(observations, list)
        or not all(isinstance(row, dict) for row in observations)
        or [r.get("id") for r in observations] != [r["id"] for r in fixture["cases"]]
        or [r["id"] for r in rows] != [r["id"] for r in fixture["cases"]]
    ):
        raise ValueError("Every validation case must be observed exactly once in fixture order")
    cases = []
    for observed, row in zip(observations, rows, strict=True):
        status = observed.get("status")
        seconds = observed.get("interpretation_seconds")
        if status not in {"interpreted", "no_match", "unavailable", "error"} or (
            type(seconds) not in {int, float} or not math.isfinite(seconds) or seconds < 0
        ):
            raise ValueError("Invalid observation status or duration")
        record = dict(
            id=row["id"],
            family=row["family"],
            expected=row["expected"],
            observation=observed,
            schema_valid=False,
            exact_match=False,
            unsafe_proposed_mutation=False,
        )
        if status == "interpreted":
            provider = observed.get("provider")
            if provider not in {"complete-rules", providers[mode]} or observed.get(
                "model_identity"
            ) != (
                RULES_MODEL_IDENTITY if provider == "complete-rules" else result["model_identity"]
            ):
                raise ValueError("Observed provider changed during evaluation")
            operation = observed.get("operation")
            if type(operation) is not dict:
                raise ValueError("Missing app operation")
            try:
                validate(operation, references=row["context"]["visible_references"])
                record["schema_valid"] = True
                record["exact_match"] = operation == row["expected"]
            except InvalidIntent as error:
                record["rejection"] = str(error)
            # Preserve unsafe proposals even when extra app constraints cause the
            # compact-schema check to reject this otherwise executed interpretation.
            record["unsafe_proposed_mutation"] = (
                operation.get("action") in {"create", "update", "remove"}
                and not record["exact_match"]
            )
        elif "operation" in observed:
            raise ValueError("Uninterpreted observations cannot contain an operation")
        elif status == "no_match" and mode != "rules":
            raise ValueError("Only rules-only evaluation can report no rule match")
        cases.append(record)
    return dict(
        cases=cases,
        requested_cases=len(rows),
        status_counts={
            status: sum(c["observation"]["status"] == status for c in cases)
            for status in ["interpreted", "no_match", "unavailable", "error"]
        },
        exact_matches=sum(c["exact_match"] for c in cases),
        schema_valid=sum(c["schema_valid"] for c in cases),
        unsafe_proposed_mutations=sum(c["unsafe_proposed_mutation"] for c in cases),
        dependency_components=clusters(rows),
        timing_scope="interpretation only; simulator observations, not end-to-end or paired latency",
        qualified=False,
    )
