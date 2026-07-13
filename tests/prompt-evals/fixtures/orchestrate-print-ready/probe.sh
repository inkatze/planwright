#!/bin/sh
# probe.sh — filesystem probe for orchestrate-print-ready. Emits the observable
# side effects /orchestrate's print dispatch should leave in the work tree ($1):
# the dispatch marker for the selected unit (Task 1) at the marker path contract
# `<spec-dir>/.orchestrate/markers/<id>`, and the task branch it prepares. The
# runner merges this JSON into the outcome assert.jq grades.
set -u
work="$1"

marker_written=false
[ -f "$work/specs/demo/.orchestrate/markers/1" ] && marker_written=true

branch_created=false
if git -C "$work" rev-parse --verify --quiet "planwright/demo/task-1" >/dev/null 2>&1; then
  branch_created=true
fi

printf '{"marker_written": %s, "branch_created": %s}\n' "$marker_written" "$branch_created"
