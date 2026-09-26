"""Prepare and compile an explicitly experimental custom-provider simulator app.

This never installs an app or changes the ordinary project's declared dependencies.
The normal generated project is restored after compiling the separate trial output.
"""

import importlib.util
import json
import plistlib
import shutil
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
BASE = ROOT / ".local/builds/assistant-app-trial"
PACKAGE = ROOT / "packages/apple/LocalAssistant"
spec = importlib.util.spec_from_file_location(
    "native_assembly", Path(__file__).with_name("assemble-native.py")
)
assembly = importlib.util.module_from_spec(spec)
spec.loader.exec_module(assembly)


def run(*args):
    subprocess.run(args, cwd=ROOT, check=True)


def source_snapshot():
    names = (
        subprocess.check_output(
            [
                "git",
                "ls-files",
                "--cached",
                "--others",
                "--exclude-standard",
                "-z",
                "--",
                "apps/ios",
                "packages/apple",
                "tooling/build/build-assistant-trial.py",
            ],
            cwd=ROOT,
        )
        .decode()
        .split("\0")
    )
    return {name: assembly.sha(ROOT / name) for name in sorted(set(names)) if name}


def prepare():
    registry_path = ROOT / "ml/registry/assistant-development-001.json"
    registry = json.loads(registry_path.read_text())
    artifact = registry["artifact"]
    model = ROOT / artifact["path"]
    if (
        registry["qualified"] is not False
        or assembly.sha(model) != artifact["sha256"]
        or model.stat().st_size != artifact["bytes"]
    ):
        raise ValueError("The trial requires the recorded unqualified development model")
    framework = (PACKAGE / "RehaAssistantNative.xcframework").resolve()
    receipt = json.loads((framework.parent / "receipt.json").read_text())
    if "simulator" not in receipt["identity"] or not assembly.matches(
        framework.parent, receipt["identity"], {"RehaAssistantNative.xcframework/Info.plist"}
    ):
        raise ValueError("Build and verify the assistant simulator library first")
    native = receipt["identity"]["simulator"]
    sources = {
        str(p.relative_to(PACKAGE)): assembly.sha(p)
        for p in sorted((PACKAGE / "Native").rglob("*"))
        if p.is_file()
    }
    if native["identity"]["sources"] != sources or native["identity"][
        "builder_sha256"
    ] != assembly.sha(Path(__file__).with_name("build-assistant-native.py")):
        raise ValueError("Assistant native sources changed; rebuild the library")
    prompt = ROOT / "apps/ios/Features/Conversation/Resources/assistant-system-v1.txt"
    license_source = ROOT / ".local/upstream/llama.cpp/LICENSE"
    model_license = ROOT / ".local/models/assistant/qwen3-0.6b/LICENSE"
    base = json.loads((ROOT / "ml/registry/assistant-base.json").read_text())
    if native["identity"]["source_revision"] != base["converter_revision"] or native["identity"][
        "cache_helper_sha256"
    ] != assembly.sha(Path(__file__).with_name("assemble-native.py")):
        raise ValueError("Native runtime revision or cache verifier changed")
    if assembly.sha(model_license) != base["files"]["LICENSE"]["sha256"]:
        raise ValueError("Model license differs from the pinned source")
    native_license = (
        ROOT
        / ".local/builds/assistant-native/libraries"
        / assembly.key(native["identity"])
        / "llama-license.txt"
    )
    if assembly.sha(license_source) != assembly.sha(native_license):
        raise ValueError("Native license differs from the compiled source")
    manifest = {
        "schema_version": 1,
        "qualified": False,
        "model_id": registry["id"],
        "model_sha256": artifact["sha256"],
        "model_bytes": artifact["bytes"],
        "prompt_sha256": assembly.sha(prompt),
        "native_identity": assembly.key(native),
        "registry_sha256": assembly.sha(registry_path),
        "notices": {
            "llama-license.txt": assembly.sha(license_source),
            "qwen-license.txt": assembly.sha(model_license),
        },
    }

    def produce(destination):
        folder = destination / "assistant-trial"
        folder.mkdir()
        run("cp", "-c", str(model), str(folder / "assistant.gguf"))
        shutil.copyfile(license_source, folder / "llama-license.txt")
        shutil.copyfile(model_license, folder / "qwen-license.txt")
        (folder / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")

    assets = assembly.cached_build(
        BASE / "assets",
        manifest,
        {
            "assistant-trial/assistant.gguf",
            "assistant-trial/manifest.json",
            "assistant-trial/llama-license.txt",
            "assistant-trial/qwen-license.txt",
        },
        produce,
    )
    assembly.publish_link(
        ROOT / ".local/models/runtime/assistant-trial", assets / "assistant-trial"
    )
    return manifest


def main():
    BASE.mkdir(parents=True, exist_ok=True)
    sources = source_snapshot()
    # These paths perform read-only manifest verification and normal source builds.
    run("sh", "tooling/build/build-native.sh", "simulator")
    manifest = prepare()
    try:
        run(
            "xcodegen",
            "generate",
            "--spec",
            "apps/ios/assistant-trial.yml",
            "--project",
            "apps/ios",
        )
        run(
            "xcodebuild",
            "-project",
            "apps/ios/Termine.xcodeproj",
            "-scheme",
            "Termine",
            "-configuration",
            "Debug",
            "-sdk",
            "iphonesimulator",
            "-destination",
            "generic/platform=iOS Simulator",
            "-derivedDataPath",
            str(BASE / "DerivedData"),
            "CODE_SIGNING_ALLOWED=NO",
            "build",
        )
        app = BASE / "DerivedData/Build/Products/Debug-iphonesimulator/Laßnitzhöhe.app"
        info = plistlib.loads((app / "Info.plist").read_bytes())
        if not info.get("REHAExperimentalAssistant"):
            raise ValueError("Trial app is missing its release-exclusion marker")
        bundled = app / "assistant-trial"
        if (
            json.loads((bundled / "manifest.json").read_text()) != manifest
            or assembly.sha(bundled / "assistant.gguf") != manifest["model_sha256"]
        ):
            raise ValueError("Bundled trial model differs from its verified artifact")
        for name, digest in manifest["notices"].items():
            if assembly.sha(bundled / name) != digest:
                raise ValueError("Bundled trial notice differs from its verified source")
        if source_snapshot() != sources:
            raise ValueError("App sources changed during the trial build")
        report = {
            "qualified": False,
            "installed": False,
            "physical_device": False,
            "source_revision": subprocess.check_output(
                ["git", "rev-parse", "HEAD"], cwd=ROOT, text=True
            ).strip(),
            "sources": sources,
            "xcode": subprocess.check_output(["xcodebuild", "-version"], text=True).strip(),
            "trial_manifest": manifest,
            "app": str(app.relative_to(ROOT)),
            "app_binary_sha256": assembly.sha(app / "Termine.debug.dylib"),
            "builder_sha256": assembly.sha(Path(__file__)),
            "activation_argument": "--assistant-model-trial",
        }
        (BASE / "verification.json").write_text(json.dumps(report, indent=2) + "\n")
        print(json.dumps(report, indent=2))
    finally:
        run("xcodegen", "generate", "--spec", "apps/ios/project.yml", "--project", "apps/ios")


if __name__ == "__main__":
    main()
