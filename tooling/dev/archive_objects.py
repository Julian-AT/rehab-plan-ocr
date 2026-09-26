"""Coalesce reviewed static test archives without deleting paths or changing evidence."""

import argparse
import json
import os
import platform
import plistlib
import re
import shutil
import stat
import subprocess
import uuid
from pathlib import Path

import model_objects
from model_objects import clone

import artifacts
from artifacts import ROOT, guard, local_path, locked, sha, write_new

ARCHIVE = "products/build-products/Debug-iphonesimulator/libRehaCoreFFI.a"
FIELDS = ["sha256", "bytes", "mode", "mtime_ns", "uid", "gid", "flags"]


def implementation_sources():
    return {
        name: sha(Path(path))
        for name, path in {
            "archive_objects": __file__,
            "clone": model_objects.__file__,
            "guards": artifacts.__file__,
        }.items()
    }


def eligible(name):
    return re.fullmatch(r"\.local/runs/[a-z0-9-]+/" + re.escape(ARCHIVE), name) is not None


def test_targets(value):
    """Read both emitted XCTest layouts; never treat missing targets as evidence."""
    version = value.get("__xctestrun_metadata__", {}).get("FormatVersion")
    if type(version) is not int or version not in {1, 2}:
        raise ValueError("Unsupported XCTest invocation format")
    if version == 1:
        targets = [
            target
            for name, target in value.items()
            if not name.startswith("__") and name != "CodeCoverageBuildableInfos"
        ]
    else:
        configurations = value.get("TestConfigurations")
        if not isinstance(configurations, list) or not configurations:
            raise ValueError("Missing XCTest configurations")
        targets = []
        for configuration in configurations:
            values = configuration.get("TestTargets") if isinstance(configuration, dict) else None
            if not isinstance(values, list) or not values:
                raise ValueError("Missing XCTest targets")
            targets.extend(values)
    if not targets or any(
        not isinstance(target, dict)
        or not isinstance(target.get("TestBundlePath"), str)
        or not target["TestBundlePath"]
        for target in targets
    ):
        raise ValueError("Expected actual XCTest bundle invocation paths")
    return targets


def identity(path):
    before = path.lstat()
    if not stat.S_ISREG(before.st_mode) or before.st_nlink != 1:
        raise ValueError("Expected an independent regular static archive")
    if stat.S_IMODE(before.st_mode) & ~0o777 or before.st_flags & ~0x8040:
        raise ValueError("Unreviewed special archive permissions or flags")
    # The reviewed compiler archives have no ACLs or extended attributes. Refuse
    # a richer file rather than silently losing metadata when cloning another copy.
    if subprocess.check_output(["/usr/bin/xattr", "-l", str(path)]):
        raise ValueError("Extended archive attributes require separate preservation")
    if subprocess.check_output(["/bin/ls", "-lde", str(path)], text=True).splitlines()[1:]:
        raise ValueError("Archive ACLs require separate preservation")
    with path.open("rb") as stream:
        if stream.read(8) != b"!<arch>\n":
            raise ValueError("Unexpected static archive signature")
    value = {
        "sha256": sha(path),
        "bytes": before.st_size,
        "mode": stat.S_IMODE(before.st_mode),
        "mtime_ns": before.st_mtime_ns,
        "uid": before.st_uid,
        "gid": before.st_gid,
        "flags": before.st_flags,
    }
    after = path.lstat()
    if any(
        getattr(before, key) != getattr(after, key)
        for key in [
            "st_ino",
            "st_size",
            "st_mtime_ns",
            "st_mode",
            "st_nlink",
            "st_dev",
            "st_uid",
            "st_gid",
            "st_flags",
        ]
    ):
        raise ValueError("Archive changed during verification")
    return value


def proof(root, run):
    """Retain complete adjacent test products and provenance; never infer unusedness."""
    source = local_path(root, str((run / "source.json").relative_to(root)))
    locations = local_path(root, str((run / "product-locations.json").relative_to(root)))
    decoded = json.loads(source.read_text())
    revision = decoded.get("head", decoded.get("commit", ""))
    if not re.fullmatch(r"[a-f0-9]{40}", revision):
        raise ValueError("Retained test products need an identified source revision")
    if not isinstance(json.loads(locations.read_text()), dict):
        raise ValueError("Expected retained producer locations")
    products = run / "products"
    invocations = list(products.rglob("*.xctestrun"))
    if not invocations:
        raise ValueError("Retained archive needs its associated test invocation")
    for path in invocations:
        local_path(root, str(path.relative_to(root)))
        test_targets(plistlib.loads(path.read_bytes()))
    result = {}
    # Check the complete retained run, including sources, logs, result bundles,
    # apps, test runners, symbols and failure evidence.
    # Symlinks are preserved as references and are never followed outside the tree.
    paths = run.rglob("*")
    for path in sorted(paths):
        name = str(path.relative_to(root))
        info = path.lstat()
        if path.is_symlink():
            result[name] = {"kind": "symlink", "target": os.readlink(path)}
        elif stat.S_ISREG(info.st_mode):
            result[name] = {
                "kind": "file",
                "sha256": sha(path),
                "bytes": info.st_size,
                "mode": stat.S_IMODE(info.st_mode),
            }
        elif not stat.S_ISDIR(info.st_mode):
            raise ValueError("Unexpected retained product kind")
    return result


