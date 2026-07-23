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
#   - REQ-A1.1 fallback: `push-capable` names hook-push for the tmux backend
#     (the only backend that launches a hook-registering session) and falls
#     back to the existing capture-pane observation for subagent, print, and
#     in-session rather than failing (kickoff risk row 16);
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
#     flailing threshold), usage/hostile input is refused (exit 2);
#   - the agents-json idle oracle (execution-backends D-11 / REQ-F1.1): the
#     `oracle` subcommand maps session rows to busy / waiting / idle by cwd or
#     sessionId, reports `absent` (exit 3) for an untracked worker (never
#     death), and fails to `unavailable` (exit 1) on a missing binary, a
#     non-zero probe, unparseable output, or a hang past the bounded timeout —
#     never an empty-fleet read; `classify` prefers oracle evidence whenever
#     the probe succeeds (a stale-idle store row is corrected to working, a
#     missed permission push to awaiting-human), never auto-resolves a queued
#     awaiting-input decision, never masks a hung row with oracle idle, keeps
#     the flailing streak fireable under oracle busy, and falls back to the
#     store/heuristic path unchanged when the oracle is unavailable or the
#     worker is absent; a spoofed session name carrying escaped JSON text is
#     parsed as data, never honored as fields.
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
# 8. REQ-A1.1 fallback (risk 16) — push-capable: only tmux launches a
#    dispatch-controlled process (identity env inherited, plugin hooks fire),
#    so only tmux pushes; subagent (in-process), in-session (the tower's own
#    session), and print (no process spawned at all — the capability contract
#    exempts print units from the liveness predicate) fall back to the
#    existing observation path (named on stdout) rather than failing.
# ---------------------------------------------------------------------------
rc=0
out=$(run "$tmp/h8" push-capable tmux) || rc=$?
[ "$rc" = 0 ] || fail "push-capable tmux: exit $rc, expected 0"
[ "$out" = push ] || fail "push-capable tmux: '$out', expected 'push'"
for b in subagent print in-session; do
  rc=0
  out=$(run "$tmp/h8" push-capable "$b") || rc=$?
  [ "$rc" = 1 ] || fail "push-capable $b: exit $rc, expected 1 (fallback, not failure)"
  [ "$out" = observe ] || fail "push-capable $b: '$out', expected 'observe' (the observation fallback)"
done
rc=0
run "$tmp/h8" push-capable no-such-backend >/dev/null 2>&1 || rc=$?
[ "$rc" = 2 ] || fail "push-capable unknown backend: exit $rc, expected 2"
echo "ok: push-capable names hook-push for tmux and the observe fallback for subagent/print/in-session"

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

# ---------------------------------------------------------------------------
# 41. execution-backends D-11 / REQ-F1.1 — the `oracle` subcommand maps the
#     agents-json session rows to a busy/waiting/idle verdict by cwd or
#     sessionId; an untracked worker is `absent` (exit 3, no evidence — never
#     death); busy outranks waiting outranks idle across rows sharing a cwd;
#     a row with no recognized status contributes no evidence.
# ---------------------------------------------------------------------------
odir="$tmp/oracle"
mkdir -p "$odir"
ofix="$odir/fixture.json"
oshim="$odir/agents-shim"
{
  echo '#!/bin/sh'
  # Refuse unexpected invocations so wiring drift fails loudly, then emit the
  # fixture (the shim stands in for the real CLI's `agents --json`).
  # shellcheck disable=SC2016 # $1/$2 are literal shim-script source, expanded at shim runtime, not here
  echo '[ "$1" = agents ] && [ "$2" = --json ] || exit 9'
  echo "cat \"$ofix\""
} >"$oshim"
chmod +x "$oshim"
# Pre-warm the fresh shim once so first-exec latency (macOS) cannot skew the
# timed probes below.
printf '[]\n' >"$ofix"
"$oshim" agents --json >/dev/null 2>&1 || true

# orun <fleet-home> <oracle-bin> <args...> — run with the oracle binary pinned.
orun() {
  or_home=$1
  or_bin=$2
  shift 2
  env -u CLAUDE_PLUGIN_DATA -u CLAUDE_PLUGIN_ROOT -u CLAUDE_DIR -u HOME \
    -u PLANWRIGHT_ROOT -u PLANWRIGHT_WORKER_HANDLE -u PLANWRIGHT_WORKER_SCOPE \
    PLANWRIGHT_FLEET_STATE_DIR="$or_home" \
    PLANWRIGHT_CONFIG_DEFAULTS="$core_cfg" \
    PLANWRIGHT_ADOPTER_OVERLAY="$adopter_root" \
    PLANWRIGHT_REPO_ROOT="$repo" \
    PLANWRIGHT_LOCAL_CONFIG="" \
    PLANWRIGHT_ORACLE_CLAUDE="$or_bin" \
    /bin/sh "$FL" "$@" </dev/null
}

