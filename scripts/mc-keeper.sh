#!/usr/bin/env bash
# mc-keeper.sh — the session-keeper duty: track each launched session's pull
# request, retire the session and reclaim its worktree once the pull request
# lands, and name the next ready unit to dispatch while others wait.
#
# `mc-keeper.sh --help` prints the contract: verbs, outputs, exit codes.
set -u
set -f
LC_ALL=C
export LC_ALL
unset CDPATH

prog=mc-keeper
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

help_text() {
  cat <<'HELP'
mc-keeper.sh — the session-keeper duty: track each launched session's pull
request, retire the session and reclaim its worktree once the pull request
lands, and name the next ready unit to dispatch while others wait.

Driving a session to done (answering what the record settles, relaying only
forks and operator-only blockers) is the mission-control session's
judgment; this script holds the mechanics around it.

THE LEDGER is <runtime>/keeper.tsv, one line per tracked session:
  <session><TAB><owner/name><TAB><pr><TAB><worktree|->

Usage:
  mc-keeper.sh track --program <p> --session <name> --repo <owner/name>
                     --pr <n> [--worktree <dir>]
      record the session's pull request; a later track replaces it
  mc-keeper.sh sweep --program <p>
      for each tracked session whose pull request is MERGED or CLOSED (one
      gh read each): retire it (scripts/mission-control-launch.sh retire),
      then reclaim its worktree (scripts/mc-reclaim.sh reclaim), and drop
      its line once both are done; one line per act:
        landed<TAB><session><TAB><state>
        retired<TAB><session>
        reclaimed<TAB><session><TAB><worktree>
        held<TAB><session><TAB><what stayed>
        open<TAB><session>
        unknown<TAB><session><TAB><why>      the read failed; kept
  mc-keeper.sh next --program <p> --spec <dir>
      the units of the spec bundle at <dir> (scripts/orchestrate-state.sh,
      run from the directory's repository) that can start now:
        dispatch<TAB><spec>:task-<id>        ready and held by no session
        waiting<TAB><spec>:task-<id><TAB>in-progress
        held<TAB><spec>:task-<id><TAB><why>  ready, but a launched session
                                             holds its scope, or the budget
                                             holds dispatch
      a unit in progress never holds back a ready one; a session holds a
      unit when the launcher lists the scope <spec>:task-<id>
  mc-keeper.sh watch [--program <p>]
      the duty's watcher (also what a run with no arguments does under the
      runner): the stall scan (scripts/mc-stall.sh scan, which emits its own
      events), then sweep, each landing an event
        event<TAB>session-landed<TAB><session><TAB><state>, retired|held
      the program from PLANWRIGHT_MC_PROGRAM when --program is absent

Exit codes: 0 done; 1 a store, a read or a retire or reclaim that failed;
2 usage; 3 the program is not configured.

Portable bash 3.2 / BSD tooling.
HELP
}

usage() {
  mc_usage_fail "usage: mc-keeper.sh track|sweep|next|watch --program <p> ...; mc-keeper.sh --help for each verb"
}

case ${1:-} in
  --help | -h)
    help_text
    exit 0
    ;;
esac
if [ $# -eq 0 ] && [ -n "${PLANWRIGHT_MC_PROGRAM:-}" ]; then
  set -- watch
fi
[ $# -ge 1 ] || usage
verb=$1
shift
program=""
session=""
slug=""
pr=""
worktree="-"
spec=""
while [ $# -gt 0 ]; do
  case $1 in
    --program | --session | --repo | --pr | --worktree | --spec)
      [ $# -ge 2 ] || usage
      mc_valid_text "$2" || mc_usage_fail "$1 takes text with no control byte"
      case $1 in
        --program) program=$2 ;;
        --session) session=$2 ;;
        --repo) slug=$2 ;;
        --pr) pr=$2 ;;
        --worktree) worktree=$2 ;;
        --spec) spec=$2 ;;
      esac
      shift 2
      ;;
    *) usage ;;
  esac
done
[ "$verb" != watch ] || [ -n "$program" ] || program=${PLANWRIGHT_MC_PROGRAM:-}
[ -n "$program" ] || usage
mc_require_program "$program"
runtime=$(mc_runtime "$program") || mc_fail "cannot resolve the runtime directory"
ledger="$runtime/keeper.tsv"

launcher() { /bin/bash "$script_dir/mission-control-launch.sh" "$@"; }

