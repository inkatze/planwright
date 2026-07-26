#!/bin/bash
# Tests for scripts/fleet-dashboard.sh — the rendered status dashboard
# (execution-backends Task 8: D-10, REQ-D1.2).
#
# REQ-D1.2 `[test]`: dashboard render fixtures assert the output is produced
# from the shared source-merging layer (no second source-reading
# implementation) and covers the same source-availability matrix as the CLI
# view, missing sources marked visibly; an output-encoding fixture asserts
# script-tag/markup content in worker-authored strings renders inert; the
# surface exposes no state-mutating endpoint (read-only assertion).
#
# HOW THE MERGE-LAYER REUSE IS PROVEN. Each render runs a COPY of the
# dashboard from a temp dir whose only sibling `fleet-status.sh` is a shim
# that logs its arguments and cats a fixture merge stream. If the dashboard
# read any source a second way, the fixture-only content could not be the
# whole of its output — and the shim log pins the one call it is allowed to
# make (`merge`). A structural grep over the real script backs it up: the
# dashboard names no raw source.
#
# Runs standalone under /bin/bash (the bash 3.2 floor):
#   ./tests/test-fleet-dashboard.sh
set -eu
LC_ALL=C
export LC_ALL
unset CDPATH

here=$(cd "$(dirname "$0")" && pwd)
DASH="$here/../scripts/fleet-dashboard.sh"
ES="$here/../scripts/echo-safety.sh"

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

[ -x "$DASH" ] || fail "scripts/fleet-dashboard.sh missing or not executable"
[ -r "$ES" ] || fail "scripts/echo-safety.sh missing"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

tab=$(printf '\t')

# --- the sandbox: a dashboard copy beside a shimmed fleet-status.sh ---------
bin="$tmp/bin"
mkdir -p "$bin"
cp "$DASH" "$bin/fleet-dashboard.sh"
cp "$ES" "$bin/echo-safety.sh"
chmod +x "$bin/fleet-dashboard.sh"

fixture="$tmp/merge.tsv"
shimlog="$tmp/shim.log"
shim_rc="$tmp/shim.rc"
shim_delay="$tmp/shim.delay"
echo 0 >"$shim_rc"
echo 0 >"$shim_delay"
# Every line below is literal shim source: the `$*`/`$rc` expansions and the
# `\n` belong to the shim at ITS runtime, not to this test. The log line is
# written BEFORE the optional delay, so a test can tell when a render is
# in flight and signal it there.
# shellcheck disable=SC2016,SC2028
{
  echo '#!/bin/sh'
  echo 'printf "%s\n" "$*" >>'"'$shimlog'"
  echo 'rc=$(cat '"'$shim_rc'"')'
  echo '[ "$rc" -eq 0 ] || exit "$rc"'
  echo 'delay=$(cat '"'$shim_delay'"')'
  echo '[ "$delay" -eq 0 ] || sleep "$delay"'
  echo "cat '$fixture'"
} >"$bin/fleet-status.sh"
chmod +x "$bin/fleet-status.sh"

DASHC="$bin/fleet-dashboard.sh"

reset_shim() {
  : >"$shimlog"
  echo 0 >"$shim_rc"
  echo 0 >"$shim_delay"
}

# write_fixture <lines...> — each argument is one merge line with fields
# separated by the literal string '|' (rewritten to tabs).
write_fixture() {
  : >"$fixture"
  for wf_line in "$@"; do
    printf '%s\n' "$wf_line" | tr '|' "$tab" >>"$fixture"
  done
}

contains() {
  case $2 in
    *"$1"*) return 0 ;;
  esac
  return 1
}

assert_has() {
  contains "$1" "$3" || fail "$2: expected to contain '$1'"
}

assert_lacks() {
  contains "$1" "$3" && fail "$2: expected NOT to contain '$1'"
  return 0
}

# --- full-availability fixture (the all-sources-ok baseline) ----------------
full_fixture() {
  write_fixture \
    'source|attention|ok|2-rows' \
    'source|streamjson|ok|2-workers' \
    'source|oracle|ok|2-rows' \
    'source|registry|ok|3-records' \
    'worker|w-alpha|specs/a/task-1|attention,streamjson|working|12|running|0|busy' \
    'worker|w-beta|specs/b/task-2|attention|awaiting-input|400|-|-|-' \
    'worker|w-print|specs/c/task-3|registry|-|-|-|-|-' \
    'session|sid-loose|idle|interactive|operator|/home/op'
}

