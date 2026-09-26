#!/bin/sh
set -eu
cd "$(dirname "$0")/../.."
REHA_CALENDAR_PROBE=apps/ios/Tests/CustomAssistantProviderProbe.swift sh tooling/checks/test-calendar-answers.sh "$@"
