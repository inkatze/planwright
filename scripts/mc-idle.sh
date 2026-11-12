#!/usr/bin/env bash
# mc-idle.sh — the idle-capacity duty: when a worker slot is free and the
# program's declared backlog holds a unit, raise an event the holder acts on.
# It launches nothing itself.
#
# `mc-idle.sh --help` prints the contract: verbs, outputs, exit codes.
set -u
set -f
LC_ALL=C
export LC_ALL
unset CDPATH

prog=mc-idle
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
mc-idle.sh — the idle-capacity duty: a free worker slot beside work that
waits is the gap no event-driven duty sees, so each wake this compares the
program's live workers with the launch bounds and, when a slot is free and
its declared backlog holds a unit, raises an event the holder must act on:
launch the unit, or drive the owning supervisor with the named units. It
changes nothing it reads and never launches.

THE SLOTS: the free ones are the smaller of
  fleet_host_max_live_workers less the live sessions of every program in
  the shared registry, and
  fleet_max_parallel_units less the program's own,
mission-control sessions counted in neither (the launcher's own count;
`off` leaves a bound open).

THE GATES are the launcher's: the usage hold, a fleet pause and host load
at the throttle threshold, read as scripts/mc-budget.sh admit heavy reads
them. Any closed gate raises nothing.

THE BACKLOG is the file mission_control_idle_backlog names (`off`: none), an
absolute path of ranked units, one per line, the first the next to run;
blank lines and lines starting with # are skipped; a unit is its id
(letters, digits and . _ : @ = -, at most 64 characters, else the line is
skipped), then an optional note after a tab or space; at most five ids are
named. It is read only when a slot is free and the gates are open. With none
declared, or one that cannot be read, the duty says so once, as an
idle-capacity-undeclared event, and raises nothing until a backlog reads
again; it never guesses a backlog.

Usage:
  mc-idle.sh check --program <p> [--now <epoch>] [--load <pct>]
      print the verdict and change nothing:
        slots<TAB><free><TAB><host live>/<host bound><TAB><program live>/<program bound>
        raise<TAB><n><TAB><unit> [<unit>...]   or   quiet<TAB><reason>
      the reasons: no-free-slot, no-backlog, undeclared, or the gate's
      (queued, then what mc-budget.sh admit printed)
  mc-idle.sh watch [--program <p>] [--now <epoch>] [--load <pct>]
      the duty's watcher (also a run with no arguments under the runner,
      the program from PLANWRIGHT_MC_PROGRAM): the check, then an
      idle-capacity event whose text names up to one unit per free slot,
      raised again only when the units change or
      mission_control_idle_interval has passed, and forgotten once the
      program is no longer idle, so it is raised afresh if it returns;
      prints the check's lines, then raised or held. --load stands in for
      the measured host load percent.

Exit codes: 0 done; 1 an invalid knob, an unresolvable fleet home or
runtime directory, a registry that cannot be read, or an event the store
refused; 2 usage; 3 the program is not configured.

Portable bash 3.2 / BSD tooling.
HELP
}

usage() {
  mc_usage_fail "usage: mc-idle.sh check|watch --program <p> [--now <epoch>] [--load <pct>]; mc-idle.sh --help"
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
case $verb in
  check | watch) ;;
  *) usage ;;
esac
program="" now="" load=""
while [ $# -gt 0 ]; do
  case $1 in
    --program | --now | --load)
      [ $# -ge 2 ] || usage
      mc_valid_text "$2" || mc_usage_fail "$1 takes text with no control byte"
      case $1 in
        --program) program=$2 ;;
        --now) now=$2 ;;
        --load) load=$2 ;;
      esac
      shift 2
      ;;
    *) usage ;;
  esac
done
[ "$verb" != watch ] || [ -n "$program" ] || program=${PLANWRIGHT_MC_PROGRAM:-}
[ -n "$program" ] || usage
[ -z "$load" ] || mc_valid_uint "$load" || mc_usage_fail "--load takes a whole percent"
mc_now_arg "$now"
mc_require_program "$program"

FLEET=$(mc_fleet_home) || mc_fail "cannot resolve the fleet home"
RUNTIME=$(mc_runtime "$program") || mc_fail "cannot create the runtime directory of program $program"

# bound <key>: the knob as a number, or `off` for an open bound.
bound() {
  b=$(/bin/sh "$script_dir/resolve-config-knob.sh" --key "$1" --type threshold --no-degrade </dev/null 2>/dev/null) \
    || mc_fail "$1 cannot be resolved to a number or off"
  printf '%s\n' "$b"
}

parse_backlog() { # an absolute path, or off
  case $1 in
    off) printf 'off\n' ;;
    /*) printf '%s\n' "$1" ;;
    *) return 1 ;;
  esac
}

# live_counts: "<host live><TAB><program live>" from the registry rows the
# launcher counts: every non-mission-control session of every program, and
# this program's own.
live_counts() {
  reg="$FLEET/mission-control/sessions"
  [ -d "$reg" ] || {
    printf '0\t0\n'
    return 0
  }
  [ -r "$reg" ] && [ -x "$reg" ] || mc_fail "cannot read the registry $(sanitize_printable "$reg")"
  set +f
  set -- "$reg"/mc-*
  set -f
  lc_host=0
  lc_own=0
  for f in "$@"; do
    [ -f "$f" ] && [ ! -L "$f" ] || continue
    case ${f##*/} in *.tmp.*) continue ;; esac
    [ "$(mc_kv "$f" format)" = 1 ] || continue
    [ "$(mc_kv "$f" kind)" != mission-control ] || continue
    lc_host=$((lc_host + 1))
    [ "$(mc_kv "$f" program)" != "$program" ] || lc_own=$((lc_own + 1))
  done
  printf '%s\t%s\n' "$lc_host" "$lc_own"
}

