# shellcheck shell=bash
# shellcheck disable=SC2154,SC2034 # `here` is the caller's; the fixture's paths and results are read by it
# fleet-adversarial-fixture.sh — the shared fixture for the multi-tower
# adversarial suites (sourced, never executed): tests/test-fleet-adversarial.sh
# (the evidence matrix) and tests/test-fleet-adversarial-concurrency.sh.
#
# Everything the destructive verbs act on is created here, under one temp
# root: real worker processes launched through the real rungs (a CLI shim
# stands in for the model session), a fleet home, a unit with a fence ref on
# its origin, a task branch and a worktree holding uncommitted work, and a
# strand entry in the attention store. The one scripted surface is presence,
# which answers the owning tower's liveness from a per-cell file, so a dead,
# live, unknown or errored owner needs no second tower. No path here reaches
# the host's fleet home, its tmux server, or any process this file did not
# start.
#
# The caller sets `here` (its own directory) and `set -eu` before sourcing.

export GIT_CONFIG_GLOBAL=/dev/null
export GIT_CONFIG_SYSTEM=/dev/null
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

command -v jq >/dev/null 2>&1 || fail "jq is required: the stream-json launch preflight runs the auto-approve hook"

tmp=$(cd "$(mktemp -d)" && pwd -P)
adv_cleanup() {
  set +e
  for p in $(jobs -p); do
    kill -9 "$p" 2>/dev/null
  done
  ac_snap=$(ps -A -ww -o pid=,args= 2>/dev/null) || ac_snap=''
  while read -r p a; do
    case $a in
      *"$tmp"*) [ "$p" = "$$" ] || kill -9 "$p" 2>/dev/null ;;
    esac
  done <<EOF
$ac_snap
EOF
  rm -rf "$tmp"
}
trap adv_cleanup EXIT
tab=$(printf '\t')

self_id='11111111-2222-3333-4444-555555555555'
peer_id='aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee'

# No death-evidence probe may reach the host's tmux server.
mkdir -p "$tmp/notmux"
printf '#!/bin/sh\nexit 1\n' >"$tmp/notmux/tmux"
chmod +x "$tmp/notmux/tmux"
export PATH="$tmp/notmux:$PATH"

# The no-LLM negative assertion's recorder: every outbound client a decision
# path could reach for, first on PATH for every decision-path run. Launches
# name their CLI shim by absolute path and run without these.
nollm="$tmp/nollm"
mkdir -p "$nollm"
for c in claude anthropic curl wget gh nc ssh; do
  printf '#!/bin/sh\nprintf "%%s %%s\\n" %s "$*" >>"%s/nollm-calls"\nexit 0\n' "$c" "$tmp" >"$nollm/$c"
  chmod +x "$nollm/$c"
done

core_cfg="$tmp/core-defaults.yml"
cp "$here/../config/defaults.yml" "$core_cfg"
repo_cfg="$tmp/cfg-repo"
mkdir -p "$repo_cfg/.claude"

env_scrub=(
  -u CLAUDE_PLUGIN_DATA -u CLAUDE_PLUGIN_ROOT -u CLAUDE_DIR -u HOME
  -u PLANWRIGHT_ROOT -u PLANWRIGHT_TOWER_ID -u PLANWRIGHT_TOWER_SESSION_ID
  -u PLANWRIGHT_TOWER_PID -u PLANWRIGHT_TOWER_CHECKOUT
  -u PLANWRIGHT_STREAMJSON_PENDING_AGE -u PLANWRIGHT_STREAMJSON_ALARM_TICK
  -u PLANWRIGHT_STREAMJSON_GUARD_PREFLIGHT
  -u PLANWRIGHT_WORKER_HANDLE -u PLANWRIGHT_WORKER_SCOPE
  -u FLEET_PANE_PROMPT_ANCHORS -u FLEET_PANE_PROMPT_SIGNATURES
  -u PLANWRIGHT_HEADLESS_ENVWRAP -u PLANWRIGHT_HEADLESS_LIVENESS_TTL
  -u PLANWRIGHT_FLEET_LOCK_HELD -u PLANWRIGHT_ORCH_STATE_DIR -u PLANWRIGHT_JQ
  -u PLANWRIGHT_ATTENTION_SURFACE_PROVIDED -u PLANWRIGHT_SKILLS_ROOT
  -u PLANWRIGHT_HEADLESS_STATE_DIR
  -u TMUX -u TMUX_PANE
)

