#!/bin/sh
set -eu
cd "$(dirname "$0")/../.."
REHA_CALENDAR_PROBE=apps/ios/Tests/CalendarTimezoneProbe.swift sh tooling/checks/test-calendar-answers.sh "$@"
