#!/bin/sh
set -eu
cd "$(dirname "$0")/../.."
probe=$(mktemp -d)
trap 'rm -r "$probe"' EXIT
source=packages/apple/VoiceActivity/Sources/CFvad
cc -std=c11 -O2 -dynamiclib -I"$source/include" -I"$source/src" "$source"/src/*.c "$source"/src/vad/*.c "$source"/src/signal_processing/*.c -o "$probe/libCFvad.dylib"
printf 'module CFvad { header "%s/%s/include/fvad.h" export * }\n' "$PWD" "$source" > "$probe/module.modulemap"
swiftc -swift-version 6 -strict-concurrency=complete -target arm64-apple-macos26.0 -I "$probe" -L "$probe" -lCFvad -Xlinker -rpath -Xlinker "$probe" apps/ios/Features/Conversation/RecognitionTurn.swift apps/ios/Features/Conversation/CalendarVocabulary.swift apps/ios/Features/Conversation/SpeechRecognitionProvider.swift apps/ios/Features/Conversation/InputAudio.swift apps/ios/Features/Conversation/SpeechInputChannel.swift apps/ios/Features/Conversation/SpeechInput.swift apps/ios/Tests/RecognitionTurnProbe.swift -o "$probe/recognition"
"$probe/recognition"
