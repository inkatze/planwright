#!/bin/bash
# The tower deny floor in every spelling the policy guard can read
# (tower-placement REQ-D1.2): each spelling row of
# tests/fixtures/tower-deny-acts.tsv (global options, long-option prefixes,
# ref forms, repo aliases, case) is refused by scripts/tower-session.sh in a
# marked session with no profile, and the tower-only acts leave the worker
# tier unchanged (REQ-G1.2).
#
# Runs standalone under /bin/bash (the bash 3.2 floor).
unset CDPATH
# shellcheck source=tests/lib/tower-floor-harness.sh
. "$(cd "$(dirname "$0")" && pwd)/lib/tower-floor-harness.sh"

echo "# every spelling row: refused in a marked session (REQ-D1.2)"
while IFS="$TAB" read -r kind act form cmd; do
  [ "$kind" = spelling ] || continue
  ts_bash "$cmd"
  expect deny "[$act/$form] $cmd"
done <"$MAP"

echo "# the tower acts are tower-only: the worker tier is unchanged (REQ-G1.2)"
for cmd in 'git reset --hard HEAD' 'git branch -f topic HEAD' 'git update-ref refs/heads/topic HEAD' \
  'git worktree add --force ../w topic' 'git hr HEAD'; do
  pg worker "$cmd"
  expect defer "worker tier defers: $cmd"
done
pg_payload worker mcp "$(jq -nc '{tool_name:"mcp__github__update_pull_request", tool_input:{pullNumber:1, title:"t"}}')"
expect defer "worker tier: an update_pull_request with no draft field still defers"

no_gh_calls
finish
