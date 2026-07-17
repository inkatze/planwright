#!/bin/bash
# Tests for scripts/fleet-liveness.sh — push-based worker liveness, the
# five-state classifier, and the crash-loop backoff (fleet-autonomy Task 2:
# D-1, D-2, D-3; REQ-A1.1, REQ-A1.2, REQ-A1.3, REQ-A1.4).
#
# What is covered:
#   - REQ-A1.1 push: each hookable transition (`stop`, `permission-request`,
#     `post-tool-use` after a pending permission, `session-end`,
#     `stop-failure`) updates fleet-attention.sh's state store synchronously
#     within the handler call itself ("one event cycle"), never waiting on a
#     tower poll; the env identity gate makes non-worker sessions a clean
#     no-op; hostile env values are refused with no write; the handler never
#     exits non-zero for a valid event (a Stop-hook exit 2 would block the
#     worker's own stop);
#   - the escalation-preserve guard: a downgrade push (stop / session-end /
#     stop-failure) never overwrites an awaiting-input row that has no
#     pending-permission marker (REQ-A1.3's never-auto-resolved floor), while
#     the deny path (permission-request then stop, no tool use between)
#     clears cleanly (kickoff risk row 28);
#   - REQ-A1.1 fallback: `push-capable` names hook-push for session-launching
#     backends (tmux, print) and falls back to the existing capture-pane
#     observation for in-process backends (subagent, in-session) rather than
#     failing (kickoff risk row 16);
#   - REQ-A1.2: synthetic heartbeat/progress sequences resolve exactly one of
#     working / idle / hung / awaiting-human / flailing, including the
#     hung-vs-flailing boundary (heartbeat stopped vs heartbeat fresh with no
#     forward progress) and the freshly-dispatched startup default (risk 33);
#   - the positive-evidence gate (REQ-A1.2/REQ-A1.7, risk 37): a stale
#     heartbeat with an evidence handle consults fleet-death-evidence.sh (the
#     stub records the call), an `unknown` verdict REFUSES the hung
#     classification (lost observability is never death), and without a
#     handle the documented elapsed-time boundary applies (risk 29);
#   - REQ-A1.3: a flailing classification queues exactly ONE decision entry,
#     stays at one across repeated classification, and issues no restart or
#     nudge (the audit trail shows the escalation and nothing act-like);
#   - risk 31 audit scoping: routine classification writes NO audit rows;
#     the flailing escalation and backoff/disable actions do;
#   - REQ-A1.4: repeated crash records escalate the relaunch delay on the
#     configured exponential schedule (capped), disable the worker at the
#     configured consecutive-failure threshold with a decision-queue entry,
#     and `crash-check` refuses relaunch while backing off, when disabled,
#     and when the operator kill-switch (fleet-daemon-gate.sh) is set;
#   - knobs resolve through the shared resolver (an overlay value changes the
#     flailing threshold), usage/hostile input is refused (exit 2).
#
# Runs standalone under /bin/bash (the bash 3.2 floor):
#   ./tests/test-fleet-liveness.sh
set -eu
LC_ALL=C
export LC_ALL
unset CDPATH

here=$(cd "$(dirname "$0")" && pwd)
FL="$here/../scripts/fleet-liveness.sh"
FA="$here/../scripts/fleet-attention.sh"
FAU="$here/../scripts/fleet-audit.sh"
tab=$(printf '\t')

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

[ -x "$FL" ] || fail "scripts/fleet-liveness.sh missing or not executable"
[ -x "$FA" ] || fail "scripts/fleet-attention.sh missing or not executable"
[ -x "$FAU" ] || fail "scripts/fleet-audit.sh missing or not executable"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# Config layers: a pinned core-defaults file and empty adopter/repo layers, so
# knob resolution is deterministic (the test host's real overlays never leak
# in) — the fleet-daemon-gate test discipline.
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

# run <fleet-home> <args...> — invoke fleet-liveness.sh with the pinned layers
# and no ambient dotfiles/plugin env.
run() {
  r_home=$1
  shift
  env -u CLAUDE_PLUGIN_DATA -u CLAUDE_PLUGIN_ROOT -u CLAUDE_DIR -u HOME \
    -u PLANWRIGHT_ROOT -u PLANWRIGHT_WORKER_HANDLE -u PLANWRIGHT_WORKER_SCOPE \
    PLANWRIGHT_FLEET_STATE_DIR="$r_home" \
    PLANWRIGHT_CONFIG_DEFAULTS="$core_cfg" \
    PLANWRIGHT_ADOPTER_OVERLAY="$adopter_root" \
    PLANWRIGHT_REPO_ROOT="$repo" \
    PLANWRIGHT_LOCAL_CONFIG="" \
    /bin/bash "$FL" "$@" </dev/null
}

