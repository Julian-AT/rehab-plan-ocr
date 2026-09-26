#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
probe=$(mktemp -d)
trap 'rm -rf "$probe"' EXIT
swiftc -swift-version 6 apps/ios/Termine/Features/CalendarEvent.swift \
  apps/ios/Termine/Features/AgendaProjection.swift apps/ios/Termine/Features/TodayModel.swift \
  apps/ios/Tests/TodayModelProbe.swift -o "$probe/agenda-cache"
"$probe/agenda-cache"
