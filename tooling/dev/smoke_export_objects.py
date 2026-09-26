"""APFS clones for three explicitly reviewed completed smoke export duplicates only."""

import argparse
import json
import shutil
import sys
from pathlib import Path

import model_objects as models

import artifacts
from artifacts import ROOT, guard, local_path, locked, sha, write_new

REVIEW_SHA256 = "ab9ddd1495aaf7a910fec3a23a83556440e1492c73bb582cf869203e9858b0d5"
GROUPS = [
    {
        "sha256": "6ed83b65b13aaea30d8dbe41f05c7c0d214a6059b9b4f5f43d7f732f0f1d1a86",
        "bytes": 1192134935,
        "retained_source": ".local/runs/assistant-smoke-003/fused/model.safetensors",
        "targets": [
            ".local/runs/assistant-smoke-001/fused/model.safetensors",
            ".local/runs/assistant-smoke-002/fused/model.safetensors",
        ],
        "possible_new_object": ".local/objects/sha256/6ed83b65b13aaea30d8dbe41f05c7c0d214a6059b9b4f5f43d7f732f0f1d1a86.safetensors",
        "object_exists_at_review": False,
    },
    {
        "sha256": "49b2cf706c096ae1776ee888cc01cdc07d45f34ba04423b725dc086079abebae",
        "bytes": 1198182240,
        "retained_source": ".local/runs/assistant-smoke-003/assistant.gguf",
        "targets": [".local/runs/assistant-smoke-002/assistant.gguf"],
        "possible_new_object": ".local/objects/sha256/49b2cf706c096ae1776ee888cc01cdc07d45f34ba04423b725dc086079abebae.gguf",
        "object_exists_at_review": False,
    },
]


def implementation():
    return {
        name: sha(Path(path))
        for name, path in {
            "scope": __file__,
            "clone": models.__file__,
            "guard": artifacts.__file__,
        }.items()
    }


def reviewed(root, review):
    if sha(review) != REVIEW_SHA256:
        raise ValueError("Only the exact independent A-group review is accepted")
    value = json.loads(review.read_text())
    if value["root"] != str(root) or value["groups"] != GROUPS:
        raise ValueError("Unknown export group or root")
    return value


def verify(root, review):
    files = {row["path"]: row for row in review["files"]}
    expected_names = {n for g in GROUPS for n in [g["retained_source"], *g["targets"]]}
    if set(files) != expected_names:
        raise ValueError("Incomplete reviewed exports")
    actual = {}
    for group in GROUPS:
        for name in [group["retained_source"], *group["targets"]]:
            expected = {key: files[name][key] for key in models.METADATA_FIELDS}
            if models.content(expected) != models.content(group):
                raise ValueError("Unreviewed export bytes")
            path = local_path(root, name)
            if models.metadata(path) != expected:
                raise ValueError("Reviewed export changed")
            actual[name] = {"inode": path.stat().st_ino, "device": path.stat().st_dev}
    if len({(v["device"], v["inode"]) for v in actual.values()}) != len(actual):
        raise ValueError("Exports must have separate inodes")
    for proof in review["retained_provenance_bindings"]:
        p = local_path(root, proof["path"])
        if p.stat().st_size != proof["bytes"] or sha(p) != proof["sha256"]:
            raise ValueError("Retained provenance changed")
    return actual


def plan(root, review_path, manifest):
    review = reviewed(root, review_path)
    names = [
        n for g in GROUPS for n in [g["retained_source"], *g["targets"], g["possible_new_object"]]
    ]
    guard(root, names)
    before = verify(root, review)
    result = {
        "schema_version": 1,
        "action": "coalesce-reviewed-smoke-exports",
        "root": str(root),
        "review": str(review_path.relative_to(root)),
        "review_sha256": sha(review_path),
        "implementation": implementation(),
        "groups": GROUPS,
        "before": before,
        "metadata_contract": list(models.METADATA_FIELDS) + ["empty_xattrs", "empty_acl", "nlink1"],
        "source_references_unchanged": True,
        "deletion_candidates": [],
        "reclaimable_bytes_known": False,
    }
    write_new(manifest, result)
    return result


