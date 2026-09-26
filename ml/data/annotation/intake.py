"""Copy a reviewed collection into a new private batch; never approve or split it.

The local consent receipt is an operator attestation, not a legal determination.
No content is uploaded, no external original is moved, and no dataset is overwritten.
"""

import argparse
import hashlib
import json
import re
import shutil
from datetime import date, datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
FORMATS = {
    "schedule": {".png", ".jpg", ".jpeg", ".heic", ".heif", ".pdf"},
    "speech": {".wav", ".caf", ".m4a", ".flac"},
}
PURPOSES = {
    "schedule": {"schedule_evaluation", "ocr_training"},
    "speech": {"speech_evaluation"},
}


def sha(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def identifier(value):
    if not isinstance(value, str) or not re.fullmatch(r"[a-zA-Z0-9][a-zA-Z0-9_-]{0,79}", value):
        raise ValueError("Use opaque identifiers with letters, digits, underscores or hyphens")
    return value


def timestamp(value):
    parsed = datetime.fromisoformat(value)
    if parsed.tzinfo is None or parsed > datetime.now(timezone.utc):
        raise ValueError("Review timestamps require a timezone and cannot be in the future")
    return value


def resolve_file(base, value):
    path = base / value
    if path.is_symlink() or not path.is_file():
        raise ValueError("Input must be an existing regular file, not a symbolic link")
    return path.resolve(strict=True)


def prepare(request_path, output, today=None):
    today = today or date.today()
    request_path = request_path.resolve(strict=True)
    request = json.loads(request_path.read_text())
    if request.get("schema_version") != 1 or not request.get("entries"):
        raise ValueError("A schema-1 collection with explicit entries is required")
    base = request_path.parent
    receipts = {}
    for item in request["consents"]:
        consent_id = identifier(item["id"])
        if consent_id in receipts:
            raise ValueError("Duplicate consent identifier")
        if item.get("status") != "active" or item.get("reviewed") is not True:
            raise ValueError("An active, explicitly reviewed consent receipt is required")
        if date.fromisoformat(item["retain_until"]) <= today:
            raise ValueError("Collection retention must still be active")
        identifier(item["reviewer_id"])
        timestamp(item["reviewed_at"])
        purposes = set(item["purposes"])
        if not purposes or not purposes <= set.union(*PURPOSES.values()):
            raise ValueError("Unknown or empty purpose selection")
        evidence = resolve_file(base, item["evidence"])
        evidence_hash = sha(evidence)
        if item.get("evidence_sha256") != evidence_hash:
            raise ValueError("Consent evidence changed since the operator review")
        receipts[consent_id] = {
            key: item[key]
            for key in ["id", "status", "reviewer_id", "reviewed_at", "retain_until", "purposes"]
        } | {"evidence_sha256": evidence_hash}
    entries, seen = [], set()
    for item in request["entries"]:
        kind = item["kind"]
        if kind not in FORMATS:
            raise ValueError("Only schedule and speech intake are supported")
        path = resolve_file(base, item["path"])
        if path.suffix.lower() not in FORMATS[kind]:
            raise ValueError("Unexpected input format")
        identifier(item["id"])
        if item["id"] in seen:
            raise ValueError("Duplicate entry identifier")
        seen.add(item["id"])
        groups = item["related_ids"]
        if not groups or len(set(groups)) != len(groups):
            raise ValueError("Explicit, unique source relationships are required")
        for group in groups:
            identifier(group)
        if kind == "speech":
            identifier(item["speaker_id"])
            if f"speaker_{item['speaker_id']}" not in groups:
                raise ValueError("Every speech recording must retain its speaker group")
        consent_id = identifier(item["consent_id"])
        receipt = receipts.get(consent_id)
        purposes = set(item["purposes"])
        if (
            receipt is None
            or not purposes
            or not purposes <= PURPOSES[kind]
            or not purposes <= set(receipt["purposes"])
        ):
            raise ValueError("Requested use is outside the reviewed receipt")
        entries.append(
            {key: item[key] for key in ["id", "kind", "related_ids", "consent_id", "purposes"]}
            | {
                "speaker_id": item.get("speaker_id"),
                "source": str(path),
                "source_sha256": sha(path),
                "bytes": path.stat().st_size,
                "extension": path.suffix.lower(),
            }
        )
    # Validate everything before creating output. mkdir rejects accidental replacement.
    output.mkdir(parents=True, exist_ok=False, mode=0o700)
    (output / "raw").mkdir(mode=0o700)
    report = {
        "schema_version": 1,
        "created_at": datetime.now(timezone.utc).isoformat(),
        "status": "copying",
        "request_sha256": sha(request_path),
        "tool_sha256": sha(Path(__file__)),
        "approved": False,
        "partition": "unassigned",
        "groups_frozen": False,
        "consents": list(receipts.values()),
        "entries": entries,
    }

    def save():
        temporary = output / "manifest.part"
        temporary.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
        temporary.chmod(0o600)
        temporary.replace(output / "manifest.json")

    save()
    try:
        for entry in entries:
            source = Path(entry["source"])
            relative = Path("raw") / (entry["source_sha256"] + entry["extension"])
            destination = output / relative
            if not destination.exists():
                partial = destination.with_suffix(".part")
                shutil.copyfile(source, partial)
                partial.chmod(0o600)
                if sha(partial) != entry["source_sha256"]:
                    raise ValueError("Source changed during copy; batch is incomplete")
                partial.replace(destination)
            if sha(source) != entry["source_sha256"] or sha(destination) != entry["source_sha256"]:
                raise ValueError("Source or copy changed; batch is incomplete")
            entry["local_path"] = str(relative)
            entry["copy_verified"] = True
            save()
        report["status"] = "awaiting_privacy_and_reference_review"
    except BaseException:
        report["status"] = "incomplete"
        save()
        raise
    save()
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("request", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    output = args.output.resolve()
    private = (ROOT / ".local/datasets/incoming").resolve()
    if not output.is_relative_to(private) or output == private:
        parser.error("Output must be a new batch below .local/datasets/incoming")
    result = prepare(args.request, output)
    print(json.dumps({"entries": len(result["entries"]), "status": result["status"]}))


if __name__ == "__main__":
    main()
