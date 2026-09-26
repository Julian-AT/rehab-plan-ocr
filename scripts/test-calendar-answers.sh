#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
export PATH="$HOME/.cargo/bin:$PATH"
export CARGO_PROFILE_DEV_DEBUG=0 CARGO_INCREMENTAL=0
cargo build --locked -p reha-ffi
probe=$(mktemp -d)
trap 'rm -r "$probe"' EXIT
swiftc -swift-version 6 -emit-library -emit-module -module-name RehaCore -module-cache-path "$probe/cache" -emit-module-path "$probe/RehaCore.swiftmodule" -I packages/apple/RehaCore/Headers packages/apple/RehaCore/Sources/RehaCore/RehaCore.swift -L target/debug -lreha_ffi -Xlinker -rpath -Xlinker "$PWD/target/debug" -o "$probe/libRehaCore.dylib"
swiftc -swift-version 6 -target arm64-apple-macos26.0 -module-cache-path "$probe/cache" -I "$probe" -I packages/apple/RehaCore/Headers -L "$probe" -lRehaCore -Xlinker -rpath -Xlinker "$probe" apps/ios/Termine/Features/ConversationRules.swift apps/ios/Termine/Features/ConversationReply.swift apps/ios/Termine/Features/VoiceRules.swift apps/ios/Termine/Features/CalendarEvent.swift apps/ios/Termine/Features/CalendarVocabulary.swift apps/ios/Termine/Features/CalendarQuestion.swift apps/ios/Termine/Features/CalendarConversation.swift apps/ios/Termine/Features/CalendarUnderstanding.swift apps/ios/Tests/CalendarAnswerProbe.swift -o "$probe/answers"
TZ=Europe/Vienna "$probe/answers" "$@"
