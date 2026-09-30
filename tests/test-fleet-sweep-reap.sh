#!/bin/bash
# Tests for the periodic sweep's schedule, its process-reap pass, and its
# worktree scan (REQ-F1.1, REQ-F1.2, REQ-F1.3, REQ-F1.4, REQ-F1.6, REQ-B1.6,
# REQ-E1.3, REQ-K1.6).
#
# The sweep runs from a copy of scripts/ with only the presence surface
# scripted, so the detector, the death-evidence predicate, the reap actuator
# and the stream-json rung are all the real ones, acting on processes this
# file spawns under its own temp dir. The owning tower's liveness is the one
# fixture: a per-token answer file the scripted presence surface reads.
#
# Covered: a cycle fires with nothing to reap and says so, and the watch loop
# fires on its interval with no threshold gating it; the default mode observes
# a dead owner's leaked worker, records the would-have close, and kills
# nothing; a repo-tracked `terminate` is not honored; the machine-local knob is
# what makes the sweep kill, with a termination record distinct from the
# would-have record; flipping the knob back stops the killing without a
# release; a sweep that declines every candidate reports each refusal and its
# reason, distinct from a sweep that found nothing; the kill-switch pauses the
# cycle; the worktree scan picks up a worktree no hook recorded.
#
# Runs standalone under /bin/bash (the bash 3.2 floor):
#   ./tests/test-fleet-sweep-reap.sh
set -eu
LC_ALL=C
export LC_ALL
unset CDPATH

export GIT_CONFIG_GLOBAL=/dev/null
export GIT_CONFIG_SYSTEM=/dev/null
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY

here=$(cd "$(dirname "$0")" && pwd)

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

[ -x "$here/../scripts/fleet-sweep.sh" ] || fail "scripts/fleet-sweep.sh missing or not executable"
command -v jq >/dev/null 2>&1 || fail "jq is required: the stream-json launch preflight runs the auto-approve hook"

tmp=$(cd "$(mktemp -d)" && pwd -P)
cleanup() {
  set +e
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

self_id='11111111-2222-3333-4444-555555555555'
peer_id='aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee'
live_id='bbbbbbbb-bbbb-cccc-dddd-eeeeeeeeeeee'
unk_id='cccccccc-bbbb-cccc-dddd-eeeeeeeeeeee'

core_cfg="$tmp/core-defaults.yml"
cp "$here/../config/defaults.yml" "$core_cfg"
repo_cfg="$tmp/cfg-repo"
mkdir -p "$repo_cfg/.claude"
tracked_cfg="$repo_cfg/.claude/planwright.yml"
mlocal_cfg="$repo_cfg/.claude/planwright.local.yml"

env_scrub=(
  -u CLAUDE_PLUGIN_DATA -u CLAUDE_PLUGIN_ROOT -u CLAUDE_DIR -u HOME
  -u PLANWRIGHT_ROOT -u PLANWRIGHT_TOWER_ID -u PLANWRIGHT_TOWER_SESSION_ID
  -u PLANWRIGHT_TOWER_PID -u PLANWRIGHT_TOWER_CHECKOUT
  -u PLANWRIGHT_STREAMJSON_PENDING_AGE -u PLANWRIGHT_STREAMJSON_ALARM_TICK
  -u PLANWRIGHT_STREAMJSON_GUARD_PREFLIGHT
  -u PLANWRIGHT_WORKER_HANDLE -u PLANWRIGHT_WORKER_SCOPE
  -u FLEET_PANE_PROMPT_ANCHORS -u FLEET_PANE_PROMPT_SIGNATURES
  -u PLANWRIGHT_FLEET_LOCK_HELD -u PLANWRIGHT_ORCH_STATE_DIR -u PLANWRIGHT_JQ
  -u PLANWRIGHT_ATTENTION_SURFACE_PROVIDED -u PLANWRIGHT_SKILLS_ROOT
  -u PLANWRIGHT_HEADLESS_STATE_DIR
  -u TMUX -u TMUX_PANE
)

it="$tmp/int"
mkdir -p "$it"
cp -R "$here/../scripts" "$here/../config" "$here/../hooks" "$it/"
IS="$it/scripts"
answers="$tmp/presence-answers"
: >"$answers"
# The owning tower's liveness, per token, from the answer file; a token the
# file does not name has no record.
cat >"$IS/fleet-presence.sh" <<STUB
#!/bin/sh
case "\$1" in
  liveness)
    for a; do t=\$a; done
    w=\$(awk -v t="\$t" '\$1 == t { print \$2; exit }' "$answers")
    if [ -n "\$w" ]; then
      printf 'tower\t%s\t%s\n' "\$t" "\$w"
    else
      printf 'no-record\t%s\n' "\$t"
    fi
    exit 0
    ;;
