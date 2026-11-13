#!/bin/sh
# isolated-hosting.sh — the hosting an `isolated` step gets on a backend
# (custom-steps REQ-D1; doctrine/custom-steps.md, Hosting).
#
# `resolve <backend>` prints `hosting` (isolated | in-session) and `reason`
# (empty unless degraded). A backend is spawn-capable iff
# `orchestrate-backends.sh detect` lists it present with session_grade yes.
# Exit: 0 printed; 2 usage or a name outside [a-z0-9-]; 5 missing sibling.
set -u
LC_ALL=C
export LC_ALL
unset CDPATH

me=isolated-hosting

script_dir=$(cd "$(dirname "$0")" && pwd) || {
  printf '%s\n' "$me: cannot resolve the script directory" >&2
  exit 5
}
BACKENDS="$script_dir/orchestrate-backends.sh"
if [ ! -f "$BACKENDS" ]; then
  printf '%s\n' "$me: missing sibling helper: orchestrate-backends.sh" >&2
  exit 5
fi

if [ "$#" -ne 2 ] || [ "$1" != resolve ]; then
  printf '%s\n' "usage: $me resolve <backend>" >&2
  exit 2
fi
backend=$2

case $backend in
  '' | -* | *[!a-z0-9-]*)
    printf '%s\n' "$me: refusing a backend name outside [a-z0-9-]" >&2
    exit 2
    ;;
esac

# detect's own stderr flows through: a malformed adapter's diagnostic is an
# operator-actionable fact, never swallowed.
rows=$(/bin/sh "$BACKENDS" detect "$backend") || rows=''

spawnable=$(printf '%s\n' "$rows" \
  | awk -F '\t' -v b="$backend" '$1 == b && $7 == "yes" { print "yes"; exit }')

if [ "$spawnable" = yes ]; then
  printf 'hosting\tisolated\n'
  printf 'reason\t\n'
else
  printf 'hosting\tin-session\n'
  printf 'reason\tno session-grade backend "%s" can spawn a fresh session on this host\n' "$backend"
fi
