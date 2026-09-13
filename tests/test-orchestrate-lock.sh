#!/bin/bash
# Tests for scripts/orchestrate-lock.sh — the per-spec advisory lock behind
# /orchestrate's state moves (Task 13, REQ-F1.3, D-10).
#
# Lock contract (REQ-F1.3, and risk-register row 18: the path and protocol MUST
# match tasks-pr-sync.sh so the two writers exclude each other):
#   - acquire creates <spec-dir>/.orchestrate.lock as a symlink whose target is
#     an owner token, through the shared primitive scripts/lock-lib.sh;
#   - a second acquire on a held lock is a clean no-op (exit 1), lock intact;
#   - release clears the lock and is idempotent, and clears a lock DIRECTORY
#     left by the retired mkdir shape so an in-place upgrade recovers itself;
#   - a lock is broken when its OWNER PROCESS IS ABSENT, never because it is
#     old: /orchestrate's hold spans tool invocations and has no owner to probe
#     (the detached default, cleared only by release), while a caller that
#     works and releases inside one invocation passes --owner-pid $$ and gets a
#     hold the next caller breaks the moment that process is gone.
#
# Runs standalone under /bin/bash (the bash 3.2 floor).
set -eu
LC_ALL=C
export LC_ALL
unset CDPATH

here=$(cd "$(dirname "$0")" && pwd)
LOCK="$here/../scripts/orchestrate-lock.sh"

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

[ -x "$LOCK" ] || fail "scripts/orchestrate-lock.sh missing or not executable"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# Fixture: a <repo>/specs/<spec> layout, the shape a real checkout has.
repo="$tmp/repo"
spec="$repo/specs/demo"
mkdir -p "$spec" "$repo/.claude"
lock="$spec/.orchestrate.lock"

# 1. Acquire on a fresh spec creates the canonical lock path, as a symlink
#    carrying an owner token.
/bin/bash "$LOCK" acquire "$spec" || fail "fresh acquire: non-zero exit"
[ -L "$lock" ] || fail "fresh acquire: lock not created as a symlink at the canonical path"
case "$(readlink "$lock")" in
  detached-*) ;;
  *) fail "fresh acquire: default hold is not detached (target: $(readlink "$lock"))" ;;
esac
echo "ok: acquire creates <spec-dir>/.orchestrate.lock as a detached owner-token symlink"

# 2. A second acquire on the held lock is a clean no-op (exit 1), intact.
rc=0
/bin/bash "$LOCK" acquire "$spec" >/dev/null 2>&1 || rc=$?
[ "$rc" = 1 ] || fail "busy acquire: exit $rc, expected 1"
[ -L "$lock" ] || fail "busy acquire: lock disappeared"
echo "ok: a busy lock is a clean no-op (exit 1)"

# 3. The detached hold is NOT broken by age. This is the defect the retired
#    age rule caused in the other direction: /orchestrate holds across several
#    tool invocations, and a threshold would hand the lock to the hook
#    mid-window.
touch -h -t 200001010000 "$lock" 2>/dev/null || touch -t 200001010000 "$lock" 2>/dev/null || true
rc=0
/bin/bash "$LOCK" acquire "$spec" >/dev/null 2>&1 || rc=$?
[ "$rc" = 1 ] || fail "aged detached lock: exit $rc, expected 1 (a detached hold has no owner to declare absent)"
[ -L "$lock" ] || fail "aged detached lock: wrongly broken"
echo "ok: a detached hold is never broken by age"

# 4. Release clears the lock and is idempotent — which is also the recovery
#    path for a detached hold whose owner never came back.
/bin/bash "$LOCK" release "$spec" || fail "release: non-zero exit"
if [ -L "$lock" ] || [ -e "$lock" ]; then
  fail "release: lock not removed"
fi
/bin/bash "$LOCK" release "$spec" || fail "release (idempotent): non-zero exit"
echo "ok: release clears the lock and is idempotent"

