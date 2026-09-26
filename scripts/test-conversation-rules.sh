#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
probe=$(mktemp -d)
trap 'rm -r "$probe"' EXIT
swiftc -swift-version 6 apps/ios/Features/Conversation/ConversationRules.swift apps/ios/Features/Agenda/EventCategory.swift apps/ios/Tests/ConversationRulesProbe.swift -o "$probe/rules"
"$probe/rules"
