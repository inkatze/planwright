#!/usr/bin/env bash
# mc-keeper.sh — the session-keeper duty: track each launched session's pull
# request, retire the session and reclaim its worktree once the pull request
# lands, keep workers short-lived (retire the idle, hand over the old), and
# name the next ready unit to dispatch while others wait.
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
lands, keep workers short-lived (retire the idle, hand over the old), and
name the next ready unit to dispatch while others wait.

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
      program, or for another program whose repositories include the
      spec's own, matched by git common directory (or one that cannot be
      told: no longer configured, or a row naming none)
  mc-keeper.sh bounds --program <p> [--now <epoch>]
      the worker, reviewer and ad-hoc sessions of the program a bound ends,
      one line each, read-only:
        retire<TAB><session><TAB><launched><TAB>idle <n>s, bound <b>s
        handover<TAB><session><TAB><launched><TAB>lived <n>s, bound <b>s
      idle past mission_control_worker_idle retires: a tmux session whose
      pane has sat at the prompt that long, by the stall scan's last
      sample, or a stream-json session whose last turn completed that long
      ago. Otherwise, lived past mission_control_worker_lifetime since its
      launch hands over. A session whose last line is a question (a tmux
      pane the stall scan reads idle-question, a stream-json turn whose
      final text ends in `?`) is parked on the operator and never retired
      here (without jq a stream-json one cannot be told apart, so none is
      retired), and a kickoff relay (scope kickoff-<spec>) is never bound
  mc-keeper.sh watch [--program <p>] [--now <epoch>]
      the duty's watcher (also what a run with no arguments does under the
      runner): the stall scan (scripts/mc-stall.sh scan, which emits its own
      events); the removal of every panel activation record whose session
      has no live process (scripts/mc-panel.sh prune); the pending-prompt
      sweep (scripts/fleet-streamjson.sh alarm-scan --once over every stream-json worker on the machine,
      whatever version or verb launched it, so an overdue request is a high
      queue item pushed once and a dead worker's is settled), each request
      still overdue one pending-prompt-overdue event, subject the worker,
      announced once per request (a worker the launcher records for
      another program left to that program), and a dead worker this scan
      settled one stream-json-worker-dead event, whatever its program,
      printing
        announced<TAB>pending-prompt-overdue|stream-json-worker-dead<TAB><worker>
      then the bounds, under their own lock: each retire done (re-checked
      first, a tmux pane sampled again; no tmux one on a pass whose stall
      scan failed) one worker-retired-idle event, raised again on a later
      pass when the store refused it, and
      each handover one worker-handover-due event, the handover requested
      once per launch through scripts/session-handover.sh request where it
      is installed (mission control retires the session and launches its
      successor otherwise),
      printing
        announced<TAB>worker-retired-idle|worker-handover-due<TAB><session>
      then sweep, each landing one session-landed event in the
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
  mc_usage_fail "usage: mc-keeper.sh track|sweep|next|bounds|watch --program <p> ...; mc-keeper.sh --help for each verb"
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
          # Neither a row nor a stream-json worker means already gone, or
          # never launched on a rung retire can close; a row still listed,
          # or a refusal naming an operation in flight, is one to wait out.
          case $sw_out in
            *"in flight"*) sw_held="session ($(printf '%s' "$sw_out" | head -n 1 | mc_clean))" ;;
          esac
          if [ -z "$sw_held" ]; then
            if sw_list=$(launcher list 2>/dev/null); then
              if printf '%s\n' "$sw_list" | S=$sw_s awk -F '\t' '$1 == ENVIRON["S"] { f = 1 } END { exit !f }'; then
                sw_held="session ($(printf '%s' "$sw_out" | head -n 1 | mc_clean))"
              fi
            else
              sw_held="session (the launcher's list cannot be read)"
            fi
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
    # cannot be read, goes to the reclaim, whose refusal holds the line. A
    # path is gone only when its nearest existing ancestor can be entered
    # and shows it missing.
    sw_gone=0
    case $sw_w in
      /*)
        if [ ! -e "$sw_w" ] && [ ! -L "$sw_w" ]; then
          # A dangling link stops the walk: what it points at may come back.
          sw_up=${sw_w%/*}
          while [ -n "$sw_up" ] && [ ! -e "$sw_up" ] && [ ! -L "$sw_up" ]; do sw_up=${sw_up%/*}; done
          ! (cd "${sw_up:-/}" 2>/dev/null) || sw_gone=1
        fi
        ;;
    esac
    if [ -z "$sw_held" ] && [ "$sw_w" != "-" ] && [ "$sw_gone" = 0 ]; then
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

# pending_prompts: the stream-json pending-age sweep over every worker on
# this machine, whatever planwright version or verb launched it, since one
# the launcher never registered has no other watcher once its own supervisor
# is older than the tick. The scan itself queues each overdue request high,
# pushes it once and settles a dead worker's; each request still overdue is
# then one event, announced once, and a dead worker the scan settled is one
# stream-json-worker-dead event, since its request row has just left the
# queue. An overdue prompt of a worker the launcher records for another
# program is that program's to announce; with the launcher's list unreadable
# every one is announced here, as heard twice beats never.
pending_prompts() {
  NL='
'
  pp_seen="$runtime/keeper-prompts"
  pp_out=$(/bin/sh "$script_dir/fleet-streamjson.sh" alarm-scan --once ${now:+--now "$now"} 2>/dev/null) || return 1
  if pp_list=$(launcher list 2>/dev/null); then
    keeper_list=$pp_list
  else
    pp_list=""
  fi
  pp_theirs=$(printf '%s\n' "$pp_list" | P=$program awk -F '\t' 'NF && $2 != ENVIRON["P"] { print $1 }')
  pp_live=""
  pp_rc=0
  while read -r pp_tag pp_w pp_id pp_age; do
    case $pp_tag in
      alarm | dead) ;;
      *) continue ;;
    esac
    mc_valid_handle "$pp_w" || continue
    # A settle prints its line once, to whichever scan made it, so a death is
    # announced here whatever program the worker belongs to.
    if [ "$pp_tag" = dead ]; then
      mc_announce "$program" "$pp_seen" "dead	$pp_w" stream-json-worker-dead "$pp_w" \
        "stream-json worker $pp_w has ended with $pp_id request(s) it left pending, now closed since nothing can answer them; mission-control-launch.sh retire $pp_w closes what is left" \
        || pp_rc=1
      continue
    fi
    case "$NL$pp_theirs$NL" in *"$NL$pp_w$NL"*) continue ;; esac
    pp_key="$pp_w	$pp_id"
    pp_live="$pp_live$pp_key$NL"
    mc_announce "$program" "$pp_seen" "$pp_key" pending-prompt-overdue "$pp_w" \
      "stream-json worker $pp_w has waited ${pp_age}s on request $(printf '%s' "$pp_id" | cut -c1-8); fleet-streamjson.sh pending $pp_w shows it, fleet-streamjson.sh answer $pp_w $pp_id --allow or --deny settles it" \
      || pp_rc=1
  done <<EOF
$pp_out
EOF
  mc_announce_prune "$pp_seen" "$pp_live" || pp_rc=1
  return "$pp_rc"
}

# bound_secs <knob>: the knob's cadence in seconds.
bound_secs() {
  bs_raw=$(mc_knob "$1" mc_parse_cadence) || return 1
  mc_seconds "$bs_raw"
}

# idle_since_tmux <session> <launched> <cutoff>: the epoch the session's
# pane has sat idle at its prompt since, by the stall scan's sample
# (scripts/mc-stall.sh writes <launch> <hash> <since> <state>), when that is
# at or before <cutoff>; else nothing. A sample of an earlier launch under
# the same name says nothing of this one.
idle_since_tmux() {
  it_f="$runtime/stall/$1"
  [ -f "$it_f" ] && [ ! -L "$it_f" ] || return 0
  it_launch="" it_at="" it_state=""
  IFS='	' read -r it_launch _ it_at it_state <"$it_f" || :
  [ "${it_launch%%:*}" = "$2" ] && [ "$it_state" = idle ] && mc_valid_uint "$it_at" && [ "$it_at" -le "$3" ] || return 0
  printf '%s\n' "$it_at"
}

# idle_since_streamjson <session> <launched> <cutoff>: the epoch the
# session's last turn completed at, from the rung's result record
# (scripts/fleet-streamjson.sh writes result <subtype> <epoch> <is_error>),
# when that is at or before <cutoff>; else nothing: when the session is not
# idle, the record predates this launch, or the turn ended on a question
# (its final text's last line ends in `?`, the tmux pane's rule), which
# parks it on the operator. Without jq that cannot be told, so it is never
# idle. The record is read first, so a recent turn costs no status call or
# log read.
idle_since_streamjson() {
  if [ -z "${sj_root:-}" ]; then
    sj_root=$(mc_fleet_home) || return 0
    sj_root="$sj_root/streamjson"
  fi
  is_dir="$sj_root/$1"
  [ -f "$is_dir/result" ] && [ ! -L "$is_dir/result" ] || return 0
  is_kind="" is_at=""
  IFS='	' read -r is_kind _ is_at _ <"$is_dir/result" || :
  [ "$is_kind" = result ] && mc_valid_uint "$is_at" && [ "$is_at" -ge "$2" ] && [ "$is_at" -le "$3" ] || return 0
  is_st=$(/bin/sh "$script_dir/fleet-streamjson.sh" status "$1" 2>/dev/null) || return 0
  case $is_st in "status $1 completed"*) ;; *) return 0 ;; esac
  command -v jq >/dev/null 2>&1 || return 0
  # The last result event sits near the log's end; the whole log is read
  # only when its tail holds none.
  is_ev=$(tail -c 1048576 "$is_dir/events.jsonl" 2>/dev/null | grep -F '"type":"result"' | tail -n 1)
  [ -n "$is_ev" ] || is_ev=$(grep -F '"type":"result"' "$is_dir/events.jsonl" 2>/dev/null | tail -n 1)
  [ -n "$is_ev" ] || return 0
  is_text=$(printf '%s\n' "$is_ev" | jq -r '.result // empty' 2>/dev/null) || return 0
  is_last=$(printf '%s\n' "$is_text" | awk '{ sub(/[[:space:]]+$/, "") } $0 != "" { l = $0 } END { print l }')
  case $is_last in *'?') return 0 ;; esac
  printf '%s\n' "$is_at"
}

# bounds: one retire or handover line per session a bound ends.
# Repository-changing kinds only: a tower, an orchestrator and mission
# control itself hand over through scripts/mc-handover.sh. A kickoff relay
# (scope kickoff-<spec>) waits on the operator by design and is never bound.
# A watch pass reuses the list pending_prompts read moments before.
bounds() {
  if [ -n "${keeper_list+x}" ]; then
    bd_list=$keeper_list
  else
    bd_list=$(launcher list) || {
      printf '%s\n' "$prog: the launcher's sessions cannot be listed" >&2
      return 1
    }
  fi
  bd_rows=$(printf '%s\n' "$bd_list" | P=$program awk -F '\t' '
    $2 == ENVIRON["P"] && ($3 == "worker" || $3 == "reviewer" || $3 == "ad-hoc") && index($4, "kickoff-") != 1 { print $1 "\t" $5 "\t" $6 }') || return 1
  [ -n "$bd_rows" ] || return 0
  bd_life=$(bound_secs mission_control_worker_lifetime) || return 1
  bd_idle=$(bound_secs mission_control_worker_idle) || return 1
  bd_now=${now:-$(mc_now)}
  bd_cut=$((bd_now - bd_idle))
  [ -n "${sj_root:-}" ] || sj_root="$(mc_fleet_home)/streamjson" || return 1
  while IFS='	' read -r bd_s bd_b bd_l; do
    mc_valid_handle "$bd_s" || continue
    mc_valid_uint "$bd_l" || continue
    case $bd_b in
      tmux) bd_since=$(idle_since_tmux "$bd_s" "$bd_l" "$bd_cut") ;;
      stream-json) bd_since=$(idle_since_streamjson "$bd_s" "$bd_l" "$bd_cut") ;;
      *) bd_since="" ;;
    esac
    if [ -n "$bd_since" ]; then
      printf 'retire\t%s\t%s\tidle %ss, bound %ss\n' "$bd_s" "$bd_l" $((bd_now - bd_since)) "$bd_idle"
    elif [ $((bd_now - bd_l)) -ge "$bd_life" ]; then
      printf 'handover\t%s\t%s\tlived %ss, bound %ss\n' "$bd_s" "$bd_l" $((bd_now - bd_l)) "$bd_life"
    fi
  done <<EOF
$bd_rows
EOF
}

handover_installed() { [ -r "$script_dir/session-handover.sh" ]; }

# request_handover <session> <why>: the seam to the session's own handover,
# scripts/session-handover.sh, which marks it due so the session hands over
# at its next safe point; nothing to do where it is not installed.
request_handover() {
  handover_installed || return 0
  /bin/bash "$script_dir/session-handover.sh" request --session "$1" --reason "$2" >/dev/null
}

# still_due <session> <launched> <backend> <cutoff>: the bounds' verdict
# holds now: the registry row is still the launch decided on, and the
# session is still idle since before the cutoff. A tmux pane is sampled
# again first, so input since the pass's stall scan counts.
still_due() {
  sd_row="$(mc_fleet_home)/mission-control/sessions/$1"
  [ -f "$sd_row" ] && [ ! -L "$sd_row" ] || return 1
  [ "$(mc_kv "$sd_row" launched)" = "$2" ] || return 1
  case $3 in
    tmux)
      /bin/bash "$script_dir/mc-stall.sh" classify --program "$program" ${now:+--now "$now"} "$1" >/dev/null 2>&1 || return 1
      [ -n "$(idle_since_tmux "$1" "$2" "$4")" ]
      ;;
    stream-json) [ -n "$(idle_since_streamjson "$1" "$2" "$4")" ] ;;
    *) return 1 ;;
  esac
}

# retired_event <session> <why>: emit the worker-retired-idle event.
retired_event() {
  mc_event emit --program "$program" ${now:+--now "$now"} -- worker-retired-idle "$1" \
    "$1 retired: $2; new work for it launches a fresh session with a handover brief" >/dev/null || return 1
  printf 'announced\tworker-retired-idle\t%s\n' "$1"
}

# act_bounds <scan-ok>: retire each idle session and request each handover
# once per launch, under one lock so two passes never act on one verdict
# twice. A pass whose stall scan failed retires no tmux session: its samples
# may be stale. A retire event the store refuses is owed and raised again on
# a later pass, since the session is gone from the list by then.
act_bounds() {
  ab_rc=0
  pw_lock_acquire "$runtime/keeper-bounds.lock" || {
    printf '%s\n' "$prog: cannot take the bounds lock" >&2
    return 1
  }
  ab_owed="$runtime/keeper-retired-owed"
  if [ -s "$ab_owed" ]; then
    if ab_due=$(cat "$ab_owed"); then
      ab_still=""
      while IFS='	' read -r ab_s ab_why; do
        [ -n "$ab_s" ] || continue
        retired_event "$ab_s" "$ab_why" && continue
        ab_still="$ab_still$ab_s	$ab_why
"
        ab_rc=1
      done <<EOF
$ab_due
EOF
      printf '%s' "$ab_still" | mc_write "$ab_owed" || {
        printf '%s\n' "$prog: cannot rewrite $ab_owed" >&2
        ab_rc=1
      }
    else
      ab_rc=1
    fi
  fi
  ab_seen="$runtime/keeper-bounds"
  ab_out=$(bounds) || {
    pw_lock_release "$runtime/keeper-bounds.lock" >/dev/null 2>&1
    return 1
  }
  ab_cut=0
  if [ -n "$ab_out" ]; then
    if ab_idle=$(bound_secs mission_control_worker_idle); then
      ab_cut=$((${now:-$(mc_now)} - ab_idle))
    else
      ab_rc=1
    fi
    [ -n "${sj_root:-}" ] || sj_root="$(mc_fleet_home)/streamjson" || ab_rc=1
  fi
  ab_live=""
  while IFS='	' read -r ab_tag ab_s ab_l ab_why; do
    [ -n "$ab_tag" ] || continue
    # Every row keeps its handover key, so a retire not carried out never
    # lets the same launch's handover go out again.
    ab_key="$ab_s	$ab_l"
    ab_live="$ab_live$ab_key
"
    case $ab_tag in
      retire)
        ab_b=$(mc_kv "$(mc_fleet_home)/mission-control/sessions/$ab_s" backend 2>/dev/null) || ab_b=""
        if [ "$ab_b" = tmux ] && [ "$1" != 1 ]; then
          printf '%s\n' "$prog: $ab_s is idle past its bound, left for a pass whose stall scan succeeds" >&2
          ab_rc=1
          continue
        fi
        still_due "$ab_s" "$ab_l" "$ab_b" "$ab_cut" || continue
        ab_r=$(launcher retire "$ab_s" 2>&1)
        case $? in
          0)
            retired_event "$ab_s" "$ab_why" && continue
            printf '%s\t%s\n' "$ab_s" "$ab_why" >>"$ab_owed" \
              || printf '%s\n' "$prog: the worker-retired-idle event for $ab_s was refused and cannot be owed" >&2
            ab_rc=1
            ;;
          3)
            # Gone meanwhile (retired by the landing sweep or by hand) is
            # not a failure; still listed is.
            if ! printf '%s\n' "$ab_r" | grep -q 'in flight' \
              && ab_now_list=$(launcher list 2>/dev/null) \
              && ! printf '%s\n' "$ab_now_list" | S=$ab_s awk -F '\t' '$1 == ENVIRON["S"] { f = 1 } END { exit !f }'; then
              continue
            fi
            printf '%s\n' "$prog: the idle session $ab_s was not retired: $(printf '%s\n' "$ab_r" | head -n 1 | mc_clean)" >&2
            ab_rc=1
            ;;
          *)
            ab_first=$(printf '%s\n' "$ab_r" | awk -F '\t' '$1 == "retire" { print; f = 1; exit } END { if (!f) exit 1 }') \
              || ab_first=$(printf '%s\n' "$ab_r" | head -n 1)
            printf '%s\n' "$prog: the idle session $ab_s was not fully retired: $(printf '%s' "$ab_first" | mc_clean)" >&2
            ab_rc=1
            ;;
        esac
        ;;
      handover)
        if [ -f "$ab_seen" ] && K=$ab_key awk 'BEGIN { k = ENVIRON["K"] } $0 == k { f = 1; exit } END { exit !f }' "$ab_seen"; then
          continue
        fi
        if ! request_handover "$ab_s" "$ab_why"; then
          printf '%s\n' "$prog: the handover of $ab_s could not be requested" >&2
          ab_rc=1
          continue
        fi
        if handover_installed; then
          ab_how="it hands over at its next safe point"
        else
          ab_how="retire it and launch its successor on the same worktree with a handover brief"
        fi
        if ! mc_announce "$program" "$ab_seen" "$ab_key" worker-handover-due "$ab_s" "$ab_s is past its lifetime ($ab_why); $ab_how"; then
          # A request that went out is not sent again every pass; without
          # one, the event is the only signal, so it is retried.
          if handover_installed; then
            printf '%s\n' "$ab_key" >>"$ab_seen" || :
          fi
          ab_rc=1
        fi
        ;;
    esac
  done <<EOF
$ab_out
EOF
  mc_announce_prune "$ab_seen" "$ab_live" || ab_rc=1
  pw_lock_release "$runtime/keeper-bounds.lock" >/dev/null 2>&1
  return "$ab_rc"
}

case $verb in
  bounds)
    bounds || exit 1
    ;;
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
    trap pw_lock_release_all EXIT
    if [ "$verb" = watch ]; then
      events=1
      scan_ok=1
      # The stall scan needs no forge, so a missing gh never stops it.
      /bin/bash "$script_dir/mc-stall.sh" scan --program "$program" ${now:+--now "$now"} >/dev/null || {
        rc=1
        scan_ok=0
      }
      /bin/bash "$script_dir/mc-panel.sh" prune >/dev/null || rc=1
      pending_prompts || rc=1
      act_bounds "$scan_ok" || rc=1
    fi
    command -v gh >/dev/null 2>&1 || mc_fail "gh is not on PATH"
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
    # A unit is never dispatched twice: a session of this program holds it,
    # and so does one of another program whose repositories include the
    # spec's own, compared by git common directory so a spec read from a
    # worktree matches its primary checkout. A session row naming no
    # program, or a program that no longer resolves, cannot be told apart,
    # so it holds too.
    common() { (cd -- "$1" 2>/dev/null && cd "$(git rev-parse --git-common-dir 2>/dev/null)" 2>/dev/null && pwd -P); }
    top_common=$(common "$top") || mc_fail "the git directory of the spec's repository cannot be resolved"
    others=$(printf '%s\n' "$sessions" | P=$program N=$name awk -F '\t' '$2 != ENVIRON["P"] && index($4, ENVIRON["N"] ":task-") == 1 { print ($2 == "" ? "-" : $2) }' | sort -u)
    shared=""
    while IFS= read -r op; do
      [ -n "$op" ] || continue
      theirs=""
      [ "$op" = - ] || theirs=$(/bin/bash "$script_dir/mc-program.sh" get "$op" repositories 2>/dev/null) || theirs=""
      if [ -z "$theirs" ]; then
        shared="$shared$op
"
        continue
      fi
      while IFS= read -r tr; do
        [ -n "$tr" ] || continue
        tr_common=$(common "$tr") || tr_common=""
        if [ -n "$tr_common" ] && [ "$tr_common" = "$top_common" ]; then
          shared="$shared$op
"
          break
        fi
      done <<EOF2
$theirs
EOF2
    done <<EOF
$others
EOF
    held=$(printf '%s\n' "$sessions" | P=$program S=$shared N=$name awk -F '\t' '
      BEGIN { n = split(ENVIRON["S"], s, "\n"); for (i = 1; i <= n; i++) if (s[i] != "") sh[s[i]] = 1 }
      ($2 == ENVIRON["P"] || (($2 == "" ? "-" : $2) in sh)) && index($4, ENVIRON["N"] ":task-") == 1 { print $4 }')
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