cat >"$ofix" <<'EOF'
[
  {"pid": 100, "id": "a1", "cwd": "/wt/alpha", "kind": "interactive", "startedAt": 1, "sessionId": "aaaa-1111", "name": "alpha-1", "status": "busy"},
  {"pid": 101, "id": "b1", "cwd": "/wt/beta", "kind": "interactive", "startedAt": 2, "sessionId": "bbbb-2222", "name": "beta-1", "status": "waiting", "waitingFor": "permission prompt"},
  {"pid": 102, "id": "c1", "cwd": "/wt/gamma", "kind": "interactive", "startedAt": 3, "sessionId": "cccc-3333", "name": "gamma-1", "status": "idle"},
  {"id": "d1", "cwd": "/wt/delta", "kind": "background", "startedAt": 4, "sessionId": "dddd-4444", "name": "defunct", "state": "blocked"}
]
EOF
home41="$tmp/h41"
out=$(orun "$home41" "$oshim" oracle --cwd /wt/alpha) || fail "oracle busy: non-zero exit"
[ "$out" = busy ] || fail "oracle busy: got '$out'"
out=$(orun "$home41" "$oshim" oracle --cwd /wt/beta) || fail "oracle waiting: non-zero exit"
[ "$out" = waiting ] || fail "oracle waiting: got '$out'"
out=$(orun "$home41" "$oshim" oracle --cwd /wt/gamma) || fail "oracle idle: non-zero exit"
[ "$out" = idle ] || fail "oracle idle: got '$out'"
# sessionId is an equally valid join key
out=$(orun "$home41" "$oshim" oracle --session bbbb-2222) || fail "oracle session-key: non-zero exit"
[ "$out" = waiting ] || fail "oracle session-key: got '$out'"
# a row with no recognized status contributes no evidence -> absent
rc=0
out=$(orun "$home41" "$oshim" oracle --cwd /wt/delta) || rc=$?
[ "$rc" = 3 ] || fail "oracle no-status row: exit $rc, expected 3 (absent)"
[ "$out" = absent ] || fail "oracle no-status row: got '$out', expected absent"
# an untracked worker is absent (exit 3), never a death read
rc=0
out=$(orun "$home41" "$oshim" oracle --cwd /wt/nope) || rc=$?
[ "$rc" = 3 ] || fail "oracle untracked: exit $rc, expected 3 (absent)"
[ "$out" = absent ] || fail "oracle untracked: got '$out', expected absent"
# busy outranks idle across rows sharing a cwd
cat >"$ofix" <<'EOF'
[
  {"pid": 110, "cwd": "/wt/shared", "kind": "interactive", "sessionId": "ee-1", "name": "s1", "status": "idle"},
  {"pid": 111, "cwd": "/wt/shared", "kind": "interactive", "sessionId": "ee-2", "name": "s2", "status": "busy"}
]
EOF
out=$(orun "$home41" "$oshim" oracle --cwd /wt/shared) || fail "oracle precedence: non-zero exit"
[ "$out" = busy ] || fail "oracle precedence: got '$out', expected busy (busy outranks idle)"
# usage floor: a join key is required; hostile values are refused
rc=0
orun "$home41" "$oshim" oracle >/dev/null 2>&1 || rc=$?
[ "$rc" = 2 ] || fail "oracle no-join-key: exit $rc, expected 2 (usage)"
rc=0
orun "$home41" "$oshim" oracle --cwd "$(printf '/wt/bad\tpath')" >/dev/null 2>&1 || rc=$?
[ "$rc" = 2 ] || fail "oracle hostile cwd: exit $rc, expected 2 (refused)"
rc=0
orun "$home41" "$oshim" oracle --cwd relative/path >/dev/null 2>&1 || rc=$?
[ "$rc" = 2 ] || fail "oracle relative cwd: exit $rc, expected 2 (refused)"
rc=0
orun "$home41" "$oshim" oracle --session "$(printf 'bad\nsession')" >/dev/null 2>&1 || rc=$?
[ "$rc" = 2 ] || fail "oracle hostile session: exit $rc, expected 2 (refused)"
echo "ok: oracle verdicts map by cwd/sessionId; untracked is absent, never death; hostile input refused"

# ---------------------------------------------------------------------------
# 41b. Probe temp hygiene — every probe temp file (the stdout capture and its
#      .err / .pid / .done siblings) lives inside a private 0700 mktemp -d
#      directory: the sibling names are derived, not mktemp-secured, so in a
#      shared world-writable TMPDIR a neighbor could otherwise pre-create one
#      (the CWE-377 class; worst case, plant `.pid` and steer the KILL
#      escalation's pid read). Asserted from inside the probe via a
#      snapshotting shim, plus cleanup removing the directory afterward.
# ---------------------------------------------------------------------------
osnap="$odir/snap"
mkdir -p "$osnap"
osnaptmp="$odir/snaptmp"
mkdir -p "$osnaptmp"
osnapfix="$odir/snap-fixture.json"
cat >"$osnapfix" <<'EOF'
[ {"cwd": "/wt/alpha", "sessionId": "zz-1", "name": "z", "status": "busy"} ]
EOF
snapshim="$odir/snap-shim"
{
  echo '#!/bin/sh'
  # shellcheck disable=SC2016 # $1/$2 are literal shim-script source, expanded at shim runtime, not here
  echo '[ "$1" = agents ] && [ "$2" = --json ] || exit 9'
  # Snapshot the probe's TMPDIR layout as seen mid-probe (the stdout capture
  # and .err redirections are already open when the shim runs).
  echo "ls \"\$TMPDIR\" >\"$osnap/top\" 2>/dev/null"
  echo "for d in \"\$TMPDIR\"/planwright-oracle.*; do"
  # shellcheck disable=SC2016 # literal shim-script source, expanded at shim runtime
  echo '  [ -d "$d" ] || continue'
  echo "  ls -ld \"\$d\" | cut -c1-10 >\"$osnap/perm\""
  echo "  ls \"\$d\" >\"$osnap/inner\""
  echo 'done'
  echo "cat \"$osnapfix\""
} >"$snapshim"
chmod +x "$snapshim"
# Pre-warm the fresh shim once (macOS first-exec latency must not eat into
# the probe bound).
"$snapshim" agents --json >/dev/null 2>&1 || true
out=$( (TMPDIR="$osnaptmp" && export TMPDIR && orun "$home41" "$snapshim" oracle --cwd /wt/alpha)) \
  || fail "temp-hygiene probe: non-zero exit"
