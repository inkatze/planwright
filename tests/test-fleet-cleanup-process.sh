#!/bin/bash
# Tests for `scripts/fleet-cleanup.sh process` — a leaked worker process as a
# reclaimable class (REQ-B1.5, REQ-D1.2, REQ-D1.3, REQ-D1.4, REQ-D1.8,
# REQ-D1.9, REQ-F1.2, REQ-K1.1).
#
# Two halves.
#
# The GATE TABLE runs the actuator from a copy of scripts/ with the
# stuck-detector and both rungs replaced by scripted stubs, so every verdict the
# gate reads is a fixture and every close it would perform is a recorded call
# rather than a signal. It pins the refusal order and the exit/message table:
# a malformed input, the kill-switch, a print-backend unit, a live-peer owner,
# an unknown liveness verdict, a self-target, a partial close, an unrecorded
# close. The evidence matrix crosses every tower verdict the detector can
# report with every session state, and only positive evidence on both axes
# reaches a rung's `stop`.
#
# The INTEGRATION CELLS run the real detector, the real death-evidence
# predicate and the real rungs against real processes, with only the presence
# surface scripted. A worker that finished and did not exit is reaped on each
# session-grade rung; its attention row is released while a surfaced strand
# entry survives byte for byte; and on the reap and on every refusal the
# unit's fence ref, branch tip and worktree contents are exactly as they were.
#
# A source audit closes it: the `process` arm sends no signal and reads no
# process table of its own, so the fleet has one kill path, the rungs' `stop`.
#
# Runs standalone under /bin/bash (the bash 3.2 floor):
#   ./tests/test-fleet-cleanup-process.sh
set -eu
LC_ALL=C
export LC_ALL
unset CDPATH

export GIT_CONFIG_GLOBAL=/dev/null
export GIT_CONFIG_SYSTEM=/dev/null

here=$(cd "$(dirname "$0")" && pwd)
FC_REAL="$here/../scripts/fleet-cleanup.sh"

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

[ -x "$FC_REAL" ] || fail "scripts/fleet-cleanup.sh missing or not executable"
command -v jq >/dev/null 2>&1 || fail "jq is required: the stream-json launch preflight runs the auto-approve hook"

# Physical temp path: the headless state base is compared physically.
tmp=$(cd "$(mktemp -d)" && pwd -P)
cleanup() {
  for p in $(jobs -p); do
    kill -9 "$p" 2>/dev/null
  done
  cl_snap=$(ps -A -ww -o pid=,args= 2>/dev/null) || cl_snap=''
  while read -r p a; do
    case $a in
      *"$tmp"*) [ "$p" = "$$" ] || kill -9 "$p" 2>/dev/null ;;
    esac
  done <<EOF
$cl_snap
EOF
  rm -rf "$tmp"
}
trap cleanup EXIT
tab=$(printf '\t')
LF='
'

core_cfg="$tmp/core-defaults.yml"
repo_cfg="$tmp/cfg-repo"
mkdir -p "$repo_cfg/.claude"
printf 'fleet_daemon_pause: false\n' >"$core_cfg"
mlocal_cfg="$repo_cfg/.claude/planwright.local.yml"

self_id='11111111-2222-3333-4444-555555555555'
peer_id='aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee'

env_scrub=(
  -u CLAUDE_PLUGIN_DATA -u CLAUDE_PLUGIN_ROOT -u CLAUDE_DIR -u HOME
  -u PLANWRIGHT_ROOT -u PLANWRIGHT_TOWER_ID -u PLANWRIGHT_TOWER_SESSION_ID
  -u PLANWRIGHT_TOWER_PID -u PLANWRIGHT_TOWER_CHECKOUT
  -u PLANWRIGHT_STREAMJSON_PENDING_AGE -u PLANWRIGHT_STREAMJSON_ALARM_TICK
  -u PLANWRIGHT_STREAMJSON_GUARD_PREFLIGHT
  -u PLANWRIGHT_WORKER_HANDLE -u PLANWRIGHT_WORKER_SCOPE
  -u FLEET_PANE_PROMPT_ANCHORS -u FLEET_PANE_PROMPT_SIGNATURES
)

# ============================================================================
# The gate table: scripted detector, recording rungs.
# ============================================================================

gs="$tmp/gate-scripts"
mkdir -p "$gs"
cp "$here/../scripts/"*.sh "$gs/"

# The detector stub prints whatever the cell wrote to det-out and exits det-rc,
# recording each invocation's argv so a cell can assert it was never asked.
cat >"$gs/fleet-stuck-detector.sh" <<STUB
#!/bin/sh
printf '%s\n' "\$*" >>"$tmp/det-calls"
cat "$tmp/det-out"
exit "\$(cat "$tmp/det-rc")"
STUB
# Each rung stub records its argv and answers from stop-out / stop-rc, with the
# literal WORKER replaced by the handle it was handed.
for r in fleet-streamjson.sh fleet-dispatch-headless.sh; do
  cat >"$gs/$r" <<STUB