esac
exit 3
STUB
chmod +x "$IS/fleet-presence.sh"

answer() {
  printf '%s %s\n' "$1" "$2" >>"$answers"
}
set_answer() {
  awk -v t="$1" '$1 != t' "$answers" >"$answers.x"
  mv "$answers.x" "$answers"
  answer "$1" "$2"
}

mkdir -p "$tmp/bin"
cat >"$tmp/bin/claude" <<'SHIM'
#!/bin/sh
# CLI shim: read the opening stdin line, emit SHIM_EVENTS, then hold open the
# way a worker that finished its turn and never exited does.
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

git_env() {
  GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t \
    GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t "$@"
}
repo="$tmp/repo"
git_env git init -q -b main "$repo"
(cd "$repo" && echo seed >f && git_env git add f && git_env git commit -qm seed)
git_env git init -q --bare "$tmp/repo.git"
(cd "$repo" && git_env git remote add origin "$tmp/repo.git" && git_env git push -q -u origin main)

home="$tmp/home"
mkdir -p "$home"

# ienv [VAR=val...] -- <script> <args...> — a script from the integration
# tree, hermetic against the host's fleet home and configuration. With
# IENV_EXEC set it replaces the calling shell, which is how a backgrounded
# `( IENV_EXEC=1 ienv ... ) &` makes $! the script itself rather than a
# wrapper that a signal would kill first.
ienv() {
  ie_pre=()
  while [ $# -gt 0 ] && [ "$1" != "--" ]; do
    ie_pre+=("$1")
    shift
  done
  shift
  ie_s=$1
  shift
  ie_cmd=(env "${env_scrub[@]}"
    PLANWRIGHT_FLEET_STATE_DIR="${IHOME:-$home}"
    PLANWRIGHT_STREAMJSON_CLI="$tmp/bin/claude"
    PLANWRIGHT_CONFIG_DEFAULTS="$core_cfg"
    PLANWRIGHT_REPO_ROOT="$repo_cfg"
    PLANWRIGHT_ADOPTER_OVERLAY="$tmp/adopter"
    PLANWRIGHT_LOCAL_CONFIG=""
    SHIM_HOLD="$tmp"
    ${ie_pre[@]+"${ie_pre[@]}"} /bin/sh "${ISX:-$IS}/$ie_s" "$@")
  if [ -n "${IENV_EXEC:-}" ]; then
    exec "${ie_cmd[@]}"
  fi
  "${ie_cmd[@]}"
}

# sweep — one sweep cycle as this tower. Sets rc, out, err.
sweep() {
  rc=0
  ienv -- fleet-sweep.sh --repo "$repo" --tower-id "$self_id" >"$tmp/out" 2>"$tmp/err" || rc=$?
  out=$(cat "$tmp/out")
  err=$(cat "$tmp/err")
}

summary() {
  printf '%s\n' "$out" | awk -F'\t' '$1 == "summary"'
}

reap_line() {
  printf '%s\n' "$out" | awk -F'\t' -v w="$1" '$1 == "reap" && $2 == w'
}

audit() {
  ienv -- fleet-audit.sh query --mechanism process-cleanup 2>/dev/null || :
}

actions_for() {
  audit | awk -F'\t' -v w="worker=$1 " 'index($6, w) == 1 { print $4 }'
}

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

alive() {
  kill -0 "$1" 2>/dev/null
}

gone() {
  ! kill -0 "$1" 2>/dev/null && ! ps -p "$1" >/dev/null 2>&1
}

sj_launch() {
  ienv PLANWRIGHT_TOWER_ID="$2" SHIM_EVENTS="$ev_done" -- \
    fleet-streamjson.sh launch "$1" demo:4 --prompt-file "$tmp/prompt" --cwd "$repo" >/dev/null \
    || fail "stream-json launch of $1 failed"
  wait_until 30 classified "$1" finished-but-unreaped \
    || fail "$1 never classified finished-but-unreaped"
}

# --- a cycle fires with nothing to reap, and says so -----------------------
sweep
[ "$rc" = 0 ] || fail "an empty cycle: exit $rc ($err)"
case $(summary) in
  "summary${tab}mode=observe${tab}workers=0${tab}candidates=0${tab}reaped=0${tab}observed=0${tab}declined=0${tab}already-closed=0${tab}status=ok") ;;
  *) fail "an empty cycle did not report an empty reap pass: '$out'" ;;
