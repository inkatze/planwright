#!/bin/bash
# Tests for scripts/fleet-tower-watchdog.sh — the external, cron-scheduled
# unattended-tower liveness check (Task 3: D-4, D-20, D-21; REQ-A1.5,
# REQ-A1.7, REQ-A1.9, REQ-G1.3, REQ-G1.4).
#
# Contract under test (one tick per invocation; the outcome word on stdout):
#   fleet-tower-watchdog.sh <spec-dir>
#   - gate first: fleet-daemon-gate.sh short-circuits the tick (`paused`);
#     resolver hard-fails (4/5) propagate as the exit code;
#   - the marker is the mode gate (risk row 7): no marker -> `no-marker`;
#     an interactive marker -> `not-unattended` (the signpost's domain, never
#     relaunched); an unparseable/ambiguous marker -> `ambiguous-marker`
#     plus an upserted decision-queue entry — NEITHER recovery path acts;
#   - death evidence via the shared D-5 predicate: `alive` (resets any
#     backoff state), `unknown` (lost observability -> refuse);
#   - ready work resolved by CALLING THROUGH to /orchestrate's own selector
#     (risk row 4): no ready work -> `no-ready-work`; a selector failure ->
#     `ready-check-error` (fail closed, no relaunch);
#   - REQ-A1.9 backoff: consecutive failed relaunches wait base*2^(n-1)
#     seconds (`backoff-wait`), and at the configured threshold the check
#     disables itself (`disabled`) with a decision-queue entry;
#   - the relaunch itself serializes under the EXISTING per-spec advisory
#     lock (D-20; busy -> `lock-busy`) and re-verifies death under the lock
#     before acting (risk rows 1 and 6) — no double-launch;
#   - a relaunch is memoryless: the launcher receives only disk/config-
#     derived inputs (spec dir + session name), lands in its OWN tmux
#     session (D-21/REQ-G1.4, `planwright-tower-<spec>`), and the marker/
#     backoff records are updated from the launch result;
#   - every action (relaunch, relaunch-failed, disable, reset-backoff) logs
#     through fleet-audit.sh (REQ-F1.4); classifications do not.
#
# Env seams (operator/test knobs, trusted verbatim like
# PLANWRIGHT_FLEET_STATE_DIR): PLANWRIGHT_TOWER_READY_CHECK,
# PLANWRIGHT_TOWER_LAUNCHER, PLANWRIGHT_TOWER_EVIDENCE_CMD.
#
# Runs standalone under /bin/bash (the bash 3.2 floor).
set -eu
LC_ALL=C
export LC_ALL
unset CDPATH

here=$(cd "$(dirname "$0")" && pwd)
FTW="$here/../scripts/fleet-tower-watchdog.sh"
FTM="$here/../scripts/fleet-tower-marker.sh"
FAU="$here/../scripts/fleet-audit.sh"
FAT="$here/../scripts/fleet-attention.sh"

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

[ -x "$FTW" ] || fail "scripts/fleet-tower-watchdog.sh missing or not executable"
[ -x "$FTM" ] || fail "scripts/fleet-tower-marker.sh missing or not executable"

tmp=$(mktemp -d)
alive_pid=""
cleanup() {
  if [ -n "$alive_pid" ]; then
    kill "$alive_pid" 2>/dev/null || true
    wait "$alive_pid" 2>/dev/null || true
  fi
  rm -rf "$tmp"
}
trap 'cleanup' EXIT

home="$tmp/fleet-home"
mkdir -p "$home"
repo="$tmp/repo"
spec_dir="$repo/specs/my-spec"
mkdir -p "$spec_dir"
bin="$tmp/bin"
mkdir -p "$bin"

# Config fixture layers: pin all four overlay layers so the host machine's
# real config can never leak into a fixture (the test-fleet-daemon-gate
# pattern).
defaults="$tmp/defaults.yml"
cat >"$defaults" <<'EOF'
fleet_daemon_pause: false
tower_relaunch_backoff_base: 60
tower_relaunch_disable_threshold: 3
EOF
fake_root="$tmp/fake-repo-root"
mkdir -p "$fake_root"

# A dead pid: spawn a short-lived child and wait for it.
/bin/sh -c 'exit 0' &
dead_pid=$!
wait "$dead_pid" 2>/dev/null || true