# sweep [events]: the sweep; with `events`, an event line per landing.
sweep() {
  [ -f "$ledger" ] || return 0
  sw_rc=0
  sw_rows=$(cat "$ledger") || mc_fail "cannot read $ledger"
  while IFS='	' read -r sw_s sw_r sw_p sw_w; do
    [ -n "$sw_s" ] || continue
    sw_state=$(gh pr view "$sw_p" --repo "$sw_r" --json state --jq .state 2>/dev/null) || {
      printf 'unknown\t%s\tthe pull request read failed\n' "$sw_s"
      sw_rc=1
      continue
    }
    case $sw_state in
      MERGED | CLOSED) ;;
      OPEN)
        [ -n "${1:-}" ] || printf 'open\t%s\n' "$sw_s"
        continue
        ;;
      *)
        printf 'unknown\t%s\tstate %s\n' "$sw_s" "$(sanitize_printable "$sw_state")"
        sw_rc=1
        continue
        ;;
    esac
    [ -n "${1:-}" ] || printf 'landed\t%s\t%s\n' "$sw_s" "$sw_state"
    sw_held=""
    sw_out=$(launcher retire "$sw_s" 2>&1)
    case $? in
      0) [ -n "${1:-}" ] || printf 'retired\t%s\n' "$sw_s" ;;
      3)
        # No row: already retired, or never launched through the launcher.
        if ! launcher list 2>/dev/null | S=$sw_s awk -F '\t' '$1 == ENVIRON["S"] { f = 1 } END { exit !f }'; then
          [ -n "${1:-}" ] || printf 'retired\t%s\n' "$sw_s"
        else
          sw_held="session ($(printf '%s' "$sw_out" | head -n 1 | mc_clean))"
        fi
        ;;
      *) sw_held="session ($(printf '%s' "$sw_out" | head -n 1 | mc_clean))" ;;
    esac
    if [ -z "$sw_held" ] && [ "$sw_w" != "-" ]; then
      if [ -d "$sw_w" ]; then
        if sw_out=$(/bin/bash "$script_dir/mc-reclaim.sh" reclaim --program "$program" "$sw_w" 2>&1); then
          [ -n "${1:-}" ] || printf 'reclaimed\t%s\t%s\n' "$sw_s" "$sw_w"
        else
          sw_held="worktree ($(printf '%s' "$sw_out" | tail -n 1 | mc_clean))"
        fi
      fi
    fi
    if [ -n "$sw_held" ]; then
      if [ -n "${1:-}" ]; then
        printf 'event\tsession-landed\t%s\t%s, held: %s\n' "$sw_s" "$sw_state" "$sw_held"
      else
        printf 'held\t%s\t%s\n' "$sw_s" "$sw_held"
      fi
      sw_rc=1
      continue
    fi
    [ -z "${1:-}" ] || printf 'event\tsession-landed\t%s\t%s, retired\n' "$sw_s" "$sw_state"
    mc_lock || mc_fail "cannot take the fleet lock"
    S=$sw_s awk -F '\t' '$1 != ENVIRON["S"]' "$ledger" | mc_write "$ledger" || {
      mc_unlock
      mc_fail "cannot rewrite $ledger"
    }
    mc_unlock
  done <<EOF
$sw_rows
EOF
  return "$sw_rc"
}

case $verb in
  track)
    mc_valid_handle "$session" || mc_usage_fail "--session takes a launched session's name"
    case $slug in */?* | ?*/*) ;; *) mc_usage_fail "--repo takes owner/name" ;; esac
    case $slug in *[!A-Za-z0-9._/-]* | */*/* | .* | */.*) mc_usage_fail "--repo takes owner/name" ;; esac
    mc_valid_uint "$pr" && [ "$pr" -gt 0 ] || mc_usage_fail "--pr takes a pull request number"
    case $worktree in
      -) ;;
      /*) case $worktree in *'	'*) mc_usage_fail "--worktree takes no tab" ;; esac ;;
      *) mc_usage_fail "--worktree takes an absolute path" ;;
    esac
    mc_lock || mc_fail "cannot take the fleet lock"
    trap mc_unlock EXIT
    {
      [ ! -f "$ledger" ] || S=$session awk -F '\t' '$1 != ENVIRON["S"]' "$ledger"
      printf '%s\t%s\t%s\t%s\n' "$session" "$slug" "$pr" "$worktree"
    } | mc_write "$ledger" || mc_fail "cannot write $ledger"
    printf 'tracked\t%s\t%s#%s\n' "$session" "$slug" "$pr"
    ;;
  sweep | watch)
    command -v gh >/dev/null 2>&1 || mc_fail "gh is not on PATH"
    rc=0
    if [ "$verb" = watch ]; then
      /bin/bash "$script_dir/mc-stall.sh" scan --program "$program" >/dev/null || rc=1
    fi
    trap mc_unlock EXIT
    if [ "$verb" = watch ]; then sweep events || rc=1; else sweep || rc=1; fi
    exit "$rc"
    ;;
  next)
    [ -n "$spec" ] && [ -d "$spec" ] || mc_usage_fail "--spec takes a spec bundle directory"
    top=$(git -C "$spec" rev-parse --show-toplevel 2>/dev/null) || mc_fail "the spec bundle is not in a repository"
    abs=$(cd "$spec" && pwd -P) || mc_fail "cannot resolve the spec bundle"
    top=$(cd "$top" && pwd -P) || mc_fail "cannot resolve the repository"
    rel=${abs#"$top"/}
    name=${abs##*/}
    mc_valid_kebab "$name" || mc_fail "the spec bundle's name is outside the identifier grammar"
    state=$(cd "$top" && /bin/bash "$script_dir/orchestrate-state.sh" "$rel" 2>/dev/null) || mc_fail "the unit states of $name cannot be derived"
    held=$(launcher list 2>/dev/null | N=$name awk -F '\t' 'index($4, ENVIRON["N"] ":task-") == 1 { print $4 }') || held=""
    rung=$(/bin/bash "$script_dir/mc-budget.sh" rung --program "$program" 2>/dev/null) || rung=unknown
    printf '%s\n' "$state" | N=$name H=$held R=$rung awk -F '\t' '
      BEGIN { n = split(ENVIRON["H"], h, "\n"); for (i = 1; i <= n; i++) if (h[i] != "") H[h[i]] = 1 }
      $1 != "task" { next }
      {
        u = ENVIRON["N"] ":task-" $2
        if ($3 == "in-progress") print "waiting\t" u "\tin-progress"
        else if ($3 != "ready") next
        else if (u in H) print "held\t" u "\ta launched session holds it"
        else if (ENVIRON["R"] == "hold-dispatch" || ENVIRON["R"] == "handover" || ENVIRON["R"] == "unknown") print "held\t" u "\tthe budget holds dispatch (" ENVIRON["R"] ")"
        else print "dispatch\t" u
      }'
    ;;
  *) usage ;;
esac
