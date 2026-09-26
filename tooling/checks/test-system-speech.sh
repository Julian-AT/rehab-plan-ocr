#!/bin/sh
set -eu
cd "$(dirname "$0")/../.."
probe=$(mktemp -d)
trap 'rm -rf "$probe"' EXIT
swiftc -swift-version 6 -strict-concurrency=complete -parse-as-library \
  -module-cache-path "$probe/cache" \
  apps/ios/Features/Conversation/OutputAudio.swift \
  apps/ios/Features/Conversation/SystemSpeech.swift \
  apps/ios/Tests/SystemSpeechProbe.swift -o "$probe/system-speech"
"$probe/system-speech" "$@"
