#!/usr/bin/env python3
"""Shared local/CI entry points. Downloads are versioned and checksum verified."""

import argparse
import hashlib
import json
import math
import platform
import re
import shutil
import subprocess
import sys
import tarfile
import tempfile
import zipfile
from pathlib import Path

import workspace

ROOT = Path(__file__).resolve().parents[2]
LOCK = json.loads((ROOT / "config/toolchains/versions.json").read_text())
VERSIONS = LOCK["versions"]
BIN = workspace.location("tools", ROOT) / "bin"
ENV = workspace.environment(ROOT)
ENV.update(CARGO_PROFILE_DEV_DEBUG="0", CARGO_INCREMENTAL="0", RUSTUP_TOOLCHAIN=VERSIONS["rust"])
APPLE = sys.platform == "darwin"
XCODEGEN_PRESETS = {
    "base.yml",
    "Configs/debug.yml",
    "Configs/release.yml",
    "Platforms/iOS.yml",
    "Products/app-extension.yml",
    "Products/bundle.ui-testing.yml",
}


def xcodegen_resources_ready(binary):
    resources = Path(binary).resolve().parent.parent / "share/xcodegen"
    if not all((resources / "SettingPresets" / name).is_file() for name in XCODEGEN_PRESETS):
        return False
    if Path(binary).resolve() == (BIN / "xcodegen").resolve():
        try:
            manifest = json.loads((resources / "installation.json").read_text())
            expected = LOCK["downloads"]["xcodegen"]["darwin-arm64"]["sha256"]
            return (
                manifest["archive_sha256"] == expected
                and all(
                    (resources / name).is_file()
                    and hashlib.sha256((resources / name).read_bytes()).hexdigest() == digest
                    for name, digest in manifest["files"].items()
                )
                and XCODEGEN_PRESETS.issubset(
                    name.removeprefix("SettingPresets/") for name in manifest["files"]
                )
            )
        except (OSError, ValueError, KeyError):
            return False
    return True


def install_xcodegen_resources(archive, archive_sha256, prefix):
    """Keep the release's sibling share directory; the binary alone silently omits defaults."""
    files = {"LICENSE": archive.read("xcodegen/LICENSE")}
    marker = "xcodegen/share/xcodegen/"
    for entry in archive.infolist():
        if not entry.filename.startswith(marker) or entry.is_dir():
            continue
        name = entry.filename.removeprefix(marker)
        path = Path(name)
        if (
            path.is_absolute()
            or ".." in path.parts
            or path.parts[0] != "SettingPresets"
            or path.suffix != ".yml"
            or name in files
        ):
            raise ValueError("Unexpected or duplicate XcodeGen preset path")
        files[name] = archive.read(entry)
    if not XCODEGEN_PRESETS.issubset(name.removeprefix("SettingPresets/") for name in files):
        raise ValueError("XcodeGen release is missing required setting presets")
    parent = prefix / "share"
    parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="xcodegen-", dir=parent) as staging:
        temporary = Path(staging) / "xcodegen"
        temporary.mkdir()
        for name, data in files.items():
            path = temporary / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(data)
        (temporary / "installation.json").write_text(
            json.dumps(
                {
                    "archive_sha256": archive_sha256,
                    "files": {
                        name: hashlib.sha256(data).hexdigest()
                        for name, data in sorted(files.items())
                    },
                },
                indent=2,
            )
            + "\n"
        )
        target = parent / "xcodegen"
        if target.exists():
            # Only generated tool resources are replaced, after complete staging.
            shutil.rmtree(target)
        temporary.replace(target)


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


def tool_artifact(tool):
    system = "darwin" if APPLE else "linux"
    arch = {"arm64": "arm64", "aarch64": "arm64", "x86_64": "amd64"}[platform.machine()]
    return LOCK["downloads"][tool][f"{system}-{arch}"]


