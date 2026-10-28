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
for lib in echo-safety.sh mc-lib.sh lock-lib.sh; do
  if [ ! -r "$script_dir/$lib" ]; then
    printf '%s\n' "$prog: $lib is missing or unreadable (broken install)" >&2
    exit 2
  fi
done
# shellcheck source=scripts/echo-safety.sh
. "$script_dir/echo-safety.sh" || exit 2
# shellcheck source=scripts/mc-lib.sh
. "$script_dir/mc-lib.sh" || exit 2
# shellcheck source=scripts/lock-lib.sh
. "$script_dir/lock-lib.sh" || exit 2

help_text() {
  cat <<'HELP'
mc-keeper.sh — the session-keeper duty: track each launched session's pull
request, retire the session and reclaim its worktree once the pull request
lands, and name the next ready unit to dispatch while others wait.

Driving a session to done (answering what the record settles, relaying only
forks and operator-only blockers) is the mission-control session's
judgment; this script holds the mechanics around it.

THE LEDGER is <runtime>/keeper.tsv, "# format: 1" then one line per
tracked session:
  <session><TAB><owner/name><TAB><pr><TAB><worktree|-><TAB><stage>
the stage `-`, or `retired` once a sweep retired the session and only its
worktree is left to reclaim (so a relaunch under the same name is never
retired for the old pull request).

Usage:
  mc-keeper.sh track --program <p> --session <name> --repo <owner/name>
                     --pr <n> [--worktree <dir>]
      record the session's pull request; a later track replaces the
      session's active line, while a line already retired and waiting to
      reclaim its worktree stays until that is done
  mc-keeper.sh sweep --program <p>
      for each tracked session whose pull request is MERGED or CLOSED (one
      gh read each, bounded): retire it (scripts/mission-control-launch.sh
      retire), then reclaim its worktree (scripts/mc-reclaim.sh reclaim),
      and drop its exact line once both are done and, under the runner,
      the landing is in the event store; a line a later track replaced
      meanwhile is left alone; one line per act:
        landed<TAB><session><TAB><state>
        retired<TAB><session>                the retire just done
        reclaimed<TAB><session><TAB><worktree>
        held<TAB><session><TAB><what stayed>
        dropped<TAB><session>                the line, once nothing is left
        open<TAB><session>
        unknown<TAB><session><TAB><why>      the read failed; kept
  mc-keeper.sh next --program <p> --spec <dir> [--now <epoch>]
      the units of the spec bundle at <dir> (scripts/orchestrate-state.sh,
      run from the directory's repository) that can start now:
        dispatch<TAB><spec>:task-<id>        ready and held by no session
        waiting<TAB><spec>:task-<id><TAB>in-progress
        held<TAB><spec>:task-<id><TAB><why>  ready, but a launched session
                                             holds its scope, or the budget
                                             does not admit a session
                                             (scripts/mc-budget.sh admit,
                                             its reason after a colon)
      a unit in progress never holds back a ready one; a session holds a
      unit when the launcher lists the scope <spec>:task-<id> for this
      program
  mc-keeper.sh watch [--program <p>] [--now <epoch>]
      the duty's watcher (also what a run with no arguments does under the
      runner): the stall scan (scripts/mc-stall.sh scan, which emits its own
      events), then sweep, each landing one session-landed event in the
      program's event store, subject the session, text
      `<owner/name>#<pr> <state>, retired|held[: <what stayed>]`, printing
        announced<TAB>session-landed<TAB><session>
      once per pull request, state and outcome while it stays tracked,
      so a landing held run after run wakes the session once; the program
      from PLANWRIGHT_MC_PROGRAM when --program is absent

Exit codes: 0 done; 1 a store, a read, a retire or reclaim that failed or
is still held (a launch or retire in flight, a worktree not yet
reclaimable), or an event the store refused; 2 usage; 3 the program is not
configured.

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
now=""
while [ $# -gt 0 ]; do
  case $1 in
    --program | --session | --repo | --pr | --worktree | --spec | --now)
      [ $# -ge 2 ] || usage
      mc_valid_text "$2" || mc_usage_fail "$1 takes text with no control byte"
      case $1 in
        --program) program=$2 ;;
        --session) session=$2 ;;
        --repo) slug=$2 ;;
        --pr) pr=$2 ;;
        --worktree) worktree=$2 ;;
        --spec) spec=$2 ;;
        --now)
          mc_valid_uint "$2" || mc_usage_fail "--now takes an epoch"
          now=$2
          ;;
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
seen="$runtime/keeper-announced"

launcher() { /bin/bash "$script_dir/mission-control-launch.sh" "$@"; }

# A forge read that hangs must not stall the stall scan sharing this run.
GH_BOUND=60
gh_bounded() { /bin/sh "$script_dir/bounded-run.sh" "$GH_BOUND" gh "$@"; }

# rows: the ledger's rows, after its format line.
rows() {
  [ -f "$ledger" ] || return 0
  mc_store_ok "$ledger" || mc_fail "the ledger has a missing or unknown format: $ledger"
  awk 'NR > 1' "$ledger" || mc_fail "cannot read $ledger"
}

