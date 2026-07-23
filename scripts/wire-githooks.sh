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
# Usage: wire-githooks.sh   (from anywhere inside a work tree of the clone)
# Exit: 0 wired (or already wired); 2 usage error / not a git work tree
#   (a bare repo has nothing to wire) / config write failure.
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

if ! top=$(git rev-parse --show-toplevel 2>/dev/null); then
  echo "wire-githooks: not inside a git work tree (a bare repo has no checkout for the relative hooksPath to resolve against; nothing to wire)" >&2
  exit 2
fi

# Read the LOCAL config only: a global core.hooksPath=githooks must not
# short-circuit the repo-local write, or the clone silently unwires the day
# the global value changes.
current=$(git config --local --get core.hooksPath 2>/dev/null || true)
if [ "$current" = "githooks" ]; then
  echo "wire-githooks: already wired (core.hooksPath=githooks); nothing to do."
  exit 0
fi
if [ -n "$current" ]; then
  printf 'wire-githooks: note: replacing existing core.hooksPath %s.\n' "'$current'"
fi

if ! git config --local core.hooksPath githooks; then
  # Two concurrent wire runs can race git's config.lock; if the other run
  # already wrote the value, this invocation's job is done.
  if [ "$(git config --local --get core.hooksPath 2>/dev/null || true)" = "githooks" ]; then
    echo "wire-githooks: already wired concurrently (core.hooksPath=githooks); nothing to do."
    exit 0
  fi
  echo "wire-githooks: writing core.hooksPath failed" >&2
  exit 2
fi

if [ ! -d "$top/githooks" ]; then
  echo "wire-githooks: note: this checkout has no githooks/ directory yet;" \
    "the hooks no-op until a branch carrying them is checked out."
fi
echo "wire-githooks: core.hooksPath=githooks set for this clone (covers all its worktrees)."
exit 0
