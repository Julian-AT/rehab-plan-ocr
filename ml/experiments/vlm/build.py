"""Restore explicitly, then build and check the isolated region reader offline."""

import argparse
import fcntl
import importlib.util
import json
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tooling/dev"))
import workspace  # noqa: E402

import artifacts  # noqa: E402

spec = importlib.util.spec_from_file_location("assembly", ROOT / "tooling/build/assemble-native.py")
assembly = importlib.util.module_from_spec(spec)
spec.loader.exec_module(assembly)
LOCK = "ml/registry/runtime/vlm-experiments.lock.json"
SOURCE = ".local/upstream/llama.cpp"
PACKAGE = "ml/experiments/vlm"
CMAKE = ["uv", "run", "--locked", "--with", "cmake==3.31.6", "cmake"]


def verify_source(root=ROOT):
    expected = json.loads((root / LOCK).read_text())["runtime"]["revision"]
    source = root / SOURCE
    revision = subprocess.check_output(
        ["git", "-C", source, "rev-parse", "HEAD"], text=True
    ).strip()
    dirty = subprocess.check_output(
        ["git", "-C", source, "status", "--porcelain", "--untracked-files=all"], text=True
    ).strip()
    if revision != expected or dirty:
        raise ValueError("VLM runtime must match its pinned clean checkout; preserve local changes")
    return revision


def restore(root=ROOT):
    # This compatibility mapping is intentional: both consumers pin the same
    # upstream checkout. Refuse to silently switch either consumer to a new pin.
    lock = json.loads((root / LOCK).read_text())["runtime"]
    assistant = json.loads((root / "ml/registry/assistant-base.json").read_text())
    if (lock["repository"], lock["revision"]) != (
        assistant["converter_repository"],
        assistant["converter_revision"],
    ):
        raise ValueError("Shared runtime pins differ; isolate their checkouts before restoration")
    subprocess.run(
        [sys.executable, "ml/training/assistant/runtime.py", "restore"],
        cwd=root,
        env=workspace.environment(root),
        check=True,
    )
    verify_source(root)


def build(output, root=ROOT):
    relative = output.absolute().relative_to(root)
    if not relative.is_relative_to(".local/runs"):
        raise ValueError("Build evidence belongs below .local/runs")
    output = artifacts.local_path(root, str(relative))
    revision = verify_source(root)
    output.mkdir(parents=True, exist_ok=False, mode=0o700)
    base = artifacts.local_path(root, ".local/builds/vlm")
    base.mkdir(parents=True, exist_ok=True)
    env = dict(workspace.environment(root), UV_OFFLINE="1", CARGO_NET_OFFLINE="true")

    def capture(command):
        return subprocess.check_output(command, cwd=root, env=env, text=True).strip()

    def execute(command, name):
        with (output / (name + ".log")).open("x") as log:
            subprocess.run(
                command, cwd=root, env=env, stdout=log, stderr=subprocess.STDOUT, check=True
            )

    receipt = {"schema_version": 1, "status": "started", "qualified": False}
    try:
        own_files = [
            *sorted((root / PACKAGE).glob("*.cpp")),
            *sorted((root / PACKAGE).glob("*.h")),
            root / PACKAGE / "CMakeLists.txt",
            root / PACKAGE / "build.py",
            root / PACKAGE / "smoke.py",
            root / LOCK,
            root / "tooling/build/assemble-native.py",
            root / "tooling/dev/workspace.py",
            root / "config/storage/workspace.json",
            root / "pyproject.toml",
            root / "uv.lock",
        ]
        sources = {str(p.relative_to(root)): assembly.sha(p) for p in own_files}
        for path in own_files:
            target = output / "sources" / path.relative_to(root)
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(path, target)
        flags = [
            "-DCMAKE_BUILD_TYPE=Release",
            "-DGGML_NATIVE=OFF",
            "-DGGML_OPENMP=OFF",
            "-DGGML_CPU_KLEIDIAI=OFF",
            "-DFETCHCONTENT_FULLY_DISCONNECTED=ON",
        ]
        identity = {
            "runtime_revision": revision,
            "sources": sources,
            "flags": flags,
            # CMake also reads these on its first configure. A changed compiler,
            # SDK or inherited flags must not reuse another build's executable.
            "build_environment": {
                key: env.get(key)
                for key in [
                    "CC",
                    "CXX",
                    "CFLAGS",
                    "CXXFLAGS",
                    "LDFLAGS",
                    "ASMFLAGS",
                    "SDKROOT",
                    "MACOSX_DEPLOYMENT_TARGET",
                    "DEVELOPER_DIR",
                    "CMAKE_PREFIX_PATH",
                    "CMAKE_GENERATOR",
                    "CMAKE_GENERATOR_PLATFORM",
                    "CMAKE_GENERATOR_TOOLSET",
                ]
            },
            "cmake": capture([*CMAKE, "--version"]),
            "compiler": capture(["xcrun", "clang", "--version"]),
            "sdk": capture(["xcrun", "--sdk", "macosx", "--show-sdk-build-version"]),
        }
        receipt["identity"] = identity

        def produce(destination):
            with tempfile.TemporaryDirectory(prefix=".compile-", dir=base) as temporary:
                compile_dir = Path(temporary)
                try:
                    execute(
                        [
                            *CMAKE,
                            "-S",
                            str(root / PACKAGE),
                            "-B",
                            temporary,
                            f"-DLLAMA_SOURCE={root / SOURCE}",
                            *flags,
                        ],
                        "configure",
                    )
                    execute(
                        [
                            *CMAKE,
                            "--build",
                            temporary,
                            "--target",
                            "reha-vlm-read",
                            "--parallel",
                            "4",
                        ],
                        "build",
                    )
                    shutil.copy2(compile_dir / "reha-vlm-read", destination / "reha-vlm-read")
                    if verify_source(root) != revision or any(
                        assembly.sha(root / path) != digest for path, digest in sources.items()
                    ):
                        raise ValueError("Sources changed during the VLM build")
                finally:
                    cache = compile_dir / "CMakeCache.txt"
                    if cache.is_file():
                        shutil.copy2(cache, output / "CMakeCache.txt")

        with (base / "assembly.lock").open("a") as lock:
            fcntl.flock(lock, fcntl.LOCK_EX)
            product = assembly.cached_build(base / "products", identity, {"reha-vlm-read"}, produce)
            binary = product / "reha-vlm-read"
            receipt.update(binary=str(binary), binary_sha256=assembly.sha(binary))
            execute(
                [sys.executable, str(root / PACKAGE / "smoke.py"), "--binary", str(binary)], "smoke"
            )
            receipt["status"] = "built-and-smoke-tested-not-qualified"
        return receipt
    except BaseException as error:
        receipt.update(status="failed", error_type=type(error).__name__)
        raise
    finally:
        (output / "receipt.json").write_text(json.dumps(receipt, indent=2) + "\n")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=["restore", "build"])
    parser.add_argument("--run", type=Path)
    args = parser.parse_args()
    os.umask(0o077)
    if args.action == "restore":
        restore()
    else:
        if not args.run:
            parser.error("build requires a new --run below .local/runs")
        print(json.dumps(build(args.run), indent=2))


if __name__ == "__main__":
    main()