# run_hook <fleet-home> <handle> <scope> <event> — invoke the hook handler as
# a worker session's registered hook would: identity from the dispatch-time
# env contract, the (ignored) JSON payload on stdin.
run_hook() {
  rh_home=$1
  rh_handle=$2
  rh_scope=$3
  rh_event=$4
  printf '{"session_id":"s1","hook_event_name":"x"}\n' \
    | env -u CLAUDE_PLUGIN_DATA -u CLAUDE_PLUGIN_ROOT -u CLAUDE_DIR -u HOME \
      -u PLANWRIGHT_ROOT \
      PLANWRIGHT_WORKER_HANDLE="$rh_handle" \
      PLANWRIGHT_WORKER_SCOPE="$rh_scope" \
      PLANWRIGHT_FLEET_STATE_DIR="$rh_home" \
      PLANWRIGHT_CONFIG_DEFAULTS="$core_cfg" \
      PLANWRIGHT_ADOPTER_OVERLAY="$adopter_root" \
      PLANWRIGHT_REPO_ROOT="$repo" \
      PLANWRIGHT_LOCAL_CONFIG="" \
      /bin/bash "$FL" hook "$rh_event"
}

# attn <fleet-home> <args...> — drive fleet-attention.sh directly (fixture
# setup and store asserts share its store).
attn() {
  a_home=$1
  shift
  env -u CLAUDE_PLUGIN_DATA -u CLAUDE_PLUGIN_ROOT -u CLAUDE_DIR -u HOME \
    PLANWRIGHT_FLEET_STATE_DIR="$a_home" \
    PLANWRIGHT_CONFIG_DEFAULTS="$core_cfg" \
    PLANWRIGHT_ADOPTER_OVERLAY="$adopter_root" \
    PLANWRIGHT_REPO_ROOT="$repo" \
    PLANWRIGHT_LOCAL_CONFIG="" \
    /bin/sh "$FA" "$@"
}

audit_q() {
  aq_home=$1
  shift
  env -u CLAUDE_PLUGIN_DATA -u CLAUDE_PLUGIN_ROOT -u CLAUDE_DIR -u HOME \
    PLANWRIGHT_FLEET_STATE_DIR="$aq_home" \
    PLANWRIGHT_CONFIG_DEFAULTS="$core_cfg" \
    PLANWRIGHT_ADOPTER_OVERLAY="$adopter_root" \
    PLANWRIGHT_REPO_ROOT="$repo" \
    PLANWRIGHT_LOCAL_CONFIG="" \
    /bin/sh "$FAU" query "$@"
}

# store_state <fleet-home> <worker> — print the worker's current store state
# (field 3 of the 8-field attention record), or nothing when no row exists.
store_state() {
  ss_home=$1
  ss_worker=$2
  [ -f "$ss_home/attention/state" ] || return 0
  awk -F "$tab" -v w="$ss_worker" '($1 "") == (w "") { print $3 }' \
    "$ss_home/attention/state"
}

# ---------------------------------------------------------------------------
# 1. REQ-A1.1 — the identity gate: without the dispatch-time worker env the
#    handler is a silent no-op (exit 0, nothing written). The plugin registers
#    these hooks for every session; only dispatched workers may write.
# ---------------------------------------------------------------------------
home1="$tmp/h1"
rc=0
printf '{}' | env -u PLANWRIGHT_WORKER_HANDLE -u PLANWRIGHT_WORKER_SCOPE \
  PLANWRIGHT_FLEET_STATE_DIR="$home1" \
  PLANWRIGHT_CONFIG_DEFAULTS="$core_cfg" \
  /bin/bash "$FL" hook stop >/dev/null 2>&1 || rc=$?
[ "$rc" = 0 ] || fail "env gate: exit $rc, expected 0 (a non-worker session must not be disturbed)"
[ ! -e "$home1/attention/state" ] || fail "env gate: a non-worker session wrote the state store"
echo "ok: without the worker env contract the hook handler is a clean no-op"

# ---------------------------------------------------------------------------
# 2. REQ-A1.1 — hostile identity env is refused with NO write, and the handler
#    still exits 0 (a hook exit must never block the worker session).
# ---------------------------------------------------------------------------
rc=0
err=$(printf '{}' | env \
  PLANWRIGHT_WORKER_HANDLE='bad worker;rm' PLANWRIGHT_WORKER_SCOPE='spec:1' \
  PLANWRIGHT_FLEET_STATE_DIR="$home1" \
  PLANWRIGHT_CONFIG_DEFAULTS="$core_cfg" \
  /bin/bash "$FL" hook stop 2>&1 >/dev/null) || rc=$?
