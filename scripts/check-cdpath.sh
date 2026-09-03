#!/usr/bin/env bash
# check-cdpath.sh — CDPATH house-pattern guard.
#
# A shell script that resolves its own paths with `dir="$(cd .. && pwd)"` is
# silently wrong under a user CDPATH: when `cd` finds the directory through a
# CDPATH entry it prints the resolved path, and that echo lands inside the
# command substitution, so the variable ends up holding two lines. The fix is
# one line, `unset CDPATH` at the top of the script, and the whole cost of the
# bug is that nobody remembers to write it.
#
# Vigilance had already failed here before this guard existed, and the
# harness's own environment hides the failure: with CDPATH unset globally, an
# offending script passes every local and CI run and only breaks on the
# machine of whoever has it set.
#
# Enumeration is by shebang rather than by *.sh extension, because the
# githooks/ hooks are extensionless and were the files most likely to be
# missed.
#
# Usage:
#   check-cdpath.sh [<root>]   scan <root>/{scripts,tests,githooks}
#                              (default root: the repo this script lives in)
#   check-cdpath.sh --help
#
# Exit codes: 0 clean, 1 an offending file, 2 usage or a broken enumeration
# (a missing root, a missing scope directory, or a scan that reached no
# shebang-bearing file — never reported as clean).
#
# Portable bash 3.2 / BSD tooling; no fish/mise/tmux/Ansible.
set -u

LC_ALL=C
export LC_ALL

unset CDPATH

SCOPE_DIRS="scripts tests githooks"

# A command substitution whose first command is `cd`, in either the $(...) or
# the backtick form.
CD_SUBST='(\$\(|`)[[:space:]]*cd[[:space:]]'

# A top-level `unset` naming CDPATH, alone or among other names.
UNSET_CDPATH='^unset[[:space:]]+([A-Za-z_][A-Za-z0-9_]*[[:space:]]+)*CDPATH([[:space:]]|$)'

usage() {
  cat <<'EOF'
check-cdpath.sh — flag scripts that resolve paths through a cd command
substitution without a top-level `unset CDPATH`.

Usage:
  check-cdpath.sh [<root>]   scan <root>/{scripts,tests,githooks}
                             (default root: the repo this script lives in)
  check-cdpath.sh --help

Files are enumerated by shebang, not by extension, so the extensionless
githooks/ hooks are covered.

Exit codes: 0 clean, 1 an offending file, 2 usage or a broken enumeration.

Fixing a flagged file: add `unset CDPATH` at the top level of the script,
before anything resolves a path.

Regression-test convention: a script that resolves paths this way gets one
test that runs it under `CDPATH=.` and asserts the resolved path is still
correct. Testing under the ambient environment proves nothing, because the
harness unsets CDPATH globally and that unset masks exactly the bug this
guard exists to catch. `CDPATH=.` is the smallest setting that reproduces it:
it makes `cd` echo for any directory reachable from the current one.
EOF
}

case "${1:-}" in
  --help | -h)
    usage
    exit 0
    ;;
esac

if [ "$#" -gt 1 ]; then
  echo "check-cdpath: too many arguments (expected at most one root)" >&2
  exit 2
fi

if [ "$#" -eq 1 ]; then
  root="$1"
else
  root="$(cd "$(dirname "$0")/.." && pwd -P)"
fi

if [ ! -d "$root" ]; then
  echo "check-cdpath: root not found or not a directory: $root" >&2
  exit 2
fi

scan_dirs=""
missing=""
for dir in $SCOPE_DIRS; do
  if [ -d "$root/$dir" ]; then
    scan_dirs="$scan_dirs $root/$dir"
  else
    missing="$missing $dir"
  fi
done
if [ -n "$missing" ]; then
  echo "check-cdpath: scope directories missing under $root:$missing — the scan would silently cover less than it claims" >&2
  exit 2
fi

status=0
scanned=0

# shellcheck disable=SC2086 # scan_dirs is a deliberate word-split path list
while IFS= read -r file; do
  first=""
  IFS= read -r first <"$file" || true
  case "$first" in
    '#!'*) ;;
    *) continue ;;
  esac
  scanned=$((scanned + 1))
  grep -v '^[[:space:]]*#' "$file" | grep -Eq "$CD_SUBST" || continue
  grep -Eq "$UNSET_CDPATH" "$file" && continue
  echo "check-cdpath: ${file#"$root"/} resolves a path through a cd command substitution but has no top-level 'unset CDPATH'" >&2
  status=1
done <<EOF
$(find $scan_dirs -type f -print | sort)
EOF

if [ "$scanned" -eq 0 ]; then
  echo "check-cdpath: no shebang-bearing files found under $SCOPE_DIRS in $root — a broken enumeration, not a clean tree" >&2
  exit 2
fi

if [ "$status" -eq 0 ]; then
  echo "check-cdpath: clean ($scanned files)"
fi
exit "$status"
