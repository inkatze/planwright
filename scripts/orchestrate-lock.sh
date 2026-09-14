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
# TOO STICKY IS NOT FREE EITHER, which is what `sweep` is for. A detached hold
# outlives the session that took it, and a dispatch that finds one reads it as
# contention — which is a clean no-op, so a spec whose orchestrator died mid
# window stops being dispatched and says nothing about it. The answer is not a
# threshold: it is evidence. An acquire that CAN name its holder does so, and
# then the hold is an ordinary one the primitive breaks by itself; an acquire
# that cannot leaves a record of why, and `sweep` refuses rather than guessing.
#
# ATTRIBUTION, in order: an explicit `--owner-pid`; else `PLANWRIGHT_TOWER_PID`
# from the environment contract the fleet doc defines for a session that knows
# its own identity, when it names a process that is actually running; else the
# tmux window this session occupies, which is a death-evidence class of its own
# but not a pid, so it is recorded beside the lock for `sweep` rather than used
# as the owner. With none of those, the hold is unattributed and stays until
# someone releases it.
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
#   sweep    clear a DETACHED hold, but only on positive evidence that its
#            holder is gone. Prints one word and exits in the evidence
#            vocabulary: `cleared` 0, `no-lock` 0, `owned` 0 (the primitive
#            breaks that one itself), `alive` 1, `unattributed` 3, `unknown` 3.
#            Never acts on silence and never on elapsed time.
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

# The attribution record: one line, `<token>\t<evidence-class> <args>`, beside
# the lock. It is bound to the token because a record that outlived its lock
# would have `sweep` judging the wrong holder; a record whose token does not
# match what is at the path now is read as absent, which is the safe answer.
handle_file="$lock#owner#"

# read_handle — set `handle` to the evidence handle recorded for the token
# currently at the lock path, or to the empty string.
read_handle() {
  handle=""
  rh_token=$(readlink "$lock" 2>/dev/null) || return 0
  [ -n "$rh_token" ] || return 0
  [ -f "$handle_file" ] || return 0
  rh_line=$(head -n 1 "$handle_file" 2>/dev/null) || return 0
  case $rh_line in
    "$rh_token	"*) handle=${rh_line#*	} ;;
  esac
}

case "$cmd" in
  sweep)
    # The evidence command is a seam so a test can pin a verdict; unset, it is
    # the fleet's own predicate, which is the only thing that decides here.
    evidence_cmd=${PLANWRIGHT_TOWER_EVIDENCE_CMD:-$script_dir/fleet-death-evidence.sh}
    if [ ! -L "$lock" ]; then
      if [ -e "$lock" ]; then
        # Something that is not a lock. `release` is the verb for that; this
        # one only ever judges holders.
        printf '%s\n' unattributed
        exit 3
      fi
      printf '%s\n' no-lock
      exit 0
    fi
    sweep_token=$(readlink "$lock" 2>/dev/null) || sweep_token=""
    case $sweep_token in
      detached-*) ;;
      *)
        # An ordinary hold names a process, and the primitive breaks it the
        # moment that process is gone. Nothing here to decide.
        printf '%s\n' owned
        exit 0
        ;;
    esac
    read_handle
    if [ -z "$handle" ]; then
      printf '%s\n' unattributed
      exit 3
    fi
    if [ ! -x "$evidence_cmd" ]; then
      printf '%s\n' unknown
      echo "orchestrate-lock: $evidence_cmd is missing or not executable; refusing to judge $lock" >&2
      exit 3
    fi
    ev_rc=0
    # The split is deliberate — a handle is a class plus its arguments — but it
    # must be a split and nothing more. A tmux window can legally be named `*`,
    # and tmux windows are the class recorded here, so an unguarded split would
    # expand it against the working directory and hand the predicate a list of
    # filenames to judge instead.
    case $- in
      *f*) ev_restore='set -f' ;;
      *) ev_restore='set +f' ;;
    esac
    set -f
    # shellcheck disable=SC2086 # word-split on purpose, with globbing off
    "$evidence_cmd" $handle >/dev/null 2>&1 || ev_rc=$?
    $ev_restore
    case $ev_rc in
      0) ;;
      1)
        printf '%s\n' alive
        exit 1
        ;;
      *)
        # Lost observability, a refused input, or the predicate itself failing.
        # None of them is death, and the lock is left exactly as it was.
        printf '%s\n' unknown
        exit 3
        ;;
    esac
    # Positive evidence, and only now. Re-read the token first: between the
    # verdict and this line the holder may have released and a successor taken
    # the path, and clearing THAT is the double-grant the evidence bar exists
    # to prevent.
    if [ "$(readlink "$lock" 2>/dev/null)" != "$sweep_token" ]; then
      printf '%s\n' alive
      exit 1
    fi
    if ! pw_lock_break_force "$lock"; then
      printf '%s\n' unknown
      echo "orchestrate-lock: cannot clear $lock (it is still present after the removal; check its type and the spec directory's permissions)" >&2
      exit 3
    fi
    rm -f "$handle_file" 2>/dev/null || :
    printf '%s\n' cleared
    exit 0
    ;;
  release)
    # Unconditional and idempotent, which is what makes it the recovery path
    # for a detached hold whose owner never came back. It also clears a lock
    # DIRECTORY left by the retired mkdir shape.
    rm -f "$handle_file" 2>/dev/null || :
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
    echo "orchestrate-lock: unknown command '$cmd' (acquire|release|sweep)" >&2
    exit 2
    ;;
