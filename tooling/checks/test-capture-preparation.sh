#!/bin/sh
set -eu
cd "$(dirname "$0")/../.."
probe=$(mktemp -d)
trap 'rm -rf "$probe"' EXIT
swiftc -swift-version 6 -strict-concurrency=complete \
  apps/ios/Features/Capture/CapturePreparation.swift \
  apps/ios/Tests/CapturePreparationProbe.swift -o "$probe/capture"
"$probe/capture"
