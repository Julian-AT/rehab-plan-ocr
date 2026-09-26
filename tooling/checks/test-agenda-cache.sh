#!/bin/sh
set -eu
cd "$(dirname "$0")/../.."
probe=$(mktemp -d)
trap 'rm -rf "$probe"' EXIT
swiftc -swift-version 6 apps/ios/Features/Agenda/CalendarEvent.swift \
  apps/ios/Features/Agenda/AgendaProjection.swift apps/ios/Features/Agenda/TodayModel.swift \
  apps/ios/Tests/TodayModelProbe.swift -o "$probe/agenda-cache"
"$probe/agenda-cache"
