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
# The stale-break case (12) reads stale_lock_threshold through the real
# config-get.sh, so it pins that value via an explicit PLANWRIGHT_LOCAL_CONFIG
# (the top-of-ladder machine-local layer) instead of trusting the ambient
# config — the break stays deterministic even against a pathological repo-local
# override (e.g. stale_lock_threshold: 99999999m), mirroring how the sibling
# orchestrate-lock.sh consumes the knob.
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
ln -s "held-by-test" "$home_ts/.fleet.lock" # hold the lock so register must block
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
lenv lock || fail "lock: fresh acquire non-zero"
[ -L "$home_lock/.fleet.lock" ] || fail "lock: lock symlink not created"
rc=0
lenv lock >/dev/null 2>&1 || rc=$?
[ "$rc" = 1 ] || fail "lock: busy acquire exit $rc, expected 1"
lenv unlock || fail "unlock: non-zero exit"
# `! -e` as well as `! -L`: a lock leaked in any OTHER shape (a directory left
# by the pre-symlink code, a regular file) is still a wedged home, and `-L`
# alone reports it clean.
[ ! -e "$home_lock/.fleet.lock" ] && [ ! -L "$home_lock/.fleet.lock" ] \
  || fail "unlock: lock not removed"
lenv unlock || fail "unlock: not idempotent"
# The exit status above is a constant; idempotence is that the path is still
# clear and a fresh acquire still succeeds.
[ ! -e "$home_lock/.fleet.lock" ] && [ ! -L "$home_lock/.fleet.lock" ] \
  || fail "unlock: a second unlock left something at the lock path"
lenv lock || fail "unlock: the lock could not be re-acquired after two unlocks"
lenv unlock || fail "unlock: non-zero exit on the trailing release"
echo "ok: the advisory-lock primitive is exclusive, busy-safe, and idempotent"

# ---------------------------------------------------------------------------
# A lock left as a DIRECTORY by the pre-symlink shape. `ln -s target dir` puts
# the link inside dir and exits 0, so an unchecked create reports the lock
# acquired while holding nothing — the worst possible reading, since the caller
# then enters its critical section. A live one must read busy; a stale one must
# be broken, because nothing else reclaims it and it would otherwise wedge every
# fleet writer permanently.
# ---------------------------------------------------------------------------
home_legacy="$tmp/legacy-home"
mkdir -p "$home_legacy"
# Pin the threshold for the same reason case 12 pins it: without it an ambient
# machine-local stale_lock_threshold (a pathological 99999999m, say) makes the
# back-dated directory below read FRESH and the stale-break half fails.
legacy_pin="$tmp/legacy-pin.yml"
printf 'stale_lock_threshold: 5m\n' >"$legacy_pin"
legacy_env() {
  env -u CLAUDE_PLUGIN_DATA -u CLAUDE_DIR -u HOME \
    PLANWRIGHT_FLEET_STATE_DIR="$home_legacy" PLANWRIGHT_LOCAL_CONFIG="$legacy_pin" \
    /bin/sh "$FS" "$@"
}
mkdir "$home_legacy/.fleet.lock" # a fresh legacy holder
rc=0
legacy_env lock >/dev/null 2>&1 || rc=$?
[ "$rc" = 1 ] || fail "a live legacy directory lock reported exit $rc, expected 1 (busy)"
# The stray a create-into-directory would leave is named for the TOKEN
# (<fleet-state pid>-<epoch>), never for this shell's $$, so assert the
# directory is EMPTY rather than probing one name that can never match.
[ -z "$(find "$home_legacy/.fleet.lock" -mindepth 1 2>/dev/null)" ] \
  || fail "the create landed INSIDE the legacy lock directory"
[ -d "$home_legacy/.fleet.lock" ] || fail "a live legacy lock was removed"
echo "ok: a live pre-symlink directory lock reads busy, and is never acquired through"

touch -t 202001010000 "$home_legacy/.fleet.lock" # same holder, now long dead
legacy_env lock || fail "a stale legacy directory lock was not broken"
[ -L "$home_legacy/.fleet.lock" ] || fail "the broken legacy lock was not replaced by a symlink"
legacy_env unlock || fail "unlock after a legacy break exited non-zero"
# Its zero status is not on its own proof of a release — the observation at
# the path below is. (`unlock` does report a failure it can see: the case
# further down covers the branch where the path survives both removals.)
[ ! -e "$home_legacy/.fleet.lock" ] && [ ! -L "$home_legacy/.fleet.lock" ] \
  || fail "unlock did not release the lock taken by the legacy break"
