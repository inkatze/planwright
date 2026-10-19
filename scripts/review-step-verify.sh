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
# unparseable, more or less than one JSON object, of another contract version,
# or carrying any finding outside the versioned fields is
# `{"outcome":"failed","reason":...}` and exits 1: the step handling records
# the step failed, never passed. Otherwise exits 0 with
# `outcome` passed, `findings` (each with its `origin`, body or thread),
# `dropped` (findings citing a path the prompt did not carry, flagged
# `path-not-in-prompt` and named on stderr), `self_resolved` (ids of threads
# the reviewer resolved itself), and `open`: the kept findings still counting
# against convergence, a self-resolved thread among them.
#
# Exit codes: 0 verified, 1 failed result, 2 usage or environment error (the
# inventory unreadable or naming no path, jq missing or unable to run the
# check).
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
case $inventory in
  -*) inventory=./$inventory ;;
esac
case $result in
  -*) result=./$result ;;
esac
[ -f "$inventory" ] && [ -r "$inventory" ] || {
  printf '%s\n' "$prog: cannot read the prompt inventory" >&2
  exit 2
}

env_error() {
  printf '%s\n' "$prog: $1" >&2
  exit 2
}

failed() {
  jq -cn --arg r "$1" '{contract: 1, outcome: "failed", reason: $r}' \
    || printf '%s\n' '{"contract":1,"outcome":"failed","reason":"the result failed verification"}'
  exit 1
}

[ -f "$result" ] && [ -r "$result" ] || failed "the step left no readable result"
grep -q '[^[:space:]]' "$result" || failed "the step returned an empty result"
if ! jq -s . "$result" >/dev/null 2>&1; then
  # jq's parse-error exit code differs across versions; a jq that still runs
  # places the fault in the result.
  jq -n true >/dev/null 2>&1 || env_error "jq could not run"
  failed "the result is not parseable JSON"
fi

# shellcheck disable=SC2016 # jq program text, expanded by jq, not the shell
verify_jq='
def norm: sub("^(\\./)+"; "");
def inventory_paths: split("\n") | map(gsub("^\\s+|\\s+$"; "") | norm)
  | map(select(length > 0 and (startswith("#") | not)));
def nonblank: type == "string" and (gsub("\\s"; "") | length) > 0;
def fields_ok($allowed): type == "object" and (keys - $allowed | length) == 0
  and has("path") and has("line") and has("severity") and has("summary")
  and (.path == null or (.path | nonblank))
  and (.line == null or ((.line | type) == "number" and .line >= 1 and .line == (.line | floor)))
  and (.severity | IN("critical", "high", "medium", "low"))
  and (.summary | nonblank);
def finding_ok: fields_ok(["path", "line", "severity", "summary"]);
def thread_ok: fields_ok(["id", "path", "line", "severity", "summary", "resolved", "resolved_by"])
  and (.id | type == "string" and test("\\A[A-Za-z0-9_=-]+\\z"))
  and (.resolved | type) == "boolean" and has("resolved_by")
  and ((.resolved == false and .resolved_by == null)
       or (.resolved == true and (.resolved_by | IN("reviewer", "run", "human"))));
($inv | inventory_paths) as $paths
| if ($paths | length) == 0 then {outcome: "no-inventory"}
  elif length != 1 then {outcome: "failed", reason: "the result holds \(length) JSON values, not one"}
  else .[0]
  | if type != "object" then {outcome: "failed", reason: "the result is not a JSON object"}
    elif .contract != 1 then {outcome: "failed", reason: "the result is not under contract 1"}
    elif (.body_findings | type) != "array" or (.threads | type) != "array" then
      {outcome: "failed", reason: "the result lacks the body_findings and threads arrays"}
    elif (.body_findings | all(finding_ok) | not) then {outcome: "failed", reason: "a body finding is outside the contract 1 fields"}
    elif (.threads | all(thread_ok) | not) then {outcome: "failed", reason: "a thread is outside the contract 1 fields"}
    else
      ([.body_findings[] | . + {origin: "body"}] + [.threads[] | . + {origin: "thread"}]
        | map(if .path == null then . else .path |= norm end)) as $all
      | ($all | map(select(.path == null or (.path as $p | any($paths[]; . == $p))))) as $kept
      | {outcome: "passed",
         findings: $kept,
         dropped: ($all - $kept | map(. + {flag: "path-not-in-prompt"})),
         self_resolved: [$kept[] | select(.origin == "thread" and .resolved_by == "reviewer") | .id],
         open: ($kept | map(select(.origin == "body" or .resolved == false or .resolved_by == "reviewer")) | length)}
    end
  end
| {contract: 1} + .
'

out=$(jq -cs --rawfile inv "$inventory" "$verify_jq" "$result") \
  || env_error "jq could not run the contract check"
case $out in
  '{"contract":1,"outcome":"no-inventory"}') env_error "the prompt inventory names no path; record it at dispatch" ;;
esac

dropped=$(printf '%s\n' "$out" | jq -r '.dropped[]?.path | gsub("[\\r\\n]"; " ")') \
  || env_error "jq could not list the dropped findings"
if [ -n "$dropped" ]; then
  printf '%s\n' "$dropped" | while IFS= read -r p; do
    printf '%s\n' "$prog: dropped a finding citing $(sanitize_printable "$p"): absent from the prompt inventory" >&2
  done
fi
printf '%s\n' "$out"
case $out in
  '{"contract":1,"outcome":"passed",'*) exit 0 ;;
  *) exit 1 ;;
esac
