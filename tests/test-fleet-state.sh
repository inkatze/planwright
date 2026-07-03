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
# Every record is well-formed: <epoch>\t<worker>\t<scope>, exactly three fields,
# no interleaving. A torn write would break the field count on some line.
malformed=$(awk -F"$tab" 'NF != 3 || $1 !~ /^[0-9]+$/ { c++ } END { print c + 0 }' "$home_reg/registry")
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
mkdir "$home_ts/.fleet.lock" # hold the lock so register must block
env -u CLAUDE_PLUGIN_DATA -u CLAUDE_DIR -u HOME \
  PLANWRIGHT_FLEET_STATE_DIR="$home_ts" \
  /bin/sh "$FS" register "worker=late" "scope-late" &
reg_pid=$!
sleep 2 # advance the clock while register is blocked on the held lock
t_release=$(date +%s)
rmdir "$home_ts/.fleet.lock" # release; register now acquires and stamps
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
[ ! -d "$home_corrupt/.fleet.lock" ] || fail "bound-incr leaked the lock on a corrupt counter"
[ "$(cat "$home_corrupt/concurrency")" = "1" ] || fail "corrupt-counter recovery did not land the increment at 1"
printf '09\n' >"$home_corrupt/concurrency"
out=$(cenv bound-decr) || fail "bound-decr crashed on a leading-zero counter (should treat it as 0)"
[ "$out" = "0" ] || fail "corrupt counter not treated as 0: bound-decr printed '$out', expected 0"
[ ! -d "$home_corrupt/.fleet.lock" ] || fail "bound-decr leaked the lock on a corrupt counter"
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
[ -d "$home_lock/.fleet.lock" ] || fail "lock: lock dir not created"
rc=0
lenv lock >/dev/null 2>&1 || rc=$?
[ "$rc" = 1 ] || fail "lock: busy acquire exit $rc, expected 1"
lenv unlock || fail "unlock: non-zero exit"
[ ! -d "$home_lock/.fleet.lock" ] || fail "unlock: lock not removed"
lenv unlock || fail "unlock: not idempotent"
echo "ok: the advisory-lock primitive is exclusive, busy-safe, and idempotent"

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
#     property. The concurrent-multi-breaker mutual-exclusion corner of the
#     mkdir stale-break — shared with the sibling orchestrate-lock.sh — is a
#     documented known limitation queued for a lock-discipline follow-up, not
#     asserted here.)
# ---------------------------------------------------------------------------
home_stale="$tmp/stale-home"
mkdir -p "$home_stale"
mkdir "$home_stale/.fleet.lock"
touch -t 202001010000 "$home_stale/.fleet.lock" # crashed holder, back-dated to 2020
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
mkdir "$home_cwd/.fleet.lock"
touch -t 202001010000 "$home_cwd/.fleet.lock" # crashed holder, back-dated to 2020
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

echo "ALL PASS: fleet-state.sh"
