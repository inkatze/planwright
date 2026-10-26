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
# ignored. A loop re-checks the fleet daemon gate before each run and skips
# the run while paused, and doubles its cadence under the budget's throttle
# rung.
#
# THE RECORD of an armed watcher is <runtime>/watchers/<slot>.rec, the slot
# derived from the duty and the script:
#   <pid><TAB><armed epoch><TAB><duty><TAB><script><TAB><cadence><TAB><cost>
# <slot>.last holds `<epoch><TAB><exit>` of its latest run. A pid is only
# trusted, or signalled, while that process's arguments still name the
# runner's loop for that slot. <slot>.log collects the loop's stderr.
#
# A PASS, in order:
#   1. the fleet daemon gate (scripts/fleet-daemon-gate.sh): paused prints
#      `paused` and arms, re-arms and sends nothing;
#   2. the budget (scripts/mc-budget.sh report, which rewrites the budget
#      file): pause-watchers stops high-cost watchers, hold-dispatch and
#      handover stop medium-cost ones too, and a watcher above its duty's
#      spend ceiling is not armed;
#   3. each watcher: running, armed, or stopped and re-armed, the stop
#      emitted as a `watcher-stopped` event before the re-arm; a record no
#      longer in the catalog's armed set is disarmed;
#   4. the snapshots (scripts/mc-snapshot.sh refresh), the wake relay and the
#      tick (scripts/mc-wake.sh relay, tick).
# One line per act: armed, rearmed, running, paused (with the rung or the
# ceiling), disarmed, stopped (with the event id), then the snapshot and wake
# scripts' own lines prefixed `snapshot` and `wake`.
#
# Usage:
#   mc-watch.sh pass --program <p>
#   mc-watch.sh run --program <p> [--once]
#       a pass every mission_control_runner_interval, until killed
#   mc-watch.sh status --program <p> [--now <epoch>]
#       watcher<TAB><duty><TAB><script><TAB><cadence><TAB><cost><TAB>running|stopped
#         <TAB><seconds since the last run|-><TAB><seconds until the next|->
#       one line per record; a next-run time already passed is negative, the
#       watcher's expiry
#   mc-watch.sh stop --program <p>
#       stop every armed watcher and drop its record
#   mc-watch.sh loop --program <p> --slot <slot>      (internal)
#
# Exit codes: 0 done; 1 a catalog, budget or store failure; 2 usage; 3 the
# program is not configured.
#
# Portable bash 3.2 / BSD tooling.
set -u
set -f
LC_ALL=C
export LC_ALL
unset CDPATH

prog=mc-watch
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

usage() {
  mc_usage_fail "usage: mc-watch.sh pass|status|stop --program <p> | run --program <p> [--once] [--now <epoch>]"
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
mc_valid_program "$program" || mc_usage_fail "invalid program name '$(sanitize_printable "$program")'"
[ -z "$now" ] || mc_valid_uint "$now" || mc_usage_fail "--now takes an epoch"
case $slot in
  *[!a-z0-9.-]*) mc_usage_fail "invalid slot" ;;
esac
mc_require_program "$program"
runtime=$(mc_runtime "$program") || mc_fail "cannot create the runtime directory for '$program'"
wdir="$runtime/watchers"
mkdir -p "$wdir" || mc_fail "cannot create the watcher directory"

slot_of() { # slot_of <duty> <script>
  printf '%s.%s\n' "$1" "$(printf '%s\t%s' "$1" "$2" | cksum | awk '{ print $1 }')"
}

# ours <pid> <slot>: the pid is this runner's loop for the slot.
ours() {
  mc_valid_uint "$1" || return 1
  kill -0 "$1" 2>/dev/null || return 1
  ou_args=$(ps -o args= -p "$1" 2>/dev/null) || return 1
  case $ou_args in
    *"mc-watch.sh loop --program $program --slot $2") return 0 ;;
  esac
  return 1
}

record_pid() { [ -f "$wdir/$1.rec" ] && cut -f1 "$wdir/$1.rec" | head -n 1; }

stop_slot() {
  ss_pid=$(record_pid "$1")
  rm -f "$wdir/$1.rec" "$wdir/$1.last"
  if [ -n "$ss_pid" ] && ours "$ss_pid" "$1"; then
    kill "$ss_pid" 2>/dev/null || :
  fi
}

arm() { # arm <slot> <duty> <script> <cadence> <cost>
  rm -f "$wdir/$1.last"
  if command -v setsid >/dev/null 2>&1; then
    setsid /bin/bash "$script_dir/mc-watch.sh" loop --program "$program" --slot "$1" \
      </dev/null >>"$wdir/$1.log" 2>&1 &
  else
    nohup /bin/bash "$script_dir/mc-watch.sh" loop --program "$program" --slot "$1" \
      </dev/null >>"$wdir/$1.log" 2>&1 &
  fi
  ar_pid=$!
  printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$ar_pid" "${now:-$(mc_now)}" "$2" "$3" "$4" "$5" \
    | mc_write "$wdir/$1.rec" || mc_fail "cannot record watcher $1"
}

cost_rank() {
  case $1 in
    low) printf '1\n' ;;
    medium) printf '2\n' ;;
    high) printf '3\n' ;;
    *) printf '9\n' ;;
  esac
}