# free_of <bound> <live>: the slots left under a bound, a large number when
# the bound is open.
free_of() {
  if [ "$1" = off ]; then
    printf '1000000\n'
  elif [ "$2" -ge "$1" ]; then
    printf '0\n'
  else
    printf '%s\n' $(($1 - $2))
  fi
}

# check: the verdict lines into VERDICT, the units to raise into UNITS (empty
# unless raising), REASON the quiet reason, FREE the free slot count.
check() {
  host_bound=$(bound fleet_host_max_live_workers)
  prog_bound=$(bound fleet_max_parallel_units)
  counts=$(live_counts)
  host_live=${counts%%	*}
  prog_live=${counts#*	}
  hf=$(free_of "$host_bound" "$host_live")
  pf=$(free_of "$prog_bound" "$prog_live")
  FREE=$hf
  [ "$pf" -ge "$FREE" ] || FREE=$pf
  VERDICT=$(printf 'slots\t%s\t%s/%s\t%s/%s\n' "$FREE" "$host_live" "$host_bound" "$prog_live" "$prog_bound")
  UNITS=""
  REASON=""
  BACKLOG_READ=0
  if [ "$FREE" -le 0 ]; then
    REASON=no-free-slot
    return 0
  fi
  if ! gate=$(/bin/bash "$script_dir/mc-budget.sh" admit --program "$program" heavy --now "$NOW" ${load:+--load "$load"} 2>&1); then
    REASON="queued: $(printf '%s' "$gate" | tr '\t\n' '  ')"
    return 0
  fi
  backlog=$(mc_knob mission_control_idle_backlog parse_backlog) || exit 1
  if [ "$backlog" = off ] || [ ! -f "$backlog" ] || [ ! -r "$backlog" ]; then
    REASON=undeclared
    UNDECLARED_WHY=$backlog
    return 0
  fi
  BACKLOG_READ=1
  # At most MAX_UNITS ids, each short, keep the event text inside its bound.
  UNITS=$(awk -v n="$FREE" -v max="$MAX_UNITS" '
    /^[[:space:]]*(#|$)/ { next }
    { u = $1; if (u ~ /^[A-Za-z0-9][A-Za-z0-9._:@=-]*$/ && length(u) <= 64) { print u; if (++c >= n || c >= max) exit } }' "$backlog")
  [ -n "$UNITS" ] || REASON=no-backlog
}

emit() { # emit <kind> <subject> <text>
  mc_event emit --program "$program" --now "$NOW" -- "$1" "$2" "$3" >/dev/null || mc_fail "the $1 event was refused"
}

UNDECLARED_WHY=""
BACKLOG_READ=0
MAX_UNITS=5
check
printf '%s\n' "$VERDICT"
if [ -n "$UNITS" ]; then
  line=$(printf '%s' "$UNITS" | tr '\n' ' ')
  printf 'raise\t%s\t%s\n' "$(printf '%s\n' "$UNITS" | awk 'END { print NR }')" "${line% }"
else
  printf 'quiet\t%s\n' "$REASON"
fi
[ "$verb" = watch ] || exit 0

interval=$(mc_knob mission_control_idle_interval mc_parse_cadence) || exit 1
interval=$(mc_seconds "$interval") || exit 1
raised="$RUNTIME/idle-raised"
undeclared="$RUNTIME/idle-undeclared"

if [ "$REASON" = undeclared ]; then
  if [ ! -e "$undeclared" ]; then
    case $UNDECLARED_WHY in
      off) why="no backlog is declared (mission_control_idle_backlog is off)" ;;
      *) why="the declared backlog cannot be read (mission_control_idle_backlog)" ;;
    esac
    emit idle-capacity-undeclared idle-capacity-backlog "Free worker slots cannot be matched to work: $why. Declare a file of ranked units."
    printf '%s\n' "$NOW" | mc_write "$undeclared" || mc_fail "cannot write $undeclared"
    printf 'raised\tundeclared\n'
  else
    printf 'held\tundeclared\n'
  fi
  rm -f "$raised"
  exit 0
fi
# A backlog that reads again is reported afresh if it is lost once more.
[ "$BACKLOG_READ" != 1 ] || rm -f "$undeclared"

if [ -z "$UNITS" ]; then
  rm -f "$raised"
  exit 0
fi
sig=$(printf '%s' "$UNITS" | tr '\n' ',')
if [ -f "$raised" ]; then
  at=$(head -n 1 "$raised")
  was=$(sed -n 2p "$raised")
  if mc_valid_uint "$at" && [ "$at" -le "$NOW" ] && [ "$was" = "$sig" ] && [ $((NOW - at)) -lt "$interval" ]; then
    printf 'held\t%s\n' "$sig"
    exit 0
  fi
fi
text="Worker slots are free and the backlog waits: launch, or drive the owning supervisor with ${sig%,}"
emit idle-capacity idle-capacity "$(printf '%s' "$text" | cut -c1-500)"
printf '%s\n%s\n' "$NOW" "$sig" | mc_write "$raised" || mc_fail "cannot write $raised"
printf 'raised\t%s\n' "${sig%,}"
