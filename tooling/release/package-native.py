#!/usr/bin/env python3
"""Verify the existing signed archive, then package it for private installation."""

import datetime
import hashlib
import json
import pathlib
import plistlib
import subprocess
import tempfile

from bundle import require, verify

ROOT = pathlib.Path(__file__).resolve().parents[2]
ARCHIVE_ROOT = ROOT / "apps/ios/build/Laßnitzhöhe.xcarchive"
ARCHIVE_INFO = plistlib.loads((ARCHIVE_ROOT / "Info.plist").read_bytes())
ARCHIVE = ARCHIVE_ROOT / "Products" / ARCHIVE_INFO["ApplicationProperties"]["ApplicationPath"]
BUNDLE = "at.rehakalender.personal"
TEAM = "ZP2PFF43D2"
GROUP = "group.at.rehakalender.personal"
INTAKE_GROUP = GROUP + ".intake"


def run(*args):
    result = subprocess.run(args, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    if result.returncode:
        raise RuntimeError(f"{args[0]} failed: {result.stderr.decode(errors='replace').strip()}")
    return result.stdout


with tempfile.TemporaryDirectory(prefix="termine-signed-") as temp:
    payload = pathlib.Path(temp) / "Payload"
    payload.mkdir()
    app = payload / ARCHIVE.name
    run("ditto", str(ARCHIVE), str(app))
    # This workspace's file provider adds Finder metadata after Xcode signs.
    # Clear extended attributes in a temporary copy without changing signed files.
    run("xattr", "-cr", str(app))
    run("codesign", "--verify", "--deep", "--strict", str(app))
    contents = verify(app, "device")
    profiles = []
    common_devices = None
    for component in [app, *sorted(app.glob("PlugIns/*.appex"))]:
        info = plistlib.loads((component / "Info.plist").read_bytes())
        profile = plistlib.loads(
            run("security", "cms", "-D", "-i", str(component / "embedded.mobileprovision"))
        )
        entitlements = plistlib.loads(run("codesign", "-d", "--entitlements", ":-", str(component)))
        identifier = info["CFBundleIdentifier"]
        require(
            entitlements["application-identifier"] == TEAM + "." + identifier,
            "Signed application identifier differs",
        )
        require(entitlements["com.apple.developer.team-identifier"] == TEAM, "Signed team differs")
        expected_groups = (
            [GROUP, INTAKE_GROUP]
            if identifier == BUNDLE
            else [INTAKE_GROUP]
            if identifier.endswith(".share")
            else [GROUP]
        )
        require(
            sorted(entitlements["com.apple.security.application-groups"])
            == sorted(expected_groups),
            "Signed App Groups differ",
        )
        allowed = profile["Entitlements"]
        require(profile["TeamIdentifier"] == [TEAM], "Profile team differs")
        require(
            allowed["application-identifier"] == entitlements["application-identifier"],
            "Profile application identifier differs",
        )
        require(
            allowed["com.apple.developer.team-identifier"] == TEAM,
            "Profile entitlement team differs",
        )
        require(
            all(
                group in allowed["com.apple.security.application-groups"]
                for group in expected_groups
            ),
            "Profile does not authorize the required App Groups",
        )
        devices = set(profile.get("ProvisionedDevices", []))
        common_devices = devices if common_devices is None else common_devices & devices
        require(
            profile["ExpirationDate"]
            > datetime.datetime.now(datetime.timezone.utc).replace(tzinfo=None),
            "Provisioning profile has expired",
        )
        profiles.append(
            {"bundle": identifier, "expires_utc": profile["ExpirationDate"].isoformat()}
        )
    require(len(profiles) == 4, "Missing signed app or extension")
    require(common_devices, "App and extensions must authorize at least one common device")
    output = ROOT / "apps/ios/build/Laßnitzhöhe.ipa"
    run("ditto", "-c", "-k", "--sequesterRsrc", "--keepParent", str(payload), str(output))
    report = {
        **contents,
        "profiles": profiles,
        "sha256": hashlib.sha256(output.read_bytes()).hexdigest(),
        "bytes": output.stat().st_size,
        "model_files_verified": contents["models"]["small"]["pinned_files"],
        "speech_model_files_verified": contents["speech"]["bundled_model_files"],
        "signatures_verified": True,
        "commonly_authorized_devices": len(common_devices),
        "physical_acceptance": "pending",
    }
    (ROOT / "apps/ios/build/package-verification.json").write_text(
        json.dumps(report, indent=2) + "\n"
    )
    print(json.dumps(report, indent=2))
