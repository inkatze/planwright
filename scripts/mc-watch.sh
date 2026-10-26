#!/usr/bin/env bash
# mc-watch.sh — mission control's watcher runner: the daemon that arms every
# enabled duty's watchers at their cadence, re-arms one that stopped (the
# stop itself an event), keeps the source snapshots and the budget file
# current, and drives the wake relay and the failsafe tick. Every step is a
# script; none calls a model.
#
# A WATCHER is a catalog entry's script (scripts/mc-duties.sh watchers: the
# armed duties' <id>, <script>, <cadence>, <cost>), resolved against the
# planwright root and then the program's repositories. Armed, it runs in its
# own detached loop process (`mc-watch.sh loop`), once per cadence, with
# PLANWRIGHT_MC_PROGRAM and PLANWRIGHT_MC_DUTY set; each stdout line of the
# form
#   event<TAB><kind><TAB><subject>[<TAB><text>]
# becomes an event (scripts/mc-event.sh emit) and every other line is
# ignored; a line the event store refuses is counted, not dropped silently.
# A loop re-checks the fleet daemon gate before each run and skips the run
# while the gate is closed, doubles its cadence at any budget rung above
# normal, and exits once its record is gone. Stopping a loop stops the
# watcher run it is waiting on.
#
# THE RECORD of an armed watcher is <runtime>/watchers/<slot>.rec, the slot
# derived from the duty and the script:
#   <pid><TAB><armed epoch><TAB><duty><TAB><script><TAB><cadence><TAB><cost>
# <slot>.last holds `<epoch><TAB><exit><TAB><refused events>` of its latest
# run and <slot>.log the loop's stderr. A pid is only trusted, or signalled,
# while that process's whole argument list is this runner's loop for that
# slot.
#
# A PASS holds the program's runner lock (<runtime>/runner.lock, through
# scripts/lock-lib.sh), so two runners never interleave, and in order:
#   1. the fleet daemon gate (scripts/fleet-daemon-gate.sh): paused prints
#      `paused` (`blocked<TAB><exit>` for a broken gate) and arms, re-arms
#      and sends nothing;
#   2. the budget (scripts/mc-budget.sh report, which rewrites the budget
#      file): pause-watchers stops high-cost watchers, hold-dispatch and
#      handover stop medium-cost ones too, and a watcher above its duty's
#      spend class is not armed;
#   3. each watcher: running, armed, or stopped and re-armed, the stop
#      emitted as a `watcher-stopped` event before the re-arm; a script that
#      does not resolve, or a cadence that does not parse, is reported
#      unresolvable and neither armed nor evented; a record no longer in the
#      catalog's armed set is disarmed;
#   4. old events pruned (scripts/mc-event.sh prune), the snapshots
#      (scripts/mc-snapshot.sh refresh), the wake relay and the tick
#      (scripts/mc-wake.sh relay, tick).
# One line per act: armed, rearmed, running, paused (with the rung or the
# spend class), unresolvable, disarmed, stopped (with the event id), then the
# event, snapshot and wake scripts' own lines prefixed `event`, `snapshot`
# and `wake`. A pass whose lock another runner holds prints `busy`.
#
# Usage:
#   mc-watch.sh pass --program <p> [--now <epoch>]
#   mc-watch.sh run --program <p> [--once]
#       hold the runner lock and make a pass every
#       mission_control_runner_interval until killed; --once makes one pass
#       and exits. A failed pass is reported and retried at the next
#       interval.
#   mc-watch.sh status --program <p> [--now <epoch>]
#       watcher<TAB><duty><TAB><script><TAB><cadence><TAB><cost><TAB>running|stopped
#         <TAB><seconds since the last run|-><TAB><seconds until the next|->
#         <TAB><last exit|-><TAB><events refused in the last run|->
#       one line per record; a next-run time already passed is negative, the
#       watcher's expiry
#   mc-watch.sh stop --program <p>
#       stop every armed watcher and drop its record, printing
#       disarmed<TAB><duty> per watcher; a live runner arms them again at
#       its next pass, so stop the runner first
#   mc-watch.sh loop --program <p> --slot <slot>      (internal)
#
# Exit codes: 0 done; 1 a catalog, budget or store failure, or a snapshot or
# wake step that failed; 2 usage; 3 the program is not configured.
#
# Portable bash 3.2 / BSD tooling.
set -u
set -f
LC_ALL=C
export LC_ALL
unset CDPATH

