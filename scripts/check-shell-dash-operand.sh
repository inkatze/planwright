#!/usr/bin/env bash
# check-shell-dash-operand.sh — the shell-dash-operand rule: a directory or
# file primitive handed a caller-supplied positional parameter with no `--`
# before it, so a value starting with `-` is read as an option (and `cd -`
# changes to $OLDPWD). Security-sensitive: a finding routes to sign-off. The
# scanner and its escape hatch are scripts/shell-rule-lib.sh's.
# shellcheck disable=SC2016,SC2034 # literal awk and usage text, read by the sourced library
set -u
unset CDPATH

SR_RULE=shell-dash-operand
SR_USAGE='check-shell-dash-operand.sh — flag a positional operand with no -- guard.

Usage:
  check-shell-dash-operand.sh [<root>]   scan scripts/, githooks/, tests/lib/
  check-shell-dash-operand.sh --help

Flagged: cd, pushd, mkdir, rmdir, rm, touch, cp, mv, ln, chmod, chown or
mktemp as a command word with an operand that begins with a positional
parameter ($1 to $9, ${1...}, $@, $*), quoted or not, and no -- before it.
Fix: end the options first, mkdir -p -- "$1".
Exempt a line with a trailing or directly preceding
  # shell-dash-operand: <reason>
Exit codes: 0 clean, 1 an offense, 2 usage or a broken enumeration.'

SR_AWK='
function rule_reset() { }
function rule_check(code, lineno,   cmds, nc, c, rest, n, k) {
  nc = split("cd pushd mkdir rmdir rm touch cp mv ln chmod chown mktemp", cmds, " ")
  for (c = 1; c <= nc; c++) {
    rest = code
    while (cmdword(rest, cmds[c])) {
      n = operands(rest)
      for (k = 1; k <= n; k++) {
        if (OPS[k] == "--") break
        if (OPS[k] ~ /^"?\$(\{)?[1-9@*]/) return cmds[c] " takes the positional " OPS[k] " with no -- before it, so a value starting with - reads as an option"
      }
      rest = substr(rest, CW_END)
    }
  }
  return ""
}
'

self_dir=$(cd "$(dirname "$0")" && pwd -P) || exit 2
[ -r "$self_dir/shell-rule-lib.sh" ] || {
  printf '%s\n' "check-$SR_RULE: scripts/shell-rule-lib.sh is missing or unreadable" >&2
  exit 2
}
# shellcheck source=scripts/shell-rule-lib.sh
. "$self_dir/shell-rule-lib.sh"
sr_main "$@"
