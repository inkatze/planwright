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
# tree, hermetic against the host's fleet home and configuration.
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
    PLANWRIGHT_FLEET_STATE_DIR="${IHOME:-$home}" \
    PLANWRIGHT_STREAMJSON_CLI="$tmp/bin/claude" \
    PLANWRIGHT_CONFIG_DEFAULTS="$core_cfg" \
    PLANWRIGHT_REPO_ROOT="$repo_cfg" \
    PLANWRIGHT_ADOPTER_OVERLAY="$tmp/adopter" \
    PLANWRIGHT_LOCAL_CONFIG="" \
    SHIM_HOLD="$tmp" \
    ${ie_pre[@]+"${ie_pre[@]}"} /bin/sh "$IS/$ie_s" "$@"
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
printf 'fleet_sweep_interval: 1s\n' >"$mlocal_cfg"
ienv -- fleet-sweep.sh --watch --repo "$repo" --tower-id "$self_id" >"$tmp/watch-out" 2>"$tmp/watch-err" &
watch_pid=$!
fired() {
  [ "$(awk -F'\t' '$1 == "summary"' "$tmp/watch-out" | grep -c .)" -ge 3 ]
}
wait_until 30 fired || fail "the watch loop did not fire three cycles on a 1s interval: $(cat "$tmp/watch-out") $(cat "$tmp/watch-err")"
kill -TERM "$watch_pid"
w_rc=0
w_start=$SECONDS
wait "$watch_pid" || w_rc=$?
[ $((SECONDS - w_start)) -le 5 ] || fail "the watch loop took $((SECONDS - w_start))s to stop on TERM"
[ "$w_rc" != 0 ] || fail "a watch loop stopped by TERM exited 0"
rm -f "$mlocal_cfg"
printf 'fleet_sweep_interval: 0s\n' >"$mlocal_cfg"
rc=0
ienv -- fleet-sweep.sh --watch --repo "$repo" --tower-id "$self_id" >"$tmp/out" 2>"$tmp/err" &
bad_pid=$!
wait_until 10 grep -q 'fleet_sweep_interval' "$tmp/err" || fail "a malformed machine-local interval was not warned about: $(cat "$tmp/err")"
kill -TERM "$bad_pid" 2>/dev/null || :
wait "$bad_pid" 2>/dev/null || :
rm -f "$mlocal_cfg"
echo "ok: the watch loop fires every interval with no threshold precondition, stops promptly on TERM, and warns on a malformed interval"

# --- the source audit: no threshold is the trigger of record -----------------
code=$(sed -e 's/^[[:space:]]*#.*//' "$IS/fleet-sweep.sh")
knobs=$(printf '%s\n' "$code" | grep -oE '(fleet|sweep)_[a-z_]*threshold[a-z_]*' | sort -u || :)
[ "$knobs" = fleet_dirty_tree_threshold ] || fail "the sweep reads a threshold knob other than the dirty-tree grace: $knobs"
echo "ok: source audit — the only threshold the sweep reads is the dirty-tree grace, which defers an escalation and never gates a cycle"

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
[ -z "$(summary)" ] || fail "a paused sweep ran its reap pass: $(summary)"
rm -f "$mlocal_cfg"
echo "ok: fleet_daemon_pause pauses the cycle before any pass"

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
    "reap${tab}wprint${tab}declined${tab}"*print*) ;;
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
