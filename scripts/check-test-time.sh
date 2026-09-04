#!/usr/bin/env bash
# check-test-time.sh — test wall-clock budget gate.
#
# The shell suite's wall-clock only ever grows, and nobody revisits a green
# gate: the observation that motivated this guard was a suite that had crept
# from seconds to minutes one harmless-looking fixture at a time. This gate
# makes that creep a reviewed decision instead of an accident, the way
# check-instructions.sh does for instruction size: explicit committed budgets,
# and a bump is a conscious edit in the PR that needs it.
#
# Two budgets, read from config/test-time-budget.yml: a per-file ceiling that
# applies to every test file alike, and a suite-total ceiling on the runner's
# wall-clock. A measured time GREATER THAN OR EQUAL TO its budget trips, the
# same boundary convention check-instructions uses.
#
# The gate never runs the suite. It reads the timing report scripts/run-tests.sh
# persists after each run (tests/.timing-report.tsv by default), so wiring it
# after `test` in the `check` aggregate costs one file read, not a second suite
# pass against ci.yml's job timeout. That makes the report's completeness the
# whole game, so the accounting is positive: every discovered tests/*.sh file
# must have exactly one entry, an entry for a file that no longer exists means
# the report describes a different suite than the one on disk, and a report
# that is missing, empty, or malformed is exit 2, never a pass. None of that
# is softened by the local mode below — it is structural, not a verdict.
#
# CI hard-fails, local warns. The budgets are measured on the reference runner
# (GitHub Actions), and a dev box differs from it in core count, contention,
# and platform cost by factors that swamp any headroom: one contended local
# run measured a file at 75x its runner time. So on the runner an overrun
# fails `mise run check`; anywhere else the same overrun prints a loud warning
# naming the file and the fact that CI would fail, and exits 0. The mode
# derives from GITHUB_ACTIONS and can be forced with --mode.
#
# The ranked table this prints is also the baseline a budget is derived from:
# CI mode prints every file so the job log carries the whole distribution.
#
# Usage:
#   check-test-time.sh [--mode ci|local] [--suite <dir>] [--report <path>]
#                      [--budget <path>] [--all]
#   check-test-time.sh --help | -h
#
# Exit codes: 0 within budget (or local mode), 1 a budget tripped in CI mode,
# 2 usage, an unreadable budget, or a report the gate cannot trust.
#
# Portable bash 3.2 / BSD tooling; no fish/mise/tmux/Ansible.
set -u

LC_ALL=C
export LC_ALL

unset CDPATH

self_dir="$(cd "$(dirname "$0")" && pwd -P)"
repo_root="$(cd "$(dirname "$0")/.." && pwd -P)"