[ "$rc" = 0 ] || fail "hostile env: exit $rc, expected 0"
[ -n "$err" ] || fail "hostile env: refused silently (expected a stderr warning)"
[ ! -e "$home1/attention/state" ] || fail "hostile env: a refused identity still wrote the store"
echo "ok: hostile worker-identity env is refused (no write) without a blocking exit"

# ---------------------------------------------------------------------------
# 3. REQ-A1.1 — each hookable transition is pushed synchronously: the store
#    reflects the new state the moment the handler call returns (one event
#    cycle, no tower poll in between).
# ---------------------------------------------------------------------------
home3="$tmp/h3"
w="worker=t2"
s="fleet-autonomy:2"

run_hook "$home3" "$w" "$s" stop >/dev/null 2>&1 || fail "hook stop: non-zero exit"
[ "$(store_state "$home3" "$w")" = idle ] || fail "hook stop: state '$(store_state "$home3" "$w")', expected idle"

run_hook "$home3" "$w" "$s" stop-failure >/dev/null 2>&1 || fail "hook stop-failure: non-zero exit"
[ "$(store_state "$home3" "$w")" = hung ] || fail "hook stop-failure: state '$(store_state "$home3" "$w")', expected hung (risk 27 mapping)"

run_hook "$home3" "$w" "$s" session-end >/dev/null 2>&1 || fail "hook session-end: non-zero exit"
[ "$(store_state "$home3" "$w")" = ended ] || fail "hook session-end: state '$(store_state "$home3" "$w")', expected ended"
echo "ok: stop / stop-failure / session-end push idle / hung / ended synchronously"

# ---------------------------------------------------------------------------
# 4. REQ-A1.1 — the permission flow: permission-request pushes awaiting-input
#    with a queue entry and a pending marker; the next post-tool-use (the
#    documented awaiting-human -> working inference) restores working and
#    clears both.
# ---------------------------------------------------------------------------
run_hook "$home3" "$w" "$s" permission-request >/dev/null 2>&1 || fail "hook permission-request: non-zero exit"
[ "$(store_state "$home3" "$w")" = awaiting-input ] || fail "permission-request: state '$(store_state "$home3" "$w")', expected awaiting-input"
[ -e "$home3/liveness/pending/$w" ] || fail "permission-request: no pending-permission marker"
qc=$(attn "$home3" queue --count) || fail "queue --count failed"
[ "$qc" = 1 ] || fail "permission-request: queue count $qc, expected 1"

run_hook "$home3" "$w" "$s" post-tool-use >/dev/null 2>&1 || fail "hook post-tool-use: non-zero exit"
[ "$(store_state "$home3" "$w")" = working ] || fail "post-tool-use after pending: state '$(store_state "$home3" "$w")', expected working"
[ ! -e "$home3/liveness/pending/$w" ] || fail "post-tool-use: pending marker not cleared"
qc=$(attn "$home3" queue --count) || fail "queue --count failed"
[ "$qc" = 0 ] || fail "post-tool-use: queue count $qc, expected 0"
echo "ok: permission-request -> awaiting-input(+queue), next post-tool-use -> working"

# ---------------------------------------------------------------------------
# 5. REQ-A1.1 — post-tool-use with NO pending permission is a fast no-op: no
#    state change (push fires only on the enumerated transitions, not on every
#    tool call).
# ---------------------------------------------------------------------------
run_hook "$home3" "$w" "$s" stop >/dev/null 2>&1 || fail "setup stop failed"
before=$(cat "$home3/attention/state")
run_hook "$home3" "$w" "$s" post-tool-use >/dev/null 2>&1 || fail "bare post-tool-use: non-zero exit"
after=$(cat "$home3/attention/state")
[ "$before" = "$after" ] || fail "bare post-tool-use rewrote the store (must only act after a pending permission)"
echo "ok: post-tool-use without a pending permission changes nothing"

# ---------------------------------------------------------------------------
# 6. Risk 28 — the deny path: permission-request then stop (turn ended, no
#    tool use in between) clears to idle, marker gone, queue drained.
# ---------------------------------------------------------------------------
run_hook "$home3" "$w" "$s" permission-request >/dev/null 2>&1 || fail "deny path: permission-request failed"
run_hook "$home3" "$w" "$s" stop >/dev/null 2>&1 || fail "deny path: stop failed"
[ "$(store_state "$home3" "$w")" = idle ] || fail "deny path: state '$(store_state "$home3" "$w")', expected idle"
[ ! -e "$home3/liveness/pending/$w" ] || fail "deny path: pending marker survived the stop"
qc=$(attn "$home3" queue --count) || fail "queue --count failed"
[ "$qc" = 0 ] || fail "deny path: queue count $qc, expected 0"
echo "ok: a denied permission whose turn ends clears on the stop push (risk 28)"

