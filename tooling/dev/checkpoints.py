"""Retain resumable best/latest checkpoints and prune only unreferenced tensor payloads.

Checkpoint receipts, metrics, configurations and historical evidence are never
rewritten. The metadata inventory is safe during evaluation; a deletion plan and
its application require a quiet workspace and the trainer's own exclusive lock.
"""

import argparse
import fcntl
import hashlib
import json
import os
import re
import shutil
import stat
from contextlib import ExitStack, contextmanager
from pathlib import Path

import artifacts

ROOT = Path(__file__).resolve().parents[2]
INDEX = ".local/maintenance/checkpoints"
EPOCH = re.compile(r"epoch-(\d{4})$")
HEX = re.compile(r"[a-f0-9]{64}$")
FORMATS = {
    "ocr": {
        "producers": ["ml/training/ocr/train.py", "ml/training/ocr/compat/training_v1/train.py"],
        "payloads": {"training.pdstate"},
        "files": {"training.pdstate", "checkpoint.json"},
    },
    "assistant": {
        "producers": ["ml/training/assistant/train.py"],
        "payloads": {"adapters.safetensors", "optimizer.safetensors", "random.safetensors"},
        "files": {
            "adapters.safetensors",
            "optimizer.safetensors",
            "random.safetensors",
            "adapter_config.json",
            "metrics.json",
            "checkpoint.json",
        },
    },
}
MAX_REFERENCE_BYTES = 8 * 1024 * 1024
TEXT = {".json", ".jsonl", ".md", ".txt", ".yaml", ".yml", ".log", ".py", ".sh", ".toml"}
SKIP = {
    ".git",
    "__pycache__",
    "site-packages",
    "node_modules",
    "checkpoints",
    "builds",
    "envs",
    "caches",
    "cache",
    "target",
    "DerivedData",
    "datasets",
    "upstream",
    "objects",
}


def relative(root, path):
    return str(path.relative_to(root))


def read(root, path, evidence):
    name = relative(root, path)
    path = artifacts.local_path(root, name)
    before = path.stat()
    value = path.read_bytes()
    after = path.stat()
    if (before.st_size, before.st_mtime_ns, before.st_ino) != (
        after.st_size,
        after.st_mtime_ns,
        after.st_ino,
    ):
        raise ValueError(f"Metadata changed during inventory: {name}")
    evidence[name] = hashlib.sha256(value).hexdigest()
    return json.loads(value)


def known_removed(root):
    """Completed receipts explain absence; an interrupted plan must resume first."""
    result = {}
    for receipt in sorted((root / INDEX).glob("*.receipt.json")):
        artifacts.local_path(root, relative(root, receipt))
        value = json.loads(receipt.read_text())
        plan = receipt.with_name(receipt.name.removesuffix(".receipt.json") + ".json")
        artifacts.local_path(root, relative(root, plan))
        if value.get("schema_version") != 1 or value.get("plan_sha256") != artifacts.sha(plan):
            raise ValueError("Checkpoint inventory receipt changed")
        saved = json.loads(plan.read_text())
        for name in value["removed"]:
            result[name] = saved["files"][name]["sha256"]
    return result