def apply(root, manifest):
    value = json.loads(manifest.read_text())
    if (
        value.get("schema_version") != 1
        or value.get("action") != "coalesce-reviewed-smoke-exports"
        or value.get("root") != str(root)
        or value.get("groups") != GROUPS
        or value.get("implementation") != implementation()
    ):
        raise ValueError("Unknown or stale export plan")
    review_path = local_path(root, value["review"])
    review = reviewed(root, review_path)
    if value["review_sha256"] != sha(review_path):
        raise ValueError("Review changed")
    names = [
        n for g in GROUPS for n in [g["retained_source"], *g["targets"], g["possible_new_object"]]
    ]
    guard(root, names)
    before = verify(root, review)
    for group in GROUPS:
        name = group["retained_source"]
        if before[name] != value["before"][name]:
            raise ValueError("Retained source inode changed")
    receipt = manifest.with_suffix(".receipt.json")
    digest = sha(manifest)
    if receipt.exists():
        previous = json.loads(receipt.read_text())
        if previous["plan_sha256"] != digest:
            raise ValueError("Receipt belongs to another plan")
        verify_objects(root)
        return previous
    progress = manifest.with_suffix(".progress.json")
    if not progress.exists():
        write_new(
            progress, {"plan_sha256": digest, "free_before_bytes": shutil.disk_usage(root).free}
        )
    started = json.loads(progress.read_text())
    if started["plan_sha256"] != digest:
        raise ValueError("Progress belongs to another plan")
    files = {x["path"]: x for x in review["files"]}
    # Validate every existing object before replacing even the first target.
    for group in GROUPS:
        p = local_path(root, group["possible_new_object"])
        if p.exists():
            check_object(p, group)
    for group in GROUPS:
        source = local_path(root, group["retained_source"])
        obj = local_path(root, group["possible_new_object"])
        obj.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
        if not obj.exists():
            models.verified_clone(source, obj, models.content(group))
        check_object(obj, group)
        for name in group["targets"]:
            models.verified_clone(
                obj,
                local_path(root, name),
                {key: files[name][key] for key in models.METADATA_FIELDS},
            )
    after = verify(root, review)
    verify_objects(root)
    if any(after[g["retained_source"]] != before[g["retained_source"]] for g in GROUPS):
        raise ValueError("Retained source inode changed")
    free = shutil.disk_usage(root).free
    result = {
        "plan_sha256": digest,
        "status": "coalesced-identical-content-and-metadata",
        "before": before,
        "after": after,
        "preserved_target_paths": 3,
        "retained_source_inodes_unchanged": True,
        "provenance_reverified": True,
        "free_before_bytes": started["free_before_bytes"],
        "free_after_bytes": free,
        "observed_volume_delta_bytes": free - started["free_before_bytes"],
        "limitation": "APFS shared extents unknown; volume delta includes concurrent system activity",
    }
    write_new(receipt, result)
    return result


def check_object(path, group):
    actual = models.metadata(path)
    if models.content(actual) != models.content(group) or actual["mode"] != 0o444:
        raise ValueError("Existing canonical object was altered")


def verify_objects(root):
    for group in GROUPS:
        obj = local_path(root, group["possible_new_object"])
        check_object(obj, group)
        if any(
            obj.stat().st_ino == local_path(root, name).stat().st_ino
            for name in [group["retained_source"], *group["targets"]]
        ):
            raise ValueError("Object shares a live export inode")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=["plan", "apply"])
    parser.add_argument("--review", required=True)
    parser.add_argument("--manifest", required=True)
    args = parser.parse_args()
    review = local_path(ROOT, args.review)
    manifest = local_path(ROOT, args.manifest)
    if not manifest.is_relative_to(ROOT / ".local/maintenance"):
        raise ValueError("Export plan must remain private")
    sys.path.insert(0, str(ROOT / "tooling/build"))
    import product_generation

    # An independent outer product lease cannot be bypassed by an inherited FD.
    with product_generation.locked(ROOT), locked(ROOT):
        if args.action == "apply" and json.loads(manifest.read_text())["review"] != str(
            review.relative_to(ROOT)
        ):
            raise ValueError("Review argument differs from the reviewed plan")
        result = plan(ROOT, review, manifest) if args.action == "plan" else apply(ROOT, manifest)
    print(json.dumps(result, indent=2))


if __name__ == "__main__":
    main()
