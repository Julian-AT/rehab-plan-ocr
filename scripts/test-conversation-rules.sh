#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
probe=$(mktemp -d)
trap 'rm -r "$probe"' EXIT
swiftc -swift-version 6 apple/Termine/Features/ConversationRules.swift apple/Termine/Features/EventCategory.swift apple/Tests/ConversationRulesProbe.swift -o "$probe/rules"
"$probe/rules"
