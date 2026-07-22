#!/bin/sh
# wire-githooks.sh — the dedicated idempotent wire step for the hook backstop
# (guard-coverage Task 2; D-3; REQ-A1.3). Sets `core.hooksPath githooks` so
# git runs the tracked githooks/ hooks. Run once per clone: core.hooksPath is
# clone-global, so one wiring covers every worktree of the clone (documented
# blast radius; the hooks no-op cleanly on a checkout whose branch lacks the
# githooks/ files). CI runs this as an explicit step before `mise run check`
# (wire-then-verify, D-3).
#
# Deliberately NOT install.sh (the ~/.claude writer, which by its own
# invariant never edits a clone's git config) and deliberately separate from
# the detection check (scripts/check-githooks.sh), which only detects and
# never wires — auto-wiring from the check would make its fail-loud path
# unreachable.
#
# The relative value `githooks` resolves against each worktree's top level at
# hook-run time, which is exactly the tracked dir on branches that carry it.
#
# Usage: wire-githooks.sh   (from anywhere inside the clone)
# Exit: 0 wired (or already wired); 2 usage error / not a git repo / config
#   write failure.
#
# Portable POSIX sh; bash 3.2 / BSD tooling floor.
set -u
LC_ALL=C
export LC_ALL
unset CDPATH

if [ $# -ne 0 ]; then
  echo "usage: wire-githooks.sh" >&2
  exit 2
fi

if ! git rev-parse --git-dir >/dev/null 2>&1; then
  echo "wire-githooks: not inside a git repository" >&2
  exit 2
fi

current=$(git config --get core.hooksPath 2>/dev/null || true)
if [ "$current" = "githooks" ]; then
  echo "wire-githooks: already wired (core.hooksPath=githooks); nothing to do."
  exit 0
fi
if [ -n "$current" ]; then
  echo "wire-githooks: note: replacing existing core.hooksPath '$current'."
fi

if ! git config core.hooksPath githooks; then
  echo "wire-githooks: writing core.hooksPath failed" >&2
  exit 2
fi

top=$(git rev-parse --show-toplevel 2>/dev/null || true)
if [ -n "$top" ] && [ ! -d "$top/githooks" ]; then
  echo "wire-githooks: note: this checkout has no githooks/ directory yet;" \
    "the hooks no-op until a branch carrying them is checked out."
fi
echo "wire-githooks: core.hooksPath=githooks set for this clone (covers all its worktrees)."
exit 0
