#!/usr/bin/env bash
# check-shell-gnu-only-flag.sh — the shell-gnu-only-flag rule: a command
# option GNU userland has and the BSD (macOS) or busybox one does not, on a
# support bar that includes both. The scanner and its escape hatch are
# scripts/shell-rule-lib.sh's; a site that falls back to the portable form on
# the same line (stat -c ... || stat -f ...) says so with the annotation.
# shellcheck disable=SC2016,SC2034 # literal awk and usage text, read by the sourced library
set -u
unset CDPATH

SR_RULE=shell-gnu-only-flag
SR_USAGE='check-shell-gnu-only-flag.sh — flag GNU-only command options.

Usage:
  check-shell-gnu-only-flag.sh [<root>]   scan scripts/, githooks/, tests/lib/
  check-shell-gnu-only-flag.sh --help

Flagged, as a command word with the option before any -- operand:
  timeout (any use)          readlink -f         date -d, --date
  stat -c, --format, --printf                    grep -P, --perl-regexp
  xargs -r, --no-run-if-empty                    sort -V, --version-sort
  sed -i with no attached suffix, --in-place     find -printf
Combined short flags count (grep -oP). sed -i.bak is portable and passes.
Exempt a line with a trailing or directly preceding
  # shell-gnu-only-flag: <reason>
Exit codes: 0 clean, 1 an offense, 2 usage or a broken enumeration.'

SR_AWK='
function rule_reset() { }
function gnu_flag(cmd, w) {
  if (cmd == "readlink") return (w ~ /^-[A-Za-z]*f[A-Za-z]*$/)
  if (cmd == "date") return (w ~ /^-[A-Za-z]*d/ || w ~ /^--date/)
  if (cmd == "stat") return (w ~ /^-[A-Za-z]*c/ || w ~ /^--(format|printf)/)
  if (cmd == "grep") return (w ~ /^-[A-Za-z]*P/ || w == "--perl-regexp")
  if (cmd == "xargs") return (w ~ /^-[A-Za-z]*r[A-Za-z]*$/ || w == "--no-run-if-empty")
  if (cmd == "sort") return (w ~ /^-[A-Za-z]*V[A-Za-z]*$/ || w == "--version-sort")
  if (cmd == "sed") return (w ~ /^-[A-Za-z]*i$/ || w ~ /^--in-place/)
  if (cmd == "find") return (w == "-printf")
  return 0
}
function rule_check(code, lineno,   cmds, nc, c, rest, n, k) {
  if (cmdword(code, "timeout")) return "timeout is GNU coreutils only; bound the wait in the shell instead"
  nc = split("readlink date stat grep xargs sort sed find", cmds, " ")
  for (c = 1; c <= nc; c++) {
    rest = code
    while (cmdword(rest, cmds[c])) {
      n = operands(rest)
      for (k = 1; k <= n; k++) {
        if (OPS[k] == "--") break
        if (cmds[c] != "find" && OPS[k] !~ /^-/) continue
        if (gnu_flag(cmds[c], OPS[k])) return cmds[c] " " OPS[k] " is GNU-only; use the portable form or annotate the fallback"
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