esac
echo "ok: a cycle with nothing to reap still runs its reap pass and reports it"

# --- the watch loop fires on its interval, with nothing present -------------
# start_watch <out> <err> — a watch loop as this tower, its pid in watch_pid.
# The files are emptied here, before the loop starts, so a check can never
# read what the previous loop left in them.
start_watch() {
  : >"$1"
  : >"$2"
  (IENV_EXEC=1 ienv -- fleet-sweep.sh --watch --repo "$repo" --tower-id "$self_id" >"$1" 2>"$2") &
  watch_pid=$!
}
# cycles <file> — how many summaries a watch loop has printed.
cycles() {
  awk -F'\t' '$1 == "summary" { n++ } END { print n + 0 }' "$1"
}
# stop_watch <what> — TERM the loop; it must end within 5s and not exit 0.
stop_watch() {
  kill -TERM "$watch_pid"
  sw_start=$SECONDS
  sw_rc=0
  wait "$watch_pid" || sw_rc=$?
  [ $((SECONDS - sw_start)) -le 5 ] || fail "$1: the watch loop took $((SECONDS - sw_start))s to stop on TERM"
  [ "$sw_rc" != 0 ] || fail "$1: a watch loop stopped by TERM exited 0"
}
three_fired() {
  [ "$(cycles "$tmp/watch-out")" -ge 3 ]
}
printf 'fleet_sweep_interval: 1s\n' >"$mlocal_cfg"
start_watch "$tmp/watch-out" "$tmp/watch-err"
wait_until 30 three_fired || fail "the watch loop did not fire three cycles on a 1s interval: $(cat "$tmp/watch-out") $(cat "$tmp/watch-err")"
stop_watch "a 1s loop"
# A long interval proves the wait between cycles is interrupted, not sat out.
printf 'fleet_sweep_interval: 1h\n' >"$mlocal_cfg"
start_watch "$tmp/watch-out" "$tmp/watch-err"
one_fired() {
  [ "$(cycles "$tmp/watch-out")" -ge 1 ]
}
wait_until 30 one_fired || fail "the 1h watch loop never ran its first cycle: $(cat "$tmp/watch-err")"
stop_watch "a 1h loop"
# bad-value:expected-warning — a malformed value degrades to the default, and
# a well-formed sub-second one waits the floor.
for cell in '0s:fleet_sweep_interval' '0.4ms:under 1s'; do
  bad=${cell%%:*}
  printf 'fleet_sweep_interval: %s\n' "$bad" >"$mlocal_cfg"
  start_watch "$tmp/watch-out" "$tmp/watch-err"
  wait_until 10 grep -q "${cell#*:}" "$tmp/watch-err" \
    || fail "an interval of $bad was not warned about: $(cat "$tmp/watch-err")"
  sleep 2
  [ "$(cycles "$tmp/watch-out")" -le 3 ] || fail "an interval of $bad ran cycles back to back: $(cycles "$tmp/watch-out") in 2s"
  stop_watch "an interval of $bad"
done
rm -f "$mlocal_cfg"
echo "ok: the watch loop fires every interval with no threshold precondition, stops promptly on TERM mid-wait, and never runs cycles back to back"

