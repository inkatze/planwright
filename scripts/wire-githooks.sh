#!/bin/sh
# wire-githooks.sh — the dedicated idempotent wire step for the hook backstop
# (guard-coverage Task 2; D-3; REQ-A1.3). Sets `core.hooksPath githooks` so
# git runs the tracked githooks/ hooks. core.hooksPath is clone-global, so one
# wiring covers every worktree of the clone until something rewrites it (see
# --if-tracked below; documented blast radius; the hooks no-op cleanly on a
# checkout whose branch lacks the githooks/ files). CI runs this as an
# explicit step before `mise run check` (wire-then-verify, D-3).
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
# --if-tracked is the form planwright's worktree-creation scripts run inside
# each worktree they create: it wires only when that checkout tracks both
# githooks/ and this wire step, and otherwise exits 0 having changed nothing,
# so a repository that does not ship the backstop keeps its own hooks. Claude
# Code's own worktree creation rewrites a relative core.hooksPath to an
# absolute path into the primary checkout, which is why fresh worktrees are
# rewired here rather than trusted to inherit the value. In this form stdout
# stays empty and every line on stderr is one for the caller to relay: a
# value it replaced, an unset value it wired (which re-enables hooks someone
# may have switched off by hand), or a failure.
#
# Usage: wire-githooks.sh [--if-tracked]   (from inside a work tree of the clone)
# Exit: 0 wired (or already wired, or --if-tracked on a checkout without the
#   backstop); 2 usage error / not a git work tree (a bare repo has nothing to
#   wire) / config write failure.
#
# Portable POSIX sh; bash 3.2 / BSD tooling floor.
set -u
LC_ALL=C
export LC_ALL
unset CDPATH

if_tracked=0
if [ $# -eq 1 ] && [ "$1" = --if-tracked ]; then
  if_tracked=1
elif [ $# -ne 0 ]; then
  echo "usage: wire-githooks.sh [--if-tracked]" >&2
  exit 2
fi

# info <line> — progress for a plain run; silent under --if-tracked.
info() {
  [ "$if_tracked" -eq 1 ] || printf '%s\n' "$1"
}
# note <line> — a change worth reporting: stdout for a plain run, stderr (for
# the caller to relay) under --if-tracked.
note() {
  if [ "$if_tracked" -eq 1 ]; then
    printf '%s\n' "$1" >&2
  else
    printf '%s\n' "$1"
  fi
}

if ! top=$(git rev-parse --show-toplevel 2>/dev/null); then
  echo "wire-githooks: not inside a git work tree (a bare repo has no checkout for the relative hooksPath to resolve against; nothing to wire)" >&2
  exit 2
fi

if [ "$if_tracked" -eq 1 ] && { [ ! -d "$top/githooks" ] || [ ! -f "$top/scripts/wire-githooks.sh" ]; }; then
  exit 0
fi

# Read the LOCAL config only: a global core.hooksPath=githooks must not
# short-circuit the repo-local write, or the clone silently unwires the day
# the global value changes.
current=$(git config --local --get core.hooksPath 2>/dev/null || true)
if [ "$current" = "githooks" ]; then
  info "wire-githooks: already wired (core.hooksPath=githooks); nothing to do."
  exit 0
fi
if [ -n "$current" ]; then
  note "wire-githooks: note: replacing existing core.hooksPath '$current'."
elif [ "$if_tracked" -eq 1 ]; then
  note "wire-githooks: note: core.hooksPath was unset; wiring the tracked githooks/ (re-enables hooks if they were switched off by hand)."
fi

# --replace-all: a multi-valued key (left by `git config --add`) refuses a
# plain single-value write.
if ! git config --local --replace-all core.hooksPath githooks; then
  # Two concurrent wire runs can race git's config.lock; if the other run
  # already wrote the value, this invocation's job is done.
  if [ "$(git config --local --get core.hooksPath 2>/dev/null || true)" = "githooks" ]; then
    info "wire-githooks: already wired concurrently (core.hooksPath=githooks); nothing to do."
    exit 0
  fi
  echo "wire-githooks: writing core.hooksPath failed" >&2
  exit 2
fi

if [ ! -d "$top/githooks" ]; then
  echo "wire-githooks: note: this checkout has no githooks/ directory yet;" \
    "the hooks no-op until a branch carrying them is checked out."
fi
info "wire-githooks: core.hooksPath=githooks set for this clone (covers all its worktrees)."
exit 0
