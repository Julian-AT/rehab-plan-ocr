#!/bin/sh
set -eu
cd "$(dirname "$0")/../.."
python3 tooling/checks/audio-runtime.py "$@"
