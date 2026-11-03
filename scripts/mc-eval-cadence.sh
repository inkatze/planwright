#!/usr/bin/env bash
# mc-eval-cadence.sh — mission control's behavioral eval cadence: run the eval
# suite on demand, record its outcome per head, and refuse a ready flip of a
# gated unit whose head has a red record or none.
#
# `mc-eval-cadence.sh --help` prints the contract: verbs, outputs, exit codes.
set -u
set -f
LC_ALL=C
export LC_ALL
unset CDPATH

prog=mc-eval-cadence
script_dir=$(cd "$(dirname "$0")" && pwd) || exit 2
for lib in echo-safety.sh mc-lib.sh; do
  if [ ! -r "$script_dir/$lib" ]; then
    printf '%s\n' "$prog: $lib is missing or unreadable (broken install)" >&2
    exit 2
  fi
done
# shellcheck source=scripts/echo-safety.sh
. "$script_dir/echo-safety.sh" || exit 2
# shellcheck source=scripts/mc-lib.sh
. "$script_dir/mc-lib.sh" || exit 2

root=$(cd "$script_dir/.." && pwd) || exit 2
default_fixture="$root/tests/behavioral-evals/fixtures/mission-control"
default_test_spec="$root/specs/mission-control/test-spec.md"

help_text() {
  cat <<'HELP'
mc-eval-cadence.sh — mission control's behavioral eval cadence: run the eval
suite on demand, record its outcome per head, and refuse a ready flip of a
gated unit whose head has a red record or none.

The suite is the mission-control fixture under tests/behavioral-evals/fixtures,
one persona per [Gherkin] arm of specs/mission-control/test-spec.md, run by
scripts/behavioral-eval.sh. It runs on demand only, never in CI.

THE GATED SPECS are listed one per line in the fixture's `gated-specs` file:
mission control itself and each of its follow-on bundles. A unit of any other
spec is not gated.

THE LEDGER, one tab-separated line per run, appended:
  <utc time><TAB><head><TAB><spec><TAB>pass|fail<TAB><detail>
It defaults to planwright/mc-eval-cadence.tsv under the repository's git
common directory, so every worktree of the repository shares it and it is
never tracked. The latest line for a head is that head's record.

VERBS
  complete [--test-spec <file>] [--fixture <dir>]
      The suite's completeness check: every [Gherkin] arm (a test-spec entry
      whose tag names Gherkin) has exactly one persona in the fixture's
      `personas` list naming it in an `arm=` line, and every listed persona
      names one such arm. Prints one line per gap:
        missing<TAB><arm>               no persona for the arm
        duplicate<TAB><arm>             more than one persona for the arm
        orphan<TAB><persona><TAB><why>  a persona with no file, no arm, or
                                        an arm that is not a [Gherkin] entry
  run [--worktree <dir>] [--spec <name>] [--ledger <file>]
      The completeness check, then the suite on the worktree's head (default
      the current directory); appends the ledger line and prints it. A run
      the harness could not carry out (no tmux or jq, a broken fixture)
      appends nothing.
  step [--ledger <file>]
      The pre-ready-flip cadence step. Reads PLANWRIGHT_STEP_SPEC and
      PLANWRIGHT_STEP_WORKTREE (default the current directory). An ungated
      spec passes. A gated one passes on a green record for the head, fails
      on a red one (a finding to read; re-run on demand), and with no record
      runs the suite once and follows its result.
  inventory [--ledger <file>] [--worktree <dir>] [--live <names>]
      The manual sweep's row: the run count, the heads covered, the latest
      record, and every head run more than once (a flaky suite's signal).
      With --live (space-separated spec names), prints nothing unless one of
      them is gated.
  gated <spec>
      Exit 0 when the spec is gated, 1 when it is not.

EXIT
  0  complete / passed / printed / gated
  1  incomplete / a red or missing record, or a failed run / not gated
  2  usage, an invalid name, or an unreadable input
  3  the suite could not run (no record written)
HELP
}