[ "$out" = busy ] || fail "temp-hygiene probe: got '$out', expected busy"
[ -s "$osnap/top" ] || fail "temp-hygiene: the shim never snapshotted TMPDIR"
while IFS= read -r entry; do
  case $entry in
    planwright-oracle.*) ;;
    *) fail "temp-hygiene: unexpected TMPDIR entry '$entry' (probe files must live inside the private dir)" ;;
  esac
done <"$osnap/top"
[ "$(wc -l <"$osnap/top" | tr -d ' ')" = 1 ] \
  || fail "temp-hygiene: expected exactly one planwright-oracle.* dir in TMPDIR, got: $(tr '\n' ' ' <"$osnap/top")"
[ "$(cat "$osnap/perm" 2>/dev/null)" = "drwx------" ] \
  || fail "temp-hygiene: probe dir perms '$(cat "$osnap/perm" 2>/dev/null)', expected drwx------"
grep -q '^probe$' "$osnap/inner" 2>/dev/null \
  || fail "temp-hygiene: the stdout capture is not inside the private dir"
grep -q '^probe\.err$' "$osnap/inner" 2>/dev/null \
  || fail "temp-hygiene: probe.err is not inside the private dir"
set -- "$osnaptmp"/planwright-oracle.*
[ ! -e "$1" ] || fail "temp-hygiene: probe dir leaked after cleanup: $1"
echo "ok: probe temp files live inside a private 0700 dir and cleanup removes it"

# ---------------------------------------------------------------------------
# 42. REQ-F1.1 — a probe that exits non-zero, hangs past the bounded timeout,
#     or returns unparseable output is oracle-UNAVAILABLE (exit 1, fallback
#     engages), never an empty-fleet read; a missing binary likewise. An empty
#     array is a genuinely empty session list: absent (exit 3), not
#     unavailable.
# ---------------------------------------------------------------------------
home42="$tmp/h42"
failshim="$odir/fail-shim"
printf '#!/bin/sh\nexit 1\n' >"$failshim"
chmod +x "$failshim"
"$failshim" agents --json >/dev/null 2>&1 || true # pre-warm
rc=0
out=$(orun "$home42" "$failshim" oracle --cwd /wt/alpha 2>/dev/null) || rc=$?
[ "$rc" = 1 ] || fail "oracle failing probe: exit $rc, expected 1 (unavailable)"
[ -z "$out" ] || fail "oracle failing probe: stdout '$out', expected empty"
# a missing binary is unavailable, not a crash
rc=0
out=$(orun "$home42" "$odir/does-not-exist" oracle --cwd /wt/alpha 2>/dev/null) || rc=$?
[ "$rc" = 1 ] || fail "oracle missing binary: exit $rc, expected 1 (unavailable)"
# unparseable output (not a JSON array) is unavailable — never an empty fleet
printf 'error: something broke\n' >"$ofix"
rc=0
out=$(orun "$home42" "$oshim" oracle --cwd /wt/alpha 2>/dev/null) || rc=$?
[ "$rc" = 1 ] || fail "oracle garbage output: exit $rc, expected 1 (unavailable)"
# truncated JSON (unbalanced) is unavailable
printf '[ {"cwd": "/wt/alpha", "status": "busy"\n' >"$ofix"
rc=0
out=$(orun "$home42" "$oshim" oracle --cwd /wt/alpha 2>/dev/null) || rc=$?
[ "$rc" = 1 ] || fail "oracle truncated output: exit $rc, expected 1 (unavailable)"
# empty output (zero bytes) is unavailable, not an empty fleet
: >"$ofix"
rc=0
out=$(orun "$home42" "$oshim" oracle --cwd /wt/alpha 2>/dev/null) || rc=$?
[ "$rc" = 1 ] || fail "oracle empty output: exit $rc, expected 1 (unavailable)"
# an empty ARRAY parses: a genuinely empty session list -> absent, not unavailable
printf '[]\n' >"$ofix"
rc=0
out=$(orun "$home42" "$oshim" oracle --cwd /wt/alpha 2>/dev/null) || rc=$?
[ "$rc" = 3 ] || fail "oracle empty array: exit $rc, expected 3 (absent)"
# a hang past the bounded timeout is unavailable, within bounded wall-clock,
# and the probe process is actually terminated (an un-killed probe would
# orphan a CLI per reconcile tick). The shim records its pid, then sleeps far
# past the bound; the wide sleep/bound gap keeps the discrimination unambiguous
# on a loaded host.
slowshim="$odir/slow-shim"
{
  echo '#!/bin/sh'
  echo "echo \$\$ >\"$odir/slow-pid\""
  echo 'sleep 30'
  echo 'printf "[]"'
} >"$slowshim"
chmod +x "$slowshim"
rm -f "$odir/slow-pid"
t0=$(date +%s)
rc=0
# A 5s timeout (not 1s) for THIS case: the kill assertion needs the shim to
# have started and recorded its pid before the bound fires, and process
# startup under a heavily parallel test runner can exceed a second. The
# 30s shim sleep keeps the discrimination unambiguous.
out=$(env PLANWRIGHT_ORACLE_TIMEOUT=5 PLANWRIGHT_FLEET_STATE_DIR="$home42" \
  PLANWRIGHT_CONFIG_DEFAULTS="$core_cfg" PLANWRIGHT_ADOPTER_OVERLAY="$adopter_root" \
  PLANWRIGHT_REPO_ROOT="$repo" PLANWRIGHT_LOCAL_CONFIG="" \
  PLANWRIGHT_ORACLE_CLAUDE="$slowshim" \
  /bin/sh "$FL" oracle --cwd /wt/alpha 2>/dev/null) || rc=$?
