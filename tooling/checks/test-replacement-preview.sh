#!/bin/sh
set -eu
cd "$(dirname "$0")/../.."
probe=$(mktemp -d)
trap 'rm -rf "$probe"' EXIT
swiftc -swift-version 6 -strict-concurrency=complete \
  apps/ios/Features/PlanReview/ReplacementPreviewState.swift \
  apps/ios/Features/PlanReview/PlanReplacementPreview.swift \
  apps/ios/Tests/ReplacementPreviewProbe.swift -o "$probe/replacement-preview"
"$probe/replacement-preview"
