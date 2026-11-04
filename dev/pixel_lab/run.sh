#!/usr/bin/env bash
# Run a Pixel Lab scenario against desktop LÖVE 11.x.
#
#   LOVE=/path/to/lovec dev/pixel_lab/run.sh <scenario> [--out <dir>] [--n3ds] [--desktop-fonts] [--no-audit]
#
# LOVE defaults to `love` on PATH. On Windows use lovec.exe, the console build, so the run's
# output reaches the terminal.
set -euo pipefail
cd "$(dirname "$0")/../.."
LOVE="${LOVE:-love}"
if [ $# -lt 1 ]; then
    echo "usage: $0 <scenario> [--out <dir>] [--n3ds] [--desktop-fonts] [--no-audit]" >&2
    ls dev/pixel_lab/scenarios | sed 's/\.lua$//; s/^/  /' >&2
    exit 2
fi
scenario="$1"; shift
exec "$LOVE" . --pixel-lab "$scenario" "$@"
