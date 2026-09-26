#!/bin/sh
set -eu
cd "$(dirname "$0")/../.."
probe=$(mktemp -d)
trap 'rm -rf "$probe"' EXIT
swiftc -swift-version 6 -strict-concurrency=complete \
  apps/ios/Features/Archive/PlansModel.swift apps/ios/Tests/PlansModelProbe.swift \
  -o "$probe/archive"
"$probe/archive"