# --- the source audit: no threshold is the trigger of record -----------------
code=$(sed -e 's/^[[:space:]]*#.*//' "$IS/fleet-sweep.sh")
knobs=$(printf '%s\n' "$code" | grep -oE '(fleet|sweep)_[a-z_]*threshold[a-z_]*' | sort -u || :)
[ "$knobs" = fleet_dirty_tree_threshold ] || fail "the sweep reads a threshold knob other than the dirty-tree grace: $knobs"
echo "ok: source audit — the only threshold the sweep reads is the dirty-tree grace, which defers an escalation and never gates a cycle"

# --- the source audit: the kill-switch is the only pause --------------------
# REQ-F1.3: the sweep pauses through fleet-daemon-gate.sh and reads no pause
# knob of its own.
pauses=$(printf '%s\n' "$code" | grep -oE '[a-z_]+_pause[a-z_]*' | sort -u || :)
[ "$pauses" = fleet_daemon_pause ] || fail "the sweep names a pause knob of its own: $pauses"
read_sites=$(printf '%s\n' "$code" | grep fleet_daemon_pause | grep -v 'warn "' || :)
[ -z "$read_sites" ] || fail "the sweep reads the kill-switch itself rather than through the gate: $read_sites"
# shellcheck disable=SC2016 # the script's own source text, matched literally
printf '%s\n' "$code" | grep -q '"\$GATE" housekeeping-sweep' || fail "the sweep does not gate through fleet-daemon-gate.sh"
echo "ok: source audit — the sweep pauses only through the existing kill-switch gate"

# --- the default mode observes: records the would-have close, kills nothing --
answer "$peer_id" dead
sj_launch sjw1 "$peer_id"
sup=$(cat "$home/streamjson/sjw1/supervisor.pid")
wrk=$(cat "$home/streamjson/sjw1/worker.pid")
sweep
[ "$rc" = 0 ] || fail "an observing cycle: exit $rc ($err)"
alive "$sup" || fail "the default mode terminated the supervisor"
alive "$wrk" || fail "the default mode terminated the worker"
case $(reap_line sjw1) in
  "reap${tab}sjw1${tab}observed${tab}"*) ;;
  *) fail "the observing cycle did not report sjw1 as observed: '$out'" ;;
esac
case $(summary) in
  *"mode=observe${tab}"*"candidates=1${tab}reaped=0${tab}observed=1${tab}declined=0${tab}"*) ;;
  *) fail "the observing cycle's summary is wrong: $(summary)" ;;
esac
[ "$(actions_for sjw1)" = would-cleanup ] || fail "the observing cycle's records for sjw1 are '$(actions_for sjw1)', expected one would-cleanup"
case $(audit) in
  *"${tab}would-cleanup${tab}"*"worker=sjw1 owner=$peer_id evidence=tower:dead,session:finished-but-unreaped/"*"released=none"*) ;;
  *) fail "the would-have record does not name worker, owner, evidence and an empty released set: $(audit)" ;;
esac
echo "ok: at the default the sweep writes the would-have record for a dead owner's leaked worker and terminates nothing"

# --- a repo-tracked terminate is not a per-machine opt-in --------------------
printf 'fleet_sweep_reap: terminate\n' >"$tracked_cfg"
sweep
alive "$sup" || fail "a repo-tracked terminate killed the supervisor"
alive "$wrk" || fail "a repo-tracked terminate killed the worker"
case $(summary) in
  *"mode=observe${tab}"*) ;;
  *) fail "a repo-tracked terminate changed the mode: $(summary)" ;;
esac
case $err in
  *fleet_sweep_reap*machine-local*) ;;
  *) fail "a repo-tracked terminate was ignored without saying why: $err" ;;
esac
rm -f "$tracked_cfg"
echo "ok: terminate set in a shared layer is refused with a warning; the sweep stays observing"

# --- the machine-local knob is what makes it kill ----------------------------
printf 'fleet_sweep_reap: terminate\n' >"$mlocal_cfg"
sweep
[ "$rc" = 0 ] || fail "a terminating cycle: exit $rc ($err)"
gone "$sup" || fail "the terminating cycle left the supervisor running"
gone "$wrk" || fail "the terminating cycle left the worker running"
case $(reap_line sjw1) in
  "reap${tab}sjw1${tab}reaped${tab}"*) ;;
  *) fail "the terminating cycle did not report sjw1 as reaped: '$out' ($err)" ;;
