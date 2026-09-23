#!/bin/bash
# Tests for fleet-attention.sh's render-on-transition mode (`render --on-change
# <key>` and `queue --on-change <key>`), the watch loop's attention render.
#
# REQ-K1.3 (operator-dialogue): the watch-loop attention render SHALL NOT
# re-render in full on every iteration. It renders on a derived-state
# transition (a worker's state, scope, or decision changing; a heartbeat
# re-stamp excluded), and otherwise prints nothing, or one liveness line once
# the liveness interval has passed so silence stays distinguishable from a dead
# loop. A bounded line or a no-op both pass; an unchanged full re-render fails.
#
# Hermetic: every case drives its own fleet home through the
# PLANWRIGHT_FLEET_STATE_DIR override, with the ambient resolution knobs
# stripped. Runs standalone under /bin/bash (bash 3.2).
set -eu
LC_ALL=C
export LC_ALL
unset CDPATH

here=$(cd "$(dirname "$0")" && pwd)
FA="$here/../scripts/fleet-attention.sh"

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

[ -x "$FA" ] || fail "scripts/fleet-attention.sh missing or not executable"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

aenv() {
  _home=$1
  shift
  env -u CLAUDE_PLUGIN_DATA -u CLAUDE_PLUGIN_ROOT -u CLAUDE_DIR -u HOME \
    -u PLANWRIGHT_ROOT -u PLANWRIGHT_ADOPTER_OVERLAY -u PLANWRIGHT_REPO_ROOT \
    -u PLANWRIGHT_LOCAL_CONFIG -u PLANWRIGHT_CONFIG_DEFAULTS \
    PLANWRIGHT_FLEET_STATE_DIR="$_home" /bin/sh "$FA" "$@"
}

home="$tmp/home"
aenv "$home" heartbeat "worker=a" "spec-one:3" working || fail "setup: heartbeat a"
aenv "$home" heartbeat "worker=b" "spec-two:5" working || fail "setup: heartbeat b"

# ---------------------------------------------------------------------------
# 1. The first on-change render for a key is a full render.
# ---------------------------------------------------------------------------
out=$(aenv "$home" render --on-change tower-1) || fail "first on-change render: non-zero exit"
printf '%s\n' "$out" | grep -q "worker=a" || fail "first on-change render did not list worker=a (got: $out)"
printf '%s\n' "$out" | grep -q "worker=b" || fail "first on-change render did not list worker=b (got: $out)"
echo "ok: the first on-change render for a key is a full render"

# ---------------------------------------------------------------------------
# 2. The skip: with no derived-state transition since that render, the next
#    iteration's render does not re-render in full. Inside the liveness
#    interval it prints nothing.
# ---------------------------------------------------------------------------
out=$(aenv "$home" render --on-change tower-1) || fail "unchanged on-change render: non-zero exit"
case $out in
  *"worker=a"* | *"worker=b"*) fail "no transition occurred, yet the render re-rendered in full (got: $out)" ;;
esac
[ -z "$out" ] || fail "no transition inside the liveness interval should print nothing (got: $out)"
echo "ok: an unchanged iteration skips the full re-render"

# ---------------------------------------------------------------------------
# 3. A heartbeat re-stamp is not a transition: moving every row's timestamp
#    (the field a heartbeat refreshes) still skips.
# ---------------------------------------------------------------------------
store="$home/attention/state"
[ -f "$store" ] || fail "no attention store at $store"
awk -F '\t' 'BEGIN { OFS = "\t" } { $4 = $4 - 60; print }' "$store" >"$tmp/restamped"
cat "$tmp/restamped" >"$store"
out=$(aenv "$home" render --on-change tower-1) || fail "re-stamped on-change render: non-zero exit"
[ -z "$out" ] || fail "a heartbeat re-stamp alone re-rendered (got: $out)"
echo "ok: a heartbeat re-stamp is not a transition"

# ---------------------------------------------------------------------------
# 4. The liveness line: once the interval has passed, an unchanged iteration
#    prints exactly one line, never the worker rows.
# ---------------------------------------------------------------------------
out=$(aenv "$home" render --on-change tower-1 --liveness 0) || fail "liveness render: non-zero exit"
n=$(printf '%s\n' "$out" | grep -c . || true)
[ "$n" = 1 ] || fail "liveness: expected one line, got $n (got: $out)"
case $out in
  *"worker=a"* | *"worker=b"*) fail "liveness line carried worker rows (got: $out)" ;;
  *"no change"*) ;;
  *) fail "liveness line does not say nothing changed (got: $out)" ;;
