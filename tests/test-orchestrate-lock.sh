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
/bin/bash "$LOCK" release "$spec" --owner-pid "$$"
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

# 14. The sweep: a detached hold is cleared ONLY on positive evidence that its
#     holder is gone, and left alone otherwise.
#
#     This is the half of the liveness rule a detached hold cannot answer for
#     itself. /orchestrate holds across tool calls, so no process of its own is
#     running to probe; if the session then dies, the lock stands and every
#     later dispatch reads it as contention and skips the spec — silently,
#     because contention is a clean no-op. The sweep is where the proof lives,
#     and it is held to the same bar every other destructive mechanism here
#     meets: the recorded holder is demonstrably gone, never merely unobserved,
#     and never a length of time.
sweepspec="$repo/specs/demo"
evid="$tmp/evidence.sh"
cat >"$evid" <<'EVID'
#!/bin/sh
# Stand-in for fleet-death-evidence.sh: the verdict is whatever the fixture
# wrote, so each leg pins one verdict rather than the host's process table.
printf '%s
' "$(cat "$EVIDENCE_VERDICT_FILE")"
case $(cat "$EVIDENCE_VERDICT_FILE") in
  dead) exit 0 ;;
  alive) exit 1 ;;
  *) exit 3 ;;
esac
EVID
chmod +x "$evid"
verdict_file="$tmp/verdict"

sweep() {
  rc=0
  out=$(EVIDENCE_VERDICT_FILE="$verdict_file" \
    PLANWRIGHT_TOWER_EVIDENCE_CMD="$evid" \
    /bin/bash "$LOCK" sweep "$sweepspec" 2>/dev/null) || rc=$?
}

# A free path has nothing to sweep.
/bin/bash "$LOCK" release "$sweepspec"
sweep
[ "$rc" = 0 ] || fail "sweep on a free path: exit $rc, expected 0"
[ "$out" = no-lock ] || fail "sweep on a free path said '$out', expected no-lock"

# A PROCESS-OWNED hold is not the sweep's business: the primitive breaks it
# itself the moment its owner is gone.
sleep 120 &
live_pid=$!
/bin/bash "$LOCK" acquire "$sweepspec" --owner-pid "$live_pid" || fail "sweep fixture: owned acquire failed"
sweep
[ "$out" = owned ] || fail "sweep over an owned hold said '$out', expected owned"
[ -L "$sweepspec/.orchestrate.lock" ] || fail "sweep over an owned hold cleared it"
kill "$live_pid" 2>/dev/null || true
wait "$live_pid" 2>/dev/null || true
/bin/bash "$LOCK" break "$sweepspec"

# A detached hold the acquire could not attribute to anything: no evidence is
# establishable, so the sweep refuses and says which.
env -u PLANWRIGHT_TOWER_PID -u TMUX -u TMUX_PANE \
  /bin/bash "$LOCK" acquire "$sweepspec" || fail "sweep fixture: detached acquire failed"
sweep
[ "$rc" = 3 ] || fail "sweep over an unattributed hold: exit $rc, expected 3"
[ "$out" = unattributed ] || fail "sweep over an unattributed hold said '$out'"
[ -L "$sweepspec/.orchestrate.lock" ] || fail "sweep cleared a hold it could not judge"
/bin/bash "$LOCK" release "$sweepspec"

# THE REAL SCENARIO, both directions. A tower holds the spec lock across its
# dispatch window; it could name itself only by the tmux window it occupies,
# which is a death-evidence class but not a pid, so the hold stays detached and
# the handle is recorded beside it for the sweep to resolve.
env -u PLANWRIGHT_TOWER_PID -u TMUX -u TMUX_PANE \
  /bin/bash "$LOCK" acquire "$sweepspec" || fail "sweep fixture: detached acquire failed"
held_token=$(readlink "$sweepspec/.orchestrate.lock")
printf '%s\ttmux-window planwright 3\n' "$held_token" >"$sweepspec/.orchestrate.lock#owner#"

# Holder still running: untouched, whatever else is true.
printf 'alive\n' >"$verdict_file"
sweep
[ "$rc" = 1 ] || fail "sweep over a live holder: exit $rc, expected 1"
[ "$out" = alive ] || fail "sweep over a live holder said '$out', expected alive"
[ -L "$sweepspec/.orchestrate.lock" ] || fail "sweep cleared a live holder's lock"

# The query mechanism cannot answer: lost observability is not observed death.
printf 'unknown\n' >"$verdict_file"
sweep
[ "$rc" = 3 ] || fail "sweep with no answer: exit $rc, expected 3"
[ "$out" = unknown ] || fail "sweep with no answer said '$out', expected unknown"
[ -L "$sweepspec/.orchestrate.lock" ] || fail "sweep cleared a lock it could not judge"

# A record that does not describe the holder now at the path is not evidence
# about it: a stale one is read as absent rather than acted on.
printf 'dead\n' >"$verdict_file"
printf 'some-other-token\ttmux-window planwright 3\n' >"$sweepspec/.orchestrate.lock#owner#"
sweep
[ "$out" = unattributed ] || fail "sweep honoured a record for a different token ('$out')"
[ -L "$sweepspec/.orchestrate.lock" ] || fail "sweep cleared a lock on a stale record"
printf '%s\ttmux-window planwright 3\n' "$held_token" >"$sweepspec/.orchestrate.lock#owner#"