t1=$(date +%s)
[ "$rc" = 1 ] || fail "oracle hang: exit $rc, expected 1 (unavailable)"
[ $((t1 - t0)) -lt 25 ] || fail "oracle hang: probe took $((t1 - t0))s, expected the 5s timeout to bound it"
# Guard the read: a missing pid file must reach the named assertion below,
# never a silent set -e abort mid-suite.
slow_pid=$(cat "$odir/slow-pid" 2>/dev/null || true)
[ -n "$slow_pid" ] || fail "oracle hang: the shim never recorded its pid"
kill_ok=0
for _ in 1 2 3 4 5 6 7 8 9 10; do
  if ! kill -0 "$slow_pid" 2>/dev/null; then
    kill_ok=1
    break
  fi
  sleep 0.3
done
[ "$kill_ok" = 1 ] || fail "oracle hang: the timed-out probe process (pid $slow_pid) survived the watchdog"
# a TERM-resistant probe is KILL-escalated within the grace, never a wedge
stubborn="$odir/stubborn-shim"
printf '#!/bin/sh\ntrap "" TERM\nsleep 30\nprintf "[]"\n' >"$stubborn"
chmod +x "$stubborn"
t0=$(date +%s)
rc=0
env PLANWRIGHT_ORACLE_TIMEOUT=1 PLANWRIGHT_FLEET_STATE_DIR="$home42" \
  PLANWRIGHT_CONFIG_DEFAULTS="$core_cfg" PLANWRIGHT_ADOPTER_OVERLAY="$adopter_root" \
  PLANWRIGHT_REPO_ROOT="$repo" PLANWRIGHT_LOCAL_CONFIG="" \
  PLANWRIGHT_ORACLE_CLAUDE="$stubborn" \
  /bin/sh "$FL" oracle --cwd /wt/alpha >/dev/null 2>&1 || rc=$?
t1=$(date +%s)
[ "$rc" = 1 ] || fail "oracle TERM-resistant: exit $rc, expected 1 (unavailable)"
[ $((t1 - t0)) -lt 15 ] || fail "oracle TERM-resistant: took $((t1 - t0))s, expected KILL escalation to bound it"
# the TERM-COMPLIANT timeout path resolves promptly: the supervisor's trap
# publishes the done flag after reaping, so the parent skips the KILL grace
# ladder entirely (the broken shape burned ~timeout+4s and fired a stale
# kill -9 at a freed pid; with a 2s timeout the ladder floor is >=6s, so the
# <6s bound discriminates while leaving ~3.5s of load margin)
t0=$(date +%s)
rc=0
env PLANWRIGHT_ORACLE_TIMEOUT=2 PLANWRIGHT_FLEET_STATE_DIR="$home42" \
  PLANWRIGHT_CONFIG_DEFAULTS="$core_cfg" PLANWRIGHT_ADOPTER_OVERLAY="$adopter_root" \
  PLANWRIGHT_REPO_ROOT="$repo" PLANWRIGHT_LOCAL_CONFIG="" \
  PLANWRIGHT_ORACLE_CLAUDE="$slowshim" \
  /bin/sh "$FL" oracle --cwd /wt/alpha >/dev/null 2>&1 || rc=$?
t1=$(date +%s)
[ "$rc" = 1 ] || fail "oracle TERM-compliant timeout: exit $rc, expected 1 (unavailable)"
[ $((t1 - t0)) -lt 6 ] \
  || fail "oracle TERM-compliant timeout: took $((t1 - t0))s, expected the done-flag publish to skip the KILL grace ladder"
# a malformed / zero timeout override falls back to the default, never a
# kill-everything zero bound
printf '[\n {"pid": 100, "cwd": "/wt/alpha", "kind": "interactive", "sessionId": "aaaa-1111", "name": "a", "status": "busy"}\n]\n' >"$ofix"
out=$(env PLANWRIGHT_ORACLE_TIMEOUT=0 PLANWRIGHT_FLEET_STATE_DIR="$home42" \
  PLANWRIGHT_CONFIG_DEFAULTS="$core_cfg" PLANWRIGHT_ADOPTER_OVERLAY="$adopter_root" \
  PLANWRIGHT_REPO_ROOT="$repo" PLANWRIGHT_LOCAL_CONFIG="" \
  PLANWRIGHT_ORACLE_CLAUDE="$oshim" \
  /bin/sh "$FL" oracle --cwd /wt/alpha) || fail "timeout=0 fallback: non-zero exit"
