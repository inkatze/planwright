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
#   - REQ-A1.1 fallback: `push-capable` reads the capability contract's
#     hook_registration field (execution-backends D-7) — push for the
#     hook-registering backends (tmux, headless-oneshot,
#     stream-json-persistent), the existing capture-pane observation fallback
#     for subagent, print, and in-session rather than failing (kickoff risk
#     row 16);
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
    /bin/sh "$FL" "$@" </dev/null
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
      /bin/sh "$FL" hook "$rh_event"
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
  /bin/sh "$FL" hook stop >/dev/null 2>&1 || rc=$?
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
  /bin/sh "$FL" hook stop 2>&1 >/dev/null) || rc=$?
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
# 8. REQ-A1.1 fallback (risk 16) — push-capable: which liveness mechanism a
#    backend gets is read from the capability contract's hook_registration
#    field (execution-backends D-7, Task 2 Done-when: never keyed on backend
#    names). tmux and the two new session-grade rows advertise
#    hook_registration=true → push; subagent (in-process), in-session (the
#    tower's own session), and print (no process spawned at all — the contract
#    exempts print units from the liveness predicate) advertise false and fall
#    back to the existing observation path (named on stdout) rather than
#    failing.
# ---------------------------------------------------------------------------
for b in tmux headless-oneshot stream-json-persistent; do
  rc=0
  out=$(run "$tmp/h8" push-capable "$b") || rc=$?
  [ "$rc" = 0 ] || fail "push-capable $b: exit $rc, expected 0"
  [ "$out" = push ] || fail "push-capable $b: '$out', expected 'push' (hook_registration=true)"
done
for b in subagent print in-session; do
  rc=0
  out=$(run "$tmp/h8" push-capable "$b") || rc=$?
  [ "$rc" = 1 ] || fail "push-capable $b: exit $rc, expected 1 (fallback, not failure)"
  [ "$out" = observe ] || fail "push-capable $b: '$out', expected 'observe' (the observation fallback)"
done
rc=0
run "$tmp/h8" push-capable no-such-backend >/dev/null 2>&1 || rc=$?
[ "$rc" = 2 ] || fail "push-capable unknown backend: exit $rc, expected 2"
echo "ok: push-capable reads hook_registration from the contract, never backend names"

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
  refused) exit 2 ;;
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
    /bin/sh "$stubbin/fleet-liveness.sh" "$@"
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
# Assert on the ACTION field (field 4) — a substring grep would match the
# mechanism name "liveness-backoff" in every row and pass vacuously.
printf '%s\n' "$aud" | awk -F "$tab" '$4 == "backoff" { found = 1 } END { exit !found }' \
  || fail "backoff ACTION rows not in the audit trail"
printf '%s\n' "$aud" | awk -F "$tab" '$4 == "disable" { found = 1 } END { exit !found }' \
  || fail "the disable ACTION row not in the audit trail"
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
    /bin/sh "$FL" crash-record "$w" "$s" --now $((1000 + i * 10))) \
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
  /bin/sh "$FL" crash-check "$w" --now 99999 2>&1 >/dev/null) || rc=$?
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
    /bin/sh "$FL" "$@"
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
# `.` and `..` are bare dot-runs: the grammar bars `/` so they can never chain
# into a traversal, but a `.`/`..` handle would still misdirect a per-worker
# path, so valid_field refuses them outright (byte-identical across the fleet
# scripts).
for bad in 'w w' 'w/../x' '$(x)' '.' '..'; do
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

# ---------------------------------------------------------------------------
# 22. REQ-A1.2 — the STORE-stamped heartbeat (field 4) drives the hung
#     verdict when no --heartbeat override is given: a working row whose
#     commit-time stamp has aged past the threshold classifies hung.
# ---------------------------------------------------------------------------
home22="$tmp/h22"
attn "$home22" heartbeat "$w" "$s" working >/dev/null || fail "setup heartbeat"
row_ts=$(awk -F "$tab" -v want="$w" '($1 "") == (want "") { print $4 }' "$home22/attention/state")
case $row_ts in
  "" | *[!0-9]*) fail "could not read the store heartbeat stamp" ;;
