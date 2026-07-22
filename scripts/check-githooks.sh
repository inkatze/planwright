#!/bin/sh
# check-githooks.sh — unwired/half-wired hook-backstop detection
# (guard-coverage Task 2; D-3; REQ-A1.3). DETECTS ONLY, never wires:
# auto-wiring from here would make this fail-loud path unreachable (the check
# would always see a freshly wired clone). The remedy on failure is the
# separate wire step, scripts/wire-githooks.sh.
#
# Fails when:
#   - not inside a git work tree — a check that cannot see the repo FAILS,
#     never silently skips (the CI-decidability pin: CI wires explicitly,
#     then this check inside `mise run check` verifies);
#   - core.hooksPath is unset, or is anything other than the literal
#     `githooks` the wire step writes (an absolute or re-spelled path fails
#     so drift stays loud);
#   - any of the four hook files is missing from this checkout, or present
#     but non-executable (git silently skips non-executable hooks, so a
#     half-wired clone must not pass).
#
# Usage: check-githooks.sh
# Exit: 0 fully wired; 1 unwired or half-wired; 2 usage / environment error.
#
# Portable POSIX sh; bash 3.2 / BSD tooling floor.
set -u
LC_ALL=C
export LC_ALL
unset CDPATH

if [ $# -ne 0 ]; then
  echo "usage: check-githooks.sh" >&2
  exit 2
fi

if ! top=$(git rev-parse --show-toplevel 2>/dev/null); then
  echo "check-githooks: not inside a git work tree; cannot verify hook wiring" \
    "(failing, not skipping)" >&2
  exit 2
fi

status=0
hookspath=$(git config --get core.hooksPath 2>/dev/null || true)
if [ -z "$hookspath" ]; then
  echo "check-githooks: core.hooksPath is unset or empty — the hook backstop is not wired." \
    "Remedy: scripts/wire-githooks.sh" >&2
  status=1
elif [ "$hookspath" != "githooks" ]; then
  printf "check-githooks: core.hooksPath is %s, not the tracked 'githooks'. Remedy: scripts/wire-githooks.sh\n" "'$hookspath'" >&2
  status=1
fi

for h in pre-push pre-rebase prepare-commit-msg commit-msg; do
  if [ ! -f "$top/githooks/$h" ]; then
    echo "check-githooks: githooks/$h missing from this checkout" >&2
    status=1
  elif [ ! -x "$top/githooks/$h" ]; then
    echo "check-githooks: githooks/$h is not executable (git silently skips" \
      "non-executable hooks — half-wired)" >&2
    status=1
  fi
done

if [ "$status" -eq 0 ]; then
  echo "check-githooks: fully wired (core.hooksPath=githooks; all four hooks present and executable)."
fi
exit "$status"