prog=mc-watch
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

usage() {
  mc_usage_fail "usage: mc-watch.sh pass|status --program <p> [--now <epoch>] | run --program <p> [--once] | stop --program <p>"
}

[ $# -ge 1 ] || usage
verb=$1
shift
program=""
slot=""
now=""
once=0
while [ $# -gt 0 ]; do
  case $1 in
    --program | --slot | --now)
      [ $# -ge 2 ] || usage
      case $1 in
        --program) program=$2 ;;
        --slot) slot=$2 ;;
        --now) now=$2 ;;
      esac
      shift 2
      ;;
    --once)
      once=1
      shift
      ;;
    *) usage ;;
  esac
done
[ -n "$program" ] || usage
[ -z "$now" ] || mc_valid_uint "$now" || mc_usage_fail "--now takes an epoch"
case $slot in
  *[!a-z0-9.-]*) mc_usage_fail "invalid slot" ;;
esac
mc_require_program "$program"
PLANWRIGHT_MC_CHECKED=$program
export PLANWRIGHT_MC_CHECKED
runtime=$(mc_runtime "$program") || mc_fail "cannot create the runtime directory for '$program'"
wdir="$runtime/watchers"
mkdir -p "$wdir" || mc_fail "cannot create the watcher directory"
now_args=()
[ -z "$now" ] || now_args=(--now "$now")

slot_of() { # slot_of <duty> <script>
  printf '%s.%s\n' "$1" "$(printf '%s\t%s' "$1" "$2" | cksum | awk '{ print $1 }')"
}

# slots: the slot of every record, one per line.
slots() {
  set +f
  for sl_f in "$wdir"/*.rec; do
    [ -f "$sl_f" ] || continue
    sl_s=${sl_f##*/}
    printf '%s\n' "${sl_s%.rec}"
  done
  set -f
}

# ours <pid> <slot>: 0 the pid is this runner's loop for the slot, 1 it is
# not, 2 the process table could not be read for a live pid.
ours() {
  mc_valid_uint "$1" || return 1
  kill -0 "$1" 2>/dev/null || return 1
  # BSD ps cuts an argument list to the terminal's width without -ww.
  ou_args=$(ps -ww -o args= -p "$1" 2>/dev/null) || ou_args=$(ps -o args= -p "$1" 2>/dev/null) || return 2
  [ "$ou_args" = "/bin/bash $script_dir/mc-watch.sh loop --program $program --slot $2" ]
}

record_pid() { [ -f "$wdir/$1.rec" ] && cut -f1 "$wdir/$1.rec" | head -n 1; }

stop_slot() {
  ss_pid=$(record_pid "$1")
  rm -f "$wdir/$1.rec" "$wdir/$1.last"
  if [ -n "$ss_pid" ] && ours "$ss_pid" "$1"; then
    kill "$ss_pid" 2>/dev/null || :
  fi
}

# arm <slot> <duty> <script> <cadence> <cost>: start the loop and record it.
arm() {
  rm -f "$wdir/$1.last"
  if command -v setsid >/dev/null 2>&1; then
    ar_detach=(setsid)
  else
    ar_detach=(nohup)
  fi
  "${ar_detach[@]}" /bin/bash "$script_dir/mc-watch.sh" loop --program "$program" --slot "$1" \
    </dev/null >>"$wdir/$1.log" 2>&1 &
  ar_pid=$!
  printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$ar_pid" "${now:-$(mc_now)}" "$2" "$3" "$4" "$5" \
    | mc_write "$wdir/$1.rec" || {
    kill "$ar_pid" 2>/dev/null
    printf '%s\n' "$prog: cannot record watcher $1" >&2
    return 1
  }
}

# step <prefix> <command...>: run a sub-step, its lines prefixed, its exit
# status kept.
step() {
  st_prefix=$1
  shift
  st_out=$("$@")
  st_rc=$?
  [ -z "$st_out" ] || printf '%s\n' "$st_out" | sed "s/^/$st_prefix	/"
  return "$st_rc"
}