# Holder demonstrably gone: cleared, and the path is usable again.
sweep
[ "$rc" = 0 ] || fail "sweep over a dead holder: exit $rc, expected 0"
[ "$out" = cleared ] || fail "sweep over a dead holder said '$out', expected cleared"
if [ -L "$sweepspec/.orchestrate.lock" ] || [ -e "$sweepspec/.orchestrate.lock" ]; then
  fail "sweep reported cleared but the lock is still there"
fi
[ ! -e "$sweepspec/.orchestrate.lock#owner#" ] || fail "sweep left the attribution record behind"
/bin/bash "$LOCK" acquire "$sweepspec" || fail "the spec is still undispatchable after the sweep"
/bin/bash "$LOCK" release "$sweepspec"
# A handle is split into the words the predicate takes, and a tmux window can
# legally be named `*`. Splitting with globbing live would expand it against
# the working directory and hand the predicate a list of filenames instead.
printf 'dead\n' >"$verdict_file"
argv_probe="$tmp/argv.sh"
cat >"$argv_probe" <<'ARGV'
#!/bin/sh
printf '%s\n' "$#" >"$ARGV_OUT"
for a in "$@"; do printf '%s\n' "$a" >>"$ARGV_OUT"; done
exit 0
ARGV
chmod +x "$argv_probe"
env -u PLANWRIGHT_TOWER_PID -u TMUX -u TMUX_PANE \
  /bin/bash "$LOCK" acquire "$sweepspec" || fail "glob fixture: detached acquire failed"
glob_token=$(readlink "$sweepspec/.orchestrate.lock")
printf '%s\ttmux-window * 3\n' "$glob_token" >"$sweepspec/.orchestrate.lock#owner#"
# Files in the working directory the split would pick up if it expanded.
mkdir -p "$tmp/globdir" && : >"$tmp/globdir/decoy-one" && : >"$tmp/globdir/decoy-two"
(cd "$tmp/globdir" && ARGV_OUT="$tmp/argv.out" EVIDENCE_VERDICT_FILE="$verdict_file" \
  PLANWRIGHT_TOWER_EVIDENCE_CMD="$argv_probe" \
  /bin/bash "$LOCK" sweep "$sweepspec" >/dev/null 2>&1) || true
[ -f "$tmp/argv.out" ] || fail "glob case: the evidence command was never reached"
argv_n=$(sed -n 1p "$tmp/argv.out")
[ "$argv_n" = 3 ] || fail "glob case: the predicate got $argv_n arguments, expected 3 (the handle expanded)"
[ "$(sed -n 3p "$tmp/argv.out")" = '*' ] \
  || fail "glob case: the window name reached the predicate as '$(sed -n 3p "$tmp/argv.out")', expected the literal *"
/bin/bash "$LOCK" release "$sweepspec"
# The window field recorded here must be one the death predicate actually
# matches on. It lists `#{window_id}` and `#{window_name}` and compares the
# handle's second argument against those two; a `#{window_index}` matches
# neither, so a live window would be reported DEAD and the sweep would clear a
# lock whose holder is still running. Pinned across the two files, because the
# bug is the disagreement and neither file is wrong on its own.
evid_fields=$(grep -o "#{window_[a-z]*}" "$here/../scripts/fleet-death-evidence.sh" | sort -u)
asked=$(grep -o "#{window_[a-z]*}" "$LOCK" | sort -u)
[ -n "$evid_fields" ] || fail "window-field pin: found no window fields in fleet-death-evidence.sh"
[ -n "$asked" ] || fail "window-field pin: orchestrate-lock.sh asks tmux for no window field"
for f in $asked; do
  case "$evid_fields" in
    *"$f"*) ;;
    *) fail "window-field pin: the handle records $f, which fleet-death-evidence.sh never matches on (it matches: $(printf '%s' "$evid_fields" | tr '\n' ' '))" ;;
  esac
done
echo "ok: the recorded window field is one the death predicate matches on"

echo "ok: a handle is split into words without expanding against the filesystem"

echo "ok: the sweep clears a detached hold whose holder is gone, and only then"

# 15. An attributed tower hold needs no sweep at all: naming a live process as
#     the owner makes it an ordinary hold, which the primitive breaks by itself
#     once that process is gone.
sleep 120 &
tower_pid=$!
PLANWRIGHT_TOWER_PID="$tower_pid" /bin/bash "$LOCK" acquire "$sweepspec" \
  || fail "attributed acquire failed"
case "$(readlink "$sweepspec/.orchestrate.lock")" in
  "$tower_pid"-*) ;;
  *) fail "an attributed hold is not owned by the tower (target: $(readlink "$sweepspec/.orchestrate.lock"))" ;;