# 5. An --owner-pid hold whose owner is still running is busy, however old the
#    lock is.
sleep 45 &
live_pid=$!
/bin/bash "$LOCK" acquire "$spec" --owner-pid "$live_pid" || fail "owned acquire: non-zero exit"
case "$(readlink "$lock")" in
  "$live_pid"-*) ;;
  *) fail "owned acquire: token does not name the owner pid (target: $(readlink "$lock"))" ;;
esac
touch -h -t 200001010000 "$lock" 2>/dev/null || touch -t 200001010000 "$lock" 2>/dev/null || true
rc=0
/bin/bash "$LOCK" acquire "$spec" >/dev/null 2>&1 || rc=$?
[ "$rc" = 1 ] || fail "live-owner lock: exit $rc, expected 1 (owner still running)"
kill "$live_pid" 2>/dev/null || true
wait "$live_pid" 2>/dev/null || true
echo "ok: a lock whose owner process still runs is busy at any age"

# 6. The same lock, once its owner is gone, is broken and re-acquired — with no
#    threshold to wait out.
/bin/bash "$LOCK" acquire "$spec" --owner-pid "$$" || fail "dead-owner acquire: non-zero exit"
case "$(readlink "$lock")" in
  "$$"-*) ;;
  *) fail "dead-owner acquire: the break did not hand the lock over (target: $(readlink "$lock"))" ;;
esac
/bin/bash "$LOCK" release "$spec"
echo "ok: a lock whose owner process is gone is broken at once, with no threshold"

# 7. Release clears a lock DIRECTORY left by the retired mkdir shape. Without
#    this an in-place upgrade would wedge every writer on that spec forever.
mkdir "$lock"
/bin/bash "$LOCK" release "$spec" || fail "legacy release: non-zero exit"
[ ! -e "$lock" ] || fail "legacy release: the mkdir-shape lock directory survived"
/bin/bash "$LOCK" acquire "$spec" || fail "post-legacy acquire: non-zero exit"
/bin/bash "$LOCK" release "$spec"
echo "ok: release clears a lock directory left by the retired mkdir shape"

# 8. A non-contention create failure (unwritable spec dir / filesystem error)
#    must fail closed (exit 2 + diagnostic), NOT be masked as a clean "busy"
#    no-op (exit 1) — otherwise /orchestrate silently skips the spec forever.
rorepo="$tmp/ro"
rospec="$rorepo/specs/demo"
mkdir -p "$rospec"
chmod u-w "$rospec"
rc=0
err=$(/bin/bash "$LOCK" acquire "$rospec" 2>&1 >/dev/null) || rc=$?
chmod u+w "$rospec" # restore so the trap cleanup can remove it
if [ "$rc" = 0 ]; then
  # Running as root bypasses the directory-write check; the failure mode is
  # unobservable, so skip rather than assert a false negative.
  echo "skip: unwritable-dir case (create succeeded — likely running as root)"
else
  [ "$rc" = 2 ] || fail "unwritable spec dir: exit $rc, expected 2 (real error, not busy)"
  case $err in
    *"cannot create"*) ;;
    *) fail "unwritable spec dir: missing diagnostic (got: $err)" ;;
  esac
  echo "ok: a non-contention create failure fails closed (exit 2) with a diagnostic"
fi

# 9. --owner-pid is validated as data, like every other argument here.
for bad in 'not-a-pid' '' '0'; do
  rc=0
  err=$(/bin/bash "$LOCK" acquire "$spec" --owner-pid "$bad" 2>&1 >/dev/null) || rc=$?
  [ "$rc" = 2 ] || fail "owner pid '$bad': exit $rc, expected 2"
  case $err in
    *"must be a non-zero number"*) ;;
    *) fail "owner pid '$bad': missing diagnostic (got: $err)" ;;
  esac
  if [ -L "$lock" ] || [ -e "$lock" ]; then
    fail "owner pid '$bad': a lock was taken anyway"
  fi
