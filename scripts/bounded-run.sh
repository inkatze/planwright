#!/bin/sh
# bounded-run.sh — run a command under a wall-clock bound, with timeout(1)'s
# exit contract, for hosts that ship neither timeout nor gtimeout (stock
# macOS). The guards fall back to it so a missing coreutils never leaves a
# read unbounded or every act refused.
#
# Usage: bounded-run.sh [-k <grace>] <seconds> <command> [<arg>...]
# Exit:  the command's own status; 124 when the bound ended it (KILL after
#        the grace included); 125 on a usage error. Bounds are whole seconds
#        without leading zeros; a 0 bound runs the command unbounded and a 0
#        grace sends no KILL, as for timeout(1).
#
# When the bound fires, TERM goes to the command and every process under it,
# read from the process table at that moment: a POSIX sh cannot give the
# command a process group of its own (dash and busybox refuse `set -m` without
# a tty). With -k, the processes of that set still running when the grace is
# spent get KILL, the command's own exit inside the grace included. A process
# of the set counts as still running only while its parent is in the set,
# init, or this runner, so a pid reissued to an unrelated process is not
# taken for it; one re-parented to a subreaper other than init is missed. A
# process that left the tree before the bound fired (it daemonized) is out of
# reach, where timeout(1)'s process group would still hold it. A signal that ends the runner is passed on the same way. The
# command's stdin is the caller's, by way of fd 9, which the command does not
# inherit.
set -u

_br_usage() {
  printf '%s\n' 'usage: bounded-run.sh [-k <grace>] <seconds> <command> [<arg>...]' >&2
  exit 125
}

_br_secs() {
  case $1 in
    0) return 0 ;;
    '' | *[!0-9]* | 0*) return 1 ;;
  esac
  [ "${#1}" -le 6 ]
}

grace=''
if [ "${1:-}" = -k ]; then
  [ "$#" -ge 2 ] || _br_usage
  grace=$2
  shift 2
  _br_secs "$grace" || _br_usage
fi
[ "$#" -ge 2 ] || _br_usage
secs=$1
shift
_br_secs "$secs" || _br_usage
[ "$secs" != 0 ] || exec "$@"
[ "$grace" != 0 ] || grace=''

# _br_tree <pid> [settled] — the pid, then every process under it, one per
# line. The pid itself is printed whatever the process table says, so a host
# without ps or awk still bounds the command. With settled, a read that finds
# nothing under the pid returns 3 while the table shows the pid running and 4
# once it shows it stopped; any other read returns 0.
_br_tree() {
  printf '%s\n' "$1"
  # stat is not a POSIX ps field, so only the settled read asks for it: a ps
  # without it still yields the tree the bound signals.
  if [ -n "${2:-}" ]; then
    ps -A -o pid= -o ppid= -o stat= 2>/dev/null
  else
    ps -A -o pid= -o ppid= 2>/dev/null
  fi | awk -v root="$1" -v settled="${2:-}" '
    { par[$1] = $2; st[$1] = $3; ids[NR] = $1 }
    END {
      keep[root] = 1
      grew = 1
      while (grew) {
        grew = 0
        for (i = 1; i <= NR; i++)
          if (!(ids[i] in keep) && (par[ids[i]] in keep)) { keep[ids[i]] = 1; grew = 1 }
      }
      kids = 0
      for (p in keep) if (p != root) { print p; kids++ }
      if (settled == "" || kids) exit 0
      if (st[root] ~ /^[RSDUIW]/) exit 3
      if (st[root] ~ /^[Tt]/) exit 4
    }'
}

_br_signal() {
  for _br_p in $2; do
    kill "-$1" "$_br_p" 2>/dev/null
  done
}

# _br_still <pids> — those of <pids> still running as members of that set:
# a row whose parent is another member, init, or this runner.
_br_still() {
  # shellcheck disable=SC2086 # the pid list is meant to split
  ps -A -o pid= -o ppid= 2>/dev/null | awk -v set=" $(printf '%s ' $1)" -v me="$$" '
    index(set, " " $1 " ") && (index(set, " " $2 " ") || $2 == 1 || $2 == me) { print $1 }'
}

# _br_term_then_kill — TERM the command's tree; with a grace, KILL what of it
# is still running once the grace is spent. The grace ends early when nothing
# of the set is left, so a tree that honours TERM costs no extra wait.
_br_term_then_kill() {
  _br_v=$(_br_tree "$pid")
  _br_signal TERM "$_br_v"
  [ -n "$grace" ] || return 0
  _br_ticks=$((grace * 10))
  while [ "$_br_ticks" -gt 0 ]; do
    [ -n "$(_br_still "$_br_v")" ] || return 0
    sleep 0.1 2>/dev/null || sleep 1
    _br_ticks=$((_br_ticks - 1))
  done
  _br_signal KILL "$(_br_still "$_br_v")"
}