# ---------------------------------------------------------------------------
# 7. REQ-A1.3 floor — the escalation-preserve guard: a queued escalation
#    (awaiting-input with NO pending-permission marker) is never overwritten
#    by a downgrade push (stop / session-end / stop-failure).
# ---------------------------------------------------------------------------
home7="$tmp/h7"
attn "$home7" decide "$w" "$s" "no forward progress - task may be stuck" \
  "park for review" "park|relaunch-fresh|redirect" high >/dev/null \
  || fail "escalation setup: decide failed"
for ev in stop session-end stop-failure; do
  run_hook "$home7" "$w" "$s" "$ev" >/dev/null 2>&1 || fail "guard: hook $ev non-zero"
  st=$(store_state "$home7" "$w")
  [ "$st" = awaiting-input ] || fail "guard: $ev overwrote the escalation (state '$st')"
done
qc=$(attn "$home7" queue --count) || fail "queue --count failed"
[ "$qc" = 1 ] || fail "guard: queue count $qc, expected the escalation to survive as 1"
echo "ok: downgrade pushes never auto-resolve a queued escalation"

# ---------------------------------------------------------------------------
# 8. REQ-A1.1 fallback (risk 16) — push-capable: session-launching backends
#    push; in-process backends fall back to the existing capture-pane
#    observation (named on stdout) rather than failing.
# ---------------------------------------------------------------------------
for b in tmux print; do
  rc=0
  out=$(run "$tmp/h8" push-capable "$b") || rc=$?
  [ "$rc" = 0 ] || fail "push-capable $b: exit $rc, expected 0"
  [ "$out" = push ] || fail "push-capable $b: '$out', expected 'push'"
done
for b in subagent in-session; do
  rc=0
  out=$(run "$tmp/h8" push-capable "$b") || rc=$?
  [ "$rc" = 1 ] || fail "push-capable $b: exit $rc, expected 1 (fallback, not failure)"
  [ "$out" = observe ] || fail "push-capable $b: '$out', expected 'observe' (the capture-pane fallback)"
done
rc=0
run "$tmp/h8" push-capable no-such-backend >/dev/null 2>&1 || rc=$?
[ "$rc" = 2 ] || fail "push-capable unknown backend: exit $rc, expected 2"
echo "ok: push-capable names hook-push for tmux/print and the observe fallback for subagent/in-session"

# ---------------------------------------------------------------------------
# 9. REQ-A1.2 — the five-state classifier over synthetic sequences: startup
#    default (risk 33), working, idle family, awaiting-human.
# ---------------------------------------------------------------------------
home9="$tmp/h9"
out=$(run "$home9" classify "$w" "$s" --now 10000) || fail "classify (no row): non-zero exit"
[ "$out" = working ] || fail "startup default: '$out', expected working (risk 33)"

attn "$home9" heartbeat "$w" "$s" working >/dev/null || fail "setup heartbeat"
out=$(run "$home9" classify "$w" "$s" --now 10000 --heartbeat 9950 --progress sha-a1) \
  || fail "classify working: non-zero exit"
[ "$out" = working ] || fail "fresh heartbeat + first observation: '$out', expected working"

for st in idle pr-ready merged "done" ended; do
  home_i="$tmp/h9-$st"
  attn "$home_i" heartbeat "$w" "$s" "$st" >/dev/null 2>&1 || {
    # idle/hung/ended acceptance is itself under test in test-fleet-attention;
    # here a refusal means the vocabulary extension is missing.
    fail "setup: heartbeat state '$st' refused by fleet-attention"
  }
  out=$(run "$home_i" classify "$w" "$s" --now 10000) || fail "classify $st: non-zero exit"
  [ "$out" = idle ] || fail "store state $st classified '$out', expected idle"
done

home9b="$tmp/h9b"
attn "$home9b" decide "$w" "$s" "q" "d" "o1|o2" >/dev/null || fail "setup decide"
out=$(run "$home9b" classify "$w" "$s" --now 10000) || fail "classify awaiting: non-zero exit"
[ "$out" = awaiting-human ] || fail "awaiting-input row classified '$out', expected awaiting-human"
echo "ok: classifier resolves startup-default/working/idle-family/awaiting-human"

# ---------------------------------------------------------------------------
# 10. REQ-A1.2 — the hung-vs-flailing boundary. Heartbeat stopped (stale, no
#     evidence handle: the documented elapsed-time boundary, risk 29) -> hung;
#     heartbeat fresh with the same progress token across the configured
#     threshold of observations -> flailing.
# ---------------------------------------------------------------------------
home10="$tmp/h10"
attn "$home10" heartbeat "$w" "$s" working >/dev/null || fail "setup heartbeat"
out=$(run "$home10" classify "$w" "$s" --now 10000 --heartbeat 9000) \
  || fail "classify stale: non-zero exit"
