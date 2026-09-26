#!/bin/sh
set -eu
cd "$(dirname "$0")/../.."
probe=$(mktemp -d)
trap 'rm -rf "$probe"' EXIT
swiftc -swift-version 6 -strict-concurrency=complete \
  packages/apple/AppleServices/Sources/AppleServices/NativeServiceCall.swift \
  packages/apple/AppleServices/Sources/AppleServices/NativePhoto.swift \
  apps/ios/Tests/NativePhotoProbe.swift -o "$probe/native-photo"
"$probe/native-photo"
