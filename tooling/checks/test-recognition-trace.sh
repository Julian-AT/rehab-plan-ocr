#!/bin/sh
set -eu
cd "$(dirname "$0")/../.."
probe=$(mktemp -d)
trap 'rm -rf "$probe"' EXIT
swiftc -swift-version 6 apps/ios/Features/PlanReview/RecognitionTraceData.swift apps/ios/Tests/RecognitionTraceProbe.swift -o "$probe/trace"
"$probe/trace"
