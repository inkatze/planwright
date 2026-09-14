#!/bin/bash
# Tests for scripts/fleet-liveness.sh `hook notification` — the fork-park
# attention signal (fleet-hardening Task 2: D-2; REQ-A1.1, REQ-A1.2, REQ-E1.2,
# REQ-E1.3).
#
# The native Claude Code `Notification` hook fires the instant a worker parks
# for human input. This arm reads the hook payload's `notification_type` (with
# awk, never jq — REQ-K1.5), gates on it, and for a genuine fork / input-wait
# park pushes an `awaiting-human` record (via fleet-attention.sh `park`) plus a
# fork-park exit-edge marker. A permission-park (owned by the PermissionRequest
# hook) and every non-park notification (auth / completion / unknown) are gated
# OUT so no false `awaiting-human` is pushed. The row clears on RESUME (the next
# PostToolUse) and on GENUINE termination (SessionEnd / StopFailure take
# precedence over the park); a plain Stop PRESERVES a live fork-park ((b)-refined,
# NS-4 — a turn-end is not a dead worker, and Stop races the async Notification).
# A real queued decision (a flailing / pending permission awaiting-input row that
# this hook did NOT park) is still preserved.
#
# What is covered:
#   - a fork-park notification (idle_prompt / agent_needs_input /
#     elicitation_dialog) pushes awaiting-input + reason within one event cycle,
#     with NO capture-pane; the classifier resolves it to awaiting-human
#     DIRECTLY, never working / hung, even with a stale heartbeat;
#   - payload gating: permission_prompt, auth_success, agent_completed,
#     elicitation_complete, an unknown type, and an absent type all push NOTHING
#     (no false awaiting-human);
#   - a hostile notification_type (shell metacharacters / a spoofed value) is
#     refused by the strict allow-list — no push, no execution;
#   - the identity gate holds (a non-worker session is a silent no-op);
#   - resume exit edge: a PostToolUse after a fork-park clears the row to working;
#   - genuine-termination exit edge: SessionEnd -> ended, StopFailure -> hung
#     clear a fork-park row (precedence over the push — the parked worker is gone);
#   - (b)-refined / NS-4: a plain Stop while a fork-park is live PRESERVES the
#     awaiting-human row and its marker (a turn-end is not a dead worker; Stop and
#     the async Notification race), and the resume edge still fires afterwards;
#   - REQ-A1.3 preservation regression: a queued decision this hook did NOT park
#     (a plain decide row, no fork-park marker) is NEVER cleared by
#     Stop / SessionEnd / StopFailure — the escalation-preserve guard still holds;
#   - REQ-E1.2 regression: the five shipped hook transitions (stop -> idle,
#     permission-request -> awaiting-input + marker, post-tool-use after a
#     permission -> working, session-end -> ended, stop-failure -> hung) are
#     behaviorally identical;
#   - no jq, no capture-pane, and no model / network call anywhere in the arm.
#
# Runs standalone under /bin/bash (the bash 3.2 floor).
set -eu
LC_ALL=C
export LC_ALL
unset CDPATH

here=$(cd "$(dirname "$0")" && pwd)
FL="$here/../scripts/fleet-liveness.sh"
FA="$here/../scripts/fleet-attention.sh"
tab=$(printf '\t')

fail() {
  echo "FAIL: $1" >&2
  exit 1
}
ok() { echo "ok: $1"; }

[ -x "$FL" ] || fail "scripts/fleet-liveness.sh missing or not executable"
[ -x "$FA" ] || fail "scripts/fleet-attention.sh missing or not executable"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

core_cfg="$tmp/core-defaults.yml"
adopter_root="$tmp/adopter"
repo="$tmp/repo"
mkdir -p "$adopter_root" "$repo/.claude"
cat >"$core_cfg" <<'EOF'
fleet_daemon_pause: false
fleet_flailing_threshold: 3
fleet_hung_heartbeat_seconds: 900
fleet_crash_backoff_base_seconds: 30
fleet_crash_disable_threshold: 3
stale_lock_threshold: 15m
EOF

