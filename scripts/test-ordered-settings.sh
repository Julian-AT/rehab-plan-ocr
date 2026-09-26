#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
probe=$(mktemp -d)
trap 'rm -rf "$probe"' EXIT
swiftc -swift-version 6 apple/Termine/Features/OrderedSettings.swift apple/Tests/OrderedSettingsProbe.swift -o "$probe/settings"
"$probe/settings"