esac
rc=0
/bin/bash "$LOCK" acquire "$sweepspec" >/dev/null 2>&1 || rc=$?
[ "$rc" = 1 ] || fail "attributed hold: a peer got exit $rc, expected 1 while the tower runs"
kill "$tower_pid" 2>/dev/null || true
wait "$tower_pid" 2>/dev/null || true
/bin/bash "$LOCK" acquire "$sweepspec" --owner-pid "$$" \
  || fail "attributed hold: not broken once the tower is gone"
/bin/bash "$LOCK" release "$sweepspec" --owner-pid "$$"
echo "ok: a hold attributed to a live tower is an ordinary hold and self-heals"

# 16. `release` verifies what it can; `break` is the unconditional clear.
#
#    `release` used to be unconditional, which was sound while nothing cleared
#    a live-looking hold. The sweep changed that: it clears A, B acquires, and
#    A's delayed release then deletes B's lock while B still believes it holds
#    it. Both properties are wanted — a hold whose owner is gone must still be
#    clearable, or the wedge returns — so they are two verbs now, and `release`
#    refuses whenever it can show the lock is not the one its caller took.
relspec="$repo/specs/demo"
/bin/bash "$LOCK" release "$relspec" >/dev/null 2>&1

# Its own hold: cleared.
/bin/bash "$LOCK" acquire "$relspec" --owner-pid "$$" || fail "release fixture: acquire failed"
/bin/bash "$LOCK" release "$relspec" --owner-pid "$$" || fail "release of its own hold was refused"
[ ! -L "$relspec/.orchestrate.lock" ] || fail "release of its own hold left the lock"

# Somebody else's live hold: refused, and left exactly as found.
sleep 120 &
other_pid=$!
/bin/bash "$LOCK" acquire "$relspec" --owner-pid "$other_pid" || fail "release fixture: foreign acquire failed"
foreign_token=$(readlink "$relspec/.orchestrate.lock")
rc=0
/bin/bash "$LOCK" release "$relspec" >/dev/null 2>&1 || rc=$?
[ "$rc" = 1 ] || fail "release over a live foreign hold: exit $rc, expected 1"
[ "$(readlink "$relspec/.orchestrate.lock")" = "$foreign_token" ] \
  || fail "release deleted a live foreign hold"
rc=0
/bin/bash "$LOCK" release "$relspec" --owner-pid "$$" >/dev/null 2>&1 || rc=$?
[ "$rc" = 1 ] || fail "release claiming the wrong owner: exit $rc, expected 1"
[ "$(readlink "$relspec/.orchestrate.lock")" = "$foreign_token" ] \
  || fail "release claiming the wrong owner still deleted the lock"

# `break` is the recovery verb and is unconditional by design.
/bin/bash "$LOCK" break "$relspec" || fail "break over a live foreign hold was refused"
[ ! -L "$relspec/.orchestrate.lock" ] || fail "break left the lock"
kill "$other_pid" 2>/dev/null || true
wait "$other_pid" 2>/dev/null || true

# A hold whose owner is gone is still cleared by release: the recovery path
# that the wedge depends on does not regress.
sh -c 'exit 0' &
gone_pid=$!
wait "$gone_pid" 2>/dev/null || true
ln -s "$gone_pid-0-0-1" "$relspec/.orchestrate.lock"
/bin/bash "$LOCK" release "$relspec" || fail "release over an absent owner was refused"
[ ! -L "$relspec/.orchestrate.lock" ] || fail "release over an absent owner left the lock"

# A detached hold whose recorded handle is demonstrably ALIVE is refused: that
# is a holder this call can show is not itself.
env -u PLANWRIGHT_TOWER_PID -u TMUX -u TMUX_PANE \
  /bin/bash "$LOCK" acquire "$relspec" || fail "release fixture: detached acquire failed"
det_token=$(readlink "$relspec/.orchestrate.lock")
printf '%s\ttmux-window planwright %%9\n' "$det_token" >"$relspec/.orchestrate.lock#owner#"
printf 'alive\n' >"$verdict_file"
rc=0
EVIDENCE_VERDICT_FILE="$verdict_file" PLANWRIGHT_TOWER_EVIDENCE_CMD="$evid" \
  /bin/bash "$LOCK" release "$relspec" >/dev/null 2>&1 || rc=$?
[ "$rc" = 1 ] || fail "release over a detached hold with a live handle: exit $rc, expected 1"
[ "$(readlink "$relspec/.orchestrate.lock")" = "$det_token" ] \
  || fail "release deleted a detached hold whose handle is alive"
/bin/bash "$LOCK" break "$relspec"

# A detached hold with nothing recorded is the one case nothing distinguishes,
# and the frozen caller depends on being able to release it.
env -u PLANWRIGHT_TOWER_PID -u TMUX -u TMUX_PANE \
  /bin/bash "$LOCK" acquire "$relspec" || fail "release fixture: second detached acquire failed"
/bin/bash "$LOCK" release "$relspec" || fail "release of an unattributed detached hold was refused"
[ ! -L "$relspec/.orchestrate.lock" ] || fail "release of an unattributed detached hold left the lock"
echo "ok: release refuses a hold it can show is not its own; break stays unconditional"

echo "PASS: orchestrate-lock"