# fire_note <home> <handle> <scope> <payload-json> — invoke the Notification
# hook as a worker session would: identity from the dispatch env, the payload on
# stdin (this arm READS it, unlike the other hooks that drain it).
fire_note() {
  fn_home=$1 fn_handle=$2 fn_scope=$3 fn_payload=$4
  printf '%s' "$fn_payload" \
    | env -u CLAUDE_PLUGIN_DATA -u CLAUDE_PLUGIN_ROOT -u CLAUDE_DIR -u HOME -u PLANWRIGHT_ROOT \
      PLANWRIGHT_WORKER_HANDLE="$fn_handle" PLANWRIGHT_WORKER_SCOPE="$fn_scope" \
      PLANWRIGHT_FLEET_STATE_DIR="$fn_home" PLANWRIGHT_CONFIG_DEFAULTS="$core_cfg" \
      PLANWRIGHT_ADOPTER_OVERLAY="$adopter_root" PLANWRIGHT_REPO_ROOT="$repo" \
      PLANWRIGHT_LOCAL_CONFIG="" \
      /bin/sh "$FL" hook notification
}

# fire <home> <handle> <scope> <event> — a non-notification hook (drained stdin).
fire() {
  f_home=$1 f_handle=$2 f_scope=$3 f_event=$4
  printf '{"session_id":"s1","hook_event_name":"x"}\n' \
    | env -u CLAUDE_PLUGIN_DATA -u CLAUDE_PLUGIN_ROOT -u CLAUDE_DIR -u HOME -u PLANWRIGHT_ROOT \
      PLANWRIGHT_WORKER_HANDLE="$f_handle" PLANWRIGHT_WORKER_SCOPE="$f_scope" \
      PLANWRIGHT_FLEET_STATE_DIR="$f_home" PLANWRIGHT_CONFIG_DEFAULTS="$core_cfg" \
      PLANWRIGHT_ADOPTER_OVERLAY="$adopter_root" PLANWRIGHT_REPO_ROOT="$repo" \
      PLANWRIGHT_LOCAL_CONFIG="" \
      /bin/sh "$FL" hook "$f_event"
}

classify() {
  c_home=$1
  shift
  env -u CLAUDE_PLUGIN_DATA -u CLAUDE_PLUGIN_ROOT -u CLAUDE_DIR -u HOME \
    -u PLANWRIGHT_ROOT -u PLANWRIGHT_WORKER_HANDLE -u PLANWRIGHT_WORKER_SCOPE \
    PLANWRIGHT_FLEET_STATE_DIR="$c_home" PLANWRIGHT_CONFIG_DEFAULTS="$core_cfg" \
    PLANWRIGHT_ADOPTER_OVERLAY="$adopter_root" PLANWRIGHT_REPO_ROOT="$repo" \
    PLANWRIGHT_LOCAL_CONFIG="" \
    /bin/sh "$FL" classify "$@" </dev/null
}

attn() {
  a_home=$1
  shift
  env -u CLAUDE_PLUGIN_DATA -u CLAUDE_PLUGIN_ROOT -u CLAUDE_DIR -u HOME \
    PLANWRIGHT_FLEET_STATE_DIR="$a_home" PLANWRIGHT_CONFIG_DEFAULTS="$core_cfg" \
    PLANWRIGHT_ADOPTER_OVERLAY="$adopter_root" PLANWRIGHT_REPO_ROOT="$repo" \
    PLANWRIGHT_LOCAL_CONFIG="" \
    /bin/sh "$FA" "$@"
}