esac
out=$(run "$home22" classify "$w" "$s" --now $((row_ts + 1000))) || fail "store-ts classify: non-zero exit"
[ "$out" = hung ] || fail "store-stamped heartbeat aged 1000s: '$out', expected hung"
out=$(run "$home22" classify "$w" "$s" --now $((row_ts + 10))) || fail "store-ts fresh classify failed"
[ "$out" = working ] || fail "store-stamped heartbeat aged 10s: '$out', expected working"
echo "ok: the store's own commit-time heartbeat drives the hung boundary"

# ---------------------------------------------------------------------------
# 23. REQ-A1.2 — a hung store row (a StopFailure push) classifies hung.
# ---------------------------------------------------------------------------
home23="$tmp/h23"
attn "$home23" heartbeat "$w" "$s" hung >/dev/null || fail "setup hung row"
out=$(run "$home23" classify "$w" "$s" --now 10000) || fail "hung-row classify: non-zero exit"
[ "$out" = hung ] || fail "hung store row classified '$out', expected hung"
echo "ok: a pushed hung row classifies hung"

# ---------------------------------------------------------------------------
# 24. REQ-A1.2/REQ-A1.7 — the tmux-window evidence class reaches the
#     predicate with both tokens in order, and a predicate REFUSAL (exit 2,
#     e.g. a pseudo-evidence class) propagates as a classify usage failure.
# ---------------------------------------------------------------------------
home24="$tmp/h24"
attn "$home24" heartbeat "$w" "$s" working >/dev/null || fail "setup heartbeat"
printf 'unknown\n' >"$tmp/evidence-verdict"
: >"$tmp/evidence-calls"
out=$(stub_run "$home24" classify "$w" "$s" --now 10000 --heartbeat 9000 \
  --evidence tmux-window sess win 2>/dev/null) || fail "tmux-window evidence: non-zero exit"
[ "$out" = working ] || fail "tmux-window unknown verdict: '$out', expected working (refused hung)"
grep -q "tmux-window sess win" "$tmp/evidence-calls" \
  || fail "tmux-window evidence tokens did not reach the predicate in order"
printf 'refused\n' >"$tmp/evidence-verdict"
rc=0
stub_run "$home24" classify "$w" "$s" --now 10000 --heartbeat 9000 \
  --evidence process 12345 >/dev/null 2>&1 || rc=$?
[ "$rc" = 2 ] || fail "predicate refusal (exit 2): classify exit $rc, expected 2"
echo "ok: tmux-window evidence passes through; a predicate refusal fails closed"

# ---------------------------------------------------------------------------
# 25. REQ-A1.1 hook discipline — a runtime store-write failure still exits 0
#     (a non-zero Stop-hook exit would block the worker's own stop); the
#     failure is warned and left to the reconcile backstop.
# ---------------------------------------------------------------------------
brokenbin="$tmp/broken-scripts"
mkdir -p "$brokenbin"
cp "$here/../scripts/"*.sh "$brokenbin/"
printf '#!/bin/sh\nexit 2\n' >"$brokenbin/fleet-attention.sh"
chmod +x "$brokenbin/fleet-attention.sh"
rc=0
err=$(printf '{}' | env \
  PLANWRIGHT_WORKER_HANDLE="$w" PLANWRIGHT_WORKER_SCOPE="$s" \
  PLANWRIGHT_FLEET_STATE_DIR="$tmp/h25" \
  PLANWRIGHT_CONFIG_DEFAULTS="$core_cfg" \
  /bin/sh "$brokenbin/fleet-liveness.sh" hook stop 2>&1 >/dev/null) || rc=$?
[ "$rc" = 0 ] || fail "hook with a failing store write: exit $rc, expected 0 (never block the session)"
[ -n "$err" ] || fail "hook write failure was silent (expected a stderr warning)"
echo "ok: a failing store write never turns a hook exit non-zero"

