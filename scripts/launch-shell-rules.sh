#!/bin/sh
# launch-shell-rules.sh — print the shell rules a worker launch appends to the
# session's system prompt (--append-system-prompt), on one line.
#
# The rules file sits beside the settings profile the launch passes, so the
# rules come from the same install as the guard that enforces them and never
# ask for a shape that install does not approve. One line, because what reads a
# launch's argv back reads it by line. A file that is missing, unreadable or
# blank prints nothing and warns on stderr: the launch goes without the rules,
# never into a refusal.
#
# Usage: launch-shell-rules.sh <settings-profile> [<who>]
# Exit: 0 (the rules, or nothing, printed); 2 usage.
#
# POSIX sh.
set -u
LC_ALL=C
export LC_ALL
unset CDPATH

me=launch-shell-rules
[ "$#" -ge 1 ] && [ "$#" -le 2 ] || {
  printf '%s\n' "usage: $me <settings-profile> [<who>]" >&2
  exit 2
}
rules_file=${1%/*}/launch-shell-rules.txt
who=${2:-the worker}
rules=''
if [ -f "$rules_file" ] && [ -r "$rules_file" ]; then
  rules=$(tr -s '\r\n' '  ' <"$rules_file") || rules=''
  rules=${rules% }
fi
case $rules in
  *[![:space:]]*) printf '%s\n' "$rules" ;;
  *) printf '%s\n' "$me: warning: $rules_file is missing, unreadable or empty; $who launches without the shell rules" >&2 ;;
esac
exit 0