# ===========================================================================
# 1. The output comes from the shared merge layer, called exactly once.
# ===========================================================================
reset_shim
full_fixture
out=$("$DASHC" render) || fail "render: nonzero exit on the baseline fixture"
assert_has 'w-alpha' 'merge-reuse' "$out"
assert_has 'w-beta' 'merge-reuse' "$out"
assert_has 'w-print' 'merge-reuse' "$out"
assert_has 'sid-loose' 'merge-reuse' "$out"
calls=$(wc -l <"$shimlog" | tr -d ' ')
[ "$calls" = 1 ] || fail "merge-reuse: expected exactly 1 fleet-status.sh call, got $calls"
[ "$(cat "$shimlog")" = "merge" ] \
  || fail "merge-reuse: expected the call to be 'merge', got '$(cat "$shimlog")'"

# ===========================================================================
# 2. No second source-reading implementation (structural).
# ===========================================================================
# Comment lines are stripped first: the assertion is about what the script
# DOES, and the header comment has to be free to name the sources the merge
# layer reads on the dashboard's behalf.
code=$(grep -v '^[[:space:]]*#' "$DASH")
for forbidden in 'attention/state' 'agents --json' 'fleet-liveness.sh' \
  'fleet-streamjson.sh' 'fleet-state.sh'; do
  if contains "$forbidden" "$code"; then
    fail "second-source: fleet-dashboard.sh reads the raw source '$forbidden'"
  fi
done

# ===========================================================================
# 3. The document shell: doctype, charset, viewport, CSP, refresh, stamp.
# ===========================================================================
assert_has '<!DOCTYPE html>' 'doc-shell' "$out"
assert_has 'charset="utf-8"' 'doc-shell' "$out"
assert_has 'name="viewport"' 'doc-shell' "$out"
assert_has 'Content-Security-Policy' 'doc-shell' "$out"
assert_has "http-equiv=\"refresh\" content=\"30\"" 'doc-shell' "$out"
assert_has 'generated ' 'doc-shell' "$out"
# The freshness stamp is a real UTC instant, not a placeholder: a stale page
# has to be readable as stale (the Task 7 poller observation).
echo "$out" | grep -Eq 'generated [0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z' \
  || fail "doc-shell: no ISO-8601 UTC generated stamp"

# --interval drives both the meta refresh and the stated cadence.
reset_shim
out5=$("$DASHC" render --interval 5) || fail "render --interval: nonzero exit"
assert_has 'http-equiv="refresh" content="5"' 'interval' "$out5"

# ===========================================================================
# 4. Read-only: no state-mutating endpoint, no script, no event handlers.
# ===========================================================================
for banned in '<form' '<input' '<button' '<textarea' '<script' 'action=' \
  'method=' 'onclick' 'onload' 'onerror' 'javascript:'; do
  assert_lacks "$banned" 'read-only' "$out"
done

# ===========================================================================
# 5. The source-availability matrix, every state, every source named.
# ===========================================================================
matrix_case() {
  # matrix_case <attn-state> <sj-state> <oracle-state> <reg-state>
  reset_shim
  write_fixture \
    "source|attention|$1|d-attn" \
    "source|streamjson|$2|d-sj" \
    "source|oracle|$3|d-oracle" \
    "source|registry|$4|d-registry" \
    'worker|w-only|specs/a/task-1|attention|working|3|-|-|-'
  mc_out=$("$DASHC" render) || fail "matrix($1/$2/$3/$4): nonzero exit"
  for mc_src in attention streamjson oracle registry; do
    assert_has "$mc_src" "matrix($1/$2/$3/$4)" "$mc_out"
  done
  for mc_state in "$1" "$2" "$3" "$4"; do
    assert_has "src-$mc_state" "matrix($1/$2/$3/$4)" "$mc_out"
  done
  # The detail token rides along, so the diagnostic is not lost.
  for mc_d in d-attn d-sj d-oracle d-registry; do
    assert_has "$mc_d" "matrix($1/$2/$3/$4)" "$mc_out"
  done
  # The worker the available source contributed is still rendered.
  assert_has 'w-only' "matrix($1/$2/$3/$4)" "$mc_out"
}

matrix_case ok ok ok ok
matrix_case absent ok ok ok
matrix_case unavailable ok ok ok
matrix_case ok absent ok ok
matrix_case ok unavailable ok ok
matrix_case ok ok absent ok
matrix_case ok ok unavailable ok
matrix_case ok ok ok absent
matrix_case ok ok ok unavailable
matrix_case absent absent absent absent
matrix_case unavailable unavailable unavailable unavailable

