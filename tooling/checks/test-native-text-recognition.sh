#!/bin/sh
set -eu
cd "$(dirname "$0")/../.."
probe=$(mktemp -d)
trap 'rm -rf "$probe"' EXIT
swiftc -swift-version 6 -strict-concurrency=complete -warnings-as-errors \
  packages/apple/AppleServices/Sources/AppleServices/NativeServiceCall.swift \
  packages/apple/AppleServices/Sources/AppleServices/NativePhoto.swift \
  packages/apple/AppleServices/Sources/AppleServices/TextRecognitionContracts.swift \
  packages/apple/AppleServices/Sources/AppleServices/NativeTextRecognition.swift \
  apps/ios/Tests/NativeTextRecognitionProbe.swift -o "$probe/native-recognition"
"$probe/native-recognition"