# Display sanitizer for untrusted content headed for the terminal (echo
# discipline, doctrine/security-posture.md): test-file names are PR-authored
# and every path argument is caller-supplied. The inline fallback keeps
# diagnostics safe when the shared helper cannot be sourced.
sanitize_printable() {
  _sp=$(printf '%s' "$1" | tr -d '\000-\037\177\200-\237' 2>/dev/null) || _sp=''
  if [ -z "$_sp" ] && [ $# -ge 2 ]; then
    _sp=$2
  fi
  printf '%s' "$_sp"
}
if [ -r "$self_dir/echo-safety.sh" ]; then
  # shellcheck source=scripts/echo-safety.sh
  . "$self_dir/echo-safety.sh"
fi

fail_closed() {
  echo "check-test-time: $1" >&2
  exit 2
}

usage() {
  cat <<'EOF'
check-test-time.sh — fail (in CI) or warn (locally) when the test suite's
measured wall-clock reaches a committed budget.

Usage:
  check-test-time.sh [--mode ci|local] [--suite <dir>] [--report <path>]
                     [--budget <path>] [--all]
  check-test-time.sh --help | -h

  --mode    ci: an overrun fails (exit 1). local: it warns loudly and exits 0.
            Default: ci when GITHUB_ACTIONS=true, local otherwise.
  --suite   the test directory whose *.sh files must all be in the report
            (default: <repo>/tests)
  --report  the timing report scripts/run-tests.sh wrote
            (default: <suite>/.timing-report.tsv)
  --budget  the committed budgets (default: <repo>/config/test-time-budget.yml)
  --all     print every file in the ranked table, not only the slowest few
            (CI mode always prints every file so the log carries the baseline)

Budgets: per_file_seconds applies to every file; suite_total_seconds applies to
the runner's wall-clock for the whole run. Measured >= budget trips.

Never re-runs the suite: run `mise run test` (or `mise run check`, which orders
this after it) to refresh the report.

Fail-closed, in both modes: a report that is missing, empty, or malformed, an
entry missing for a discovered test file, an entry for a file the suite no
longer has, or a budget file the gate cannot parse is exit 2, never a pass.

Bumping a budget: a budget is raised only as a conscious, reviewed edit to the
budget file in the PR that needs it, with the measured baseline and the
headroom recorded in the file's comment; the file's header states the rule.
Measure on the reference runner (this gate's CI-mode log), never on a shared
dev box, and split or slim the offending file before reaching for the bump.
EOF
}

mode=""
suite=""
report=""
budget=""
show_all=0
while [ "$#" -gt 0 ]; do
  case "$1" in
    --mode | --suite | --report | --budget)
      [ "$#" -ge 2 ] || fail_closed "$1 needs a value (see --help)"
      case "$1" in
        --mode) mode="$2" ;;
        --suite) suite="$2" ;;
        --report) report="$2" ;;
        --budget) budget="$2" ;;
      esac
      shift 2
      ;;
    --all)
      show_all=1
      shift
      ;;
    --help | -h)
      [ "$#" -eq 1 ] || fail_closed "--help takes no other arguments"
      usage
      exit 0
      ;;
    *)
      fail_closed "unknown option: $(sanitize_printable "$1" "(unprintable)") (see --help)"
      ;;
  esac
done

if [ -z "$mode" ]; then
  if [ "${GITHUB_ACTIONS:-}" = "true" ]; then
    mode=ci
  else
    mode=local
  fi
fi
case "$mode" in
  ci | local) ;;
  *) fail_closed "unknown mode: $(sanitize_printable "$mode" "(unprintable)") (expected ci or local)" ;;
esac
[ "$mode" = ci ] && show_all=1

[ -n "$suite" ] || suite="$repo_root/tests"
[ -n "$report" ] || report="$suite/.timing-report.tsv"
[ -n "$budget" ] || budget="$repo_root/config/test-time-budget.yml"
safe_suite="$(sanitize_printable "$suite" "(unprintable path)")"
safe_report="$(sanitize_printable "$report" "(unprintable path)")"
safe_budget="$(sanitize_printable "$budget" "(unprintable path)")"

# --- Budgets ---------------------------------------------------------------
# A flat `key: value` file, read as data. Every line that is not a comment,
# blank, or the document marker must be one of the two known keys with a
# positive number; anything else means the file is not the one this gate
# expects, and a budget it cannot trust is not a budget of zero.
[ -f "$budget" ] || fail_closed "budget file not found: $safe_budget"
[ -r "$budget" ] || fail_closed "budget file not readable: $safe_budget"

per_file=""
suite_total=""
is_positive_number() {
  case "$1" in
    '' | *[!0-9.]* | .* | *. | *.*.*) return 1 ;;
  esac
  awk -v v="$1" 'BEGIN { exit !(v + 0 > 0) }'
}
while IFS= read -r line || [ -n "$line" ]; do
  case "$line" in
    '' | '#'* | '---'*) continue ;;
  esac
  case "$line" in
    *[!' 	']*) ;;
    *) continue ;;
  esac
  key="${line%%:*}"
  val="${line#*:}"
  [ "$key" != "$line" ] || fail_closed "budget file line is not 'key: value': $(sanitize_printable "$line" "(unprintable)")"
  val="${val%%#*}"
  val="${val#"${val%%[! 	]*}"}"
  val="${val%"${val##*[! 	]}"}"
  case "$key" in
    per_file_seconds)
      [ -z "$per_file" ] || fail_closed "budget file sets per_file_seconds twice"
      is_positive_number "$val" || fail_closed "per_file_seconds is not a positive number: $(sanitize_printable "$val" "(unprintable)")"
      per_file="$val"
      ;;
    suite_total_seconds)
      [ -z "$suite_total" ] || fail_closed "budget file sets suite_total_seconds twice"
      is_positive_number "$val" || fail_closed "suite_total_seconds is not a positive number: $(sanitize_printable "$val" "(unprintable)")"
      suite_total="$val"
      ;;
    *)
      fail_closed "budget file has an unknown key: $(sanitize_printable "$key" "(unprintable)")"
      ;;
  esac