def catalog(root, names, *, removed=None):
    evidence, runs = {}, []
    removed = known_removed(root) if removed is None else removed
    for name in sorted(set(names)):
        if not re.fullmatch(r"\.local/runs/[^/]+", name):
            raise ValueError("Only direct, explicitly selected .local/runs children are supported")
        run = artifacts.local_path(root, name)
        identity = read(root, run / "identity.json", evidence)
        settings = read(root, run / "settings.json", evidence)
        baseline = read(root, run / "baseline.json", evidence)
        del baseline
        if identity["settings_sha256"] != evidence[name + "/settings.json"]:
            raise ValueError("Training settings no longer match their provenance")
        lineage = identity["lineage"]
        kind = "assistant" if settings.get("fine_tune_type") == "lora" else "ocr"
        dataset = Path(settings["dataset"])
        if not dataset.is_absolute():
            dataset = root / dataset
        if not dataset.is_relative_to(root / ".local/datasets"):
            raise ValueError("Training dataset must retain its checked local provenance")
        read(root, dataset, evidence)
        pins = {
            relative(root, dataset): "dataset_sha256",
            f"ml/registry/{'assistant' if kind == 'assistant' else 'ocr'}-base.json": "registry_sha256",
            f"ml/training/{kind}/uv.lock": "environment_sha256",
        }
        for path, key in pins.items():
            checked = artifacts.local_path(root, path)
            evidence[path] = artifacts.sha(checked)
            if lineage.get(key) != evidence[path]:
                raise ValueError("Dataset/model/environment pin changed; preserve all checkpoints")
        producer = (
            lineage.get("sources_sha256", {}).get("ml/training/assistant/train.py")
            if kind == "assistant"
            else lineage.get("source_sha256", {}).get("train.py")
        )
        if producer not in {
            artifacts.sha(artifacts.local_path(root, p))
            for p in FORMATS[kind]["producers"]
            if (root / p).is_file()
        }:
            raise ValueError("Unknown checkpoint producer; preserve the complete run")
        for path in FORMATS[kind]["producers"]:
            if (root / path).is_file():
                evidence[path] = artifacts.sha(artifacts.local_path(root, path))
        entries = []
        for directory in sorted((run / "checkpoints").iterdir()):
            if directory.name.startswith(".incomplete-"):
                # Never infer that an interrupted write is disposable.
                continue
            match = EPOCH.fullmatch(directory.name)
            if not match or not directory.is_dir() or directory.is_symlink():
                raise ValueError("Unrecognized checkpoint directory; retain it for investigation")
            epoch = int(match[1])
            receipt = read(root, directory / "checkpoint.json", evidence)
            if (
                receipt["epoch"] != epoch
                or receipt["state"]["epoch"] != epoch
                or receipt["run_identity"] != evidence[name + "/identity.json"]
                or receipt.get("baseline_sha256") != evidence[name + "/baseline.json"]
            ):
                raise ValueError("Checkpoint state or provenance is inconsistent")
            files = (
                {"training.pdstate": receipt["training_sha256"]}
                if kind == "ocr"
                else receipt["files"]
            )
            required = FORMATS[kind]["files"] - {"checkpoint.json"}
            if set(files) != required:
                raise ValueError("Incomplete checkpoint contract; optimizer/random state required")
            present = {p.name for p in directory.iterdir()}
            if present - FORMATS[kind]["files"]:
                raise ValueError("Unknown checkpoint contents; do not remove any of them")
            payloads, missing = {}, []
            for leaf, digest in files.items():
                if not isinstance(digest, str) or not HEX.fullmatch(digest):
                    raise ValueError("Invalid checkpoint content digest")
                path = directory / leaf
                file_name = relative(root, path)
                artifacts.local_path(root, file_name)
                if not path.exists():
                    if leaf not in FORMATS[kind]["payloads"] or removed.get(file_name) != digest:
                        raise ValueError(
                            "Missing checkpoint file without a completed removal receipt"
                        )
                    missing.append(file_name)
                    continue
                info = path.lstat()
                if not stat.S_ISREG(info.st_mode) or info.st_nlink != 1:
                    raise ValueError("Checkpoint files must be regular, independently owned files")
                if leaf in FORMATS[kind]["payloads"]:
                    payloads[file_name] = {"sha256": digest, "bytes": info.st_size}
                else:
                    read(root, path, evidence)
                    if evidence[file_name] != digest:
                        raise ValueError("Checkpoint metrics/configuration changed")
            entries.append(
                {
                    "epoch": epoch,
                    "directory": relative(root, directory),
                    "receipt_sha256": evidence[relative(root, directory / "checkpoint.json")],
                    "state": receipt["state"],
                    "payloads": payloads,
                    "payload_digests": [files[leaf] for leaf in sorted(FORMATS[kind]["payloads"])],
                    "removed": missing,
                }
            )
        if not entries:
            raise ValueError("No complete checkpoint; preserve the run")
        protected = {entries[-1]["epoch"]: ["latest complete resumable epoch"]}
        best = entries[-1]["state"].get("best_epoch")
        protected.setdefault(best, []).append("best epoch recorded in latest resumable state")
        for control in ["progress.json", "selection.json", "result.json"]:
            path = run / control
            if path.exists():
                data = read(root, path, evidence)
                state = data.get("selection", data)
                chosen = (
                    state.get("best_epoch") if control != "selection.json" else state.get("epoch")
                )
                if chosen is not None:
                    protected.setdefault(chosen, []).append(control)
        if any(epoch not in {e["epoch"] for e in entries} for epoch in protected):
            raise ValueError("Selected/best epoch is missing")
        runs.append(
            {
                "run": name,
                "kind": kind,
                "identity": evidence[name + "/identity.json"],
                "entries": entries,
                "protected_epochs": protected,
            }
        )
    return runs, evidence