pass() {
  if ! mc_gate mc-watch; then
    if [ "$MC_GATE_RC" -eq 1 ]; then
      printf 'paused\n'
      return 0
    fi
    printf 'blocked\t%s\n' "$MC_GATE_RC"
    return 1
  fi
  rows=$(/bin/bash "$script_dir/mc-duties.sh" watchers --program "$program") || return 1
  budget=$(/bin/bash "$script_dir/mc-budget.sh" report --program "$program" ${now_args[@]+"${now_args[@]}"}) || return 1
  rung=$(printf '%s\n' "$budget" | awk -F '\t' '$1 == "rung" { print $2 }')
  ceiling=$(printf '%s\n' "$budget" | awk -F '\t' '$1 == "spend" && $2 == "ceiling" { print $3 }')
  allowed=3
  case $rung in
    pause-watchers) allowed=2 ;;
    hold-dispatch | handover) allowed=1 ;;
  esac
  wanted=""
  status=0
  while IFS='	' read -r duty script cadence cost; do
    [ -n "$duty" ] || continue
    s=$(slot_of "$duty" "$script")
    wanted="$wanted $s"
    own=$(printf '%s\n' "$budget" | D=$duty awk -F '\t' '$1 == "spend" && $2 == ENVIRON["D"] { print $3 }')
    class=${own:-$ceiling}
    reason=""
    if [ "$(mc_cost_rank "$cost")" -gt "$(mc_cost_rank "$class")" ]; then
      reason="above the $class spend class"
    elif [ "$(mc_cost_rank "$cost")" -gt "$allowed" ]; then
      reason="budget rung $rung"
    fi
    if [ -n "$reason" ]; then
      [ ! -f "$wdir/$s.rec" ] || stop_slot "$s"
      printf 'paused\t%s\t%s\t%s\n' "$duty" "$script" "$reason"
      continue
    fi
    if [ -f "$wdir/$s.rec" ]; then
      pid=$(record_pid "$s")
      ours "$pid" "$s"
      case $? in
        0)
          printf 'running\t%s\t%s\n' "$duty" "$script"
          continue
          ;;
        2)
          printf 'running\t%s\t%s\tunverified\n' "$duty" "$script"
          continue
          ;;
      esac
    fi
    if ! mc_resolve_script "$script" "$program" >/dev/null || ! mc_seconds "$cadence" >/dev/null; then
      [ ! -f "$wdir/$s.rec" ] || stop_slot "$s"
      printf 'unresolvable\t%s\t%s\n' "$duty" "$script"
      status=1
      continue
    fi
    if [ -f "$wdir/$s.rec" ]; then
      id=$(mc_event emit --program "$program" -- \
        watcher-stopped "$duty" "$script stopped; re-armed by the runner") || return 1
      printf 'stopped\t%s\t%s\t%s\n' "$duty" "$script" "$id"
      arm "$s" "$duty" "$script" "$cadence" "$cost" || return 1
      printf 'rearmed\t%s\t%s\n' "$duty" "$script"
    else
      arm "$s" "$duty" "$script" "$cadence" "$cost" || return 1
      printf 'armed\t%s\t%s\n' "$duty" "$script"
    fi
  done <<EOF
$rows
EOF
  for s in $(slots); do
    case " $wanted " in
      *" $s "*) ;;
      *)
        dd=$(cut -f3 "$wdir/$s.rec")
        stop_slot "$s"
        printf 'disarmed\t%s\n' "$(sanitize_printable "$dd")"
        ;;
    esac
  done
  step event mc_event prune --program "$program" ${now_args[@]+"${now_args[@]}"} || status=1
  step snapshot /bin/bash "$script_dir/mc-snapshot.sh" refresh --program "$program" \
    --rung "$rung" ${now_args[@]+"${now_args[@]}"} || status=1
  step wake /bin/bash "$script_dir/mc-wake.sh" relay --program "$program" || status=1
  step wake /bin/bash "$script_dir/mc-wake.sh" tick --program "$program" ${now_args[@]+"${now_args[@]}"} || status=1
  return "$status"
}

runner_sleep=""
runner_exit() {
  [ -z "$runner_sleep" ] || kill "$runner_sleep" 2>/dev/null
  pw_lock_release_all
  exit "$1"
}
take_runner_lock() {
  trap 'pw_lock_release_all' EXIT
  trap 'runner_exit 130' INT
  trap 'runner_exit 143' TERM
  trap 'runner_exit 129' HUP
  pw_lock_try "$runtime/runner.lock"
  case $? in
    0) return 0 ;;
    1)
      printf 'busy\n'
      exit 0
      ;;
  esac
  mc_fail "cannot take the runner lock"
}

