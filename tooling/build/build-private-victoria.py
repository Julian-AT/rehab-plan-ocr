"""Build the user's pinned Victoria voice without changing the public native build.

Owns an independent Swift package/XCFramework. The normal RehaCore binary link and
public release exclusions are preserved. No phone installation happens here.
"""

import argparse
import importlib.util
import json
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
BASE = ROOT / ".local/builds/private-victoria"
sys.path.insert(0, str(ROOT / "tooling/dev"))
sys.path.insert(0, str(ROOT / "tooling/release"))
sys.path.insert(0, str(ROOT / "tooling/build"))
import private_speech  # noqa: E402
import product_generation  # noqa: E402
import runtime_inventory  # noqa: E402
import workspace  # noqa: E402


def module(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    result = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(result)
    return result


assembly = module("victoria_assembly", ROOT / "tooling/build/assemble-native.py")
assets = module("victoria_assets", ROOT / "tooling/build/verify-native-assets.py")


def run(*args, capture=False):
    env = workspace.environment(ROOT)
    env["IPHONEOS_DEPLOYMENT_TARGET"] = "26.0"
    result = subprocess.run(
        [str(a) for a in args],
        cwd=ROOT,
        env=env,
        check=True,
        text=True,
        stdout=subprocess.PIPE if capture else None,
    )
    return result.stdout.strip() if capture else None


def prepare():
    runtime_inventory.verify(ROOT)
    run("python3", "tooling/dev/artifacts.py", "space", "--peak-gib", "6")
    run(
        "python3",
        "tooling/build/build-phonemizer.py",
        "--verify",
        "--offline",
        "aarch64-apple-ios",
        "aarch64-apple-ios-sim",
    )
    lock = json.loads((ROOT / "ml/registry/runtime/kokoro.lock.json").read_text())
    assets.model_bundle(ROOT / ".local/models/runtime/kokoro-german", lock, strict=True)
    BASE.mkdir(parents=True, exist_ok=True)
    manifest = {
        "profile": "personal-victoria",
        "public_distribution": False,
        "cargo_features": ["kokoro"],
        "base_inventory_sha256": private_speech.sha(
            ROOT / "docs/third-party/runtime-inventory.json"
        ),
        "sources": {name: private_speech.sha(ROOT / name) for name in private_speech.SOURCES},
        "phonemizer": {},
        "libraries": {},
    }
    for variant, target in assembly.VARIANTS.items():
        assets.verify(ROOT, [target])
        run(
            "cargo",
            "build",
            "--locked",
            "--offline",
            "--release",
            "-p",
            "reha-ffi",
            "--lib",
            "--features",
            "kokoro",
            "--target",
            target,
        )
        archive = workspace.cargo_directory(ROOT) / target / "release/libreha_ffi.a"
        runtime = ROOT / ".local/models/runtime/runtime" / target / "libonnxruntime.a"
        phonemizer = ROOT / ".local/builds/phonemizer" / target
        receipt = json.loads((phonemizer / "build-identity.json").read_text())
        manifest["phonemizer"][target] = receipt
        identity = {
            "profile": "personal-victoria",
            "target": target,
            "rust_archive_sha256": assembly.sha(archive),
            "runtime_sha256": assembly.sha(runtime),
            "phonemizer": receipt,
            "builder_sha256": assembly.sha(Path(__file__)),
        }

        def produce(staging, archive=archive, runtime=runtime):
            library = staging / "libRehaCoreFFI.a"
            run("xcrun", "libtool", "-static", "-o", library, archive, runtime)
            if run("xcrun", "lipo", "-archs", library, capture=True) != "arm64":
                raise ValueError("Unexpected private native architecture")
            # Cargo statically includes the pinned eSpeak/ucd libraries through
            # reha-core's checked build.rs. Verify their required entry points.
            symbols = subprocess.run(
                ["xcrun", "nm", "-g", str(library)], text=True, capture_output=True, check=False
            )
            for symbol in ["_OrtGetApiBase", "_espeak_Initialize", "_espeak_TextToPhonemes"]:
                if not any(line.endswith(" T " + symbol) for line in symbols.stdout.splitlines()):
                    raise ValueError("Missing private native symbol: " + symbol)
            (staging / "nm-diagnostics.txt").write_text(symbols.stderr)

        library = assembly.cached_build(BASE / "libraries", identity, ["libRehaCoreFFI.a"], produce)
        manifest["libraries"][variant] = {
            "identity": identity,
            "path": str(library.relative_to(ROOT)),
        }
    framework_identity = {
        "libraries": manifest["libraries"],
        "headers": assembly.tree(ROOT / "packages/apple/RehaCore/Headers"),
    }

    def framework(staging):
        command = ["xcodebuild", "-create-xcframework"]
        for value in manifest["libraries"].values():
            command += [
                "-library",
                ROOT / value["path"] / "libRehaCoreFFI.a",
                "-headers",
                ROOT / "packages/apple/RehaCore/Headers",
            ]
        run(*command, "-output", staging / "RehaCoreFFI.xcframework")

    product = assembly.cached_build(
        BASE / "frameworks", framework_identity, ["RehaCoreFFI.xcframework/Info.plist"], framework
    )
    package = BASE / "RehaCore"
    (package / "Sources/RehaCore").mkdir(parents=True, exist_ok=True)
    for relative in ["Package.swift", "Sources/RehaCore/RehaCore.swift"]:
        shutil.copyfile(ROOT / "packages/apple/RehaCore" / relative, package / relative)
    assembly.publish_link(package / "RehaCoreFFI.xcframework", product / "RehaCoreFFI.xcframework")
    folder = BASE / "private-speech"
    folder.mkdir(exist_ok=True)
    for name in json.loads((ROOT / private_speech.NOTICES / "manifest.json").read_text()):
        shutil.copyfile(ROOT / private_speech.NOTICES / name, folder / name)
    (folder / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    return manifest


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("mode", choices=["prepare", "simulator", "archive"])
    parser.add_argument(
        "--output", type=Path, help="New build directory outside synchronized storage"
    )
    args = parser.parse_args()
    with product_generation.leased(ROOT):
        prepare()
        if args.mode == "prepare":
            return
        if args.output is None or not args.output.is_absolute():
            parser.error("Pass a new absolute --output build directory")
        args.output.mkdir(mode=0o700, parents=True, exist_ok=False)
        try:
            run(
                "xcodegen",
                "generate",
                "--spec",
                "apps/ios/private-victoria.yml",
                "--project",
                "apps/ios",
            )
            command = [
                "xcodebuild",
                "-project",
                "apps/ios/Termine.xcodeproj",
                "-scheme",
                "Termine",
                "-derivedDataPath",
                args.output / "DerivedData",
                "ARCHS=arm64",
            ]
            if args.mode == "simulator":
                command += [
                    "-configuration",
                    "Debug",
                    "-sdk",
                    "iphonesimulator",
                    "-destination",
                    "generic/platform=iOS Simulator",
                    "CODE_SIGNING_ALLOWED=NO",
                    "build",
                ]
            else:
                command += [
                    "-configuration",
                    "Release",
                    "-destination",
                    "generic/platform=iOS",
                    "-archivePath",
                    args.output / "Laßnitzhöhe.xcarchive",
                    "-allowProvisioningUpdates",
                    "archive",
                ]
            run(*command)
        finally:
            run("xcodegen", "generate", "--spec", "apps/ios/project.yml", "--project", "apps/ios")


if __name__ == "__main__":
    main()
