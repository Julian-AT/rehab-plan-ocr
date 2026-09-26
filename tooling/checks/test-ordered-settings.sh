#!/bin/sh
set -eu
cd "$(dirname "$0")/../.."
probe=$(mktemp -d)
trap 'rm -rf "$probe"' EXIT
swiftc -swift-version 6 apps/ios/Features/Settings/OrderedSettings.swift apps/ios/Tests/OrderedSettingsProbe.swift -o "$probe/settings"
"$probe/settings"
