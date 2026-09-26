#!/bin/sh
set -eu
cd "$(dirname "$0")/../.."
probe=$(mktemp -d)
trap 'rm -r "$probe"' EXIT
swiftc -swift-version 6 -strict-concurrency=complete apps/ios/Features/Conversation/RecognitionTurn.swift apps/ios/Features/Conversation/SpeechAssetReadiness.swift apps/ios/Tests/SpeechAssetReadinessProbe.swift -o "$probe/assets"
"$probe/assets"