# _br_drop_watcher — KILL the watcher and the sleep under it. A running
# watcher can fork its sleep between the read of its tree and the KILL, and
# that sleep then outlives the runner by the whole bound, so the watcher is
# stopped first, which ends its forking, and its tree is taken from a read
# that cannot have missed the sleep: one that shows it (the only lasting
# child a watcher forks), or one begun after an earlier read showed the
# watcher stopped. A read that itself shows the stop does not do, since a
# process table is not read in one instant. Where /proc shows the stop, a
# read of the shell's own costing no fork, the first read is begun after it.
# Both waits are capped so the runner stays bounded: past a cap, or with no
# ps, the KILL goes to what the last read showed. A runner killed outright
# between the STOP and the KILL leaves the watcher stopped, with its sleep,
# until something continues or kills it.
_br_drop_watcher() {
  kill -STOP "$dog" 2>/dev/null || return 0
  _br_stopped=''
  _br_n=0
  while [ "$_br_n" -lt 1000 ] && { read -r _br_s <"/proc/$dog/stat"; } 2>/dev/null; do
    case ${_br_s##*') '} in
      [Tt]*)
        _br_stopped=1
        break
        ;;
      [RSD]*) ;;
      *) break ;;
    esac
    _br_n=$((_br_n + 1))
  done
  _br_n=0
  while
    _br_v=$(_br_tree "$dog" settled)
    _br_rc=$?
    [ "$_br_n" -lt 100 ]
  do
    case $_br_rc in
      3) ;;
      4)
        [ -z "$_br_stopped" ] || break
        _br_stopped=1
        ;;
      *) break ;;
    esac
    _br_n=$((_br_n + 1))
  done
  _br_signal KILL "$_br_v"
}

# _br_end <status> — the runner was signalled: end the command's tree as the
# bound would, then exit with the signal's status.
# shellcheck disable=SC2329 # called from the traps below
_br_end() {
  # Ignored, not reset: a second signal that ended the runner mid-drop would
  # leave the watcher stopped for good, where a running one ends at the bound.
  trap '' TERM INT HUP QUIT
  # A fired watcher already holds the TERM-time set and is spending the grace
  # on it; anything else is ended here. Nothing more is said on stderr, where
  # a shell would report the watcher's KILL.
  exec 2>/dev/null
  if [ "$fired" = 1 ]; then
    wait "$dog"
  else
    [ -z "$dog" ] || _br_drop_watcher
    [ "$reaped" = 1 ] || [ -z "$pid" ] || _br_term_then_kill
  fi
  exit "$1"
}

pid=''
dog=''
fired=0
reaped=0
trap '_br_end 143' TERM
trap '_br_end 130' INT
trap '_br_end 129' HUP
trap '_br_end 131' QUIT
# The watcher's word that the bound fired.
trap 'fired=1' USR1

# An asynchronous command's stdin is /dev/null unless redirected, and dash
# applies that before an explicit `<&0`, so the caller's stdin goes by fd 9.
# A closed stdin is not passed on (the command gets the shell's default for an
# asynchronous command) rather than failing the runner.
if (exec 8<&0) 2>/dev/null; then
  exec 9<&0
  "$@" <&9 9<&- &
  pid=$!
  exec 9<&-
else
  "$@" <&- &
  pid=$!
fi

# The watcher sleeps the bound itself, so the command's end is seen the moment
# it happens and the bound is the full number of seconds. Its streams are
# closed, so it never keeps a caller's command substitution open. $$ is this
# runner's pid in the subshell too.
(
  trap - TERM INT HUP QUIT USR1
  sleep "$secs"
  kill -0 "$pid" 2>/dev/null || exit 0
  kill -USR1 "$$" 2>/dev/null
  _br_term_then_kill
) </dev/null >/dev/null 2>&1 &
dog=$!

# The watcher's USR1 interrupts the wait; the command is then waited for again.
wait "$pid" 2>/dev/null
rc=$?
if [ "$fired" = 1 ] && [ "$rc" -gt 128 ]; then
  wait "$pid" 2>/dev/null
fi
reaped=1
if [ "$fired" = 0 ]; then
  # KILL, which no trap can lose, to the watcher and the sleep under it, with
  # stderr closed first: the command is done, and a shell reports the KILL.
  exec 2>/dev/null
  _br_drop_watcher
fi
# A fired watcher is left to finish its grace, which is bounded.
wait "$dog" 2>/dev/null
[ "$fired" = 0 ] || exit 124
exit "$rc"
