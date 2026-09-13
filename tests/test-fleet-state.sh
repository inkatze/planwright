#!/bin/bash
# Tests for scripts/fleet-state.sh — the CROSS-SPEC fleet-coordination-state
# home, its worker/scope registry store, and the named concurrency-control
# primitive Task 6 (fleet bound) and Task 12 (registry) consume
# (orchestration-fleet Task 9; D-11, REQ-D1.6, REQ-A1.6).
#
# Contract under test (REQ-D1.6):
#   - the cross-spec fleet-state root resolves in both delivery modes (plugin
#     via ${CLAUDE_PLUGIN_DATA}, and writer via <claude-dir>/planwright/<name>)
#     and survives a simulated plugin-version change (it derives from the
#     version-stable data home, not the versioned install root);
#   - distinct plugin namespaces resolve to distinct roots;
#   - the worker/scope registry round-trips a record;
#   - the named concurrency-control primitive serializes concurrent registry
#     writes and the fleet-bound check-and-increment, so two concurrent towers
#     produce no torn record and no over-count past the bound;
#   - no fleet path writes into the sibling's spec-local .orchestrate/ dir;
#   - hostile identifiers are rejected before any path use.
#
# Hermetic: every case sets the resolution env explicitly (no ambient HOME /
# CLAUDE_DIR / CLAUDE_PLUGIN_* leak), so the suite is reproducible on a
# developer box and on CI alike. Runs standalone under /bin/bash (bash 3.2).
#
# THE LOCK FIXTURES, and what each token means. The lock is a symlink whose
# target is the owner token, and staleness is the OWNER PROCESS's absence, never
# an age — so a fixture chooses which case it wants by choosing a token, and no
# case back-dates anything:
#   - `detached-<n>-<n>`  a hold with no owning process, the shape the exposed
#                         `lock` verb takes. Always reads alive, so it is never
#                         auto-broken: this is how a case holds the lock.
#   - `$$-<n>-<n>`        owned by this still-running test shell: also live.
#   - `crashed-holder`    no probeable pid, so the owner is absent: breakable.
set -eu
LC_ALL=C
export LC_ALL
unset CDPATH

here=$(cd "$(dirname "$0")" && pwd)
FS="$here/../scripts/fleet-state.sh"

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

[ -x "$FS" ] || fail "scripts/fleet-state.sh missing or not executable"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
tab=$(printf '\t')

# A clean environment for a resolution call: strip every ambient knob the
# resolver reads, then let the caller set exactly what the case exercises.
run_root() {
  env -u PLANWRIGHT_FLEET_STATE_DIR -u CLAUDE_PLUGIN_DATA \
    -u CLAUDE_PLUGIN_ROOT -u CLAUDE_DIR -u HOME -u PLANWRIGHT_ROOT \
    "$@" /bin/sh "$FS" root
}

# ---------------------------------------------------------------------------
# 1. Plugin mode: the root derives from ${CLAUDE_PLUGIN_DATA} (the version-
#    stable per-plugin data home), under a fleet/ leaf.
# ---------------------------------------------------------------------------
data="$tmp/plugins/data/planwright-planwright"
mkdir -p "$data"
root=$(run_root CLAUDE_PLUGIN_DATA="$data") || fail "plugin-mode: root did not resolve"
case $root in
  "$data"/fleet) ;;
  *) fail "plugin-mode: root '$root' not under \$CLAUDE_PLUGIN_DATA/fleet" ;;
esac
echo "ok: plugin-mode root resolves under \$CLAUDE_PLUGIN_DATA/fleet"

# ---------------------------------------------------------------------------
# 2. Writer mode: no ${CLAUDE_PLUGIN_DATA}; derive the namespace from the
#    plugin manifest name under <claude-dir>/planwright.
# ---------------------------------------------------------------------------
cdir="$tmp/writer/.claude"
mkdir -p "$cdir/planwright"
printf '%s\n' '{ "name": "planwright", "version": "0.0.0" }' >"$cdir/planwright/plugin.json"
root=$(run_root CLAUDE_DIR="$cdir") || fail "writer-mode: root did not resolve"
case $root in
  "$cdir"/planwright/planwright/fleet) ;;
  *) fail "writer-mode: root '$root' not at <claude-dir>/planwright/<name>/fleet" ;;
esac
echo "ok: writer-mode root resolves under <claude-dir>/planwright/<name>/fleet"

# ---------------------------------------------------------------------------
# 2b. Writer-mode manifest parse skips a NESTED object's `name` (e.g.
#     author.name) and captures only the TOP-LEVEL name. This is exactly what
#     the brace-depth tracking in resolve_root exists for; without a case it
#     was the script's most complex logic left unpinned.
# ---------------------------------------------------------------------------
cdir_nested="$tmp/nested/.claude"
mkdir -p "$cdir_nested/planwright"
printf '%s\n' '{ "author": { "name": "not-the-plugin" }, "name": "planwright" }' \
  >"$cdir_nested/planwright/plugin.json"
root=$(run_root CLAUDE_DIR="$cdir_nested") || fail "nested-manifest: root did not resolve"
case $root in
  "$cdir_nested"/planwright/planwright/fleet) ;;
  *) fail "nested-manifest: captured the wrong name (root '$root')" ;;
esac
echo "ok: writer-mode manifest parse skips a nested name, captures the top-level name"

# ---------------------------------------------------------------------------
# 3. Survives a simulated plugin-version change: with the data home fixed, the
#    resolved root does not move when the versioned install root changes.
# ---------------------------------------------------------------------------
root_v1=$(run_root CLAUDE_PLUGIN_DATA="$data" \
  CLAUDE_PLUGIN_ROOT="$tmp/cache/planwright/0.2.6") || fail "version-change: v1 resolve"
root_v2=$(run_root CLAUDE_PLUGIN_DATA="$data" \
  CLAUDE_PLUGIN_ROOT="$tmp/cache/planwright/0.3.0") || fail "version-change: v2 resolve"
[ "$root_v1" = "$root_v2" ] || fail "version-change: root moved ($root_v1 != $root_v2)"
echo "ok: root survives a simulated plugin-version change"

# ---------------------------------------------------------------------------
# 4. Distinct plugin namespaces resolve to distinct roots (both modes).
# ---------------------------------------------------------------------------
ra=$(run_root CLAUDE_PLUGIN_DATA="$tmp/plugins/data/ns-a") || fail "ns: a resolve"
rb=$(run_root CLAUDE_PLUGIN_DATA="$tmp/plugins/data/ns-b") || fail "ns: b resolve"
[ "$ra" != "$rb" ] || fail "distinct data namespaces collapsed to one root ($ra)"

cdir2="$tmp/writer2/.claude"
mkdir -p "$cdir2/planwright"
printf '%s\n' '{ "name": "planwright-fork" }' >"$cdir2/planwright/plugin.json"
rw=$(run_root CLAUDE_DIR="$cdir2") || fail "ns: writer-fork resolve"
root_w1=$(run_root CLAUDE_DIR="$cdir") || fail "ns: writer-base resolve"
[ "$rw" != "$root_w1" ] || fail "distinct writer manifest names collapsed to one root ($rw)"
echo "ok: distinct plugin namespaces resolve to distinct roots"

