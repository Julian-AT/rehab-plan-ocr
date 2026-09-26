#!/usr/bin/env python3
"""Shared local/CI entry points. Downloads are versioned and checksum verified."""

import argparse
import hashlib
import json
import os
import platform
import re
import shutil
import subprocess
import sys
import tarfile
import tempfile
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
LOCK = json.loads((ROOT / "tool-versions.json").read_text())
VERSIONS = LOCK["versions"]
BIN = ROOT / ".tools/bin"
ENV = dict(os.environ)
ENV["PATH"] = os.pathsep.join([str(BIN), str(Path.home() / ".cargo/bin"), ENV.get("PATH", "")])
ENV.update(CARGO_PROFILE_DEV_DEBUG="0", CARGO_INCREMENTAL="0")
APPLE = sys.platform == "darwin"


def run(*command, capture=False, env=None):
    if not capture:
        print("+ " + " ".join(map(str, command)), flush=True)
    result = subprocess.run(
        list(map(str, command)),
        cwd=ROOT,
        env=env or ENV,
        check=True,
        text=True,
        stdout=subprocess.PIPE if capture else None,
    )
    return result.stdout.strip() if capture else None


def installed(tool):
    if shutil.which(tool, path=ENV["PATH"]) is None:
        return False
    output = run(tool, "--version", capture=True)
    return re.search(r"(?<![\d.])" + re.escape(VERSIONS[tool]) + r"(?![\d.])", output) is not None


def space(gib):
    free = shutil.disk_usage(ROOT).free / 1024**3
    if free < gib:
        raise RuntimeError(
            f"{free:.1f} GiB frei; dieser Schritt benötigt mindestens {gib:g} GiB. Private Daten bleiben erhalten."
        )
    print(f"Speicherprüfung: {free:.1f} GiB frei (Mindestreserve {gib:g} GiB).")


def bootstrap():
    space(1)
    system = "darwin" if APPLE else "linux"
    arch = {"arm64": "arm64", "aarch64": "arm64", "x86_64": "amd64"}[platform.machine()]
    BIN.mkdir(parents=True, exist_ok=True)
    for tool in ["uv", "shellcheck", "shfmt"] + (["xcodegen"] if APPLE else []):
        if installed(tool):
            continue
        artifact = LOCK["downloads"][tool][f"{system}-{arch}"]
        with tempfile.TemporaryDirectory(prefix="reha-tool-") as temporary:
            path = Path(temporary) / "download"
            run(
                "curl",
                "--fail",
                "--location",
                "--silent",
                "--show-error",
                "--max-time",
                "60",
                artifact["url"],
                "--output",
                path,
            )
            if hashlib.sha256(path.read_bytes()).hexdigest() != artifact["sha256"]:
                raise RuntimeError(f"Prüfsumme für {tool} stimmt nicht.")
            if artifact["url"].endswith(".zip"):
                with zipfile.ZipFile(path) as archive:
                    names = [
                        n
                        for n in archive.namelist()
                        if Path(n).name == tool and not n.endswith("/")
                    ]
                    if len(names) != 1:
                        raise RuntimeError(f"Werkzeugarchiv {tool} ist nicht eindeutig.")
                    data = archive.read(names[0])
            elif artifact["url"].endswith(".tar.gz"):
                with tarfile.open(path) as archive:
                    members = [
                        m for m in archive.getmembers() if m.isfile() and Path(m.name).name == tool
                    ]
                    if len(members) != 1:
                        raise RuntimeError(f"Werkzeugarchiv {tool} ist nicht eindeutig.")
                    data = archive.extractfile(members[0]).read()
            else:
                data = path.read_bytes()
            target = BIN / tool
            temporary_binary = target.with_suffix(".partial")
            temporary_binary.write_bytes(data)
            temporary_binary.chmod(0o755)
            temporary_binary.replace(target)
        if not installed(tool):
            raise RuntimeError(f"Version von {tool} stimmt nicht.")
    run("uv", "python", "install", VERSIONS["python"])
    run("uv", "sync", "--locked")
    if VERSIONS["rust"] not in run("rustc", "--version", capture=True):
        run(
            "rustup",
            "toolchain",
            "install",
            VERSIONS["rust"],
            "--profile",
            "minimal",
            "--component",
            "clippy,rustfmt",
        )
        ENV["RUSTUP_TOOLCHAIN"] = VERSIONS["rust"]
    if APPLE:
        run("rustup", "target", "add", "aarch64-apple-ios", "aarch64-apple-ios-sim")