done <"$budget"
[ -n "$per_file" ] || fail_closed "budget file sets no per_file_seconds: $safe_budget"
[ -n "$suite_total" ] || fail_closed "budget file sets no suite_total_seconds: $safe_budget"

# --- Discovery -------------------------------------------------------------
# The same glob scripts/run-tests.sh dispatches, so "every discovered file"
# here is exactly the set that ran.
[ -d "$suite" ] || fail_closed "suite directory not found: $safe_suite"
files=("$suite"/*.sh)
if [ "${#files[@]}" -eq 0 ] || [ ! -e "${files[0]}" ]; then
  fail_closed "no *.sh test files in $safe_suite — nothing to check a report against"
fi

work="$(mktemp -d "${TMPDIR:-/tmp}/check-test-time.XXXXXX")" \
  || fail_closed "could not create a temporary directory"
trap 'rm -rf "$work"' EXIT

newline='
'
tab="$(printf '\t')"
: >"$work/discovered"
for f in "${files[@]}"; do
  name="${f##*/}"
  # The report is tab-delimited and the discovered list newline-delimited; a
  # name carrying either could not be matched, and silently dropping it is
  # the hole this gate exists to refuse.
  case "$name" in
    *"$newline"* | *"$tab"*)
      fail_closed "test filename contains a newline or tab, refusing: $(sanitize_printable "$name" "(unprintable filename)")"
      ;;
  esac
  printf '%s\n' "$name" >>"$work/discovered"
done

# --- Report ----------------------------------------------------------------
[ -e "$report" ] || fail_closed "timing report not found: $safe_report — run \`mise run test\` first (\`mise run check\` orders this gate after it)"
[ -r "$report" ] || fail_closed "timing report not readable: $safe_report"
[ -s "$report" ] || fail_closed "timing report is empty: $safe_report — run \`mise run test\` first"

# One awk pass validates the report against the discovered set and emits
# either `E<TAB>message` (the gate fails closed on the first) or the rows
# (`R<TAB>name<TAB>seconds`) and the wall-clock (`W<TAB>seconds`).
awk -F'\t' -v discovered="$work/discovered" '
  BEGIN {
    while ((getline n < discovered) > 0) want[n] = 1
    close(discovered)
    num = "^[0-9]+(\\.[0-9]+)?$"
    wall = ""
    err = 0
  }
  err { next }
  NR == 1 {
    if ($1 != "planwright-test-timing" || $2 != "1") {
      print "E\treport header is not a planwright-test-timing version 1 header"
      err = 1
    }
    next
  }
  $1 == "file" {
    if (NF != 3 || $2 == "") {
      print "E\tmalformed file row at line " NR
      err = 1
      next
    }
    if ($3 !~ num) {
      print "E\tnon-numeric time for " $2 " at line " NR
      err = 1
      next
    }
    if ($2 in seen) {
      print "E\tduplicate entry for " $2 " at line " NR
      err = 1
      next
    }
    seen[$2] = $3
    if (!($2 in want)) extra[$2] = 1
    next
  }
  $1 == "suite" && $2 == "wall" {
    if (NF != 3 || $3 !~ num) {
      print "E\tmalformed suite wall-clock row at line " NR
      err = 1
      next
    }
    if (wall != "") {
      print "E\tduplicate suite wall-clock row at line " NR
      err = 1
      next
    }
    wall = $3
    next
  }
  {
    print "E\tunrecognised report row at line " NR
    err = 1
  }
  END {
    if (err) exit 0
    if (wall == "") { print "E\treport has no suite wall-clock row"; exit 0 }
    missing = ""
    for (n in want) if (!(n in seen)) missing = missing " " n
    if (missing != "") { print "E\treport has no timing entry for discovered file(s):" missing; exit 0 }
    stale = ""
    for (n in extra) stale = stale " " n
    if (stale != "") { print "E\treport is stale: it names file(s) the suite no longer has:" stale; exit 0 }
    for (n in seen) print "R\t" n "\t" seen[n]
    print "W\t" wall
  }