# ---------------------------------------------------------------------------
# 26. REQ-A1.2 — precedence: a stale heartbeat beats a no-progress streak
#     (hung, not flailing), even when the same progress token repeats.
# ---------------------------------------------------------------------------
home26="$tmp/h26"
attn "$home26" heartbeat "$w" "$s" working >/dev/null || fail "setup heartbeat"
run "$home26" classify "$w" "$s" --now 10000 --heartbeat 9000 --progress sha-p >/dev/null || fail "prec 1"
run "$home26" classify "$w" "$s" --now 11000 --heartbeat 9000 --progress sha-p >/dev/null || fail "prec 2"
out=$(run "$home26" classify "$w" "$s" --now 12000 --heartbeat 9000 --progress sha-p) || fail "prec 3"
[ "$out" = hung ] || fail "stale heartbeat + repeated token: '$out', expected hung (staleness wins)"
echo "ok: a stopped heartbeat outranks the no-progress streak"

# ---------------------------------------------------------------------------
# 27. REQ-A1.1 — a half-set identity env (only one of handle/scope) is
#     refused with a warning, no write, exit 0.
# ---------------------------------------------------------------------------
rc=0
err=$(printf '{}' | env -u PLANWRIGHT_WORKER_SCOPE \
  PLANWRIGHT_WORKER_HANDLE="$w" \
  PLANWRIGHT_FLEET_STATE_DIR="$tmp/h27" \
  PLANWRIGHT_CONFIG_DEFAULTS="$core_cfg" \
  /bin/sh "$FL" hook stop 2>&1 >/dev/null) || rc=$?
[ "$rc" = 0 ] || fail "half-set env: exit $rc, expected 0"
[ -n "$err" ] || fail "half-set env refused silently (expected a warning)"
[ ! -e "$tmp/h27/attention/state" ] || fail "half-set env wrote the store"
echo "ok: a half-set identity env is refused loudly with no write"

# ---------------------------------------------------------------------------
# 28. Hostile handles are refused by crash-check and crash-reset too.
# ---------------------------------------------------------------------------
# shellcheck disable=SC2016 # the literal '$(x)' is the hostile token under test
for bad in 'w w' 'w/../x' '$(x)' '.' '..'; do
  rc=0
  run "$tmp/h28" crash-check "$bad" --now 1000 >/dev/null 2>&1 || rc=$?
  [ "$rc" = 2 ] || fail "hostile worker '$bad' (crash-check): exit $rc, expected 2"
  rc=0
  run "$tmp/h28" crash-reset "$bad" >/dev/null 2>&1 || rc=$?
  [ "$rc" = 2 ] || fail "hostile worker '$bad' (crash-reset): exit $rc, expected 2"
done
echo "ok: crash-check and crash-reset refuse hostile handles"

# ---------------------------------------------------------------------------
# 29. REQ-A1.2 — a flailing threshold ABOVE the 50-row history floor still
#     fires: the observation window scales with the knob (regression for the
#     silent cap at 50).
# ---------------------------------------------------------------------------
cfg29="$tmp/cfg29.yml"
sed 's/^fleet_flailing_threshold: .*/fleet_flailing_threshold: 52/' "$core_cfg" >"$cfg29"
home29="$tmp/h29"
attn "$home29" heartbeat "$w" "$s" working >/dev/null || fail "setup heartbeat"
big_run() {
  env PLANWRIGHT_FLEET_STATE_DIR="$home29" \
    PLANWRIGHT_CONFIG_DEFAULTS="$cfg29" \
    PLANWRIGHT_ADOPTER_OVERLAY="$adopter_root" \
    PLANWRIGHT_REPO_ROOT="$repo" \
    PLANWRIGHT_LOCAL_CONFIG="" \
    /bin/sh "$FL" "$@"
}
i=1
while [ "$i" -lt 52 ]; do
  out=$(big_run classify "$w" "$s" --now $((20000 + i * 60)) --heartbeat $((19990 + i * 60)) --progress sha-cap) \
    || fail "window obs $i: non-zero exit"
  [ "$out" = working ] || fail "window obs $i: '$out', expected working (below threshold 52)"
  i=$((i + 1))
done
out=$(big_run classify "$w" "$s" --now $((20000 + 52 * 60)) --heartbeat $((19990 + 52 * 60)) --progress sha-cap) \
  || fail "window obs 52: non-zero exit"
