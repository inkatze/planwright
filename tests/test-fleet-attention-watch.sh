#!/bin/bash
# Tests for scripts/fleet-attention-watch.sh — the tower-side attention-store
# event watch (fleet-hardening Task 2: D-2; REQ-A1.2, REQ-E1.3).
#
# The tower learns a worker parked by WATCHING the attention store as an event —
# never by capturing and grep-parsing the worker's pane. The watch reacts to a
# store-row change (a change-detection pass whose callback fires on the write),
# carries a LIVENESS stamp, and runs a periodic full-store RECONCILE sweep so a
# push written before the watch started, or a dead watch, degrades to
# poll-latency rather than silent blindness (the 7-hour gap this closes).
#
# What is covered:
#   - a `pass` fires the on-change callback for a NEW awaiting-human row and
#     emits it to stdout (the event reaction), passing worker / scope / reason
#     so the tower distinguishes a fork-park from a permission / flailing decide;
#   - a `pass` does NOT re-fire an unchanged row, and DOES re-fire a changed one;
#   - a `pass` ignores a non-awaiting (working) row;
#   - `reconcile` fires for EVERY current awaiting-human row regardless of the
#     signature — including a row pushed BEFORE any pass ran (the backstop);
#   - `liveness` reports fresh after a pass and stale/absent when the watch never
#     ran (the dead-watch tell);
#   - `watch --once` runs a single pass and returns (does not hang);
#   - no capture-pane, no jq, no model / network call anywhere in the watch.
#
# Runs standalone under /bin/bash (the bash 3.2 floor).
set -eu
LC_ALL=C
export LC_ALL
unset CDPATH

here=$(cd "$(dirname "$0")" && pwd)
FW="$here/../scripts/fleet-attention-watch.sh"
FA="$here/../scripts/fleet-attention.sh"

fail() {
  echo "FAIL: $1" >&2
  exit 1
}
ok() { echo "ok: $1"; }

[ -x "$FW" ] || fail "scripts/fleet-attention-watch.sh missing or not executable"
[ -x "$FA" ] || fail "scripts/fleet-attention.sh missing or not executable"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# A callback that appends "worker scope reason" to a log, so the test can assert
# the watch fired on the write.
cb="$tmp/cb.sh"
cblog="$tmp/cb.log"
cat >"$cb" <<EOF
#!/bin/sh
printf '%s %s %s\n' "\$1" "\$2" "\$3" >>"$cblog"
EOF
chmod +x "$cb"
: >"$cblog"

aenv() {
  _home=$1
  shift
  env -u CLAUDE_PLUGIN_DATA -u CLAUDE_PLUGIN_ROOT -u CLAUDE_DIR -u HOME \
    -u PLANWRIGHT_ROOT -u PLANWRIGHT_ADOPTER_OVERLAY -u PLANWRIGHT_REPO_ROOT \
    -u PLANWRIGHT_LOCAL_CONFIG -u PLANWRIGHT_CONFIG_DEFAULTS \
    PLANWRIGHT_FLEET_STATE_DIR="$_home" /bin/sh "$1" "${@:2}"
}
park() { aenv "$1" "$FA" park "$2" "$3" "$4"; }
watch() { aenv "$1" "$FW" "${@:2}"; }

# ---------------------------------------------------------------------------
# 1. pass fires the callback + emits on a NEW awaiting-human row (event).
# ---------------------------------------------------------------------------
h1="$tmp/h1"
park "$h1" w1 spec-a "notification:idle_prompt" || fail "park failed"
out=$(watch "$h1" pass --on-change "$cb") || fail "pass exited non-zero"
printf '%s' "$out" | grep -q "w1" || fail "pass did not emit the changed row to stdout: [$out]"
grep -q "^w1 spec-a notification:idle_prompt$" "$cblog" \
  || fail "callback did not fire with worker/scope/reason: [$(cat "$cblog")]"
ok "pass fires the on-change callback and emits the new awaiting-human row (worker/scope/reason)"

