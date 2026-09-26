#!/bin/sh
set -eu
cd "$(dirname "$0")/../.."
probe=$(mktemp -d)
trap 'rm -rf "$probe"' EXIT
swiftc -swift-version 6 -strict-concurrency=complete -parse-as-library \
  packages/apple/AppleServices/Sources/AppleServices/NativeServiceCall.swift \
  packages/apple/AppleServices/Sources/AppleServices/ServiceRequest.swift \
  packages/apple/AppleServices/Sources/AppleServices/NotificationDeadline.swift \
  apps/ios/Tests/NotificationDeadlineProbe.swift -o "$probe/deadline"
"$probe/deadline"