[ "$out" = flailing ] || fail "threshold 52, observation 52: '$out', expected flailing (window must scale)"
echo "ok: the observation window scales with a threshold above 50"

# ---------------------------------------------------------------------------
# 30. REQ-A1.4 — the disable is STICKY: raising the threshold after a worker
#     was disabled never silently re-enables it; only crash-reset does.
# ---------------------------------------------------------------------------
home30="$tmp/h30"
run "$home30" crash-record "$w" "$s" --now 1000 >/dev/null || fail "sticky setup crash 1"
run "$home30" crash-record "$w" "$s" --now 1100 >/dev/null || fail "sticky setup crash 2"
out=$(run "$home30" crash-record "$w" "$s" --now 1200) || fail "sticky setup crash 3"
case $out in disabled*) ;; *) fail "sticky setup did not disable (got '$out')" ;; esac
cfg30="$tmp/cfg30.yml"
sed 's/^fleet_crash_disable_threshold: .*/fleet_crash_disable_threshold: 99/' "$core_cfg" >"$cfg30"
out=$(env PLANWRIGHT_FLEET_STATE_DIR="$home30" \
  PLANWRIGHT_CONFIG_DEFAULTS="$cfg30" \
  PLANWRIGHT_ADOPTER_OVERLAY="$adopter_root" \
  PLANWRIGHT_REPO_ROOT="$repo" \
  PLANWRIGHT_LOCAL_CONFIG="" \
  /bin/sh "$FL" crash-record "$w" "$s" --now 99999) || fail "sticky crash 4 failed"
case $out in
  "disabled 4") ;;
  *) fail "raised threshold un-disabled the worker (got '$out', expected 'disabled 4')" ;;
esac
rc=0
run "$home30" crash-check "$w" --now 999999 >/dev/null 2>&1 || rc=$?
[ "$rc" = 3 ] || fail "sticky: crash-check exit $rc, expected 3 (still disabled)"
run "$home30" crash-reset "$w" >/dev/null || fail "sticky: crash-reset failed"
rc=0
run "$home30" crash-check "$w" --now 999999 >/dev/null 2>&1 || rc=$?
[ "$rc" = 0 ] || fail "sticky: crash-check after reset exit $rc, expected 0"
echo "ok: the disable is sticky until a human crash-reset"

# ---------------------------------------------------------------------------
# 31. REQ-A1.4 — the terminal disabled state outranks the kill-switch
#     (exit 3, never masked as paused), and crash-check re-upserts the
#     disable escalation when the queue entry went missing (the
#     crash-record-died-before-decide self-heal).
# ---------------------------------------------------------------------------
home31="$tmp/h31"
run "$home31" crash-record "$w" "$s" --now 1000 >/dev/null || fail "heal setup crash 1"
run "$home31" crash-record "$w" "$s" --now 1100 >/dev/null || fail "heal setup crash 2"
run "$home31" crash-record "$w" "$s" --now 1200 >/dev/null || fail "heal setup crash 3"
rc=0
env PLANWRIGHT_FLEET_STATE_DIR="$home31" \
  PLANWRIGHT_CONFIG_DEFAULTS="$cfg19" \
  PLANWRIGHT_ADOPTER_OVERLAY="$adopter_root" \
  PLANWRIGHT_REPO_ROOT="$repo" \
  PLANWRIGHT_LOCAL_CONFIG="" \
  /bin/sh "$FL" crash-check "$w" --now 99999 >/dev/null 2>&1 || rc=$?
[ "$rc" = 3 ] || fail "disabled under kill-switch: exit $rc, expected 3 (terminal state never masked)"
attn "$home31" clear "$w" >/dev/null || fail "heal: clear failed"
qc=$(attn "$home31" queue --count) || fail "queue --count failed"
[ "$qc" = 0 ] || fail "heal setup: queue not empty after clear"
rc=0
run "$home31" crash-check "$w" --now 99999 >/dev/null 2>&1 || rc=$?
[ "$rc" = 3 ] || fail "heal: crash-check exit $rc, expected 3"
qc=$(attn "$home31" queue --count) || fail "queue --count failed"
[ "$qc" = 1 ] || fail "heal: crash-check did not re-upsert the missing disable escalation (queue $qc)"
echo "ok: disabled outranks paused, and the disable escalation self-heals on check"