state_of() {
  s_home=$1 s_worker=$2
  [ -f "$s_home/attention/state" ] || return 0
  awk -F "$tab" -v w="$s_worker" '($1 "") == (w "") { print $3 }' "$s_home/attention/state"
}
reason_of() {
  r_home=$1 r_worker=$2
  [ -f "$r_home/attention/state" ] || return 0
  awk -F "$tab" -v w="$r_worker" '($1 "") == (w "") { print $9 }' "$r_home/attention/state"
}

# ---------------------------------------------------------------------------
# 1. A fork-park notification pushes awaiting-human + reason; classifier
#    resolves awaiting-human directly; no capture-pane on the path.
# ---------------------------------------------------------------------------
h1="$tmp/h1"
rc=0
fire_note "$h1" w1 spec-a '{"session_id":"s1","hook_event_name":"Notification","notification_type":"idle_prompt","message":"Claude is waiting for your input"}' >/dev/null 2>&1 || rc=$?
[ "$rc" = 0 ] || fail "notification hook exited $rc, expected 0 (a hook must never block the session)"
[ "$(state_of "$h1" w1)" = "awaiting-input" ] || fail "idle_prompt did not push awaiting-input: '$(state_of "$h1" w1)'"
[ "$(reason_of "$h1" w1)" = "notification:idle_prompt" ] || fail "reason not recorded: '$(reason_of "$h1" w1)'"
# classify: awaiting-human directly, even with a stale heartbeat + a huge now.
cls=$(classify "$h1" w1 spec-a --now 9999999999 --heartbeat 1) || fail "classify exited non-zero"
[ "$cls" = "awaiting-human" ] || fail "classifier: got '$cls', expected awaiting-human (never working/hung) for a fork-park"
ok "idle_prompt pushes awaiting-human with a reason; classifier resolves it directly (never working/hung)"

# ---------------------------------------------------------------------------
# 2. agent_needs_input and elicitation_dialog also push (input-wait types).
# ---------------------------------------------------------------------------
for t in agent_needs_input elicitation_dialog; do
  hh="$tmp/h2-$t"
  fire_note "$hh" w1 spec-a "{\"notification_type\":\"$t\"}" >/dev/null 2>&1 || fail "$t hook failed"
  [ "$(state_of "$hh" w1)" = "awaiting-input" ] || fail "$t did not push awaiting-input"
  [ "$(reason_of "$hh" w1)" = "notification:$t" ] || fail "$t reason wrong: '$(reason_of "$hh" w1)'"
done
ok "agent_needs_input and elicitation_dialog also push a fork-park"

# ---------------------------------------------------------------------------
# 3. Gating: permission_prompt / informational / unknown / absent push NOTHING.
# ---------------------------------------------------------------------------
for p in \
  '{"notification_type":"permission_prompt","message":"Claude wants to run: rm"}' \
  '{"notification_type":"auth_success"}' \
  '{"notification_type":"agent_completed"}' \
  '{"notification_type":"elicitation_complete"}' \
  '{"notification_type":"elicitation_response"}' \
  '{"notification_type":"totally_unknown_type"}' \
  '{"session_id":"s1","message":"no type field at all"}' \
  '{}'; do
  hg="$tmp/h3-$(printf '%s' "$p" | cksum | cut -d' ' -f1)"
  rc=0
  fire_note "$hg" w1 spec-a "$p" >/dev/null 2>&1 || rc=$?
  [ "$rc" = 0 ] || fail "gated notification exited $rc (must exit 0): payload=$p"
  [ -z "$(state_of "$hg" w1)" ] || fail "a gated notification pushed a row (payload=$p): '$(state_of "$hg" w1)'"
done
ok "permission_prompt / informational / unknown / absent types push no false awaiting-human"