# ---------------------------------------------------------------------------
# 5. Explicit override is trusted verbatim (the operator/test knob).
# ---------------------------------------------------------------------------
override="$tmp/explicit-home"
root=$(run_root PLANWRIGHT_FLEET_STATE_DIR="$override" CLAUDE_PLUGIN_DATA="$data") \
  || fail "override: did not resolve"
[ "$root" = "$override" ] || fail "override not honored verbatim ('$root' != '$override')"
echo "ok: PLANWRIGHT_FLEET_STATE_DIR override wins, verbatim"

# From here on, drive a concrete fleet home via the override so the store /
# lock / counter cases are hermetic and independent of the resolution chain.
home="$tmp/fleet-home"
fenv() {
  env -u CLAUDE_PLUGIN_DATA -u CLAUDE_PLUGIN_ROOT -u CLAUDE_DIR -u HOME \
    PLANWRIGHT_FLEET_STATE_DIR="$home" /bin/sh "$FS" "$@"
}

# ---------------------------------------------------------------------------
# 6. The worker/scope registry round-trips a record.
# ---------------------------------------------------------------------------
fenv register "worker=alpha" "orchestration-fleet" || fail "register: non-zero exit"
out=$(fenv registry) || fail "registry: non-zero exit"
printf '%s\n' "$out" | grep -q "worker=alpha" || fail "registry: worker not round-tripped"
printf '%s\n' "$out" | grep -q "orchestration-fleet" || fail "registry: scope not round-tripped"
echo "ok: the registry round-trips a worker/scope record"

