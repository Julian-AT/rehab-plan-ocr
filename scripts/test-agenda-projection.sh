#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
probe=$(mktemp -d)
trap 'rm -rf "$probe"' EXIT
swiftc -swift-version 6 apps/ios/Termine/Features/CalendarEvent.swift apps/ios/Termine/Features/AgendaProjection.swift apps/ios/Tests/AgendaProjectionProbe.swift -o "$probe/agenda"
"$probe/agenda"