# A degraded source is marked in words, not by colour alone.
reset_shim
write_fixture \
  'source|attention|unavailable|unreadable-store' \
  'source|streamjson|absent|no-runtime-dirs' \
  'source|oracle|ok|1-rows' \
  'source|registry|ok|1-records' \
  'worker|w1|specs/a/task-1|registry|-|-|-|-|?'
degraded=$("$DASHC" render) || fail "degraded: nonzero exit"
assert_has 'unavailable' 'degraded' "$degraded"
assert_has 'unreadable-store' 'degraded' "$degraded"
assert_has 'absent' 'degraded' "$degraded"
assert_has 'no-runtime-dirs' 'degraded' "$degraded"
# The `?` cell is degraded evidence, never an invented verdict.
assert_has 'v-unknown' 'degraded' "$degraded"
assert_lacks '>busy<' 'degraded' "$degraded"

# A merge stream carrying no source line at all is itself marked, not shown
# as an empty (and therefore reassuring) source list.
reset_shim
write_fixture 'worker|w1|specs/a/task-1|attention|working|3|-|-|-'
nosrc=$("$DASHC" render) || fail "no-source-line: nonzero exit"
assert_has 'src-other' 'no-source-line' "$nosrc"
assert_has 'empty merge stream' 'no-source-line' "$nosrc"
assert_has 'w1' 'no-source-line' "$nosrc"

# ===========================================================================
# 6. A registry-only worker renders with a visible not-applicable marker.
# ===========================================================================
reset_shim
full_fixture
regonly=$("$DASHC" render) || fail "registry-only: nonzero exit"
assert_has 'w-print' 'registry-only' "$regonly"
assert_has 'v-na' 'registry-only' "$regonly"

# ===========================================================================
# 7. Output encoding: worker-authored markup renders inert.
# ===========================================================================
reset_shim
write_fixture \
  'source|attention|ok|1-rows' \
  'source|streamjson|ok|1-workers' \
  'source|oracle|ok|1-rows' \
  'source|registry|ok|1-records' \
  'worker|<script>alert(1)</script>|a&b "q" '"'"'s'"'"'|attention|working|1|-|-|-' \
  'session|sid<img src=x onerror=alert(1)>|idle|interactive|<b>name</b>|/tmp/&'
enc=$("$DASHC" render) || fail "encoding: nonzero exit"
assert_lacks '<script>alert(1)</script>' 'encoding' "$enc"
assert_lacks '<img src=x' 'encoding' "$enc"
assert_lacks '<b>name</b>' 'encoding' "$enc"
assert_has '&lt;script&gt;alert(1)&lt;/script&gt;' 'encoding' "$enc"
assert_has '&lt;img src=x onerror=alert(1)&gt;' 'encoding' "$enc"
assert_has 'a&amp;b' 'encoding' "$enc"
assert_has '&quot;q&quot;' 'encoding' "$enc"
assert_has '&#39;s&#39;' 'encoding' "$enc"
# The whole document stays script-free even under injected markup. (The
# `onerror=` text survives inside the escaped session id — inert, because its
# angle brackets are entities, so there is no tag for it to be an attribute
# of. What must not survive is a real tag.)
assert_lacks '<script' 'encoding' "$enc"
assert_lacks '<img' 'encoding' "$enc"

# ===========================================================================
# 8. Attention-first ordering: what needs the operator sorts to the top.
# ===========================================================================
reset_shim
write_fixture \
  'source|attention|ok|3-rows' \
  'source|streamjson|ok|3-workers' \
  'source|oracle|ok|3-rows' \
  'source|registry|ok|3-records' \
  'worker|w-aaa-working|specs/a/task-1|attention|working|5|running|0|busy' \
  'worker|w-mmm-done|specs/b/task-2|attention|pr-ready|9|-|0|idle' \
  'worker|w-zzz-blocked|specs/c/task-3|attention|awaiting-input|60|-|0|-'