esac
case $(summary) in
  *"mode=terminate${tab}"*"reaped=1${tab}observed=0${tab}"*) ;;
  *) fail "the terminating cycle's summary is wrong: $(summary)" ;;
esac
[ "$(actions_for sjw1 | tr '\n' ' ')" = "would-cleanup would-cleanup cleanup " ] \
  || fail "sjw1's records read '$(actions_for sjw1 | tr '\n' ' ')'"
case $(audit | awk -F'\t' '$4 == "cleanup"') in
  *"worker=sjw1 owner=$peer_id evidence=tower:dead,session:finished-but-unreaped/"*"released=process"*) ;;
  *) fail "the termination record does not name worker, owner, evidence and released set: $(audit)" ;;
esac
# The two records can never be read as each other: different actions, and the
# would-have one names nothing released.
audit | awk -F'\t' '$4 == "would-cleanup" && $6 ~ /released=process/ { bad = 1 } END { exit bad }' \
  || fail "a would-have record names something released"
audit | awk -F'\t' '$4 == "cleanup" && $6 ~ /released=none/ { bad = 1 } END { exit bad }' \
  || fail "a termination record reads as releasing nothing"
sweep
case $(reap_line sjw1) in
  "reap${tab}sjw1${tab}already-closed${tab}"*) ;;
  *) fail "a reaped worker was not reported already closed on the next cycle: '$out'" ;;
esac
[ "$(actions_for sjw1 | grep -c '^cleanup$')" = 1 ] || fail "a second terminating cycle wrote a second termination record"
echo "ok: the machine-local knob makes the sweep reap the leaked worker, with a termination record distinct from the would-have record, once"

# --- flipping the knob back stops the killing, with no release --------------
printf 'fleet_sweep_reap: observe\n' >"$mlocal_cfg"
sj_launch sjw2 "$peer_id"
sup2=$(cat "$home/streamjson/sjw2/supervisor.pid")
sweep
alive "$sup2" || fail "a knob flipped back to observe still killed"
case $(reap_line sjw2) in
  "reap${tab}sjw2${tab}observed${tab}"*) ;;
  *) fail "a knob flipped back to observe did not observe sjw2: '$out'" ;;
esac
# The would-have record is taken from the rung's own probe, so a worker with
# nothing left to release is not recorded as one the sweep would close.
[ "$(actions_for sjw1 | tr '\n' ' ')" = "would-cleanup would-cleanup cleanup " ] \
  || fail "an observing cycle recorded a would-have close of an already-closed worker: $(actions_for sjw1 | tr '\n' ' ')"
case $(audit | awk -F'\t' '$4 == "would-cleanup"' | tail -n 1) in
  *"worker=sjw2 "*"released=none would-release=process"*) ;;
  *) fail "the would-have record does not name what the close would release: $(audit | tail -n 1)" ;;
esac
rm -f "$mlocal_cfg"
echo "ok: the knob is reversible by an overlay edit; flipped back, the sweep observes again"

# --- the kill-switch pauses the whole cycle ---------------------------------
printf 'fleet_daemon_pause: true\nfleet_sweep_reap: terminate\n' >"$mlocal_cfg"
sweep
[ "$rc" = 4 ] || fail "a paused sweep: exit $rc ($err)"
alive "$sup2" || fail "a paused sweep killed"
[ -z "$out" ] || fail "a paused sweep ran a pass: $out"
rm -f "$mlocal_cfg"
echo "ok: fleet_daemon_pause pauses the cycle before any pass"