def plan(root, review_path, destination):
    review = json.loads(review_path.read_text())
    if (
        review.get("schema_version") != 1
        or review.get("status") != "read-only-inventory-no-files-changed"
    ):
        raise ValueError("Expected an explicit reviewed archive inventory")
    groups = []
    names = []
    for group in review["groups"]:
        if len(group["paths"]) < 2:
            continue
        if not re.fullmatch(r"[a-f0-9]{64}", group["sha256"]):
            raise ValueError("Invalid object identity")
        paths = []
        for item in group["paths"]:
            name = item["path"]
            if not eligible(name) or name in names:
                raise ValueError("Only unique reviewed static test archive paths are supported")
            value = identity(local_path(root, name))
            if value["uid"] != os.getuid() or (paths and value["gid"] != paths[0]["gid"]):
                raise ValueError("Archive ownership needs a separate preservation contract")
            if any(
                value[key] != expected
                for key, expected in {
                    "sha256": group["sha256"],
                    "bytes": group["bytes"],
                    "mode": item["mode"],
                }.items()
            ):
                raise ValueError("Reviewed archive changed")
            names.append(name)
            paths.append({"path": name, **value})
        groups.append({"sha256": group["sha256"], "bytes": group["bytes"], "paths": paths})
    if not groups:
        raise ValueError("No reviewed duplicate archives")
    guard(root, names)
    evidence = {}
    runs = sorted({str(Path(name).parents[3]) for name in names})
    for name in runs:
        evidence.update(proof(root, root / name))
    value = {
        "schema_version": 1,
        "root": str(root),
        "action": "coalesce-reviewed-static-test-archives",
        "review": str(review_path.relative_to(root)),
        "review_sha256": sha(review_path),
        "implementation_sources": implementation_sources(),
        "groups": groups,
        "protected_run_evidence": evidence,
        "runs": runs,
        "paths_bytes_modes_mtimes_preserved": True,
        "deletion_candidates": [],
        "reclaimable_bytes_known": False,
    }
    write_new(destination, value)
    return value


def replace_clone(source, destination, expected):
    temporary = destination.with_name(f".{destination.name}.clone-{uuid.uuid4().hex}")
    previous = identity(destination) if destination.exists() else None
    if previous is not None and previous != expected:
        raise ValueError("Destination no longer matches the reviewed identity")
    try:
        clone(source, temporary)
        temporary.chmod(expected["mode"])
        os.utime(temporary, ns=(temporary.stat().st_atime_ns, expected["mtime_ns"]))
        # clonefile intentionally drops UF_TRACKED; restore the reviewed original
        # user flags on the new inode before it can replace an existing path.
        os.chflags(temporary, expected["flags"])
        if identity(temporary) != expected or temporary.stat().st_ino == source.stat().st_ino:
            raise ValueError("Clone changed content/metadata or shared an inode")
        with temporary.open("rb") as stream:
            os.fsync(stream.fileno())
        if destination.exists():
            if previous is None or identity(destination) != previous:
                raise ValueError("Destination changed while preparing its clone")
        elif previous is not None:
            raise ValueError("Destination disappeared while preparing its clone")
        temporary.replace(destination)
        directory = os.open(destination.parent, os.O_RDONLY)
        try:
            os.fsync(directory)
        finally:
            os.close(directory)
    finally:
        temporary.unlink(missing_ok=True)


def validate(root, value):
    if (
        value.get("schema_version") != 1
        or value.get("root") != str(root)
        or value.get("action") != "coalesce-reviewed-static-test-archives"
        or value.get("implementation_sources") != implementation_sources()
    ):
        raise ValueError("Unknown or changed archive-object protocol")
    review = local_path(root, value["review"])
    if (
        not review.is_relative_to(root / ".local/maintenance")
        or sha(review) != value["review_sha256"]
    ):
        raise ValueError("Reviewed archive inventory changed")
    names = [item["path"] for group in value["groups"] for item in group["paths"]]
    if not names or len(names) != len(set(names)) or any(not eligible(name) for name in names):
        raise ValueError("Expected only unique reviewed static archive paths")
    reviewed = json.loads(review.read_text())
    allowed = {
        item["path"]: {"sha256": group["sha256"], "bytes": group["bytes"], "mode": item["mode"]}
        for group in reviewed["groups"]
        if len(group["paths"]) > 1
        for item in group["paths"]
    }
    if set(names) != set(allowed):
        raise ValueError("Plan paths differ from the reviewed duplicate groups")
    expected_runs = sorted({str(Path(name).parents[3]) for name in names})
    if expected_runs != value["runs"]:
        raise ValueError("Associated test-product roots changed")
    for group in value["groups"]:
        if len(group["paths"]) < 2 or not re.fullmatch(r"[a-f0-9]{64}", group["sha256"]):
            raise ValueError("Invalid immutable archive group")
        for item in group["paths"]:
            expected = {key: item[key] for key in FIELDS}
            if any(expected[key] != match for key, match in allowed[item["path"]].items()):
                raise ValueError("Archive identity differs from the explicit review")
            if (
                expected["sha256"] != group["sha256"]
                or expected["bytes"] != group["bytes"]
                or identity(local_path(root, item["path"])) != expected
            ):
                raise ValueError("A reviewed archive changed before replacement")
    actual = {}
    for name in value["runs"]:
        actual.update(proof(root, root / name))
    if actual != value["protected_run_evidence"]:
        raise ValueError("Retained test products or historical provenance changed")
    return names


