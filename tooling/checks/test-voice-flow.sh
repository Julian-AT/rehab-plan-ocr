#!/bin/sh
set -eu
cd "$(dirname "$0")/../.."
export CARGO_BUILD_JOBS=1
# shellcheck source=tooling/checks/prepare-core-probe.sh
. tooling/checks/prepare-core-probe.sh
swiftc -j 1 -D REHA_PROVIDER_PROBE -swift-version 6 -target arm64-apple-macos26.0 -module-cache-path "$probe/cache" -I "$probe" -I packages/apple/RehaCore/Headers -L "$probe" -lRehaCore -Xlinker -rpath -Xlinker "$probe" @tooling/checks/calendar-answer-sources.rsp apps/ios/Features/Conversation/VoiceDependencies.swift apps/ios/Features/Conversation/ConversationState.swift apps/ios/Features/Agenda/EventProposal.swift apps/ios/Features/Agenda/EventSessionRegistration.swift apps/ios/Features/Agenda/EventMutationClient.swift apps/ios/Features/Agenda/EventHistoryItem.swift apps/ios/Features/Agenda/CalendarQueryClient.swift apps/ios/Features/Agenda/EventSession.swift apps/ios/Features/Conversation/VoiceModel.swift apps/ios/Tests/Support/VoiceFlowFixtures.swift apps/ios/Tests/VoiceFlowProbe.swift -o "$probe/answers"
TZ=Europe/Vienna "$probe/answers" "$@"