# --- a running watch loop picks up the knob without a restart ----------------
printf 'fleet_sweep_interval: 1s\nfleet_sweep_reap: observe\n' >"$mlocal_cfg"
start_watch "$tmp/watch-out" "$tmp/watch-err"
observed_sjw2() {
  awk -F'\t' '$1 == "reap" && $2 == "sjw2" && $3 == "observed" { f = 1 } END { exit f ? 0 : 1 }' "$tmp/watch-out"
}
wait_until 30 observed_sjw2 || fail "the watch loop never observed sjw2: $(cat "$tmp/watch-out")"
alive "$sup2" || fail "an observing watch loop killed sjw2"
printf 'fleet_sweep_interval: 1s\nfleet_sweep_reap: terminate\n' >"$mlocal_cfg"
wait_until 30 gone "$sup2" || fail "the running loop did not start terminating once the knob flipped: $(cat "$tmp/watch-out") $(cat "$tmp/watch-err")"
stop_watch "a loop whose knob flipped"
rm -f "$mlocal_cfg"
echo "ok: a running watch loop re-reads the knob every cycle; flipping it takes effect with no restart"

# --- a sweep that declines every candidate says why -------------------------
IHOME="$tmp/home-decline"
export IHOME
mkdir -p "$IHOME"
answer "$live_id" live
answer "$unk_id" unknown
ienv -- fleet-state.sh register wpeer demo:7 --owner "$live_id" --backend stream-json-persistent >/dev/null
ienv -- fleet-state.sh register wprint demo:8 --owner "$peer_id" --backend print --death-handle none >/dev/null
ienv -- fleet-state.sh register wunk demo:9 --owner "$unk_id" --backend stream-json-persistent >/dev/null
for w in wpeer:demo:7 wprint:demo:8 wunk:demo:9; do
  ienv -- fleet-attention.sh heartbeat "${w%%:*}" "${w#*:}" ended >/dev/null
done
for mode in observe terminate; do
  printf 'fleet_sweep_reap: %s\n' "$mode" >"$mlocal_cfg"
  sweep
  [ "$rc" = 0 ] || fail "a declining cycle ($mode): exit $rc ($err)"
  case $(summary) in
    *"mode=$mode${tab}workers=3${tab}candidates=3${tab}reaped=0${tab}observed=0${tab}declined=3${tab}already-closed=0${tab}status=ok") ;;
    *) fail "a cycle declining every candidate ($mode) summarised as: $(summary)" ;;
  esac
  case $(reap_line wpeer) in
    "reap${tab}wpeer${tab}declined${tab}"*'live peer'*) ;;
    *) fail "the live-peer decline ($mode) does not say why: $(reap_line wpeer)" ;;
  esac
  case $(reap_line wprint) in
    "reap${tab}wprint${tab}declined${tab}"*'print-backend unit'*) ;;
    *) fail "the print decline ($mode) does not say why: $(reap_line wprint)" ;;
  esac
  case $(reap_line wunk) in
    "reap${tab}wunk${tab}declined${tab}"*'owning tower is gone'*) ;;
    *) fail "the unknown-owner decline ($mode) does not say why: $(reap_line wunk)" ;;
  esac
done
[ -z "$(audit)" ] || fail "a cycle that declined everything wrote a reap record: $(audit)"
rm -f "$mlocal_cfg"
unset IHOME
echo "ok: a sweep declining every candidate reports each refusal and its reason, in both modes, and is distinguishable from one that found nothing"

# --- the worktree scan runs every cycle and heals a registry gap -------------
git_env git -C "$repo" worktree add -q -b unrecorded "$tmp/wt-unrecorded"
listed() {
  ienv -- fleet-worktree-track.sh list | grep -qx "$tmp/wt-unrecorded"
}
! listed || fail "fixture: the unrecorded worktree is already tracked"
sweep
[ "$rc" = 0 ] || fail "a scanning cycle: exit $rc ($err)"
listed || fail "the sweep's scan did not pick up a worktree no hook recorded"
case $out in
  *"scan${tab}ok"*) ;;
  *) fail "the cycle does not report its scan: '$out'" ;;
esac
echo "ok: the worktree scan runs as part of the cycle and reconciles a registry gap"

