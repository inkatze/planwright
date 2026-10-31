#!/usr/bin/env bash
# check-shell-mktemp-template.sh — the shell-mktemp-template rule: a `mktemp`
# given no template operand. The bare form leans on a default template that the
# BSD and older busybox mktemp do not share with GNU, so the house form names
# one: mktemp -d "${TMPDIR:-/tmp}/<name>.XXXXXX". The scanner and its escape
# hatch are scripts/shell-rule-lib.sh's.
# shellcheck disable=SC2016,SC2034 # literal awk and usage text, read by the sourced library
set -u
unset CDPATH

SR_RULE=shell-mktemp-template
SR_USAGE='check-shell-mktemp-template.sh — flag a mktemp call given no template.

Usage:
  check-shell-mktemp-template.sh [<root>]   scan scripts/, githooks/, tests/lib/
  check-shell-mktemp-template.sh --help

Flagged: mktemp as a command word with no operand other than its options
(the directory -p takes is not a template).
Fix: pass a template, mktemp -d "${TMPDIR:-/tmp}/<name>.XXXXXX".
Exempt a line with a trailing or directly preceding
  # shell-mktemp-template: <reason>
Exit codes: 0 clean, 1 an offense, 2 usage or a broken enumeration.'

SR_AWK='
function rule_reset() { }
function rule_check(code, lineno,   rest, n, k, p) {
  rest = code
  while ((p = cmdword(rest, "mktemp")) > 0) {
    n = operands(rest)
    for (k = 1; k <= n; k++) {
      # -p takes a directory, not a template.
      if (OPS[k] == "-p") { k++; continue }
      if (OPS[k] !~ /^-/) break
    }
    if (k > n) return "mktemp is given no template; name one, mktemp -d \"${TMPDIR:-/tmp}/<name>.XXXXXX\""
    rest = substr(rest, CW_END)
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