#!/bin/sh
printf '%s %s\n' "$r" "\$*" >>"$tmp/stop-calls"
[ -s "$tmp/stop-err" ] && cat "$tmp/stop-err" >&2
sed "s/WORKER/\$2/" "$tmp/stop-out"
exit "\$(cat "$tmp/stop-rc")"
STUB
done
# The kill-switch answers from a flag file here: the real resolver runs once per
# cell otherwise, which is most of this half's wall clock. The integration half
# runs the real one.
# pause-after <n> flips it to paused after its first <n> answers.
cat >"$gs/fleet-daemon-gate.sh" <<STUB
#!/bin/sh
printf 'x\n' >>"$tmp/gate-calls"
if [ -s "$tmp/pause-after" ] && [ "\$(grep -c . "$tmp/gate-calls")" -gt "\$(cat "$tmp/pause-after")" ]; then
  exit 1
fi
[ ! -e "$tmp/paused" ]
STUB
chmod +x "$gs"/*.sh

gate_home="$tmp/gate-home"
: >"$tmp/unwritable"

# det <state> <owner> <reason> <backend> <owner-evidence> [<owner-token>] —
# the detector's answer for worker `w1`, in its own output grammar.
det() {
  {
    printf 'worker\tw1\t%s\t%s\t-\t%s\n' "$1" "$2" "$3"
    printf 'evidence\tw1\tregistry\tpresent\n'
    printf 'evidence\tw1\tbackend\t%s\n' "$4"
    printf 'evidence\tw1\towner-token\t%s\n' "${6:-$peer_id}"
    printf 'evidence\tw1\towner-evidence\t%s\n' "$5"
  } >"$tmp/det-out"
  printf '0\n' >"$tmp/det-rc"
}

stop_answers() {
  printf '%s\n' "$1" >"$tmp/stop-out"
  printf '%s\n' "$2" >"$tmp/stop-rc"
  : >"$tmp/stop-err"
}

reset_calls() {
  : >"$tmp/det-calls"
  : >"$tmp/stop-calls"
  : >"$tmp/gate-calls"
}

# gate <args...> — the actuator from the stub tree. Sets rc, out, err.
gate() {
  reset_calls
  rc=0
  env "${env_scrub[@]}" \
    PLANWRIGHT_FLEET_STATE_DIR="${G_HOME:-$gate_home}" \
    PLANWRIGHT_CONFIG_DEFAULTS="$core_cfg" \
    PLANWRIGHT_REPO_ROOT="$repo_cfg" \
    PLANWRIGHT_ADOPTER_OVERLAY="$tmp/adopter" \
    PLANWRIGHT_LOCAL_CONFIG="" \
    /bin/sh "$gs/fleet-cleanup.sh" process "$@" >"$tmp/out" 2>"$tmp/err" || rc=$?
  out=$(cat "$tmp/out")
  err=$(cat "$tmp/err")
}

audit_rows() {
  env "${env_scrub[@]}" PLANWRIGHT_FLEET_STATE_DIR="$gate_home" \
    /bin/sh "$gs/fleet-audit.sh" query --mechanism process-cleanup 2>/dev/null
}

expect() {
  [ "$rc" = "$1" ] || fail "$2: exit $rc, expected $1 (stderr: $err)"
}

never_stopped() {
  [ ! -s "$tmp/stop-calls" ] || fail "$1: a rung's stop was invoked: $(cat "$tmp/stop-calls")"
}

stop_answers 'stop WORKER stopped released=process,attention' 0

# --- malformed input refuses before the detector is asked (exit 2) ----------
det finished-but-unreaped this-tower completion:result=success stream-json-persistent self "$self_id"
for bad in '' '..' 'a/b' 'w 1' '-w' 'pwfence.0123456789ab'; do
  gate "$bad" trig why
  expect 2 "malformed handle '$bad'"
  [ ! -s "$tmp/det-calls" ] || fail "malformed handle '$bad': the detector was asked"
done
case $err in
  *'strand'*) ;;
  *) fail "a handle in the strand sink's namespace was refused without naming why: $err" ;;
esac
gate w1 "$(printf 'bad\ttrig')" why
expect 2 "a trigger with a tab"
gate w1 trig why --grace 0
expect 2 "a zero grace"
gate w1 trig why --grace abc
expect 2 "a non-numeric grace"
gate w1 trig why --repo-root relative/dir
expect 2 "a relative repo root"
gate w1 trig why --tower-id 'bad id'
expect 2 "a malformed tower id"
gate w1 trig why --bogus
expect 2 "an unknown flag"
gate w1 trig
expect 2 "a missing reasoning"
echo "ok: malformed input is refused (exit 2) before any liveness verdict is read"

# --- the kill-switch pauses it before anything is read (exit 4) -------------
: >"$tmp/paused"
gate w1 trig why
expect 4 "kill-switch"
[ ! -s "$tmp/det-calls" ] || fail "kill-switch: the detector was asked while paused"
never_stopped "kill-switch"
rm -f "$tmp/paused"
# A pause set while the verdict was being read still stops the close.
det dead dead-or-unknown death-evidence stream-json-persistent dead
printf '1\n' >"$tmp/pause-after"
gate w1 trig why
expect 4 "a pause set after the verdict"
[ -s "$tmp/det-calls" ] || fail "a pause set after the verdict: the verdict was never read"
never_stopped "a pause set after the verdict"
rm -f "$tmp/pause-after"
echo "ok: the kill-switch pauses the process class (exit 4) before any read, and again just before the close"

# --- print-backend units are exempt, under any evidence (exit 8) ------------
for st in 'dead death-evidence' 'finished-but-unreaped completion:result=success' 'working runtime-running'; do
  det "${st% *}" dead-or-unknown "${st#* }" print dead
  gate w1 trig why
  expect 8 "print backend ($st)"
  never_stopped "print backend ($st)"
  case $err in
    *print*) ;;
    *) fail "print backend: the refusal does not name the exemption: $err" ;;
  esac
done
echo "ok: a print-backend unit is refused with its own exit (8) under every evidence"

# --- a live peer's worker is never touched, under any evidence (exit 7) -----
for st in 'dead death-evidence' 'finished-but-unreaped completion:result=success' \
  'unclassified completion-failed:exit=1' 'working runtime-running'; do
  for be in stream-json-persistent headless-oneshot; do
    det "${st% *}" live-peer "${st#* }" "$be" live
    gate w1 trig why
    expect 7 "live peer ($be, $st)"
    never_stopped "live peer ($be, $st)"
    case $err in
      *'live peer'*) ;;
      *) fail "live peer: the refusal does not name the peer: $err" ;;
    esac
  done
done
echo "ok: a worker owned by a live peer tower is refused with its own exit (7) under every evidence"

# --- the evidence matrix: tower verdict x session state ---------------------
# Only a positively dead owner crossed with a positively ended session reaches
# a stop; the reaping cells are listed literally rather than recomputed the way
# the script decides them. Every other cell is refused with exit 5, this
# tower's own worker included: the tower closes those with the rung's stop.
reaping='dead:dead-or-unknown|dead:death-evidence
dead:dead-or-unknown|finished-but-unreaped:completion:result=success
dead:dead-or-unknown|finished-but-unreaped:session-ended
dead:dead-or-unknown|unclassified:completion-failed:exit=1
dead:dead-or-unknown|unclassified:completion-unlanded'
sessions='dead:death-evidence
finished-but-unreaped:completion:result=success
finished-but-unreaped:session-ended
unclassified:completion-failed:exit=1
unclassified:completion-failed:exit=unknown
unclassified:completion-failed:result=unknown
unclassified:completion-unlanded
working:runtime-running
working:attention-working
waiting-on-a-human:hook-push
waiting-on-a-human:journal-pending
unclassified:no-signal
unclassified:turn-ended
unclassified:stop-failure
unclassified:fork-answered'
towers='self:this-tower
dead:dead-or-unknown
unknown:dead-or-unknown
ambiguous:dead-or-unknown
no-record:dead-or-unknown
unreadable:dead-or-unknown
presence-unavailable:dead-or-unknown
unrecognized:dead-or-unknown
no-identity:dead-or-unknown
absent:dead-or-unknown
self:dead-or-unknown
dead:this-tower'
cells=0
reaps=0
while IFS= read -r tw; do
  oe=${tw%%:*}
  ow=${tw#*:}
  while IFS= read -r ss; do
    st=${ss%%:*}
    rs=${ss#*:}
    det "$st" "$ow" "$rs" stream-json-persistent "$oe"
    gate w1 trig why
    cells=$((cells + 1))
    want=5
    case "$LF$reaping$LF" in
      *"$LF$tw|$ss$LF"*) want=0 ;;
    esac
    expect "$want" "evidence cell tower=$oe/$ow session=$st/$rs"
    if [ "$want" = 0 ]; then
      reaps=$((reaps + 1))
      [ "$(cat "$tmp/stop-calls")" = "fleet-streamjson.sh stop w1" ] \
        || fail "evidence cell $oe/$ow x $st/$rs: reaped through '$(cat "$tmp/stop-calls")'"
    else
      never_stopped "evidence cell $oe/$ow x $st/$rs"
      case $oe/$ow/$err in
        self/this-tower/*"this tower's own worker"*) ;;
        self/this-tower/*) fail "evidence cell $oe/$ow x $st/$rs: this tower's own worker was not named: $err" ;;
        */*/*'no positive evidence'*) ;;
        *) fail "evidence cell $oe/$ow x $st/$rs: the refusal does not say what was missing: $err" ;;
      esac
    fi
  done <<EOF
$sessions
EOF
done <<EOF
$towers
EOF
[ "$cells" = 180 ] || fail "the evidence matrix ran $cells cells, expected 180"
[ "$reaps" = 5 ] || fail "the evidence matrix reaped $reaps cells, expected 5"
det finished-but-unreaped this-tower completion:result=success stream-json-persistent self "$self_id"
gate w1 trig why --tower-id "$self_id"
expect 5 "this tower's own worker"
case $err in
  *"this tower's own worker"*stop*) ;;
  *) fail "this tower's own worker: the refusal does not point at the rung's stop: $err" ;;
esac
echo "ok: the evidence matrix ($cells cells) reaps only a dead owner's worker whose session ended; this tower's own is refused"

# --- a detector that errors, or answers nothing usable, refuses (exit 5) ----
det finished-but-unreaped this-tower completion:result=success stream-json-persistent self
printf '2\n' >"$tmp/det-rc"
gate w1 trig why
expect 5 "an errored detector"
never_stopped "an errored detector"
: >"$tmp/det-out"
printf '0\n' >"$tmp/det-rc"
gate w1 trig why
expect 5 "an empty detector answer"
never_stopped "an empty detector answer"
det finished-but-unreaped this-tower completion:result=success stream-json-persistent self
sed "s/${tab}registry${tab}present/${tab}registry${tab}absent/" "$tmp/det-out" >"$tmp/det-out.x"
mv "$tmp/det-out.x" "$tmp/det-out"
gate w1 trig why
expect 5 "no dispatch record"
never_stopped "no dispatch record"
case $err in
  *'dispatch record'*) ;;
  *) fail "no dispatch record: the refusal does not name the missing record: $err" ;;
esac
echo "ok: an errored, empty, or recordless liveness verdict refuses (exit 5)"

# --- a backend with no process close refuses (exit 5) -----------------------
for be in tmux subagent - claude-p; do
  det dead dead-or-unknown death-evidence "$be" dead
  gate w1 trig why
  expect 5 "backend $be"
  never_stopped "backend $be"
done
echo "ok: a backend with no process close is refused (exit 5), never guessed at"

# --- delegation: each backend reaches its own rung, with its own arguments --
det finished-but-unreaped dead-or-unknown completion:result=success stream-json-persistent dead
gate w1 trig why --grace 7 --repo-root /some/repo --tower-id "$self_id"
expect 0 "stream-json delegation"
[ "$(cat "$tmp/stop-calls")" = "fleet-streamjson.sh stop w1 --grace 7" ] \
  || fail "stream-json delegation: the rung was asked '$(cat "$tmp/stop-calls")'"
grep -q -- "--tower-id $self_id" "$tmp/det-calls" || fail "the tower identity did not reach the detector: $(cat "$tmp/det-calls")"
det finished-but-unreaped dead-or-unknown completion:result=success headless-oneshot dead
gate w1 trig why --grace 7 --repo-root /some/repo
expect 0 "headless delegation"
[ "$(cat "$tmp/stop-calls")" = "fleet-dispatch-headless.sh stop w1 --repo-root /some/repo --grace 7" ] \
  || fail "headless delegation: the rung was asked '$(cat "$tmp/stop-calls")'"
gate w1 trig why
[ "$(cat "$tmp/stop-calls")" = "fleet-dispatch-headless.sh stop w1" ] \
  || fail "headless delegation without flags: the rung was asked '$(cat "$tmp/stop-calls")'"
[ "$out" = 'stop w1 stopped released=process,attention' ] || fail "the rung's result line was not passed through: '$out'"
echo "ok: each session-grade backend is closed by its own rung's stop, with the caller's grace and repo root"

# --- the audit record names worker, owner, evidence, and what was released --
rm -rf "$gate_home"
det dead dead-or-unknown death-evidence stream-json-persistent dead "$peer_id"
gate w1 'periodic sweep' 'owner gone'
expect 0 "a reap"
rows=$(audit_rows)
[ "$(printf '%s\n' "$rows" | grep -c .)" = 1 ] || fail "a reap wrote $(printf '%s\n' "$rows" | grep -c .) audit rows, expected 1"
for want in "${tab}process-cleanup${tab}cleanup${tab}periodic sweep${tab}" "worker=w1" "owner=$peer_id" \
  "evidence=tower:dead,session:dead/death-evidence" "released=process,attention" "owner gone"; do
  case $rows in
    *"$want"*) ;;
    *) fail "the reap's audit row lacks '$want': $rows" ;;
  esac
done
echo "ok: a reap writes one audit record naming worker, owner, evidence class, and released set"

# --- an already-closed worker is a clean no-op, not an action --------------
rm -rf "$gate_home"
stop_answers 'stop WORKER already-closed' 0
gate w1 trig why
expect 0 "already-closed"
[ -z "$(audit_rows)" ] || fail "already-closed wrote an audit row: $(audit_rows)"
echo "ok: an already-closed worker is a clean no-op with no audit row"

# --- a partial close is exit 5, and recorded whatever it released ----------
# The rung signals the tree before it can find a class still held, so even a
# close that released nothing may have killed something: every partial and
# every rung that died mid-close leaves a record.
stop_answers 'stop WORKER partial released=process held=attention' 6
gate w1 trig why
expect 5 "a partial close"
case $err in
  *attention*) ;;
  *) fail "a partial close does not name what is still held: $err" ;;
esac
case $(audit_rows) in
  *"${tab}cleanup-partial${tab}"*"released=process held=attention"*) ;;
  *) fail "a partial close wrote no partial record naming both sets: $(audit_rows)" ;;
esac
rm -rf "$gate_home"
stop_answers 'stop WORKER partial released=- held=process' 6
gate w1 trig why
expect 5 "a partial close that released nothing"
case $(audit_rows) in
  *"${tab}cleanup-partial${tab}"*"released=- held=process"*) ;;
  *) fail "a partial close that released nothing went unrecorded: $(audit_rows)" ;;
esac
rm -rf "$gate_home"
stop_answers '' 137
gate w1 trig why
expect 5 "a rung killed mid-close"
case $(audit_rows) in
  *"${tab}cleanup-partial${tab}"*"released=unreported held=unreported"*) ;;
  *) fail "a rung that died mid-close went unrecorded: $(audit_rows)" ;;
esac
stop_answers 'stop WORKER partial released=- held=process' 6
G_HOME="$tmp/unwritable/fleet" gate w1 trig why
expect 6 "an unrecorded partial close"
echo "ok: a partial close is exit 5 and recorded with both sets, even one that released nothing; unrecorded, it is exit 6"

# --- the self-target guard: the rung refuses, the actuator says so (exit 3) -
# The rung's own words are left out, so the message checked is this script's.
rm -rf "$gate_home"
stop_answers '' 3
gate w1 trig why
expect 3 "self-target"
case $err in
  *'REFUSING self-target'*"own process tree"*) ;;
  *) fail "self-target: the refusal does not name the caller's own tree: $err" ;;
esac
case $(audit_rows) in
  *"${tab}refuse-self${tab}"*"worker=w1 "*) ;;
  *) fail "self-target: the self-block was not audited against its worker: $(audit_rows)" ;;
esac
echo "ok: a close from inside the worker's own tree is refused (exit 3) and the self-block audited against the worker"

# --- a stop that refused before acting is not a reap (exit 5) --------------
rm -rf "$gate_home"
stop_answers '' 2
gate w1 trig why
expect 5 "a stop that refused its input"
stop_answers '' 1
gate w1 trig why
expect 5 "a stop that failed"
[ -z "$(audit_rows)" ] || fail "a stop that refused before acting was recorded: $(audit_rows)"
echo "ok: a rung stop that refuses or fails before acting is reported as not reclaimed (exit 5)"

# --- a close that happened but could not be recorded (exit 6) ---------------
stop_answers 'stop WORKER stopped released=process' 0
G_HOME="$tmp/unwritable/fleet" gate w1 trig why
expect 6 "an unrecorded reap"
[ -s "$tmp/stop-calls" ] || fail "an unrecorded reap: the stop never ran"
case $err in
  *'FAILED to record'*) ;;
  *) fail "an unrecorded reap does not say so: $err" ;;
esac
echo "ok: a reap whose audit write fails returns exit 6, never a silent success"

# --- every refusal is distinct: exit code and message -----------------------
# REQ-K1.1: an operator reading the stderr of each path can tell them apart.
msgs=$(
  stop_answers 'stop WORKER stopped released=process' 0
  det dead dead-or-unknown death-evidence print dead
  gate w1 trig why
  printf '%s|%s\n' "$rc" "$err"
  det dead live-peer death-evidence stream-json-persistent live
  gate w1 trig why
  printf '%s|%s\n' "$rc" "$err"
  det working dead-or-unknown runtime-running stream-json-persistent unknown
  gate w1 trig why
  printf '%s|%s\n' "$rc" "$err"
  det dead dead-or-unknown death-evidence stream-json-persistent dead
  stop_answers '' 3
  gate w1 trig why
  printf '%s|%s\n' "$rc" "$err"
)
[ "$(printf '%s\n' "$msgs" | cut -d'|' -f1 | sort -u | grep -c .)" = 4 ] \
  || fail "the four refusals do not carry four distinct exits: $msgs"
[ "$(printf '%s\n' "$msgs" | cut -d'|' -f2- | sort -u | grep -c .)" = 4 ] \
  || fail "the four refusals do not carry four distinct messages: $msgs"
echo "ok: print, live-peer, unknown-evidence and self-target refusals each carry their own exit and message"

# --- source audit: one kill path --------------------------------------------
# The process arm names a rung's stop and nothing that signals or scans on its
# own: no kill, no process-table read, no sourcing of the close library.
arm=$(awk '/^  process\)$/ { on = 1 } on { print } on && /^    ;;$/ { exit }' "$FC_REAL")
[ -n "$arm" ] || fail "source audit: no process arm found in fleet-cleanup.sh"
code=$(printf '%s\n' "$arm" | sed 's/#.*//')
for bad in 'kill ' 'kill	' 'pkill' 'killall' 'ps -' 'fleet-stop-lib' 'release_processes' 'stop_candidates' '/proc/'; do
  case $code in
    *"$bad"*) fail "source audit: the process arm carries '$bad', a second kill path" ;;
  esac
