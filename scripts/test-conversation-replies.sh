#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
export PATH="$HOME/.cargo/bin:$PATH"
export CARGO_PROFILE_DEV_DEBUG=0 CARGO_INCREMENTAL=0
cargo build --locked -p reha-ffi
probe=$(mktemp -d)
trap 'rm -r "$probe"' EXIT
swiftc -swift-version 6 -emit-library -emit-module -module-name RehaCore -module-cache-path "$probe/cache" -emit-module-path "$probe/RehaCore.swiftmodule" -I packages/apple/RehaCore/Headers packages/apple/RehaCore/Sources/RehaCore/RehaCore.swift -L target/debug -lreha_ffi -Xlinker -rpath -Xlinker "$PWD/target/debug" -o "$probe/libRehaCore.dylib"
swiftc -swift-version 6 -module-cache-path "$probe/cache" -I "$probe" -I packages/apple/RehaCore/Headers -L "$probe" -lRehaCore -Xlinker -rpath -Xlinker "$probe" apps/ios/Features/Conversation/ConversationRules.swift apps/ios/Features/Conversation/ConversationReply.swift apps/ios/Features/Agenda/CalendarEvent.swift apps/ios/Features/Agenda/EventProposal.swift apps/ios/Tests/ConversationReplyProbe.swift -o "$probe/replies"
TZ=Europe/Vienna "$probe/replies"