def reference_files(root):
    paths = set()
    tracked = artifacts.command(root, "git", "ls-files", "-z").split("\0")
    paths.update(root / p for p in tracked if p and Path(p).suffix in TEXT)
    for base in [root / ".local/runs", root / ".local/models", root / ".local/releases"]:
        for directory, folders, leaves in os.walk(base, followlinks=False):
            folders[:] = [
                n for n in folders if n not in SKIP and not (Path(directory) / n).is_symlink()
            ]
            paths.update(Path(directory) / n for n in leaves if Path(n).suffix in TEXT)
    return sorted(paths)


def reference_scopes(value, evidence, inherited=""):
    """Keep epoch context inside each run record of a combined report.

    A path->hash pair for metadata we retain is a reference to that receipt,
    not to its tensor payload. Other paths, checkpoint hashes and unknown
    evidence remain protective. Historical reports themselves are untouched.
    """
    if isinstance(value, dict):
        items = {k: v for k, v in value.items() if k not in evidence or evidence[k] != v}
        direct = []
        for key, child in items.items():
            direct.append(key)
            if isinstance(child, (str, int)):
                direct.append(str(child))
            elif isinstance(child, list):
                direct.extend(str(v) for v in child if isinstance(v, (str, int)))
        context = "\n".join(direct)
        yield (
            context,
            inherited,
            {
                child
                for key, child in items.items()
                if key in {"epoch", "selected_epoch", "best_epoch", "checkpoint_epoch"}
                and type(child) is int
            },
        )
        for child in items.values():
            if isinstance(child, (dict, list)):
                yield from reference_scopes(child, evidence, inherited + "\n" + context)
    elif isinstance(value, list):
        for child in value:
            yield from reference_scopes(child, evidence, inherited)
    elif isinstance(value, str):
        yield value, inherited, set()


def read_reference(path, needles):
    before = path.stat()
    oversized = before.st_size > MAX_REFERENCE_BYTES
    digest = hashlib.sha256()
    if oversized:
        # Large trace/log files must not turn maintenance into a memory workload.
        matches, overlap = set(), b""
        encoded = {token: token.encode() for token in needles}
        width = max(len(token) for token in encoded.values())
        with path.open("rb") as stream:
            while chunk := stream.read(1024 * 1024):
                digest.update(chunk)
                window = overlap + chunk
                matches.update(token for token, raw in encoded.items() if raw in window)
                overlap = window[-width:]
        text = "\n".join(sorted(matches))
    else:
        raw = path.read_bytes()
        digest.update(raw)
        text = raw.decode("utf-8", errors="replace")
    after = path.stat()
    if (before.st_size, before.st_mtime_ns, before.st_ino) != (
        after.st_size,
        after.st_mtime_ns,
        after.st_ino,
    ):
        raise ValueError("Reference metadata changed during inventory")
    return text, digest.hexdigest(), oversized


def references(root, runs, evidence):
    source_receipts = set(evidence)
    proofs = {}
    needles = {
        token for run in runs for token in [run["identity"], run["run"], Path(run["run"]).name]
    }
    needles.update(
        digest
        for run in runs
        for entry in run["entries"]
        for digest in [entry["receipt_sha256"], *entry["payload_digests"]]
    )
    for path in reference_files(root):
        name = relative(root, path)
        if name in source_receipts or path.is_symlink():
            continue
        text, digest, oversized = read_reference(path, needles)
        if not any(token in text for token in needles):
            continue
        try:
            if oversized:
                raise ValueError(
                    "Conservatively retain every state of runs named in oversized evidence"
                )
            documents = (
                [json.loads(line) for line in text.splitlines() if line.strip()]
                if path.suffix == ".jsonl"
                else [json.loads(text)]
            )
            scopes = (scope for doc in documents for scope in reference_scopes(doc, evidence))
        except (ValueError, TypeError):
            scopes = [(text, "", set())]
        mentioned = False
        for direct, inherited, epochs in scopes:
            for run in runs:
                associated = any(
                    token in direct + "\n" + inherited
                    for token in [run["identity"], run["run"], Path(run["run"]).name]
                )
                for entry in run["entries"]:
                    digests = {entry["receipt_sha256"], *entry["payload_digests"]}
                    local_epoch = Path(entry["directory"]).name
                    if (
                        (oversized and associated)
                        or entry["directory"] in direct
                        or (
                            associated
                            and re.search(r"(?<![\w-])" + local_epoch + r"(?![\w-])", direct)
                        )
                        or any(digest in direct for digest in digests)
                        or (associated and entry["epoch"] in epochs)
                    ):
                        reasons = run["protected_epochs"].setdefault(entry["epoch"], [])
                        if name not in reasons:
                            reasons.append(name)
                        mentioned = True
        if mentioned:
            proofs[name] = digest
    return proofs