done
for want in 'fleet-streamjson.sh' 'fleet-dispatch-headless.sh'; do
  grep -q "$want" "$FC_REAL" || fail "source audit: fleet-cleanup.sh never names $want"
done
case $code in
  *'" stop "'*) ;;
  *) fail "source audit: the process arm does not invoke a rung's stop" ;;
esac
echo "ok: source audit — the process arm terminates only through the rungs' stop"

# ============================================================================
# Integration: real detector, real death evidence, real rungs.
# ============================================================================

it="$tmp/int"
mkdir -p "$it"
cp -R "$here/../scripts" "$here/../config" "$here/../hooks" "$it/"
IS="$it/scripts"
# Presence is the one scripted surface: it answers the owning tower's liveness
# from a fixture file, so a dead or live owner needs no second tower.
cat >"$IS/fleet-presence.sh" <<STUB
#!/bin/sh
case "\$1" in
  liveness) cat "$tmp/presence-answer"; exit 0 ;;
esac
exit 3
STUB
chmod +x "$IS/fleet-presence.sh"

mkdir -p "$tmp/bin"
cat >"$tmp/bin/claude" <<'SHIM'
#!/bin/sh
# CLI shim: read the opening stdin line, emit SHIM_EVENTS, then hold open the
# way a worker that finished its turn and never exited does, until the
# fixture tree it is told to watch is gone.
IFS= read -r line || :
[ -n "${SHIM_EVENTS:-}" ] && cat "$SHIM_EVENTS"
while [ -d "$SHIM_HOLD" ]; do
  sleep 1
