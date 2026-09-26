"""Verify per-component privacy manifests against their reviewed source files."""

import argparse
import hashlib
import json
import plistlib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
BUNDLE = "at.rehakalender.personal"
SOURCES = {
    BUNDLE: "App",
    BUNDLE + ".share": "Extensions/Share",
    BUNDLE + ".widgets": "Extensions/Widgets",
    BUNDLE + ".notification-content": "Extensions/NotificationContent",
}


def verify_bundle(app):
    checked = {}
    for component in [app, *sorted(app.glob("PlugIns/*.appex"))]:
        identifier = plistlib.loads((component / "Info.plist").read_bytes())["CFBundleIdentifier"]
        if identifier not in SOURCES or identifier in checked:
            raise ValueError("Unknown or duplicated privacy manifest component")
        source = ROOT / "apps/ios" / SOURCES[identifier] / "PrivacyInfo.xcprivacy"
        path = component / "PrivacyInfo.xcprivacy"
        data = path.read_bytes()
        expected = plistlib.loads(source.read_bytes())
        if plistlib.loads(data) != expected:
            raise ValueError(f"Bundled privacy declaration differs from source: {identifier}")
        if expected["NSPrivacyTracking"] or expected["NSPrivacyTrackingDomains"]:
            raise ValueError("Unexpected tracking declaration in this offline application")
        checked[identifier] = {"sha256": hashlib.sha256(data).hexdigest(), "bytes": len(data)}
    if set(checked) != set(SOURCES):
        raise ValueError("Missing app/extension privacy manifest")
    return checked


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("app", type=Path)
    args = parser.parse_args()
    print(json.dumps(verify_bundle(args.app), indent=2))