# ---------------------------------------------------------------------------
# 4. A hostile notification_type is refused by the strict allow-list: no push.
# ---------------------------------------------------------------------------
h4="$tmp/h4"
# The injection target lives under the test's own mktemp dir (never a shared
# /tmp path), so a stray file or a parallel run can never cross-contaminate.
pwn="$tmp/pwn_fh2"
rc=0
fire_note "$h4" w1 spec-a "{\"notification_type\":\"idle_prompt; touch $pwn\"}" >/dev/null 2>&1 || rc=$?
[ "$rc" = 0 ] || fail "hostile payload exited $rc"
[ -z "$(state_of "$h4" w1)" ] || fail "a spoofed notification_type pushed a row"
[ ! -e "$pwn" ] || {
  rm -f "$pwn"
  fail "a payload value was executed (command injection)"
}
ok "a spoofed / metacharacter notification_type is refused by the allow-list (no push, no execution)"

# ---------------------------------------------------------------------------
# 5. Identity gate: a non-worker session (no env) is a silent no-op.
# ---------------------------------------------------------------------------
h5="$tmp/h5"
rc=0
printf '%s' '{"notification_type":"idle_prompt"}' \
  | env -u PLANWRIGHT_WORKER_HANDLE -u PLANWRIGHT_WORKER_SCOPE \
    PLANWRIGHT_FLEET_STATE_DIR="$h5" PLANWRIGHT_CONFIG_DEFAULTS="$core_cfg" \
    /bin/sh "$FL" hook notification >/dev/null 2>&1 || rc=$?
[ "$rc" = 0 ] || fail "identity gate: non-worker notification exited $rc, expected 0"
[ ! -f "$h5/attention/state" ] || fail "a non-worker session wrote to the store"
ok "the identity gate holds for notification (a non-worker session is a silent no-op)"

# ---------------------------------------------------------------------------
# 6. Resume exit edge: a PostToolUse after a fork-park clears the row -> working.
# ---------------------------------------------------------------------------
h6="$tmp/h6"
fire_note "$h6" w1 spec-a '{"notification_type":"idle_prompt"}' >/dev/null 2>&1 || fail "park failed"
[ "$(state_of "$h6" w1)" = "awaiting-input" ] || fail "precondition: not parked"
fire "$h6" w1 spec-a post-tool-use >/dev/null 2>&1 || fail "post-tool-use failed"
[ "$(state_of "$h6" w1)" = "working" ] || fail "resume: post-tool-use did not clear the fork-park to working: '$(state_of "$h6" w1)'"
ok "resume exit edge: PostToolUse after a fork-park clears the row to working"