def file_sha256(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def tool_installation_ready(tool):
    binary = BIN / tool
    try:
        receipt = json.loads((BIN.parent / "receipts" / f"{tool}.json").read_text())
        return (
            receipt["schema_version"] == 1
            and receipt["version"] == VERSIONS[tool]
            and receipt["archive_sha256"] == tool_artifact(tool)["sha256"]
            and binary.is_file()
            and binary.stat().st_size == receipt["binary_bytes"]
            and file_sha256(binary) == receipt["binary_sha256"]
        )
    except (OSError, ValueError, KeyError, TypeError):
        return False


def installed(tool, *, local=False):
    binary = (
        str(BIN / tool)
        if local and (BIN / tool).is_file()
        else (None if local else shutil.which(tool, path=ENV["PATH"]))
    )
    if binary is None:
        return False
    if Path(binary).resolve() == (BIN / tool).resolve() and not tool_installation_ready(tool):
        return False
    try:
        output = run(binary, "--version", capture=True)
    except OSError:
        return False
    return re.search(
        r"(?<![\d.])" + re.escape(VERSIONS[tool]) + r"(?![\d.])", output
    ) is not None and (tool != "xcodegen" or xcodegen_resources_ready(binary))


def install_tool(tool):
    """Repair from verified archives; legacy binaries earn receipts only by comparison."""
    artifact = tool_artifact(tool)
    cache = BIN.parent / "downloads"
    cache.mkdir(parents=True, exist_ok=True)
    archive_path = cache / artifact["sha256"]
    BIN.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix=".install-", dir=cache) as temporary:
        staging = Path(temporary)
        if not archive_path.is_file() or file_sha256(archive_path) != artifact["sha256"]:
            download = staging / "download"
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
                download,
            )
            if file_sha256(download) != artifact["sha256"]:
                raise RuntimeError(f"Prüfsumme für {tool} stimmt nicht.")
            download.replace(archive_path)
        if artifact["url"].endswith(".zip"):
            with zipfile.ZipFile(archive_path) as archive:
                names = [
                    n for n in archive.namelist() if Path(n).name == tool and not n.endswith("/")
                ]
                if len(names) != 1:
                    raise RuntimeError(f"Werkzeugarchiv {tool} ist nicht eindeutig.")
                data = archive.read(names[0])
                if tool == "xcodegen" and not xcodegen_resources_ready(BIN / tool):
                    install_xcodegen_resources(archive, artifact["sha256"], BIN.parent)
        elif artifact["url"].endswith(".tar.gz"):
            with tarfile.open(archive_path) as archive:
                members = [
                    m for m in archive.getmembers() if m.isfile() and Path(m.name).name == tool
                ]
                if len(members) != 1:
                    raise RuntimeError(f"Werkzeugarchiv {tool} ist nicht eindeutig.")
                data = archive.extractfile(members[0]).read()
        else:
            data = archive_path.read_bytes()
        digest = hashlib.sha256(data).hexdigest()
        target = BIN / tool
        if target.is_symlink() or not target.is_file() or file_sha256(target) != digest:
            binary = staging / tool
            binary.write_bytes(data)
            binary.chmod(0o755)
            binary.replace(target)
        elif target.stat().st_mode & 0o111 != 0o111:
            target.chmod(0o755)
        receipt = staging / "receipt.json"
        receipt.write_text(
            json.dumps(
                {
                    "schema_version": 1,
                    "version": VERSIONS[tool],
                    "archive_sha256": artifact["sha256"],
                    "binary_sha256": digest,
                    "binary_bytes": len(data),
                },
                indent=2,
            )
            + "\n"
        )
        receipts = BIN.parent / "receipts"
        receipts.mkdir(exist_ok=True)
        receipt.replace(receipts / f"{tool}.json")


def space(gib, *, working_reserve=False):
    free = shutil.disk_usage(ROOT).free / 1024**3
    reserve = (
        json.loads((ROOT / "config/storage/retention.json").read_text())["reserve_gib"]
        if working_reserve
        else 0
    )
    required = reserve + gib
    if not math.isfinite(gib) or gib < 0 or free < required:
        raise RuntimeError(
            f"{free:.1f} GiB frei; benötigt: {reserve:g} GiB Reserve + {gib:g} GiB Spitzenbedarf. Private Daten bleiben erhalten."
        )
    print(f"Speicherprüfung: {free:.1f} GiB frei (benötigt {required:g} GiB).")


def bootstrap():
    space(1)
    workspace.prepare(ROOT)
    BIN.mkdir(parents=True, exist_ok=True)
    for tool in ["uv", "shellcheck", "shfmt"] + (["xcodegen"] if APPLE else []):
        if installed(tool, local=True):
            continue
        binary = BIN / tool
        if not binary.is_symlink() and tool_installation_ready(tool):
            mode = binary.stat().st_mode
            if mode & 0o111 != 0o111:
                binary.chmod(mode | 0o111)
                if installed(tool, local=True):
                    continue
        install_tool(tool)
        if not installed(tool, local=True):
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
    import tomllib

    toolchain = tomllib.loads((ROOT / "rust-toolchain.toml").read_text())["toolchain"]
    if toolchain["channel"] != VERSIONS["rust"]:
        raise RuntimeError("Rust toolchain file differs from config/toolchains/versions.json.")
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
            raise RuntimeError(
                "Xcode-Build stimmt nicht mit config/toolchains/versions.json überein."
            )
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
                    ".local/",
                    "artifacts/",
                    "models/private/",
                    "data/private/",
                )
            )
        }
    )