# ---------------------------------------------------------------------------
# 7. No fleet path writes into the sibling's spec-local .orchestrate/ dir, and
#    the fleet home is not itself under a specs/ tree.
# ---------------------------------------------------------------------------
case $home in
  */specs/*) fail "fleet home '$home' sits under a specs/ tree (sibling territory)" ;;
  *.orchestrate*) fail "fleet home '$home' collides with the sibling .orchestrate namespace" ;;
esac
[ ! -e "$home/.orchestrate" ] || fail "fleet writes created a sibling .orchestrate dir"
find "$home" -name '.orchestrate' -print 2>/dev/null | grep -q . \
  && fail "a fleet path wrote into a .orchestrate dir"
echo "ok: no fleet path writes into the sibling .orchestrate/ dir"

# ---------------------------------------------------------------------------
# 8. Concurrency — the named primitive serializes concurrent registry writes:
#    N concurrent registers produce exactly N well-formed (untorn) records.
# ---------------------------------------------------------------------------
home_reg="$tmp/reg-race"
N=20
i=0
reg_pids=""
while [ "$i" -lt "$N" ]; do
  env -u CLAUDE_PLUGIN_DATA -u CLAUDE_DIR -u HOME \
    PLANWRIGHT_FLEET_STATE_DIR="$home_reg" \
    /bin/sh "$FS" register "worker=w$i" "spec-$i" &
  reg_pids="$reg_pids $!"
  i=$((i + 1))
done
# Track PIDs and check each exit status: a bare `wait` returns only the last
# job's status, so a register that exited non-zero under contention would go
# unnoticed (repo idiom, cf. tests/test-tasks-pr-sync.sh). Every register must
# succeed here — none should fail — so any non-zero exit is a real regression.
reg_rc=0
for p in $reg_pids; do
  wait "$p" || reg_rc=1
done
[ "$reg_rc" = 0 ] || fail "registry race: a concurrent register exited non-zero under contention"
lines=$(wc -l <"$home_reg/registry" | tr -d ' ')
[ "$lines" = "$N" ] || fail "registry race: $lines records, expected $N (lost or torn writes)"
# Every record is well-formed: the seven-field dispatch record
# <epoch> <worker> <scope> <owner> <backend> <state-dir> <death-handle>, with
# `-` in every column this two-argument register left unsupplied. A torn write
# would break the field count on some line.
malformed=$(awk -F"$tab" 'NF != 7 || $1 !~ /^[0-9]+$/ { c++ } END { print c + 0 }' "$home_reg/registry")
[ "$malformed" = "0" ] || fail "registry race: $malformed torn/malformed records"
distinct=$(cut -f2 "$home_reg/registry" | sort -u | wc -l | tr -d ' ')
[ "$distinct" = "$N" ] || fail "registry race: $distinct distinct workers, expected $N"
echo "ok: concurrent registry writes are serialized (no torn records, none lost)"

# ---------------------------------------------------------------------------
# 8b. The record's timestamp is stamped UNDER the lock (commit time), not at
#     invocation. Deterministic proof: hold the lock, launch a register that
#     blocks on it, let the wall clock advance past a 1s boundary, then release.
#     A commit-time stamp is taken only after the release, so it is >= the
#     release time; an invocation-time stamp (captured before the block) would
#     predate the release and fail this assertion.
# ---------------------------------------------------------------------------
home_ts="$tmp/ts-home"
mkdir -p "$home_ts"
ln -s "detached-1-1" "$home_ts/.fleet.lock" # a detached hold: never auto-broken, so register must block
env -u CLAUDE_PLUGIN_DATA -u CLAUDE_DIR -u HOME \
  PLANWRIGHT_FLEET_STATE_DIR="$home_ts" \
  /bin/sh "$FS" register "worker=late" "scope-late" &
reg_pid=$!
sleep 2 # advance the clock while register is blocked on the held lock
t_release=$(date +%s)
rm -f "$home_ts/.fleet.lock" # release; register now acquires and stamps
wait "$reg_pid" || fail "blocked register did not complete after lock release"
rec_ts=$(cut -f1 "$home_ts/registry")
case $rec_ts in
  "" | *[!0-9]*) fail "registry timestamp '$rec_ts' is not numeric" ;;
esac
[ "$rec_ts" -ge "$t_release" ] \
  || fail "register timestamp ($rec_ts) predates lock release ($t_release): stamped at invocation, not under the lock"
echo "ok: the register timestamp is stamped under the lock (commit time, monotonic append order)"

# ---------------------------------------------------------------------------
# 9. Concurrency — the fleet-bound check-and-increment cannot over-count:
#    with a bound of MAX, N concurrent increments yield exactly MAX successes
#    and the counter lands on exactly MAX (no two towers exceed the bound).
# ---------------------------------------------------------------------------
home_bound="$tmp/bound-race"
MAX=5
N=20
okdir="$tmp/bound-results"
rcdir="$tmp/bound-rcs"
errdir="$tmp/bound-errs"
mkdir -p "$okdir" "$rcdir" "$errdir"
i=0
bound_pids=""
while [ "$i" -lt "$N" ]; do
  (
    # Capture the exit code, the granted new-count (stdout on exit 0), and any
    # stderr, so the race proves not just that exactly MAX succeeded but that
    # every non-grant was a CLEAN at-bound refusal (exit 1 — which prints the
    # current count on stdout but is silent on stderr) — never a fail-closed
    # error (exit 2, e.g. spin_acquire budget exhaustion under
    # contention). A grant-count-only check would pass an exit-2 that landed on a
    # call which would have been refused anyway, as long as MAX grants still hit.
    # The subshell swallows bound-incr's own exit into the rc marker, so its OWN
    # exit is 0 unless a marker write fails (set -e) — which the PID check below
    # then surfaces as a harness failure rather than a confusing count mismatch.
    rc=0
    out=$(env -u CLAUDE_PLUGIN_DATA -u CLAUDE_DIR -u HOME \
      PLANWRIGHT_FLEET_STATE_DIR="$home_bound" \
      /bin/sh "$FS" bound-incr "$MAX" 2>"$errdir/$i") || rc=$?
    printf '%s\n' "$rc" >"$rcdir/$i"
    if [ "$rc" = 0 ]; then printf '%s\n' "$out" >"$okdir/$i"; fi
  ) &
  bound_pids="$bound_pids $!"
  i=$((i + 1))
done
# Track PIDs and check each exit status (repo idiom, cf.
# tests/test-tasks-pr-sync.sh): a bare `wait` returns only the last job's status,
# so a subshell that failed to write its rc/stderr marker would slip past.
bound_prc=0
for p in $bound_pids; do
  wait "$p" || bound_prc=1
done
[ "$bound_prc" = 0 ] || fail "bound race: a concurrent worker subshell exited non-zero (marker-write/harness failure)"
granted=$(find "$okdir" -type f | wc -l | tr -d ' ')
[ "$granted" = "$MAX" ] || fail "bound race: $granted grants, expected exactly $MAX (over/under-count)"
# Exit-code distribution: exactly MAX grants (exit 0) and N-MAX clean at-bound
# refusals (exit 1), with ZERO fail-closed errors (exit 2 or anything else) —
# this is what a grant-count-only assertion cannot see.
zeros=0
ones=0
others=0
for f in "$rcdir"/*; do
  case $(cat "$f") in
    0) zeros=$((zeros + 1)) ;;
    1) ones=$((ones + 1)) ;;
    *) others=$((others + 1)) ;;
  esac
done
[ "$zeros" = "$MAX" ] || fail "bound race: $zeros grants (exit 0), expected $MAX"
[ "$ones" = "$((N - MAX))" ] || fail "bound race: $ones clean refusals (exit 1), expected $((N - MAX))"
[ "$others" = 0 ] || fail "bound race: $others invocations failed closed (exit 2/other) under contention, expected 0"
# And none of them wrote to stderr: a clean grant and a clean at-bound refusal
# are both silent there; only a fail-closed error diagnoses to stderr.
errfiles=$(find "$errdir" -type f ! -empty)
[ -z "$errfiles" ] || fail "bound race: invocation(s) wrote to stderr under contention: $errfiles"
counter=$(cat "$home_bound/concurrency")
[ "$counter" = "$MAX" ] || fail "bound race: counter landed on $counter, expected $MAX"
# The MAX grants printed exactly the counts 1..MAX on stdout (the documented
# contract Task 6 consumes). A regression that stopped printing, printed the
# old value, or printed an empty line would break this even though the exit
# codes and the counter file stayed correct.
grants_printed=$(cat "$okdir"/* | sort -n | tr '\n' ' ')
expected_printed=""
c=1
while [ "$c" -le "$MAX" ]; do
  expected_printed="$expected_printed$c "
  c=$((c + 1))
done
[ "$grants_printed" = "$expected_printed" ] \
  || fail "bound race: grants printed '$grants_printed', expected '$expected_printed'"
echo "ok: the fleet-bound check-and-increment never over-counts under contention"

# At the bound, a further increment is REFUSED: it grants no slot, prints the
# current count (MAX) on stdout, and exits 1. The race above proved the granted
# calls print 1..MAX; this proves the refused call honors its own half of the
# contract (a regression printing an empty string or the wrong value, or exiting
# 0, would break a consumer that gates dispatch on this exit + count).
at_bound_rc=0
at_bound_out=$(env -u CLAUDE_PLUGIN_DATA -u CLAUDE_DIR -u HOME \
  PLANWRIGHT_FLEET_STATE_DIR="$home_bound" \
  /bin/sh "$FS" bound-incr "$MAX" 2>/dev/null) || at_bound_rc=$?
[ "$at_bound_rc" = 1 ] || fail "bound-incr at bound: exit $at_bound_rc, expected 1"
[ "$at_bound_out" = "$MAX" ] || fail "bound-incr at bound: printed '$at_bound_out', expected $MAX"
[ "$(cat "$home_bound/concurrency")" = "$MAX" ] || fail "bound-incr at bound mutated the counter"
echo "ok: bound-incr at the bound is refused, prints the current count, and exits 1"

# bound-decr releases a slot and floors at zero. Its own bound-home closure
# (benv), matching the per-home <mnemonic>env convention (cenv/lenv/henv) so no
# helper name is bound to two different homes across the suite.
benv() {
  env -u CLAUDE_PLUGIN_DATA -u CLAUDE_DIR -u HOME \
    PLANWRIGHT_FLEET_STATE_DIR="$home_bound" /bin/sh "$FS" "$@"
}
# bound-decr prints the new count on stdout (the documented contract Task 6
# consumes); assert the printed value, not only the counter file.
decr_out=$(benv bound-decr) || fail "bound-decr: non-zero exit"
[ "$decr_out" = "$((MAX - 1))" ] || fail "bound-decr printed '$decr_out', expected $((MAX - 1))"
[ "$(cat "$home_bound/concurrency")" = "$((MAX - 1))" ] || fail "bound-decr did not decrement"
c=$MAX
while [ "$c" -gt 0 ]; do
  benv bound-decr >/dev/null || fail "bound-decr drain"
  c=$((c - 1))
done
[ "$(cat "$home_bound/concurrency")" = "0" ] || fail "bound-decr floored below zero"
# The floored decr also prints 0 on stdout, not an empty string.
floor_out=$(benv bound-decr) || fail "bound-decr: floor exit"
[ "$floor_out" = "0" ] || fail "bound-decr at floor printed '$floor_out', expected 0"
echo "ok: bound-decr releases a slot, prints the new count, and floors at zero"

# ---------------------------------------------------------------------------
# 9b. A corrupt counter file with a leading-zero value is treated as malformed
#     (→ 0), NOT parsed as octal. Regression: `08`/`010` passed read_counter's
#     `*[!0-9]*` guard, reached `$(( ))` as octal, aborted bound-incr
#     mid-critical-section with "value too great for base", and LEAKED the lock
#     (wedging the fleet until a stale break). read_counter is the designated
#     sanitizer — it already maps "" and non-numeric to 0; a leading-zero value
#     must land there too. Covers both bound-incr and bound-decr.
# ---------------------------------------------------------------------------
home_corrupt="$tmp/corrupt-counter"
mkdir -p "$home_corrupt"
cenv() {
  env -u CLAUDE_PLUGIN_DATA -u CLAUDE_DIR -u HOME \
    PLANWRIGHT_FLEET_STATE_DIR="$home_corrupt" /bin/sh "$FS" "$@"
}
printf '08\n' >"$home_corrupt/concurrency"
out=$(cenv bound-incr 10) || fail "bound-incr crashed on a leading-zero counter (should treat it as 0)"
[ "$out" = "1" ] || fail "corrupt counter not treated as 0: bound-incr printed '$out', expected 1"
[ ! -L "$home_corrupt/.fleet.lock" ] && [ ! -e "$home_corrupt/.fleet.lock" ] \
  || fail "bound-incr leaked the lock on a corrupt counter"
[ "$(cat "$home_corrupt/concurrency")" = "1" ] || fail "corrupt-counter recovery did not land the increment at 1"
printf '09\n' >"$home_corrupt/concurrency"
out=$(cenv bound-decr) || fail "bound-decr crashed on a leading-zero counter (should treat it as 0)"
[ "$out" = "0" ] || fail "corrupt counter not treated as 0: bound-decr printed '$out', expected 0"
[ ! -L "$home_corrupt/.fleet.lock" ] && [ ! -e "$home_corrupt/.fleet.lock" ] \
  || fail "bound-decr leaked the lock on a corrupt counter"
echo "ok: a corrupt (leading-zero) counter is sanitized to 0 — no octal crash, no leaked lock"

# ---------------------------------------------------------------------------
# 10. The advisory-lock primitive: exclusive acquire, busy no-op, idempotent
#     release — the surface Task 6/12 consume for custom critical sections.
# ---------------------------------------------------------------------------
home_lock="$tmp/lock-home"
lenv() {
  env -u CLAUDE_PLUGIN_DATA -u CLAUDE_DIR -u HOME \
    PLANWRIGHT_FLEET_STATE_DIR="$home_lock" /bin/sh "$FS" "$@"
}
lock_token=$(lenv lock) || fail "lock: fresh acquire non-zero"
[ -L "$home_lock/.fleet.lock" ] || fail "lock: lock symlink not created"
# The token is the verb's output, and it is the link's target: that identity is
# what makes a cross-process release provable rather than a guess.
[ -n "$lock_token" ] || fail "lock: printed no token, so a caller cannot release by token"
[ "$(readlink "$home_lock/.fleet.lock")" = "$lock_token" ] \
  || fail "lock: the printed token is not the lock's target"
# DETACHED: the hold outlives the process that took it, so nothing may decide
# it is dead on its own. A second acquire has to read busy, not break it.
case $lock_token in
  detached-*) ;;
  *) fail "lock: the exposed hold is not detached ('$lock_token'); a later acquire could break it as owner-less" ;;
esac
rc=0
lenv lock >/dev/null 2>&1 || rc=$?
[ "$rc" = 1 ] || fail "lock: busy acquire exit $rc, expected 1"

# A token that is not the holder's releases NOTHING: that is the clobber the
# token crossing exists to prevent.
rc=0
lenv unlock "detached-999-999" >/dev/null 2>&1 || rc=$?
[ "$rc" = 1 ] || fail "unlock <foreign token>: exit $rc, expected 1"
[ "$(readlink "$home_lock/.fleet.lock")" = "$lock_token" ] \
  || fail "unlock with a foreign token deleted the current holder's lock"

lenv unlock "$lock_token" || fail "unlock <token>: non-zero exit"
# `! -e` as well as `! -L`: a lock leaked in any OTHER shape (a directory left
# by the retired mkdir code, a regular file) is still a wedged home, and `-L`
# alone reports it clean.
[ ! -e "$home_lock/.fleet.lock" ] && [ ! -L "$home_lock/.fleet.lock" ] \
  || fail "unlock <token>: lock not removed"
# Idempotent: a second release of a token whose lock is already gone is this
# verb's success condition, not an error.
lenv unlock "$lock_token" || fail "unlock <token>: not idempotent"
echo "ok: the lock verb hands out a detached hold and its token, and only that token releases it"

lenv lock >/dev/null || fail "unlock: the lock could not be re-acquired"
lenv unlock || fail "unlock: non-zero exit"
[ ! -e "$home_lock/.fleet.lock" ] && [ ! -L "$home_lock/.fleet.lock" ] \
  || fail "unlock: lock not removed"
lenv unlock || fail "unlock: not idempotent"
# The exit status above is a constant; idempotence is that the path is still
# clear and a fresh acquire still succeeds.
[ ! -e "$home_lock/.fleet.lock" ] && [ ! -L "$home_lock/.fleet.lock" ] \
  || fail "unlock: a second unlock left something at the lock path"
lenv lock >/dev/null || fail "unlock: the lock could not be re-acquired after two unlocks"
lenv unlock || fail "unlock: non-zero exit on the trailing release"
echo "ok: a tokenless unlock is the unconditional escape hatch, and it is idempotent"

# ---------------------------------------------------------------------------
# A lock left as a DIRECTORY by the retired `mkdir` shape. `ln -s target dir`
# puts the link inside dir and exits 0, so an unchecked create reports the lock
# acquired while holding nothing — the worst possible reading, since the caller
# then enters its critical section. Nothing about a directory answers "is its
# owner still running", so an acquire refuses it outright (exit 2) rather than
# guessing or waiting out a budget on a wait that cannot end. A tokenless
# `unlock` is the in-place upgrade: it clears the directory, and the next
# acquire takes an ordinary lock at the same path.
# ---------------------------------------------------------------------------
home_legacy="$tmp/legacy-home"
mkdir -p "$home_legacy"
legacy_env() {
  env -u CLAUDE_PLUGIN_DATA -u CLAUDE_DIR -u HOME \
    PLANWRIGHT_FLEET_STATE_DIR="$home_legacy" /bin/sh "$FS" "$@"
}
mkdir "$home_legacy/.fleet.lock"
rc=0
legacy_err=$(legacy_env lock 2>&1 >/dev/null) || rc=$?
[ "$rc" = 2 ] || fail "a legacy directory lock reported exit $rc, expected 2 (it is not a lock and cannot be waited out)"
case $legacy_err in
  *"not a lock symlink"*) ;;
  *) fail "the legacy-directory refusal did not say what it found: $legacy_err" ;;
esac
# The stray a create-into-directory would leave is named for the TOKEN, never
# for this shell's $$, so assert the directory is EMPTY rather than probing one
# name that can never match.
[ -z "$(find "$home_legacy/.fleet.lock" -mindepth 1 2>/dev/null)" ] \
  || fail "the create landed INSIDE the legacy lock directory"
[ -d "$home_legacy/.fleet.lock" ] || fail "an acquire removed a legacy lock it refused"
echo "ok: a retired-shape directory lock is refused, never acquired through, never written into"

legacy_env unlock || fail "unlock over a legacy directory lock exited non-zero"
[ ! -e "$home_legacy/.fleet.lock" ] \
  || fail "unlock reported success but left the legacy directory lock standing"
legacy_env lock >/dev/null || fail "the upgraded path could not take an ordinary lock"
[ -L "$home_legacy/.fleet.lock" ] || fail "the upgraded path did not take a symlink lock"
legacy_env unlock || fail "unlock after the upgrade exited non-zero"
echo "ok: a tokenless unlock upgrades a retired-shape directory lock in place"

# A NON-EMPTY legacy directory is the shape that matters most, because the
# retired create-into-a-directory race is exactly what leaves a stray inside
# one. The old rmdir could not clear it and reported the home wedged; the clear
# takes it, which is what makes the upgrade path work on a real casualty.
home_uld="$tmp/unlock-legacy-home"
mkdir -p "$home_uld"
mkdir "$home_uld/.fleet.lock"
: >"$home_uld/.fleet.lock/stray"
env -u CLAUDE_PLUGIN_DATA -u CLAUDE_DIR -u HOME \
  PLANWRIGHT_FLEET_STATE_DIR="$home_uld" /bin/sh "$FS" unlock \
  || fail "unlock over a non-empty legacy directory lock exited non-zero"
[ ! -e "$home_uld/.fleet.lock" ] \
  || fail "unlock left a non-empty legacy directory lock standing"
echo "ok: unlock clears a retired-shape directory lock even with a stray inside it"

# A REGULAR FILE at the lock path is nobody's lock and nothing here can judge
# what it is, so the clear refuses it rather than deleting a file it does not
# understand.
: >"$home_uld/.fleet.lock"
rc=0
env -u CLAUDE_PLUGIN_DATA -u CLAUDE_DIR -u HOME \
  PLANWRIGHT_FLEET_STATE_DIR="$home_uld" /bin/sh "$FS" unlock >/dev/null 2>&1 || rc=$?
[ "$rc" = 2 ] || fail "unlock over a regular file at the lock path exited $rc, expected 2"
[ -f "$home_uld/.fleet.lock" ] || fail "unlock deleted a regular file it could not judge"
rm -f "$home_uld/.fleet.lock"
echo "ok: unlock refuses a regular file squatting the lock path instead of deleting it"

# ---------------------------------------------------------------------------
# The one-shot `lock` verb against a lock whose OWNER IS GONE must report 0
# (held), not 1: the verb tries exactly once, so a break that does not
# re-acquire hands the caller "busy" for a lock the same call just freed.
# ---------------------------------------------------------------------------
home_sl="$tmp/stale-lockverb-home"
mkdir -p "$home_sl"
ln -s "crashed-holder" "$home_sl/.fleet.lock"
rc=0
env -u CLAUDE_PLUGIN_DATA -u CLAUDE_DIR -u HOME \
  PLANWRIGHT_FLEET_STATE_DIR="$home_sl" \
  /bin/sh "$FS" lock >/dev/null 2>&1 || rc=$?
[ "$rc" = 0 ] || fail "one-shot lock against an owner-less lock exited $rc, expected 0 (it broke the lock, so it holds it)"
[ -L "$home_sl/.fleet.lock" ] || fail "one-shot lock reported held but left no lock symlink"
echo "ok: the one-shot lock verb acquires the lock it just broke"

# ---------------------------------------------------------------------------
# A lock symlink whose target is a REAL directory, cleared by the tokenless
# `unlock`. That clear is the one place in this path that runs `rm -rf`: it
# takes a lock left as a directory by the retired shape, and it is safe here
# only because the symlink arm is tested FIRST, so the `rm -f` that removes a
# link is reached before the `rm -rf` that removes a directory. Nothing at the
# call site shows that ordering matters, so a canary pins it before a future
# edit (a reordered test, a `find -delete`, a trailing slash that makes the
# link read as its target) silently starts deleting whatever a lock points at.
# ---------------------------------------------------------------------------
home_canary="$tmp/canary-home"
mkdir -p "$home_canary"
canary_dir="$tmp/canary-target"
mkdir -p "$canary_dir"
: >"$canary_dir/canary"
ln -s "$canary_dir" "$home_canary/.fleet.lock"
env -u CLAUDE_PLUGIN_DATA -u CLAUDE_DIR -u HOME \
  PLANWRIGHT_FLEET_STATE_DIR="$home_canary" \
  /bin/sh "$FS" unlock \
  || fail "unlock over a lock symlink pointing at a real directory exited non-zero"
[ ! -L "$home_canary/.fleet.lock" ] && [ ! -e "$home_canary/.fleet.lock" ] \
  || fail "unlock left the lock symlink standing"
[ -d "$canary_dir" ] || fail "clearing the lock DELETED the directory its symlink pointed at"
[ -e "$canary_dir/canary" ] || fail "clearing the lock deleted the contents of the symlink's target"
echo "ok: clearing a lock symlink removes the link and never its target"

# ---------------------------------------------------------------------------
# A LOCK WHOSE OWNER IS STILL RUNNING IS NEVER BROKEN, HOWEVER OLD IT IS. This
# is the defect the retired age rule caused: a threshold answers a question
# nobody asked, and a holder that stayed inside its critical section longer
# than the threshold had its lock taken out from under it — mutual exclusion
# lost to a clock. The fixture back-dates the link to the year 2000 and pins a
# live owner (this test shell), so any age rule that came back would break it
# and any liveness rule refuses to.
# ---------------------------------------------------------------------------
home_old="$tmp/old-live-home"
mkdir -p "$home_old"
ln -s "$$-1-1" "$home_old/.fleet.lock" # owned by this still-running shell
touch -h -t 200001010000 "$home_old/.fleet.lock"
rc=0
env -u CLAUDE_PLUGIN_DATA -u CLAUDE_DIR -u HOME \
  PLANWRIGHT_FLEET_STATE_DIR="$home_old" \
  /bin/sh "$FS" lock >/dev/null 2>&1 || rc=$?
[ "$rc" = 1 ] || fail "a 26-year-old lock with a LIVE owner was not reported busy (exit $rc): an age rule is deciding staleness again"
[ "$(readlink "$home_old/.fleet.lock")" = "$$-1-1" ] \
  || fail "a live owner's lock was broken because of its age"
# The companion, so the case cannot pass by never breaking anything at all:
# the SAME back-dated link with a DEAD owner is broken on the first attempt.
ln -sf "crashed-holder" "$home_old/.fleet.lock"
touch -h -t 200001010000 "$home_old/.fleet.lock"
env -u CLAUDE_PLUGIN_DATA -u CLAUDE_DIR -u HOME \
  PLANWRIGHT_FLEET_STATE_DIR="$home_old" \
  /bin/sh "$FS" lock >/dev/null 2>&1 \
  || fail "the same back-dated lock with an ABSENT owner was not broken: the case proves nothing"
echo "ok: a live owner's lock is never broken by age, and an absent owner's is broken without one"

# ---------------------------------------------------------------------------
# A signal delivered the instant the lock is taken must still release it. The
# release is armed before the first acquire and the library records the hold
# before its acquire returns, so there is no window where the link exists and
# the handler does not know about it — but "no window" is a property of how the
# two are ordered, and nothing at the call site shows it. This pins it: a
# holder killed just after the acquire must leave nothing standing, because
# nothing breaks an abandoned lock on its own once the age rule is gone.
#
# The real window is sub-millisecond, so this widens it by fault injection: a
# copy of the script with a sleep immediately after the acquire returns. The
# injection is asserted, because an anchor that silently stops matching would
# turn the whole case green without testing anything.
# ---------------------------------------------------------------------------
shim2="$tmp/shim-term"
mkdir -p "$shim2"
cp "$here/../scripts/echo-safety.sh" "$here/../scripts/config-get.sh" \
  "$here/../scripts/lock-lib.sh" "$shim2/"
sed 's/^  sa_rc=\$?$/  sa_rc=$?\
  sleep 3/' "$here/../scripts/fleet-state.sh" >"$shim2/fleet-state.sh"
chmod +x "$shim2/fleet-state.sh"
[ "$(grep -c '^  sleep 3$' "$shim2/fleet-state.sh")" = 1 ] \
  || fail "the acquire-window fault injection did not apply; its anchor in spin_acquire moved"
home_term="$tmp/term-window-home"
mkdir -p "$home_term"
env -u CLAUDE_PLUGIN_DATA -u CLAUDE_DIR -u HOME \
  PLANWRIGHT_FLEET_STATE_DIR="$home_term" \
  /bin/sh "$shim2/fleet-state.sh" register "w-term" "scope-term" >/dev/null 2>&1 &
term_pid=$!
# Wait for the LOCK to appear rather than for a wall-clock guess: its presence
# is proof the acquire returned, which is the start of the window under test.
term_waited=0
while [ ! -L "$home_term/.fleet.lock" ]; do
  term_waited=$((term_waited + 1))
  [ "$term_waited" -lt 400 ] || fail "the fault-injected register never took the lock"
  sleep 0.02
done
kill -TERM "$term_pid" 2>/dev/null || true
wait "$term_pid" 2>/dev/null || true
[ ! -L "$home_term/.fleet.lock" ] && [ ! -e "$home_term/.fleet.lock" ] \
  || fail "a TERM between the acquire and the caller's bookkeeping leaked the lock"
echo "ok: a signal in the acquire window releases the lock instead of leaking it"

# ---------------------------------------------------------------------------
# A toolchain WITHOUT `readlink`. Every lock create is confirmed by reading the
# link back, so a confirm that cannot run reads as a create somebody else won:
# the acquire makes its own link, judges it foreign, and reports busy while that
# link stands with nobody able to prove it is theirs. Measured before the guard
# existed: `lock` exited 1 with its own token still at the lock path, and
# `register` / `bound-incr` spun the entire budget before failing with a
# diagnostic blaming contention that was never there.
#
# The guard sits AT THE FIRST ACQUIRE, not at the top of the script, which is
# what the root/registry/unlock half below pins: those verbs never confirm a
# link, and failing them on a tool they do not use would be its own regression.
# ---------------------------------------------------------------------------
norl_bin="$tmp/no-readlink-bin"
mkdir -p "$norl_bin"
# A curated toolchain rather than a filtered copy of PATH: the tools
# fleet-state.sh and the config helpers it forks actually use, minus readlink.
# Under-enumerating it cannot quietly turn this case green — the readlink-
# restored control at the end runs the same verbs over this same PATH and has
# to succeed, so a stub too thin to work fails there instead of passing here.
for t in awk bash cat date dirname find grep head ln mkdir mktemp mv rm rmdir sed sleep sort tail tr; do
  t_path=$(command -v "$t") || fail "no-readlink stub: cannot resolve $t on this host"
  ln -s "$t_path" "$norl_bin/$t"
done
# Asserted, not assumed: if readlink stayed reachable the whole case would pass
# while testing nothing at all.
if env PATH="$norl_bin" /bin/sh -c 'command -v readlink' >/dev/null 2>&1; then
  fail "no-readlink stub: readlink is still reachable, so this case would assert nothing"
fi

norl_env() {
  norl_home=$1
  shift
  env -u CLAUDE_PLUGIN_DATA -u CLAUDE_DIR -u HOME \
    PATH="$norl_bin" PLANWRIGHT_FLEET_STATE_DIR="$norl_home" /bin/sh "$FS" "$@"
}

# Every verb that takes the lock: refuse with exit 2 and a diagnostic naming the
# tool, and leave NOTHING behind. Exit 1 is the specific misreport the guard
# exists to prevent, so it is called out by name in the failure text.
for norl_verb in lock register bound-incr bound-decr; do
  case $norl_verb in
    lock) set -- lock ;;
    register) set -- register "w-norl" "scope-norl" ;;
    bound-incr) set -- bound-incr 5 ;;
    bound-decr) set -- bound-decr 5 ;;
  esac
  norl_home="$tmp/no-readlink-$norl_verb"
  norl_err="$tmp/no-readlink-$norl_verb.err"
  rc=0
  norl_env "$norl_home" "$@" >/dev/null 2>"$norl_err" || rc=$?
  [ "$rc" = 2 ] \
    || fail "$norl_verb without readlink exited $rc, expected 2 (1 is the busy misreport the guard exists to prevent)"
  grep -q 'readlink' "$norl_err" \
    || fail "$norl_verb without readlink exited 2 but never named the missing tool: $(cat "$norl_err")"
  [ ! -e "$norl_home/.fleet.lock" ] && [ ! -L "$norl_home/.fleet.lock" ] \
    || fail "$norl_verb without readlink left a lock standing it could never confirm"
done
echo "ok: without readlink the lock is refused, not taken, misreported busy, and leaked"

# The diagnostic says WHY the refusal happened, not just that one did: the
# reason an acquire cannot proceed without readlink is that it cannot tell its
# own link from a peer's, and an operator who is not told that goes looking for
# contention. The message comes from the lock primitive, which is what refuses,
# so it is pinned by its content rather than by a list of this script's verbs.
norl_msg=$(cat "$tmp/no-readlink-lock.err")
case "$norl_msg" in
  *"readlink"*) ;;
  *) fail "the refusal diagnostic does not name the missing tool: $norl_msg" ;;
esac
case "$norl_msg" in
  *"this process's own"*) ;;
  *) fail "the refusal diagnostic does not say why a lock cannot be confirmed without it: $norl_msg" ;;
esac
echo "ok: the refusal names the missing tool and why an acquire depends on it"

# The verbs that never read a link target must be untouched by the guard. This
# is the half a top-of-script fast-fail turns red, and the reason the guard is
# placed where the dependency is actually used.
norl_env "$tmp/no-readlink-plain" root >/dev/null \
  || fail "root without readlink exited non-zero; the guard is not at the lock path"
norl_env "$tmp/no-readlink-plain" registry >/dev/null \
  || fail "registry without readlink exited non-zero; the guard is not at the lock path"
# `unlock` is deliberately NOT guarded: it unlinks and rmdirs, and reads no link
# target, so it stays correct without the tool. Pinned here so a later
# broad-brush guard cannot quietly take away the one release path that still
# works on a toolchain missing readlink.
mkdir -p "$tmp/no-readlink-unlock"
ln -s "12345-999" "$tmp/no-readlink-unlock/.fleet.lock"
norl_env "$tmp/no-readlink-unlock" unlock \
  || fail "unlock without readlink exited non-zero; it reads no link target and must still release"
[ ! -e "$tmp/no-readlink-unlock/.fleet.lock" ] && [ ! -L "$tmp/no-readlink-unlock/.fleet.lock" ] \
  || fail "unlock without readlink reported a release that did not happen"
echo "ok: without readlink, root/registry/unlock — the verbs that confirm no link — still work"

# Negative control: the SAME stub PATH, readlink restored. This separates "the
# tool is missing" from "the stub PATH was too thin", and stops the guard from
# being a blanket refusal that passes the case above for the wrong reason.
ln -s "$(command -v readlink)" "$norl_bin/readlink"
norl_ctl="$tmp/readlink-restored"
norl_env "$norl_ctl" lock >/dev/null \
  || fail "negative control: lock failed with readlink present on the stub PATH"
[ -L "$norl_ctl/.fleet.lock" ] \
  || fail "negative control: lock reported success but took no lock"
norl_env "$norl_ctl" unlock \
  || fail "negative control: unlock failed with readlink present on the stub PATH"
norl_env "$norl_ctl" register "w-ctl" "scope-ctl" >/dev/null \
  || fail "negative control: register failed with readlink present on the stub PATH"
[ "$(norl_env "$norl_ctl" bound-incr 5)" = 1 ] \
  || fail "negative control: bound-incr did not grant the first slot with readlink present"
[ ! -e "$norl_ctl/.fleet.lock" ] && [ ! -L "$norl_ctl/.fleet.lock" ] \
  || fail "negative control: a verb left the lock standing with readlink present"
echo "ok: with readlink restored on the same PATH the guard stays silent and every verb works"

# ---------------------------------------------------------------------------
# 11. Hostile identifiers are rejected BEFORE any path use.
# ---------------------------------------------------------------------------
# 11a. A hostile plugin-namespace manifest name (path traversal) never reaches
#      a path: writer resolution refuses it and the traversal never appears in
#      any resolved output.
cdir_bad="$tmp/hostile/.claude"
mkdir -p "$cdir_bad/planwright"
printf '%s\n' '{ "name": "../../escape" }' >"$cdir_bad/planwright/plugin.json"
rc=0
bad=$(run_root CLAUDE_DIR="$cdir_bad") || rc=$?
[ "$rc" != "0" ] || fail "hostile manifest name resolved to a root ('$bad')"
case $bad in
  *escape*) fail "hostile manifest name leaked into a resolved path ('$bad')" ;;
esac
echo "ok: a hostile plugin-namespace name is rejected before any path use"

# 11b. A hostile worker/scope identifier (traversal, control chars) is refused
#      and nothing is written to the registry.
home_h="$tmp/hostile-ids"
henv() {
  env -u CLAUDE_PLUGIN_DATA -u CLAUDE_DIR -u HOME \
    PLANWRIGHT_FLEET_STATE_DIR="$home_h" /bin/sh "$FS" "$@"
}
rc=0
henv register "../../etc/passwd" "scope" >/dev/null 2>&1 || rc=$?
[ "$rc" != "0" ] || fail "hostile worker id accepted"
rc=0
henv register "worker=ok" "$(printf 'sc\tope')" >/dev/null 2>&1 || rc=$?
[ "$rc" != "0" ] || fail "scope with an embedded tab accepted (would tear the record)"
[ ! -e "$home_h/registry" ] || {
  # A registry file may exist but must hold no hostile record.
  grep -q "passwd" "$home_h/registry" && fail "hostile worker id reached the registry"
  true
}
echo "ok: hostile worker/scope identifiers are refused, nothing written"

# 11c. bound-incr rejects a malformed bound rather than coercing it into an
#      unbounded counter. Cover both the non-numeric and the empty-string arms
#      of the validation `case`, so a refactor that drops either is caught.
rc=0
benv bound-incr "notanumber" >/dev/null 2>&1 || rc=$?
[ "$rc" != "0" ] || fail "bound-incr accepted a non-numeric bound"
rc=0
benv bound-incr "" >/dev/null 2>&1 || rc=$?
[ "$rc" != "0" ] || fail "bound-incr accepted an empty-string bound"
echo "ok: bound-incr rejects a malformed bound (non-numeric and empty)"

# ---------------------------------------------------------------------------
# 12. Crash recovery: a lock left behind by a holder whose process is GONE must
#     not deadlock the fleet forever — a new acquirer breaks it and proceeds.
#     (This is the recoverable, single-acquirer property. The concurrent
#     multi-breaker corner belongs to the lock primitive's own suite, which is
#     where the claim-link mechanism that closes it lives.)
# ---------------------------------------------------------------------------
home_stale="$tmp/stale-home"
mkdir -p "$home_stale"
ln -s "crashed-holder" "$home_stale/.fleet.lock"
env -u CLAUDE_PLUGIN_DATA -u CLAUDE_DIR -u HOME \
  PLANWRIGHT_FLEET_STATE_DIR="$home_stale" \
  /bin/sh "$FS" bound-incr 3 >/dev/null \
  || fail "an owner-less lock deadlocked a new acquirer (no break/recovery)"
[ "$(cat "$home_stale/concurrency")" = "1" ] || fail "break recovery did not complete the increment"
echo "ok: a crashed holder's lock is broken, not a permanent deadlock"

# ---------------------------------------------------------------------------
# 12b. No configuration can disable crash recovery, because no configuration
#      takes part in it. `stale_lock_threshold` used to gate the break, and it
#      resolved through the caller's cwd — so a repo with a ~190-year threshold
#      in its committed config silently turned recovery off for any tower run
#      from inside it. Liveness answers the question now and reads no config at
#      all, which this pins by planting that same hostile threshold in the cwd
#      and requiring the break anyway.
# ---------------------------------------------------------------------------
home_cwd="$tmp/cwd-indep-home"
mkdir -p "$home_cwd"
ln -s "crashed-holder" "$home_cwd/.fleet.lock"
hostile_repo="$tmp/hostile-cwd-repo"
mkdir -p "$hostile_repo/.claude"
(cd "$hostile_repo" && git init -q) || fail "cwd-indep: could not init the hostile cwd repo"
printf 'stale_lock_threshold: 99999999m\n' >"$hostile_repo/.claude/planwright.yml"
(
  cd "$hostile_repo" \
    && env -u CLAUDE_PLUGIN_DATA -u CLAUDE_DIR -u HOME -u PLANWRIGHT_LOCAL_CONFIG \
      PLANWRIGHT_FLEET_STATE_DIR="$home_cwd" /bin/sh "$FS" bound-incr 3 >/dev/null
) || fail "cwd-indep: the break did not fire — a stale-age knob is gating crash recovery again"
[ "$(cat "$home_cwd/concurrency")" = "1" ] || fail "cwd-indep: break recovery did not complete the increment"
echo "ok: no configured threshold takes part in crash recovery (a hostile repo-local knob cannot disable it)"

# ---------------------------------------------------------------------------
# 13. Fail-closed usage error: an UNKNOWN command exits 2 and creates NO
#     fleet-state artifacts. A typo is a usage error, not a reason to
#     materialize the fleet home (REQ-A1.6 data hygiene) — the unknown-command
#     rejection must happen BEFORE the unconditional fleet-home mkdir.
# ---------------------------------------------------------------------------
home_bogus="$tmp/bogus-home"
rc=0
env -u CLAUDE_PLUGIN_DATA -u CLAUDE_DIR -u HOME \
  PLANWRIGHT_FLEET_STATE_DIR="$home_bogus" /bin/sh "$FS" bogus-cmd >/dev/null 2>&1 || rc=$?
[ "$rc" = 2 ] || fail "unknown command: exit $rc, expected 2"
[ ! -e "$home_bogus" ] || fail "unknown command created fleet-state artifacts at '$home_bogus' (not fail-closed)"
echo "ok: an unknown command exits 2 and creates no fleet-home artifacts"

# ---------------------------------------------------------------------------
# 14. Echo discipline (doctrine/security-posture.md): untrusted input embedded
#     in a diagnostic is stripped of C0/DEL control bytes before it reaches
#     stderr, so an escape sequence in a caller's argv (or a hostile manifest
#     name) cannot drive the terminal or corrupt a log. Covers the
#     unknown-command ($cmd) and register field ($worker/$scope) diagnostics.
# ---------------------------------------------------------------------------
esc=$(printf 'x\033]0;INJECT\007y\010z') # ESC + OSC + BEL + backspace embedded
home_inj="$tmp/inj-home"
assert_no_cntrl() {
  # $1 = captured stderr, $2 = label. Fail if any C0/DEL byte survived, using
  # the same byte set the sanitizer strips.
  aic_stripped=$(printf '%s' "$1" | tr -d '\000-\037\177')
  [ -n "$1" ] || fail "$2: no diagnostic emitted at all"
  [ "$aic_stripped" = "$1" ] || fail "$2: leaked control bytes to stderr (terminal/log injection)"
}
inj_err=$(env -u CLAUDE_PLUGIN_DATA -u CLAUDE_DIR -u HOME \
  PLANWRIGHT_FLEET_STATE_DIR="$home_inj" /bin/sh "$FS" "$esc" 2>&1 >/dev/null) || true
assert_no_cntrl "$inj_err" "unknown-command diagnostic"
inj_err=$(env -u CLAUDE_PLUGIN_DATA -u CLAUDE_DIR -u HOME \
  PLANWRIGHT_FLEET_STATE_DIR="$home_inj" /bin/sh "$FS" register "$esc" "scope-ok" 2>&1 >/dev/null) || true
assert_no_cntrl "$inj_err" "register worker diagnostic"
inj_err=$(env -u CLAUDE_PLUGIN_DATA -u CLAUDE_DIR -u HOME \
  PLANWRIGHT_FLEET_STATE_DIR="$home_inj" /bin/sh "$FS" register "worker-ok" "$esc" 2>&1 >/dev/null) || true
assert_no_cntrl "$inj_err" "register scope diagnostic"
echo "ok: untrusted diagnostics are stripped of control/escape bytes (no terminal/log injection)"

# ---------------------------------------------------------------------------
# `unlock` must REPORT a release that did not happen, whatever the reason. The
# two removals discard their exit status, so the only thing this branch knows
# is that the path is still there — it could be a non-empty directory, or an
# ordinary lock symlink whose parent is not writable. The diagnostic used to
# assert the first ("it is not a lock symlink"), which sends an operator
# hitting the second to inspect the wrong thing entirely.
# ---------------------------------------------------------------------------
if [ "$(id -u)" = 0 ]; then
  echo "skip: unlock permission case needs a non-root user (root ignores the directory mode)"
else
  home_perm="$tmp/perm-home"
  mkdir -p "$home_perm"
  penv() {
    env -u CLAUDE_PLUGIN_DATA -u CLAUDE_DIR -u HOME \
      PLANWRIGHT_FLEET_STATE_DIR="$home_perm" /bin/sh "$FS" "$@"
  }
  penv lock >/dev/null || fail "perm: could not take the lock to begin with"
  [ -L "$home_perm/.fleet.lock" ] || fail "perm: the lock is not a symlink, so this case tests nothing"
  chmod 500 "$home_perm" || fail "perm: could not make the home unwritable"
  # `|| rc=$?` on the assignment itself: under `set -e` a failing command
  # substitution ends the script before the next line runs, which would skip
  # the chmod below and leave the fixture undeletable.
  rc=0
  out=$(penv unlock 2>&1) || rc=$?
  chmod 700 "$home_perm"
  [ "$rc" = 2 ] || fail "perm: an unlock that could not remove the lock must exit 2, got $rc"
  case $out in
    *"still present"*) ;;
    *) fail "perm: the diagnostic should report the observable condition, got: $out" ;;
  esac
  case $out in
    *"not a lock symlink"*)
      fail "perm: the diagnostic asserts a shape this branch never checked, on a genuine symlink: $out"
      ;;
  esac
  penv unlock >/dev/null 2>&1 || fail "perm: unlock should succeed once the home is writable again"
  echo "ok: an unlock blocked by permissions reports the condition it can see, not a guessed shape"
fi

# A fleet home this script creates is owner-only from birth. `mkdir -p` alone
# takes the caller's umask, so a umask-002 host got 0775 — and everything
# private underneath (the tower-comms surface, the registry) is only as private
# as the directory holding it. A home that already exists is left alone: its
# permissions are its owner's call, not ours to tighten underneath them.
if [ "${PLANWRIGHT_TEST_SKIP_PERM:-}" != 1 ]; then
  home_new="$tmp/fresh-home/nested"
  old_umask=$(umask)
  umask 002
  env -u CLAUDE_PLUGIN_DATA -u CLAUDE_DIR -u HOME \
    PLANWRIGHT_FLEET_STATE_DIR="$home_new" /bin/sh "$FS" registry >/dev/null \
    || fail "fresh home: registry should succeed"
  umask "$old_umask"
  mode=$(stat -c '%a' "$home_new")
  [ "$mode" = 700 ] \
    || fail "fresh home: a home this script creates must be owner-only, got $mode"
  echo "ok: a fleet home this script creates is owner-only whatever the caller's umask"

  home_pre="$tmp/preexisting-home"
  mkdir -p "$home_pre"
  chmod 755 "$home_pre"
  env -u CLAUDE_PLUGIN_DATA -u CLAUDE_DIR -u HOME \
    PLANWRIGHT_FLEET_STATE_DIR="$home_pre" /bin/sh "$FS" registry >/dev/null \
    || fail "pre-existing home: registry should succeed"
  mode=$(stat -c '%a' "$home_pre")
  [ "$mode" = 755 ] \
    || fail "pre-existing home: a home we did not create must be left alone, got $mode"
  echo "ok: a fleet home that already existed keeps the permissions its owner gave it"
fi

echo "ALL PASS: fleet-state.sh"
