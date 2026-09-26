#!/bin/sh
set -eu
cd "$(dirname "$0")/../.."
probe=$(mktemp -d)
trap 'rm -r "$probe"' EXIT
source=packages/apple/VoiceActivity/Sources/CFvad
cc -std=c11 -O2 -I"$source/include" -I"$source/src" "$source"/src/*.c "$source"/src/vad/*.c "$source"/src/signal_processing/*.c apps/ios/Tests/vad-probe.c -o "$probe/vad"
ffmpeg -v error -i "${1:-artifacts/continuous-voice-preview/victoria-fruehstueck.wav}" -ar 16000 -ac 1 -f s16le "$probe/speech.pcm"
"$probe/vad" "$probe/speech.pcm"
