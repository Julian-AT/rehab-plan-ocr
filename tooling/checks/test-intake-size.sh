#!/bin/sh
set -eu
cd "$(dirname "$0")/../.."
probe=$(mktemp -d)
trap 'rm -rf "$probe"' EXIT
swiftc -swift-version 6 -strict-concurrency=complete -module-cache-path "$probe/modules" \
  apps/ios/Shared/Intake/IntakeGate.swift apps/ios/Shared/Intake/IntakeReceipt.swift \
  apps/ios/Tests/IntakeSizeProbe.swift -o "$probe/intake-size"
"$probe/intake-size"