# ---------------------------------------------------------------------------
# 2. pass does NOT re-fire an unchanged row.
# ---------------------------------------------------------------------------
before=$(wc -l <"$cblog")
watch "$h1" pass --on-change "$cb" >/dev/null || fail "second pass exited non-zero"
after=$(wc -l <"$cblog")
[ "$before" = "$after" ] || fail "pass re-fired an unchanged row ($before -> $after)"
ok "pass does not re-fire an unchanged row"

# ---------------------------------------------------------------------------
# 3. pass RE-fires when the row changes (a re-park with a new reason).
# ---------------------------------------------------------------------------
# clear then re-park so the reason (and commit-time heartbeat) differ.
aenv "$h1" "$FA" clear w1 || fail "clear failed"
sleep 1
park "$h1" w1 spec-a "notification:agent_needs_input" || fail "re-park failed"
watch "$h1" pass --on-change "$cb" >/dev/null || fail "third pass exited non-zero"
grep -q "^w1 spec-a notification:agent_needs_input$" "$cblog" \
  || fail "pass did not re-fire on a changed row: [$(cat "$cblog")]"
ok "pass re-fires when the awaiting-human row changes"

# ---------------------------------------------------------------------------
# 4. pass ignores a non-awaiting (working) row.
# ---------------------------------------------------------------------------
h4="$tmp/h4"
cblog4="$tmp/cb4.log"
: >"$cblog4"
cb4="$tmp/cb4.sh"
cat >"$cb4" <<EOF
#!/bin/sh
printf '%s\n' "\$1" >>"$cblog4"
EOF
chmod +x "$cb4"
aenv "$h4" "$FA" heartbeat w9 spec-a working || fail "heartbeat failed"
watch "$h4" pass --on-change "$cb4" >/dev/null || fail "pass (working) exited non-zero"
[ ! -s "$cblog4" ] || fail "pass fired for a non-awaiting (working) row: [$(cat "$cblog4")]"
ok "pass ignores a non-awaiting (working) row"

# ---------------------------------------------------------------------------
# 5. reconcile fires for ALL awaiting-human rows regardless of signature,
#    including a row pushed BEFORE any pass ran (the backstop).
# ---------------------------------------------------------------------------
h5="$tmp/h5"
cblog5="$tmp/cb5.log"
: >"$cblog5"
cb5="$tmp/cb5.sh"
cat >"$cb5" <<EOF
#!/bin/sh
printf '%s\n' "\$1" >>"$cblog5"
EOF
chmod +x "$cb5"
# A push written BEFORE the watch established a signature (push-before-watch).
park "$h5" wA spec-a "notification:idle_prompt" || fail "park wA failed"
park "$h5" wB spec-a "notification:idle_prompt" || fail "park wB failed"
watch "$h5" reconcile --on-change "$cb5" >/dev/null || fail "reconcile exited non-zero"
grep -q "^wA$" "$cblog5" || fail "reconcile missed wA (push-before-watch backstop failed)"
grep -q "^wB$" "$cblog5" || fail "reconcile missed wB"
# reconcile is unconditional: a second reconcile fires them again.
: >"$cblog5"
watch "$h5" reconcile --on-change "$cb5" >/dev/null || fail "second reconcile exited non-zero"
grep -q "^wA$" "$cblog5" || fail "reconcile is not unconditional (missed wA on the sweep)"
ok "reconcile fires for every awaiting-human row regardless of signature (the backstop)"

# ---------------------------------------------------------------------------
# 6. liveness: fresh after a pass, stale/absent when the watch never ran.
# ---------------------------------------------------------------------------
h6="$tmp/h6"
rc=0
watch "$h6" liveness --max-age 3600 >/dev/null 2>&1 || rc=$?
[ "$rc" != 0 ] || fail "liveness reported fresh with no watch ever run"
park "$h6" w1 spec-a "notification:idle_prompt" || fail "park failed"
watch "$h6" pass >/dev/null || fail "pass exited non-zero"
rc=0
watch "$h6" liveness --max-age 3600 >/dev/null 2>&1 || rc=$?
[ "$rc" = 0 ] || fail "liveness reported stale immediately after a pass (exit $rc)"
ok "liveness reports fresh after a pass and stale/absent when the watch never ran"

