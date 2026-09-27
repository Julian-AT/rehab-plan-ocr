#!/bin/sh
set -eu
cd "$(dirname "$0")/../.."
eval "$(python3 tooling/dev/workspace.py shell)"
export CARGO_PROFILE_DEV_DEBUG=0 CARGO_INCREMENTAL=0 CARGO_BUILD_JOBS=1
cargo build --locked -p reha-ffi
probe=$(mktemp -d)
trap 'rm -r "$probe"' EXIT
swiftc -j 1 -swift-version 6 -emit-library -emit-module -module-name RehaCore -module-cache-path "$probe/cache" -emit-module-path "$probe/RehaCore.swiftmodule" -I packages/apple/RehaCore/Headers packages/apple/RehaCore/Sources/RehaCore/RehaCore.swift -L "$CARGO_TARGET_DIR/debug" -lreha_ffi -Xlinker -rpath -Xlinker "$CARGO_TARGET_DIR/debug" -o "$probe/libRehaCore.dylib"
swiftc -j 1 -D REHA_PROVIDER_PROBE -swift-version 6 -target arm64-apple-macos26.0 -module-cache-path "$probe/cache" -I "$probe" -I packages/apple/RehaCore/Headers -L "$probe" -lRehaCore -Xlinker -rpath -Xlinker "$probe" @tooling/checks/calendar-answer-sources.rsp apps/ios/Features/Conversation/VoiceDependencies.swift apps/ios/Features/Conversation/ConversationState.swift apps/ios/Features/Agenda/EventProposal.swift apps/ios/Features/Agenda/EventSessionRegistration.swift apps/ios/Features/Agenda/EventMutationClient.swift apps/ios/Features/Agenda/EventHistoryItem.swift apps/ios/Features/Agenda/CalendarQueryClient.swift apps/ios/Features/Agenda/EventSession.swift apps/ios/Features/Conversation/VoiceModel.swift apps/ios/Tests/Support/VoiceFlowFixtures.swift apps/ios/Tests/VoiceFlowProbe.swift -o "$probe/answers"
TZ=Europe/Vienna "$probe/answers" "$@"
