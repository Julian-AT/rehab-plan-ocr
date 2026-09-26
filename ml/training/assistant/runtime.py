"""Restore a pinned converter, then build its desktop runtime offline."""

import argparse
import json
import os
import subprocess

from restore import REGISTRY, ROOT, sha

SOURCE = ROOT / ".local/upstream/llama.cpp"
BUILD = ROOT / ".local/builds/assistant-runtime-41fc758"
UV = ROOT / ".tools/bin/uv"
CMAKE = [str(UV), "run", "--locked", "--with", "cmake==3.31.6", "cmake"]


def run(command, *, capture=False, offline=False):
    env = dict(os.environ, UV_OFFLINE="1") if offline else None
    result = subprocess.run(
        command,
        cwd=ROOT,
        env=env,
        check=True,
        text=True,
        stdout=subprocess.PIPE if capture else None,
    )
    return result.stdout.strip() if capture else None


def verify_source(registry):
    revision = run(["git", "-C", str(SOURCE), "rev-parse", "HEAD"], capture=True)
    dirty = run(["git", "-C", str(SOURCE), "status", "--porcelain"], capture=True)
    if revision != registry["converter_revision"] or dirty:
        raise ValueError(
            "Converter revision differs or has local changes; preserve it and use the pinned source"
        )


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=["restore", "build"])
    args = parser.parse_args()
    registry = json.loads(REGISTRY.read_text())
    if args.action == "restore":
        if not SOURCE.exists():
            SOURCE.parent.mkdir(parents=True, exist_ok=True)
            run(
                [
                    "git",
                    "clone",
                    "--filter=blob:none",
                    "--no-checkout",
                    registry["converter_repository"],
                    str(SOURCE),
                ]
            )
            run(["git", "-C", str(SOURCE), "checkout", "--detach", registry["converter_revision"]])
        verify_source(registry)
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
