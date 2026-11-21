#!/bin/sh
# mc-session-names.sh — the names of the sessions that exist now, one per
# line: every launched mission-control session and every fleet registry
# worker whose last row is not retired. Read-only; it starts nothing.
#
# Exit 0 with the names (none at all reads as an unreadable source, exit 1);
# 1 when either source cannot be read.
set -u
LC_ALL=C
export LC_ALL
unset CDPATH

script_dir=$(cd "$(dirname "$0")" && pwd) || exit 1
launched=$(/bin/sh "$script_dir/mission-control-launch.sh" list 2>/dev/null </dev/null) || exit 1
registry=$(/bin/sh "$script_dir/fleet-state.sh" registry 2>/dev/null </dev/null) || exit 1
names=$(
  {
    printf '%s\n' "$launched" | awk -F '\t' 'NF { print $1 }'
    printf '%s\n' "$registry" | awk -F '\t' 'NF { closed[$2] = (NF == 8 && $8 == "closed") } END { for (w in closed) if (!closed[w]) print w }'
  }
)
[ -n "$names" ] || exit 1
printf '%s\n' "$names"