[ "$out" = busy ] || fail "timeout=0 fallback: got '$out', expected busy (zero coerced to the default)"
out=$(env PLANWRIGHT_ORACLE_TIMEOUT=abc PLANWRIGHT_FLEET_STATE_DIR="$home42" \
  PLANWRIGHT_CONFIG_DEFAULTS="$core_cfg" PLANWRIGHT_ADOPTER_OVERLAY="$adopter_root" \
  PLANWRIGHT_REPO_ROOT="$repo" PLANWRIGHT_LOCAL_CONFIG="" \
  PLANWRIGHT_ORACLE_CLAUDE="$oshim" \
  /bin/sh "$FL" oracle --cwd /wt/alpha) || fail "timeout=abc fallback: non-zero exit"
[ "$out" = busy ] || fail "timeout=abc fallback: got '$out', expected busy (malformed coerced to the default)"
echo "ok: probe failure, hang, and unparseable output are unavailable (fallback), never an empty fleet"

# ---------------------------------------------------------------------------
# 42b. Scanner strictness and input hygiene: concatenated documents and
#      bracket-type mismatches are unavailable (never rows, never an
#      empty-fleet absent); a >256 KiB payload is unavailable; a row whose
#      fields carry raw control characters or exotic escapes is dropped whole
#      (tainted), never normalized into a key collision; a trailing-slash /
#      symlinked query key is canonicalized to the physical path.
# ---------------------------------------------------------------------------
printf '[] [ {"cwd": "/wt/alpha", "status": "idle"} ]\n' >"$ofix"
rc=0
orun "$home42" "$oshim" oracle --cwd /wt/alpha >/dev/null 2>&1 || rc=$?
[ "$rc" = 1 ] || fail "42b concat: exit $rc, expected 1 (a second document is malformed, never rows)"
printf '[ [ } ] ]\n' >"$ofix"
rc=0
orun "$home42" "$oshim" oracle --cwd /wt/alpha >/dev/null 2>&1 || rc=$?
[ "$rc" = 1 ] || fail "42b bracket-mismatch: exit $rc, expected 1 (unavailable)"
awk 'BEGIN { printf "[ {\"cwd\": \"/wt/alpha\", \"status\": \"busy\", \"name\": \""; for (i = 0; i < 270000; i++) printf "x"; print "\"} ]" }' >"$ofix"
rc=0
orun "$home42" "$oshim" oracle --cwd /wt/alpha >/dev/null 2>&1 || rc=$?
[ "$rc" = 1 ] || fail "42b cap: exit $rc, expected 1 (past the 256 KiB cap is unavailable)"
# tainted row: an escaped tab inside cwd must NOT collide with the stripped
# form — the row is dropped, the worker reads absent (safe no-evidence)
printf '[ {"cwd": "/wt/al\\tpha", "sessionId": "t-1", "status": "busy"} ]\n' >"$ofix"
rc=0
out=$(orun "$home42" "$oshim" oracle --cwd /wt/altpha) || rc=$?
[ "$rc" = 3 ] || fail "42b taint: exit $rc, expected 3 (a tainted row contributes nothing)"
[ "$out" = absent ] || fail "42b taint: got '$out', expected absent"
# canonicalization: a real directory queried with a trailing slash (and any
# symlinked prefix, e.g. macOS /tmp) matches its physical-path row
realdir="$tmp/wt-real"
mkdir -p "$realdir"
phys=$(cd "$realdir" && pwd -P)
printf '[ {"cwd": "%s", "sessionId": "r-1", "status": "busy"} ]\n' "$phys" >"$ofix"
out=$(orun "$home42" "$oshim" oracle --cwd "$realdir/") || fail "42b canon: non-zero exit"
[ "$out" = busy ] || fail "42b canon: got '$out', expected busy (physical-path join)"
echo "ok: scanner strictness — concat/mismatch/cap unavailable, tainted rows dropped, keys canonicalized"

# ---------------------------------------------------------------------------
# 43. REQ-F1.1 — classify prefers oracle evidence whenever the probe succeeds:
#     a stale-idle store row is corrected to working (the recorded false-idle
#     class), a missed Stop push is corrected to idle, a missed permission
#     push to awaiting-human.
# ---------------------------------------------------------------------------
cat >"$ofix" <<'EOF'
[
  {"pid": 100, "cwd": "/wt/alpha", "kind": "interactive", "sessionId": "aaaa-1111", "name": "a", "status": "busy"},
  {"pid": 101, "cwd": "/wt/beta", "kind": "interactive", "sessionId": "bbbb-2222", "name": "b", "status": "waiting"},
  {"pid": 102, "cwd": "/wt/gamma", "kind": "interactive", "sessionId": "cccc-3333", "name": "c", "status": "idle"}
]
EOF
home43="$tmp/h43"
# stale-idle store row + oracle busy -> working
attn "$home43" heartbeat "$w" "$s" idle >/dev/null || fail "43 setup: idle row"
out=$(orun "$home43" "$oshim" classify "$w" "$s" --now 2000000000 --oracle-cwd /wt/alpha) \
  || fail "43 stale-idle: non-zero exit"