ledger=""
worktree=""
spec=""
test_spec="$default_test_spec"
fixture="$default_fixture"
live=""
live_set=0

valid_spec() {
  [ "${#1}" -le 64 ] || return 1
  [ "$1" != flight ] || return 1
  case $1 in
    "" | [!a-z0-9]* | *[!a-z0-9-]*) return 1 ;;
  esac
}

resolve_worktree() {
  [ -n "$worktree" ] || worktree=$(pwd -P)
  [ -d "$worktree" ] || mc_usage_fail "no such worktree: $(sanitize_printable "$worktree")"
}

resolve_ledger() {
  [ -n "$ledger" ] && return 0
  resolve_worktree
  _common=$(git -C "$worktree" rev-parse --git-common-dir 2>/dev/null) \
    || mc_usage_fail "not a git checkout: $(sanitize_printable "$worktree")"
  case $_common in
    /*) ;;
    *) _common="$worktree/$_common" ;;
  esac
  ledger="$_common/planwright/mc-eval-cadence.tsv"
}

head_of() {
  git -C "$worktree" rev-parse --verify -q HEAD 2>/dev/null | awk '/^[0-9a-f]{40}([0-9a-f]{24})?$/ { print; ok = 1 } END { exit !ok }'
}

gated_list() {
  _gf="$fixture/gated-specs"
  [ -r "$_gf" ] || mc_usage_fail "the gated-specs list is missing or unreadable: $(sanitize_printable "$_gf")"
  sed -e 's/#.*//' -e 's/[[:space:]]//g' "$_gf" | awk 'NF'
}

is_gated() {
  gated_list | grep -qxF -- "$1"
}

# latest_record <head> — the ledger's latest well-formed line for the head.
latest_record() {
  [ -f "$ledger" ] || return 0
  awk -F '\t' -v h="$1" 'NF >= 4 && $2 == h && ($4 == "pass" || $4 == "fail") { last = $0 } END { if (last != "") print last }' "$ledger"
}

