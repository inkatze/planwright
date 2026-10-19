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
# taken for it. A process that left the tree before the bound fired (it
# daemonized) is out of reach, where timeout(1)'s process group would still
# hold it. A signal that ends the runner is passed on the same way. The
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

# _br_tree <pid> — the pid, then every process under it, one per line. The
# pid itself is printed whatever the process table says, so a host without ps
# or awk still bounds the command.
_br_tree() {
  printf '%s\n' "$1"
  ps -A -o pid= -o ppid= 2>/dev/null | awk -v root="$1" '
    { par[$1] = $2; ids[NR] = $1 }
    END {
      keep[root] = 1
      grew = 1
      while (grew) {
        grew = 0
        for (i = 1; i <= NR; i++)
          if (!(ids[i] in keep) && (par[ids[i]] in keep)) { keep[ids[i]] = 1; grew = 1 }
      }
      for (p in keep) if (p != root) print p
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
# is still running once the grace is spent.
_br_term_then_kill() {
  _br_v=$(_br_tree "$pid")
  _br_signal TERM "$_br_v"
  if [ -n "$grace" ]; then
    sleep "$grace"
    _br_signal KILL "$(_br_still "$_br_v")"
  fi
}

# _br_end <status> — the runner was signalled: end the command's tree as the
# bound would, then exit with the signal's status.
# shellcheck disable=SC2329 # called from the traps below
_br_end() {
  trap - TERM INT HUP QUIT
  [ -z "$dog" ] || _br_signal KILL "$(_br_tree "$dog")"
  [ -z "$pid" ] || _br_term_then_kill
  exit "$1"
}

pid=''
dog=''
fired=0
trap '_br_end 143' TERM
trap '_br_end 130' INT
trap '_br_end 129' HUP
trap '_br_end 131' QUIT
# The watcher's word that the bound fired.
trap 'fired=1' USR1

# An asynchronous command's stdin is /dev/null unless redirected, and dash
# applies that before an explicit `<&0`, so the caller's stdin goes by fd 9.
# A closed stdin stays closed to the command rather than failing the runner.
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
if [ "$fired" = 0 ]; then
  # KILL, which no trap can lose, to the watcher and the sleep under it.
  _br_signal KILL "$(_br_tree "$dog")"
fi
# A fired watcher is left to finish its grace, which is bounded.
wait "$dog" 2>/dev/null
[ "$fired" = 0 ] || exit 124
exit "$rc"