# ---------------------------------------------------------------------------
# 6b. liveness reports STALE (exit 1) when the last pass is older than
#     --max-age — the actual dead-watch tell (test 6 only covered the fresh and
#     never-ran cases, never the staleness boundary the subcommand exists for).
# ---------------------------------------------------------------------------
watch "$h6" pass >/dev/null || fail "pass exited non-zero"
sleep 2
rc=0
watch "$h6" liveness --max-age 1 >/dev/null 2>&1 || rc=$?
[ "$rc" = 1 ] || fail "liveness did not report stale (exit 1) for a pass older than --max-age: exit $rc"
ok "liveness reports stale (the dead-watch tell) when the last pass predates --max-age"

# ---------------------------------------------------------------------------
# 7. watch --once runs a single pass and returns (does not hang).
# ---------------------------------------------------------------------------
h7="$tmp/h7"
cblog7="$tmp/cb7.log"
: >"$cblog7"
cb7="$tmp/cb7.sh"
cat >"$cb7" <<EOF
#!/bin/sh
printf '%s\n' "\$1" >>"$cblog7"
EOF
chmod +x "$cb7"
park "$h7" w1 spec-a "notification:idle_prompt" || fail "park failed"
watch "$h7" watch --once --on-change "$cb7" >/dev/null || fail "watch --once exited non-zero"
grep -q "^w1$" "$cblog7" || fail "watch --once did not run a pass"
ok "watch --once runs a single pass and returns"

# ---------------------------------------------------------------------------
# 7b. The watch fires for a NON-park awaiting-human row (a permission / flailing
#     decide) too, with an empty reason — the tower learns of every
#     awaiting-human cause and distinguishes a fork-park by its non-empty reason.
# ---------------------------------------------------------------------------
h7b="$tmp/h7b"
cblog7b="$tmp/cb7b.log"
: >"$cblog7b"
cb7b="$tmp/cb7b.sh"
cat >"$cb7b" <<EOF
#!/bin/sh
printf '[%s][%s][%s]\n' "\$1" "\$2" "\$3" >>"$cblog7b"
EOF
chmod +x "$cb7b"
aenv "$h7b" "$FA" decide w1 spec-a "Approve?" "hold" "A|B" high >/dev/null || fail "decide failed"
watch "$h7b" pass --on-change "$cb7b" >/dev/null || fail "pass (decide) exited non-zero"
grep -q '^\[w1\]\[spec-a\]\[\]$' "$cblog7b" \
  || fail "watch did not fire for a non-park decide with an empty reason: [$(cat "$cblog7b")]"
ok "the watch fires for a non-park awaiting-human row (decide) with an empty reason"

# ---------------------------------------------------------------------------
# 8. No capture-pane, no jq, no model / network call in EXECUTABLE code.
# ---------------------------------------------------------------------------
code_only() { grep -vE '^[[:space:]]*#' "$1"; }
code_only "$FW" | grep -qE 'capture-pane' && fail "fleet-attention-watch.sh references capture-pane (REQ-A1.2)"
code_only "$FW" | grep -qE '(^|[^A-Za-z_.])jq([^A-Za-z_]|$)' && fail "fleet-attention-watch.sh invokes jq (REQ-K1.5)"
code_only "$FW" | grep -qiE '(^|[^A-Za-z_.])(claude|anthropic|curl|wget)([^A-Za-z_]|$)' \
  && fail "fleet-attention-watch.sh references a model / network call (REQ-E1.3)"
ok "no capture-pane, no jq, no model / network call in the watch (REQ-A1.2, REQ-E1.3)"

echo "PASS: fleet-attention-watch"