it="$tmp/int"
mkdir -p "$it"
cp -R "$here/../scripts" "$here/../config" "$here/../hooks" "$it/"
IS="$it/scripts"
# Presence answers the owning tower's liveness from a fixture file; the word
# ERRORED makes the surface itself fail, the way an unreadable store does.
presence_answer="$tmp/presence-answer"
cat >"$IS/fleet-presence.sh" <<STUB
#!/bin/sh
case "\$1" in
  liveness)
    grep -q ERRORED "$presence_answer" && exit 2
    cat "$presence_answer"
    exit 0
    ;;
esac
exit 3
STUB
chmod +x "$IS/fleet-presence.sh"

# owner_is <dead|live|unknown|ERRORED> — what presence says of the peer.
owner_is() {
  if [ "$1" = ERRORED ]; then
    printf 'ERRORED\n' >"$presence_answer"
  else
    printf 'tower\t%s\t%s\n' "$peer_id" "$1" >"$presence_answer"
  fi
}
owner_is dead

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
ev_init="$tmp/ev-init"
printf '%s\n' '{"type":"system","subtype":"init","cwd":"/x","session_id":"'$sid'","tools":[]}' >"$ev_init"
printf 'do the thing\n' >"$tmp/prompt"

ihome="$tmp/int-home"
mkdir -p "$ihome"

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

# decide [VAR=val...] -- <script> <args...> — a decision-path run: ienv with
# the outbound-client recorders first on PATH.
decide() {
  PATH="$nollm:$PATH" ienv "$@"
}

