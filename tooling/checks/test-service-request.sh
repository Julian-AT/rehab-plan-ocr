#!/bin/sh
set -eu
cd "$(dirname "$0")/../.."
probe=$(mktemp -d)
trap 'rm -rf "$probe"' EXIT
swiftc -swift-version 6 -strict-concurrency=complete \
  packages/apple/AppleServices/Sources/AppleServices/ServiceRequest.swift \
  apps/ios/Tests/ServiceRequestProbe.swift -o "$probe/service-request"
"$probe/service-request"
