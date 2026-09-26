"""Freeze reviewed source groups before augmentation, without granting training use."""

import argparse
import hashlib
import json
from pathlib import Path


def partition(entries, review):
    ids = [entry["id"] for entry in entries]
    if not ids or len(set(ids)) != len(ids) or set(review) != set(ids):
        raise ValueError("Every unique intake source needs one reviewed assignment")
    parents = {key: key for key in ids}

    def root(key):
        while parents[key] != key:
            parents[key] = parents[parents[key]]
            key = parents[key]
        return key

    owners = {}
    for entry in entries:
        item = review[entry["id"]]
        if item["partition"] not in {"development", "holdout"}:
            raise ValueError("Unsupported partition")
        fields = (
            ("speaker_id", "dialogue_id")
            if entry["kind"] == "speech"
            else ("plan_id", "revision_family", "layout_family")
        )
        if any(not isinstance(item.get(field), str) or not item[field] for field in fields):
            raise ValueError("Speaker/dialogue or plan/revision/layout relationships are required")
        if entry["kind"] == "speech" and item["speaker_id"] != entry["speaker_id"]:
            raise ValueError("Reviewed speaker differs from intake")
        relations = [f"{field}:{item[field]}" for field in fields]
        relations += ["intake:" + group for group in entry["related_ids"]]
        relations += ["sha256:" + entry["source_sha256"]]
        for relation in relations:
            prior = owners.setdefault(relation, entry["id"])
            parents[root(entry["id"])] = root(prior)
    components = {}
    for key in ids:
        components.setdefault(root(key), []).append(key)
    groups = []
    for members in sorted(sorted(members) for members in components.values()):
        assignments = {review[key]["partition"] for key in members}
        if len(assignments) != 1:
            raise ValueError("Related sources cross development and untouched holdout")
        groups.append({"members": members, "partition": assignments.pop()})
    return {
        "schema_version": 1,
        "groups": groups,
        "before_augmentation": True,
        "training_authorized": False,
        "purpose_authority": "original_intake_receipts_only",
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("intake", type=Path)
    parser.add_argument("review", type=Path)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    raw, review = args.intake.read_bytes(), args.review.read_bytes()
    intake = json.loads(raw)
    if (
        intake.get("schema_version") != 1
        or intake.get("status") != "awaiting_privacy_and_reference_review"
    ):
        raise ValueError("A completed local intake is required before freezing")
    for entry in intake["entries"]:
        path = (args.intake.parent / entry["local_path"]).resolve(strict=True)
        if not path.is_relative_to(args.intake.parent.resolve()):
            raise ValueError("Source outside private intake")
        if hashlib.sha256(path.read_bytes()).hexdigest() != entry["source_sha256"]:
            raise ValueError("Intake source changed before freezing")
    result = partition(intake["entries"], json.loads(review))
    result.update(
        intake_sha256=hashlib.sha256(raw).hexdigest(),
        review_sha256=hashlib.sha256(review).hexdigest(),
    )
    output = args.output.resolve()
    private = Path(__file__).resolve().parents[3] / ".local"
    if not output.is_relative_to(private) or output.exists():
        raise ValueError("Choose a new output below .local; frozen groups are immutable")
    output.parent.mkdir(parents=True, exist_ok=True)
    with output.open("x") as stream:
        json.dump(result, stream, indent=2)
        stream.write("\n")
    output.chmod(0o600)


if __name__ == "__main__":
    main()