# ---------------------------------------------------------------------------
# 32. crash-reset surfaces a removal failure (exit 2, streak NOT cleared)
#     instead of lying with exit 0. Skipped under root, which bypasses the
#     directory permission and lets rm succeed anyway (repo convention).
# ---------------------------------------------------------------------------
if [ "$(id -u)" -ne 0 ]; then
  home32="$tmp/h32"
  run "$home32" crash-record "$w" "$s" --now 1000 >/dev/null || fail "reset-fail setup"
  chmod 555 "$home32/liveness/crash" || fail "reset-fail: chmod failed"
  rc=0
  run "$home32" crash-reset "$w" >/dev/null 2>&1 || rc=$?
  chmod 755 "$home32/liveness/crash"
  [ "$rc" = 2 ] || fail "crash-reset with unwritable dir: exit $rc, expected 2"
  [ -e "$home32/liveness/crash/$w" ] || fail "reset-fail: record vanished despite the failure exit"
  echo "ok: a failed crash-reset is surfaced, never reported as success"
else
  echo "skip: crash-reset removal-failure test (running as root bypasses dir permissions)"
fi

# ---------------------------------------------------------------------------
# 33. A missing knob resolver is the broken-install hard-fail (exit 5),
#     never a raw shell 126/127.
# ---------------------------------------------------------------------------
noresolver="$tmp/noresolver-scripts"
mkdir -p "$noresolver"
cp "$here/../scripts/"*.sh "$noresolver/"
rm -f "$noresolver/resolve-config-knob.sh"
rc=0
env PLANWRIGHT_FLEET_STATE_DIR="$tmp/h33" \
  PLANWRIGHT_CONFIG_DEFAULTS="$core_cfg" \
  /bin/sh "$noresolver/fleet-liveness.sh" classify "$w" "$s" --now 10000 >/dev/null 2>&1 || rc=$?
[ "$rc" = 5 ] || fail "missing resolver: classify exit $rc, expected 5 (broken install)"
echo "ok: a missing knob resolver fails as a broken install (exit 5)"

# ---------------------------------------------------------------------------
# 34. The flailing escalation audits BEFORE it queues: an audit-trail
#     failure fails the classification closed with NO queue entry (a queued
#     fork whose escalate action is permanently missing from the trail is
#     the unrecoverable order).
# ---------------------------------------------------------------------------
noaudit="$tmp/noaudit-scripts"
mkdir -p "$noaudit"
cp "$here/../scripts/"*.sh "$noaudit/"
printf '#!/bin/sh\nexit 2\n' >"$noaudit/fleet-audit.sh"
chmod +x "$noaudit/fleet-audit.sh"
home34="$tmp/h34"
attn "$home34" heartbeat "$w" "$s" working >/dev/null || fail "audit-first setup"
na_run() {
  env PLANWRIGHT_FLEET_STATE_DIR="$home34" \
    PLANWRIGHT_CONFIG_DEFAULTS="$core_cfg" \
    PLANWRIGHT_ADOPTER_OVERLAY="$adopter_root" \
    PLANWRIGHT_REPO_ROOT="$repo" \
    PLANWRIGHT_LOCAL_CONFIG="" \
    /bin/sh "$noaudit/fleet-liveness.sh" "$@"
}
na_run classify "$w" "$s" --now 10000 --heartbeat 9990 --progress sha-au >/dev/null || fail "audit-first obs 1"
na_run classify "$w" "$s" --now 10060 --heartbeat 10050 --progress sha-au >/dev/null || fail "audit-first obs 2"
rc=0
na_run classify "$w" "$s" --now 10120 --heartbeat 10110 --progress sha-au >/dev/null 2>&1 || rc=$?
[ "$rc" = 2 ] || fail "audit failure on escalation: exit $rc, expected 2"
qc=$(attn "$home34" queue --count) || fail "queue --count failed"
[ "$qc" = 0 ] || fail "audit-first: a queue entry landed despite the audit failure (count $qc)"
echo "ok: the escalation audits before it queues (audit failure -> no queue entry)"