esac

# One attempt, not a spin: the caller owns the failure policy off the exit code
# (REQ-D1.2), and a busy lock is a clean skip for both callers rather than
# something to wait out. The stale break inside the attempt is what turns a
# dead owner's lock into a held one, in the same call.
# Attribution, before the take. A holder this call can name is a holder the
# primitive can probe, which makes the hold an ordinary one that needs no sweep
# at all; a holder it can only name by tmux window is recorded beside the lock
# instead, because that is a death-evidence class and not a pid.
sweep_handle=""
if [ -z "$owner_pid" ]; then
  case ${PLANWRIGHT_TOWER_PID:-} in
    '' | 0 | *[!0-9]*) ;;
    *)
      # Only a pid that is actually running: naming a dead one would mint a
      # hold the next caller breaks immediately, which is worse than not
      # attributing it at all.
      if kill -0 "$PLANWRIGHT_TOWER_PID" 2>/dev/null; then
        owner_pid=$PLANWRIGHT_TOWER_PID
      fi
      ;;
  esac
fi
if [ -z "$owner_pid" ] && [ -n "${TMUX:-}" ] && [ -n "${TMUX_PANE:-}" ] \
  && command -v tmux >/dev/null 2>&1; then
  tw=$(tmux display-message -p -t "$TMUX_PANE" '#{session_name} #{window_index}' 2>/dev/null) || tw=""
  # One space, no tab, and no shell pattern character: a handle is recorded to
  # be split and handed to the predicate later, and one carrying a glob is one
  # this cannot act on safely. Refusing to record it leaves the hold
  # unattributed, which the sweep already treats as a reason to refuse.
  case $tw in
    '' | *"$(printf '\t')"* | *' '*' '* | *'*'* | *'?'* | *'['*) ;;
    *' '*) sweep_handle="tmux-window $tw" ;;
  esac
fi

rc=0
if [ -n "$owner_pid" ]; then
  pw_lock_acquire_for "$lock" "$owner_pid" 1 || rc=$?
else
  pw_lock_try_detached "$lock" || rc=$?
fi
if [ "$rc" -eq 0 ]; then
  # Bound to the token, so a record that outlives its lock is read as absent
  # rather than as evidence about a holder it never described.
  rm -f "$handle_file" 2>/dev/null || :
  if [ -n "$sweep_handle" ]; then
    printf '%s\t%s\n' "$PW_LOCK_TOKEN" "$sweep_handle" >"$handle_file" 2>/dev/null || :
  fi
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