done
rc=0
err=$(/bin/bash "$LOCK" acquire "$spec" --frobnicate 2>&1 >/dev/null) || rc=$?
[ "$rc" = 2 ] || fail "unknown option: exit $rc, expected 2"
echo "ok: an empty, zero or malformed --owner-pid and an unknown option are clean refusals"

# 10. REQ-F1.1: the lock path is derived from a grammar-validated spec id. A
#     spec dir whose id fails the spec-id grammar (`^[a-z0-9][a-z0-9-]*$`) is a
#     clean refusal (exit 2, diagnostic, no lock created) — hostile/malformed
#     input is never used to build an on-disk lock path.
badspec="$tmp/badid/specs/Bad_Spec"
mkdir -p "$badspec"
rc=0
err=$(/bin/bash "$LOCK" acquire "$badspec" 2>&1 >/dev/null) || rc=$?
[ "$rc" = 2 ] || fail "hostile spec id: exit $rc, expected 2 (clean refusal)"
[ ! -e "$badspec/.orchestrate.lock" ] || fail "hostile spec id: a lock was created"
case $err in
  *F1.1* | *refus*) ;;
  *) fail "hostile spec id: missing refusal diagnostic (got: $err)" ;;
esac
echo "ok: a spec id failing the grammar is refused (REQ-F1.1)"

# 11. REQ-F1.1 containment: a spec dir not located under a specs/ parent is
#     refused — the derived lock path must stay inside the spec tree.
loosespec="$tmp/loose/notspecs/demo"
mkdir -p "$loosespec"
rc=0
/bin/bash "$LOCK" acquire "$loosespec" >/dev/null 2>&1 || rc=$?
[ "$rc" = 2 ] || fail "non-specs parent: exit $rc, expected 2"
[ ! -e "$loosespec/.orchestrate.lock" ] || fail "non-specs parent: a lock was created"
echo "ok: a spec dir outside a specs/ parent is refused (REQ-F1.1)"

# 12. REQ-F1.1 containment *after canonicalization*: a spec dir that is a
#     symlink resolving outside any specs/ parent is refused — the physical
#     path, not the link path, decides containment, so an escaping symlink
#     cannot smuggle the lock out of the tree.
realout="$tmp/realout/demo" # canonical parent is realout, not specs
mkdir -p "$realout"
mkdir -p "$tmp/linked/specs"
ln -s "$realout" "$tmp/linked/specs/demo" # specs/demo -> .../realout/demo
rc=0
/bin/bash "$LOCK" acquire "$tmp/linked/specs/demo" >/dev/null 2>&1 || rc=$?
[ "$rc" = 2 ] || fail "escaping symlink: exit $rc, expected 2"
[ ! -e "$realout/.orchestrate.lock" ] || fail "escaping symlink: lock created outside the tree"
echo "ok: a spec dir symlinked outside a specs/ parent is refused (REQ-F1.1)"

# 13. REQ-F1.1 length cap: a spec id whose charset is valid but whose length
#     exceeds the 64-char bound is its own refusal branch (separate from the
#     grammar and containment checks). A 65-char all-valid id under a specs/
#     parent must be a clean refusal (exit 2, diagnostic naming the bound, no
#     lock created) — the length branch is exercised in isolation here.
longid=$(printf 'a%.0s' {1..65}) # 65 valid chars: trips only the >64 cap
longspec="$tmp/longid/specs/$longid"
mkdir -p "$longspec"
rc=0
err=$(/bin/bash "$LOCK" acquire "$longspec" 2>&1 >/dev/null) || rc=$?
[ "$rc" = 2 ] || fail "over-length spec id: exit $rc, expected 2 (clean refusal)"
[ ! -e "$longspec/.orchestrate.lock" ] || fail "over-length spec id: a lock was created"
case $err in
  *64*) ;;
  *) fail "over-length spec id: diagnostic does not name the 64-char bound (got: $err)" ;;
esac
echo "ok: a spec id exceeding 64 chars is refused (REQ-F1.1)"

echo "PASS: orchestrate-lock"
