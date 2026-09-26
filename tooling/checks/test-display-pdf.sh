#!/bin/sh
set -eu
cd "$(dirname "$0")/../.."
probe=$(mktemp -d)
trap 'rm -rf "$probe"' EXIT
swiftc -swift-version 6 -strict-concurrency=complete \
  apps/ios/Features/PlanReview/DisplayPDF.swift apps/ios/Tests/DisplayPDFProbe.swift \
  -o "$probe/display-pdf"
"$probe/display-pdf"
