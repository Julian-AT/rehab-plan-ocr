#!/bin/sh
set -eu
cd "$(dirname "$0")/../.."
probe=$(mktemp -d)
trap 'rm -rf "$probe"' EXIT
swiftc -swift-version 6 -strict-concurrency=complete \
  apps/ios/Features/Conversation/OutputAudio.swift \
  apps/ios/Tests/OutputAudioProbe.swift -o "$probe/output-audio"
"$probe/output-audio"