# ---------------------------------------------------------------------------
# 35. REQ-A1.2 / kickoff risk 3 — the no-progress streak counts only
#     observations taken while the worker was working (or had no row yet, the
#     startup/observe default): a stretch spent awaiting-input (a permission
#     block: no progress is EXPECTED) must not inflate the streak into a
#     spurious flailing escalation the moment the worker resumes.
# ---------------------------------------------------------------------------
home35="$tmp/h35"
attn "$home35" decide "$w" "$s" "may I run this?" "deny" "allow|deny" high >/dev/null \
  || fail "streak-scope setup: decide failed"
# Three classification cycles while blocked: each observes the same progress
# token and an awaiting-input row (threshold is 3).
out=$(run "$home35" classify "$w" "$s" --now 10000 --heartbeat 9990 --progress sha-w) || fail "blocked obs 1"
[ "$out" = awaiting-human ] || fail "blocked obs 1: '$out', expected awaiting-human"
run "$home35" classify "$w" "$s" --now 10060 --heartbeat 10050 --progress sha-w >/dev/null || fail "blocked obs 2"
run "$home35" classify "$w" "$s" --now 10120 --heartbeat 10110 --progress sha-w >/dev/null || fail "blocked obs 3"
# The permission resolves; the worker resumes (the post-tool-use push).
attn "$home35" heartbeat "$w" "$s" working >/dev/null || fail "streak-scope resume"
out=$(run "$home35" classify "$w" "$s" --now 10180 --heartbeat 10170 --progress sha-w) \
  || fail "post-resume classify: non-zero exit"
[ "$out" = working ] \
  || fail "streak-scope: '$out', expected working (blocked-stretch observations counted toward the streak)"
# A genuine post-resume no-progress streak still fires at the threshold.
run "$home35" classify "$w" "$s" --now 10240 --heartbeat 10230 --progress sha-w >/dev/null || fail "resumed obs 2"
out=$(run "$home35" classify "$w" "$s" --now 10300 --heartbeat 10290 --progress sha-w) || fail "resumed obs 3"
[ "$out" = flailing ] || fail "streak-scope: '$out', expected flailing (a real working streak must still fire)"
echo "ok: awaiting-input observations never count toward the flailing streak"

# ---------------------------------------------------------------------------
# 36. REQ-A1.4 — the crash-record disable path audits BEFORE it queues (the
#     classifier's ordering): an audit failure exits 2 with NO queue entry
#     (the counter is already durable), and the next crash-check re-upserts
#     the escalation — the trail never lags the queue.
# ---------------------------------------------------------------------------
noaudit2="$tmp/noaudit2-scripts"
mkdir -p "$noaudit2"
cp "$here/../scripts/"*.sh "$noaudit2/"
printf '#!/bin/sh\nexit 2\n' >"$noaudit2/fleet-audit.sh"
chmod +x "$noaudit2/fleet-audit.sh"
home36="$tmp/h36"
na2_run() {
  env PLANWRIGHT_FLEET_STATE_DIR="$home36" \
    PLANWRIGHT_CONFIG_DEFAULTS="$core_cfg" \
    PLANWRIGHT_ADOPTER_OVERLAY="$adopter_root" \
    PLANWRIGHT_REPO_ROOT="$repo" \
    PLANWRIGHT_LOCAL_CONFIG="" \
    /bin/sh "$noaudit2/fleet-liveness.sh" "$@"
}
# Crashes 1-2: the backoff audit fails (exit 2) but each counter is durable.
na2_run crash-record "$w" "$s" --now 1000 >/dev/null 2>&1 || true
na2_run crash-record "$w" "$s" --now 1100 >/dev/null 2>&1 || true
# Crash 3 crosses the threshold: the disable must audit first, so the failed
# audit leaves NO queue entry (crash-check owns the self-heal).
rc=0
out=$(na2_run crash-record "$w" "$s" --now 1200 2>/dev/null) || rc=$?
[ "$rc" = 2 ] || fail "disable audit failure: exit $rc, expected 2"
case $out in
  disabled*) ;;
  *) fail "disable audit failure: '$out', expected the durable disabled record" ;;
