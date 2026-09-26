#!/bin/sh
set -eu
cd "$(dirname "$0")/../.."
probe=$(mktemp -d)
trap 'rm -rf "$probe"' EXIT
swiftc -swift-version 6 -strict-concurrency=complete \
  apps/ios/Shared/Intake/IntakeGate.swift \
  apps/ios/Shared/Intake/IntakeReceipt.swift \
  apps/ios/Shared/Intake/IntakeProviderRequest.swift \
  apps/ios/Tests/IntakeProviderProbe.swift -o "$probe/intake-provider"
"$probe/intake-provider"
