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
tab=$(printf '\t')

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
for args in "--on-change tower-1 --liveness x" "--on-change tower-1 --liveness 01" \
  "--on-change tower-1 --liveness 9999999999" "--liveness 30" "--on-change --liveness 30"; do
  rc=0
  # shellcheck disable=SC2086 # word-split on purpose: each entry is an argv
  aenv "$home" render $args >/dev/null 2>&1 || rc=$?
  [ "$rc" = 2 ] || fail "render $args exited $rc, expected 2"
done
rc=0
aenv "$home" queue --on-change "../x" >/dev/null 2>&1 || rc=$?
[ "$rc" = 2 ] || fail "queue --on-change '../x' exited $rc, expected 2"
strays=$(find "$home/attention" -name '*-seen.*' ! -name '*-seen.tower-1' ! -name '*-seen.tower-2' -print)
[ -z "$strays" ] || fail "a refused key still left a seen file: $strays"
echo "ok: a hostile key or a malformed interval is refused"

# ---------------------------------------------------------------------------
# 9. The liveness line is periodic: right after one prints, the next quiet
#    iteration inside the interval is silent again.
# ---------------------------------------------------------------------------
aenv "$home" render --on-change tower-1 >/dev/null || fail "liveness setup render"
out=$(aenv "$home" render --on-change tower-1 --liveness 0) || fail "liveness render"
case $out in *"no change"*) ;; *) fail "no liveness line at interval 0 (got: $out)" ;; esac
out=$(aenv "$home" render --on-change tower-1 --liveness 5) || fail "post-liveness render"
[ -z "$out" ] || fail "a second liveness line inside the interval (got: $out)"
echo "ok: the liveness line waits out its interval"

# ---------------------------------------------------------------------------
# 10. The queue ignores a heartbeat re-stamp and a hand-over (--except): the
#     first changes no decision, the second changes only what one call shows.
# ---------------------------------------------------------------------------
qhome="$tmp/qhome"
aenv "$qhome" decide "worker=a" "spec-one:3" "Ship it?" "yes" "yes|no" || fail "q setup: decide a"
aenv "$qhome" decide "worker=b" "spec-two:5" "Rebase?" "no" "yes|no" || fail "q setup: decide b"
out=$(aenv "$qhome" queue --on-change t --except "worker=a" 2>/dev/null) || fail "q: first render"
case $out in *"Ship it?"*) fail "q: --except did not narrow the first render (got: $out)" ;; esac
printf '%s\n' "$out" | grep -q "Rebase?" || fail "q: first render lost the other decision (got: $out)"
out=$(aenv "$qhome" queue --on-change t) || fail "q: render without --except"
[ -z "$out" ] || fail "q: dropping --except alone re-rendered the queue (got: $out)"
qstore="$qhome/attention/state"
awk -F '\t' 'BEGIN { OFS = "\t" } { $4 = $4 - 60; print }' "$qstore" >"$tmp/qrestamped"
cat "$tmp/qrestamped" >"$qstore"
out=$(aenv "$qhome" queue --on-change t) || fail "q: render after re-stamp"
[ -z "$out" ] || fail "q: a heartbeat re-stamp re-rendered the queue (got: $out)"
echo "ok: the queue ignores a re-stamp and a hand-over"

# ---------------------------------------------------------------------------
# 11. With no store yet the queue is silent and records nothing.
# ---------------------------------------------------------------------------
ehome="$tmp/empty-home"
err=$(aenv "$ehome" queue --on-change t 2>&1 >/dev/null) || fail "empty: queue exited non-zero"
[ -z "$err" ] || fail "empty: queue --on-change warned with no store (got: $err)"
[ ! -e "$ehome/attention/queue-seen.t" ] || fail "empty: a seen file was recorded with no store"
echo "ok: no store means nothing to show and nothing recorded"

