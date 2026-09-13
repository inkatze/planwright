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
# The lock is taken through scripts/lock-lib.sh, the one advisory-lock
# primitive in the tree: an atomic symlink create whose target is an owner
# token. The branch ref is the natural fence (D-4): because a lock holder
# writes no authoritative state (D-1), a holder acting after it lost the lock
# cannot corrupt derived state, so no fencing tokens are added. The lock is
# held only across the brief state-changing move and released before
# /execute-task runs, so it never serializes execution (D-10).
#
# WHO OWNS THE HOLD decides when it can be broken, and the two callers of this
# script differ:
#
#   * /orchestrate acquires at the start of its dispatch window and releases at
#     the end, several tool invocations later. Nothing of its own runs in
#     between, so there is no process whose absence could prove the lock dead:
#     that is a DETACHED hold, never auto-broken, cleared by `release` (which
#     an operator can run by hand if a crash left one standing).
#   * a script that acquires, works, and releases inside ONE invocation passes
#     `--owner-pid $$`. Its hold is owned by a live process, so a crash leaves
#     a lock the next caller breaks on its own — no waiting, no operator.
#
# The default is the detached form, because it is the one that cannot silently
# lose exclusion: a caller that forgets the flag gets a lock that is too sticky
# rather than one that evaporates the moment it is taken.
#
# REQ-F1.1 (parsed input is data, never an executed path): the spec id is read
# from the canonicalized spec-dir basename and validated against the spec-id
# grammar `^[a-z0-9][a-z0-9-]*$` (max 64), and the spec dir must resolve under
# a `specs/` parent after symlink resolution, so the derived lock path is
# containment-checked before any create or unlink. A malformed or hostile spec dir
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
# Usage: orchestrate-lock.sh acquire <spec-dir> [--owner-pid <pid>]
#        orchestrate-lock.sh release <spec-dir>
#   acquire  take the lock, breaking one whose owner process is gone. Exit 0
#            on a held lock, 1 when a holder has it (a clean no-op: the caller
#            skips this step and --bookkeeping reconciles a dropped move), 2 on
#            a real error or a refused (malformed/hostile) spec dir.
#   release  clear the lock unconditionally (idempotent: a missing lock is
#            fine). Exit 0, or 2 when the path could not be cleared at all. It
#            also clears a lock DIRECTORY left by the retired mkdir shape, so
#            an in-place upgrade recovers itself.
#
# Portable POSIX sh. `flock` is not an option: it is absent on macOS, inside
# the support bar, and it is process-bound, which neither caller here is.
set -u

LC_ALL=C
export LC_ALL
unset CDPATH

cmd="${1:-}"
spec_dir="${2:-}"
if [ -z "$cmd" ] || [ -z "$spec_dir" ]; then
  echo "usage: orchestrate-lock.sh acquire|release <spec-dir> [--owner-pid <pid>]" >&2
  exit 2
fi
shift 2 2>/dev/null || true

owner_pid=""
owner_pid_given=0
while [ "$#" -gt 0 ]; do
  case $1 in
    --owner-pid)
      [ "$#" -ge 2 ] || {
        echo "orchestrate-lock: --owner-pid needs a pid" >&2
        exit 2
      }
      owner_pid=$2
      owner_pid_given=1
      shift 2
      ;;
    *)
      echo "orchestrate-lock: unknown option '$1'" >&2
      exit 2
      ;;
  esac
done
if [ "$owner_pid_given" = 1 ]; then
  # An empty or zero value is refused rather than treated as absent: the
  # absent case takes the DETACHED hold, which nothing auto-breaks, so a caller
  # writing `--owner-pid "$maybe_unset"` would silently get the stickiest lock
  # available and a success exit. Zero names no process at all.
  case $owner_pid in
    '' | 0 | *[!0-9]*)
      echo "orchestrate-lock: --owner-pid must be a non-zero number" >&2
      exit 2
      ;;
  esac
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

script_dir=$(cd "$(dirname "$0")" && pwd) || exit 2
# shellcheck source=scripts/lock-lib.sh
. "$script_dir/lock-lib.sh" || {
  echo "orchestrate-lock: cannot load the lock primitive $script_dir/lock-lib.sh" >&2
  exit 2
}

case "$cmd" in
  release)
    # Unconditional and idempotent, which is what makes it the recovery path
    # for a detached hold whose owner never came back. It also clears a lock
    # DIRECTORY left by the retired mkdir shape.
    pw_lock_break_force "$lock" || {
      # What is known is only that the path is still occupied. WHY is not: the
      # removal can fail on an unwritable spec dir as readily as on something
      # unusual at the path, and naming one of those sends the operator to
      # inspect the wrong thing.
      echo "orchestrate-lock: cannot clear $lock (it is still present after the removal; check its type and the spec directory's permissions)" >&2
      exit 2
    }
    exit 0
    ;;
  acquire) ;;
  *)
    echo "orchestrate-lock: unknown command '$cmd' (acquire|release)" >&2
    exit 2
    ;;
esac

# One attempt, not a spin: the caller owns the failure policy off the exit code
# (REQ-D1.2), and a busy lock is a clean skip for both callers rather than
# something to wait out. The stale break inside the attempt is what turns a
# dead owner's lock into a held one, in the same call.
rc=0
if [ -n "$owner_pid" ]; then
  pw_lock_acquire_for "$lock" "$owner_pid" 1 || rc=$?
else
  pw_lock_try_detached "$lock" || rc=$?
fi
case $rc in
  0) exit 0 ;;
  1)
    # Held by a live holder: a clean no-op. No diagnostic — this is the
    # expected outcome under contention and both callers treat it as a skip.
    exit 1
    ;;
  *)
    # A real error (unwritable spec dir, a non-lock squatting the path). The
    # library already said what it was on stderr. Masking it as a clean busy
    # would make /orchestrate skip the spec forever; fail closed instead.
    exit 2
    ;;
esac