# row_live <row>: the exact ledger row is still there (a later track may
# have re-pointed the session).
row_live() {
  rl_rows=$(rows) || exit 1
  printf '%s\n' "$rl_rows" | R=$1 awk 'BEGIN { r = ENVIRON["R"] } $0 == r { f = 1 } END { exit !f }'
}

# The ledger has its own lock, never the fleet lock: a retire runs inside
# its critical section, and the retire's own steps take the fleet lock.
ledger_lock() {
  pw_lock_acquire "$runtime/keeper.lock" || mc_fail "cannot take the ledger lock"
}
ledger_unlock() { pw_lock_release "$runtime/keeper.lock" >/dev/null 2>&1; }

# replace_row <row> [<new row>]: put <new row> in place of that exact row,
# or drop it; the caller holds the ledger lock.
replace_row() {
  rr_rows=$(rows) || exit 1
  rr_kept=$(printf '%s\n' "$rr_rows" | R=$1 N=${2:-} awk 'BEGIN { r = ENVIRON["R"]; n = ENVIRON["N"] } $0 == r { if (n != "") print n; next } NF { print }')
  { printf '# format: 1\n' && { [ -z "$rr_kept" ] || printf '%s\n' "$rr_kept"; }; } | mc_write "$ledger" || mc_fail "cannot rewrite $ledger"
}

# say <tag> <session> [<text>]: a sweep line, or under the runner the
# session's landing as an event, once per pull request, state and outcome.
say() {
  if [ "$events" = 0 ]; then
    printf '%s\t%s%s\n' "$1" "$2" "${3:+	$3}"
    return 0
  fi
  case $1 in
    retired | held) ;;
    *) return 0 ;;
  esac
  mc_announce "$program" "$seen" "$2	$sw_r#$sw_p	$sw_state	$1" session-landed "$2" "$sw_r#$sw_p $sw_state, $1${3:+: $3}"
}

sweep() {
  sw_rc=0
  sw_rows=$(rows) || exit 1
  while IFS= read -r sw_row; do
    [ -n "$sw_row" ] || continue
    IFS='	' read -r sw_s sw_r sw_p sw_w sw_stage <<EOF
$sw_row
EOF
    sw_state=$(gh_bounded pr view "$sw_p" --repo "$sw_r" --json state --jq .state 2>/dev/null) || {
      [ "$events" = 1 ] || printf 'unknown\t%s\tthe pull request read failed\n' "$sw_s"
      sw_rc=1
      continue
    }
    case $sw_state in
      MERGED | CLOSED) ;;
      OPEN)
        say open "$sw_s"
        continue
        ;;
      *)
        [ "$events" = 1 ] || printf 'unknown\t%s\tstate %s\n' "$sw_s" "$(sanitize_printable "$sw_state")"
        sw_rc=1
        continue
        ;;
    esac
    sw_held=""
    # A session retired on an earlier sweep is not retired again: the name
    # may since belong to a relaunch of the same scope. The row is re-read,
    # the retire run and its retired stage written in one hold of the
    # ledger lock, so a track re-pointing the session meanwhile is never
    # retired for this pull request, nor drops the line still owed a
    # reclaim.
    if [ "$sw_stage" != retired ]; then
      ledger_lock
      if ! row_live "$sw_row"; then
        ledger_unlock
        continue
      fi
      say landed "$sw_s" "$sw_state"
      sw_out=$(launcher retire "$sw_s" 2>&1)
      sw_retire=$?
      case $sw_retire in
        0) ;;
        3)
          # No row means already retired, or never launched through the
          # launcher; a row still listed means a launch or retire in flight.
          if sw_list=$(launcher list 2>/dev/null); then
            if printf '%s\n' "$sw_list" | S=$sw_s awk -F '\t' '$1 == ENVIRON["S"] { f = 1 } END { exit !f }'; then
              sw_held="session ($(printf '%s' "$sw_out" | head -n 1 | mc_clean))"
            fi
          else
            sw_held="session (the launcher's list cannot be read)"
          fi
          ;;
        *) sw_held="session ($(printf '%s' "$sw_out" | head -n 1 | mc_clean))" ;;
      esac
      if [ -z "$sw_held" ]; then
        [ "$events" = 1 ] || printf 'retired\t%s\n' "$sw_s"
        sw_next="$sw_s	$sw_r	$sw_p	$sw_w	retired"
        replace_row "$sw_row" "$sw_next"
        sw_row=$sw_next
      fi
      ledger_unlock
    else
      row_live "$sw_row" || continue
      say landed "$sw_s" "$sw_state"
    fi
    # A worktree already gone needs no reclaim; any other path, even one that
    # cannot be read, goes to the reclaim, whose refusal holds the line.
    if [ -z "$sw_held" ] && [ "$sw_w" != "-" ] && { [ -e "$sw_w" ] || [ -L "$sw_w" ]; }; then
      if sw_out=$(/bin/bash "$script_dir/mc-reclaim.sh" reclaim --program "$program" "$sw_w" 2>&1); then
        [ "$events" = 1 ] || printf 'reclaimed\t%s\t%s\n' "$sw_s" "$sw_w"
      elif ! row_live "$sw_row"; then
        # Another sweep took the line and its worktree meanwhile.
        continue
      else
        sw_held="worktree ($(printf '%s' "$sw_out" | tail -n 1 | mc_clean))"
      fi
    fi
    if [ -n "$sw_held" ]; then
      say held "$sw_s" "$sw_held"
      sw_rc=1
      continue
    fi
    # The row goes only once the store holds the landing, so a refused
    # event is raised again on the next sweep.
    if [ "$events" = 0 ] || say retired "$sw_s"; then
      ledger_lock
      replace_row "$sw_row"
      ledger_unlock
      [ "$events" = 1 ] || printf 'dropped\t%s\n' "$sw_s"
    else
      sw_rc=1
    fi
  done <<EOF
