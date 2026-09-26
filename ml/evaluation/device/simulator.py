"""Install a freshly built simulator app for isolated synthetic evaluations."""

import json
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
BUNDLE = "at.rehakalender.personal"


def disposable(identifier, run):
    devices = json.loads(run(["xcrun", "simctl", "list", "devices", "booted", "--json"]))
    selected = [
        dict(d, runtime_identifier=runtime)
        for runtime, group in devices["devices"].items()
        for d in group
        if d["udid"] == identifier
    ]
    if len(selected) != 1 or not selected[0]["name"].startswith("Termine-Native-Test-"):
        raise ValueError("Use a booted disposable Termine-Native-Test simulator; run serially")
    return selected[0]


def install(app, identifier, run):
    disposable(identifier, run)
    with tempfile.TemporaryDirectory(prefix="reha-evaluation-") as temporary:
        staged = Path(temporary) / app.name
        run(["cp", "-cRp", str(app), str(staged)])
        run(["xattr", "-cr", str(staged)])
        for product, entitlements in [
            ("PlugIns/RehaWidgets.appex", "Extensions/Widgets/Widgets.entitlements"),
            (
                "PlugIns/RehaNotificationContent.appex",
                "Extensions/NotificationContent/Notification.entitlements",
            ),
            ("PlugIns/RehaShare.appex", "Extensions/Share/Share.entitlements"),
            ("", "App/Termine.entitlements"),
        ]:
            run(
                [
                    "codesign",
                    "--force",
                    "--sign",
                    "-",
                    "--entitlements",
                    str(ROOT / "apps/ios" / entitlements),
                    str(staged / product),
                ]
            )
        run(["xcrun", "simctl", "install", identifier, str(staged)], timeout=120)
    return Path(run(["xcrun", "simctl", "get_app_container", identifier, BUNDLE, "data"]))
