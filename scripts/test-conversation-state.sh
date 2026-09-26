#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
probe=$(mktemp -d)
trap 'rm -rf "$probe"' EXIT
swiftc -swift-version 6 -strict-concurrency=complete \
  apps/ios/Termine/Features/VoiceRules.swift \
  apps/ios/Termine/Features/ConversationState.swift \
  apps/ios/Tests/ConversationStateProbe.swift -o "$probe/conversation-state"
"$probe/conversation-state"