def apply(root, manifest):
    value = json.loads(manifest.read_text())
    digest = sha(manifest)
    receipt = local_path(root, str(manifest.with_suffix(".receipt.json").relative_to(root)))
    progress = local_path(root, str(manifest.with_suffix(".progress.json").relative_to(root)))
    if receipt.exists():
        previous = json.loads(receipt.read_text())
        if previous["plan_sha256"] != digest:
            raise ValueError("Completed plan changed")
        return previous
    names = validate(root, value)
    objects = local_path(root, ".local/objects/sha256")
    guard(root, names + [str(objects.relative_to(root))])
    objects.mkdir(parents=True, exist_ok=True, mode=0o700)
    if not progress.exists():
        write_new(
            progress, {"plan_sha256": digest, "free_before_bytes": shutil.disk_usage(root).free}
        )
    started = json.loads(progress.read_text())
    if started["plan_sha256"] != digest:
        raise ValueError("Interrupted plan changed")
    replaced = []
    for group in value["groups"]:
        object_path = local_path(root, f".local/objects/sha256/{group['sha256']}.a")
        first = group["paths"][0]
        expected_object = {key: first[key] for key in FIELDS} | {"mode": 0o444}
        if not object_path.exists():
            replace_clone(local_path(root, first["path"]), object_path, expected_object)
        actual = identity(object_path)
        if any(actual[key] != expected_object[key] for key in FIELDS if key != "mtime_ns"):
            raise ValueError("Existing canonical archive was altered")
        for item in group["paths"]:
            path = local_path(root, item["path"])
            expected = {key: item[key] for key in FIELDS}
            if identity(path) != expected:
                raise ValueError("Archive changed immediately before replacement")
            old_inode = path.stat().st_ino
            replace_clone(object_path, path, expected)
            replaced.append(
                {
                    "path": item["path"],
                    "old_inode": old_inode,
                    "new_inode": path.stat().st_ino,
                    "object_inode": object_path.stat().st_ino,
                }
            )
    # Atomic replacements preserve bytes/modes/mtime, so interrupted operations
    # can safely repeat. No completion receipt is written until all proofs match.
    validate(root, value)
    free = shutil.disk_usage(root).free
    result = {
        "schema_version": 1,
        "status": "coalesced-identical-test-archives",
        "plan_sha256": digest,
        "objects": len(value["groups"]),
        "preserved_paths": len(names),
        "deleted_paths": [],
        "preserved_run_files": len(value["protected_run_evidence"]),
        "identities": replaced,
        "free_before_bytes": started["free_before_bytes"],
        "free_after_bytes": free,
        "observed_volume_delta_bytes": free - started["free_before_bytes"],
        "limitation": "Observed volume change includes system activity; APFS sharing is not a reclaim estimate.",
        "originals_models_backups_touched": False,
    }
    write_new(receipt, result)
    return result


def main():
    if platform.system() != "Darwin":
        raise ValueError("Archive coalescing requires macOS/APFS metadata and clonefile")
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=["plan", "apply"])
    parser.add_argument("--manifest", required=True)
    parser.add_argument("--review")
    args = parser.parse_args()
    manifest = local_path(ROOT, args.manifest)
    if not manifest.is_relative_to(ROOT / ".local/maintenance"):
        parser.error("Archive-object evidence belongs below .local/maintenance")
    if args.action == "plan" and not args.review:
        parser.error("Planning needs an explicit reviewed archive inventory")
    with locked(ROOT):
        if args.action == "plan":
            review = local_path(ROOT, args.review)
            if not review.is_relative_to(ROOT / ".local/maintenance"):
                parser.error("Review must be below .local/maintenance")
            result = plan(ROOT, review, manifest)
            print(
                json.dumps(
                    {
                        "groups": len(result["groups"]),
                        "preserved_paths": sum(len(g["paths"]) for g in result["groups"]),
                        "reclaimable_bytes_known": False,
                    }
                )
            )
        else:
            result = apply(ROOT, manifest)
            print(
                json.dumps(
                    {key: item for key, item in result.items() if key != "identities"}, indent=2
                )
            )


if __name__ == "__main__":
    main()
