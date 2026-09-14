#!/bin/sh
# orchestrate-lock.sh — the ONE per-spec advisory-lock primitive, shared by
# /orchestrate (held only during a tasks.md state move) and the
# scripts/tasks-pr-sync.sh PostToolUse hook (D-4, REQ-D1.1, REQ-D1.2;
# originally Task 13, REQ-F1.3, D-10). Both call sites acquire and break
# through this script: there is no second acquire/stale-break implementation
# (REQ-D1.1 — the duplicated inline hook lock was collapsed into this
# primitive), so the orchestrator and the hook — which may run concurrently
# against the same primary checkout — mutually exclude by construction.
#
# The lock is a directory at <spec-dir>/.orchestrate.lock, taken with an
# atomic mkdir and broken when older than stale_lock_threshold. The branch ref
# is the natural fence (D-4): because a lock holder writes no authoritative
# state (D-1), a stale holder acting after lease expiry cannot corrupt derived
# state, so no fencing tokens are added. The lock is held only across the brief
# state-changing move and released before /execute-task runs, so it never
# serializes execution (D-10).
#
# REQ-F1.1 (parsed input is data, never an executed path): the spec id is read
# from the canonicalized spec-dir basename and validated against the spec-id
# grammar `^[a-z0-9][a-z0-9-]*$` (max 64), and the spec dir must resolve under
# a `specs/` parent after symlink resolution, so the derived lock path is
# containment-checked before any mkdir/rmdir. A malformed or hostile spec dir
# (bad charset, traversal, a symlink escaping the tree) is a clean refusal
# (exit 2, diagnostic, no lock touched), never an out-of-tree lock path.
#
# Failure policy is the CALLER's, off one exit-code contract (REQ-D1.2): this
# script reports 0 held / 1 busy / 2 error-or-refusal, and each caller applies
# its own policy. /orchestrate fails closed (a non-zero acquire halts/skips the
# step per its own table); the hook is fail-soft (any non-zero acquire is a
# clean skip that --bookkeeping reconciles). Keeping the policy at the call
# site is what lets one primitive serve both without a second implementation.
#
# Usage: orchestrate-lock.sh acquire|release <spec-dir>
#   acquire  mkdir the lock; break + re-acquire a stale one. Exit 0 on a held
#            lock, 1 when another live holder has it (a clean no-op — the
#            caller skips this step; --bookkeeping reconciles a dropped move),
#            2 on a real error or a refused (malformed/hostile) spec dir.
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

# REQ-F1.1: derive the lock path from a grammar-validated spec id, contained
# under a specs/ parent after canonicalization, before any mkdir/rmdir. The
# spec dir is treated as data: its physical path (pwd -P resolves any symlink)
# decides the id and containment, so a hostile dir (bad charset, traversal, an
# escaping symlink) is a clean refusal rather than an out-of-tree lock path.
# This applies to release too: a hostile path must never reach an rmdir.
canon_dir=$(cd "$spec_dir" 2>/dev/null && pwd -P) || {
  echo "orchestrate-lock: cannot resolve spec dir: $spec_dir" >&2
  exit 2
}
spec_id=${canon_dir##*/}
spec_parent=${canon_dir%/*}
case "$spec_id" in
  '' | -* | *[!a-z0-9-]*)
    echo "orchestrate-lock: refusing malformed spec id '$spec_id' (REQ-F1.1: must match ^[a-z0-9][a-z0-9-]*\$)" >&2
    exit 2
    ;;
esac
if [ "${#spec_id}" -gt 64 ]; then
  echo "orchestrate-lock: refusing spec id '$spec_id' (REQ-F1.1: exceeds 64 chars)" >&2
  exit 2
fi
case "$spec_parent" in
  */specs) ;;
  *)
    echo "orchestrate-lock: spec dir '$canon_dir' is not contained under a specs/ parent; refusing (REQ-F1.1)" >&2
    exit 2
    ;;
esac

lock="$canon_dir/.orchestrate.lock"

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
repo_root=$(cd "$canon_dir/../.." 2>/dev/null && pwd) || repo_root=""
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