# ---------------------------------------------------------------------------
# 12. A seen file that cannot be trusted means a full render, never an abort
#     or a skip: a leading-zero stamp (octal, fatal under dash), a stamp in the
#     future, and a seen path that is a directory.
# ---------------------------------------------------------------------------
seen="$home/attention/render-seen.tower-1"
digest=$(cut -f1 "$seen")
for stamps in "08${tab}09" "9999999999${tab}9999999999"; do
  printf '%s\t%s\n' "$digest" "$stamps" >"$seen"
  out=$(aenv "$home" render --on-change tower-1 --liveness 0) \
    || fail "a seen file stamped '$stamps' aborted the render"
  printf '%s\n' "$out" | grep -q "worker=a" \
    || fail "a seen file stamped '$stamps' did not fall back to a full render (got: $out)"
done
rm -f "$home/attention/render-seen.tower-3"
mkdir "$home/attention/render-seen.tower-3"
out=$(aenv "$home" render --on-change tower-3 2>/dev/null) || fail "dir seen path: non-zero exit"
printf '%s\n' "$out" | grep -q "worker=a" || fail "dir seen path: no full render (got: $out)"
[ -z "$(ls -A "$home/attention/render-seen.tower-3")" ] \
  || fail "a seen path that is a directory was written into"
echo "ok: an untrustworthy seen file falls back to a full render"

# ---------------------------------------------------------------------------
# 13. An unreadable store is an error on every call, not an exit-0 skip once
#     its digest has been recorded.
# ---------------------------------------------------------------------------
if [ "$(id -u)" != 0 ]; then
  chmod 000 "$store"
  for _ in 1 2; do
    rc=0
    aenv "$home" render --on-change tower-1 >/dev/null 2>&1 || rc=$?
    [ "$rc" = 2 ] || {
      chmod 600 "$store"
      fail "an unreadable store exited $rc, expected 2"
    }
  done
  chmod 600 "$store"
  echo "ok: an unreadable store is an error every time"
fi

# ---------------------------------------------------------------------------
# 14. A change that empties a view says so. Silence means "unchanged" in this
#     mode, so a queue whose last decision cleared, or a fleet whose last worker
#     did, would otherwise read as still showing what it showed last.
# ---------------------------------------------------------------------------
zhome="$tmp/zhome"
aenv "$zhome" decide "worker=a" "spec-one:3" "Ship it?" "yes" "yes|no" || fail "z setup: decide a"
aenv "$zhome" render --on-change t >/dev/null || fail "z: first render"
aenv "$zhome" queue --on-change t >/dev/null || fail "z: first queue"
aenv "$zhome" clear "worker=a" || fail "z: clear a"
out=$(aenv "$zhome" queue --on-change t) || fail "z: queue after the last decision cleared"
[ -n "$out" ] || fail "z: the queue emptying printed nothing, which reads as unchanged"
out=$(aenv "$zhome" queue --on-change t) || fail "z: queue, still empty"
[ -z "$out" ] || fail "z: an unchanged empty queue re-rendered (got: $out)"
out=$(aenv "$zhome" render --on-change t) || fail "z: render after the last worker cleared"
[ -n "$out" ] || fail "z: the fleet emptying printed nothing, which reads as unchanged"
out=$(aenv "$zhome" render --on-change t) || fail "z: render, still empty"
[ -z "$out" ] || fail "z: an unchanged empty render re-rendered (got: $out)"
out=$(aenv "$zhome" queue) || fail "z: plain queue"
[ -z "$out" ] || fail "z: the plain empty queue is no longer silent (got: $out)"
echo "ok: a change that empties a view is rendered, not silent"

# ---------------------------------------------------------------------------
# 15. The queue refuses an unreadable store under --on-change, as render does,
#     rather than digesting it as empty.
# ---------------------------------------------------------------------------
if [ "$(id -u)" != 0 ]; then
  qstore="$qhome/attention/state"
  chmod 000 "$qstore"
  rc=0
  aenv "$qhome" queue --on-change t >/dev/null 2>&1 || rc=$?
  chmod 600 "$qstore"
  [ "$rc" = 2 ] || fail "queue: an unreadable store exited $rc, expected 2"
  echo "ok: the queue refuses an unreadable store"
fi

echo "all fleet-attention render-on-change tests passed"