# An alive pid for the alive cases (killed in cleanup).
sleep 300 &
alive_pid=$!

# Stub ready checks.
printf '#!/bin/sh\necho 3\nexit 0\n' >"$bin/ready-ok"
printf '#!/bin/sh\nexit 1\n' >"$bin/ready-none"
chmod +x "$bin/ready-ok" "$bin/ready-none"

# Stub launcher: records argv (one per line) and a marker env probe, prints
# the fixed dead pid so a "relaunched tower" immediately reads as dead on the
# next tick (the crash-loop fixture).
launch_log="$tmp/launch-calls"
cat >"$bin/launcher" <<EOF
#!/bin/sh
{
  echo "call"
  for a in "\$@"; do echo "arg:\$a"; done
} >>"$launch_log"
echo $dead_pid
EOF
chmod +x "$bin/launcher"
launch_calls() {
  [ -f "$launch_log" ] || {
    echo 0
    return
  }
  grep -c '^call$' "$launch_log"
}

# Stub failing launcher.
printf '#!/bin/sh\nexit 1\n' >"$bin/launcher-fail"
chmod +x "$bin/launcher-fail"

run() {
  PLANWRIGHT_FLEET_STATE_DIR="$home" \
    PLANWRIGHT_CONFIG_DEFAULTS="$defaults" \
    PLANWRIGHT_ADOPTER_OVERLAY="$tmp/no-adopter.yml" \
    PLANWRIGHT_REPO_ROOT="$fake_root" \
    PLANWRIGHT_LOCAL_CONFIG="$tmp/no-local.yml" \
    PLANWRIGHT_TOWER_READY_CHECK="${READY_CHECK:-$bin/ready-ok}" \
    PLANWRIGHT_TOWER_LAUNCHER="${LAUNCHER:-$bin/launcher}" \
    /bin/bash "$FTW" "$@"
}

fleet_env() {
  PLANWRIGHT_FLEET_STATE_DIR="$home" /bin/bash "$@"
}

record_marker() {
  # record_marker <mode> <pid>
  fleet_env "$FTM" record my-spec --mode "$1" --pid "$2" --checkout "$repo" \
    --tmux-session planwright-tower-my-spec >/dev/null
}

backoff_file="$home/towers/my-spec.backoff"
write_backoff() {
  # write_backoff <count> <last-epoch> <disabled>
  mkdir -p "$home/towers"
  printf '%s\t%s\t%s\n' "$1" "$2" "$3" >"$backoff_file"
}
read_backoff_field() {
  cut -f"$1" "$backoff_file"
}

audit_rows() {
  fleet_env "$FAU" query --mechanism tower-watchdog 2>/dev/null || true
}

# --- usage / hostile input ----------------------------------------------------

rc=0
run >/dev/null 2>&1 || rc=$?
[ "$rc" = 2 ] || fail "no args: exit $rc, expected 2"
echo "ok: no args refused"

rc=0
run "$tmp/not-under-specs" >/dev/null 2>&1 || rc=$?
[ "$rc" = 2 ] || fail "dir outside specs/: exit $rc, expected 2"
echo "ok: a spec dir outside specs/ is refused"

# --- kill-switch gate (D-15 composition) --------------------------------------

paused_defaults="$tmp/defaults-paused.yml"
sed 's/^fleet_daemon_pause: false/fleet_daemon_pause: true/' "$defaults" >"$paused_defaults"
record_marker unattended "$dead_pid"
out=$(PLANWRIGHT_FLEET_STATE_DIR="$home" \
  PLANWRIGHT_CONFIG_DEFAULTS="$paused_defaults" \
  PLANWRIGHT_ADOPTER_OVERLAY="$tmp/no-adopter.yml" \
  PLANWRIGHT_REPO_ROOT="$fake_root" \
  PLANWRIGHT_LOCAL_CONFIG="$tmp/no-local.yml" \
  PLANWRIGHT_TOWER_READY_CHECK="$bin/ready-ok" \
  PLANWRIGHT_TOWER_LAUNCHER="$bin/launcher" \
  /bin/bash "$FTW" "$spec_dir" 2>/dev/null) || fail "paused tick exited non-zero"
