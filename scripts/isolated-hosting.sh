#!/bin/sh
# isolated-hosting.sh — the run-time hosting an `isolated` step actually gets on
# a backend (custom-steps REQ-D1; doctrine/custom-steps.md, Hosting).
#
# An isolated step launches a fresh session through the backend. A backend that
# cannot spawn one (no session-grade rung present, or an unknown pluggable name
# with no working adapter) degrades the step to `in-session` instead of
# dispatching nothing, and the reason is recorded (step-record.sh write
# --degraded) so the degradation is never silent.
#
# Usage:
#   isolated-hosting.sh resolve <backend>
#     Print two TAB-separated lines:
#       hosting<TAB>isolated | in-session
#       reason<TAB><text, empty unless the hosting degraded>
#     A backend is spawn-capable iff `orchestrate-backends.sh detect` lists it as
#     present with session_grade yes (the presence answer comes from detect, so
#     a shipped rung whose CLI is absent, and a pluggable name with no adapter,
#     both degrade).
#
# Exit codes: 0 a hosting was printed; 2 usage error or a backend name outside
# the identifier grammar (refused, nothing printed); 5 orchestrate-backends.sh
# is missing (broken install).
#
# POSIX sh. The backend name is data: it is validated against a lowercase
# identifier charset before it reaches any command.
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