[ "$out" = working ] || fail "43 stale-idle: got '$out', expected working (oracle busy corrects a stale idle row)"
# working store row + oracle idle -> idle (a missed Stop push corrected)
home43b="$tmp/h43b"
attn "$home43b" heartbeat "$w" "$s" working >/dev/null || fail "43b setup: working row"
out=$(orun "$home43b" "$oshim" classify "$w" "$s" --now 2000000000 --oracle-cwd /wt/gamma) \
  || fail "43b missed-stop: non-zero exit"
[ "$out" = idle ] || fail "43b missed-stop: got '$out', expected idle (oracle idle corrects a stale working row)"
# working store row + oracle waiting -> awaiting-human (a missed permission push)
home43c="$tmp/h43c"
attn "$home43c" heartbeat "$w" "$s" working >/dev/null || fail "43c setup: working row"
out=$(orun "$home43c" "$oshim" classify "$w" "$s" --now 2000000000 --oracle-cwd /wt/beta) \
  || fail "43c missed-permission: non-zero exit"
[ "$out" = awaiting-human ] \
  || fail "43c missed-permission: got '$out', expected awaiting-human (oracle waiting corrects a missed push)"
echo "ok: classify prefers oracle evidence whenever the probe succeeds"

# ---------------------------------------------------------------------------
# 44. REQ-A1.3 x REQ-F1.1 — oracle evidence never auto-resolves a queued
#     awaiting-input decision, and oracle idle never masks a hung row (the
#     StopFailure push keeps its human-attention claim).
# ---------------------------------------------------------------------------
home44="$tmp/h44"
attn "$home44" decide "$w" "$s" "stuck?" "park" "park|relaunch" high >/dev/null \
  || fail "44 setup: decide"
out=$(orun "$home44" "$oshim" classify "$w" "$s" --now 2000000000 --oracle-cwd /wt/alpha) \
  || fail "44 escalation: non-zero exit"
[ "$out" = awaiting-human ] \
  || fail "44 escalation: got '$out', expected awaiting-human (oracle busy must not auto-resolve a queued decision)"
home44b="$tmp/h44b"
attn "$home44b" heartbeat "$w" "$s" hung >/dev/null || fail "44b setup: hung row"
out=$(orun "$home44b" "$oshim" classify "$w" "$s" --now 2000000000 --oracle-cwd /wt/gamma) \
  || fail "44b hung row: non-zero exit"
[ "$out" = hung ] || fail "44b hung row: got '$out', expected hung (oracle idle must not mask a StopFailure push)"
echo "ok: oracle evidence never auto-resolves a queued decision and never masks a hung row"

# ---------------------------------------------------------------------------
# 45. REQ-F1.1 x REQ-A1.2 — oracle busy is positive evidence of life (a stale
#     heartbeat no longer classifies hung) but never masks the flailing
#     streak: busy-yet-stuck still escalates.
# ---------------------------------------------------------------------------
home45="$tmp/h45"
attn "$home45" heartbeat "$w" "$s" working >/dev/null || fail "45 setup: working row"
# control: without the oracle, the stale heartbeat classifies hung
out=$(run "$home45" classify "$w" "$s" --now 100000 --heartbeat 90000) || fail "45 control: non-zero exit"
[ "$out" = hung ] || fail "45 control: got '$out', expected hung (stale heartbeat, no oracle)"
# with oracle busy, the same stale heartbeat stays working (alive by evidence)
out=$(orun "$home45" "$oshim" classify "$w" "$s" --now 100000 --heartbeat 90000 --oracle-cwd /wt/alpha) \
  || fail "45 oracle-alive: non-zero exit"
[ "$out" = working ] || fail "45 oracle-alive: got '$out', expected working (oracle busy defeats the elapsed-time hung)"
# oracle busy never masks flailing: an unchanged progress token across the
# threshold still escalates
home45b="$tmp/h45b"
attn "$home45b" heartbeat "$w" "$s" working >/dev/null || fail "45b setup: working row"
orun "$home45b" "$oshim" classify "$w" "$s" --now 1000 --heartbeat 990 --progress sha-o --oracle-cwd /wt/alpha >/dev/null \
  || fail "45b obs 1"
orun "$home45b" "$oshim" classify "$w" "$s" --now 1060 --heartbeat 1050 --progress sha-o --oracle-cwd /wt/alpha >/dev/null \
  || fail "45b obs 2"
out=$(orun "$home45b" "$oshim" classify "$w" "$s" --now 1120 --heartbeat 1110 --progress sha-o --oracle-cwd /wt/alpha) \
  || fail "45b obs 3"
[ "$out" = flailing ] || fail "45b flailing: got '$out', expected flailing (oracle busy must not mask a stuck worker)"
# the streak survives a STALE-IDLE store row too: the observation records the
# oracle-effective state, so a missed Stop push cannot silently reset the
# streak on every observation and let oracle busy mask a stuck worker forever
home45c="$tmp/h45c"
attn "$home45c" heartbeat "$w" "$s" idle >/dev/null || fail "45c setup: idle row"
orun "$home45c" "$oshim" classify "$w" "$s" --now 2000 --heartbeat 1990 --progress sha-o --oracle-cwd /wt/alpha >/dev/null \
  || fail "45c obs 1"