done
exit 0
SHIM
chmod +x "$tmp/bin/claude"

sid='99999999-2222-3333-4444-555555555555'
ev_done="$tmp/ev-done"
printf '%s\n%s\n' \
  '{"type":"system","subtype":"init","cwd":"/x","session_id":"'$sid'","tools":[]}' \
  '{"type":"result","subtype":"success","result":"done","session_id":"'$sid'"}' >"$ev_done"
printf 'do the thing\n' >"$tmp/prompt"

ihome="$tmp/int-home"
mkdir -p "$ihome"

# ienv [VAR=val...] -- <script> <args...> — a script from the integration tree,
# hermetic against the host's fleet home and configuration.
ienv() {
  ie_pre=()
  while [ $# -gt 0 ] && [ "$1" != "--" ]; do
    ie_pre+=("$1")
    shift
  done
  shift
  ie_s=$1
  shift
  env "${env_scrub[@]}" \
    PLANWRIGHT_FLEET_STATE_DIR="$ihome" \
    PLANWRIGHT_HEADLESS_STATE_DIR="$ihome/headless" \
    PLANWRIGHT_STREAMJSON_CLI="$tmp/bin/claude" \
    PLANWRIGHT_HEADLESS_CLAUDE="$tmp/bin/claude" \
    PLANWRIGHT_CONFIG_DEFAULTS="$core_cfg" \
    PLANWRIGHT_REPO_ROOT="$repo_cfg" \
    PLANWRIGHT_ADOPTER_OVERLAY="$tmp/adopter" \
    PLANWRIGHT_LOCAL_CONFIG="" \
    SHIM_HOLD="$tmp" \
    ${ie_pre[@]+"${ie_pre[@]}"} /bin/sh "$IS/$ie_s" "$@"
}

# icleanup <worker> [flags...] — the real actuator. Sets rc, out, err.
icleanup() {
  ic_w=$1
  shift
  rc=0
  ienv -- fleet-cleanup.sh process "$ic_w" 'periodic sweep' 'finished, never exited' \
    --tower-id "$self_id" --grace 1 "$@" >"$tmp/out" 2>"$tmp/err" || rc=$?
  out=$(cat "$tmp/out")
  err=$(cat "$tmp/err")
}

# wait_until <secs> <cmd...> — bounded by wall clock: each poll can run the
# whole detector, so a tick count would stretch with the host's load.
wait_until() {
  wu_end=$((SECONDS + $1))
  shift
  while [ "$SECONDS" -lt "$wu_end" ]; do
    "$@" >/dev/null 2>&1 && return 0
    sleep 0.1
  done
  "$@" >/dev/null 2>&1
}

classified() {
  ienv -- fleet-stuck-detector.sh classify "$1" --tower-id "$self_id" \
    | awk -F'\t' -v s="$2" '$1 == "worker" && $3 == s { f = 1 } END { exit f ? 0 : 1 }'
}

gone() {
  ! kill -0 "$1" 2>/dev/null && ! ps -p "$1" >/dev/null 2>&1
}

alive() {
  kill -0 "$1" 2>/dev/null
}

# The unit the workers run against: a fence ref on origin, a task branch with
# a commit of its own, and a worktree carrying uncommitted work.
git_env() {
  GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t \
    GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t "$@"
}
origin="$tmp/origin.git"
main_repo="$tmp/main"
wt="$tmp/wt"
git_env git init -q --bare "$origin"
git_env git init -q -b main "$main_repo"
(
  cd "$main_repo"
  echo seed >f
  git_env git add f
  git_env git commit -qm seed
  git_env git remote add origin "$origin"
  git_env git push -q origin main
  git_env git push -q origin HEAD:refs/planwright-fence/demo/4
  git_env git worktree add -q -b planwright/demo/task-4 "$wt"
)
(
  cd "$wt"
  echo work >g
  git_env git add g
  git_env git commit -qm work
  echo 'uncommitted, in flight' >h
)

untouched_ref=$(git -C "$origin" rev-parse refs/planwright-fence/demo/4)
untouched_tip=$(git -C "$wt" rev-parse HEAD)
untouched_status=$(git -C "$wt" status --porcelain)
untouched_h=$(cat "$wt/h")
untouched_list=$(git -C "$main_repo" worktree list --porcelain)

# untouched <what> — REQ-D1.3: the fence, the branch, and the worktree are
# exactly as the fixture left them.
untouched() {
  [ "$(git -C "$origin" rev-parse refs/planwright-fence/demo/4 2>/dev/null)" = "$untouched_ref" ] \
    || fail "$1: the unit's fence ref changed"
  [ "$(git -C "$wt" rev-parse HEAD)" = "$untouched_tip" ] || fail "$1: the branch tip moved"
  [ "$(git -C "$wt" status --porcelain)" = "$untouched_status" ] || fail "$1: the worktree status changed"
  [ "$(cat "$wt/h" 2>/dev/null)" = "$untouched_h" ] || fail "$1: the uncommitted work changed"
  [ "$(git -C "$main_repo" worktree list --porcelain)" = "$untouched_list" ] || fail "$1: the worktree list changed"
}

sj_launch() {
  ienv PLANWRIGHT_TOWER_ID="$2" SHIM_EVENTS="$ev_done" -- \
    fleet-streamjson.sh launch "$1" demo:4 --prompt-file "$tmp/prompt" --cwd "$wt" >/dev/null \
    || fail "stream-json launch of $1 failed"
  wait_until 30 classified "$1" finished-but-unreaped \
    || fail "$1 never classified finished-but-unreaped"
}

attn() {
  ienv -- fleet-attention.sh "$@" >/dev/null || fail "fleet-attention.sh $1 failed"
}

store="$ihome/attention/state"
# The strand is keyed the way the fence sweep keys it (fleet-fence.sh
# key_digest over the fence ref and the owner), so a close that derived the
# unit's strand key and cleared it would be caught here.
strand_handle="pwfence.$(printf '%s' "refs/planwright-fence/demo/4|$peer_id" \
  | git -C "$main_repo" hash-object --stdin | cut -c1-12)"
attn fork "$strand_handle" demo:4 \
  'planwright strand: unit demo:4 is fenced by tower (dead) and not terminal. Choose: reclaim, investigate, or dismiss.' \
  investigate 'reclaim|investigate|dismiss' "$strand_handle" high
strand_row=$(grep "^$strand_handle$tab" "$store")
[ -n "$strand_row" ] || fail "fixture: the strand entry was not written"

strand_intact() {
  [ "$(grep "^$strand_handle$tab" "$store")" = "$strand_row" ] \
    || fail "$1: the strand entry was cleared or modified"
}

has_row() {
  grep -q "^$1$tab" "$store"
}

reaps_recorded() {
  ienv -- fleet-audit.sh query --mechanism process-cleanup 2>/dev/null \
    | awk -F'\t' '$4 == "cleanup" || $4 == "cleanup-partial"' | grep -c . || :
}

# refused <what> <rc> <sup> <wrk> — REQ-D1.3 on a refusal: the exit, both
# processes still running, no reap recorded, the unit and the strand untouched.
refused() {
  [ "$rc" = "$2" ] || fail "$1: exit $rc, expected $2 ($err)"
  alive "$3" || fail "$1: the supervisor was terminated"
  alive "$4" || fail "$1: the worker was terminated"
  [ "$(reaps_recorded)" = "$reaps_before" ] || fail "$1: a reap was recorded"
  untouched "$1"
  strand_intact "$1"
}

# --- stream-json, a dead owner's finished worker ----------------------------
printf 'tower\t%s\tdead\n' "$peer_id" >"$tmp/presence-answer"
sj_launch sjw1 "$peer_id"
attn heartbeat sjw1 demo:4 ended
has_row sjw1 || fail "fixture: sjw1 has no attention row to release"
sup=$(cat "$ihome/streamjson/sjw1/supervisor.pid")
wrk=$(cat "$ihome/streamjson/sjw1/worker.pid")
icleanup sjw1
[ "$rc" = 0 ] || fail "stream-json reap: exit $rc ($err)"
case $out in
  'stop sjw1 stopped released='*process*attention*) ;;
  *) fail "stream-json reap: unexpected result '$out'" ;;
