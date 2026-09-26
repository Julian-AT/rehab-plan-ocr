"""Read-only release-content verification shared by unsigned CI and signed packaging."""

import argparse
import importlib.util
import json
import plistlib
import tomllib
from pathlib import Path

from privacy import BUNDLE
from privacy import verify_bundle as verify_privacy
from private_speech import verify as verify_private_speech
from runtime_inventory import verify as verify_inventory
from runtime_policy import ESPEAK_SYMBOL, MODELS, check_binary, check_resources, embedded_code

ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location(
    "native_assets", ROOT / "tooling/build/verify-native-assets.py"
)
ASSETS = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(ASSETS)
COMPONENTS = {
    BUNDLE: (None, "Termine", None),
    BUNDLE + ".widgets": ("RehaWidgets.appex", "RehaWidgets", "com.apple.widgetkit-extension"),
    BUNDLE + ".share": ("RehaShare.appex", "RehaShare", "com.apple.share-services"),
    BUNDLE + ".notification-content": (
        "RehaNotificationContent.appex",
        "RehaNotificationContent",
        "com.apple.usernotifications.content-extension",
    ),
}
PLATFORMS = {"simulator": "iPhoneSimulator", "device": "iPhoneOS"}


def require(condition, message):
    if not condition:
        raise ValueError(message)


def verify(app, target, root=ROOT, *, private_victoria=False):
    require(target in PLATFORMS, "Unknown native target")
    require(app.is_dir() and not app.is_symlink(), "Expected a self-contained app directory")
    # A packaged iOS app must carry all of its contents, including model data.
    require(not any(p.is_symlink() for p in app.rglob("*")), "App contains a symbolic link")
    private_marker = plistlib.loads((app / "Info.plist").read_bytes()).get(
        "REHAPrivateVictoria", False
    )
    require(
        private_marker is private_victoria, "Private Victoria profile requires explicit packaging"
    )
    check_resources(app, private_victoria=private_victoria)
    plugins = app / "PlugIns"
    require(
        {p.name for p in plugins.iterdir()} == {v[0] for v in COMPONENTS.values() if v[0]},
        "Missing or unexpected app extension",
    )
    version = tomllib.loads((root / "Cargo.toml").read_text())["workspace"]["package"]["version"]
    build = None
    components = {}
    checked_executables = set()
    for identifier, (name, executable, extension) in COMPONENTS.items():
        component = plugins / name if name else app
        info = plistlib.loads((component / "Info.plist").read_bytes())
        expected = {
            "CFBundleIdentifier": identifier,
            "CFBundleDisplayName": "Laßnitzhöhe",
            "CFBundleExecutable": executable,
            "CFBundleShortVersionString": version,
            "CFBundlePackageType": "XPC!" if extension else "APPL",
            "MinimumOSVersion": "26.0",
            "UIDeviceFamily": [1],
            "CFBundleSupportedPlatforms": [PLATFORMS[target]],
        }
        for key, value in expected.items():
            require(info.get(key) == value, f"Unexpected {key} in {identifier}")
        require(
            info.get("NSExtension", {}).get("NSExtensionPointIdentifier") == extension,
            f"Unexpected extension point in {identifier}",
        )
        if build is None:
            build = info.get("CFBundleVersion")
            require(isinstance(build, str) and bool(build), "Missing app build version")
        require(info.get("CFBundleVersion") == build, "App and extension build versions differ")
        require(not info.get("REHAExperimentalAssistant"), "Experimental assistant trial bundle")
        binary = component / executable
        require(binary.is_file() and binary.stat().st_size > 0, f"Missing executable: {identifier}")
        if not (private_victoria and identifier == BUNDLE):
            check_binary(binary)
        checked_executables.add(binary)
        components[identifier] = {"executable_sha256": ASSETS.sha(binary)}
    embedded = {}
    for binary in embedded_code(app):
        if binary not in checked_executables:
            if not (private_victoria and binary == app / "Termine.debug.dylib"):
                check_binary(binary)
            embedded[str(binary.relative_to(app))] = {"sha256": ASSETS.sha(binary)}
    if private_victoria:
        main_code = [app / "Termine", app / "Termine.debug.dylib"]
        require(
            any(p.is_file() and ESPEAK_SYMBOL.search(p.read_bytes()) for p in main_code),
            "Private voice bundle is missing its native renderer",
        )
    models = {}
    for model in MODELS:
        lock = json.loads((root / "ml/registry/runtime" / f"{model}.lock.json").read_text())
        directory = lock.get("bundle_directory", model)
        require(
            directory not in {"", ".", ".."} and Path(directory).name == directory,
            "Model bundle directory must be local",
        )
        models[model] = ASSETS.model_bundle(app / directory, lock, strict=True)
    speech = (
        verify_private_speech(app, root, ASSETS.model_bundle)
        if private_victoria
        else {
            "provider": "Apple operating system",
            "bundled_model_files": 0,
            "experimental_speech_excluded": True,
            "device_voice_acceptance": "pending",
        }
    )
    inventory = verify_inventory(root, bundle=app)
    if private_victoria:
        inventory["scope"] = (
            "base OCR/Rust/Apple dependencies; private speech supplement verified separately"
        )
    return {
        "schema_version": 1,
        "target": target,
        "version": version,
        "build": build,
        "components": components,
        "embedded_code": embedded,
        "models": models,
        "speech": speech,
        "privacy_manifests_verified": verify_privacy(app, root=root),
        "runtime_inventory": inventory,
        "signatures_verified": False,
        "physical_acceptance": "pending",
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("app", type=Path)
    parser.add_argument("--target", choices=PLATFORMS, required=True)
    parser.add_argument("--private-victoria", action="store_true")
    args = parser.parse_args()
    print(
        json.dumps(verify(args.app, args.target, private_victoria=args.private_victoria), indent=2)
    )


if __name__ == "__main__":
    main()