orun "$home45c" "$oshim" classify "$w" "$s" --now 2060 --heartbeat 2050 --progress sha-o --oracle-cwd /wt/alpha >/dev/null \
  || fail "45c obs 2"
out=$(orun "$home45c" "$oshim" classify "$w" "$s" --now 2120 --heartbeat 2110 --progress sha-o --oracle-cwd /wt/alpha) \
  || fail "45c obs 3"
[ "$out" = flailing ] \
  || fail "45c stale-idle flailing: got '$out', expected flailing (effective-state observations keep the streak countable)"
echo "ok: oracle busy defeats elapsed-time hung but never masks the flailing streak"

# ---------------------------------------------------------------------------
# 45d. Preference edges: oracle busy corrects a hung row to working (proof of
#      life); oracle waiting outranks a hung row (a session observed blocked
#      at a prompt is the more actionable state — the deliberate asymmetry
#      with 44b's idle-never-masks-hung); oracle idle without a store row
#      yields the startup default (risk 33: never a premature idle during the
#      launch window); an unknown status value contributes no evidence.
# ---------------------------------------------------------------------------
home45d="$tmp/h45d"
attn "$home45d" heartbeat "$w" "$s" hung >/dev/null || fail "45d setup: hung row"
out=$(orun "$home45d" "$oshim" classify "$w" "$s" --now 2000000000 --oracle-cwd /wt/alpha) \
  || fail "45d busy-over-hung: non-zero exit"
[ "$out" = working ] || fail "45d busy-over-hung: got '$out', expected working (oracle busy is proof of life)"
home45e="$tmp/h45e"
attn "$home45e" heartbeat "$w" "$s" hung >/dev/null || fail "45e setup: hung row"
out=$(orun "$home45e" "$oshim" classify "$w" "$s" --now 2000000000 --oracle-cwd /wt/beta) \
  || fail "45e waiting-over-hung: non-zero exit"
[ "$out" = awaiting-human ] \
  || fail "45e waiting-over-hung: got '$out', expected awaiting-human (waiting outranks hung, unlike idle)"
home45f="$tmp/h45f"
out=$(orun "$home45f" "$oshim" classify "$w" "$s" --now 2000000000 --oracle-cwd /wt/gamma) \
  || fail "45f no-row idle: non-zero exit"
[ "$out" = working ] \
  || fail "45f no-row idle: got '$out', expected working (the startup default outranks oracle idle with no row)"
cat >"$ofix" <<'EOF'
[
  {"pid": 300, "cwd": "/wt/unk", "kind": "interactive", "sessionId": "uu-1", "name": "u", "status": "compacting"},
  {"pid": 301, "cwd": "/wt/mix", "kind": "interactive", "sessionId": "uu-2", "name": "m1", "status": "compacting"},
  {"pid": 302, "cwd": "/wt/mix", "kind": "interactive", "sessionId": "uu-3", "name": "m2", "status": "idle"}
]
EOF
rc=0
out=$(orun "$home45f" "$oshim" oracle --cwd /wt/unk) || rc=$?
[ "$rc" = 3 ] || fail "45f unknown status: exit $rc, expected 3 (no evidence, forward-compatibly)"
out=$(orun "$home45f" "$oshim" oracle --cwd /wt/mix) || fail "45f unknown+idle: non-zero exit"
[ "$out" = idle ] || fail "45f unknown+idle: got '$out', expected idle (the recognized row still counts)"
# restore the shared fixture for later sections
cat >"$ofix" <<'EOF'
[
  {"pid": 100, "cwd": "/wt/alpha", "kind": "interactive", "sessionId": "aaaa-1111", "name": "a", "status": "busy"},
  {"pid": 101, "cwd": "/wt/beta", "kind": "interactive", "sessionId": "bbbb-2222", "name": "b", "status": "waiting"},
  {"pid": 102, "cwd": "/wt/gamma", "kind": "interactive", "sessionId": "cccc-3333", "name": "c", "status": "idle"}
]
EOF
echo "ok: preference edges — busy/waiting over hung, startup default over no-row idle, unknown status inert"

# ---------------------------------------------------------------------------
# 45g. Join-key discipline on classify: the session key works end-to-end; a
#      hostile key is refused (exit 2); two join keys are refused (exit 2) on
#      both subcommands.
# ---------------------------------------------------------------------------
home45g="$tmp/h45g"
attn "$home45g" heartbeat "$w" "$s" idle >/dev/null || fail "45g setup: idle row"
out=$(orun "$home45g" "$oshim" classify "$w" "$s" --now 2000000000 --oracle-session aaaa-1111) \
  || fail "45g session key: non-zero exit"