do_complete() {
  [ -r "$test_spec" ] || mc_usage_fail "the test spec is missing or unreadable: $(sanitize_printable "$test_spec")"
  [ -r "$fixture/fixture.conf" ] || mc_usage_fail "the fixture is missing or unreadable: $(sanitize_printable "$fixture")"
  _arms=$(awk '
    { sub(/\r$/, "") }
    /^```/ { fence = !fence; next }
    fence { next }
    /^### REQ-[A-Z][0-9]+\.[0-9]+ / && /\[[^][]*Gherkin[^][]*\]$/ { print $2 }
  ' "$test_spec")
  _personas=$(awk -F '=' '$1 == "personas" { sub(/^[^=]*=/, ""); print; exit }' "$fixture/fixture.conf")
  _gaps=""
  _named=""
  for _p in $_personas; do
    case $_p in
      "" | *[!a-z0-9-]*)
        _gaps="${_gaps}orphan	$(sanitize_printable "$_p")	not a persona name
"
        continue
        ;;
    esac
    _pf="$fixture/personas/$_p.persona"
    if [ ! -r "$_pf" ]; then
      _gaps="${_gaps}orphan	$_p	no persona file
"
      continue
    fi
    _arm=$(awk -F '=' '$1 == "arm" { print $2; exit }' "$_pf")
    if [ -z "$_arm" ]; then
      _gaps="${_gaps}orphan	$_p	names no arm
"
      continue
    fi
    if ! printf '%s\n' "$_arms" | grep -qxF -- "$_arm"; then
      _gaps="${_gaps}orphan	$_p	names $(sanitize_printable "$_arm"), not a [Gherkin] arm
"
      continue
    fi
    _named="$_named$_arm
"
  done
  for _a in $_arms; do
    _n=$(printf '%s' "$_named" | grep -cxF -- "$_a")
    if [ "$_n" -eq 0 ]; then
      _gaps="${_gaps}missing	$_a
"
    elif [ "$_n" -gt 1 ]; then
      _gaps="${_gaps}duplicate	$_a
"
    fi
  done
  [ -n "$_arms" ] || _gaps="${_gaps}missing	(no [Gherkin] arm found in the test spec)
"
  if [ -n "$_gaps" ]; then
    printf '%s' "$_gaps"
    return 1
  fi
  return 0
}

append_record() {
  # append_record <head> <outcome> <detail>
  _dir=$(dirname "$ledger")
  mkdir -p "$_dir" 2>/dev/null || mc_usage_fail "cannot create the ledger directory: $(sanitize_printable "$_dir")"
  _line=$(printf '%s\t%s\t%s\t%s\t%s' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$1" "$spec" "$2" "$3")
  printf '%s\n' "$_line" >>"$ledger" || mc_usage_fail "cannot append to the ledger: $(sanitize_printable "$ledger")"
  printf '%s\n' "$(sanitize_printable "$(printf "%s" "$_line" | tr "\t" " ")")"
}

do_run() {
  resolve_worktree
  resolve_ledger
  [ -n "$spec" ] || spec=mission-control
  valid_spec "$spec" || mc_usage_fail "invalid spec name"
  _head=$(head_of) || mc_usage_fail "cannot read the head of $(sanitize_printable "$worktree")"
  if ! _gaps=$(do_complete); then
    printf '%s\n' "$_gaps" | while IFS= read -r _g; do
      [ -n "$_g" ] && printf '%s\n' "$prog: incomplete: $(sanitize_printable "$_g")" >&2
    done
    append_record "$_head" fail "incomplete: a [Gherkin] arm has no fixture"
    return 1
  fi
  _rec=$(mktemp -d "${TMPDIR:-/tmp}/mc-eval-cadence.XXXXXX") || mc_usage_fail "cannot create a scratch directory"
  /bin/sh "$script_dir/behavioral-eval.sh" --record "$_rec" "$fixture" >"$_rec/harness.log" 2>&1
  _rc=$?
  _want=$(awk -F '=' '$1 == "personas" { sub(/^[^=]*=/, ""); print; exit }' "$fixture/fixture.conf" | wc -w | tr -d ' ')
  _passed=0
  set +f
  for _r in "$_rec"/*.json; do
    [ -f "$_r" ] || continue
    [ "$(jq -r '.structural_pass' "$_r" 2>/dev/null)" = true ] && _passed=$((_passed + 1))
  done
  set -f
  case $_rc in
    0 | 1) ;;
    *)
      printf '%s\n' "$prog: the suite could not run (harness exit $_rc); no record written" >&2
      tail -n 20 "$_rec/harness.log" | while IFS= read -r _l; do printf '%s\n' "  $(sanitize_printable "$_l")" >&2; done
      rm -rf -- "$_rec"
      return 3
      ;;
  esac
  rm -rf -- "$_rec"
  if [ "$_rc" -eq 0 ] && [ "$_passed" -eq "$_want" ]; then
    append_record "$_head" pass "$_passed of $_want arms green"
    return 0
  fi
  append_record "$_head" fail "$_passed of $_want arms green (harness exit $_rc)"
  return 1
}

do_step() {
  worktree="${PLANWRIGHT_STEP_WORKTREE:-}"
  spec="${PLANWRIGHT_STEP_SPEC:-}"
  if [ -z "$spec" ]; then
    printf '%s\n' "not gated: the unit names no spec"
    return 0
  fi
  valid_spec "$spec" || mc_usage_fail "invalid PLANWRIGHT_STEP_SPEC"
  if ! is_gated "$spec"; then
    printf '%s\n' "not gated: $spec"
    return 0
  fi
  resolve_worktree
  resolve_ledger
  _head=$(head_of) || mc_usage_fail "cannot read the head of $(sanitize_printable "$worktree")"
  _last=$(latest_record "$_head")
  if [ -z "$_last" ]; then
    printf '%s\n' "no eval record on ${_head%"${_head#????????????}"}; running the suite"
    do_run
    _rc=$?
    [ "$_rc" -eq 3 ] && printf '%s\n' "missing eval record on ${_head%"${_head#????????????}"}: the ready flip waits for a green run (mc-eval-cadence.sh run)" >&2
    [ "$_rc" -eq 0 ] && return 0
    return 1
  fi
  case $(printf '%s' "$_last" | cut -f4) in
    pass)
      printf '%s\n' "green eval record on ${_head%"${_head#????????????}"}: $(sanitize_printable "$(printf "%s" "$_last" | tr "\t" " ")")"
      return 0
      ;;
  esac
  printf '%s\n' "red eval record on ${_head%"${_head#????????????}"}: $(sanitize_printable "$(printf "%s" "$_last" | tr "\t" " ")")" >&2
  printf '%s\n' "read the failing arms, fix, and re-run on demand (mc-eval-cadence.sh run)" >&2
  return 1
}

do_inventory() {
  if [ "$live_set" -eq 1 ]; then
    _any=0
    for _s in $live; do
      valid_spec "$_s" && is_gated "$_s" && _any=1
    done
    [ "$_any" -eq 1 ] || return 0
  fi
  resolve_ledger
  if [ ! -s "$ledger" ]; then
    printf '%s\n' "eval cadence: no runs recorded"
    return 0
  fi
  awk -F '\t' '
    NF >= 4 && $2 ~ /^[0-9a-f]+$/ && ($4 == "pass" || $4 == "fail") {
      n++
      if (!($2 in runs)) { heads++; order[heads] = $2 }
      runs[$2]++
      last = substr($2, 1, 12) " " $4 " at " $1
    }
    END {
      if (n == 0) { print "eval cadence: no runs recorded"; exit }
      printf "eval cadence: %d runs over %d heads; latest %s\n", n, heads, last
      for (i = 1; i <= heads; i++) if (runs[order[i]] > 1) printf "  %s: %d runs on one head\n", substr(order[i], 1, 12), runs[order[i]]
    }' "$ledger" | while IFS= read -r _l; do printf '%s\n' "$(sanitize_printable "$_l")"; done
}

verb="${1:-}"
[ $# -gt 0 ] && shift
case $verb in
  -h | --help | help)
    help_text
    exit 0
    ;;
  complete | run | step | inventory | gated) ;;
  "") mc_usage_fail "a verb is required (complete, run, step, inventory, gated); see --help" ;;
  *) mc_usage_fail "unknown verb: $(sanitize_printable "$verb")" ;;
esac

if [ "$verb" = gated ]; then
  [ $# -eq 1 ] || mc_usage_fail "gated takes one spec name"
  valid_spec "$1" || mc_usage_fail "invalid spec name"
  is_gated "$1"
  exit $?
fi

while [ $# -gt 0 ]; do
  case $1 in
    --ledger | --worktree | --spec | --test-spec | --fixture | --live)
      [ $# -ge 2 ] || mc_usage_fail "$1 needs a value"
      case $1 in
        --ledger) ledger=$2 ;;
        --worktree) worktree=$2 ;;
        --spec) spec=$2 ;;
        --test-spec) test_spec=$2 ;;
        --fixture) fixture=$2 ;;
        --live)
          live=$2
          live_set=1
          ;;
      esac
      shift 2
      ;;
    *) mc_usage_fail "unknown argument: $(sanitize_printable "$1")" ;;
  esac
done

case $verb in
  complete)
    do_complete
    exit $?
    ;;
  run)
    do_run
    exit $?
    ;;
  step)
    do_step
    exit $?
    ;;
  inventory)
    do_inventory
    exit $?
    ;;
esac