' "$report" >"$work/parsed" || fail_closed "could not read the timing report: $safe_report"

if IFS= read -r first <"$work/parsed" && [ "${first%%"$tab"*}" = "E" ]; then
  fail_closed "$(sanitize_printable "${first#E"$tab"}" "(unprintable)") in $safe_report"
fi
[ -s "$work/parsed" ] || fail_closed "timing report yielded no rows: $safe_report"

wall="$(awk -F'\t' '$1 == "W" { print $2 }' "$work/parsed")"
grep "^R$tab" "$work/parsed" | sort -t "$tab" -k3,3nr >"$work/ranked" \
  || fail_closed "could not rank the report"
count="$(wc -l <"$work/ranked" | tr -d ' ')"

# --- Verdict ---------------------------------------------------------------
# Ranked slowest-first; overruns are always at the top, so a truncated local
# table never hides one. The table goes through the sanitizer as a whole
# (names are PR-authored), keeping tabs and newlines.
limit=10
[ "$show_all" -eq 1 ] && limit="$count"
echo "check-test-time: $count files ranked slowest-first (per-file budget ${per_file}s, suite-total budget ${suite_total}s, mode $mode)"
awk -F'\t' -v per_file="$per_file" -v limit="$limit" '
  {
    n++
    over = ($3 + 0 >= per_file + 0)
    if (n <= limit || over) printf "  %10ss  %s%s\n", $3, $2, (over ? "  >= per-file budget" : "")
  }
  END { if (n > limit) printf "  (%d more under budget; --all lists them)\n", n - limit }
' "$work/ranked" | tr -d '\000-\010\013\014\016-\037\177'
echo "  suite wall-clock ${wall}s (suite-total budget ${suite_total}s)"

offenders="$(awk -F'\t' -v per_file="$per_file" '$3 + 0 >= per_file + 0 { printf " %s (%ss)", $2, $3 }' "$work/ranked" | tr -d '\000-\010\013\014\016-\037\177')"
wall_over=0
awk -v w="$wall" -v t="$suite_total" 'BEGIN { exit !(w + 0 >= t + 0) }' && wall_over=1

if [ -z "$offenders" ] && [ "$wall_over" -eq 0 ]; then
  slowest="$(head -n 1 "$work/ranked" | cut -f3)"
  echo "check-test-time: clean ($count files; slowest ${slowest}s of per-file budget ${per_file}s; wall ${wall}s of suite-total budget ${suite_total}s)"
  exit 0
fi

reason=""
[ -n "$offenders" ] && reason="file(s) at or over the per-file budget of ${per_file}s:$offenders"
if [ "$wall_over" -eq 1 ]; then
  [ -z "$reason" ] || reason="$reason; "
  reason="${reason}suite wall-clock ${wall}s at or over the suite-total budget of ${suite_total}s"
fi
if [ "$mode" = ci ]; then
  echo "check-test-time: FAIL: $reason" >&2
  echo "check-test-time: split or slim the file before bumping; a bump is a reviewed edit to $safe_budget with its derivation (see --help)" >&2
  exit 1
fi
echo "check-test-time: WARNING: $reason" >&2
echo "check-test-time: WARNING: this would fail in CI (GitHub Actions is the reference runner the budgets are measured on); local numbers are not the baseline, so measure there before bumping" >&2
exit 0