# --- every actuator outcome is counted as what it was -------------------------
# The actuator is scripted here: an acted-on close must never be counted as a
# decline, and one the trail missed must degrade the cycle's status.
stubs="$tmp/stub-scripts"
cp -R "$IS" "$stubs"
# The stub answers from cl-<field>, or from cl-<field>.<worker> when a cell
# gives one worker its own answer.
cat >"$stubs/fleet-cleanup.sh" <<STUB
#!/bin/sh
s=""
[ -e "$tmp/cl-rc.\$2" ] && s=".\$2"
[ -s "$tmp/cl-out\$s" ] && sed "s/WORKER/\$2/" "$tmp/cl-out\$s"
[ -s "$tmp/cl-err\$s" ] && cat "$tmp/cl-err\$s" >&2
exit "\$(cat "$tmp/cl-rc\$s")"
STUB
chmod +x "$stubs/fleet-cleanup.sh"
IHOME="$tmp/home-stub"
export IHOME ISX="$stubs"
mkdir -p "$IHOME"
for w in wa wb; do
  ienv -- fleet-state.sh register "$w" demo:5 --owner "$peer_id" --backend stream-json-persistent >/dev/null
  ienv -- fleet-attention.sh heartbeat "$w" demo:5 ended >/dev/null
done
printf 'fleet_sweep_reap: terminate\n' >"$mlocal_cfg"
# outcome <rc> <stdout> <stderr> <outcome> <reaped> <declined> <status>
outcome() {
  printf '%s\n' "$1" >"$tmp/cl-rc"
  printf '%s' "$2" >"$tmp/cl-out"
  printf '%s' "$3" >"$tmp/cl-err"
  sweep
  for w in wa wb; do
    case $(reap_line "$w") in
      "reap${tab}$w${tab}$4${tab}"*) ;;
      *) fail "actuator exit $1 ('$2'): $w reads '$(reap_line "$w")', expected $4" ;;
    esac
  done
  case $(summary) in
    *"reaped=$5${tab}"*"declined=$6${tab}"*"status=$7") ;;
    *) fail "actuator exit $1 ('$2'): summary $(summary)" ;;
  esac
}
outcome 0 'stop WORKER stopped released=process' '' reaped 2 0 ok
outcome 5 'stop WORKER stopped released=process' 'fleet-cleanup: interrupted while closing' reaped 2 0 ok
outcome 5 'stop WORKER partial released=unreported held=unreported' 'fleet-cleanup: the stop died' partial 2 0 ok
outcome 6 'stop WORKER stopped released=process' 'fleet-cleanup: FAILED to record it' unrecorded 2 0 degraded
case $err in
  *"not in the audit trail"*) ;;
  *) fail "an unrecorded close was not warned about: $err" ;;
esac
outcome 6 'stop WORKER partial released=process held=attention' 'fleet-cleanup: could not record the partial close' unrecorded 2 0 degraded
outcome 5 '' 'fleet-cleanup: refusing: no positive evidence' declined 0 2 ok
outcome 4 '' 'fleet-cleanup: daemon layer paused' paused 0 0 paused
# An unrecorded close ahead of a pause keeps the cycle degraded.
printf '6\n' >"$tmp/cl-rc.wa"
printf 'stop WORKER stopped released=process' >"$tmp/cl-out.wa"
printf 'fleet-cleanup: FAILED to record it' >"$tmp/cl-err.wa"
sweep
case $(summary) in
  *"status=degraded") ;;
  *) fail "a pause after an unrecorded close hid the degradation: $(summary)" ;;
esac
case $(reap_line wb) in
  "reap${tab}wb${tab}paused${tab}"*) ;;
  *) fail "the candidate after the pause was not reported paused: $(reap_line wb)" ;;
esac
rm -f "$tmp/cl-rc.wa" "$tmp/cl-out.wa" "$tmp/cl-err.wa"
# A worker whose own handle starts with `sweep-` is a worker, not one of the
# sweep's queue rows.
ienv -- fleet-state.sh register sweep-docs demo:6 --owner "$peer_id" --backend stream-json-persistent >/dev/null
ienv -- fleet-attention.sh heartbeat sweep-docs demo:6 ended >/dev/null
printf '0\n' >"$tmp/cl-rc"
printf 'stop WORKER stopped released=process' >"$tmp/cl-out"
: >"$tmp/cl-err"
sweep
case $(reap_line sweep-docs) in
  "reap${tab}sweep-docs${tab}reaped${tab}"*) ;;
  *) fail "a worker named sweep-docs was left out of the reap: '$out'" ;;