loop() {
  # The runner records this process's pid just after starting it.
  tries=0
  until [ "$(record_pid "$slot")" = "$$" ]; do
    tries=$((tries + 1))
    [ "$tries" -le 50 ] || exit 0
    sleep 0.1 2>/dev/null || sleep 1
  done
  IFS='	' read -r _ _ duty script cadence _ <"$wdir/$slot.rec" || exit 1
  secs=$(mc_seconds "$cadence") || exit 1
  path=$(mc_resolve_script "$script" "$program") || {
    printf '%s\n' "$prog: watcher script '$script' not found" >&2
    exit 1
  }
  child=""
  trap '[ -z "$child" ] || kill "$child" 2>/dev/null; exit 0' TERM INT HUP
  while :; do
    [ -d "$wdir" ] && [ "$(record_pid "$slot")" = "$$" ] || exit 0
    if mc_gate mc-watch; then
      out=$(mktemp "$wdir/.$slot.out.XXXXXX") || exit 1
      # Run in the background and waited for, so a TERM stops this run too.
      PLANWRIGHT_MC_PROGRAM=$program PLANWRIGHT_MC_DUTY=$duty /bin/bash "$path" </dev/null >"$out" &
      child=$!
      wait "$child"
      rc=$?
      child=""
      refused=0
      while IFS='	' read -r tag kind subject text; do
        [ "$tag" = event ] || continue
        text=${text%"$(printf '\r')"}
        subject=${subject%"$(printf '\r')"}
        if ! mc_event emit --program "$program" -- "$kind" "$subject" ${text:+"$text"} >/dev/null; then
          refused=$((refused + 1))
        fi
      done <"$out"
      rm -f "$out"
      printf '%s\t%s\t%s\n' "$(mc_now)" "$rc" "$refused" | mc_write "$wdir/$slot.last" 2>/dev/null || :
    fi
    lp_rung=$(mc_file_rung "$runtime/budget") || lp_rung=normal
    sleep $((secs * $(mc_cadence_factor "$lp_rung"))) &
    child=$!
    wait "$child"
    child=""
  done
}

case $verb in
  pass)
    take_runner_lock
    pass || exit 1
    ;;
  run)
    interval=$(mc_knob mission_control_runner_interval mc_parse_cadence) || exit 1
    secs=$(mc_seconds "$interval")
    take_runner_lock
    while :; do
      # A subshell, so a failure that exits inside the pass ends the pass,
      # not the daemon.
      (pass) || printf '%s\n' "$prog: the pass failed; retrying at the next interval" >&2
      [ "$once" -eq 0 ] || exit 0
      # Waited for in the background, so a TERM is handled at once.
      sleep "$secs" &
      runner_sleep=$!
      wait "$runner_sleep"
      runner_sleep=""
    done
    ;;
  status)
    mc_now_arg "$now"
    for s in $(slots); do
      IFS='	' read -r pid _ duty script cadence cost <"$wdir/$s.rec" || continue
      state=stopped
      ! ours "$pid" "$s" || state=running
      since=-
      next=-
      last_rc=-
      last_refused=-
      if [ -f "$wdir/$s.last" ]; then
        IFS='	' read -r at last_rc last_refused <"$wdir/$s.last"
        if mc_valid_uint "$at" && cad=$(mc_seconds "$cadence"); then
          since=$((NOW - at))
          next=$((cad - since))
        fi
      fi
      printf 'watcher\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$(sanitize_printable "$duty")" \
        "$(sanitize_printable "$script")" "$(sanitize_printable "$cadence")" \
        "$(sanitize_printable "$cost")" "$state" "$since" "$next" \
        "$(sanitize_printable "${last_rc:--}" -)" "$(sanitize_printable "${last_refused:--}" -)"
    done
    ;;
  stop)
    for s in $(slots); do
      dd=$(cut -f3 "$wdir/$s.rec")
      stop_slot "$s"
      printf 'disarmed\t%s\n' "$(sanitize_printable "$dd")"
    done
    ;;
  loop) loop ;;
  *) usage ;;
esac
