#!/bin/sh
set -eu
cd "$(dirname "$0")/../.."
probe=$(mktemp -d)
trap 'rm -rf "$probe"' EXIT
swiftc -swift-version 6 -strict-concurrency=complete \
  apps/ios/Features/Archive/ArtifactThumbnail.swift apps/ios/Tests/ArtifactThumbnailProbe.swift \
  -o "$probe/archive-thumbnail"
"$probe/archive-thumbnail"