[ "$out" = hung ] || fail "stale heartbeat (age 1000 >= 900), no handle: '$out', expected hung"

home10b="$tmp/h10b"
attn "$home10b" heartbeat "$w" "$s" working >/dev/null || fail "setup heartbeat"
out=$(run "$home10b" classify "$w" "$s" --now 10000 --heartbeat 9990 --progress sha-x) || fail "flail 1"
[ "$out" = working ] || fail "flail obs 1: '$out', expected working"
out=$(run "$home10b" classify "$w" "$s" --now 10060 --heartbeat 10050 --progress sha-x) || fail "flail 2"
[ "$out" = working ] || fail "flail obs 2: '$out', expected working"
out=$(run "$home10b" classify "$w" "$s" --now 10120 --heartbeat 10110 --progress sha-x) || fail "flail 3"
[ "$out" = flailing ] || fail "flail obs 3 (threshold 3): '$out', expected flailing"
echo "ok: heartbeat stopped -> hung; heartbeat fresh + no progress across threshold -> flailing"

# ---------------------------------------------------------------------------
# 11. REQ-A1.2 — forward progress resets the flailing streak.
# ---------------------------------------------------------------------------
home11="$tmp/h11"
attn "$home11" heartbeat "$w" "$s" working >/dev/null || fail "setup heartbeat"
run "$home11" classify "$w" "$s" --now 10000 --heartbeat 9990 --progress sha-1 >/dev/null || fail "reset 1"
run "$home11" classify "$w" "$s" --now 10060 --heartbeat 10050 --progress sha-1 >/dev/null || fail "reset 2"
out=$(run "$home11" classify "$w" "$s" --now 10120 --heartbeat 10110 --progress sha-2) || fail "reset 3"
[ "$out" = working ] || fail "progress change still classified '$out', expected working"
out=$(run "$home11" classify "$w" "$s" --now 10180 --heartbeat 10170 --progress sha-2) || fail "reset 4"
[ "$out" = working ] || fail "streak 2 of 3 after reset classified '$out', expected working"
echo "ok: a new progress token resets the no-progress streak"

# ---------------------------------------------------------------------------
# 12. REQ-A1.2 / REQ-A1.7 / risk 37 — the positive-evidence gate, proven as a
#     call-through: with a stale heartbeat and an evidence handle the
#     classifier consults the death-evidence predicate (the stub records its
#     argv); verdict unknown -> REFUSES hung (working + warning); verdicts
#     alive (wedged harness) and dead both -> hung.
# ---------------------------------------------------------------------------
stubbin="$tmp/stub-scripts"
mkdir -p "$stubbin"
cp "$here/../scripts/"*.sh "$stubbin/"
cat >"$stubbin/fleet-death-evidence.sh" <<EOF
#!/bin/sh
printf '%s\n' "\$*" >>"$tmp/evidence-calls"
verdict=\$(cat "$tmp/evidence-verdict")
printf '%s\n' "\$verdict"
case \$verdict in
  dead) exit 0 ;;
  alive) exit 1 ;;
  *) exit 3 ;;
esac
EOF
chmod +x "$stubbin/fleet-death-evidence.sh"

stub_run() {
  sr_home=$1
  shift
  env -u CLAUDE_PLUGIN_DATA -u CLAUDE_PLUGIN_ROOT -u CLAUDE_DIR -u HOME \
    PLANWRIGHT_FLEET_STATE_DIR="$sr_home" \
    PLANWRIGHT_CONFIG_DEFAULTS="$core_cfg" \
    PLANWRIGHT_ADOPTER_OVERLAY="$adopter_root" \
    PLANWRIGHT_REPO_ROOT="$repo" \
    PLANWRIGHT_LOCAL_CONFIG="" \
    /bin/bash "$stubbin/fleet-liveness.sh" "$@"
}

home12="$tmp/h12"
attn "$home12" heartbeat "$w" "$s" working >/dev/null || fail "setup heartbeat"

printf 'unknown\n' >"$tmp/evidence-verdict"
: >"$tmp/evidence-calls"
rc=0
out=$(stub_run "$home12" classify "$w" "$s" --now 10000 --heartbeat 9000 \
  --evidence process 12345 2>"$tmp/cls-err") || rc=$?
[ "$rc" = 0 ] || fail "evidence unknown: exit $rc"
[ "$out" = working ] || fail "evidence unknown: '$out', expected working (refuse hung on lost observability)"
grep -q "process 12345" "$tmp/evidence-calls" \
  || fail "risk 37: the classifier did not call through to the death-evidence predicate"