[ "$out" = paused ] || fail "paused tick outcome '$out'"
[ "$(launch_calls)" = 0 ] || fail "paused tick must not launch"
echo "ok: fleet_daemon_pause short-circuits the tick"

# A malformed repo-tracked overlay is a hard-fail the watchdog propagates.
mkdir -p "$fake_root-bad/.claude"
printf 'fleet_daemon_pause: banana\n' >"$fake_root-bad/.claude/planwright.yml"
rc=0
PLANWRIGHT_FLEET_STATE_DIR="$home" \
  PLANWRIGHT_CONFIG_DEFAULTS="$defaults" \
  PLANWRIGHT_ADOPTER_OVERLAY="$tmp/no-adopter.yml" \
  PLANWRIGHT_REPO_ROOT="$fake_root-bad" \
  PLANWRIGHT_LOCAL_CONFIG="$tmp/no-local.yml" \
  /bin/bash "$FTW" "$spec_dir" >/dev/null 2>&1 || rc=$?
[ "$rc" = 4 ] || fail "malformed repo-tracked overlay: exit $rc, expected 4"
echo "ok: a repo-tracked config hard-fail propagates (exit 4)"

# --- marker mode gate (risk row 7) --------------------------------------------

fleet_env "$FTM" clear my-spec >/dev/null
out=$(run "$spec_dir" 2>/dev/null) || fail "no-marker tick exited non-zero"
[ "$out" = no-marker ] || fail "no-marker outcome '$out'"
echo "ok: no marker -> no action"

record_marker interactive "$dead_pid"
out=$(run "$spec_dir" 2>/dev/null) || fail "interactive tick exited non-zero"
[ "$out" = not-unattended ] || fail "interactive marker outcome '$out'"
[ "$(launch_calls)" = 0 ] || fail "interactive marker must never be relaunched"
echo "ok: an interactive marker is never relaunched (mode mutual exclusion)"

# Hand-corrupt the marker: an ambiguous mode must fail closed on BOTH paths
# and surface a decision-queue entry.
printf 'my-spec\tsideways\t%s\t-\t-\t%s\t123\n' "$dead_pid" "$repo" >"$home/towers/my-spec"
out=$(run "$spec_dir" 2>/dev/null) || fail "ambiguous tick exited non-zero"
[ "$out" = ambiguous-marker ] || fail "ambiguous marker outcome '$out'"
[ "$(launch_calls)" = 0 ] || fail "ambiguous marker must not relaunch"
queue=$(fleet_env "$FAT" queue 2>/dev/null) || fail "attention queue unreadable"
case "$queue" in
  *my-spec*) ;;
  *) fail "ambiguous marker left no decision-queue entry" ;;
esac
echo "ok: an ambiguous marker refuses both paths and queues a decision"

# --- death evidence (D-5 predicate) -------------------------------------------

record_marker unattended "$alive_pid"
out=$(run "$spec_dir" 2>/dev/null) || fail "alive tick exited non-zero"
[ "$out" = alive ] || fail "alive outcome '$out'"
[ "$(launch_calls)" = 0 ] || fail "an alive tower must not be relaunched"
echo "ok: an alive tower is left alone"

# Lost observability refuses to act (evidence seam prints unknown).
printf '#!/bin/sh\necho unknown\nexit 3\n' >"$bin/evidence-unknown"
chmod +x "$bin/evidence-unknown"
record_marker unattended "$dead_pid"
out=$(PLANWRIGHT_TOWER_EVIDENCE_CMD="$bin/evidence-unknown" run "$spec_dir" 2>/dev/null) \
  || fail "unknown tick exited non-zero"
[ "$out" = unknown ] || fail "unknown outcome '$out'"
[ "$(launch_calls)" = 0 ] || fail "lost observability must not relaunch"
echo "ok: lost observability refuses to act (REQ-A1.7)"

# --- ready-work call-through (risk row 4) -------------------------------------

record_marker unattended "$dead_pid"
out=$(READY_CHECK="$bin/ready-none" run "$spec_dir" 2>/dev/null) \
  || fail "no-ready-work tick exited non-zero"
[ "$out" = no-ready-work ] || fail "no-ready-work outcome '$out'"
[ "$(launch_calls)" = 0 ] || fail "no ready work must not relaunch"
echo "ok: a dead tower with no ready work is not relaunched"