ord=$("$DASHC" render) || fail "ordering: nonzero exit"
pos_blocked=$(printf '%s\n' "$ord" | grep -n 'w-zzz-blocked' | head -n 1 | cut -d: -f1)
pos_working=$(printf '%s\n' "$ord" | grep -n 'w-aaa-working' | head -n 1 | cut -d: -f1)
pos_done=$(printf '%s\n' "$ord" | grep -n 'w-mmm-done' | head -n 1 | cut -d: -f1)
[ -n "$pos_blocked" ] && [ -n "$pos_working" ] && [ -n "$pos_done" ] \
  || fail "ordering: a worker went missing from the render"
[ "$pos_blocked" -lt "$pos_working" ] \
  || fail "ordering: awaiting-input worker did not sort above the working one"
[ "$pos_working" -lt "$pos_done" ] \
  || fail "ordering: working worker did not sort above the finished one"
assert_has '1 worker needs you' 'ordering' "$ord"

# A pending stream-json request and an oracle `waiting` each raise attention.
reset_shim
write_fixture \
  'source|attention|ok|2-rows' \
  'source|streamjson|ok|2-workers' \
  'source|oracle|ok|2-rows' \
  'source|registry|absent|no-records' \
  'worker|w-pend|specs/a/task-1|streamjson|-|-|running|2|-' \
  'worker|w-wait|specs/b/task-2|streamjson|-|-|running|0|waiting'
attn=$("$DASHC" render) || fail "attention-triggers: nonzero exit"
assert_has '2 workers need you' 'attention-triggers' "$attn"

# Nothing pending reads as an explicit all-clear, not an empty gap.
reset_shim
write_fixture \
  'source|attention|ok|1-rows' \
  'source|streamjson|absent|no-runtime-dirs' \
  'source|oracle|absent|0-rows' \
  'source|registry|absent|no-records' \
  'worker|w-calm|specs/a/task-1|attention|working|4|-|-|-'
calm=$("$DASHC" render) || fail "all-clear: nonzero exit"
assert_has 'no worker needs you' 'all-clear' "$calm"

# ===========================================================================
# 9. Empty fleet: sources still marked, emptiness stated, exit 0.
# ===========================================================================
reset_shim
write_fixture \
  'source|attention|absent|no-store' \
  'source|streamjson|absent|no-runtime-dirs' \
  'source|oracle|absent|0-rows' \
  'source|registry|absent|no-records'
empty=$("$DASHC" render) || fail "empty: nonzero exit"
assert_has 'no workers' 'empty' "$empty"
for s in attention streamjson oracle registry; do
  assert_has "$s" 'empty' "$empty"
done

# ===========================================================================
# 10. Fail closed: a merge failure is never a half-rendered page.
# ===========================================================================
reset_shim
full_fixture
echo 2 >"$shim_rc"
set +e
badout=$("$DASHC" render 2>"$tmp/err")
badrc=$?
set -e
[ "$badrc" -eq 2 ] || fail "fail-closed: expected exit 2 on a merge failure, got $badrc"
[ -z "$badout" ] || fail "fail-closed: emitted output despite the merge failure"

# ===========================================================================
# 11. `write --out`: atomic, owner-only, no residue, no clobber on failure.
# ===========================================================================
reset_shim
full_fixture
target="$tmp/out/fleet.html"
mkdir -p "$tmp/out"
"$DASHC" write --out "$target" || fail "write: nonzero exit"
[ -f "$target" ] || fail "write: no file produced"
assert_has '<!DOCTYPE html>' 'write' "$(cat "$target")"
assert_has 'w-alpha' 'write' "$(cat "$target")"
# `ls -l` over a known-good literal path: the portable mode read on the
# macOS + Linux support bar (`stat` disagrees between BSD and GNU).
# shellcheck disable=SC2012
mode=$(ls -l "$target" | cut -c1-10)
[ "$mode" = "-rw-------" ] || fail "write: expected owner-only 0600, got '$mode'"
# No temp residue beside the target.
residue=$(find "$tmp/out" -name '.planwright-dash*' | wc -l | tr -d ' ')
[ "$residue" = 0 ] || fail "write: left $residue temp file(s) beside the target"

# A failing merge leaves the previous good page untouched.
reset_shim
echo 2 >"$shim_rc"
set +e
"$DASHC" write --out "$target" 2>/dev/null
wrc=$?
set -e
[ "$wrc" -eq 2 ] || fail "write-fail-closed: expected exit 2, got $wrc"
assert_has 'w-alpha' 'write-fail-closed' "$(cat "$target")"
residue=$(find "$tmp/out" -name '.planwright-dash*' | wc -l | tr -d ' ')
[ "$residue" = 0 ] || fail "write-fail-closed: left $residue temp file(s)"