echo "ok: a stale pre-symlink directory lock is broken rather than wedging the home"

# ---------------------------------------------------------------------------
# `unlock` must clear a lock left as a DIRECTORY by the pre-symlink shape.
# `rm -f` refuses a directory, so an unlock that only unlinks reports success
# while the home stays wedged behind a lock the operator was told was released.
# ---------------------------------------------------------------------------
home_uld="$tmp/unlock-legacy-home"
mkdir -p "$home_uld"
mkdir "$home_uld/.fleet.lock"
env -u CLAUDE_PLUGIN_DATA -u CLAUDE_DIR -u HOME \
  PLANWRIGHT_FLEET_STATE_DIR="$home_uld" /bin/sh "$FS" unlock \
  || fail "unlock against a legacy directory lock exited non-zero"
[ ! -e "$home_uld/.fleet.lock" ] \
  || fail "unlock reported success but left the legacy directory lock standing"
# A directory it CANNOT clear must not be reported as released. rmdir takes an
# empty directory only, so this is the half an empty-directory case never sees.
mkdir "$home_uld/.fleet.lock"
: >"$home_uld/.fleet.lock/stray"
rc=0
env -u CLAUDE_PLUGIN_DATA -u CLAUDE_DIR -u HOME \
  PLANWRIGHT_FLEET_STATE_DIR="$home_uld" /bin/sh "$FS" unlock >/dev/null 2>&1 || rc=$?
[ "$rc" = 2 ] || fail "unlock over a non-empty directory lock exited $rc, expected 2 (it did not release it)"
rm -rf "$home_uld/.fleet.lock"
echo "ok: unlock clears a pre-symlink directory lock, and refuses to claim one it cannot clear"

# ---------------------------------------------------------------------------
# The one-shot `lock` verb against a STALE lock must report 0 (held), not 1.
# The verb calls try_acquire exactly once, so a break that does not re-acquire
# hands the caller "busy" for a lock the same call just freed — and the two
# stale shapes (symlink, legacy directory) must not disagree about it.
# ---------------------------------------------------------------------------
home_sl="$tmp/stale-lockverb-home"
mkdir -p "$home_sl"
sl_pin="$tmp/stale-lockverb-pin.yml"
printf 'stale_lock_threshold: 5m\n' >"$sl_pin"
ln -s "crashed-holder" "$home_sl/.fleet.lock"
touch -h -t 202001010000 "$home_sl/.fleet.lock"
rc=0
env -u CLAUDE_PLUGIN_DATA -u CLAUDE_DIR -u HOME \
  PLANWRIGHT_FLEET_STATE_DIR="$home_sl" PLANWRIGHT_LOCAL_CONFIG="$sl_pin" \
  /bin/sh "$FS" lock >/dev/null 2>&1 || rc=$?
[ "$rc" = 0 ] || fail "one-shot lock against a stale symlink exited $rc, expected 0 (it broke the lock, so it holds it)"
[ -L "$home_sl/.fleet.lock" ] || fail "one-shot lock reported held but left no lock symlink"
echo "ok: the one-shot lock verb acquires the lock it just broke, on both stale shapes"

# ---------------------------------------------------------------------------
# A lock symlink whose target is a REAL directory. Breaking it must remove the
# LINK and never touch what it points at. `mv` and `rm -f` operate on the link,
# and `[ ! -L ]` keeps the legacy `rm -rf` arm unreachable for links — but the
# containment comes from those semantics rather than from anything obvious at
# the call site, so a canary pins it before a future edit (an `rm -rf` here, a
# `find -delete` there) silently starts deleting the target's contents.
# ---------------------------------------------------------------------------
home_canary="$tmp/canary-home"
mkdir -p "$home_canary"
canary_dir="$tmp/canary-target"
mkdir -p "$canary_dir"
: >"$canary_dir/canary"
ln -s "$canary_dir" "$home_canary/.fleet.lock"
touch -h -t 202001010000 "$home_canary/.fleet.lock" # stale, so the break fires
env -u CLAUDE_PLUGIN_DATA -u CLAUDE_DIR -u HOME \
  PLANWRIGHT_FLEET_STATE_DIR="$home_canary" PLANWRIGHT_LOCAL_CONFIG="$sl_pin" \
  /bin/sh "$FS" lock >/dev/null 2>&1 \
  || fail "a stale lock symlink pointing at a real directory was not broken"
