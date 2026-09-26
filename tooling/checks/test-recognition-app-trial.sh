#!/bin/sh
set -eu
cd "$(dirname "$0")/../.."
uv run --locked python ml/evaluation/recognition/app_trial.py "$@"
