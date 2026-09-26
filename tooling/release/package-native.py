#!/usr/bin/env python3
"""Verify the existing signed archive, then package it for private installation."""

import argparse
import datetime
import hashlib
import json
import pathlib
import plistlib
import subprocess
import tempfile

import release_artifacts
from bundle import require, verify
from signing import verify_signer

BUNDLE = "at.rehakalender.personal"
TEAM = "ZP2PFF43D2"
GROUP = "group.at.rehakalender.personal"
INTAKE_GROUP = GROUP + ".intake"


def run(*args):
    result = subprocess.run(args, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    if result.returncode:
        raise RuntimeError(f"{args[0]} failed: {result.stderr.decode(errors='replace').strip()}")
    return result.stdout


def package(run_value, existing_archive=None, *, private_victoria=False):
    if existing_archive is not None:
        release_artifacts.reserve(run_value, archive=existing_archive)
    release_root, archive_root, provenance = release_artifacts.load(run_value)
    release_artifacts.write_new(
        release_root / ".packaging.lock", b"Reserved for one packaging attempt.\n"
    )
    archived_app = release_artifacts.application(archive_root)
    symbol_report = release_artifacts.symbols(archive_root, archived_app)
    with tempfile.TemporaryDirectory(prefix="termine-signed-") as temp:
        payload = pathlib.Path(temp) / "Payload"
        payload.mkdir()
        app = payload / archived_app.name
        run("ditto", str(archived_app), str(app))
        archived_relative = archived_app.relative_to(archive_root)
        for symbol in symbol_report:
            binary = pathlib.Path(symbol["binary"]).relative_to(archived_relative)
            require(
                release_artifacts.sha(app / binary) == symbol["binary_sha256"],
                "Packaged executable differs from its verified archive/dSYM identity",
            )
        # This workspace's file provider adds Finder metadata after Xcode signs.
        # Clear extended attributes in a temporary copy without changing signed files.
        run("xattr", "-cr", str(app))
        run("codesign", "--verify", "--deep", "--strict", str(app))
        contents = (
            verify(app, "device", private_victoria=True)
            if private_victoria
            else verify(app, "device")
        )
        profiles = []
        common_devices = None
        for component in [app, *sorted(app.glob("PlugIns/*.appex"))]:
            info = plistlib.loads((component / "Info.plist").read_bytes())
            profile = plistlib.loads(
                run("security", "cms", "-D", "-i", str(component / "embedded.mobileprovision"))
            )
            entitlements = plistlib.loads(
                run("codesign", "-d", "--entitlements", ":-", str(component))
            )
            identifier = info["CFBundleIdentifier"]
            require(
                entitlements["application-identifier"] == TEAM + "." + identifier,
                "Signed application identifier differs",
            )
            require(
                entitlements["com.apple.developer.team-identifier"] == TEAM, "Signed team differs"
            )
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
                {
                    "bundle": identifier,
                    "expires_utc": profile["ExpirationDate"].isoformat(),
                    "signer": verify_signer(component, profile, run),
                }
            )
        require(len(profiles) == 4, "Missing signed app or extension")
        require(common_devices, "App and extensions must authorize at least one common device")
        output = release_root / "Laßnitzhöhe.ipa"
        staged = pathlib.Path(temp) / output.name
        run("ditto", "-c", "-k", "--sequesterRsrc", "--keepParent", str(payload), str(staged))
        release_artifacts.publish(staged, output)
        report = {
            **contents,
            "release_provenance": provenance,
            "symbols": symbol_report,
            "profiles": profiles,
            "sha256": hashlib.sha256(output.read_bytes()).hexdigest(),
            "bytes": output.stat().st_size,
            "model_files_verified": contents["models"]["small"]["pinned_files"],
            "speech_model_files_verified": contents["speech"]["bundled_model_files"],
            "signatures_verified": True,
            "commonly_authorized_devices": len(common_devices),
            "physical_acceptance": "pending",
        }
        release_artifacts.write_new(
            release_root / "package-verification.json",
            (json.dumps(report, indent=2) + "\n").encode(),
        )
        print(json.dumps(report, indent=2))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--run", required=True, help="Reserved archive run below .local/releases")
    parser.add_argument(
        "--private-victoria", action="store_true", help="Explicit personal-device Victoria profile"
    )
    parser.add_argument(
        "--archive", type=pathlib.Path, help="Explicit historical archive; --run must be new"
    )
    args = parser.parse_args()
    package(args.run, args.archive, private_victoria=args.private_victoria)


if __name__ == "__main__":
    main()
