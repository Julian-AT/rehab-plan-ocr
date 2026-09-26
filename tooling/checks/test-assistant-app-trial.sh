#!/bin/sh
# Explicit local experimental build; never installs on physical hardware.
set -eu
cd "$(dirname "$0")/../.."
uv run --locked python ml/evaluation/conversation/app_trial.py "$@"