# Default (no seam): the check calls through to orchestrate-select.sh, whose
# failure on this taskless fixture spec proves the live selector ran — and a
# selector failure is fail-closed, never a relaunch.
out=$(PLANWRIGHT_FLEET_STATE_DIR="$home" \
  PLANWRIGHT_CONFIG_DEFAULTS="$defaults" \
  PLANWRIGHT_ADOPTER_OVERLAY="$tmp/no-adopter.yml" \
  PLANWRIGHT_REPO_ROOT="$fake_root" \
  PLANWRIGHT_LOCAL_CONFIG="$tmp/no-local.yml" \
  PLANWRIGHT_TOWER_LAUNCHER="$bin/launcher" \
  /bin/bash "$FTW" "$spec_dir" 2>/dev/null) || fail "ready-check-error tick exited non-zero"
[ "$out" = ready-check-error ] || fail "default ready-check outcome '$out'"
[ "$(launch_calls)" = 0 ] || fail "a ready-check failure must not relaunch"
echo "ok: readiness calls through to the live selector and fails closed"

# --- the relaunch (REQ-A1.5) --------------------------------------------------

record_marker unattended "$dead_pid"
rm -f "$backoff_file"
out=$(run "$spec_dir" 2>/dev/null) || fail "relaunch tick exited non-zero"
[ "$out" = relaunched ] || fail "relaunch outcome '$out'"
[ "$(launch_calls)" = 1 ] || fail "expected exactly one launch, got $(launch_calls)"

# Memoryless: the launcher received ONLY the disk/config-derived inputs
# (the watchdog passes the canonicalized spec dir).
spec_dir_canon=$(cd "$spec_dir" && pwd -P)
args=$(grep '^arg:' "$launch_log" | sed 's/^arg://')
expected_args="$spec_dir_canon
planwright-tower-my-spec"
[ "$args" = "$expected_args" ] || fail "launcher args were '$args' — a relaunch must pass only disk-derived state"
echo "ok: a dead tower with ready work is relaunched from disk state alone"

# The marker now records the relaunched tower.
row=$(fleet_env "$FTM" read my-spec) || fail "marker missing after relaunch"
IFS=$(printf '\t') read -r _ m_mode m_pid _ m_tmux _ _ <<EOF
$row
EOF
[ "$m_mode" = unattended ] || fail "post-relaunch marker mode '$m_mode'"
[ "$m_pid" = "$dead_pid" ] || fail "post-relaunch marker pid '$m_pid' (launcher printed $dead_pid)"
[ "$m_tmux" = planwright-tower-my-spec ] || fail "post-relaunch marker tmux session '$m_tmux'"
echo "ok: the marker is re-recorded from the launch result"

# Backoff state after attempt 1.
[ "$(read_backoff_field 1)" = 1 ] || fail "backoff count after first relaunch"
[ "$(read_backoff_field 3)" = 0 ] || fail "backoff disabled flag after first relaunch"

# The relaunch was audited.
rows=$(audit_rows)
case "$rows" in
  *relaunch*) ;;
  *) fail "no audit row for the relaunch" ;;
esac
echo "ok: the relaunch is audited (REQ-F1.4)"

# --- escalating backoff and disable (REQ-A1.9) --------------------------------

now=$(date +%s)

# count=1, 10s since the attempt: the schedule demands base(60)s -> wait.
write_backoff 1 $((now - 10)) 0
out=$(run "$spec_dir" 2>/dev/null) || fail "backoff-wait tick exited non-zero"
[ "$out" = backoff-wait ] || fail "backoff-wait outcome '$out'"
[ "$(launch_calls)" = 1 ] || fail "backoff window must suppress the relaunch"
echo "ok: a relaunch inside the backoff window waits"

# count=1, 70s elapsed >= 60 -> attempt 2.
write_backoff 1 $((now - 70)) 0
out=$(run "$spec_dir" 2>/dev/null) || fail "second relaunch tick exited non-zero"
[ "$out" = relaunched ] || fail "second relaunch outcome '$out'"
[ "$(read_backoff_field 1)" = 2 ] || fail "backoff count after second relaunch"

