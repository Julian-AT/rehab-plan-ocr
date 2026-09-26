#!/bin/sh
set -eu
cd "$(dirname "$0")/../.."
probe=$(mktemp -d)
trap 'rm -rf "$probe"' EXIT
swiftc -j 1 -swift-version 6 -strict-concurrency=complete \
  packages/apple/AppleServices/Sources/AppleServices/NativeServiceCall.swift \
  packages/apple/AppleServices/Sources/AppleServices/calendar-contracts.swift \
  packages/apple/AppleServices/Sources/AppleServices/CalendarReadContracts.swift \
  packages/apple/AppleServices/Sources/AppleServices/CalendarMutationContracts.swift \
  apps/ios/Tests/CalendarMutationContractsProbe.swift -o "$probe/calendar-mutations"
"$probe/calendar-mutations"
