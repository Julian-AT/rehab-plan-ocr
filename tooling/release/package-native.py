#!/usr/bin/env python3
"""Verify the existing signed archive, then package it for private installation."""

import datetime
import hashlib
import json
import pathlib
import plistlib
import subprocess
import tempfile
import tomllib

ROOT = pathlib.Path(__file__).resolve().parents[2]
ARCHIVE_ROOT = ROOT / "apps/ios/build/Laßnitzhöhe.xcarchive"
ARCHIVE_INFO = plistlib.loads((ARCHIVE_ROOT / "Info.plist").read_bytes())
ARCHIVE = ARCHIVE_ROOT / "Products" / ARCHIVE_INFO["ApplicationProperties"]["ApplicationPath"]
BUNDLE = "at.rehakalender.personal"
TEAM = "ZP2PFF43D2"
GROUP = "group.at.rehakalender.personal"
INTAKE_GROUP = GROUP + ".intake"
VERSION = tomllib.loads((ROOT / "Cargo.toml").read_text())["workspace"]["package"]["version"]


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
    profiles = []
    common_devices = None
    build_version = None
    for component in [app, *sorted(app.glob("PlugIns/*.appex"))]:
        info = plistlib.loads((component / "Info.plist").read_bytes())
        profile = plistlib.loads(
            run("security", "cms", "-D", "-i", str(component / "embedded.mobileprovision"))
        )
        entitlements = plistlib.loads(run("codesign", "-d", "--entitlements", ":-", str(component)))
        identifier = info["CFBundleIdentifier"]
        assert info["CFBundleDisplayName"] == "Laßnitzhöhe"
        if identifier == BUNDLE:
            assert info["CFBundleExecutable"] == "Termine", (
                "Keep the internal executable name stable for signing"
            )
        assert info["CFBundleShortVersionString"] == VERSION, (
            "Generated app version must match the workspace"
        )
        if build_version is None:
            build_version = info["CFBundleVersion"]
        assert info["CFBundleVersion"] == build_version, (
            "App and extension build numbers must match"
        )
        assert info["UIDeviceFamily"] == [1], "The first release targets iPhone"
        assert identifier in [
            BUNDLE,
            BUNDLE + ".widgets",
            BUNDLE + ".notification-content",
            BUNDLE + ".share",
        ]
        assert entitlements["application-identifier"] == TEAM + "." + identifier
        assert entitlements["com.apple.developer.team-identifier"] == TEAM
        expected_groups = (
            [GROUP, INTAKE_GROUP]
            if identifier == BUNDLE
            else [INTAKE_GROUP]
            if identifier.endswith(".share")
            else [GROUP]
        )
        assert sorted(entitlements["com.apple.security.application-groups"]) == sorted(
            expected_groups
        )
        allowed = profile["Entitlements"]
        assert profile["TeamIdentifier"] == [TEAM]
        assert allowed["application-identifier"] == entitlements["application-identifier"]
        assert allowed["com.apple.developer.team-identifier"] == TEAM
        assert all(
            group in allowed["com.apple.security.application-groups"] for group in expected_groups
        )
        devices = set(profile.get("ProvisionedDevices", []))
        common_devices = devices if common_devices is None else common_devices & devices
        assert profile["ExpirationDate"] > datetime.datetime.now(datetime.timezone.utc).replace(
            tzinfo=None
        )
        profiles.append(
            {"bundle": identifier, "expires_utc": profile["ExpirationDate"].isoformat()}
        )
    assert len(profiles) == 4
    assert common_devices, "App and extensions must authorize at least one common device"
    manifest = json.loads((app / "small/manifest.json").read_text())
    assert manifest == json.loads((ROOT / "models/small.lock.json").read_text())
    for entry in manifest["files"]:
        assert (
            hashlib.sha256((app / "small" / entry["path"]).read_bytes()).hexdigest()
            == entry["sha256"]
        )
    speech_manifest = json.loads((ROOT / "models/kokoro.lock.json").read_text())
    for entry in speech_manifest["files"]:
        assert (
            hashlib.sha256((app / "kokoro-german" / entry["path"]).read_bytes()).hexdigest()
            == entry["sha256"]
        )
    for name, digest in json.loads((ROOT / "licenses/manifest.json").read_text()).items():
        assert hashlib.sha256((app / "licenses" / name).read_bytes()).hexdigest() == digest
    output = ROOT / "apps/ios/build/Laßnitzhöhe.ipa"
    run("ditto", "-c", "-k", "--sequesterRsrc", "--keepParent", str(payload), str(output))
    report = {
        "profiles": profiles,
        "sha256": hashlib.sha256(output.read_bytes()).hexdigest(),
        "bytes": output.stat().st_size,
        "version": VERSION,
        "build": build_version,
        "model_files_verified": len(manifest["files"]),
        "speech_model_files_verified": len(speech_manifest["files"]),
        "signatures_verified": True,
        "commonly_authorized_devices": len(common_devices),
        "physical_acceptance": "pending",
    }
    (ROOT / "apps/ios/build/package-verification.json").write_text(
        json.dumps(report, indent=2) + "\n"
    )
    print(json.dumps(report, indent=2))