# ===========================================================================
# 12. `watch`: re-renders on the interval, exits on TERM.
# ===========================================================================
reset_shim
full_fixture
wtarget="$tmp/out/watched.html"
"$DASHC" watch --out "$wtarget" --interval 1 >/dev/null 2>&1 &
wpid=$!
waited=0
while [ "$waited" -lt 100 ]; do
  n=$(wc -l <"$shimlog" | tr -d ' ')
  [ "$n" -ge 2 ] && break
  sleep 0.1 2>/dev/null || sleep 1
  waited=$((waited + 1))
done
n=$(wc -l <"$shimlog" | tr -d ' ')
kill -TERM "$wpid" 2>/dev/null || true
wait "$wpid" 2>/dev/null || true
[ "$n" -ge 2 ] || fail "watch: expected repeated renders, saw $n"
[ -f "$wtarget" ] || fail "watch: no file produced"

# A signal that lands MID-RENDER cleans up after itself. `watch` is stopped
# with a signal by design, so a temp left beside the target on every stop
# would accumulate in the operator's output directory run after run.
reset_shim
full_fixture
echo 3 >"$shim_delay"
mkdir -p "$tmp/sig"
sigtarget="$tmp/sig/page.html"
"$DASHC" watch --out "$sigtarget" --interval 1 >/dev/null 2>&1 &
spid=$!
waited=0
while [ "$waited" -lt 100 ]; do
  [ -s "$shimlog" ] && break
  sleep 0.1 2>/dev/null || sleep 1
  waited=$((waited + 1))
done
[ -s "$shimlog" ] || fail "signal-cleanup: the render never started"
kill -TERM "$spid" 2>/dev/null || true
wait "$spid" 2>/dev/null || true
residue=$(find "$tmp/sig" -name '.planwright-dash*' | wc -l | tr -d ' ')
[ "$residue" = 0 ] \
  || fail "signal-cleanup: TERM mid-render left $residue temp file(s) beside the target"
reset_shim

# A merge failure MID-LOOP stops `watch` instead of looping blind: a loop that
# keeps running while writing nothing is worse than one that stops, because the
# page's generated-at stamp is what tells an away operator it went stale. The
# last good page survives the failed iteration untouched.
reset_shim
full_fixture
ftarget="$tmp/out/failwatch.html"
"$DASHC" watch --out "$ftarget" --interval 1 >/dev/null 2>&1 &
fpid=$!
waited=0
while [ "$waited" -lt 100 ]; do
  [ -f "$ftarget" ] && break
  sleep 0.1 2>/dev/null || sleep 1
  waited=$((waited + 1))
done
[ -f "$ftarget" ] || fail "watch-fail-closed: the first page was never written"
echo 2 >"$shim_rc"
# A watchdog bounds the wait, so a watch that keeps looping fails the assertion
# instead of hanging the suite. Its firing IS the failure signal.
fired="$tmp/watchdog.fired"
(
  sleep 20
  kill -TERM "$fpid" 2>/dev/null && : >"$fired"
) &
kpid=$!
set +e
wait "$fpid"
fwrc=$?
set -e
kill "$kpid" 2>/dev/null || true
wait "$kpid" 2>/dev/null || true
[ -f "$fired" ] \
  && fail "watch-fail-closed: watch kept looping after the merge started failing"
[ "$fwrc" -eq 2 ] || fail "watch-fail-closed: expected exit 2, got $fwrc"
assert_has 'w-alpha' 'watch-fail-closed' "$(cat "$ftarget")"
residue=$(find "$tmp/out" -name '.planwright-dash*' | wc -l | tr -d ' ')
[ "$residue" = 0 ] || fail "watch-fail-closed: left $residue temp file(s)"
reset_shim