[ -d "$canary_dir" ] || fail "breaking the lock DELETED the directory its symlink pointed at"
[ -e "$canary_dir/canary" ] || fail "breaking the lock deleted the contents of the symlink's target"
echo "ok: breaking a lock symlink removes the link and never its target"

# ---------------------------------------------------------------------------
# stale_lock_threshold refuses a zero and falls back to the default. A 0 makes
# `find -mmin +0` match a lock that is merely seconds old (on BSD find, one
# second old), so a LIVE holder mid-critical-section reads stale and its lock
# is broken underneath it — mutual exclusion lost by configuration alone.
# ---------------------------------------------------------------------------
home_floor="$tmp/floor-home"
mkdir -p "$home_floor"
floor_pin="$tmp/floor-pin.yml"
printf 'stale_lock_threshold: 0m\n' >"$floor_pin"
ln -s "live-holder" "$home_floor/.fleet.lock"
# GNU first, then BSD. A last-resort constant would be WORSE than no fixture:
# any fixed old date reads stale against the floored threshold, so the case
# would fail claiming the floor did not hold when really the clock was wrong.
touch -h -d "@$(($(date +%s) - 90))" "$home_floor/.fleet.lock" 2>/dev/null \
  || touch -h -t "$(date -v-90S +%Y%m%d%H%M.%S)" "$home_floor/.fleet.lock" 2>/dev/null \
  || fail "could not back-date the lock 90s (neither GNU touch -d nor BSD date -v worked)"
rc=0
env -u CLAUDE_PLUGIN_DATA -u CLAUDE_DIR -u HOME \
  PLANWRIGHT_FLEET_STATE_DIR="$home_floor" PLANWRIGHT_LOCAL_CONFIG="$floor_pin" \
  /bin/sh "$FS" lock >/dev/null 2>&1 || rc=$?
[ "$rc" = 1 ] || fail "a 0m threshold broke a 90s-old LIVE lock (exit $rc); a zero threshold must floor to the default"
# Companion: the SAME fixture with a 1m threshold must break. Without it the
# case above passes just as well when the pinned config is never read at all,
# because the 15m default would also decline to break a 90s-old lock.
floor_live="$tmp/floor-live-pin.yml"
printf 'stale_lock_threshold: 1m\n' >"$floor_live"
rc=0
env -u CLAUDE_PLUGIN_DATA -u CLAUDE_DIR -u HOME \
  PLANWRIGHT_FLEET_STATE_DIR="$home_floor" PLANWRIGHT_LOCAL_CONFIG="$floor_live" \
  /bin/sh "$FS" lock >/dev/null 2>&1 || rc=$?
[ "$rc" = 0 ] || fail "a 1m threshold did not break the same 90s-old lock (exit $rc): the pinned config is not being read"
echo "ok: a 0m stale_lock_threshold floors to the default, and a real 1m threshold still breaks"

# ---------------------------------------------------------------------------
# The stale threshold is resolved ONCE per process. It is read on every
# contended spin, so resolving it per iteration forks config-get.sh ~50 times
# a second per waiter. A memo written inside a command substitution never
# reaches the caller, so this asserts the observable count, not the variable.
# ---------------------------------------------------------------------------
shim="$tmp/shim-scripts"
mkdir -p "$shim"
cp "$here/../scripts/fleet-state.sh" "$shim/fleet-state.sh"
cp "$here/../scripts/echo-safety.sh" "$shim/echo-safety.sh"
cg_count="$tmp/config-get-calls"
: >"$cg_count"
cat >"$shim/config-get.sh" <<'SHIM'
#!/bin/sh
echo call >>"$PLANWRIGHT_CG_COUNT"
[ "$1" = stale_lock_threshold ] && { echo "15m"; exit 0; }
exit 1
SHIM
chmod +x "$shim/config-get.sh"
home_cg="$tmp/cachecount-home"
mkdir -p "$home_cg"
ln -s "held-by-test" "$home_cg/.fleet.lock" # a live holder, so register must spin
env -u CLAUDE_PLUGIN_DATA -u CLAUDE_DIR -u HOME \
  PLANWRIGHT_CG_COUNT="$cg_count" PLANWRIGHT_FLEET_STATE_DIR="$home_cg" \
  /bin/sh "$shim/fleet-state.sh" register "w-cache" "scope-cache" >/dev/null 2>&1 &
