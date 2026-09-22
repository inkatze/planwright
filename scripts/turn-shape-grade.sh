#!/bin/sh
# turn-shape-grade.sh — grade a behavioral-eval run's turn shape from the turn
# records in its decision log (operator-dialogue REQ-M1.1, REQ-M1.2, D-19,
# D-20). scripts/behavioral-eval.sh calls it for a fixture that names turn
# invariants; the turn-shape unit test calls it directly.
#
# It reads what the run wrote, never a pane: the decision log's schema-v2 turn
# records (each projection a surface emitted, mirrored as emitted) and the
# files beside it. The invariants and their reasons live in
# scripts/turn-shape-grade.jq; the schema is in tests/behavioral-evals/README.md.
#
# Every number an invariant needs comes from the fixture, never from here or
# from doctrine: doctrine states the density bound qualitatively, and the
# fixtures tune it on evidence. A listed invariant whose threshold the fixture
# omits is a config error, not a silent default.
#
#   turn_invariants              the invariants to grade (space-separated)
#   turn_expect_fail             invariants this fixture plants a wall for; the
#                                grade holds only if exactly these fail
#   turn_max_tables              no-table-dump: tables allowed in one turn
#   turn_max_chars               projection-present: a turn's length bound
#   turn_max_sections            projection-present (optional): sections per turn
#   turn_artifact_min_tables     projection-present (optional): tables the full
#                                record must carry (completeness governs artifacts)
#   turn_max_confirm_line_chars  no-monotonic-growth: one resume-confirmation line
#   turn_max_selector_ids        identifier-density: identifiers per selector
#   turn_planted_capture         capture-at-birth: the id the persona confirms
#
# Usage: turn-shape-grade.sh [--conf <fixture.conf>] [--invariants <list>]
#                            [--expect-fail <list>] <artifacts-dir>
#   --invariants and --expect-fail override the conf's lists, so one
#   invariant can be graded alone against either side of its fixture pair.
#
# Output: one line per invariant, `PASS <inv>`, `FAIL <inv>: <reason>`,
# `FAIL <inv> (expected): <reason>`, or `UNEXPECTED-PASS <inv>`.
# Exit: 0 every invariant graded as the fixture expects; 1 an unexpected
# failure, an expected failure that passed, or an expected failure with
# nothing to grade (a run that emitted no turns is never a planted wall);
# 2 usage or config error; 3 the artifacts are unreadable or break the
# turn-record schema (fail-closed).
#
# Portable POSIX sh + jq. Artifact content is parsed as data, never executed;
# reasons carry fixture text, so they pass the canonical sanitizer.
set -u
LC_ALL=C
export LC_ALL
unset CDPATH

SELF_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=scripts/echo-safety.sh
. "$SELF_DIR/echo-safety.sh"
PROGRAM="$SELF_DIR/turn-shape-grade.jq"
prog="turn-shape-grade"

KNOWN="no-table-dump projection-present decisions-first no-monotonic-growth identifier-density capture-at-birth step-report-slots open-captures-list"

usage() {
  printf '%s\n' "$prog: $(sanitize_printable "$1")" >&2
  printf '%s\n' "usage: turn-shape-grade.sh [--conf <fixture.conf>] [--invariants <list>] [--expect-fail <list>] <artifacts-dir>" >&2
  exit 2
}

conf=""
art=""
inv_override=""
inv_set=0
xf_override=""
xf_set=0
while [ $# -gt 0 ]; do
  case "$1" in
    --conf)
      [ $# -ge 2 ] || usage "--conf needs a value"
      conf="$2"
      shift 2
      ;;
    --invariants)
      [ $# -ge 2 ] || usage "--invariants needs a value"
      inv_override="$2"
      inv_set=1
      shift 2
      ;;
    --expect-fail)
      [ $# -ge 2 ] || usage "--expect-fail needs a value"
      xf_override="$2"
      xf_set=1
      shift 2
      ;;
    -h | --help)
      sed -n '2,/^[^#]/p' "$0" | sed '$d' | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    -*) usage "unknown option: $1" ;;
    *)
      [ -z "$art" ] || usage "exactly one artifacts dir"
      art="$1"
      shift
      ;;
  esac
done
[ -n "$art" ] || usage "an artifacts dir is required"
[ -d "$art" ] || {
  printf '%s\n' "$prog: artifacts dir '$(sanitize_printable "$art")' does not exist" >&2
  exit 3
}
[ -z "$conf" ] || [ -f "$conf" ] || usage "conf file not found: $conf"
[ -f "$PROGRAM" ] || {
  printf '%s\n' "$prog: the invariant program is missing beside this script" >&2
  exit 2
}

# conf_get <key> — the key's value from the fixture conf (split on the first
# '=', never sourced), or empty.
conf_get() {
  [ -n "$conf" ] || return 0
  while IFS= read -r raw || [ -n "$raw" ]; do
    case "$raw" in
      '' | '#'*) continue ;;
    esac
    [ "${raw%%=*}" = "$1" ] && printf '%s' "${raw#*=}" && return 0
  done <"$conf"
  return 0
}

if [ "$inv_set" -eq 1 ]; then invariants="$inv_override"; else invariants="$(conf_get turn_invariants)"; fi
if [ "$xf_set" -eq 1 ]; then expect_fail="$xf_override"; else expect_fail="$(conf_get turn_expect_fail)"; fi
[ -n "$invariants" ] || usage "no invariants to grade (turn_invariants or --invariants)"

