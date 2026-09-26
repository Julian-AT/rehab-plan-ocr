#!/bin/sh
set -eu
cd "$(dirname "$0")/../.."
probe=$(mktemp -d)
trap 'rm -rf "$probe"' EXIT
swiftc -swift-version 6 -strict-concurrency=complete \
  packages/apple/AppleServices/Sources/AppleServices/NativeServiceCall.swift \
  packages/apple/AppleServices/Sources/AppleServices/calendar-contracts.swift \
  packages/apple/AppleServices/Sources/AppleServices/CalendarReadContracts.swift \
  apps/ios/Tests/CalendarReadContractsProbe.swift -o "$probe/calendar-reads"
"$probe/calendar-reads"
