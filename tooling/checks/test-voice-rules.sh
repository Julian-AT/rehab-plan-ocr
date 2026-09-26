#!/bin/sh
set -eu
cd "$(dirname "$0")/../.."
voice_check_dir=$(mktemp -d)
trap 'rm -rf "$voice_check_dir"' EXIT
swiftc -swift-version 6 -strict-concurrency=complete -module-cache-path "$voice_check_dir/cache" apps/ios/Features/Conversation/VoiceRules.swift apps/ios/Tests/VoiceRulesProbe.swift -o "$voice_check_dir/voice-rules"
"$voice_check_dir/voice-rules"
