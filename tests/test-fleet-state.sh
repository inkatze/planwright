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
while [ "$i" -lt "$N" ]; do
  env -u CLAUDE_PLUGIN_DATA -u CLAUDE_DIR -u HOME \
    PLANWRIGHT_FLEET_STATE_DIR="$home_reg" \
    /bin/sh "$FS" register "worker=w$i" "spec-$i" &
  i=$((i + 1))
done
wait
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
# 9. Concurrency — the fleet-bound check-and-increment cannot over-count:
#    with a bound of MAX, N concurrent increments yield exactly MAX successes
#    and the counter lands on exactly MAX (no two towers exceed the bound).
# ---------------------------------------------------------------------------
home_bound="$tmp/bound-race"
MAX=5
N=20
okdir="$tmp/bound-results"
mkdir -p "$okdir"
i=0
while [ "$i" -lt "$N" ]; do
  (
    # Capture the granted increment's stdout (the new count) into the marker,
    # so the race also proves each grant PRINTS its unique new-count — not just
    # that it exited 0 and the counter file landed right.
    if out=$(env -u CLAUDE_PLUGIN_DATA -u CLAUDE_DIR -u HOME \
      PLANWRIGHT_FLEET_STATE_DIR="$home_bound" \
      /bin/sh "$FS" bound-incr "$MAX" 2>/dev/null); then
      printf '%s\n' "$out" >"$okdir/$i"
    fi
  ) &
  i=$((i + 1))
done
wait
granted=$(find "$okdir" -type f | wc -l | tr -d ' ')
[ "$granted" = "$MAX" ] || fail "bound race: $granted grants, expected exactly $MAX (over/under-count)"
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

# bound-decr releases a slot and floors at zero.
fenv() {
  env -u CLAUDE_PLUGIN_DATA -u CLAUDE_DIR -u HOME \
    PLANWRIGHT_FLEET_STATE_DIR="$home_bound" /bin/sh "$FS" "$@"
}
# bound-decr prints the new count on stdout (the documented contract Task 6
# consumes); assert the printed value, not only the counter file.
decr_out=$(fenv bound-decr) || fail "bound-decr: non-zero exit"
[ "$decr_out" = "$((MAX - 1))" ] || fail "bound-decr printed '$decr_out', expected $((MAX - 1))"
[ "$(cat "$home_bound/concurrency")" = "$((MAX - 1))" ] || fail "bound-decr did not decrement"
c=$MAX
while [ "$c" -gt 0 ]; do
  fenv bound-decr >/dev/null || fail "bound-decr drain"
  c=$((c - 1))
done
[ "$(cat "$home_bound/concurrency")" = "0" ] || fail "bound-decr floored below zero"
# The floored decr also prints 0 on stdout, not an empty string.
floor_out=$(fenv bound-decr) || fail "bound-decr: floor exit"
[ "$floor_out" = "0" ] || fail "bound-decr at floor printed '$floor_out', expected 0"
echo "ok: bound-decr releases a slot, prints the new count, and floors at zero"

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

# 11c. bound-incr rejects a non-numeric / non-positive bound rather than
#      coercing it into an unbounded counter.
rc=0
fenv bound-incr "notanumber" >/dev/null 2>&1 || rc=$?
[ "$rc" != "0" ] || fail "bound-incr accepted a non-numeric bound"
echo "ok: bound-incr rejects a malformed bound"

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
touch -t 202001010000 "$home_stale/.fleet.lock" # crashed holder, >15m stale
env -u CLAUDE_PLUGIN_DATA -u CLAUDE_DIR -u HOME \
  PLANWRIGHT_FLEET_STATE_DIR="$home_stale" /bin/sh "$FS" bound-incr 3 >/dev/null \
  || fail "stale lock deadlocked a new acquirer (no break/recovery)"
[ "$(cat "$home_stale/concurrency")" = "1" ] || fail "stale-break recovery did not complete the increment"
echo "ok: a crashed holder's stale lock is broken, not a permanent deadlock"

echo "ALL PASS: fleet-state.sh"
