#!/bin/sh
set -eu
cd "$(dirname "$0")/../.."
probe=$(mktemp -d)
trap 'rm -rf "$probe"' EXIT
swiftc -swift-version 6 -strict-concurrency=complete \
  apps/ios/Shared/AppTemporaryStore.swift \
  apps/ios/Features/Settings/TemporaryDiagnosticExport.swift \
  apps/ios/Tests/DiagnosticExportProbe.swift -o "$probe/diagnostic-export"
"$probe/diagnostic-export"
