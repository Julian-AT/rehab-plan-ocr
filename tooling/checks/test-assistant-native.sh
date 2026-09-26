#!/bin/sh
# Explicit local GGUF compatibility test; CI's ordinary tests require no model assets.
set -eu
cd "$(dirname "$0")/../.."
uv run --locked python ml/evaluation/conversation/native.py "$@"
