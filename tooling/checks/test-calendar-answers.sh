#!/bin/sh
set -eu
cd "$(dirname "$0")/../.."
# shellcheck source=tooling/checks/prepare-core-probe.sh
. tooling/checks/prepare-core-probe.sh
swiftc -D REHA_PROVIDER_PROBE -swift-version 6 -target arm64-apple-macos26.0 -module-cache-path "$probe/cache" -I "$probe" -I packages/apple/RehaCore/Headers -L "$probe" -lRehaCore -Xlinker -rpath -Xlinker "$probe" @tooling/checks/calendar-answer-sources.rsp "${REHA_CALENDAR_PROBE:-apps/ios/Tests/CalendarAnswerProbe.swift}" -o "$probe/answers"
TZ=Europe/Vienna "$probe/answers" "$@"
