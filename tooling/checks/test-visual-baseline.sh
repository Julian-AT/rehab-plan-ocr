#!/bin/sh
# Explicit serial simulator capture and exact comparison, using synthetic data.
set -eu
cd "$(dirname "$0")/../.."
uv run --locked python tooling/checks/compare-visual-suite.py --capture "$@"
