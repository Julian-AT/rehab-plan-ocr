#!/bin/sh
set -eu
cd "$(dirname "$0")/../.."
probe=$(mktemp -d)
trap 'rm -r "$probe"' EXIT
source=packages/apple/VoiceActivity/Sources/CFvad
cc -std=c11 -O2 -dynamiclib -I"$source/include" -I"$source/src" "$source"/src/*.c "$source"/src/vad/*.c "$source"/src/signal_processing/*.c -o "$probe/libCFvad.dylib"
printf 'module CFvad { header "%s/%s/include/fvad.h" export * }\n' "$PWD" "$source" > "$probe/module.modulemap"
swiftc -swift-version 6 -strict-concurrency=complete -I "$probe" -L "$probe" -lCFvad -Xlinker -rpath -Xlinker "$probe" apps/ios/Features/Conversation/SpeechActivity.swift apps/ios/Features/Conversation/InputAudio.swift apps/ios/Features/Conversation/InputBufferWatchdog.swift apps/ios/Features/Conversation/AudioConfigurationRecovery.swift apps/ios/Tests/InputAudioProbe.swift -o "$probe/audio"
"$probe/audio"
