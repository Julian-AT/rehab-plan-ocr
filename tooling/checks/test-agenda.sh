#!/bin/sh
set -eu
cd "$(dirname "$0")/../.."
check_dir=$(mktemp -d)
trap 'rm -rf "$check_dir"' EXIT
swiftc packages/apple/AppleServices/Sources/AppleServices/AgendaShared/AgendaModels.swift \
  packages/apple/AppleServices/Sources/AppleServices/AgendaShared/ReminderTransfer.swift \
  apps/ios/IntegrationTests/agenda-policy-check.swift -o "$check_dir/agenda-check"
"$check_dir/agenda-check"
