"""Restore a pinned converter, then build its desktop runtime offline."""

import argparse
import fcntl
import json
import subprocess
import sys
import tempfile
from pathlib import Path

from restore import REGISTRY, ROOT, sha

sys.path.insert(0, str(ROOT / "tooling/dev"))
import workspace  # noqa: E402

SOURCE = ROOT / ".local/upstream/llama.cpp"
BUILD = ROOT / ".local/builds/assistant-runtime-41fc758"
UV = "uv"
CMAKE = [str(UV), "run", "--locked", "--with", "cmake==3.31.6", "cmake"]


def run(command, *, capture=False, offline=False):
    env = workspace.environment(ROOT)
    if offline:
        env["UV_OFFLINE"] = "1"
    result = subprocess.run(
        command,
        cwd=ROOT,
        env=env,
        check=True,
        text=True,
        stdout=subprocess.PIPE if capture else None,
    )
    return result.stdout.strip() if capture else None


def verify_source(registry, source=None):
    source = SOURCE if source is None else source
    revision = run(["git", "-C", str(source), "rev-parse", "HEAD"], capture=True)
    dirty = run(["git", "-C", str(source), "status", "--porcelain"], capture=True)
    if revision != registry["converter_revision"] or dirty:
        raise ValueError(
            "Converter revision differs or has local changes; preserve it and use the pinned source"
        )


def restore_source(registry):
    if SOURCE.exists() or SOURCE.is_symlink():
        verify_source(registry)
        return
    SOURCE.parent.mkdir(parents=True, exist_ok=True)
    with (SOURCE.parent / f".{SOURCE.name}.restore.lock").open("a") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        if SOURCE.exists() or SOURCE.is_symlink():
            verify_source(registry)
            return
        staging = Path(tempfile.mkdtemp(prefix=f".{SOURCE.name}-restore-", dir=SOURCE.parent))
        try:
            run(
                [
                    "git",
                    "clone",
                    "--filter=blob:none",
                    "--no-checkout",
                    registry["converter_repository"],
                    str(staging),
                ]
            )
            run(["git", "-C", str(staging), "checkout", "--detach", registry["converter_revision"]])
            verify_source(registry, staging)
            if SOURCE.exists() or SOURCE.is_symlink():
                raise FileExistsError(f"Source appeared during restore; preserved: {SOURCE}")
            staging.rename(SOURCE)
        except BaseException as error:
            error.add_note(f"Unpublished restore checkout preserved at {staging}")
            raise


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=["restore", "build"])
    args = parser.parse_args()
    registry = json.loads(REGISTRY.read_text())
    if args.action == "restore":
        restore_source(registry)
        run([*CMAKE, "--version"])
        return
    verify_source(registry)
    flags = [
        "-DCMAKE_BUILD_TYPE=Release",
        "-DLLAMA_BUILD_TESTS=OFF",
        "-DLLAMA_BUILD_SERVER=OFF",
        "-DLLAMA_BUILD_APP=OFF",
        "-DLLAMA_OPENSSL=OFF",
    ]
    run([*CMAKE, "-S", str(SOURCE), "-B", str(BUILD), *flags], offline=True)
    run([*CMAKE, "--build", str(BUILD), "--target", "llama-completion", "-j", "4"], offline=True)
    receipt = {
        "source_revision": registry["converter_revision"],
        "builder_sha256": sha(__file__),
        "cmake": run([*CMAKE, "--version"], capture=True, offline=True),
        "compiler": run(["xcrun", "clang", "--version"], capture=True),
        "sdk": run(["xcrun", "--sdk", "macosx", "--show-sdk-build-version"], capture=True),
        "flags": flags,
        "runtime_sha256": sha(BUILD / "bin/llama-completion"),
    }
    (BUILD / "receipt.json").write_text(json.dumps(receipt, indent=2) + "\n")


if __name__ == "__main__":
    main()