cg_pid=$!
sleep 2 # ~100 spins at the 20ms backoff
rm -f "$home_cg/.fleet.lock"
wait "$cg_pid" || fail "the contended register did not complete after the lock was released"
cg_calls=$(wc -l <"$cg_count" | tr -d ' ')
# The lower bound matters as much as the upper: a 0 would mean the acquire was
# never contended and the case proved nothing.
[ "$cg_calls" -ge 1 ] \
  || fail "the contended acquire never resolved stale_lock_threshold at all ($cg_calls): the case did not exercise the spin"
[ "$cg_calls" -le 2 ] \
  || fail "stale_lock_threshold was resolved $cg_calls times in one acquire (expected 1): the per-process memo is not reaching the caller"
echo "ok: the stale threshold is resolved once per process, not once per contended spin"

# ---------------------------------------------------------------------------
# A signal delivered AFTER the lock is taken but BEFORE the caller records
# ownership must still release it. try_acquire creates the link and returns;
# its caller does its bookkeeping afterwards, so anything that gates release on
# that bookkeeping declines to release a lock the process genuinely holds and
# wedges every later fleet writer until the stale break — the outcome the trap
# discipline exists to prevent.
#
# The real window is sub-millisecond, so this widens it by fault injection: a
# copy of the script with a sleep between the acquire and the caller's
# bookkeeping. The injection is asserted, because an anchor that silently stops
# matching would turn the whole case green without testing anything.
# ---------------------------------------------------------------------------
shim2="$tmp/shim-term"
mkdir -p "$shim2"
cp "$here/../scripts/echo-safety.sh" "$here/../scripts/config-get.sh" "$shim2/"
sed 's/^    sa_rc=\$?$/    sa_rc=$?\
    sleep 3/' "$here/../scripts/fleet-state.sh" >"$shim2/fleet-state.sh"
chmod +x "$shim2/fleet-state.sh"
[ "$(grep -c '^    sleep 3$' "$shim2/fleet-state.sh")" = 1 ] \
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
# try_acquire makes its own link, judges it foreign, and reports busy while that
# link stands until the stale break. Measured before the guard existed: `lock`
# exited 1 with its own token still at the lock path, and `register` /
# `bound-incr` spun the entire budget (~27s) before failing with a diagnostic
# blaming contention that was never there.
#
# The guard sits AT THE LOCK, not at the top of the script, which is what the
# root/registry/unlock half below pins: those verbs never confirm a link, and
# failing them on a tool they do not use would be its own regression.
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

# The diagnostic must describe the partition this case actually proves. It was
# wrong once — it listed `register` among the verbs that keep working, while
# the loop above proves `register` is refused — so the two are pinned to each
# other here rather than left to agree by inspection.
norl_msg=$(cat "$tmp/no-readlink-lock.err")
for norl_taking in lock register bound-incr bound-decr; do
  case "$norl_msg" in
    *"$norl_taking"*) ;;
    *) fail "the readlink diagnostic does not name '$norl_taking' among the verbs it refuses: $norl_msg" ;;
  esac
done
for norl_working in root registry unlock; do
  case "$norl_msg" in
    *"$norl_working"*) ;;
    *) fail "the readlink diagnostic does not name '$norl_working' among the verbs that keep working: $norl_msg" ;;
  esac
done
#   And the halves must not be swapped: the refused verbs have to appear before
#   the working ones, which is what makes the sentence say what it means.
norl_head=${norl_msg%%refused*}
case "$norl_head" in
  *registry* | *unlock*)
    fail "the readlink diagnostic lists a still-working verb among the refused ones: $norl_msg"
    ;;