# icleanup <worker> [flags...] — the reap actuator as this tower. Sets rc,
# out, err.
icleanup() {
  ic_w=$1
  shift
  rc=0
  decide -- fleet-cleanup.sh process "$ic_w" 'periodic sweep' 'adversarial matrix' \
    --tower-id "$self_id" --grace 1 "$@" >"$tmp/out" 2>"$tmp/err" || rc=$?
  out=$(cat "$tmp/out")
  err=$(cat "$tmp/err")
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

gone() {
  ! kill -0 "$1" 2>/dev/null && ! ps -p "$1" >/dev/null 2>&1
}

alive() {
  kill -0 "$1" 2>/dev/null
}

git_env() {
  GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t \
    GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t "$@"
}

# The unit every worker runs against: a fence ref on origin, a task branch
# with a commit of its own, and a worktree carrying uncommitted work.
origin="$tmp/origin.git"
main_repo="$tmp/main"
wt="$tmp/wt"
git_env git init -q --bare "$origin"
git_env git init -q -b main "$main_repo"
(
  cd "$main_repo" || exit 1
  echo seed >f
  git_env git add f
  git_env git commit -qm seed
  git_env git remote add origin "$origin"
  git_env git push -q origin main
  git_env git push -q origin HEAD:refs/planwright-fence/demo/4
  git_env git worktree add -q -b planwright/demo/task-4 "$wt"
)
(
  cd "$wt" || exit 1
  echo work >g
  git_env git add g
  git_env git commit -qm work
  echo 'uncommitted, in flight' >h
)

untouched_origin=$(git -C "$origin" for-each-ref)
untouched_refs=$(git -C "$main_repo" for-each-ref)
untouched_tip=$(git -C "$wt" rev-parse HEAD)
untouched_status=$(git -C "$wt" status --porcelain)
untouched_h=$(cat "$wt/h")
untouched_list=$(git -C "$main_repo" worktree list --porcelain)

# untouched <what> — the fence, the branch and the worktree exactly as the
# fixture left them.
untouched() {
  [ "$(git -C "$origin" for-each-ref)" = "$untouched_origin" ] \
    || fail "$1: a ref on origin changed (the unit's fence among them)"
  [ "$(git -C "$main_repo" for-each-ref)" = "$untouched_refs" ] || fail "$1: a local ref changed"
  [ "$(git -C "$wt" rev-parse HEAD)" = "$untouched_tip" ] || fail "$1: the branch tip moved"
  [ "$(git -C "$wt" status --porcelain)" = "$untouched_status" ] || fail "$1: the worktree status changed"
  [ "$(cat "$wt/h" 2>/dev/null)" = "$untouched_h" ] || fail "$1: the uncommitted work changed"
  [ "$(git -C "$main_repo" worktree list --porcelain)" = "$untouched_list" ] || fail "$1: the worktree list changed"
}

attn() {
  ienv -- fleet-attention.sh "$@" >/dev/null || fail "fleet-attention.sh $1 failed"
}

store="$ihome/attention/state"
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

reaps_recorded() {
  ienv -- fleet-audit.sh query --mechanism process-cleanup 2>/dev/null \
    | awk -F'\t' '$4 == "cleanup" || $4 == "cleanup-partial"' | grep -c . || :
}

# reaps_of <worker> — the termination records naming <worker>.
reaps_of() {
  ienv -- fleet-audit.sh query --mechanism process-cleanup 2>/dev/null \
    | awk -F'\t' -v w="worker=$1 " '($4 == "cleanup" || $4 == "cleanup-partial") && index($6, w) == 1' \
    | grep -c . || :
}

# sj_launch <handle> <events-file> <owner> — a stream-json worker under the
# real rung; prints nothing, sets sup and wrk.
sj_launch() {
  ienv PLANWRIGHT_TOWER_ID="$3" SHIM_EVENTS="$2" -- \
    fleet-streamjson.sh launch "$1" demo:4 --prompt-file "$tmp/prompt" --cwd "$wt" >/dev/null \
    || fail "stream-json launch of $1 failed"
  wait_until 30 test -s "$ihome/streamjson/$1/worker.pid" || fail "$1 never recorded its worker pid"
  sup=$(cat "$ihome/streamjson/$1/supervisor.pid")
  wrk=$(cat "$ihome/streamjson/$1/worker.pid")
}

# hl_launch <task> <owner> — a headless worker under the real rung; sets
# hw (its handle) and runner.
hl_launch() {
  ienv PLANWRIGHT_TOWER_ID="$2" -- \
    fleet-dispatch-headless.sh launch demo "$1" --worktree "$wt" <"$tmp/prompt" >/dev/null \
    || fail "headless launch of task $1 failed"
  hw="headless-demo-task-$1"
  wait_until 30 test -s "$ihome/headless/$1/pid" || fail "$hw never recorded its runner pid"
  runner=$(cat "$ihome/headless/$1/pid")
}

# unobservable <worker> — supersede the worker's record with a death handle no
# probe can answer, so its session is neither positively running nor
# positively ended: lost observability, the evidence class REQ-D1.4 reads as
# alive.
unobservable() {
  uo_row=$(awk -F'\t' -v w="$1" '($2 "") == (w "") { l = $0 } END { print l }' "$ihome/registry")
  [ -n "$uo_row" ] || fail "fixture: $1 has no record to supersede"
  printf '%s\n' "$uo_row" | awk -F'\t' -v OFS='\t' '{ $1 = $1 + 1; $7 = "tmux-window unobservable @1"; print }' \
    >>"$ihome/registry"
}

# Cell bookkeeping: every cell a suite runs is recorded, and the suite's
# literal expected-cell manifest must match the recorded set exactly, so a
# cell dropped or added without the manifest changing fails the run.
: >"$tmp/cells-ran"
ran() {
  grep -qx "$1" "$tmp/cells-ran" && fail "cell $1 ran twice"
  printf '%s\n' "$1" >>"$tmp/cells-ran"
}

manifest_check() {
  mc_want=$(printf '%s\n' "$1" | awk 'NF' | sort)
  mc_have=$(sort "$tmp/cells-ran")
  mc_missing=$(comm -23 <(printf '%s\n' "$mc_want") <(printf '%s\n' "$mc_have"))
  mc_extra=$(comm -13 <(printf '%s\n' "$mc_want") <(printf '%s\n' "$mc_have"))
  [ -z "$mc_missing" ] || fail "expected-cell manifest: cells that never ran: $(printf '%s' "$mc_missing" | tr '\n' ' ')"
  [ -z "$mc_extra" ] || fail "expected-cell manifest: cells that ran but are not in it: $(printf '%s' "$mc_extra" | tr '\n' ' ')"
}

# nollm_check — no decision-path run invoked an outbound client, and the
# recorders were reachable (a positive control, so an empty log means
# something).
nollm_check() {
  [ ! -s "$tmp/nollm-calls" ] || fail "an outbound client was invoked on a decision path: $(cat "$tmp/nollm-calls")"
  PATH="$nollm:$PATH" claude --probe >/dev/null 2>&1
  [ -s "$tmp/nollm-calls" ] || fail "no-LLM positive control: the recorder was not reachable on PATH"
  : >"$tmp/nollm-calls"
}
