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
or in the first statement of the next statement line (blank and comment
lines skipped), a pipeline inside a command substitution included
(x=$(a | b); rc=$?). Not flagged: a pipeline whose upstream stages are only
printf or echo, a line naming PIPESTATUS, and every line after a
set -o pipefail up to a set +o pipefail.
Fix: run the producer on its own and keep its status, or read PIPESTATUS.
Exempt a line with a trailing or directly preceding
  # shell-pipe-status: <reason>
Exit codes: 0 clean, 1 an offense, 2 usage or a scan covering less than it
claims (see scripts/shell-rule-lib.sh).'

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
    # Cut through the last opener before the first stage, one leftmost match
    # at a time: a greedy ^.* over an alternation is not longest in every awk.
    if (k == 1)
      while (match(st1, /\$\(|;|\(|(^|[ \t;&|])\{[ \t]|\001\001|&&|then[ \t]|do[ \t]/))
        st1 = substr(st1, RSTART + RLENGTH)
    sub(/^[ \t]*/, "", st1)
    if (st1 !~ /^(printf|echo)([ \t]|$)/) return 1
  }
  return 0
}
# last_case_arm(body): the body of the last arm of a case statement. The last
# arm follows the last ;; or ;& (or the "in" of the header), and its pattern
# ends at the first ) after that: a cut to the last ) would run through a
# $(...) in the arm body.
function last_case_arm(body) {
  sub(/[ \t;&]*$/, "", body)
  while (match(body, /;;|;&/)) body = substr(body, RSTART + RLENGTH)
  if (match(body, /(^|[ \t;&|(])case[ \t]/)) {
    body = substr(body, RSTART + RLENGTH)
    if (match(body, /[ \t]in([ \t]|$)/)) body = substr(body, RSTART + RLENGTH)
  }
  sub(/^[ \t]*\(?[^()]*\)/, "", body)
  return body
}
# last_stmt(line): the statement whose status a $? on the next line reads. A
# compound command closing on the line returns the status of the last
# statement of its body: cut the closer (and, for esac, through the arm), then
# take only that statement. A closer alone on its line leaves nothing.
function last_stmt(line,   last, closer) {
  last = line
  sub(/[ \t;]*$/, "", last)
  sub(/^.*;/, "", last)
  if (!match(last, /^[ \t]*(\}|fi|done|esac|\))[ \t]*$/)) return last
  closer = last
  gsub(/[ \t]/, "", closer)
  last = line
  sub(/[ \t;]*(\}|fi|done|esac|\))[ \t]*$/, "", last)
  if (closer == "esac") last = last_case_arm(last)
  sub(/[ \t;]*$/, "", last)
  sub(/^.*;/, "", last)
  return last
}
function rule_check(code, lineno,   head, p, last) {
  if (code ~ /-[A-Za-z]*o[ \t]+pipefail/) pipefail = 1
  if (code ~ /\+[A-Za-z]*o[ \t]+pipefail/) pipefail = 0
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
  last = last_stmt(prev_code)
  if (last != "" && has_pipe(last)) return "$? is read after the pipeline on the line above, so it holds the last stage status"
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
