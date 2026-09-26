#!/bin/sh
set -eu
cd "$(dirname "$0")/../.."
probe=$(mktemp -d)
trap 'rm -rf "$probe"' EXIT
swiftc -j 1 -swift-version 6 -strict-concurrency=complete -warnings-as-errors \
  packages/apple/AppleServices/Sources/AppleServices/NativeServiceCall.swift \
  packages/apple/AppleServices/Sources/AppleServices/calendar-contracts.swift \
  packages/apple/AppleServices/Sources/AppleServices/CalendarImportContracts.swift \
  packages/apple/AppleServices/Sources/AppleServices/AgendaShared/AgendaModels.swift \
  apps/ios/Tests/CalendarImportContractsProbe.swift -o "$probe/calendar-imports"
"$probe/calendar-imports"
