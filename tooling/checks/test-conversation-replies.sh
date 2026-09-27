#!/bin/sh
set -eu
cd "$(dirname "$0")/../.."
# shellcheck source=tooling/checks/prepare-core-probe.sh
. tooling/checks/prepare-core-probe.sh
swiftc -swift-version 6 -module-cache-path "$probe/cache" -I "$probe" -I packages/apple/RehaCore/Headers -L "$probe" -lRehaCore -Xlinker -rpath -Xlinker "$probe" apps/ios/Features/Conversation/ConversationRules.swift apps/ios/Features/Conversation/ConversationReply.swift apps/ios/Features/Agenda/CalendarEvent.swift apps/ios/Features/Agenda/EventProposal.swift apps/ios/Tests/Support/StableSpeechPhrases.swift apps/ios/Tests/ConversationReplyProbe.swift -o "$probe/replies"
TZ=Europe/Vienna "$probe/replies"