grep -qi "observab\|refus" "$tmp/cls-err" \
  || fail "evidence unknown: no lost-observability warning on stderr"

printf 'alive\n' >"$tmp/evidence-verdict"
out=$(stub_run "$home12" classify "$w" "$s" --now 10000 --heartbeat 9000 \
  --evidence process 12345 2>/dev/null) || fail "evidence alive: non-zero exit"
[ "$out" = hung ] || fail "evidence alive + stale heartbeat: '$out', expected hung (wedged harness)"

printf 'dead\n' >"$tmp/evidence-verdict"
out=$(stub_run "$home12" classify "$w" "$s" --now 10000 --heartbeat 9000 \
  --evidence process 12345 2>/dev/null) || fail "evidence dead: non-zero exit"
[ "$out" = hung ] || fail "evidence dead: '$out', expected hung"
echo "ok: the classifier consults the death-evidence predicate; unknown refuses hung (risk 37)"

# ---------------------------------------------------------------------------
# 13. Real-predicate smoke (no stub): an alive pid with a stale heartbeat is
#     hung via the real fleet-death-evidence.sh process class.
# ---------------------------------------------------------------------------
home13="$tmp/h13"
attn "$home13" heartbeat "$w" "$s" working >/dev/null || fail "setup heartbeat"
out=$(run "$home13" classify "$w" "$s" --now 10000 --heartbeat 9000 --evidence process $$ 2>/dev/null) \
  || fail "real evidence: non-zero exit"
[ "$out" = hung ] || fail "real evidence (alive pid, stale heartbeat): '$out', expected hung"
echo "ok: the real predicate integrates (alive pid + stale heartbeat -> hung)"

# ---------------------------------------------------------------------------
# 14. REQ-A1.3 — flailing escalates to EXACTLY ONE decision-queue entry, stays
#     at one across repeated classification, and issues no restart or nudge:
#     the audit trail records the escalation and nothing act-like, and the
#     death-evidence stub is not consulted to authorize any action.
# ---------------------------------------------------------------------------
home14="$tmp/h14"
attn "$home14" heartbeat "$w" "$s" working >/dev/null || fail "setup heartbeat"
: >"$tmp/evidence-calls"
stub_run "$home14" classify "$w" "$s" --now 10000 --heartbeat 9990 --progress sha-f >/dev/null || fail "esc 1"
stub_run "$home14" classify "$w" "$s" --now 10060 --heartbeat 10050 --progress sha-f >/dev/null || fail "esc 2"
out=$(stub_run "$home14" classify "$w" "$s" --now 10120 --heartbeat 10110 --progress sha-f) || fail "esc 3"
[ "$out" = flailing ] || fail "escalation fixture did not reach flailing (got '$out')"
qc=$(attn "$home14" queue --count) || fail "queue --count failed"
[ "$qc" = 1 ] || fail "flailing: queue count $qc, expected exactly 1"

out=$(stub_run "$home14" classify "$w" "$s" --now 10180 --heartbeat 10170 --progress sha-f) || fail "esc 4"
[ "$out" = awaiting-human ] || fail "post-escalation classify: '$out', expected awaiting-human"
qc=$(attn "$home14" queue --count) || fail "queue --count failed"
[ "$qc" = 1 ] || fail "repeated classify: queue count $qc, expected still exactly 1"

[ ! -s "$tmp/evidence-calls" ] || fail "flailing path consulted the death predicate (no action may be authorized)"
aud=$(audit_q "$home14" 2>/dev/null) || fail "audit query failed"
printf '%s\n' "$aud" | awk -F "$tab" '$4 == "escalate" { found = 1 } END { exit !found }' \
  || fail "flailing escalation not in the audit trail"
printf '%s\n' "$aud" | awk -F "$tab" '$4 ~ /restart|nudge|relaunch/ { found = 1 } END { exit !found }' \
  && fail "audit trail records an act-like ACTION for a flailing worker (REQ-A1.3 forbids restart/nudge)"
echo "ok: flailing queues exactly one human decision and never restarts or nudges"

# ---------------------------------------------------------------------------
# 15. Risk 31 — audit scoping: routine classification writes NO audit rows.
# ---------------------------------------------------------------------------
home15="$tmp/h15"
attn "$home15" heartbeat "$w" "$s" working >/dev/null || fail "setup heartbeat"
run "$home15" classify "$w" "$s" --now 10000 --heartbeat 9990 --progress sha-r >/dev/null || fail "routine classify"
aud=$(audit_q "$home15" 2>/dev/null) || fail "audit query failed"
[ -z "$aud" ] || fail "routine classification wrote audit rows (risk 31 scopes the trail to actions): $aud"
echo "ok: routine classification stays out of the audit trail"

