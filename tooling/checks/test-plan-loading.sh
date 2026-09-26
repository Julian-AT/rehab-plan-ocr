#!/bin/sh
set -eu
cd "$(dirname "$0")/../.."
probe=$(mktemp -d)
trap 'rm -rf "$probe"' EXIT
swiftc -swift-version 6 -strict-concurrency=complete \
  apps/ios/Features/PlanReview/PlanModel.swift \
  apps/ios/Features/PlanReview/PlanPagesModel.swift \
  apps/ios/Tests/PlanLoadingProbe.swift -o "$probe/plan-loading"
"$probe/plan-loading"