def inventory(root, names, *, removed=None):
    runs, evidence = catalog(root, names, removed=removed)
    refs = references(root, runs, evidence)
    files, protected = {}, {}
    for run in runs:
        for entry in run["entries"]:
            keep = entry["epoch"] in run["protected_epochs"]
            if keep and entry["removed"]:
                raise ValueError(
                    "A required checkpoint was previously removed; restore it before proceeding"
                )
            (protected if keep else files).update(entry["payloads"])
    return {
        "schema_version": 1,
        "runs": runs,
        "metadata": evidence,
        "references": refs,
        "files": files,
        "protected": protected,
        "logical_bytes": sum(v["bytes"] for v in files.values()),
        "notice": "Metadata preview only; hashes, exclusive locks and process safety are checked before a deletion plan.",
    }


@contextmanager
def quiet(root, names):
    with artifacts.locked(root), ExitStack() as stack:
        for name in sorted(names):
            lock = artifacts.local_path(root, name + "/training.lock")
            stream = stack.enter_context(lock.open("rb"))
            fcntl.flock(stream, fcntl.LOCK_EX | fcntl.LOCK_NB)
        processes = artifacts.command(root, "ps", "-axo", "pid=,command=")
        for line in processes.splitlines():
            pid, _, command = line.strip().partition(" ")
            if int(pid) not in {os.getpid(), os.getppid()} and re.search(
                r"(?:ml/(?:training|evaluation)/|\.local/envs/(?:ocr|assistant))", command
            ):
                raise ValueError(
                    f"Active model process {pid}; wait for the evaluation/training window to close"
                )
        artifacts.guard(root, [name + "/checkpoints" for name in names])
        yield


def manifest(root, path):
    path = Path(path)
    if path.is_absolute():
        path = path.relative_to(root)
    if path.parent != Path(INDEX) or path.suffix != ".json":
        raise ValueError("Use a new JSON plan directly below .local/maintenance/checkpoints")
    return artifacts.local_path(root, str(path))


def verified_files(root, entries):
    result = {}
    for name, expected in entries.items():
        value = artifacts.fingerprint(artifacts.local_path(root, name))
        if value["sha256"] != expected["sha256"] or value["bytes"] != expected["bytes"]:
            raise ValueError("Checkpoint tensor changed; preserve the run")
        if (root / name).stat().st_nlink != 1:
            raise ValueError("Mutable checkpoint shares a writable inode")
        result[name] = value
    return result


def plan(root, names, destination):
    destination = manifest(root, destination)
    with quiet(root, names):
        value = inventory(root, names)
        value.update(
            root=str(root),
            tool_sha256=artifacts.sha(Path(__file__)),
            source_revision=artifacts.command(root, "git", "rev-parse", "HEAD").strip(),
        )
        value["files"] = verified_files(root, value["files"])
        value["protected"] = verified_files(root, value["protected"])
        value["allocated_bytes_upper_bound"] = sum(
            v["allocated_bytes"] for v in value["files"].values()
        )
        value["notice"] = (
            "Only tensor payloads listed in files may be removed. APFS block sharing prevents a guaranteed saving estimate. Historical receipts remain."
        )
        artifacts.write_new(destination, value)
    return value


