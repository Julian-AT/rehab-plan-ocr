#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
probe=$(mktemp -d)
trap 'rm -rf "$probe"' EXIT
swiftc -swift-version 6 apple/Termine/Features/CalendarEvent.swift apple/Termine/Features/AgendaProjection.swift apple/Tests/AgendaProjectionProbe.swift -o "$probe/agenda"
"$probe/agenda"
