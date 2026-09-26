#!/bin/sh
set -eu
cd "$(dirname "$0")/../.."
check_dir=$(mktemp -d)
trap 'rm -rf "$check_dir"' EXIT
swiftc -swift-version 6 apps/ios/Tests/Support/PreviewFixtureTiming.swift \
  apps/ios/Tests/PreviewFixtureTimingProbe.swift -o "$check_dir/probe"
"$check_dir/probe"