esac
echo "ok: the readlink diagnostic names the same partition this case proves"

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
norl_env "$norl_ctl" lock \
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
# 12. Stale-break liveness: a lock left behind by a CRASHED holder (a stale
#     lock older than the threshold) must not deadlock the fleet forever — a new
#     acquirer breaks it and proceeds. (This is the recoverable, single-acquirer
#     property. The concurrent-multi-breaker corner is narrowed but not closed
#     by the symlink shape's rename-aside claim — a breaker descheduled between
#     its staleness probe and its rename can still displace a successor's live
#     lock, and the legacy-directory break has no atomic claim at all — so it
#     remains unasserted here.)
# ---------------------------------------------------------------------------
home_stale="$tmp/stale-home"
mkdir -p "$home_stale"
ln -s "crashed-holder" "$home_stale/.fleet.lock"
touch -h -t 202001010000 "$home_stale/.fleet.lock" # crashed holder, back-dated to 2020
# Pin stale_lock_threshold via an explicit machine-local config so the break is
# deterministic regardless of the ambient config-get resolution. An explicit
# PLANWRIGHT_LOCAL_CONFIG replaces the resolver-derived machine-local layer (the
# top of the four-layer ladder, last-wins), so no repo-local or adopter override
# can widen the threshold past the back-dated lock's age. Mirrors how the sibling
# orchestrate-lock.sh consumes the knob. 5m is far below the 2020 lock's age, so
# the lock is reliably stale.
stale_pin="$tmp/stale-pin.yml"
printf 'stale_lock_threshold: 5m\n' >"$stale_pin"
env -u CLAUDE_PLUGIN_DATA -u CLAUDE_DIR -u HOME \
  PLANWRIGHT_FLEET_STATE_DIR="$home_stale" PLANWRIGHT_LOCAL_CONFIG="$stale_pin" \
  /bin/sh "$FS" bound-incr 3 >/dev/null \
  || fail "stale lock deadlocked a new acquirer (no break/recovery)"
[ "$(cat "$home_stale/concurrency")" = "1" ] || fail "stale-break recovery did not complete the increment"
echo "ok: a crashed holder's stale lock is broken, not a permanent deadlock"

# ---------------------------------------------------------------------------
# 12b. CWD-independence: the cross-spec fleet stale threshold must NOT vary by
#      the repo a tower happens to run from. fleet_stale_min pins
#      PLANWRIGHT_REPO_ROOT to the fleet home (which has no .claude overlay), so
#      config-get cannot pick up the cwd repo's stale_lock_threshold. Here the
#      cwd is a git repo whose committed config sets a ~190-year threshold: if it
#      leaked in, the back-dated 2020 lock would count as FRESH and the stale
#      break would NOT fire (crash recovery silently disabled). Note NO explicit
#      PLANWRIGHT_LOCAL_CONFIG here — the determinism must come from the
#      REPO_ROOT pin alone, not an override. Regression for the cwd-dependence bug.
# ---------------------------------------------------------------------------
home_cwd="$tmp/cwd-indep-home"
mkdir -p "$home_cwd"
ln -s "crashed-holder" "$home_cwd/.fleet.lock"
touch -h -t 202001010000 "$home_cwd/.fleet.lock" # crashed holder, back-dated to 2020
hostile_repo="$tmp/hostile-cwd-repo"
mkdir -p "$hostile_repo/.claude"
(cd "$hostile_repo" && git init -q) || fail "cwd-indep: could not init the hostile cwd repo"
printf 'stale_lock_threshold: 99999999m\n' >"$hostile_repo/.claude/planwright.yml"
(
  cd "$hostile_repo" \
    && env -u CLAUDE_PLUGIN_DATA -u CLAUDE_DIR -u HOME -u PLANWRIGHT_LOCAL_CONFIG \
      PLANWRIGHT_FLEET_STATE_DIR="$home_cwd" /bin/sh "$FS" bound-incr 3 >/dev/null
) || fail "cwd-indep: stale break did not fire — the cwd repo's threshold leaked into the fleet lock"
[ "$(cat "$home_cwd/concurrency")" = "1" ] || fail "cwd-indep: stale-break recovery did not complete the increment"
echo "ok: the fleet stale threshold is cwd-independent (a hostile repo-local override cannot disable recovery)"

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
  penv lock || fail "perm: could not take the lock to begin with"
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

echo "ALL PASS: fleet-state.sh"
