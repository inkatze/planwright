#!/usr/bin/env bash
# check-shell-config-pin.sh — the shell-config-pin rule: a config-get.sh read
# that does not say which repository's overlays it reads. Unpinned, the reader
# takes the repo-tracked and machine-local layers from the working directory,
# so a script operating on a root it was handed (a fleet root, a primary
# checkout) applies whatever repository it happened to be run from. The
# scanner and its escape hatch are scripts/shell-rule-lib.sh's.
# shellcheck disable=SC2016,SC2034 # literal awk and usage text, read by the sourced library
set -u
unset CDPATH

SR_RULE=shell-config-pin
SR_USAGE='check-shell-config-pin.sh — flag a config-get.sh read not pinned to a repository.

Usage:
  check-shell-config-pin.sh [<root>]   scan scripts/, githooks/, tests/lib/
  check-shell-config-pin.sh --help

Flagged: config-get.sh run as a command, by its path or through a variable
assigned that path, with no PLANWRIGHT_REPO_ROOT= assignment and no cd on the
same line, in a file that never sets PLANWRIGHT_REPO_ROOT before it.
Fix: pin the read, PLANWRIGHT_REPO_ROOT="$root" "$config_get" <key>, or, where
the working directory is the repository by contract, say so with the
annotation.
Exempt a line with a trailing or directly preceding
  # shell-config-pin: <reason>
Exit codes: 0 clean, 1 an offense, 2 usage or a broken enumeration.'

SR_AWK='
function rule_reset() { split("", CG_VARS); pinned = 0; self = (FILE ~ /(^|\/)config-get\.sh$/) }
function pinned_line(code) { return (code ~ /PLANWRIGHT_REPO_ROOT=/ || cmdword(code, "cd")) }
# A literal config-get.sh in RAW counts only where the code view shows the
# word unmasked at a command-word position, never inside a quoted message.
function literal_call(code,   s, p, w, pre) {
  s = RAW
  while ((p = index(s, "config-get.sh")) > 0) {
    w = p
    while (w > 1 && substr(s, w - 1, 1) !~ /[ \t;&|()`]/) w--
    pre = substr(code, 1, length(RAW) - length(s) + w - 1)
    if (substr(s, w, p - w) !~ /=/ && substr(code, length(pre) + 1, 1) == substr(RAW, length(pre) + 1, 1) \
      && pre ~ /(^|[;&|({!`]|\$\()[ \t]*((if|then|do|else|elif|while|until|time|command|exec|builtin|nohup|env|!|([^ \t;&|()]*\/)?(ba)?sh)[ \t]+)*([A-Za-z_][A-Za-z0-9_]*=[^ \t]*[ \t]+)*$/) return 1
    s = substr(s, p + 13)
  }
  return 0
}
function rule_check(code, lineno,   v, m) {
  if (self) return ""
  # An export pins whatever its value holds; a plain assignment pins unless it
  # is only a prefix to the command after it.
  if (code ~ /(^|[ \t;])export[ \t]+PLANWRIGHT_REPO_ROOT([= \t;]|$)/) pinned = 1
  if (code ~ /(^|[ \t;])PLANWRIGHT_REPO_ROOT=/ && code !~ /PLANWRIGHT_REPO_ROOT=[^ \t;]*[ \t]+[^ \t;|&]/) pinned = 1
  if (match(RAW, /(^|[ \t;])[A-Za-z_][A-Za-z0-9_]*="?[^ \t"]*config-get\.sh"?[ \t]*($|;)/)) {
    m = substr(RAW, RSTART, RLENGTH)
    sub(/^[ \t;]*/, "", m); sub(/=.*/, "", m)
    CG_VARS[m] = 1
  }
  if (pinned || pinned_line(code)) return ""
  if (literal_call(code)) return "config-get.sh is read unpinned, so its overlays come from the working directory"
  for (v in CG_VARS)
    if (cmdword(code, "\\$\\{?" v "\\}?")) return "config-get.sh (through $" v ") is read unpinned, so its overlays come from the working directory"
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
