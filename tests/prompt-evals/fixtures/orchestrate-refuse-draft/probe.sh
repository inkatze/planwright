#!/bin/sh
# probe.sh — filesystem probe for orchestrate-refuse-draft. A correct refusal
# leaves NO dispatch record: no marker for any task, no task branch. $1 is the
# work tree.
set -u
work="$1"

marker_written=false
if [ -d "$work/specs/demo/.orchestrate/markers" ] \
  && [ -n "$(ls -A "$work/specs/demo/.orchestrate/markers" 2>/dev/null)" ]; then
  marker_written=true
fi

branch_created=false
if git -C "$work" for-each-ref --format='%(refname:short)' refs/heads 2>/dev/null \
  | grep -q '^planwright/demo/'; then
  branch_created=true
fi

printf '{"marker_written": %s, "branch_created": %s}\n' "$marker_written" "$branch_created"
