"""Read-only release-content verification shared by unsigned CI and signed packaging."""

import argparse
import importlib.util
import json
import plistlib
import tomllib
from pathlib import Path

from privacy import BUNDLE
from privacy import verify_bundle as verify_privacy
from runtime_inventory import verify as verify_inventory

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


def verify(app, target, root=ROOT):
    require(target in PLATFORMS, "Unknown native target")
    require(app.is_dir() and not app.is_symlink(), "Expected a self-contained app directory")
    # A packaged iOS app must carry all of its contents, including model data.
    require(not any(p.is_symlink() for p in app.rglob("*")), "App contains a symbolic link")
    plugins = app / "PlugIns"
    require(
        {p.name for p in plugins.iterdir()} == {v[0] for v in COMPONENTS.values() if v[0]},
        "Missing or unexpected app extension",
    )
    version = tomllib.loads((root / "Cargo.toml").read_text())["workspace"]["package"]["version"]
    build = None
    components = {}
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
        components[identifier] = {"executable_sha256": ASSETS.sha(binary)}
    models = {}
    for model in ["small", "kokoro"]:
        lock = json.loads((root / "ml/registry/runtime" / f"{model}.lock.json").read_text())
        directory = lock.get("bundle_directory", model)
        require(
            directory not in {"", ".", ".."} and Path(directory).name == directory,
            "Model bundle directory must be local",
        )
        models[model] = ASSETS.model_bundle(app / directory, lock, strict=True)
    return {
        "schema_version": 1,
        "target": target,
        "version": version,
        "build": build,
        "components": components,
        "models": models,
        "privacy_manifests_verified": verify_privacy(app, root=root),
        "runtime_inventory": verify_inventory(root, bundle=app),
        "signatures_verified": False,
        "physical_acceptance": "pending",
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("app", type=Path)
    parser.add_argument("--target", choices=PLATFORMS, required=True)
    args = parser.parse_args()
    print(json.dumps(verify(args.app, args.target), indent=2))


if __name__ == "__main__":
    main()