def apply(root, source):
    source = manifest(root, source)
    value = json.loads(source.read_text())
    digest = artifacts.sha(source)
    journal = artifacts.local_path(root, relative(root, source.with_suffix(".journal.jsonl")))
    receipt = artifacts.local_path(root, relative(root, source.with_suffix(".receipt.json")))
    if (
        value.get("schema_version") != 1
        or value.get("root") != str(root)
        or value.get("tool_sha256") != artifacts.sha(Path(__file__))
    ):
        raise ValueError("Plan does not match this checkpoint-retention implementation")
    if receipt.exists():
        completed = json.loads(receipt.read_text())
        if completed["plan_sha256"] != digest:
            raise ValueError("Completed receipt does not match the plan")
        return completed
    previous = artifacts.events(journal)
    if previous and previous[0].get("plan_sha256") != digest:
        raise ValueError("Plan changed after removal started")
    intended = {e["path"] for e in previous if e["action"] == "unlink-intent"}
    removed = known_removed(root)
    removed.update({p: value["files"][p]["sha256"] for p in intended})
    names = [r["run"] for r in value["runs"]]
    with quiet(root, names):
        current = inventory(root, names, removed=removed)
        if current["metadata"] != value["metadata"]:
            raise ValueError("Run metadata/source changed since preview")
        eligible = set(current["files"]) | intended
        required = set(current["protected"])
        if not set(value["files"]) <= eligible or set(value["files"]) & required:
            raise ValueError("A checkpoint gained a protected selection/reference since preview")
        # Every intended path must still identify an allowed payload in the immutable receipt.
        allowed = {}
        for run in current["runs"]:
            for entry in run["entries"]:
                if entry["epoch"] not in run["protected_epochs"]:
                    for leaf in FORMATS[run["kind"]]["payloads"]:
                        allowed[entry["directory"] + "/" + leaf] = entry
        if not set(value["files"]) <= set(allowed):
            raise ValueError("Plan contains a protected or non-checkpoint file")
        if any(
            value["files"][name]["sha256"] != current["files"][name]["sha256"]
            for name in value["files"]
            if name in current["files"]
        ):
            raise ValueError("Plan payload digest differs from its immutable checkpoint receipt")
        if set(value["protected"]) != set(current["protected"]):
            raise ValueError("Protected checkpoint inventory changed since preview")
        verified_files(root, current["protected"])
        existing = {p: expected for p, expected in value["files"].items() if (root / p).exists()}
        if set(value["files"]) - set(existing) - intended:
            raise ValueError("File disappeared without a durable removal intent")
        checked = verified_files(root, existing)
        if any(checked[p] != value["files"][p] for p in checked):
            raise ValueError("Checkpoint file identity changed since preview")
        if not previous:
            artifacts.append(
                journal,
                {
                    "action": "started",
                    "plan_sha256": digest,
                    "free_bytes": shutil.disk_usage(root).free,
                },
            )
        for name in sorted(existing):
            path = artifacts.local_path(root, name)
            if artifacts.fingerprint(path) != value["files"][name] or path.stat().st_nlink != 1:
                raise ValueError("Checkpoint changed immediately before removal")
            artifacts.append(journal, {"action": "unlink-intent", "path": name})
            path.unlink()
            artifacts.append(
                journal,
                {"action": "removed", "path": name, "sha256": value["files"][name]["sha256"]},
            )
        verified_files(root, value["protected"])
        if any(
            artifacts.sha(artifacts.local_path(root, name)) != digest
            for name, digest in value["metadata"].items()
        ):
            raise ValueError("Protected metadata changed during cleanup; retain the journal")
        started = artifacts.events(journal)[0]
        result = {
            "schema_version": 1,
            "plan_sha256": digest,
            "removed": sorted(value["files"]),
            "logical_bytes_removed": sum(v["bytes"] for v in value["files"].values()),
            "measured_free_bytes_delta": shutil.disk_usage(root).free - started["free_bytes"],
            "protected_checkpoint_files_verified": len(value["protected"]),
            "recovery": "Retained best/latest resume normally. Removed intermediate tensors require re-running pinned training; byte-identical reconstruction is not promised.",
            "historical_reports_modified": False,
        }
        artifacts.write_new(receipt, result)
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=["inventory", "plan", "apply"])
    parser.add_argument("--run", action="append", default=[], help="Project-relative training run")
    parser.add_argument("--manifest", type=Path)
    args = parser.parse_args()
    if args.action != "apply" and not args.run:
        parser.error("At least one explicit --run is required")
    if args.action != "inventory" and args.manifest is None:
        parser.error("A new/existing --manifest is required")
    result = (
        inventory(ROOT, args.run)
        if args.action == "inventory"
        else plan(ROOT, args.run, args.manifest)
        if args.action == "plan"
        else apply(ROOT, args.manifest)
    )
    if args.action == "inventory" and args.manifest is not None:
        artifacts.write_new(manifest(ROOT, args.manifest), result)
    print(json.dumps(result, indent=2, ensure_ascii=False))


if __name__ == "__main__":
    main()
