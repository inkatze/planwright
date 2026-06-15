#!/bin/sh
# orchestrate-lock.sh — the per-spec advisory lock /orchestrate holds only
# during a tasks.md state move (Task 13, REQ-F1.3, D-10).
#
# The lock is a directory at <spec-dir>/.orchestrate.lock, taken with an
# atomic mkdir and broken when older than stale_lock_threshold. The lock path
# and the mkdir acquisition protocol match scripts/tasks-pr-sync.sh's inline
# lock (kickoff brief risk row 18) so the orchestrator and the PR-sync hook —
# which may run concurrently against the same primary checkout — exclude each
# other. The failure handling differs by design: this dispatch-path primitive
# fails closed (exit 2) on a non-contention mkdir error, whereas the hook is
# fail-soft (a failed mkdir is a clean skip that --bookkeeping reconciles).
# The lock is held only across the brief state-changing move and released
# before /execute-task runs, so it never serializes execution (D-10).
#
# Usage: orchestrate-lock.sh acquire|release <spec-dir>
#   acquire  mkdir the lock; break + re-acquire a stale one. Exit 0 on a held
#            lock, 1 when another live holder has it (a clean no-op — the
#            caller skips this step; --bookkeeping reconciles a dropped move).
#   release  rmdir the lock (idempotent: a missing lock is fine). Exit 0.
#
# stale_lock_threshold is read via scripts/config-get.sh (defaults + the
# per-repo override, D-33), normalized from `<n>m`/bare minutes; an absent
# key uses 15m and a malformed value falls back to 15m with a warning (the
# config-model fallback rule, matching the hook).
#
# Portable POSIX sh: mkdir-atomicity is the lock primitive (not flock, which
# is non-portable and process-bound); a mkdir lock survives the acquiring
# process, which is what lets /orchestrate hold it across the move and a
# crash fall through to the stale-break.
set -u

LC_ALL=C
export LC_ALL
unset CDPATH

cmd="${1:-}"
spec_dir="${2:-}"
if [ -z "$cmd" ] || [ -z "$spec_dir" ]; then
  echo "usage: orchestrate-lock.sh acquire|release <spec-dir>" >&2
  exit 2
fi
if [ ! -d "$spec_dir" ]; then
  echo "orchestrate-lock: no such spec dir: $spec_dir" >&2
  exit 2
fi

lock="$spec_dir/.orchestrate.lock"

case "$cmd" in
  release)
    rmdir "$lock" 2>/dev/null || true
    exit 0
    ;;
  acquire) ;;
  *)
    echo "orchestrate-lock: unknown command '$cmd' (acquire|release)" >&2
    exit 2
    ;;
esac

# Resolve stale_lock_threshold (minutes). The local override lives at the
# repo root (<spec-dir>/../..), the layout the lock protocol assumes.
threshold_min=15
script_dir=$(cd "$(dirname "$0")" && pwd) || exit 2
repo_root=$(cd "$spec_dir/../.." 2>/dev/null && pwd) || repo_root=""
local_cfg=""
[ -n "$repo_root" ] && local_cfg="$repo_root/.claude/planwright.local.yml"

# config-get's stderr is NOT suppressed: it is silent on a found/absent key,
# and the one thing it does emit — the broken-install diagnostic when the
# tracked defaults are missing/unreadable — is exactly what should surface
# rather than be swallowed into a silent 15m fallback.
v=$(PLANWRIGHT_LOCAL_CONFIG="$local_cfg" \
  "$script_dir/config-get.sh" stale_lock_threshold) || v=""
v=${v%m}
case "$v" in
  '') ;; # key absent everywhere: the tracked default (15) stands
  *[!0-9]*)
    echo "orchestrate-lock: ignoring malformed stale_lock_threshold; using ${threshold_min}m" >&2
    ;;
  *) threshold_min=$v ;;
esac

# Atomic acquire; break a stale holder, then retry once.
if mkdir "$lock" 2>/dev/null; then
  exit 0
fi
# mkdir failed. Distinguish real contention (the lock dir now exists, held by
# another holder) from a genuine error (unwritable spec dir, filesystem fault)
# where the lock never got created. Masking the latter as a clean "busy" no-op
# would make /orchestrate skip the spec forever; fail closed instead.
if [ ! -d "$lock" ]; then
  echo "orchestrate-lock: cannot create $lock (spec dir unwritable or filesystem error)" >&2
  exit 2
fi
if [ -n "$(find "$lock" -maxdepth 0 -mmin +"$threshold_min" 2>/dev/null)" ]; then
  rm -rf "$lock"
  if mkdir "$lock" 2>/dev/null; then
    exit 0
  fi
  # Same distinction as the initial mkdir: no lock dir means a real error
  # (fail closed), a present one means another holder won the post-break race.
  if [ ! -d "$lock" ]; then
    echo "orchestrate-lock: cannot create $lock after stale break (spec dir unwritable or filesystem error)" >&2
    exit 2
  fi
  echo "orchestrate-lock: contention after stale break; skipping ($lock)" >&2
  exit 1
fi
# Held by a live holder within the threshold: clean no-op.
exit 1
