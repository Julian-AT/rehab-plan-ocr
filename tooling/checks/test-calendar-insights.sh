#!/bin/sh
set -eu
cd "$(dirname "$0")/../.."
REHA_CALENDAR_PROBE=apps/ios/Tests/CalendarInsightsProbe.swift sh tooling/checks/test-calendar-answers.sh "$@"