for i in $invariants $expect_fail; do
  case " $KNOWN " in
    *" $i "*) ;;
    *) usage "unknown invariant: $i" ;;
  esac
done
for i in $expect_fail; do
  case " $invariants " in
    *" $i "*) ;;
    *) usage "expected failure '$i' is not among the graded invariants" ;;
  esac
done

# number <key> <required-by> — a threshold as a JSON number, or null when the
# key is unset and nothing listed needs it.
number() {
  _n="$(conf_get "$1")"
  if [ -z "$_n" ]; then
    if [ -n "$2" ]; then
      case " $invariants " in
        *" $2 "*) usage "$2 needs $1 in the fixture conf" ;;
      esac
    fi
    printf 'null'
    return 0
  fi
  case "$_n" in
    *[!0-9]*) usage "$1 must be a whole number" ;;
  esac
  printf '%s' "$_n"
}

planted="$(conf_get turn_planted_capture)"
case " $invariants " in
  *" capture-at-birth "*) [ -n "$planted" ] || usage "capture-at-birth needs turn_planted_capture in the fixture conf" ;;
esac

cfg="$(jq -cn \
  --arg invs "$invariants" \
  --argjson max_tables "$(number turn_max_tables no-table-dump)" \
  --argjson max_chars "$(number turn_max_chars projection-present)" \
  --argjson max_sections "$(number turn_max_sections '')" \
  --argjson artifact_min_tables "$(number turn_artifact_min_tables '')" \
  --argjson max_confirm_line_chars "$(number turn_max_confirm_line_chars no-monotonic-growth)" \
  --argjson max_selector_ids "$(number turn_max_selector_ids identifier-density)" \
  --arg planted "$planted" \
  '{invariants: ($invs | split(" ") | map(select(length > 0))), max_tables: $max_tables,
    max_chars: $max_chars, max_sections: $max_sections, artifact_min_tables: $artifact_min_tables,
    max_confirm_line_chars: $max_confirm_line_chars, max_selector_ids: $max_selector_ids,
    planted_capture: $planted}')" || usage "could not build the grading config"

log="$art/decision-log.jsonl"
if [ -f "$log" ]; then
  log_json="$(jq -cs . "$log" 2>/dev/null)" || {
    printf '%s\n' "$prog: the decision log is not valid JSON lines" >&2
    exit 3
  }
else
  log_json="[]"
fi

# Metadata only (size and table count) for every other file the run wrote, so
# a turn's pointer can be checked against what actually exists.
artifacts="[]"
listing="$(cd "$art" && find . -type f ! -name decision-log.jsonl ! -name sign-off.json 2>/dev/null | sed 's|^\./||' | sort)"
while IFS= read -r name; do
  [ -n "$name" ] || continue
  case "$name" in
    *[!A-Za-z0-9._/-]*) continue ;;
  esac
  entry="$(jq -Rs --arg n "$name" \
    '{name: $n, bytes: length, tables: ([split("\n")[] | select(test("\\|") and test("^ *\\|? *:?-{3,}:? *(\\| *:?-{3,}:? *)*\\|? *$"))] | length)}' \
    "$art/$name" 2>/dev/null)" || {
    printf '%s\n' "$prog: cannot read artifact '$(sanitize_printable "$name")'" >&2
    exit 3
  }
  artifacts="$(printf '%s' "$artifacts" | jq -c --argjson e "$entry" '. + [$e]')"
done <<EOF
$listing
EOF

graded="$(printf '%s' "$log_json" | jq -c --argjson cfg "$cfg" --argjson artifacts "$artifacts" -f "$PROGRAM" 2>&1)" || {
  printf '%s\n' "$prog: the invariant program failed: $(sanitize_printable "$graded")" >&2
  exit 3
}

schema="$(printf '%s' "$graded" | jq -r '.schema_errors[]')"
if [ -n "$schema" ]; then
  printf '%s\n' "$schema" | while IFS= read -r e; do
    printf '%s\n' "$prog: schema: $(sanitize_printable "$e")" >&2
  done
  exit 3
fi

rc=0
lines="$(printf '%s' "$graded" | jq -r '.results[] | "\(.inv)\t\(.ok)\t\(.vacuous // false)\t\(.reason)"')"
while IFS="$(printf '\t')" read -r inv passed vacuous reason; do
  [ -n "$inv" ] || continue
  expected=0
  case " $expect_fail " in
    *" $inv "*) expected=1 ;;
  esac
  if [ "$passed" = "true" ]; then
    if [ "$expected" -eq 1 ]; then
      printf '%s\n' "UNEXPECTED-PASS $inv"
      rc=1
    else
      printf '%s\n' "PASS $inv"
    fi
  elif [ "$expected" -eq 1 ] && [ "$vacuous" = "true" ]; then
    printf '%s\n' "FAIL $inv (expected, but nothing to grade): $(sanitize_printable "$reason")"
    rc=1
  elif [ "$expected" -eq 1 ]; then
    printf '%s\n' "FAIL $inv (expected): $(sanitize_printable "$reason")"
  else
    printf '%s\n' "FAIL $inv: $(sanitize_printable "$reason")"
    rc=1
  fi
done <<EOF
$lines
EOF
exit "$rc"