[ "$out" = working ] || fail "45g session key: got '$out', expected working (session join corrects the stale idle)"
rc=0
orun "$home45g" "$oshim" classify "$w" "$s" --now 2000000000 --oracle-session "$(printf 'bad\nkey')" >/dev/null 2>&1 || rc=$?
[ "$rc" = 2 ] || fail "45g hostile session key: exit $rc, expected 2 (refused)"
rc=0
orun "$home45g" "$oshim" classify "$w" "$s" --now 2000000000 --oracle-cwd relative/path >/dev/null 2>&1 || rc=$?
[ "$rc" = 2 ] || fail "45g relative oracle-cwd: exit $rc, expected 2 (refused)"
rc=0
orun "$home45g" "$oshim" classify "$w" "$s" --now 2000000000 --oracle-cwd /wt/alpha --oracle-session aaaa-1111 >/dev/null 2>&1 || rc=$?
[ "$rc" = 2 ] || fail "45g two keys (classify): exit $rc, expected 2 (exactly one join key)"
rc=0
orun "$home45g" "$oshim" oracle --cwd /wt/alpha --session aaaa-1111 >/dev/null 2>&1 || rc=$?
[ "$rc" = 2 ] || fail "45g two keys (oracle): exit $rc, expected 2 (exactly one join key)"
echo "ok: classify join-key discipline — session join works, hostile and doubled keys refused"

# ---------------------------------------------------------------------------
# 46. REQ-F1.1 — the fallback path: an unavailable oracle warns and leaves the
#     store/heuristic classification unchanged; an absent worker (valid JSON,
#     no matching row) contributes no evidence — the existing logic runs and
#     absence alone never reads as death (the elapsed-time boundary and the
#     fresh-heartbeat working path are both unchanged).
# ---------------------------------------------------------------------------
home46="$tmp/h46"
attn "$home46" heartbeat "$w" "$s" idle >/dev/null || fail "46 setup: idle row"
out=$(orun "$home46" "$failshim" classify "$w" "$s" --now 2000000000 --oracle-cwd /wt/alpha 2>"$tmp/err46") \
  || fail "46 unavailable: non-zero exit"
[ "$out" = idle ] || fail "46 unavailable: got '$out', expected idle (fallback to the store row)"
grep -qi oracle "$tmp/err46" || fail "46 unavailable: no oracle warning on stderr"
# absent worker: fresh heartbeat stays working, stale heartbeat still hung
cat >"$ofix" <<'EOF'
[ {"pid": 100, "cwd": "/wt/other", "kind": "interactive", "sessionId": "zz-9", "name": "z", "status": "busy"} ]
EOF
home46b="$tmp/h46b"
attn "$home46b" heartbeat "$w" "$s" working >/dev/null || fail "46b setup: working row"
out=$(orun "$home46b" "$oshim" classify "$w" "$s" --now 1000 --heartbeat 990 --oracle-cwd /wt/nope 2>"$tmp/err46b") \
  || fail "46b absent-fresh: non-zero exit"
[ "$out" = working ] || fail "46b absent-fresh: got '$out', expected working (absence is no evidence)"
[ ! -s "$tmp/err46b" ] \
  || fail "46b absent-fresh: absence must be silent on stderr (reconcile-cadence noise), got: $(cat "$tmp/err46b")"
out=$(orun "$home46b" "$oshim" classify "$w" "$s" --now 100000 --heartbeat 90000 --oracle-cwd /wt/nope) \
  || fail "46b absent-stale: non-zero exit"
[ "$out" = hung ] || fail "46b absent-stale: got '$out', expected hung (the elapsed-time boundary is unchanged)"
# malformed OUTPUT (not just a failing probe) also falls back end-to-end: the
# test-spec's malformed-output demand exercised through classify itself
home46c="$tmp/h46c"
attn "$home46c" heartbeat "$w" "$s" idle >/dev/null || fail "46c setup: idle row"
printf 'error: something broke\n' >"$ofix"
out=$(orun "$home46c" "$oshim" classify "$w" "$s" --now 2000000000 --oracle-cwd /wt/alpha 2>"$tmp/err46c") \
  || fail "46c garbage-output: non-zero exit"
[ "$out" = idle ] || fail "46c garbage-output: got '$out', expected idle (fallback to the store row)"
grep -qi oracle "$tmp/err46c" || fail "46c garbage-output: no oracle warning on stderr"
cat >"$ofix" <<'EOF'
[ {"pid": 100, "cwd": "/wt/other", "kind": "interactive", "sessionId": "zz-9", "name": "z", "status": "busy"} ]
EOF
echo "ok: unavailable oracle falls back with a warning; absence contributes no evidence either way"

# ---------------------------------------------------------------------------
# 47. Input hygiene — a spoofed session name carrying escaped JSON text
#     (\"cwd\": ..., \"status\": ...) is data, never parsed as fields: the
#     spoofed cwd does not match, and the row's real fields still do.
# ---------------------------------------------------------------------------
cat >"$ofix" <<'EOF'
[
  {"pid": 200, "cwd": "/wt/other", "kind": "interactive", "sessionId": "ff-5", "name": "evil \"cwd\": \"/wt/target\", \"status\": \"idle\" trailing", "status": "busy"}
]
EOF
home47="$tmp/h47"
rc=0
out=$(orun "$home47" "$oshim" oracle --cwd /wt/target) || rc=$?
[ "$rc" = 3 ] || fail "47 spoof: exit $rc, expected 3 (the spoofed cwd must not match)"
[ "$out" = absent ] || fail "47 spoof: got '$out', expected absent"
out=$(orun "$home47" "$oshim" oracle --cwd /wt/other) || fail "47 real row: non-zero exit"
[ "$out" = busy ] || fail "47 real row: got '$out', expected busy (the real fields still parse)"
echo "ok: a spoofed session name is data, never honored as fields"

echo "ALL PASS: fleet-liveness.sh"