# A pacing `sleep` that will not run stops the loop too — the other half of the
# fail-closed watch contract. Unchecked, the loop would keep re-rendering with
# no pacing at all, paying a full merge (an uncached oracle probe plus a
# per-worker stream-json fan-out) per iteration. `sleep` is shimmed on PATH
# because a validated --interval can no longer make the real one fail: the
# digit cap closed the route that used to get here.
reset_shim
full_fixture
mkdir -p "$tmp/nosleep"
printf '%s\n' '#!/bin/sh' 'exit 1' >"$tmp/nosleep/sleep"
chmod +x "$tmp/nosleep/sleep"
sltarget="$tmp/out/sleepfail.html"
PATH="$tmp/nosleep:$PATH" "$DASHC" watch --out "$sltarget" --interval 1 >/dev/null 2>&1 &
slpid=$!
# Same watchdog discipline as above: a spinning loop must fail the assertion,
# never hang the suite.
slfired="$tmp/sleep-watchdog.fired"
(
  sleep 20
  kill -TERM "$slpid" 2>/dev/null && : >"$slfired"
) &
slkpid=$!
set +e
wait "$slpid"
slrc=$?
set -e
kill "$slkpid" 2>/dev/null || true
wait "$slkpid" 2>/dev/null || true
[ -f "$slfired" ] \
  && fail "watch-sleep-fail: watch kept looping after the pacing sleep failed"
[ "$slrc" -eq 2 ] || fail "watch-sleep-fail: expected exit 2, got $slrc"
# One render, then the stop: proof it did not spin before exiting.
sln=$(wc -l <"$shimlog" | tr -d ' ')
[ "$sln" -eq 1 ] || fail "watch-sleep-fail: expected 1 render before the stop, saw $sln"
[ -f "$sltarget" ] || fail "watch-sleep-fail: the first page was never written"
residue=$(find "$tmp/out" -name '.planwright-dash*' | wc -l | tr -d ' ')
[ "$residue" = 0 ] || fail "watch-sleep-fail: left $residue temp file(s)"
reset_shim

# ===========================================================================
# 13. Usage errors fail closed with exit 2.
# ===========================================================================
usage_case() {
  set +e
  uc_out=$("$DASHC" "$@" 2>&1 >/dev/null)
  uc_rc=$?
  set -e
  [ "$uc_rc" -eq 2 ] || fail "usage($*): expected exit 2, got $uc_rc"
  [ -n "$uc_out" ] || fail "usage($*): no diagnostic on stderr"
}

set +e
"$DASHC" >/dev/null 2>&1
rc=$?
set -e
[ "$rc" -eq 2 ] || fail "usage(no args): expected exit 2, got $rc"

reset_shim
full_fixture
usage_case bogus
usage_case render --bogus
usage_case render --interval
usage_case render --interval abc
usage_case render --interval 0
usage_case render --interval -5
# A leading zero would read as octal in the range arithmetic, so it is refused
# outright rather than silently reinterpreted.
usage_case render --interval 01
# The upper bound is closed at 86400: one second past it is a usage error, the
# bound itself is accepted.
usage_case render --interval 86401
# An all-digit value too long for shell arithmetic has to be refused by a
# length cap BEFORE it reaches `-lt`/`-gt`: both comparisons ERROR on an
# oversized operand (they do not simply compare false), so the range check
# fails open and the value is accepted. Under `watch` that lands in `sleep`,
# which cannot parse it either, and the loop spins at full render speed. Same
# 15-digit overflow guard fleet-throttle.sh and fleet-audit.sh carry.
usage_case render --interval 999999999999999999999
# ...and refused BY THE CAP, not incidentally by the range test. A 21-digit
# value would exit 2 either way once the hole is closed, so the diagnostic is
# what pins which guard fired: without the cap the range test errors out and
# the value is ACCEPTED, so this assertion is the one with teeth.
set +e
ovf=$("$DASHC" render --interval 999999999999999999999 2>&1 >/dev/null)
set -e
case $ovf in
  *"overflow guard"*) ;;
  *) fail "interval-overflow: refused, but not by the overflow guard: $ovf" ;;
esac
reset_shim
"$DASHC" render --interval 86400 >/dev/null \
  || fail "interval-bound: --interval 86400 (the bound itself) was refused"
# `render` writes stdout, so --out is meaningless there and is refused
# rather than silently ignored (which would look like a file was written).
usage_case render --out "$tmp/out/never.html"
if [ -e "$tmp/out/never.html" ]; then
  fail "usage(render --out): wrote a file anyway"
fi
usage_case write
usage_case write --out ''
usage_case write --out "$tmp/out"
usage_case write --out "$tmp/no-such-dir/page.html"
usage_case watch

# An unprintable flag is sanitized before it reaches the terminal.
esc_char=$(printf '\033')
set +e
badflag=$("$DASHC" render "${esc_char}[31m--x" 2>&1 >/dev/null)
set -e
case $badflag in
  *"$esc_char"*) fail "usage: raw escape byte reached stderr" ;;
esac

echo "ok: fleet-dashboard tests passed"