esac
unset IHOME ISX
rm -f "$mlocal_cfg" "$tmp/cl-out" "$tmp/cl-err"
echo "ok: a close, an interrupted close, a partial one, an unrecorded one, a refusal and a pause are each reported as what they were"

# --- the knob is this checkout's, read from --repo and never from the repo ---
# No pinned repo root here: the layers are the ones the checkout derives, the
# way a cron entry started in another directory finds them.
repo2="$tmp/repo2"
git_env git init -q -b main "$repo2"
(cd "$repo2" && echo seed >f && git_env git add f && git_env git commit -qm seed)
mkdir -p "$repo2/.claude"
printf 'fleet_sweep_reap: terminate\n' >"$repo2/.claude/planwright.local.yml"
IHOME="$tmp/home-repo2"
export IHOME
mkdir -p "$IHOME"
# derived_sweep — a sweep of repo2 started from /, its layers derived.
derived_sweep() {
  rc=0
  (cd / && ienv PLANWRIGHT_REPO_ROOT= -- fleet-sweep.sh --repo "$repo2" --tower-id "$self_id") \
    >"$tmp/out" 2>"$tmp/err" || rc=$?
  out=$(cat "$tmp/out")
  err=$(cat "$tmp/err")
}
derived_sweep
case $(summary) in
  *"mode=terminate${tab}"*) ;;
  *) fail "a sweep started outside the checkout did not read its machine-local terminate: $(summary) ($err)" ;;
esac
git_env git -C "$repo2" add -f .claude/planwright.local.yml
git_env git -C "$repo2" commit -qm 'ship a local config'
derived_sweep
case $(summary) in
  *"mode=observe${tab}"*) ;;
  *) fail "a committed machine-local terminate switched the reaper on: $(summary)" ;;
esac
case $err in
  *'the repository tracks that file'*) ;;
  *) fail "a committed machine-local terminate was ignored without saying why: $err" ;;
esac
cp "$core_cfg" "$tmp/core-saved.yml"
sed 's/^fleet_sweep_reap: observe$/fleet_sweep_reap: terminate/' "$tmp/core-saved.yml" >"$core_cfg"
grep -q '^fleet_sweep_reap: terminate$' "$core_cfg" || fail "fixture: the core layer does not say terminate"
sweep
case $(summary) in
  *"mode=observe${tab}"*) ;;
  *) fail "a core-layer terminate switched the reaper on: $(summary)" ;;
esac
case $err in
  *'not the core layer'*) ;;
  *) fail "a core-layer terminate was ignored without saying why: $err" ;;
esac
cp "$tmp/core-saved.yml" "$core_cfg"
# A local file reached through a symlink, and a .claude that is its own
# repository, are the repository's content too.
repo2_local() {
  git_env git -C "$repo2" rm -q --cached .claude/planwright.local.yml
  git_env git -C "$repo2" commit -qm 'stop shipping the local config'
}
repo2_local
printf 'fleet_sweep_reap: terminate\n' >"$tmp/elsewhere.yml"
rm -f "$repo2/.claude/planwright.local.yml"
ln -s "$tmp/elsewhere.yml" "$repo2/.claude/planwright.local.yml"
derived_sweep
case $(summary)/$err in
  *"mode=observe${tab}"*/*'through a symlink'*) ;;
  *) fail "a symlinked machine-local terminate was not refused: $(summary) ($err)" ;;
esac
rm -f "$repo2/.claude/planwright.local.yml"
printf 'fleet_sweep_reap: terminate\n' >"$repo2/.claude/planwright.local.yml"
git_env git init -q "$repo2/.claude"
derived_sweep
case $(summary)/$err in
  *"mode=observe${tab}"*/*'its own repository'*) ;;
  *) fail "a machine-local terminate inside a nested .claude repository was not refused: $(summary) ($err)" ;;
esac
unset IHOME
echo "ok: the reap knob is read from the swept checkout wherever the sweep starts, and terminate from a committed, symlinked or nested local file, or the core layer, is refused"
