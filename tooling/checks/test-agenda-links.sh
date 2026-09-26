#!/bin/sh
set -eu
cd "$(dirname "$0")/../.."
probe=$(mktemp -d)
trap 'rm -rf "$probe"' EXIT
swiftc -swift-version 6 -strict-concurrency=complete -warnings-as-errors \
  -module-cache-path "$probe/cache" \
  apps/ios/Features/Agenda/CalendarEvent.swift \
  apps/ios/Features/Agenda/AgendaLinkRequests.swift \
  apps/ios/Tests/AgendaLinkRequestsProbe.swift -o "$probe/agenda-links"
"$probe/agenda-links"
