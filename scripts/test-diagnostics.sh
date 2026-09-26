#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
probe=$(mktemp -d)
trap 'rm -rf "$probe"' EXIT
swiftc -swift-version 6 apple/Packages/AppleServices/Sources/AppleServices/LocalDiagnostics.swift apple/Tests/DiagnosticsProbe.swift -o "$probe/diagnostics"
"$probe/diagnostics"
