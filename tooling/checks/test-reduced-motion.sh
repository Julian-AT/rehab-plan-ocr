#!/bin/sh
# Uses the actual Settings switch on the disposable UI-test simulator.
set -eu
cd "$(dirname "$0")/../.."
export REHA_UI_MEDIA=0
exec sh tooling/checks/test-native-ui.sh "$@" \
  -only-testing:TermineUITests/AgendaPreviewTests/testReducedMotionSystemSettingKeepsVoiceUsable
