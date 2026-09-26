#!/bin/sh
set -eu
cd "$(dirname "$0")/../.."
probe=$(mktemp -d)
trap 'rm -rf "$probe"' EXIT
swiftc -swift-version 6 -strict-concurrency=complete \
  apps/ios/Features/Capture/IntakeAdmission.swift \
  apps/ios/Features/Capture/ScanAttemptRegistry.swift \
  apps/ios/Tests/ScanAttemptRegistryProbe.swift -o "$probe/scan-attempts"
"$probe/scan-attempts"
