#!/bin/sh
# migrate-status-lifecycle.sh [specs-dir]
#
# The one-time adoption migration for the six-status lifecycle (kickoff-lifecycle
# Task 8; REQ-A1.7, D-4). Sweeps every spec bundle under <specs-dir> (default the
# repo's specs/) and reconciles its bundle **Status:** header to the value derived
# from task state: a bundle whose declared Status is Active but with no task
# deriving In-progress or Completed migrates to Ready; a bundle with work in
# flight or completed stays Active; Done takes precedence when no startable task
# remains. Because Ready<->Active is derived (D-3), the reconcile *is* the
# migration (D-4): this is a thin one-time application of the SAME single writer,
# `tasks-pr-sync.sh reconcile-status` (do_status), not a second status writer.
#
# Status-only by design: it never rewrites task placement, so sweeping the whole
# corpus cannot relocate task blocks in legacy bundles whose git evidence has aged
# out. The single writer's guards therefore apply per bundle — Draft, Retired, and
# Superseded headers are left untouched, and a stored-Done bundle is never
# reopened.
#
# Idempotent: re-running over a migrated corpus is a no-op (each bundle's
# reconcile-status is itself idempotent), so an interrupted sweep is recovered by
# simply re-running. Per-bundle halt-and-report: a malformed bundle is surfaced by
# path on stderr and skipped, never silently flipped; the sweep proceeds to the
# next bundle. Underscore-prefixed accumulators (specs/_observations, specs/_*)
# are not bundles and are excluded.
#
# Exit 0 once the sweep completes (skips included — they are reported, not fatal);
# exit 2 only on an operational failure that prevents the sweep from running (the
# reconcile writer or the specs dir is unreachable).
set -eu
LC_ALL=C
export LC_ALL
unset CDPATH 2>/dev/null || true

here=$(cd "$(dirname "$0")" && pwd -P) || exit 2
sync_sh="$here/tasks-pr-sync.sh"
repo_root=$(cd "$here/.." && pwd -P) || exit 2

if [ ! -x "$sync_sh" ]; then
  echo "migrate-status-lifecycle: reconcile writer missing or not executable: $sync_sh" >&2
  exit 2
fi

specs_arg="${1:-$repo_root/specs}"
specs_dir=$(cd "$specs_arg" 2>/dev/null && pwd -P) || {
  echo "migrate-status-lifecycle: no such specs dir: $specs_arg" >&2
  exit 2
}

status_of() { awk '/^\*\*Status:\*\* / { print $2; exit }' "$1" 2>/dev/null; }

migrated=0
unchanged=0
skipped=0

for spec_dir in "$specs_dir"/*/; do
  [ -d "$spec_dir" ] || continue # no-match glob stays literal; not a dir
  spec_dir=${spec_dir%/}
  name=$(basename "$spec_dir")
  # Underscore-prefixed accumulators are not spec bundles (specs/_observations,
  # specs/_pending): never migrate their headers.
  case $name in
    _*) continue ;;
  esac

  req="$spec_dir/requirements.md"
  tasks="$spec_dir/tasks.md"
  # Malformed pre-check: surface by path and skip, never silently flip. A bundle
  # must carry a regular (non-symlink) requirements.md and tasks.md, and tasks.md
  # must declare at least one task block to derive from.
  reason=""
  if [ ! -f "$req" ] || [ -L "$req" ]; then
    reason="missing or symlinked requirements.md"
  elif [ ! -f "$tasks" ] || [ -L "$tasks" ]; then
    reason="missing or symlinked tasks.md"
  elif ! grep -qE '^### Task [0-9]' "$tasks"; then
    reason="no task blocks in tasks.md"
  fi
  if [ -n "$reason" ]; then
    echo "skipped (malformed): $spec_dir — $reason" >&2
    skipped=$((skipped + 1))
    continue
  fi

  before=$(status_of "$req")
  # The single status writer (do_status via reconcile-status). A fail-closed exit
  # (hostile dir, lock error, derivation failure) is a per-bundle skip-and-report,
  # never a silent flip and never a hard stop for the rest of the sweep.
  if ! "$sync_sh" reconcile-status "$spec_dir" >/dev/null 2>&1; then
    echo "skipped (reconcile failed): $spec_dir" >&2
    skipped=$((skipped + 1))
    continue
  fi
  after=$(status_of "$req")

  if [ "$before" != "$after" ]; then
    echo "migrated: $name  $before -> $after"
    migrated=$((migrated + 1))
  else
    echo "unchanged: $name  ($after)"
    unchanged=$((unchanged + 1))
  fi
done

echo "migrate-status-lifecycle: $migrated migrated, $unchanged unchanged, $skipped skipped"