esac
qc=$(attn "$home36" queue --count) || fail "queue --count failed"
[ "$qc" = 0 ] || fail "disable audits first: a queue entry landed despite the audit failure (count $qc)"
# The self-heal: the next crash-check re-upserts the missing escalation.
rc=0
run "$home36" crash-check "$w" --now 99999 >/dev/null 2>&1 || rc=$?
[ "$rc" = 3 ] || fail "post-heal crash-check: exit $rc, expected 3 (disabled)"
qc=$(attn "$home36" queue --count) || fail "queue --count failed"
[ "$qc" = 1 ] || fail "crash-check did not re-upsert the disable escalation (count $qc)"
echo "ok: the disable audits before it queues, and crash-check heals the queue entry"

# ---------------------------------------------------------------------------
# 37. A missing daemon gate is the broken-install hard-fail (exit 5, the
#     knob-resolver discipline), never a raw shell 126/127 — and a gate
#     hard-fail (exit 4, unresolvable kill-switch) propagates as-is: never
#     relaunch under unknown switch state.
# ---------------------------------------------------------------------------
nogate="$tmp/nogate-scripts"
mkdir -p "$nogate"
cp "$here/../scripts/"*.sh "$nogate/"
rm -f "$nogate/fleet-daemon-gate.sh"
rc=0
env PLANWRIGHT_FLEET_STATE_DIR="$tmp/h37" \
  PLANWRIGHT_CONFIG_DEFAULTS="$core_cfg" \
  /bin/sh "$nogate/fleet-liveness.sh" crash-check "$w" --now 10000 >/dev/null 2>&1 || rc=$?
[ "$rc" = 5 ] || fail "missing daemon gate: crash-check exit $rc, expected 5 (broken install)"
gate4="$tmp/gate4-scripts"
mkdir -p "$gate4"
cp "$here/../scripts/"*.sh "$gate4/"
printf '#!/bin/sh\nexit 4\n' >"$gate4/fleet-daemon-gate.sh"
chmod +x "$gate4/fleet-daemon-gate.sh"
rc=0
env PLANWRIGHT_FLEET_STATE_DIR="$tmp/h37b" \
  PLANWRIGHT_CONFIG_DEFAULTS="$core_cfg" \
  /bin/sh "$gate4/fleet-liveness.sh" crash-check "$w" --now 10000 >/dev/null 2>&1 || rc=$?
[ "$rc" = 4 ] || fail "unresolvable kill-switch: crash-check exit $rc, expected 4 (propagated)"
echo "ok: a missing daemon gate fails as a broken install; a gate hard-fail propagates"

# ---------------------------------------------------------------------------
# 38. REQ-A1.7 posture — an attention store that exists but cannot be read
#     fails the classification closed (exit 2), never open: a blind classifier
#     must not report a possibly-hung worker as working. Skipped under root,
#     which reads through chmod 000 and would make classify succeed (repo
#     convention).
# ---------------------------------------------------------------------------
if [ "$(id -u)" -ne 0 ]; then
  home38="$tmp/h38"
  attn "$home38" heartbeat "$w" "$s" working >/dev/null || fail "unreadable-store setup"
  chmod 000 "$home38/attention/state" || fail "unreadable-store: chmod failed"
  rc=0
  out=$(run "$home38" classify "$w" "$s" --now 10000 --heartbeat 9990 2>/dev/null) || rc=$?
  chmod 644 "$home38/attention/state"
  [ "$rc" = 2 ] || fail "unreadable store: classify exit $rc ('$out'), expected 2 (fail closed)"
  echo "ok: an unreadable attention store fails the classification closed"
else
  echo "skip: unreadable-store test (running as root reads through chmod 000)"
fi

