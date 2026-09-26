#!/bin/sh
set -eu
cd "$(dirname "$0")/../.."
probe=$(mktemp -d)
trap 'rm -rf "$probe"' EXIT
swiftc -swift-version 6 -strict-concurrency=complete apps/ios/Shared/AppTemporaryStore.swift apps/ios/Tests/TemporaryPrivacyProbe.swift -o "$probe/privacy"
"$probe/privacy"