def doctor(portable=False):
    if VERSIONS["rust"] not in run("rustc", "--version", capture=True):
        run("rustup", "run", VERSIONS["rust"], "rustc", "--version", capture=True)
        ENV["RUSTUP_TOOLCHAIN"] = VERSIONS["rust"]
    for tool in ["uv", "shellcheck", "shfmt"] + (["xcodegen"] if APPLE and not portable else []):
        if not installed(tool):
            raise RuntimeError(f"{tool} {VERSIONS[tool]} fehlt. make bootstrap ausführen.")
    for tool in ["rustc", "cargo"]:
        if VERSIONS["rust"] not in run(tool, "--version", capture=True):
            raise RuntimeError(f"{tool} muss Version {VERSIONS['rust']} verwenden.")
    if APPLE and not portable:
        if run("xcrun", "swift-format", "--version", capture=True) != VERSIONS["swift-format"]:
            raise RuntimeError("swift-format hat eine ungeprüfte Version.")
        version = run("xcodebuild", "-version", capture=True)
        if not any(f"Build version {build}" in version for build in VERSIONS["xcode-builds"]):
            raise RuntimeError("Xcode-Build stimmt nicht mit tool-versions.json überein.")
        print(version)
    print("Werkzeugversionen geprüft.")


def files(suffix):
    names = run(
        "git", "ls-files", "-z", "--cached", "--others", "--exclude-standard", capture=True
    ).split("\0")
    return sorted(
        {
            name
            for name in names
            if name.endswith(suffix)
            and (ROOT / name).is_file()
            and not name.startswith(
                (
                    "packages/apple/VoiceActivity/Sources/",
                    "packages/apple/RehaCore/Sources/",
                    "artifacts/",
                    "models/private/",
                    "data/private/",
                )
            )
        }
    )


def style(write, portable):
    doctor(portable)
    run("cargo", "fmt", "--all", *([] if write else ["--", "--check"]))
    run("uv", "run", "--locked", "ruff", "format", *([] if write else ["--check"]), *files(".py"))
    run("uv", "run", "--locked", "ruff", "check", *(["--fix"] if write else []), *files(".py"))
    run("shfmt", "-i", "2", "-ci", "-sr", "-w" if write else "-d", *files(".sh"))
    if not write:
        run("shellcheck", "--severity=style", *files(".sh"))
        run("cargo", "clippy", "--locked", "--workspace", "--all-targets", "--", "-D", "warnings")
    if APPLE and not portable:
        run(
            "xcrun",
            "swift-format",
            "format" if write else "lint",
            "--configuration",
            ".swift-format",
            *(["--in-place"] if write else ["--strict"]),
            *files(".swift"),
        )


def tests(portable):
    doctor(portable)
    space(1)
    run("cargo", "test", "--locked", "--workspace")
    for test in sorted((ROOT / "tests").glob("test-*.py")):
        run("uv", "run", "--locked", "python", test)
    run("cargo", "build", "--locked", "-p", "reha-core", "--bin", "reha")
    run(
        "uv",
        "run",
        "--locked",
        "python",
        "tests/verify-ics.py",
        env=dict(ENV, REHA_BINARY=str(ROOT / "target/debug/reha")),
    )
    if APPLE and not portable:
        for probe in [
            "agenda-projection",
            "agenda",
            "voice-rules",
            "conversation-rules",
            "ordered-settings",
            "diagnostics",
            "intake-erasure",
            "vad",
            "native-bindings",
        ]:
            run("sh", f"scripts/test-{probe}.sh")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "action",
        choices=["bootstrap", "doctor", "format", "lint", "test", "test-ios", "build", "space"],
    )
    parser.add_argument("value", nargs="?")
    parser.add_argument("--portable", action="store_true")
    args = parser.parse_args()
    if args.action == "bootstrap":
        bootstrap()
    elif args.action == "doctor":
        doctor(args.portable)
    elif args.action == "space":
        space(float(args.value or 2))
    elif args.action in ["format", "lint"]:
        style(args.action == "format", args.portable)
    elif args.action == "test":
        tests(args.portable)
    elif args.action == "test-ios":
        doctor()
        space(4)
        run("sh", "scripts/test-calendar-events.sh")
        run("sh", "scripts/build-native.sh", "test")
    else:
        doctor()
        space(3)
        run("sh", "scripts/build-native.sh", args.value or "simulator")


if __name__ == "__main__":
    try:
        main()
    except (RuntimeError, subprocess.CalledProcessError) as error:
        print(str(error), file=sys.stderr)
        raise SystemExit(1) from error
