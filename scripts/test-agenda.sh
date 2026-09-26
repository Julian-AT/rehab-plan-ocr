#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
check_dir=$(mktemp -d)
trap 'rm -rf "$check_dir"' EXIT
swiftc apple/Packages/AppleServices/Sources/AppleServices/AgendaShared/AgendaModels.swift \
  apple/Packages/AppleServices/Sources/AppleServices/AgendaShared/ReminderTransfer.swift \
  tests/ios/agenda-policy-check.swift -o "$check_dir/agenda-check"
"$check_dir/agenda-check"