def style(write, portable):
    if not write:
        # Clippy compiles the workspace; keep the same reserve as an app build.
        space(4, working_reserve=True)
    doctor(portable)
    run("cargo", "fmt", "--all", *([] if write else ["--", "--check"]))
    run("uv", "run", "--locked", "ruff", "format", *([] if write else ["--check"]), *files(".py"))
    run("uv", "run", "--locked", "ruff", "check", *(["--fix"] if write else []), *files(".py"))
    run("shfmt", "-i", "2", "-ci", "-sr", "-w" if write else "-d", *files(".sh"))
    if not write:
        run("python3", "tooling/release/runtime_inventory.py", "verify")
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
    # Tests compile Rust and native probes even when previous outputs are absent.
    space(4, working_reserve=True)
    doctor(portable)
    run("cargo", "test", "--locked", "--workspace")
    tool_tests()
    run("cargo", "build", "--locked", "-p", "reha-cli", "--bin", "reha")
    run(
        "uv",
        "run",
        "--locked",
        "python",
        "packages/rust/reha-cli/tests/verify-ics.py",
        env=dict(ENV, REHA_BINARY=str(workspace.cargo_directory(ROOT, ENV) / "debug/reha")),
    )
    run("sh", "tooling/checks/test-vad.sh")
    if APPLE and not portable:
        for probe in [
            "preview-fixtures",
            "agenda-projection",
            "agenda-cache",
            "agenda-links",
            "event-session",
            "archive",
            "plan-loading",
            "replacement-preview",
            "agenda",
            "voice-rules",
            "voice-flow",
            "conversation-rules",
            "conversation-state",
            "conversation-replies",
            "calendar-answers",
            "calendar-insights",
            "plan-evidence",
            "calendar-read-contracts",
            "calendar-mutation-contracts",
            "calendar-import-contracts",
            "calendar-timezone",
            "interpretation-provider",
            "assistant-request",
            "custom-assistant-provider",
            "interpretation-evaluation",
            "input-audio",
            "system-speech",
            "capture-preparation",
            "native-photo",
            "native-text-recognition",
            "speech-input",
            "recognition-turn",
            "ordered-settings",
            "service-request",
            "notification-deadline",
            "diagnostics",
            "intake-erasure",
            "scan-attempts",
            "intake-provider",
            "temporary-privacy",
            "intake-size",
            "pdf-text-evidence",
            "native-bindings",
        ]:
            run("sh", f"tooling/checks/test-{probe}.sh")


def tool_tests():
    for test in sorted([*(ROOT / "tooling").rglob("test-*.py"), *(ROOT / "ml").rglob("test-*.py")]):
        run("uv", "run", "--locked", "python", test)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "action",
        choices=[
            "bootstrap",
            "doctor",
            "format",
            "lint",
            "test",
            "test-tools",
            "test-ios",
            "build",
            "space",
        ],
    )
    parser.add_argument("value", nargs="?")
    parser.add_argument("--portable", action="store_true")
    args = parser.parse_args()
    if args.action == "bootstrap":
        bootstrap()
    elif args.action == "doctor":
        doctor(args.portable)
    elif args.action == "space":
        space(float(args.value or 2), working_reserve=True)
    elif args.action in ["format", "lint"]:
        style(args.action == "format", args.portable)
    elif args.action == "test":
        tests(args.portable)
    elif args.action == "test-tools":
        tool_tests()
    elif args.action == "test-ios":
        doctor()
        space(4, working_reserve=True)
        run("sh", "tooling/checks/test-calendar-events.sh")
        run("sh", "tooling/build/build-native.sh", "test")
    else:
        doctor()
        space(4, working_reserve=True)
        run("sh", "tooling/build/build-native.sh", args.value or "simulator")


if __name__ == "__main__":
    try:
        main()
    except (RuntimeError, subprocess.CalledProcessError) as error:
        print(str(error), file=sys.stderr)
        raise SystemExit(1) from error
