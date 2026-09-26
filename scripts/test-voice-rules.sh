#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
voice_check_dir=$(mktemp -d)
trap 'rm -rf "$voice_check_dir"' EXIT
swiftc -module-cache-path "$voice_check_dir/cache" apple/Termine/Features/VoiceRules.swift apple/Tests/VoiceRulesProbe.swift -o "$voice_check_dir/voice-rules"
"$voice_check_dir/voice-rules"