# ---------------------------------------------------------------------------
# 39. store_row_field is LAST-WRITE-WINS: one row per worker is the store
#     invariant (upsert, last wins), but external corruption could leave more.
#     store_row_field must then return a SINGLE field value (the last matching
#     row's), never a multi-line value — otherwise classify would embed a
#     newline into the observations TSV and break its 4-field-per-line format,
#     and single-string state compares would fail. (Corruption detection itself
#     is a separate concern; here we only assert no reader emits a torn value.)
# ---------------------------------------------------------------------------
home39="$tmp/h39"
attn "$home39" heartbeat "$w" "$s" working >/dev/null || fail "multirow-read setup: heartbeat"
# Inject a second, later row for the same worker (awaiting-input) — corruption.
printf '%s\t%s\tawaiting-input\t1\thigh\tq\td\to\n' "$w" "$s" >>"$home39/attention/state"
rows=$(awk -F "$tab" -v want="$w" '($1 "") == (want "") { c++ } END { print c + 0 }' \
  "$home39/attention/state")
[ "$rows" = 2 ] || fail "multirow-read setup: expected 2 rows, got $rows"
run "$home39" classify "$w" "$s" --now 20000 --heartbeat 19990 --progress p1 >/dev/null 2>&1 \
  || fail "multirow classify: non-zero exit"
obs39="$home39/liveness/observations/$w.tsv"
[ -f "$obs39" ] || fail "multirow classify: no observations file written"
# Every observation line must carry exactly 4 tab-separated fields (3 tabs): a
# torn multi-line row_state would leave a stray 1-field line.
badlines=$(awk -F "$tab" 'NF != 4 { n++ } END { print n + 0 }' "$obs39")
[ "$badlines" = 0 ] || fail "multirow classify: $badlines malformed observation line(s) (torn row_state)"
echo "ok: store_row_field is last-write-wins — a corrupt multi-row store never tears the observations TSV"

# ---------------------------------------------------------------------------
# 40. REQ-A1.3 via the marker-identity check: a LEAKED pending-permission
#     marker (one that outlived an ungraceful session death) must never let
#     post-tool-use OR a downgrade push auto-resolve an UNRELATED awaiting-input
#     escalation on a reused handle. The marker carries the permission
#     decision's heartbeat identity; a re-decided row (a flailing / crash
#     escalation) re-stamps the heartbeat, so the stale token no longer matches
#     and the escalation is preserved (the orphan marker is dropped).
# ---------------------------------------------------------------------------
home40="$tmp/h40"
wl="worker=leak"
# A non-permission escalation (a flailing "stuck" decision) occupies the row.
attn "$home40" decide "$wl" "$s" \
  "No forward progress across 3 heartbeats - this task may be stuck" \
  "park for human review" "park for review|relaunch fresh|redirect with guidance" high \
  >/dev/null || fail "leaked-marker setup: decide failed"
# Plant a leaked marker whose stale token cannot match the escalation heartbeat.
mkdir -p "$home40/liveness/pending" || fail "leaked-marker setup: mkdir"
printf '1\n' >"$home40/liveness/pending/$wl"
run_hook "$home40" "$wl" "$s" post-tool-use >/dev/null 2>&1 \
  || fail "leaked-marker post-tool-use: non-zero exit"
st=$(awk -F "$tab" -v want="$wl" '($1 "") == (want "") { print $3 }' "$home40/attention/state")
[ "$st" = awaiting-input ] \
  || fail "leaked marker let post-tool-use clobber an escalation (state=$st, want awaiting-input)"
[ ! -e "$home40/liveness/pending/$wl" ] \
  || fail "leaked-marker post-tool-use: orphan marker not cleaned up"
# A downgrade push (stop) must likewise preserve it. Re-plant the leaked marker.
printf '1\n' >"$home40/liveness/pending/$wl"
run_hook "$home40" "$wl" "$s" stop >/dev/null 2>&1 \
  || fail "leaked-marker stop: non-zero exit"
st=$(awk -F "$tab" -v want="$wl" '($1 "") == (want "") { print $3 }' "$home40/attention/state")
[ "$st" = awaiting-input ] \
  || fail "leaked marker let stop clobber an escalation (state=$st, want awaiting-input)"
echo "ok: a leaked pending-permission marker never clobbers an unrelated escalation (REQ-A1.3)"

echo "ALL PASS: fleet-liveness.sh"