# ---------------------------------------------------------------------------
# 7. Genuine-termination exit edges: SessionEnd -> ended, StopFailure -> hung
#    each clear a live fork-park (precedence over the push — the parked worker
#    really is gone). A plain Stop is NOT a termination and is covered by 7d.
# ---------------------------------------------------------------------------
for pair in "session-end:ended" "stop-failure:hung"; do
  ev=${pair%%:*}
  want=${pair##*:}
  ht="$tmp/h7-$ev"
  fire_note "$ht" w1 spec-a '{"notification_type":"idle_prompt"}' >/dev/null 2>&1 || fail "park failed ($ev)"
  [ "$(state_of "$ht" w1)" = "awaiting-input" ] || fail "precondition ($ev): not parked"
  fire "$ht" w1 spec-a "$ev" >/dev/null 2>&1 || fail "$ev hook failed"
  [ "$(state_of "$ht" w1)" = "$want" ] || fail "genuine-termination edge $ev: got '$(state_of "$ht" w1)', expected $want (precedence over the park)"
done
ok "genuine-termination edges (session-end/stop-failure) clear a fork-park with precedence over the push"

# ---------------------------------------------------------------------------
# 7d. (b)-refined (NS-4): a plain Stop while a fork-park is LIVE does NOT clear
#     it. Claude Code fires Stop on every turn-end (including a park-and-wait),
#     and Notification(idle_prompt) races Stop with no guaranteed order, so a
#     Stop on a live fork-park means the worker is ALIVE and waiting for the
#     human — the awaiting-human row AND its await_marker must survive, and the
#     post-tool-use resume exit-edge must still fire afterwards.
# ---------------------------------------------------------------------------
h7d="$tmp/h7d"
fire_note "$h7d" w1 spec-a '{"notification_type":"idle_prompt"}' >/dev/null 2>&1 || fail "park failed"
[ "$(state_of "$h7d" w1)" = "awaiting-input" ] || fail "precondition: not parked"
[ -e "$h7d/liveness/awaiting/w1" ] || fail "precondition: no fork-park marker written"
fire "$h7d" w1 spec-a stop >/dev/null 2>&1 || fail "stop hook failed"
[ "$(state_of "$h7d" w1)" = "awaiting-input" ] \
  || fail "a plain stop cleared a live fork-park (must PRESERVE it, NS-4): '$(state_of "$h7d" w1)'"
[ "$(reason_of "$h7d" w1)" = "notification:idle_prompt" ] \
  || fail "stop lost the fork-park reason: '$(reason_of "$h7d" w1)'"
[ -e "$h7d/liveness/awaiting/w1" ] \
  || fail "stop dropped the fork-park await_marker (the resume exit-edge would no longer fire)"
# the resume edge still works after a preserving stop.
fire "$h7d" w1 spec-a post-tool-use >/dev/null 2>&1 || fail "post-tool-use failed"
[ "$(state_of "$h7d" w1)" = "working" ] \
  || fail "resume after a stop-preserved fork-park did not clear to working: '$(state_of "$h7d" w1)'"
ok "a plain stop PRESERVES a live fork-park and keeps its marker; the resume edge still fires (NS-4, (b)-refined)"

# ---------------------------------------------------------------------------
# 7e. (b)-refined completeness: a LEAKED pending-permission marker whose token
#     collides (same wall-clock second) with a live fork-park's heartbeat must
#     NOT let a plain Stop clobber the fork-park. marker_live_permission is
#     checked BEFORE marker_live_awaiting, so without its field-9-EMPTY guard the
#     fork-park (non-empty field 9) would be misread as a permission decision and
#     cleared to idle — silently defeating the stop-preserve guarantee.
# ---------------------------------------------------------------------------
h7e="$tmp/h7e"
fire_note "$h7e" w1 spec-a '{"notification_type":"idle_prompt"}' >/dev/null 2>&1 || fail "park failed"
[ "$(state_of "$h7e" w1)" = "awaiting-input" ] || fail "precondition: not parked"
hb=$(awk -F "$tab" -v w=w1 '($1 "") == (w "") { print $4 }' "$h7e/attention/state")
[ -n "$hb" ] || fail "could not read the fork-park heartbeat"
# a leaked pending-permission marker carrying that same heartbeat token.
mkdir -p "$h7e/liveness/pending"
printf '%s' "$hb" >"$h7e/liveness/pending/w1"
fire "$h7e" w1 spec-a stop >/dev/null 2>&1 || fail "stop hook failed"
[ "$(state_of "$h7e" w1)" = "awaiting-input" ] \
  || fail "a colliding leaked permission marker let a plain stop clobber the fork-park: '$(state_of "$h7e" w1)'"
[ -e "$h7e/liveness/awaiting/w1" ] \
  || fail "the fork-park await_marker was dropped under the permission-collision path"
ok "a same-second leaked-permission-marker collision cannot let a plain stop clobber a fork-park (NS-4 completeness)"

# ---------------------------------------------------------------------------
# 8. REQ-A1.3 preservation regression: a queued decision this hook did NOT park
#    (a plain decide row, no fork-park marker) is NEVER cleared by a downgrade.
# ---------------------------------------------------------------------------
for ev in stop session-end stop-failure; do
  hp="$tmp/h8-$ev"
  attn "$hp" decide w1 spec-a "Real human decision?" "hold" "A|B" high >/dev/null 2>&1 || fail "decide setup failed"
  fire "$hp" w1 spec-a "$ev" >/dev/null 2>&1 || fail "$ev hook failed"
  [ "$(state_of "$hp" w1)" = "awaiting-input" ] \
    || fail "$ev auto-resolved a queued decision with no fork-park marker (REQ-A1.3 violation): '$(state_of "$hp" w1)'"
done
ok "a real queued decision (no fork-park marker) is preserved by every downgrade (REQ-A1.3 holds)"

# ---------------------------------------------------------------------------
# 8b. REQ-A1.3 WRITE-SIDE ownership gate: a Notification that no-op's over a
#     PRE-EXISTING queued decision (park --unless-awaiting) must NOT stamp the
#     fork-park exit-edge marker — so a later resume (PostToolUse) can never
#     mistake that decision for a fork-park and auto-resolve it. This exercises
#     the write-side ownership check (state == awaiting-input AND field-9 reason
#     == our reason) that gates the marker stamp, distinct from #9b's read-side
#     marker_live_awaiting check on a hand-built colliding row.
# ---------------------------------------------------------------------------
h8b="$tmp/h8b"
attn "$h8b" decide w1 spec-a "Real human decision?" "hold" "A|B" high >/dev/null 2>&1 || fail "decide setup failed"
[ "$(state_of "$h8b" w1)" = "awaiting-input" ] || fail "precondition: decide row not present"
fire_note "$h8b" w1 spec-a '{"notification_type":"idle_prompt"}' >/dev/null 2>&1 || fail "notification hook failed"
# The park no-op'd over the decision, so no fork-park marker may exist.
[ ! -e "$h8b/liveness/awaiting/w1" ] \
  || fail "notification stamped a fork-park marker over a pre-existing decision (would hijack its exit edge)"
# The decision is intact: still a decide row (empty field-9 reason), not clobbered.
[ "$(state_of "$h8b" w1)" = "awaiting-input" ] || fail "notification clobbered the decision state"
[ -z "$(reason_of "$h8b" w1)" ] || fail "notification overwrote the decision with a fork-park reason: '$(reason_of "$h8b" w1)'"
# A resume must NOT clear a decision the notification never parked.
fire "$h8b" w1 spec-a post-tool-use >/dev/null 2>&1 || fail "post-tool-use failed"
[ "$(state_of "$h8b" w1)" = "awaiting-input" ] \
  || fail "resume cleared a decision the notification did not park (REQ-A1.3 write-side): '$(state_of "$h8b" w1)'"
ok "a Notification that no-op's over a queued decision never claims its exit edge (REQ-A1.3 write-side)"

# ---------------------------------------------------------------------------
# 9. REQ-E1.2 regression: the five shipped hook transitions are unchanged.
# ---------------------------------------------------------------------------
h9="$tmp/h9"
fire "$h9" w1 spec-a stop >/dev/null 2>&1 || fail "stop failed"
[ "$(state_of "$h9" w1)" = "idle" ] || fail "shipped stop -> idle broke: '$(state_of "$h9" w1)'"
fire "$h9" w2 spec-a permission-request >/dev/null 2>&1 || fail "permission-request failed"
[ "$(state_of "$h9" w2)" = "awaiting-input" ] || fail "shipped permission-request -> awaiting-input broke"
fire "$h9" w2 spec-a post-tool-use >/dev/null 2>&1 || fail "post-tool-use failed"
[ "$(state_of "$h9" w2)" = "working" ] || fail "shipped post-tool-use (after permission) -> working broke: '$(state_of "$h9" w2)'"
fire "$h9" w3 spec-a session-end >/dev/null 2>&1 || fail "session-end failed"
[ "$(state_of "$h9" w3)" = "ended" ] || fail "shipped session-end -> ended broke"
fire "$h9" w4 spec-a stop-failure >/dev/null 2>&1 || fail "stop-failure failed"
[ "$(state_of "$h9" w4)" = "hung" ] || fail "shipped stop-failure -> hung broke"
ok "REQ-E1.2 regression: the five shipped hook transitions are behaviorally identical"

# ---------------------------------------------------------------------------
# 9b. Same-second heartbeat collision (REQ-A1.3): a decide (empty field 9) that
#     replaced a fork-park row while carrying the SAME heartbeat as the fork-park
#     marker is NOT cleared by a terminal exit — the field-9 ownership
#     discriminator in marker_live_awaiting keeps the exit edge from
#     auto-resolving a queued human decision, which the heartbeat token alone
#     (second-granular) cannot.
# ---------------------------------------------------------------------------
h9b="$tmp/h9b"
fire_note "$h9b" w1 spec-a '{"notification_type":"idle_prompt"}' >/dev/null 2>&1 || fail "park failed"
tok=$(cat "$h9b/liveness/awaiting/w1" 2>/dev/null) || tok=""
[ -n "$tok" ] || fail "no fork-park marker token was written"
# A flailing / permission decide that replaced the row in the SAME wall-clock
# second (same heartbeat as the marker token) with an EMPTY reason (field 9).
printf 'w1\tspec-a\tawaiting-input\t%s\thigh\tReal human decision?\thold\tA|B\n' "$tok" \
  >"$h9b/attention/state"
fire "$h9b" w1 spec-a stop >/dev/null 2>&1 || fail "stop hook failed"
[ "$(state_of "$h9b" w1)" = "awaiting-input" ] \
  || fail "same-second collision: the exit edge auto-resolved a queued decision (REQ-A1.3): '$(state_of "$h9b" w1)'"
ok "a same-second heartbeat collision cannot make the fork-park exit edge clear a queued decision (REQ-A1.3)"

# ---------------------------------------------------------------------------
# 10. No jq, no capture-pane, no model / network call in EXECUTABLE code
#     (comment lines that merely NAME jq / Claude Code as documentation are
#     fine and expected — only an actual invocation is a violation).
# ---------------------------------------------------------------------------
code_only() { grep -vE '^[[:space:]]*#' "$1"; }
code_only "$FL" | grep -qE '(^|[^A-Za-z_.])jq([^A-Za-z_]|$)' \
  && fail "fleet-liveness.sh invokes jq (REQ-K1.5)"
code_only "$FL" | grep -qE 'capture-pane' \
  && fail "fleet-liveness.sh references capture-pane"
# One sanctioned carve-out (execution-backends D-11 / REQ-F1.1): the
# agents-json idle oracle's binary default, `ORACLE_BIN` from
# PLANWRIGHT_ORACLE_CLAUDE, names the CLI in executable code. That probe is a
# local session-registry listing — no model inference, no network — and the
# hook/notification decision path never invokes it, so REQ-E1.3's intent
# stands. The carve-out is the single ORACLE_BIN assignment line; any OTHER
# executable model/network reference (including a new bare CLI invocation)
# still fails here.
oracle_carveout='^ORACLE_BIN="\$\{PLANWRIGHT_ORACLE_CLAUDE:-claude\}"$'
code_only "$FL" | grep -vE "$oracle_carveout" \
  | grep -qiE '(^|[^A-Za-z_.])(claude|anthropic|curl|wget)([^A-Za-z_]|$)' \
  && fail "fleet-liveness.sh references a model / network call (REQ-E1.3)"
# The carve-out must stay anchored to the real line: if the assignment moves
# or is reworded, this positive control fails instead of silently widening.
code_only "$FL" | grep -qE "$oracle_carveout" \
  || fail "REQ-E1.3 carve-out is stale: the ORACLE_BIN assignment line no longer matches"
ok "no jq, no capture-pane, no model / network call in fleet-liveness.sh executable code (REQ-E1.3, REQ-K1.5)"

echo "PASS: fleet-liveness notification"