# count=2, 70s elapsed < 120 -> the schedule ESCALATED: wait.
write_backoff 2 $((now - 70)) 0
out=$(run "$spec_dir" 2>/dev/null) || fail "escalated wait tick exited non-zero"
[ "$out" = backoff-wait ] || fail "escalated backoff outcome '$out' (delay must double)"
echo "ok: the backoff schedule escalates (60s, then 120s)"

# count=2, 130s elapsed >= 120 -> attempt 3 (the third consecutive failure).
write_backoff 2 $((now - 130)) 0
out=$(run "$spec_dir" 2>/dev/null) || fail "third relaunch tick exited non-zero"
[ "$out" = relaunched ] || fail "third relaunch outcome '$out'"
[ "$(read_backoff_field 1)" = 3 ] || fail "backoff count after third relaunch"

# count=3 = threshold -> disable: no further relaunch, a decision-queue entry,
# an audit row.
calls_before=$(launch_calls)
out=$(run "$spec_dir" 2>/dev/null) || fail "disable tick exited non-zero"
[ "$out" = disabled ] || fail "disable outcome '$out'"
[ "$(read_backoff_field 3)" = 1 ] || fail "disable must persist in the backoff record"
[ "$(launch_calls)" = "$calls_before" ] || fail "the disable tick must not relaunch"
queue=$(fleet_env "$FAT" queue 2>/dev/null) || fail "attention queue unreadable after disable"
case "$queue" in
  *my-spec*) ;;
  *) fail "disable left no decision-queue entry" ;;
esac
rows=$(audit_rows)
case "$rows" in
  *disable*) ;;
  *) fail "no audit row for the disable" ;;
esac
echo "ok: the consecutive-failure threshold disables relaunching (REQ-A1.9)"

# Disabled stays disabled on later ticks.
out=$(run "$spec_dir" 2>/dev/null) || fail "post-disable tick exited non-zero"
[ "$out" = disabled ] || fail "post-disable outcome '$out'"
[ "$(launch_calls)" = "$calls_before" ] || fail "a disabled watchdog must never relaunch"
echo "ok: a disabled watchdog stays disabled"

# A tower observed ALIVE heals the backoff record (human intervention is the
# re-enable path) — and the heal is audited.
record_marker unattended "$alive_pid"
out=$(run "$spec_dir" 2>/dev/null) || fail "alive-reset tick exited non-zero"
[ "$out" = alive ] || fail "alive-reset outcome '$out'"
[ "$(read_backoff_field 1)" = 0 ] || fail "alive tower must reset the backoff count"
[ "$(read_backoff_field 3)" = 0 ] || fail "alive tower must clear the disable flag"
rows=$(audit_rows)
case "$rows" in
  *reset-backoff*) ;;
  *) fail "no audit row for the backoff reset" ;;
esac
echo "ok: an alive tower resets backoff and re-arms the watchdog"

# --- overlapping invocations (risk rows 1 and 6; D-20, REQ-G1.3) --------------

# A held per-spec advisory lock (another tick or a live tower's state move)
# makes this tick a clean no-op — the EXISTING lock, no new primitive.
record_marker unattended "$dead_pid"
rm -f "$backoff_file"
calls_before=$(launch_calls)
mkdir "$spec_dir/.orchestrate.lock"
out=$(run "$spec_dir" 2>/dev/null) || fail "lock-busy tick exited non-zero"
rmdir "$spec_dir/.orchestrate.lock"
[ "$out" = lock-busy ] || fail "lock-busy outcome '$out'"
[ "$(launch_calls)" = "$calls_before" ] || fail "a busy lock must suppress the relaunch"
echo "ok: overlapping ticks serialize on the existing advisory lock (REQ-G1.3)"

# Death is RE-VERIFIED under the lock before acting: evidence that flips to
# alive between the first check and the locked one must abort the relaunch.
seq_file="$tmp/evidence-seq"
rm -f "$seq_file"
cat >"$bin/evidence-flip" <<EOF
#!/bin/sh
echo x >>"$seq_file"
calls=\$(grep -c x "$seq_file")
if [ "\$calls" -ge 2 ]; then
  echo alive
  exit 1
fi
echo dead
exit 0
EOF
chmod +x "$bin/evidence-flip"
calls_before=$(launch_calls)
out=$(PLANWRIGHT_TOWER_EVIDENCE_CMD="$bin/evidence-flip" run "$spec_dir" 2>/dev/null) \
  || fail "re-verify tick exited non-zero"
