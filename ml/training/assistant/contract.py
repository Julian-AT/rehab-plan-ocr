"""Dataset, prompt and checkpoint-selection contract for local intent adaptation."""

import datetime
import hashlib
import json
import math
import os
import re

from ml.evaluation.conversation.intent import canonical_date, validate

SYSTEM = """Du übersetzt eine deutsche Äußerung in genau ein JSON-Objekt.
Du führst nichts aus. Du beantwortest keine Kalenderfragen mit erfundenen Fakten.
Gültige Formen (nur ausdrücklich benötigte Felder):
{"action":"calendar","query":{"detail":"next|list|count|room|therapist|start|end|duration","date":"YYYY-MM-DD","reference":"ID","after":"HH:mm","before":"HH:mm"}}
Bei calendar muss date oder reference vorhanden sein. IDs stammen ausschließlich
aus visible_references. selected bezeichnet den zuletzt gemeinten Termin.
{"action":"create","change":{"title":"Titel","date":"YYYY-MM-DD","time":"HH:mm","duration":30}}
Bei create sind title, date und time erforderlich; duration ist optional.
{"action":"update","query":{"reference":"ID"},"change":{"title":"Neuer Titel","date":"YYYY-MM-DD","time":"HH:mm","duration":20}}
Bei update enthält change NUR die ausdrücklich geänderten Felder, mindestens eines.
{"action":"remove","query":{"reference":"ID"}}
{"action":"cancel"}
{"action":"help","topic":"capture|calendars|archive|voice|privacy"}
{"action":"clarify","problem":"invalid_date|ambiguous|missing_date|missing_time|missing_title|missing_event|unsupported"}
Die durch | getrennten Wörter sind Alternativen, keine wörtlichen Werte.
Beziehe heute/morgen/übermorgen auf today. Nutze YYYY-MM-DD und HH:mm.
Vormittags bedeutet vor 12:00, nachmittags ab 12:00 und vor 18:00.
Für 'danach' verwende detail next und die reference des ausgewählten Termins.
Bei Korrekturen gilt die zuletzt bestätigte Angabe. Verneinte Änderungen oder
Abbruch ergeben cancel ohne weitere Felder. Ungültige Kalenderdaten ergeben
clarify invalid_date. Fehlende Angaben oder ein unklarer Zieltermin erfordern
clarify. Keine vorhandenen Werte ergänzen, keine Fakten, keine Erklärung,
kein Markdown und keine Bestätigung, dass etwas gespeichert wurde."""


def sha(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def digest(value):
    return hashlib.sha256(
        json.dumps(value, sort_keys=True, ensure_ascii=False, allow_nan=False).encode()
    ).hexdigest()


def write(path, value):
    temporary = path.with_suffix(path.suffix + ".tmp")
    with temporary.open("w") as stream:
        stream.write(json.dumps(value, ensure_ascii=False, indent=2, allow_nan=False) + "\n")
        stream.flush()
        os.fsync(stream.fileno())
    temporary.replace(path)


def references(row):
    return row["context"]["visible_references"]


def messages(row, *, include_answer=True):
    result = [
        {"role": "system", "content": SYSTEM},
        {
            "role": "user",
            "content": json.dumps(row["context"], ensure_ascii=False, sort_keys=True)
            + "\n"
            + row["utterance"],
        },
    ]
    if include_answer:
        result.append(
            {
                "role": "assistant",
                "content": json.dumps(row["expected"], ensure_ascii=False, separators=(",", ":")),
            }
        )
    return result


def validate_dataset(path):
    data = json.loads(path.read_text())
    if data.get("schema_version") != 1 or data.get("kind") not in {
        "invented-development-dialogues",
        "reviewed-development-dialogues",
    }:
        raise ValueError("Unknown assistant dataset contract")
    if data.get("final_holdout") is not False:
        raise ValueError("Final holdout cannot be used for training or checkpoint selection")
    ids, assignments = set(), {}
    for row in data["samples"]:
        if not isinstance(row["id"], str) or not row["id"] or row["id"] in ids:
            raise ValueError("Missing or duplicate sample identity")
        ids.add(row["id"])
        partition = row["partition"]
        if partition not in {"train", "validation"}:
            raise ValueError("Only training and development validation partitions are allowed")
        if not isinstance(row["utterance"], str) or not 1 <= len(row["utterance"]) <= 2000:
            raise ValueError("Missing or overlong German utterance")
        context = row["context"]
        canonical_date(context["today"])
        if context.get("timezone") != "Europe/Vienna":
            raise ValueError("This dataset uses the explicit Europe/Vienna calendar context")
        refs = references(row)
        if (
            not isinstance(refs, list)
            or any(not isinstance(r, str) or not r for r in refs)
            or len(refs) != len(set(refs))
            or ("selected" in context and context["selected"] not in refs)
        ):
            raise ValueError("Selected references must belong to the visible context")
        validate(row["expected"], references=refs)
        for namespace in ["family", "scenario_group", "paraphrase_group", "speaker_group"]:
            value = row.get(namespace)
            if not isinstance(value, str) or not value:
                raise ValueError(f"Missing grouping before augmentation: {namespace}")
            key = (namespace, value)
            if key in assignments and assignments[key] != partition:
                raise ValueError("Related dialogue families or speakers cross partitions")
            assignments[key] = partition
        prompt = digest({"context": context, "text": re.sub(r"\s+", " ", row["utterance"]).strip()})
        if ("prompt", prompt) in assignments:
            raise ValueError("Duplicate prompt would inflate the independent sample count")
        assignments[("prompt", prompt)] = partition
        if data["kind"] == "reviewed-development-dialogues":
            review = row.get("review", {})
            approved = {k: v for k, v in row.items() if k != "review"}
            if (
                review.get("status") != "approved"
                or not review.get("reviewer")
                or review.get("content_sha256") != digest(approved)
            ):
                raise ValueError("Missing or stale human language/operation review")
            datetime.datetime.fromisoformat(review["reviewed_at"])
        elif row.get("provenance") != "agent-authored-invented-development":
            raise ValueError("Invented data cannot silently include participant material")
    if {r["partition"] for r in data["samples"]} != {"train", "validation"}:
        raise ValueError("Nonempty grouped training and validation sets are required")
    return data


def selection(metrics):
    score = [
        metrics["unsafe_mutations"],
        metrics["critical_errors"],
        metrics["family_mean_error"],
        metrics["loss"],
    ]
    if any(not math.isfinite(v) or v < 0 for v in score):
        raise ValueError("Validation must produce finite nonnegative metrics")
    return score


def advance(state, metrics, epoch, patience):
    score = selection(metrics)
    improved = state.get("best_score") is None or score < state["best_score"]
    result = dict(state, epoch=epoch, stale_epochs=0 if improved else state["stale_epochs"] + 1)
    if improved:
        result.update(best_score=score, best_epoch=epoch)
    result["stopped"] = result["stale_epochs"] >= patience
    return result
