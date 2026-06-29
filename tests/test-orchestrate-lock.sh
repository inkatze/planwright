#!/bin/bash
# Tests for scripts/orchestrate-lock.sh — the per-spec advisory lock behind
# /orchestrate's state moves (Task 13, REQ-F1.3, D-10).
#
# Lock contract (REQ-F1.3, and risk-register row 18: the path + mkdir
# protocol MUST match tasks-pr-sync.sh so the two writers exclude each other):
#   - acquire creates <spec-dir>/.orchestrate.lock (mkdir, atomic);
#   - a second acquire on a fresh lock is a clean no-op (exit 1), lock intact;
#   - release removes the lock and is idempotent;
#   - a lock older than stale_lock_threshold is broken and re-acquired;
#   - the local stale_lock_threshold override is honored (a huge value keeps
#     an old lock busy); a malformed override falls back to 15m with a warning.
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

# Fixture: a <repo>/specs/<spec> layout so the local-config lookup resolves
# to <repo>/.claude/planwright.local.yml the way it will in a real checkout.
repo="$tmp/repo"
spec="$repo/specs/demo"
mkdir -p "$spec" "$repo/.claude"
lockdir="$spec/.orchestrate.lock"

# 1. Acquire on a fresh spec creates the canonical lock path.
/bin/bash "$LOCK" acquire "$spec" || fail "fresh acquire: non-zero exit"
[ -d "$lockdir" ] || fail "fresh acquire: lock dir not created at the canonical path"
echo "ok: acquire creates <spec-dir>/.orchestrate.lock"

# 2. A second acquire on the held lock is a clean no-op (exit 1), intact.
rc=0
/bin/bash "$LOCK" acquire "$spec" >/dev/null 2>&1 || rc=$?
[ "$rc" = 1 ] || fail "busy acquire: exit $rc, expected 1"
[ -d "$lockdir" ] || fail "busy acquire: lock disappeared"
echo "ok: a busy lock is a clean no-op (exit 1)"

# 3. Release removes the lock and is idempotent.
/bin/bash "$LOCK" release "$spec" || fail "release: non-zero exit"
[ ! -d "$lockdir" ] || fail "release: lock not removed"
/bin/bash "$LOCK" release "$spec" || fail "release (idempotent): non-zero exit"
echo "ok: release removes the lock and is idempotent"

# 4. A stale lock (mtime in 2020) is broken and re-acquired at the default
#    threshold.
mkdir "$lockdir"
touch -t 202001010000 "$lockdir"
/bin/bash "$LOCK" acquire "$spec" || fail "stale acquire: non-zero exit"
[ -d "$lockdir" ] || fail "stale acquire: lock missing after re-acquire"
[ -z "$(find "$lockdir" -maxdepth 0 -mmin +60 2>/dev/null)" ] \
  || fail "stale acquire: lock mtime not refreshed (not re-created)"
/bin/bash "$LOCK" release "$spec"
echo "ok: a stale lock is broken and re-acquired"

# 5. A huge local override keeps the 2020 lock busy.
printf 'stale_lock_threshold: 99999999m\n' >"$repo/.claude/planwright.local.yml"
mkdir "$lockdir"
touch -t 202001010000 "$lockdir"
rc=0
/bin/bash "$LOCK" acquire "$spec" >/dev/null 2>&1 || rc=$?
[ "$rc" = 1 ] || fail "override acquire: exit $rc, expected 1 (lock held by huge threshold)"
[ -d "$lockdir" ] || fail "override acquire: lock wrongly broken"
echo "ok: a local stale_lock_threshold override is honored"

# 6. A malformed override falls back to 15m with a warning; the 2020 lock is
#    stale at 15m and is broken.
printf 'stale_lock_threshold: banana\n' >"$repo/.claude/planwright.local.yml"
err=$(/bin/bash "$LOCK" acquire "$spec" 2>&1 >/dev/null) || fail "malformed acquire: non-zero exit"
[ -d "$lockdir" ] || fail "malformed acquire: stale lock not broken under the default fallback"
case $err in
  *"malformed stale_lock_threshold"*) ;;
  *) fail "malformed acquire: missing fallback warning (got: $err)" ;;
esac
echo "ok: a malformed threshold warns and falls back to the default"

# 7. A non-contention mkdir failure (unwritable spec dir / filesystem error)
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
  echo "skip: unwritable-dir case (mkdir succeeded — likely running as root)"
else
  [ "$rc" = 2 ] || fail "unwritable spec dir: exit $rc, expected 2 (real error, not busy)"
  case $err in
    *"cannot create"*) ;;
    *) fail "unwritable spec dir: missing diagnostic (got: $err)" ;;
  esac
  echo "ok: a non-contention mkdir failure fails closed (exit 2) with a diagnostic"
fi

# 8. REQ-F1.1: the lock path is derived from a grammar-validated spec id. A
#    spec dir whose id fails the spec-id grammar (`^[a-z0-9][a-z0-9-]*$`) is a
#    clean refusal (exit 2, diagnostic, no lock created) — hostile/malformed
#    input is never used to build an on-disk lock path.
badspec="$tmp/badid/specs/Bad_Spec"
mkdir -p "$badspec"
rc=0
err=$(/bin/bash "$LOCK" acquire "$badspec" 2>&1 >/dev/null) || rc=$?
[ "$rc" = 2 ] || fail "hostile spec id: exit $rc, expected 2 (clean refusal)"
[ ! -d "$badspec/.orchestrate.lock" ] || fail "hostile spec id: a lock was created"
case $err in
  *F1.1* | *refus*) ;;
  *) fail "hostile spec id: missing refusal diagnostic (got: $err)" ;;
esac
echo "ok: a spec id failing the grammar is refused (REQ-F1.1)"

# 9. REQ-F1.1 containment: a spec dir not located under a specs/ parent is
#    refused — the derived lock path must stay inside the spec tree.
loosespec="$tmp/loose/notspecs/demo"
mkdir -p "$loosespec"
rc=0
/bin/bash "$LOCK" acquire "$loosespec" >/dev/null 2>&1 || rc=$?
[ "$rc" = 2 ] || fail "non-specs parent: exit $rc, expected 2"
[ ! -d "$loosespec/.orchestrate.lock" ] || fail "non-specs parent: a lock was created"
echo "ok: a spec dir outside a specs/ parent is refused (REQ-F1.1)"

# 10. REQ-F1.1 containment *after canonicalization*: a spec dir that is a
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
[ ! -d "$realout/.orchestrate.lock" ] || fail "escaping symlink: lock created outside the tree"
echo "ok: a spec dir symlinked outside a specs/ parent is refused (REQ-F1.1)"

echo "PASS: orchestrate-lock"
