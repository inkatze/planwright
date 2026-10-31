#!/usr/bin/env bash
# check-shell-pipe-status.sh — the shell-pipe-status rule: `$?` read straight
# after a pipeline, where it holds the last stage's status, so a failing
# producer behind `| tail` or `| head` reads as success. The scanner and its
# escape hatch are scripts/shell-rule-lib.sh's.
# shellcheck disable=SC2016,SC2034 # literal awk and usage text, read by the sourced library
set -u
unset CDPATH

SR_RULE=shell-pipe-status
SR_USAGE='check-shell-pipe-status.sh — flag $? read after a pipeline.

Usage:
  check-shell-pipe-status.sh [<root>]   scan scripts/, githooks/, tests/lib/
  check-shell-pipe-status.sh --help

Flagged: a $? in the statement after a pipeline, on the same line after a ;
or in the first statement of the next line, a pipeline inside a command
substitution included (x=$(a | b); rc=$?). Not flagged: a line naming
PIPESTATUS, and any file that sets -o pipefail.
Fix: run the producer on its own and keep its status, or read PIPESTATUS.
Exempt a line with a trailing or directly preceding
  # shell-pipe-status: <reason>
Exit codes: 0 clean, 1 an offense, 2 usage or a broken enumeration.'

SR_AWK='
function rule_reset() { pipefail = 0 }
# has_pipe(s): s holds a pipeline whose upstream stages can fail. A producer
# that is only printf or echo of text already in hand cannot, so reading the
# status of the last stage is the intended read there.
function has_pipe(s,   n, k, stages, st1) {
  if (s !~ /(^|[^|])\|([^|&]|$)/) return 0
  gsub(/\|\|/, "\001\001", s)
  n = split(s, stages, "|")
  for (k = 1; k < n; k++) {
    st1 = stages[k]
    if (k == 1) sub(/^.*(\$\(|[;({]|\001\001|&&|then[ \t]|do[ \t])/, "", st1)
    sub(/^[ \t]*/, "", st1)
    if (st1 !~ /^(printf|echo)([ \t]|$)/) return 1
  }
  return 0
}
function rule_check(code, lineno,   head, p) {
  if (code ~ /-[A-Za-z]*o[ \t]+pipefail/) pipefail = 1
  if (pipefail || code ~ /PIPESTATUS/) return ""
  p = index(code, "$?")
  if (!p) p = index(code, "${?}")
  if (!p) return ""
  head = substr(code, 1, p - 1)
  if (head ~ /;/) {
    sub(/;[^;]*$/, "", head)
    sub(/^.*;/, "", head)
    if (has_pipe(head)) return "$? is read after a pipeline, so it holds the last stage status"
    return ""
  }
  if (head ~ /(&&|\|\|)/) return ""
  if (prev_code != "" && has_pipe(prev_code)) return "$? is read after the pipeline on the line above, so it holds the last stage status"
  return ""
}
'

self_dir=$(cd "$(dirname "$0")" && pwd -P) || exit 2
[ -r "$self_dir/shell-rule-lib.sh" ] || {
  printf '%s\n' "check-$SR_RULE: scripts/shell-rule-lib.sh is missing or unreadable" >&2
  exit 2
}
# shellcheck source=scripts/shell-rule-lib.sh
. "$self_dir/shell-rule-lib.sh"
sr_main "$@"
