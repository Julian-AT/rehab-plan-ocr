#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
probe=$(mktemp -d)
trap 'rm -rf "$probe"' EXIT
swiftc -swift-version 6 apps/ios/Shared/Intake/IntakeGate.swift apps/ios/Features/Capture/IntakeAdmission.swift apps/ios/Tests/IntakeErasureProbe.swift -o "$probe/erasure"
"$probe/erasure"