esac
gone "$sup" || fail "stream-json reap: the supervisor survived"
gone "$wrk" || fail "stream-json reap: the worker survived"
[ -f "$store" ] || fail "stream-json reap: the attention store is gone"
! has_row sjw1 || fail "stream-json reap: the worker's attention row was not released"
strand_intact "stream-json reap"
untouched "stream-json reap"
case $(ienv -- fleet-audit.sh query --mechanism process-cleanup) in
  *"worker=sjw1 owner=$peer_id evidence=tower:dead,session:finished-but-unreaped/"*"released=process"*) ;;
  *) fail "stream-json reap: no matching audit record" ;;
esac
echo "ok: stream-json — a dead owner's finished, unexited worker is reaped and audited; its strand survives; fence, branch and worktree untouched"

# --- refusals leave the worker running and the unit untouched ---------------
reaps_before=$(reaps_recorded)
printf 'tower\t%s\tlive\n' "$peer_id" >"$tmp/presence-answer"
sj_launch sjw2 "$self_id"
sup=$(cat "$ihome/streamjson/sjw2/supervisor.pid")
wrk=$(cat "$ihome/streamjson/sjw2/worker.pid")
icleanup sjw2
refused "this tower's own worker" 5 "$sup" "$wrk"
sj_launch sjw3 "$peer_id"
sup=$(cat "$ihome/streamjson/sjw3/supervisor.pid")
wrk=$(cat "$ihome/streamjson/sjw3/worker.pid")
icleanup sjw3
refused "live-peer refusal" 7 "$sup" "$wrk"
printf 'tower\t%s\tunknown\n' "$peer_id" >"$tmp/presence-answer"
icleanup sjw3
refused "unknown-owner refusal" 5 "$sup" "$wrk"
printf 'tower\t%s\tdead\n' "$peer_id" >"$tmp/presence-answer"
printf 'fleet_daemon_pause: true\n' >"$mlocal_cfg"
icleanup sjw3
refused "kill-switch refusal" 4 "$sup" "$wrk"
rm -f "$mlocal_cfg"
ienv -- fleet-state.sh register wprint demo:6 --backend print --death-handle none \
  || fail "fixture: the print record was not written"