# ---------------------------------------------------------------------------
# 16. REQ-A1.4 — the crash-loop backoff escalates on the configured schedule
#     (base 30, doubling), gates relaunch while backing off, and disables at
#     the configured threshold with a queue entry and an audit disable row.
# ---------------------------------------------------------------------------
home16="$tmp/h16"
out=$(run "$home16" crash-record "$w" "$s" --now 1000) || fail "crash 1: non-zero exit"
[ "$out" = "1 30" ] || fail "crash 1: '$out', expected '1 30'"
rc=0
run "$home16" crash-check "$w" --now 1010 >/dev/null 2>&1 || rc=$?
[ "$rc" = 1 ] || fail "crash-check during backoff: exit $rc, expected 1"
rc=0
run "$home16" crash-check "$w" --now 1031 >/dev/null 2>&1 || rc=$?
[ "$rc" = 0 ] || fail "crash-check after the delay: exit $rc, expected 0"

out=$(run "$home16" crash-record "$w" "$s" --now 1100) || fail "crash 2: non-zero exit"
[ "$out" = "2 60" ] || fail "crash 2: '$out', expected '2 60' (the schedule escalates)"

out=$(run "$home16" crash-record "$w" "$s" --now 1200) || fail "crash 3: non-zero exit"
case $out in
  disabled*) ;;
  *) fail "crash 3 (threshold 3): '$out', expected the disable arm" ;;
esac
rc=0
run "$home16" crash-check "$w" --now 99999 >/dev/null 2>&1 || rc=$?
[ "$rc" = 3 ] || fail "crash-check when disabled: exit $rc, expected 3 (never relaunch)"
qc=$(attn "$home16" queue --count) || fail "queue --count failed"
[ "$qc" = 1 ] || fail "disable: queue count $qc, expected 1 (the human decision recording the disable)"
aud=$(audit_q "$home16" --mechanism liveness-backoff 2>/dev/null) || fail "audit query failed"
printf '%s\n' "$aud" | grep -q "backoff" || fail "backoff actions not in the audit trail"
printf '%s\n' "$aud" | grep -q "disable" || fail "the disable action not in the audit trail"
echo "ok: crashes back off on the escalating schedule and disable at the threshold"

# ---------------------------------------------------------------------------
# 17. REQ-A1.4 — the schedule shape: with a high disable threshold the delay
#     doubles from the base and caps at 3600s.
# ---------------------------------------------------------------------------
cfg17="$tmp/cfg17.yml"
sed 's/^fleet_crash_disable_threshold: .*/fleet_crash_disable_threshold: 99/' "$core_cfg" >"$cfg17"
home17="$tmp/h17"
expected="30 60 120 240 480 960 1920 3600"
i=1
for want in $expected; do
  out=$(env PLANWRIGHT_FLEET_STATE_DIR="$home17" \
    PLANWRIGHT_CONFIG_DEFAULTS="$cfg17" \
    PLANWRIGHT_ADOPTER_OVERLAY="$adopter_root" \
    PLANWRIGHT_REPO_ROOT="$repo" \
    PLANWRIGHT_LOCAL_CONFIG="" \
    /bin/bash "$FL" crash-record "$w" "$s" --now $((1000 + i * 10))) \
    || fail "schedule crash $i: non-zero exit"
  [ "$out" = "$i $want" ] || fail "schedule crash $i: '$out', expected '$i $want'"
  i=$((i + 1))
done
echo "ok: the relaunch delay doubles from the base and caps at 3600s"

# ---------------------------------------------------------------------------
# 18. crash-reset clears the streak (a healthy run resets the counter).
# ---------------------------------------------------------------------------
run "$home16" crash-reset "$w" >/dev/null || fail "crash-reset: non-zero exit"
rc=0
run "$home16" crash-check "$w" --now 99999 >/dev/null 2>&1 || rc=$?
[ "$rc" = 0 ] || fail "crash-check after reset: exit $rc, expected 0"
out=$(run "$home16" crash-record "$w" "$s" --now 100000) || fail "crash after reset"
[ "$out" = "1 30" ] || fail "crash after reset: '$out', expected the schedule to restart at '1 30'"
echo "ok: crash-reset clears the consecutive-failure streak"