[ "$out" = alive ] || fail "re-verify outcome '$out' (the locked re-check must win)"
[ "$(launch_calls)" = "$calls_before" ] || fail "a re-verified-alive tower must not be relaunched"
[ "$(grep -c x "$seq_file")" = 2 ] || fail "death must be checked exactly twice (pre-lock + under-lock)"
echo "ok: death is re-verified under the lock before relaunching (risk row 1)"

# --- session-per-tower isolation via the default launcher (D-21, REQ-G1.4) ----

# A fake tmux records every invocation; a pre-existing, unrelated operator
# session exists. The default launcher must create its OWN session (-d -s
# planwright-tower-<spec>) and never a window in the unrelated session.
tmux_log="$tmp/tmux-calls"
rm -f "$tmux_log"
cat >"$bin/tmux" <<EOF
#!/bin/sh
{
  printf 'invoke'
  for a in "\$@"; do printf ' %s' "\$a"; done
  echo
} >>"$tmux_log"
case "\$1" in
  has-session)
    # Only the unrelated operator session exists.
    case "\$3" in
      =operator-main) exit 0 ;;
      *) exit 1 ;;
    esac
    ;;
  new-session) exit 0 ;;
  list-panes) echo $dead_pid; exit 0 ;;
esac
exit 0
EOF
chmod +x "$bin/tmux"

record_marker unattended "$dead_pid"
rm -f "$backoff_file"
out=$(PATH="$bin:$PATH" PLANWRIGHT_FLEET_STATE_DIR="$home" \
  PLANWRIGHT_CONFIG_DEFAULTS="$defaults" \
  PLANWRIGHT_ADOPTER_OVERLAY="$tmp/no-adopter.yml" \
  PLANWRIGHT_REPO_ROOT="$fake_root" \
  PLANWRIGHT_LOCAL_CONFIG="$tmp/no-local.yml" \
  PLANWRIGHT_TOWER_READY_CHECK="$bin/ready-ok" \
  /bin/bash "$FTW" "$spec_dir" 2>/dev/null) || fail "default-launcher tick exited non-zero"
[ "$out" = relaunched ] || fail "default-launcher outcome '$out'"
grep -q '^invoke new-session' "$tmux_log" || fail "default launcher must create a session"
grep '^invoke new-session' "$tmux_log" | grep -q -- '-s planwright-tower-my-spec' \
  || fail "the fresh tower must land in its own planwright-tower-<spec> session"
if grep -q 'new-window' "$tmux_log"; then
  fail "the launcher created a window instead of its own session (REQ-G1.4)"
fi
if grep '^invoke new-session' "$tmux_log" | grep -q 'operator-main'; then
  fail "the launcher targeted a pre-existing, unrelated session"
fi
echo "ok: a fresh tower lands in its own tmux session (REQ-G1.4)"

# A colliding session name is a launch failure, not a hijack.
cat >"$bin/tmux" <<EOF
#!/bin/sh
case "\$1" in
  has-session) exit 0 ;;
esac
exit 0
EOF
chmod +x "$bin/tmux"
record_marker unattended "$dead_pid"
rm -f "$backoff_file"
out=$(PATH="$bin:$PATH" PLANWRIGHT_FLEET_STATE_DIR="$home" \
  PLANWRIGHT_CONFIG_DEFAULTS="$defaults" \
  PLANWRIGHT_ADOPTER_OVERLAY="$tmp/no-adopter.yml" \
  PLANWRIGHT_REPO_ROOT="$fake_root" \
  PLANWRIGHT_LOCAL_CONFIG="$tmp/no-local.yml" \
  PLANWRIGHT_TOWER_READY_CHECK="$bin/ready-ok" \
  /bin/bash "$FTW" "$spec_dir" 2>/dev/null) || fail "collision tick exited non-zero"
[ "$out" = relaunch-failed ] || fail "collision outcome '$out'"
[ "$(read_backoff_field 1)" = 1 ] || fail "a failed launch must count toward the backoff"
rows=$(audit_rows)
case "$rows" in
  *relaunch-failed*) ;;
  *) fail "no audit row for the failed relaunch" ;;
esac
echo "ok: a session-name collision fails the launch safely and is audited"

echo "ALL PASS: fleet-tower-watchdog"
