"""Coalesce immutable exported assistant baselines using APFS copy-on-write clones.

No checkpoint, optimizer, original, backup, app bundle or selected tuned model is
eligible. Every legacy path retains the same bytes and its own inode. Hard links
and symlinks are never used. Unsupported filesystems fail without a full-copy fallback.
"""

import argparse
import ctypes
import json
import os
import platform
import re
import shutil
import uuid

from artifacts import ROOT, guard, local_path, locked, sha, write_new

PIN = "ml/registry/assistant-untuned-001.json"


def pinned_identity(root):
    artifact = json.loads((root / PIN).read_text())["artifact"]
    return {k: artifact[k] for k in ("sha256", "bytes")}


def eligible(name):
    return re.fullmatch(r"\.local/runs/assistant-[a-z0-9-]+/(deployment/)?baseline\.gguf", name)


def clone(source, destination):
    if platform.system() != "Darwin":
        raise ValueError("Model coalescing requires APFS clonefile; no copying fallback")
    call = ctypes.CDLL(None, use_errno=True).clonefile
    call.argtypes = [ctypes.c_char_p, ctypes.c_char_p, ctypes.c_int]
    call.restype = ctypes.c_int
    if call(os.fsencode(source), os.fsencode(destination), 0):
        code = ctypes.get_errno()
        raise OSError(code, os.strerror(code))


def identity(path):
    before = path.stat()
    digest = sha(path)
    after = path.stat()
    if (before.st_ino, before.st_mtime_ns, before.st_size) != (
        after.st_ino,
        after.st_mtime_ns,
        after.st_size,
    ):
        raise ValueError("Model changed while hashing")
    return {"sha256": digest, "bytes": before.st_size}


def plan(root, destination):
    names = sorted(
        str(p.relative_to(root))
        for p in (root / ".local/runs").glob("assistant-*/**/baseline.gguf")
        if eligible(str(p.relative_to(root)))
    )
    guard(root, names)
    groups = {}
    for name in names:
        path = local_path(root, name)
        value = identity(path)
        if value != pinned_identity(root):
            raise ValueError("Unknown baseline; only the reviewed registry identity is eligible")
        with path.open("rb") as stream:
            if stream.read(4) != b"GGUF":
                raise ValueError("Expected GGUF baseline export")
        group = groups.setdefault(value["sha256"], value | {"paths": []})
        group["paths"].append(name)
    value = {
        "schema_version": 1,
        "registry_sha256": sha(root / PIN),
        "root": str(root),
        "action": "coalesce-immutable-baselines",
        "groups": [g for g in groups.values() if len(g["paths"]) > 1],
        "protected": "All paths except the listed immutable baseline exports; no checkpoints or backups",
        "historical_paths_preserved": True,
    }
    write_new(destination, value)
    return value


def verified_clone(source, destination, expected):
    temporary = destination.with_name(f".{destination.name}.clone-{uuid.uuid4().hex}")
    try:
        clone(source, temporary)
        if identity(temporary) != expected or temporary.stat().st_ino == source.stat().st_ino:
            raise ValueError("Clone did not preserve bytes in a separate inode")
        temporary.chmod(0o444)
        with temporary.open("rb") as stream:
            os.fsync(stream.fileno())
        temporary.replace(destination)
    finally:
        temporary.unlink(missing_ok=True)


def apply(root, source):
    value = json.loads(source.read_text())
    if (
        value["schema_version"] != 1
        or value["registry_sha256"] != sha(root / PIN)
        or value["root"] != str(root)
        or value["action"] != "coalesce-immutable-baselines"
    ):
        raise ValueError("Unknown model-object plan")
    digest = sha(source)
    receipt = local_path(root, str(source.with_suffix(".receipt.json").relative_to(root)))
    progress = local_path(root, str(source.with_suffix(".progress.json").relative_to(root)))
    if receipt.exists():
        result = json.loads(receipt.read_text())
        if result["plan_sha256"] != digest:
            raise ValueError("Model-object plan changed")
        return result
    names = [n for g in value["groups"] for n in g["paths"]]
    if any(not eligible(n) for n in names) or len(names) != len(set(names)):
        raise ValueError("Only unique immutable baseline export paths are allowed")
    for group in value["groups"]:
        if {k: group[k] for k in ("sha256", "bytes")} != pinned_identity(root):
            raise ValueError("Plan contains an unreviewed model identity")
        if not re.fullmatch(r"[a-f0-9]{64}", group["sha256"]) or len(group["paths"]) < 2:
            raise ValueError("Invalid content-addressed model group")
        for name in group["paths"]:
            if identity(local_path(root, name)) != {k: group[k] for k in ("sha256", "bytes")}:
                raise ValueError("A baseline changed after the preview; no model replaced")
    objects = local_path(root, ".local/objects/sha256")
    guard(root, names + [str(objects.relative_to(root))])
    objects.mkdir(parents=True, exist_ok=True, mode=0o700)
    if not progress.exists():
        write_new(
            progress, {"plan_sha256": digest, "free_before_bytes": shutil.disk_usage(root).free}
        )
    started = json.loads(progress.read_text())
    if started["plan_sha256"] != digest:
        raise ValueError("Model-object plan changed after application started")
    # Each replacement preserves content, so replaying an interrupted step is safe.
    for group in value["groups"]:
        expected = {k: group[k] for k in ("sha256", "bytes")}
        object_path = local_path(root, f".local/objects/sha256/{group['sha256']}.gguf")
        if not object_path.exists():
            verified_clone(local_path(root, group["paths"][0]), object_path, expected)
        if identity(object_path) != expected:
            raise ValueError("Existing model object was altered")
        object_path.chmod(0o444)
        for name in group["paths"]:
            path = local_path(root, name)
            if identity(path) != expected:
                raise ValueError("Baseline changed before replacement")
            verified_clone(object_path, path, expected)
        if any(identity(local_path(root, n)) != expected for n in group["paths"]):
            raise ValueError("Baseline verification failed after coalescing")
    free = shutil.disk_usage(root).free
    result = {
        "schema_version": 1,
        "plan_sha256": digest,
        "status": "coalesced-identical-content",
        "objects": len(value["groups"]),
        "preserved_paths": len(names),
        "free_before_bytes": started["free_before_bytes"],
        "free_after_bytes": free,
        "observed_volume_delta_bytes": free - started["free_before_bytes"],
        "limitation": "APFS sharing is not a reclaim estimate; volume delta includes system activity",
        "mutable_checkpoints_touched": False,
    }
    write_new(receipt, result)
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=["plan", "apply"])
    parser.add_argument("--manifest", required=True)
    args = parser.parse_args()
    source = local_path(ROOT, args.manifest)
    if not source.is_relative_to(ROOT / ".local/maintenance"):
        raise ValueError("Model-object evidence belongs below .local/maintenance")
    with locked(ROOT):
        result = plan(ROOT, source) if args.action == "plan" else apply(ROOT, source)
    print(json.dumps(result, indent=2))


if __name__ == "__main__":
    main()