# ---------------------------------------------------------------------------
# 19. The operator kill-switch (fleet-daemon-gate) short-circuits relaunch
#     authorization: with fleet_daemon_pause true, crash-check refuses even a
#     worker that is past its delay and not disabled.
# ---------------------------------------------------------------------------
cfg19="$tmp/cfg19.yml"
sed 's/^fleet_daemon_pause: .*/fleet_daemon_pause: true/' "$core_cfg" >"$cfg19"
home19="$tmp/h19"
run "$home19" crash-record "$w" "$s" --now 1000 >/dev/null || fail "kill-switch setup: crash-record"
rc=0
err=$(env PLANWRIGHT_FLEET_STATE_DIR="$home19" \
  PLANWRIGHT_CONFIG_DEFAULTS="$cfg19" \
  PLANWRIGHT_ADOPTER_OVERLAY="$adopter_root" \
  PLANWRIGHT_REPO_ROOT="$repo" \
  PLANWRIGHT_LOCAL_CONFIG="" \
  /bin/bash "$FL" crash-check "$w" --now 99999 2>&1 >/dev/null) || rc=$?
[ "$rc" != 0 ] || fail "kill-switch: crash-check authorized a relaunch under fleet_daemon_pause"
case $err in
  *fleet_daemon_pause* | *paus*) ;;
  *) fail "kill-switch: refusal does not name the pause (got: '$err')" ;;
esac
echo "ok: the operator kill-switch short-circuits relaunch authorization"

# ---------------------------------------------------------------------------
# 20. Knobs resolve through the shared resolver: an overlay value lowers the
#     flailing threshold to 2.
# ---------------------------------------------------------------------------
cfg20="$tmp/cfg20.yml"
sed 's/^fleet_flailing_threshold: .*/fleet_flailing_threshold: 2/' "$core_cfg" >"$cfg20"
home20="$tmp/h20"
attn "$home20" heartbeat "$w" "$s" working >/dev/null || fail "setup heartbeat"
knob_run() {
  env PLANWRIGHT_FLEET_STATE_DIR="$home20" \
    PLANWRIGHT_CONFIG_DEFAULTS="$cfg20" \
    PLANWRIGHT_ADOPTER_OVERLAY="$adopter_root" \
    PLANWRIGHT_REPO_ROOT="$repo" \
    PLANWRIGHT_LOCAL_CONFIG="" \
    /bin/bash "$FL" "$@"
}
knob_run classify "$w" "$s" --now 10000 --heartbeat 9990 --progress sha-k >/dev/null || fail "knob 1"
out=$(knob_run classify "$w" "$s" --now 10060 --heartbeat 10050 --progress sha-k) || fail "knob 2"
[ "$out" = flailing ] || fail "threshold 2: second no-progress observation classified '$out', expected flailing"
echo "ok: the flailing threshold resolves through the shared knob resolver"

# ---------------------------------------------------------------------------
# 21. Usage and hostile input are refused (exit 2): unknown subcommand,
#     unknown hook event, hostile worker handles on every store-touching
#     subcommand, malformed --now/--heartbeat/--progress.
# ---------------------------------------------------------------------------
for args in "" "bogus" "hook" "hook not-an-event" "push-capable" "classify" \
  "crash-record" "crash-check" "crash-reset"; do
  rc=0
  # shellcheck disable=SC2086
  run "$tmp/h21" $args >/dev/null 2>&1 || rc=$?
  [ "$rc" = 2 ] || fail "usage '$args': exit $rc, expected 2"
done
# shellcheck disable=SC2016 # the literal '$(x)' is the hostile token under test
for bad in 'w w' 'w/../x' '$(x)'; do
  rc=0
  run "$tmp/h21" classify "$bad" "$s" --now 1000 >/dev/null 2>&1 || rc=$?
  [ "$rc" = 2 ] || fail "hostile worker '$bad' (classify): exit $rc, expected 2"
  rc=0
  run "$tmp/h21" crash-record "$bad" "$s" --now 1000 >/dev/null 2>&1 || rc=$?
  [ "$rc" = 2 ] || fail "hostile worker '$bad' (crash-record): exit $rc, expected 2"
done
rc=0
run "$tmp/h21" classify "$w" "$s" --now 12x3 >/dev/null 2>&1 || rc=$?
[ "$rc" = 2 ] || fail "malformed --now: exit $rc, expected 2"
rc=0
run "$tmp/h21" classify "$w" "$s" --now 1000 --heartbeat -5 >/dev/null 2>&1 || rc=$?
[ "$rc" = 2 ] || fail "malformed --heartbeat: exit $rc, expected 2"
rc=0
run "$tmp/h21" classify "$w" "$s" --now 1000 --progress 'a b' >/dev/null 2>&1 || rc=$?
[ "$rc" = 2 ] || fail "hostile --progress: exit $rc, expected 2"
[ ! -e "$tmp/h21/attention/state" ] || fail "a refused invocation wrote the store"
echo "ok: usage errors and hostile input are refused with no write"

echo "ALL PASS: fleet-liveness.sh"
