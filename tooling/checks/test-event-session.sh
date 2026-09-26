#!/bin/sh
set -eu
cd "$(dirname "$0")/../.."
probe=$(mktemp -d)
trap 'rm -rf "$probe"' EXIT
swiftc -swift-version 6 -strict-concurrency=complete \
  apps/ios/Features/Agenda/EventSessionRegistration.swift \
  apps/ios/Tests/EventSessionRegistrationProbe.swift -o "$probe/event-session"
"$probe/event-session"
