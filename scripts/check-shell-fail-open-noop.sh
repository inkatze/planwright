#!/usr/bin/env bash
# check-shell-fail-open-noop.sh — the shell-fail-open-noop rule: a command
# substitution's failure swallowed by `|| true` or `|| :`, so the variable is
# left empty and the failed read is taken as "absent" or "none" downstream. The
# scanner and its escape hatch are scripts/shell-rule-lib.sh's.
# shellcheck disable=SC2016,SC2034 # literal awk and usage text, read by the sourced library
set -u
unset CDPATH

SR_RULE=shell-fail-open-noop
SR_USAGE='check-shell-fail-open-noop.sh — flag a substitution failure swallowed by a no-op.

Usage:
  check-shell-fail-open-noop.sh [<root>]   scan scripts/, githooks/, tests/lib/
  check-shell-fail-open-noop.sh --help

Flagged: an assignment from a command substitution, name=$(...),
name="$(...)", name="text$(...)" or name=`...`, whose alternative, after any
redirections, is the no-op `|| true` or `|| :`.
Fix: handle the failure (|| die ...), or, where an empty value is the right
reading of a failed command, say why with the annotation.
Exempt a line with a trailing or directly preceding
  # shell-fail-open-noop: <reason>
Exit codes: 0 clean, 1 an offense, 2 usage or a scan covering less than it
claims (see scripts/shell-rule-lib.sh).'

SR_AWK='
function rule_reset() { }
function rule_check(code, lineno) {
  # The value may open with text before the substitution ("pre$(...)"), use
  # backticks, and carry redirections before the ||.
  if (code ~ /(^|[ \t;(])[A-Za-z_][A-Za-z0-9_]*=[^ \t;|&]*(\$\(|`).*(\)|`)"?([ \t]+(&|[0-9]*)(<<<|<>|>\||>>|<&|>&|<|>)[ \t]*[^ \t;|&]+)*[ \t]*\|\|[ \t]*(true|:)[ \t]*([;)&|]|$)/)
    return "a command substitution failure is swallowed by a no-op alternative, so an empty value reads as absent"
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