icleanup wprint
[ "$rc" = 8 ] || fail "print refusal: exit $rc ($err)"
untouched "print refusal"
strand_intact "print refusal"
echo "ok: own-worker, live-peer, unknown-owner, kill-switch and print refusals terminate nothing, record no reap, and touch no fence, branch, worktree or strand"

# --- headless, a dead owner's worker whose session ended --------------------
hw=headless-demo-task-4
ienv PLANWRIGHT_TOWER_ID="$peer_id" -- \
  fleet-dispatch-headless.sh launch demo 4 --worktree "$wt" <"$tmp/prompt" >/dev/null \
  || fail "headless launch failed"
hdir="$ihome/headless/4"
wait_until 30 test -s "$hdir/pid" || fail "the headless runner never recorded its pid"
runner=$(cat "$hdir/pid")
attn heartbeat "$hw" demo:4 ended
has_row "$hw" || fail "fixture: $hw has no attention row to release"
wait_until 30 classified "$hw" finished-but-unreaped || fail "$hw never classified finished-but-unreaped"
icleanup "$hw"
[ "$rc" = 0 ] || fail "headless reap: exit $rc ($err)"
case $out in
  "stop $hw stopped released="*process*) ;;
  *) fail "headless reap: unexpected result '$out'" ;;
esac
gone "$runner" || fail "headless reap: the runner survived"
! has_row "$hw" || fail "headless reap: the worker's attention row was not released"
strand_intact "headless reap"
untouched "headless reap"
echo "ok: headless — a dead owner's worker whose session ended is reaped through the headless rung's stop; strand, fence, branch and worktree untouched"
