#!/bin/sh
set -eu
cd "$(dirname "$0")/../.."
probe=$(mktemp -d)
trap 'rm -r "$probe"' EXIT
swiftc -swift-version 6 -strict-concurrency=complete apps/ios/Features/Conversation/SpeechInputChannel.swift apps/ios/Features/Conversation/ConversationRules.swift apps/ios/Tests/SpeechInputChannelProbe.swift -o "$probe/input"
"$probe/input"
swiftc -swift-version 6 -strict-concurrency=complete apps/ios/Features/Conversation/SpeechActivity.swift apps/ios/Tests/SpeechActivityProbe.swift -o "$probe/activity"
"$probe/activity"
