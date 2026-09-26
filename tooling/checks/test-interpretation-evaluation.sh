#!/bin/sh
set -eu
cd "$(dirname "$0")/../.."
REHA_CALENDAR_PROBE=apps/ios/Tests/InterpretationEvaluationProbe.swift sh tooling/checks/test-calendar-answers.sh "$@"
