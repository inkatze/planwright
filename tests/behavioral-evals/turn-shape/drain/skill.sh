#!/bin/sh
# Replays this fixture's scenario through the shared turn-shape stand-in.
unset CDPATH
here="$(cd "$(dirname "$0")" && pwd)"
exec /bin/sh "$here/../../lib/turn-surface.sh" "$here/scenario.jsonl" "${1:-}"