pass() {
  if ! /bin/sh "$script_dir/fleet-daemon-gate.sh" mc-watch >/dev/null 2>&1; then
    printf 'paused\n'
    return 0
  fi
  rows=$(/bin/bash "$script_dir/mc-duties.sh" watchers --program "$program") || return 1
  budget=$(/bin/bash "$script_dir/mc-budget.sh" report --program "$program" ${now:+--now "$now"}) || return 1
  rung=$(printf '%s\n' "$budget" | awk -F '\t' '$1 == "rung" { print $2 }')
  allowed=3
  case $rung in
    pause-watchers) allowed=2 ;;
    hold-dispatch | handover) allowed=1 ;;
    paused) allowed=0 ;;
  esac
  wanted=""
  while IFS='	' read -r duty script cadence cost; do
    [ -n "$duty" ] || continue
    s=$(slot_of "$duty" "$script")
    wanted="$wanted $s"
    ceiling=$(/bin/bash "$script_dir/mc-budget.sh" ceiling --program "$program" "$duty") || return 1
    reason=""
    if [ "$(cost_rank "$cost")" -gt "$(cost_rank "$ceiling")" ]; then
      reason="above the $ceiling spend ceiling"
    elif [ "$(cost_rank "$cost")" -gt "$allowed" ]; then
      reason="budget rung $rung"
    fi
    if [ -n "$reason" ]; then
      [ ! -f "$wdir/$s.rec" ] || stop_slot "$s"
      printf 'paused\t%s\t%s\t%s\n' "$duty" "$script" "$reason"
      continue
    fi
    if [ -f "$wdir/$s.rec" ]; then
      pid=$(record_pid "$s")
      if [ -n "$pid" ] && ours "$pid" "$s"; then
        printf 'running\t%s\t%s\n' "$duty" "$script"
        continue
      fi
      id=$(/bin/bash "$script_dir/mc-event.sh" emit --program "$program" \
        watcher-stopped "$duty" "$script stopped; re-armed by the runner") || return 1
      printf 'stopped\t%s\t%s\t%s\n' "$duty" "$script" "$id"
      arm "$s" "$duty" "$script" "$cadence" "$cost"
      printf 'rearmed\t%s\t%s\n' "$duty" "$script"
    else
      arm "$s" "$duty" "$script" "$cadence" "$cost"
      printf 'armed\t%s\t%s\n' "$duty" "$script"
    fi
  done <<EOF
$rows
EOF
  set +f
  for f in "$wdir"/*.rec; do
    [ -f "$f" ] || continue
    s=${f##*/}
    s=${s%.rec}
    case " $wanted " in
      *" $s "*) ;;
      *)
        dd=$(cut -f3 "$f")
        stop_slot "$s"
        printf 'disarmed\t%s\n' "$(sanitize_printable "$dd")"
        ;;
    esac
  done
  set -f
  /bin/bash "$script_dir/mc-snapshot.sh" refresh --program "$program" ${now:+--now "$now"} | sed 's/^/snapshot	/'
  /bin/bash "$script_dir/mc-wake.sh" relay --program "$program" | sed 's/^/wake	/'
  /bin/bash "$script_dir/mc-wake.sh" tick --program "$program" ${now:+--now "$now"} | sed 's/^/wake	/'
  return 0
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
    [ "$(record_pid "$slot")" = "$$" ] || exit 0
    if /bin/sh "$script_dir/fleet-daemon-gate.sh" mc-watch >/dev/null 2>&1; then
      out=$(PLANWRIGHT_MC_PROGRAM=$program PLANWRIGHT_MC_DUTY=$duty /bin/bash "$path" </dev/null)
      rc=$?
      printf '%s\n' "$out" | while IFS='	' read -r tag kind subject text; do
        [ "$tag" = event ] || continue
        /bin/bash "$script_dir/mc-event.sh" emit --program "$program" "$kind" "$subject" ${text:+"$text"} >/dev/null
      done
      printf '%s\t%s\n' "$(mc_now)" "$rc" | mc_write "$wdir/$slot.last" 2>/dev/null || :
    fi
    factor=1
    [ ! -f "$runtime/budget" ] \
      || [ "$(awk -F '\t' '$1 == "rung" { print $2 }' "$runtime/budget")" != throttle ] || factor=2
    sleep $((secs * factor)) &
    child=$!
    wait "$child"
    child=""
  done
}

case $verb in
  pass) pass || exit 1 ;;
  run)
    interval=$(mc_knob mission_control_runner_interval mc_is_cadence) || exit 1
    secs=$(mc_seconds "$interval")
    while :; do
      pass || printf '%s\n' "$prog: the pass failed; retrying at the next interval" >&2
      [ "$once" -eq 0 ] || exit 0
      sleep "$secs"
    done
    ;;
  status)
    t=${now:-$(mc_now)}
    set +f
    for f in "$wdir"/*.rec; do
      [ -f "$f" ] || continue
      s=${f##*/}
      s=${s%.rec}
      IFS='	' read -r pid _ duty script cadence cost <"$f" || continue
      state=stopped
      ! ours "$pid" "$s" || state=running
      since=-
      next=-
      if [ -f "$wdir/$s.last" ]; then
        IFS='	' read -r at _ <"$wdir/$s.last"
        if mc_valid_uint "$at" && secs=$(mc_seconds "$cadence"); then
          since=$((t - at))
          next=$((secs - since))
        fi
      fi
      printf 'watcher\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$(sanitize_printable "$duty")" \
        "$(sanitize_printable "$script")" "$(sanitize_printable "$cadence")" \
        "$(sanitize_printable "$cost")" "$state" "$since" "$next"
    done
    ;;
  stop)
    set +f
    for f in "$wdir"/*.rec; do
      [ -f "$f" ] || continue
      s=${f##*/}
      s=${s%.rec}
      stop_slot "$s"
      printf 'stopped\t%s\n' "$s"
    done
    ;;
  loop) loop ;;
  *) usage ;;
esac
