"""Install a freshly built simulator app for isolated synthetic evaluations."""

import json
import tempfile
from pathlib import Path

from tooling.utils.apfs_clone import clone

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


def install(app, identifier, run, *, expected_files=None):
    disposable(identifier, run)
    temporary_root = ROOT / ".local/tmp"
    temporary_root.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="reha-evaluation-", dir=temporary_root) as temporary:
        staged = Path(temporary) / app.name
        signed_copy(app, staged, run, expected_files=expected_files)
        run(["xcrun", "simctl", "install", identifier, str(staged)], timeout=120)
    return Path(run(["xcrun", "simctl", "get_app_container", identifier, BUNDLE, "data"]))


def signed_copy(app, destination, run, *, expected_files=None):
    """Sign a new caller-owned copy; its lifetime is owned by the caller."""
    app, destination = Path(app), Path(destination)
    if (
        destination.exists()
        or destination.is_symlink()
        or destination.resolve().is_relative_to(app.resolve())
    ):
        raise ValueError("Signed staging destination must be new and outside the source app")
    clone(app, destination, expected_files=expected_files)
    run(["xattr", "-cr", str(destination)])
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
                str(destination / product),
            ]
        )