$sw_rows
EOF
  # The announced set keeps only the pull requests still tracked.
  if [ "$events" = 1 ] && [ -f "$seen" ]; then
    sw_cur=$(rows) || exit 1
    sw_live=$(printf '%s\n' "$sw_cur" | awk -F '\t' 'NF { print $1 "\t" $2 "#" $3 }')
    sw_kept=$(LIVE=$sw_live awk -F '\t' 'BEGIN { n = split(ENVIRON["LIVE"], l, "\n"); for (i = 1; i <= n; i++) live[l[i]] = 1 } (($1 "\t" $2) in live)' "$seen") || return 1
    { [ -z "$sw_kept" ] || printf '%s\n' "$sw_kept"; } | mc_write "$seen" || return 1
  fi
  return "$sw_rc"
}

case $verb in
  track)
    mc_valid_handle "$session" || mc_usage_fail "--session takes a launched session's name"
    mc_valid_slug "$slug" || mc_usage_fail "--repo takes owner/name"
    mc_valid_uint "$pr" && [ "$pr" -gt 0 ] || mc_usage_fail "--pr takes a pull request number"
    case $worktree in
      - | /*) ;;
      *) mc_usage_fail "--worktree takes an absolute path" ;;
    esac
    trap pw_lock_release_all EXIT
    ledger_lock
    current=$(rows) || exit 1
    kept=$(printf '%s\n' "$current" | S=$session awk -F '\t' 'NF && ($1 != ENVIRON["S"] || $5 == "retired")')
    {
      printf '# format: 1\n'
      [ -z "$kept" ] || printf '%s\n' "$kept"
      printf '%s\t%s\t%s\t%s\t-\n' "$session" "$slug" "$pr" "$worktree"
    } | mc_write "$ledger" || mc_fail "cannot write $ledger"
    printf 'tracked\t%s\t%s#%s\n' "$session" "$slug" "$pr"
    ;;
  sweep | watch)
    rc=0
    events=0
    if [ "$verb" = watch ]; then
      events=1
      # The stall scan needs no forge, so a missing gh never stops it.
      /bin/bash "$script_dir/mc-stall.sh" scan --program "$program" ${now:+--now "$now"} >/dev/null || rc=1
    fi
    command -v gh >/dev/null 2>&1 || mc_fail "gh is not on PATH"
    trap pw_lock_release_all EXIT
    sweep || rc=1
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
    sessions=$(launcher list 2>/dev/null) || mc_fail "the launcher's sessions cannot be listed"
    held=$(printf '%s\n' "$sessions" | P=$program N=$name awk -F '\t' '$2 == ENVIRON["P"] && index($4, ENVIRON["N"] ":task-") == 1 { print $4 }')
    admit=$(/bin/bash "$script_dir/mc-budget.sh" admit --program "$program" session ${now:+--now "$now"} 2>/dev/null)
    case $? in
      0) hold="" ;;
      *)
        # A refusal names its reason on a queued line; an exit with none
        # is a budget that could not be read, which holds dispatch too.
        hold=$(printf '%s\n' "$admit" | awk -F '\t' '$1 == "queued" { print $2; exit }')
        [ -n "$hold" ] || hold="the budget cannot be read"
        ;;
    esac
    printf '%s\n' "$state" | N=$name H=$held Q=$hold awk -F '\t' '
      BEGIN { n = split(ENVIRON["H"], h, "\n"); for (i = 1; i <= n; i++) if (h[i] != "") H[h[i]] = 1 }
      $1 != "task" { next }
      {
        u = ENVIRON["N"] ":task-" $2
        if ($3 == "in-progress") print "waiting\t" u "\tin-progress"
        else if ($3 != "ready") next
        else if (u in H) print "held\t" u "\ta launched session holds it"
        else if (ENVIRON["Q"] != "") print "held\t" u "\tthe budget holds dispatch: " ENVIRON["Q"]
        else print "dispatch\t" u
      }'
    ;;
  *) usage ;;
esac
