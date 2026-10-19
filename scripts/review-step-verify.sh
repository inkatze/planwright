#!/bin/sh
# review-step-verify.sh — apply the external review step output contract to a
# step's result (review-effectiveness REQ-E1.4, D-5). The contract, its
# versioned finding fields, and why each rule exists are in
# doctrine/review-independence.md; this script is its mechanical half.
#
# Usage: review-step-verify.sh --inventory <file> --result <file>
#   --inventory  the prompt inventory the step handling recorded at dispatch:
#                one repository-relative path per line, blank lines and `#`
#                lines ignored, a leading `./` dropped.
#   --result     the step's output, one JSON object under contract 1.
#
# Prints one JSON object on stdout. A result that is absent, empty,
# unparseable, of another contract version, or carrying a finding outside the
# versioned fields is `{"outcome":"failed","reason":...}` and exits 1: the
# step handling records the step failed, never passed. Otherwise exits 0 with
# `outcome` passed, `findings` (each with its `origin`, body or thread),
# `dropped` (findings citing a path the prompt did not carry, flagged
# `path-not-in-prompt` and named on stderr), `self_resolved` (ids of threads
# the reviewer resolved itself), and `open`: the kept findings still counting
# against convergence, a self-resolved thread among them.
#
# Exit codes: 0 verified, 1 failed result, 2 usage or environment error (the
# inventory unreadable, jq missing).
set -u
LC_ALL=C
export LC_ALL
unset CDPATH

prog=review-step-verify
here=$(cd "$(dirname "$0")" && pwd) || exit 2

if [ -r "$here/echo-safety.sh" ]; then
  # shellcheck source=scripts/echo-safety.sh
  . "$here/echo-safety.sh"
else
  sanitize_printable() { printf '%s' "$1" | tr -d '\000-\037\177\200-\237'; }
fi

usage() {
  printf '%s\n' "usage: $prog --inventory <file> --result <file>" >&2
}

inventory=
result=
while [ $# -gt 0 ]; do
  case $1 in
    --inventory | --result)
      [ $# -ge 2 ] && [ -n "$2" ] || {
        usage
        exit 2
      }
      if [ "$1" = --inventory ]; then inventory=$2; else result=$2; fi
      shift 2
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      usage
      exit 2
      ;;
  esac
done
[ -n "$inventory" ] && [ -n "$result" ] || {
  usage
  exit 2
}
command -v jq >/dev/null 2>&1 || {
  printf '%s\n' "$prog: jq is required" >&2
  exit 2
}
[ -f "$inventory" ] && [ -r "$inventory" ] || {
  printf '%s\n' "$prog: cannot read the prompt inventory" >&2
  exit 2
}

failed() {
  jq -cn --arg r "$1" '{contract: 1, outcome: "failed", reason: $r}'
  exit 1
}

case $result in
  -*) result=./$result ;;
esac
[ -f "$result" ] && [ -r "$result" ] || failed "the step left no readable result"
grep -q '[^[:space:]]' "$result" || failed "the step returned an empty result"

# shellcheck disable=SC2016 # jq program text, expanded by jq, not the shell
prog_jq='
def norm: sub("^(\\./)+"; "");
def nonblank: type == "string" and (gsub("\\s"; "") | length) > 0;
def finding_ok: type == "object"
  and ((.path // null) == null or (.path | nonblank))
  and ((.line // null) == null or ((.line | type) == "number" and .line >= 1 and .line == (.line | floor)))
  and (.severity | IN("critical", "high", "medium", "low"))
  and (.summary | nonblank);
def thread_ok: finding_ok and (.id | nonblank) and (.resolved | type) == "boolean"
  and ((.resolved == false and (.resolved_by // null) == null)
       or (.resolved == true and (.resolved_by | IN("reviewer", "run", "human"))));
($inv | split("\n") | map(gsub("^\\s+|\\s+$"; "") | norm)
  | map(select(length > 0 and (startswith("#") | not)))) as $paths
| if length != 1 then {outcome: "failed", reason: "the result holds \(length) JSON values, not one"}
  else .[0]
  | if type != "object" then {outcome: "failed", reason: "the result is not a JSON object"}
    elif .contract != 1 then {outcome: "failed", reason: "the result is not under contract 1"}
    elif (.body_findings | type) != "array" or (.threads | type) != "array" then
      {outcome: "failed", reason: "the result lacks the body_findings and threads arrays"}
    elif (.body_findings | all(finding_ok) | not) then {outcome: "failed", reason: "a body finding is outside the contract 1 fields"}
    elif (.threads | all(thread_ok) | not) then {outcome: "failed", reason: "a thread is outside the contract 1 fields"}
    else
      ([.body_findings[] | . + {origin: "body"}] + [.threads[] | . + {origin: "thread"}]
        | map(if (.path // null) == null then . else .path |= norm end)) as $all
      | ($all | map(select((.path // null) == null or (.path as $p | any($paths[]; . == $p))))) as $kept
      | {outcome: "passed",
         findings: $kept,
         dropped: ($all - $kept | map(. + {flag: "path-not-in-prompt"})),
         self_resolved: [$kept[] | select(.origin == "thread" and .resolved_by == "reviewer") | .id],
         open: ($kept | map(select(.origin == "body" or .resolved == false or .resolved_by == "reviewer")) | length)}
    end
  end
| {contract: 1} + .
'

rc=0
out=$(jq -cs --rawfile inv "$inventory" "$prog_jq" "$result" 2>/dev/null) || rc=$?
[ "$rc" -eq 0 ] || failed "the result is not parseable JSON"

printf '%s\n' "$out" | jq -r '.dropped[]?.path' | while IFS= read -r p; do
  printf '%s\n' "$prog: dropped a finding citing $(sanitize_printable "$p"): absent from the prompt inventory" >&2
done
printf '%s\n' "$out"
case $(printf '%s\n' "$out" | jq -r .outcome) in
  passed) exit 0 ;;
  *) exit 1 ;;
esac
