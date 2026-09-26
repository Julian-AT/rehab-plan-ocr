#!/bin/sh
set -eu
cd "$(dirname "$0")/../.."
probe=$(mktemp -d)
trap 'rm -r "$probe"' EXIT
swiftc -swift-version 6 -strict-concurrency=complete apps/ios/Features/Conversation/OutputAudio.swift apps/ios/Features/Conversation/VictoriaSpeech.swift ml/evaluation/speech/SpeechSampleFile.swift apps/ios/Tests/VictoriaPCMProbe.swift -o "$probe/pcm"
"$probe/pcm"
