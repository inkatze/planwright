#!/bin/sh
# bounded-run.sh — run a command under a wall-clock bound, with timeout(1)'s
# contract, for hosts that ship neither timeout nor gtimeout (stock macOS).
# The guards fall back to it so a missing coreutils never leaves a read
# unbounded or every act refused.
#
# Usage: bounded-run.sh [-k <grace>] <seconds> <command> [<arg>...]
# Exit:  the command's own status; 124 when the bound ended it; 125 on a
#        usage error. Bounds are whole seconds.
#
# When the bound fires, TERM goes to the command and every process under it,
# read from the process table at that moment: a POSIX sh cannot give the
# command a process group of its own (dash and busybox refuse `set -m` without
# a tty), and a grandchild left holding the command's output would keep a
# caller's command substitution waiting. With -k, whatever of that set is
# still running when the grace is spent gets KILL. A runner that is itself
# ended takes its command's tree with it.
set -u

usage() {
  printf '%s\n' 'usage: bounded-run.sh [-k <grace>] <seconds> <command> [<arg>...]' >&2
  exit 125
}

is_secs() {
  case $1 in
    '' | *[!0-9]*) return 1 ;;
  esac
  [ "${#1}" -le 6 ]
}

grace=''
if [ "${1:-}" = -k ]; then
  [ "$#" -ge 2 ] || usage
  grace=$2
  shift 2
  is_secs "$grace" || usage
fi
[ "$#" -ge 2 ] || usage
secs=$1
shift
is_secs "$secs" || usage

# tree <pid> — the pid and every process under it, one per line.
tree() {
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
      for (p in keep) print p
    }'
}

signal_all() {
  for sa_p in $2; do
    kill "-$1" "$sa_p" 2>/dev/null
  done
}

now() {
  date +%s
}

pid=''
trap 'trap - TERM INT HUP; [ -z "$pid" ] || signal_all TERM "$(tree "$pid")"; exit 143' TERM
trap 'trap - TERM INT HUP; [ -z "$pid" ] || signal_all TERM "$(tree "$pid")"; exit 130' INT
trap 'trap - TERM INT HUP; [ -z "$pid" ] || signal_all TERM "$(tree "$pid")"; exit 129' HUP

# The explicit redirection keeps the caller's stdin: an asynchronous command
# would otherwise get /dev/null.
"$@" <&0 &
pid=$!

deadline=$(($(now) + secs))
while kill -0 "$pid" 2>/dev/null; do
  [ "$(now)" -lt "$deadline" ] || break
  sleep 0.1 2>/dev/null || sleep 1
done
if ! kill -0 "$pid" 2>/dev/null; then
  wait "$pid"
  exit $?
fi

victims=$(tree "$pid")
signal_all TERM "$victims"
if [ -n "$grace" ]; then
  deadline=$(($(now) + grace))
  while kill -0 "$pid" 2>/dev/null && [ "$(now)" -lt "$deadline" ]; do
    sleep 0.1 2>/dev/null || sleep 1
  done
  signal_all KILL "$victims"
fi
wait "$pid" 2>/dev/null
exit 124