esac
echo "ok: an unchanged iteration past the liveness interval prints one liveness line"

# ---------------------------------------------------------------------------
# 5. A transition renders in full again: a state change, then a new worker.
# ---------------------------------------------------------------------------
aenv "$home" heartbeat "worker=b" "spec-two:5" pr-ready || fail "transition: heartbeat b"
out=$(aenv "$home" render --on-change tower-1) || fail "post-transition render: non-zero exit"
printf '%s\n' "$out" | grep -q "^\[pr-ready\] spec-two:5  worker=b" \
  || fail "a state transition did not re-render (got: $out)"
printf '%s\n' "$out" | grep -q "worker=a" || fail "the re-render dropped the unchanged worker (got: $out)"
out=$(aenv "$home" render --on-change tower-1) || fail "settled render: non-zero exit"
[ -z "$out" ] || fail "the render after a transition settled did not skip (got: $out)"
aenv "$home" heartbeat "worker=c" "spec-one:4" working || fail "transition: heartbeat c"
out=$(aenv "$home" render --on-change tower-1) || fail "new-worker render: non-zero exit"
printf '%s\n' "$out" | grep -q "worker=c" || fail "a new worker did not re-render (got: $out)"
echo "ok: a derived-state transition renders in full"

# ---------------------------------------------------------------------------
# 6. Keys are independent: a second tower's first render is full even though
#    the first tower already saw this state; the plain render never skips.
# ---------------------------------------------------------------------------
out=$(aenv "$home" render --on-change tower-2) || fail "second key render: non-zero exit"
printf '%s\n' "$out" | grep -q "worker=a" || fail "a second key inherited the first key's skip (got: $out)"
for _ in 1 2; do
  out=$(aenv "$home" render) || fail "plain render: non-zero exit"
  printf '%s\n' "$out" | grep -q "worker=a" || fail "the plain render skipped (got: $out)"
done
echo "ok: on-change keys are independent and the plain render is unchanged"

# ---------------------------------------------------------------------------
# 7. The decision queue follows the same rule: a queued decision renders once,
#    an unchanged queue is silent, a new decision renders the queue again.
# ---------------------------------------------------------------------------
aenv "$home" decide "worker=a" "spec-one:3" "Ship it?" "yes" "yes|no" || fail "queue setup: decide a"
out=$(aenv "$home" queue --on-change tower-1) || fail "first on-change queue: non-zero exit"
printf '%s\n' "$out" | grep -q "Ship it?" || fail "first on-change queue did not render the decision (got: $out)"
out=$(aenv "$home" queue --on-change tower-1) || fail "unchanged on-change queue: non-zero exit"
[ -z "$out" ] || fail "an unchanged queue re-rendered (got: $out)"
aenv "$home" decide "worker=b" "spec-two:5" "Rebase?" "no" "yes|no" || fail "queue setup: decide b"
out=$(aenv "$home" queue --on-change tower-1) || fail "changed on-change queue: non-zero exit"
printf '%s\n' "$out" | grep -q "Rebase?" || fail "a new decision did not re-render the queue (got: $out)"
printf '%s\n' "$out" | grep -q "Ship it?" || fail "the queue re-render dropped the older decision (got: $out)"
[ "$(aenv "$home" queue --count)" = 2 ] || fail "--count is not the full awaiting count"
echo "ok: the decision queue renders on change only"

# ---------------------------------------------------------------------------
# 8. A key outside the field grammar is refused before it reaches a path.
# ---------------------------------------------------------------------------
for bad in "../x" "a/b" "" ".."; do
  rc=0
  aenv "$home" render --on-change "$bad" >/dev/null 2>&1 || rc=$?
  [ "$rc" = 2 ] || fail "render --on-change '$bad' exited $rc, expected 2"
done
rc=0
aenv "$home" render --on-change >/dev/null 2>&1 || rc=$?
[ "$rc" = 2 ] || fail "render --on-change with no key exited $rc, expected 2"
rc=0
aenv "$home" render --on-change tower-1 --liveness x >/dev/null 2>&1 || rc=$?
[ "$rc" = 2 ] || fail "render --liveness x exited $rc, expected 2"
[ ! -e "$tmp/x" ] || fail "a hostile key wrote outside the fleet home"
echo "ok: a hostile key or a malformed interval is refused"

echo "all fleet-attention render-on-change tests passed"
