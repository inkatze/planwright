# shellcheck shell=bash
# fleet-stop-table.sh — the close on both session-grade rungs as one behavioural
# table, parameterised by rung (sourced, never executed). Each rung runs it from
# its own file, tests/test-fleet-stop-sj.sh against `scripts/fleet-streamjson.sh
# stop` and tests/test-fleet-stop-hl.sh against
# `scripts/fleet-dispatch-headless.sh stop`, so the two halves share the runner's
# parallelism rather than one file's budget. Every cell runs on both; a cell
# passing on one rung and not the other is the asymmetry the table exists to
# catch (REQ-B1.1). A cell that does not apply to a rung says so with a visible
# `skip:` line naming why.
#
# The cells:
#   c19 (REQ-B1.2, REQ-B1.4, REQ-A1.3): `stop` terminates the re-exec, the
#       worker, and the worker's own child, releases the runtime set, keeps the
#       durable record, and leaves the worktree as it found it.
#   c20 (REQ-B1.2): SIGTERM first, SIGKILL after the grace the caller set.
#   c21 (REQ-B1.3): state-directory matching spares a look-alike operator
#       session and a sibling whose handle extends the stopped one; a source
#       audit over the shared kill path and each rung's match finds no name or
#       command-pattern match.
#   c22 (REQ-B1.7): a repeat stop returns already-closed and signals nothing;
#       c22c adds the lock class where the rung has one, and the refusals of a
#       malformed or unknown handle and an out-of-range grace.
#   c22b (REQ-B1.2): a SIGTERM-surviving grandchild reparented away from the
#       tree is still closed.
#   c22d-h (REQ-B1.3): a close from inside the worker's own tree is refused; a
#       recycled pid in the closer's ancestry is not mistaken for one; a
#       truncated-argv host fails closed; an unreadable process table refuses;
#       a fifo planted at a pid file cannot hang the close.
#   c23 (REQ-A1.3, REQ-B1.7): a partial close reports partial, and the retry
#       drains exactly what is still held; c32 holds the attention class when
#       its probe cannot answer.
#   c40 (REQ-B1.3, REQ-B1.7): a unit whose run already ended keeps its record,
#       and its stale pid is never signalled.
#   c41 (REQ-B1.3, REQ-B1.4): the headless rung's default state layout, where
#       the spec is part of the path, and its symlinked-state refusal.
#
# The stream-json rung's own suite keeps the cases that exercise what only it
# has: the receipt journal, the launch and recover elections, the supervisor's
# pid publication.
#
# Hermetic: every cell pins the fleet home, the headless state base, and both
# rungs' CLI seam to case-local paths and one env-driven shim. The sourcing file
# sets `here` to the tests directory first. Runs under /bin/bash (bash 3.2).
set -u
LC_ALL=C
export LC_ALL
unset CDPATH

: "${here:?the sourcing test sets here to the tests directory}"
SJ="$here/../scripts/fleet-streamjson.sh"
FDH="$here/../scripts/fleet-dispatch-headless.sh"
LIB="$here/../scripts/fleet-stop-lib.sh"
FA="$here/../scripts/fleet-attention.sh"

fail() {
  echo "FAIL: [${rung:-}] $1" >&2
  exit 1
}

for f in "$SJ" "$FDH" "$FA"; do
  [ -x "$f" ] || fail "$f missing or not executable"
done
[ -r "$LIB" ] || fail "$LIB missing or not readable"
# The stream-json launch preflight runs the worker-command-guard, whose payload
# read needs jq; without it every launch below would refuse for the wrong reason.
command -v jq >/dev/null 2>&1 || fail "jq is required: the stream-json launch preflight runs the auto-approve hook"

# Physical temp path (macOS /var -> /private/var): the headless state base is
# compared physically.
tmp=$(cd "$(mktemp -d)" && pwd -P)
strangers=''
cleanup() {
  # A failed cell can leave a worker holding open; nothing may outlive the run.
  # A headless unit keeps its pid file after its runner is gone, so a pid is
  # killed only while its argv still names this run's scratch tree.
  for pf in "$tmp"/*/h*/streamjson/*/supervisor.pid "$tmp"/*/h*/streamjson/*/worker.pid \
    "$tmp"/*/h*/headless/*/pid "$tmp"/*/repo*/specs/*/.orchestrate/headless/*/pid; do
    [ -f "$pf" ] || continue
    p=$(cat "$pf" 2>/dev/null) || continue
    case $p in '' | *[!0-9]*) continue ;; esac
    case $(ps -p "$p" -o args= 2>/dev/null) in
      *"$tmp"*) kill -9 "$p" 2>/dev/null ;;
    esac
  done
  # The processes the cells plant as reissued pids, named by nothing in the tree.
  # Checked first: an exited sleep's pid may already belong to something else.
  for p in $strangers; do
    case $(ps -p "$p" -o args= 2>/dev/null) in
      'sleep 120') kill "$p" 2>/dev/null ;;
    esac
  done
  rm -rf "$tmp"
}
trap cleanup EXIT
tab=$(printf '\t')
SPEC=execution-backends

# --- fixtures ---------------------------------------------------------------

# The single env-driven CLI shim both rungs launch. It reads SHIM_READ_FIRST
# stdin lines (the stream-json rung's init frame, the headless rung's prompt),
# so one shim serves both launch shapes.
mkdir -p "$tmp/bin"
cat >"$tmp/bin/claude" <<'SHIM'
#!/bin/sh
# CLI shim (fixture), driven by env:
#   SHIM_RECORD_DIR   records argv + stdin lines (required)
#   SHIM_EVENTS       file of lines emitted on stdout
#   SHIM_READ_FIRST   stdin lines to read+record before emitting (default 1)
#   SHIM_SLEEP        sleep after emitting (hold open)
#   SHIM_STUBBORN_CHILD  path a SIGTERM-surviving grandchild records its pid in
#   SHIM_IGNORE_TERM=1   survive SIGTERM, recording each one in <record>/signals
#   SHIM_SELF_CLOSE   a command run from inside the worker's own tree, after
#                     SHIM_SELF_CLOSE_WHEN exists; its output and exit are
#                     recorded as selfclose.out / selfclose.rc
printf '%s\n' "$*" >>"$SHIM_RECORD_DIR/argv"
n=${SHIM_READ_FIRST:-1}
i=0
while [ "$i" -lt "$n" ]; do
  IFS= read -r line || break
  printf '%s\n' "$line" >>"$SHIM_RECORD_DIR/stdin"
  i=$((i + 1))
done
if [ -n "${SHIM_EVENTS:-}" ]; then
  cat "$SHIM_EVENTS"
fi
if [ -n "${SHIM_STUBBORN_CHILD:-}" ]; then
  # A separate `sh -c`, not a `( … ) &` subshell: POSIX `$$` in a subshell is
  # the parent's pid, so a subshell would record the shim's own pid and every
  # assertion against it would only re-test that the worker died.
  sh -c 'trap "" TERM; printf "%s\n" "$$" >"$1"; while :; do sleep 1; done' \
    _ "$SHIM_STUBBORN_CHILD" &
fi
if [ "${SHIM_IGNORE_TERM:-0}" = 1 ]; then
  trap 'printf "term\n" >>"$SHIM_RECORD_DIR/signals"' TERM
  while :; do
    sleep 1
  done
fi
if [ -n "${SHIM_SELF_CLOSE:-}" ]; then
  # Bounded: a cell that fails before creating the go-file must not leave this
  # shim spinning past the run.
  if [ -n "${SHIM_SELF_CLOSE_WHEN:-}" ]; then
    sc_i=0
    while [ ! -e "$SHIM_SELF_CLOSE_WHEN" ] && [ "$sc_i" -lt 600 ]; do
      sleep 0.1
      sc_i=$((sc_i + 1))
    done
  fi
  sh -c "$SHIM_SELF_CLOSE" >"$SHIM_RECORD_DIR/selfclose.out" 2>&1
  printf '%s\n' "$?" >"$SHIM_RECORD_DIR/selfclose.rc"
fi
if [ -n "${SHIM_SLEEP:-}" ]; then
  sleep "$SHIM_SLEEP"
fi
exit 0
SHIM
chmod +x "$tmp/bin/claude"

sid='11111111-2222-3333-4444-555555555555'
line_init='{"type":"system","subtype":"init","cwd":"/x","session_id":"'$sid'","tools":[]}'
line_perm='{"type":"control_request","request_id":"aaaa1111-bbbb-cccc-dddd-eeee00000001","request":{"subtype":"can_use_tool","tool_name":"Write","input":{"file_path":"/x/y.txt","content":"hello"},"tool_use_id":"t1"}}'
line_result='{"type":"result","subtype":"success","result":"done","session_id":"'$sid'"}'
ev_hold="$tmp/ev-hold"
printf '%s\n%s\n' "$line_init" "$line_perm" >"$ev_hold"
ev_done="$tmp/ev-done"
printf '%s\n%s\n%s\n' "$line_init" "$line_perm" "$line_result" >"$ev_done"

# The ambient overlay/config knobs every hermetic runner strips, so no cell
# reads the developer's real fleet home or configuration.
env_scrub=(
  -u CLAUDE_PLUGIN_DATA -u CLAUDE_PLUGIN_ROOT -u CLAUDE_DIR -u HOME
  -u PLANWRIGHT_ROOT -u PLANWRIGHT_ADOPTER_OVERLAY -u PLANWRIGHT_REPO_ROOT
  -u PLANWRIGHT_LOCAL_CONFIG -u PLANWRIGHT_CONFIG_DEFAULTS
  -u PLANWRIGHT_STREAMJSON_PENDING_AGE -u PLANWRIGHT_STREAMJSON_ALARM_TICK
  -u PLANWRIGHT_STREAMJSON_GUARD_PREFLIGHT
  -u PLANWRIGHT_WORKER_HANDLE -u PLANWRIGHT_WORKER_SCOPE
)

# --- the rung adapter -------------------------------------------------------
# Everything a cell needs to know about a rung, keyed on `$rung` (sj | hl).
# Cells are written against these and never name a rung's files directly.

rung_script() {
  case $rung in
    sj) printf '%s' "$SJ" ;;
    hl) printf '%s' "$FDH" ;;
  esac
}

# renv <home> <rec> [VAR=val...] -- <args...> — the rung's script, hermetic.
renv() {
  re_home=$1
  re_rec=$2
  shift 2
  re_pre=()
  while [ $# -gt 0 ] && [ "$1" != "--" ]; do
    re_pre+=("$1")
    shift
  done
  shift
  env "${env_scrub[@]}" \
    PLANWRIGHT_FLEET_STATE_DIR="$re_home" \
    PLANWRIGHT_HEADLESS_STATE_DIR="$re_home/headless" \
    PLANWRIGHT_STREAMJSON_CLI="$tmp/bin/claude" \
    PLANWRIGHT_HEADLESS_CLAUDE="$tmp/bin/claude" \
    SHIM_RECORD_DIR="$re_rec" \
    ${re_pre[@]+"${re_pre[@]}"} /bin/sh "$(rung_script)" "$@"
}

aenv() {
  ae_home=$1
  shift
  env "${env_scrub[@]}" PLANWRIGHT_FLEET_STATE_DIR="$ae_home" /bin/sh "$FA" "$@"
}

# w_name <n> — the handle `stop` takes for unit <n>; w_sibling <n> — a handle
# this one is a prefix of, whose state directory this one's prefixes too.
w_name() {
  case $rung in
    sj) printf 'sjw%s' "$1" ;;
    hl) printf 'headless-%s-task-%s' "$SPEC" "$1" ;;
  esac
}

w_sibling() {
  case $rung in
    sj) printf 'sjw%sx' "$1" ;;
    hl) printf 'headless-%s-task-%s.1' "$SPEC" "$1" ;;
  esac
}

# w_dir <home> <handle> — the worker's state directory.
w_dir() {
  case $rung in
    sj) printf '%s/streamjson/%s' "$1" "$2" ;;
    hl) printf '%s/headless/%s' "$1" "${2##*-task-}" ;;
  esac
}

# The pid files the rung records, and the one naming the re-exec.
w_pidfiles() {
  case $rung in
    sj) printf 'supervisor.pid worker.pid' ;;
    hl) printf 'pid' ;;
  esac
}

w_pidfile_primary() {
  case $rung in
    sj) printf 'supervisor.pid' ;;
    hl) printf 'pid' ;;
  esac
}

# w_launch <home> <rec> <handle> <prompt-file> <worktree> [VAR=val...] —
# detached; returns the launch's own exit code.
w_launch() {
  wl_home=$1
  wl_rec=$2
  wl_w=$3
  wl_p=$4
  wl_wt=$5
  shift 5
  case $rung in
    sj)
      renv "$wl_home" "$wl_rec" "$@" -- \
        launch "$wl_w" "$SPEC:4" --prompt-file "$wl_p" --cwd "$wl_wt" >/dev/null
      ;;
    hl)
      renv "$wl_home" "$wl_rec" "$@" -- \
        launch "$SPEC" "${wl_w##*-task-}" --worktree "$wl_wt" <"$wl_p" >/dev/null
      ;;
  esac
}

# w_finished <handle> <dir> <prompt-file> — a worker whose run has ended, in
# the cell's home and worktree. The stream-json one leaves a pending
# permission's attention row behind; the headless one leaves none of its own.
w_finished() {
  case $rung in
    sj)
      renv "$home" "$rec" SHIM_EVENTS="$ev_done" -- \
        launch "$1" "$SPEC:4" --prompt-file "$3" --cwd "$wt" --foreground \
        || fail "foreground launch exited non-zero"
      ;;
    hl)
      w_launch "$home" "$rec" "$1" "$3" "$wt" || fail "launch exited non-zero"
      wait_until 100 test -s "$2/exit" || fail "the one-shot never completed"
      ;;
  esac
}

# w_worker_pid <dir> — the worker process itself (the shim). The stream-json
# supervisor records it; the headless runner does not, and its one child is
# the worker, exec'd through the dispatch-env wrapper.
w_worker_pid() {
  case $rung in
    sj) cat "$1/worker.pid" 2>/dev/null ;;
    hl) first_child "$(cat "$1/pid" 2>/dev/null)" ;;
  esac
}

w_up() {
  case $rung in
    sj) test -s "$1/worker.pid" ;;
    hl) test -s "$1/pid" && [ -n "$(w_worker_pid "$1")" ] ;;
  esac
}

# w_recorded <dir> — every pid the rung's state records.
w_recorded() {
  for wr_f in $(w_pidfiles); do
    cat "$1/$wr_f" 2>/dev/null
  done
}

# w_occupy_attention <home> <handle> — make sure the worker has an attention
# row. The stream-json supervisor writes one for the pending permission the
# shim emits; a headless worker's comes from its hooks, which the shim has
# none of, so the row is planted the way those hooks write it.
w_occupy_attention() {
  case $rung in
    sj) : ;;
    hl) aenv "$1" heartbeat "$2" "$SPEC:${2##*-task-}" working >/dev/null ;;
  esac
  i=0
  while [ "$i" -lt 100 ] && [ "$(attention_rows "$1" "$2")" = 0 ]; do
    sleep 0.1
    i=$((i + 1))
  done
  [ "$(attention_rows "$1" "$2")" != 0 ]
}

# w_occupy_scratch <dir> — make sure the scratch class holds something. The
# stream-json supervisor's fifos already do; the headless rung's scratch is a
# staging temp that exists only mid-write, so one is planted.
w_occupy_scratch() {
  case $rung in
    sj) test -p "$1/in.fifo" ;;
    hl) : >"$1/.exit.planted" ;;
  esac
}

w_scratch_gone() {
  case $rung in
    sj) [ ! -p "$1/in.fifo" ] && [ ! -p "$1/out.fifo" ] ;;
    hl) [ ! -e "$1/.exit.planted" ] && [ ! -e "$1/exit.tmp" ] ;;
  esac
}

# w_durable_ok <home> <rec> <dir> <handle> — the record of the run survives.
w_durable_ok() {
  case $rung in
    sj)
      [ -s "$3/events.jsonl" ] || fail "the event-stream capture must survive a stop"
      [ -s "$3/journal" ] || fail "the receipt journal must survive a stop"
      [ -s "$3/session" ] || fail "the persisted session must survive a stop"
      ;;
    hl)
      [ -s "$3/prompt" ] || fail "the prompt must survive a stop"
      [ -s "$3/launched" ] || fail "the launch marker must survive a stop"
      [ -e "$3/result.json" ] || fail "the captured result must survive a stop"
      [ -e "$3/stderr.log" ] || fail "the captured stderr must survive a stop"
      wd_out=$(renv "$1" "$2" -- status "$SPEC" "${4##*-task-}")
      [ "$wd_out" = "completed 143" ] \
        || fail "a stopped unit must read as the runner's graceful completion, got: $wd_out"
      ;;
  esac
}

# w_terminated_ok <home> <rec> <handle> — a worker this close had to SIGKILL
# still reads as terminated rather than dead. Only the headless runner has a
# record to keep: its trap writes one when stopped gracefully, and the close
# writes the same one when the escalation left the runner no chance to.
w_terminated_ok() {
  case $rung in
    sj) : ;;
    hl)
      wt_out=$(renv "$1" "$2" -- status "$SPEC" "${3##*-task-}")
      [ "$wt_out" = "completed 143" ] \
        || fail "a unit the close had to kill must read completed 143, got: $wt_out"
      ;;
  esac
}

# w_partial_released — what c23's partial close releases before the attention
# class refuses: the stream-json supervisor's leftover fifos, and nothing on the
# headless rung, whose finished runner left no scratch and holds no process.
w_partial_released() {
  case $rung in
    sj) printf 'scratch' ;;
    hl) printf -- '-' ;;
  esac
}

# The worker's command shape, run by nobody's state directory.
w_decoy_args() {
  case $rung in
    sj) printf '%s\n' -p --input-format stream-json --output-format stream-json \
      --verbose --permission-prompt-tool stdio ;;
    hl) printf '%s\n' --print --output-format json ;;
  esac
}

# --- process-table helpers --------------------------------------------------

# ps_rows — one `<pid> <ppid> <args>` row per process, captured through a
# variable so an assertion's own `grep` is never in the snapshot it searches.
# Mirrors the scripts' degradation: without the fallback, a host whose `ps`
# rejects `-ww` yields an empty snapshot, and every "no process survives"
# assertion passes for the wrong reason.
ps_rows() {
  pr_out=$(ps -A -ww -o pid=,ppid=,args= 2>/dev/null) || pr_out=''
  case ${pr_out%%"
"*} in
    *[0-9]*) ;;
    *) pr_out=$(ps -A -o pid=,ppid=,args= 2>/dev/null) || pr_out='' ;;
  esac
  [ -n "$pr_out" ] || fail "ps_rows: this host produced no usable process table"
  printf '%s\n' "$pr_out"
}

# no_proc_under <dir> — true when no live process references <dir> in its argv.
# The emptiness is re-checked here because `fail` inside a command substitution
# only leaves the subshell.
no_proc_under() {
  np_snap=$(ps_rows) || fail "no_proc_under: this host produced no usable process table"
  [ -n "$np_snap" ] || fail "no_proc_under: this host produced no usable process table"
  ! printf '%s\n' "$np_snap" | grep -Fq -- "$1"
}

first_child() {
  [ -n "$1" ] || return 0
  fc_snap=$(ps_rows) || fail "first_child: this host produced no usable process table"
  printf '%s\n' "$fc_snap" | awk -v p="$1" '$2 == p { print $1; exit }'
}

# Every close assertion rests on the process table, and the helpers above are
# called through `wait_until`, which discards both streams. Prove the table is
# readable once, here, where the message survives.
ps_rows >/dev/null \
  || fail "this host produced no usable process table; the close assertions cannot run"

attention_rows() {
  ar_store="$1/attention/state"
  [ -f "$ar_store" ] || {
    echo 0
    return 0
  }
  awk -F "$tab" -v w="$2" '($1 "") == (w "") { n++ } END { print n + 0 }' "$ar_store"
}

wait_until() {
  wu_n=$1
  shift
  wu_i=0
  while [ "$wu_i" -lt "$wu_n" ]; do
    if "$@" >/dev/null 2>&1; then
      return 0
    fi
    sleep 0.1
    wu_i=$((wu_i + 1))
  done
  return 1
}

all_gone() {
  for ag_p in "$@"; do
    kill -0 "$ag_p" 2>/dev/null && return 1
  done
  return 0
}

# case_dirs <name> — a fresh home, record dir, and worktree for one cell.
case_dirs() {
  home="$tmp/$rung/h$1"
  rec="$tmp/$rung/r$1"
  wt="$tmp/$rung/wt$1"
  mkdir -p "$rec" "$wt"
}

# ---------------------------------------------------------------------------
c19() {
  case_dirs 19
  printf 'keep me\n' >"$wt/marker"
  wt_before=$(ls -A "$wt")
  w=$(w_name 19)
  d=$(w_dir "$home" "$w")
  printf 'hold open\n' >"$tmp/$rung/prompt19"
  w_launch "$home" "$rec" "$w" "$tmp/$rung/prompt19" "$wt" \
    SHIM_EVENTS="$ev_hold" SHIM_SLEEP=120 || fail "c19: detached launch exited non-zero"
  wait_until 100 w_up "$d" || fail "c19: the worker never came up"
  recorded=$(w_recorded "$d")
  wrk=$(w_worker_pid "$d")
  kid=''
  i=0
  while [ "$i" -lt 100 ]; do
    kid=$(first_child "$wrk")
    [ -n "$kid" ] && break
    sleep 0.1
    i=$((i + 1))
  done
  [ -n "$kid" ] || fail "c19: the worker's own child never appeared"
  w_occupy_attention "$home" "$w" || fail "c19: no attention record to release"
  w_occupy_scratch "$d" || fail "c19: no scratch to release"

  out=$(renv "$home" "$rec" -- stop "$w" --grace 2)
  rc=$?
  [ "$rc" = 0 ] || fail "c19: stop should exit 0 on a complete release, got rc=$rc ($out)"
  case $out in
    "stop $w stopped released="*) : ;;
    *) fail "c19: expected a stopped result, got: $out" ;;
  esac
  for cls in process scratch attention; do
    case ",${out#*released=}," in
      *",$cls,"*) : ;;
      *) fail "c19: the released set must name $cls, got: $out" ;;
    esac
  done
  # shellcheck disable=SC2086 # the pid lists are split on purpose
  wait_until 100 all_gone $recorded "$wrk" "$kid" \
    || fail "c19: the re-exec, the worker, and the worker's child must all be gone"
  wait_until 50 no_proc_under "$d" \
    || fail "c19: no process may still reference the worker's state directory"
  w_scratch_gone "$d" || fail "c19: the scratch temp must be released"
  [ "$(attention_rows "$home" "$w")" = 0 ] || fail "c19: the attention record must be released"
  w_durable_ok "$home" "$rec" "$d" "$w"
  [ "$(ls -A "$wt")" = "$wt_before" ] || fail "c19: the worktree's contents changed"
  [ "$(cat "$wt/marker")" = "keep me" ] || fail "c19: a worktree file was modified"
  echo "ok: [$rung] c19 stop terminates the tree, releases the runtime set, keeps the record and the worktree (REQ-B1.2, REQ-B1.4, REQ-A1.3)"
}

# ---------------------------------------------------------------------------
# c20_stop <n> <grace> — launch a TERM-ignoring worker, wait for its hold loop,
# stop it with <grace>, and leave the elapsed seconds in `elapsed`.
c20_stop() {
  w=$(w_name "$1")
  d=$(w_dir "$home" "$w")
  printf 'ignore term\n' >"$tmp/$rung/prompt$1"
  w_launch "$home" "$rec" "$w" "$tmp/$rung/prompt$1" "$wt" \
    SHIM_EVENTS="$ev_hold" SHIM_IGNORE_TERM=1 || fail "c20: detached launch exited non-zero"
  wait_until 100 w_up "$d" || fail "c20: the worker never came up"
  wrk=$(w_worker_pid "$d")
  # The shim installs its TERM handler only after emitting, and the hold loop's
  # own `sleep` child is the first thing that exists afterwards. Waiting for
  # that child is what proves the handler is in place.
  i=0
  while [ "$i" -lt 100 ] && [ -z "$(first_child "$wrk")" ]; do
    sleep 0.1
    i=$((i + 1))
  done
  [ -n "$(first_child "$wrk")" ] || fail "c20: the worker never reached its hold loop"
  started=$(date +%s)
  out=$(renv "$home" "$rec" -- stop "$w" --grace "$2")
  rc=$?
  elapsed=$(($(date +%s) - started))
  [ "$rc" = 0 ] || fail "c20: stop should exit 0 after escalating, got rc=$rc ($out)"
  wait_until 100 all_gone "$wrk" \
    || fail "c20: a worker ignoring SIGTERM must be SIGKILLed after the grace"
  wait_until 50 no_proc_under "$d" \
    || fail "c20: no process may still reference the state directory after the escalation"
  w_terminated_ok "$home" "$rec" "$w"
}

c20() {
  case_dirs 20
  c20_stop 20 1
  grep -q term "$rec/signals" 2>/dev/null \
    || fail "c20: SIGTERM must be sent before the escalation"
  [ "$elapsed" -ge 1 ] || fail "c20: the grace must elapse before SIGKILL, took ${elapsed}s"
  short=$elapsed
  # The close must wait out the grace it was *given*, not a fixed one: two
  # closes at different graces show it, immune to how fast the host is.
  c20_stop 201 4
  [ $((elapsed - short)) -ge 2 ] \
    || fail "c20: --grace must set the wait; 1s took ${short}s and 4s took ${elapsed}s"
  # The difference pins that --grace is read; this pins the unit. Set far above
  # any plausible scheduling delay, since the suite runs beside the whole gate.
  [ "$elapsed" -lt 120 ] || fail "c20: a 4s grace should not take ${elapsed}s"
  echo "ok: [$rung] c20 SIGTERM first, SIGKILL after the grace the caller set (REQ-B1.2)"
}

# ---------------------------------------------------------------------------
c21() {
  case_dirs 21
  # The decoy: the worker's exact command shape, belonging to nobody's state
  # directory.
  decoy_args=()
  while IFS= read -r a; do decoy_args+=("$a"); done <<EOF
$(w_decoy_args)
EOF
  env SHIM_RECORD_DIR="$rec" SHIM_READ_FIRST=0 SHIM_SLEEP=120 \
    "$tmp/bin/claude" "${decoy_args[@]}" </dev/null >/dev/null 2>&1 &
  decoy=$!
  w=$(w_name 21)
  d=$(w_dir "$home" "$w")
  printf 'decoy neighbour\n' >"$tmp/$rung/prompt21"
  w_launch "$home" "$rec" "$w" "$tmp/$rung/prompt21" "$wt" \
    SHIM_EVENTS="$ev_hold" SHIM_SLEEP=120 || fail "c21: detached launch exited non-zero"
  wait_until 100 w_up "$d" || fail "c21: the worker never came up"
  wrk=$(w_worker_pid "$d")
  kill -0 "$decoy" 2>/dev/null || fail "c21: the decoy session did not start"
  renv "$home" "$rec" -- stop "$w" --grace 2 >/dev/null || fail "c21: stop exited non-zero"
  wait_until 100 all_gone "$wrk" || fail "c21: the worker must be terminated"
  kill -0 "$decoy" 2>/dev/null \
    || fail "c21: the operator session sharing the worker's command shape must survive"
  decoy_kid=$(first_child "$decoy")
  kill -9 "$decoy" 2>/dev/null
  [ -z "$decoy_kid" ] || kill -9 "$decoy_kid" 2>/dev/null
  wait "$decoy" 2>/dev/null
  # A sibling whose handle and state directory this one's are a prefix of. An
  # unanchored search for the directory finds its re-exec — and then kills a
  # healthy unrelated worker's whole tree.
  ws=$(w_sibling 21)
  ds=$(w_dir "$home" "$ws")
  printf 'prefix sibling\n' >"$tmp/$rung/prompt21x"
  w_launch "$home" "$rec" "$ws" "$tmp/$rung/prompt21x" "$wt" \
    SHIM_EVENTS="$ev_hold" SHIM_SLEEP=120 || fail "c21: the prefix-sibling launch exited non-zero"
  wait_until 100 w_up "$ds" || fail "c21: the sibling never came up"
  sib_recorded=$(w_recorded "$ds")
  sib_wrk=$(w_worker_pid "$ds")
  out=$(renv "$home" "$rec" -- stop "$w" --grace 2)
  [ "$out" = "stop $w already-closed" ] \
    || fail "c21: the already-closed worker must stay closed, got: $out"
  for p in $sib_recorded $sib_wrk; do
    kill -0 "$p" 2>/dev/null \
      || fail "c21: a worker whose handle merely extends the stopped one must survive (pid $p)"
  done
  renv "$home" "$rec" -- stop "$ws" --grace 2 >/dev/null || fail "c21: sibling stop failed"
  echo "ok: [$rung] c21 state-directory matching spares a look-alike session and a prefix sibling (REQ-B1.3)"
}

# The source audit is rung-independent in what it reads — the shared kill path
# and every rung's match — so it runs once rather than per rung.
c21_audit() {
  audit=$(
    awk '/^stop_candidates\(\)/, /^}/' "$LIB"
    awk '/^stop_self_hosted\(\)/, /^}/' "$LIB"
    awk '/^release_processes\(\)/, /^}/' "$LIB"
    awk '/^stop_match\(\)/, /^}/' "$SJ" "$FDH"
    awk '/^stop_seedfiles\(\)/, /^}/' "$FDH"
    grep -h '^stop_pidfiles=' "$SJ"
  )
  [ -n "$audit" ] || fail "c21: the kill path was not found for the audit"
  for want in SC_MATCH stop_seeds '_supervise' 'run-worker' 'supervisor.pid' "printf 'pid'"; do
    printf '%s\n' "$audit" | grep -qF -- "$want" \
      || fail "c21: the kill path must key on the state directory and its pid files (missing '$want')"
  done
  for bad in claude pgrep killall pkill 'input-format' 'output-format' 'permission-prompt-tool' '--print'; do
    printf '%s\n' "$audit" | grep -qF -- "$bad" \
      && fail "c21: the kill path must not match on '$bad' (name or command-pattern matching)"
  done
  echo "ok: c21 source audit: the shared kill path and both rungs' matches key on the state directory only (REQ-B1.3)"
}

# ---------------------------------------------------------------------------
c22() {
  case_dirs 22
  w=$(w_name 22)
  d=$(w_dir "$home" "$w")
  printf 'idempotent\n' >"$tmp/$rung/prompt22"
  w_launch "$home" "$rec" "$w" "$tmp/$rung/prompt22" "$wt" \
    SHIM_EVENTS="$ev_hold" SHIM_IGNORE_TERM=1 || fail "c22: detached launch exited non-zero"
  wait_until 100 w_up "$d" || fail "c22: the worker never came up"
  renv "$home" "$rec" -- stop "$w" --grace 1 >/dev/null || fail "c22: the first stop failed"
  # The shim records every SIGTERM it survives. A repeat stop that re-signalled
  # the stale recorded pids would add to that file.
  before=$(wc -l <"$rec/signals" 2>/dev/null || echo 0)
  out=$(renv "$home" "$rec" -- stop "$w" --grace 2)
  rc=$?
  after=$(wc -l <"$rec/signals" 2>/dev/null || echo 0)
  [ "$rc" = 0 ] || fail "c22: a repeat stop must succeed, got rc=$rc ($out)"
  [ "$out" = "stop $w already-closed" ] \
    || fail "c22: a repeat stop must return the distinct already-closed result, got: $out"
  [ "$before" = "$after" ] || fail "c22: a repeat stop must send no signal"
  w_terminated_ok "$home" "$rec" "$w"
  echo "ok: [$rung] c22 a repeat close returns already-closed and signals nothing (REQ-B1.7)"

  # c22c, against the closed worker above: the lock class where the rung has
  # one, and the refusals every rung shares.
  case $rung in
    sj)
      mkdir -p "$d/launch.lock" || fail "c22c: cannot plant the lock"
      out=$(renv "$home" "$rec" -- stop "$w" --grace 2)
      rc=$?
      [ "$rc" = 0 ] || fail "c22c: stop should release a stranded lock, got rc=$rc ($out)"
      [ "$out" = "stop $w stopped released=locks" ] \
        || fail "c22c: the lock class must be released and named, got: $out"
      [ ! -e "$d/launch.lock" ] || fail "c22c: the stranded lock must be gone"
      ;;
    hl)
      echo "skip: [hl] c22c lock leg: the headless rung takes no lock of its own (its row of the floor's rung table)"
      ;;
  esac
  # A handle the rung could not have printed: a path separator is outside
  # both grammars.
  renv "$home" "$rec" -- stop "not/a-handle" >/dev/null 2>&1
  [ $? -eq 2 ] || fail "c22c: a malformed handle must be refused (exit 2)"
  renv "$home" "$rec" -- stop "$(w_name 999)" >/dev/null 2>&1
  [ $? -eq 2 ] || fail "c22c: an unknown handle must be refused (exit 2), never already-closed"
  renv "$home" "$rec" -- stop "$w" --grace 0 >/dev/null 2>&1
  [ $? -eq 2 ] || fail "c22c: --grace 0 must be refused"
  renv "$home" "$rec" -- stop "$w" --grace 99999999 >/dev/null 2>&1
  [ $? -eq 2 ] || fail "c22c: an out-of-range --grace must be refused"
  echo "ok: [$rung] c22c bad handles and graces are refused (REQ-A1.3)"
}

# ---------------------------------------------------------------------------
c22b() {
  case_dirs 22b
  w=$(w_name 222)
  d=$(w_dir "$home" "$w")
  printf 'stubborn grandchild\n' >"$tmp/$rung/prompt22b"
  w_launch "$home" "$rec" "$w" "$tmp/$rung/prompt22b" "$wt" \
    SHIM_EVENTS="$ev_hold" SHIM_SLEEP=120 SHIM_STUBBORN_CHILD="$rec/stubborn.pid" \
    || fail "c22b: detached launch exited non-zero"
  wait_until 100 test -s "$rec/stubborn.pid" || fail "c22b: the stubborn grandchild never started"
  stubborn=$(cat "$rec/stubborn.pid")
  kill -0 "$stubborn" 2>/dev/null || fail "c22b: the stubborn grandchild is not running"
  wait_until 100 w_up "$d" || fail "c22b: the worker never came up"
  [ "$stubborn" != "$(w_worker_pid "$d")" ] \
    || fail "c22b: the grandchild pid must not be the worker's own"
  # It must also be invisible to a state-directory match, so that only the
  # accumulated target set can account for it once it reparents.
  stub_args=$(ps -p "$stubborn" -o args= 2>/dev/null)
  [ -n "$stub_args" ] || fail "c22b: cannot read the grandchild's argv to check it"
  case $stub_args in
    *"$d"*) fail "c22b: the grandchild must not carry the state dir in its argv" ;;
  esac
  out=$(renv "$home" "$rec" -- stop "$w" --grace 1)
  rc=$?
  [ "$rc" = 0 ] || fail "c22b: stop should close the whole tree, got rc=$rc ($out)"
  case $out in
    "stop $w stopped released="*) : ;;
    *) fail "c22b: expected a stopped result, got: $out" ;;
  esac
  wait_until 100 all_gone "$stubborn" \
    || fail "c22b: a reparented grandchild must not survive a close that reports success"
  wait_until 50 no_proc_under "$d" || fail "c22b: the state directory is still referenced"
  echo "ok: [$rung] c22b a reparented SIGTERM-surviving grandchild is still closed (REQ-B1.2)"
}

# ---------------------------------------------------------------------------
c22d() {
  case_dirs 22d
  w=$(w_name 224)
  d=$(w_dir "$home" "$w")
  printf 'self close\n' >"$tmp/$rung/prompt22d"
  w_launch "$home" "$rec" "$w" "$tmp/$rung/prompt22d" "$wt" \
    SHIM_EVENTS="$ev_hold" SHIM_SLEEP=120 \
    SHIM_SELF_CLOSE="/bin/sh '$(rung_script)' stop $w --grace 2" \
    SHIM_SELF_CLOSE_WHEN="$rec/go" || fail "c22d: detached launch exited non-zero"
  wait_until 100 w_up "$d" || fail "c22d: the worker never came up"
  recorded=$(w_recorded "$d")
  wrk=$(w_worker_pid "$d")
  : >"$rec/go"
  wait_until 100 test -s "$rec/selfclose.rc" || fail "c22d: the self-close never ran"
  [ "$(cat "$rec/selfclose.rc")" = 3 ] \
    || fail "c22d: a self-close must be refused (exit 3), got $(cat "$rec/selfclose.rc"): $(cat "$rec/selfclose.out")"
  grep -q 'from inside its own process tree' "$rec/selfclose.out" \
    || fail "c22d: the refusal must be the self-close one, got: $(cat "$rec/selfclose.out")"
  # Refused means nothing was touched: the tree is intact, the pid files that
  # stop a second launch are still there, and the second launch is refused.
  for p in $recorded $wrk; do
    kill -0 "$p" 2>/dev/null || fail "c22d: the refused close killed pid $p"
  done
  for f in $(w_pidfiles); do
    [ -s "$d/$f" ] || fail "c22d: the refused close cleared $f"
  done
  [ "$rung" != sj ] || [ -p "$d/in.fifo" ] || fail "c22d: the refused close deleted the worker's channel"
  w_launch "$home" "$rec" "$w" "$tmp/$rung/prompt22d" "$wt" \
    SHIM_EVENTS="$ev_hold" SHIM_SLEEP=120 2>/dev/null
  [ $? -eq 3 ] || fail "c22d: a launch over the still-live worker must still be refused"
  renv "$home" "$rec" -- stop "$w" --grace 2 >/dev/null || fail "c22d: the outside close failed"
  # shellcheck disable=SC2086 # the pid list is split on purpose
  wait_until 100 all_gone $recorded || fail "c22d: the re-exec survived the outside close"
  echo "ok: [$rung] c22d a close from inside the worker's own tree is refused (REQ-B1.3)"
}

# selfpid_close <home> <rec> <pidfile> <handle> [env=val...] — run `stop` from a
# wrapper that records its own pid into <pidfile> and then execs, so the
# recorded pid is the closing process itself: an ancestor of the closer that
# has no other descendants to be signalled for real.
# shellcheck disable=SC2016 # $$/$1/$@ belong to the inner shell
selfpid_close() {
  spc_home=$1
  spc_rec=$2
  spc_file=$3
  spc_w=$4
  shift 4
  env "${env_scrub[@]}" "$@" \
    PLANWRIGHT_FLEET_STATE_DIR="$spc_home" \
    PLANWRIGHT_HEADLESS_STATE_DIR="$spc_home/headless" \
    PLANWRIGHT_STREAMJSON_CLI="$tmp/bin/claude" \
    PLANWRIGHT_HEADLESS_CLAUDE="$tmp/bin/claude" \
    SHIM_RECORD_DIR="$spc_rec" \
    /bin/sh -c 'printf "%s\n" "$$" >"$1"; shift; exec "$@"' _ \
    "$spc_file" /bin/sh "$(rung_script)" stop "$spc_w" --grace 2 2>&1
}

c22efg() {
  case_dirs 22e
  pf=$(w_pidfile_primary)
  # c22e: on a host whose `ps` gives full argv, a recorded pid that is an
  # ancestor of the closer is a recycled pid, not a self-close. Refusing on one
  # would wedge the handle forever, since `stop` is what clears the file.
  w=$(w_name 225)
  d=$(w_dir "$home" "$w")
  mkdir -p "$d" || fail "c22e: cannot plant the state dir"
  out=$(selfpid_close "$home" "$rec" "$d/$pf" "$w")
  rc=$?
  [ "$rc" != 3 ] || fail "c22e: a recorded pid that is an ancestor must not read as a self-close: $out"
  [ "$rc" = 0 ] || fail "c22e: the close should have succeeded, got rc=$rc ($out)"
  # The stream-json close counts a pid file recording nothing live as residue
  # and clears it, or the handle stays wedged; the headless close never counts
  # it (the file is that rung's record), so nothing is left to wedge.
  case $rung in
    sj) [ ! -e "$d/$pf" ] || fail "c22e: the close must clear the stale pid file, or the handle stays wedged" ;;
    hl) [ "$out" = "stop $w already-closed" ] || fail "c22e: a pid file alone holds nothing here, got: $out" ;;
  esac
  echo "ok: [$rung] c22e a recorded pid in the closer's ancestry is not a self-close (REQ-B1.3)"

  # c22f: on a host whose `ps` truncates argv, a missing match is not evidence
  # of absence, so the recorded pids are consulted and the close fails closed.
  mkdir -p "$tmp/narrowbin"
  cat >"$tmp/narrowbin/ps" <<'NPS'
#!/bin/sh
for a in "$@"; do
  case $a in
    -ww) exit 1 ;;
  esac
done
/bin/ps "$@" | cut -c1-40
NPS
  chmod +x "$tmp/narrowbin/ps"
  w=$(w_name 226)
  d=$(w_dir "$home" "$w")
  mkdir -p "$d" || fail "c22f: cannot plant the state dir"
  out=$(selfpid_close "$home" "$rec" "$d/$pf" "$w" PATH="$tmp/narrowbin:$PATH")
  rc=$?
  [ "$rc" = 3 ] \
    || fail "c22f: with truncated argv the recorded pid must fail closed (exit 3), got rc=$rc ($out)"
  case $out in
    *'from inside its own process tree'*) : ;;
    *) fail "c22f: wrong refusal: $out" ;;
  esac
  echo "ok: [$rung] c22f a truncated-argv host consults the recorded pids and fails closed (REQ-B1.3)"

  # c22g: a process table that cannot be read at all refuses the close.
  mkdir -p "$tmp/deadbin"
  printf '#!/bin/sh\nexit 1\n' >"$tmp/deadbin/ps"
  chmod +x "$tmp/deadbin/ps"
  w=$(w_name 227)
  d=$(w_dir "$home" "$w")
  mkdir -p "$d" || fail "c22g: cannot plant the state dir"
  out=$(selfpid_close "$home" "$rec" "$d/$pf" "$w" PATH="$tmp/deadbin:$PATH")
  rc=$?
  [ "$rc" = 2 ] \
    || fail "c22g: an unreadable process table must refuse the close (exit 2), got rc=$rc ($out)"
  [ -e "$d/$pf" ] || fail "c22g: a refused close must not have cleared the pid file"
  echo "ok: [$rung] c22g an unreadable process table refuses rather than proceeds (REQ-B1.3)"

  # c22h: a pid file the worker replaced with a fifo cannot hang the close. A
  # blocking read there would stall `stop` before it sent a single signal.
  w=$(w_name 228)
  d=$(w_dir "$home" "$w")
  mkdir -p "$d" || fail "c22h: cannot plant the state dir"
  mkfifo "$d/$pf" || fail "c22h: cannot plant the fifo"
  # The headless close reads its pid file only on a host whose `ps` truncates
  # argv, so that rung runs this leg on the narrow shim c22f built; on a full
  # `ps` it would pass without ever opening the fifo.
  c22h_path=$PATH
  [ "$rung" != hl ] || c22h_path="$tmp/narrowbin:$PATH"
  PATH=$c22h_path renv "$home" "$rec" -- stop "$w" --grace 1 >"$rec/c22h.out" 2>&1 &
  closer=$!
  wait_until 200 sh -c "! kill -0 $closer 2>/dev/null" || {
    kill -9 "$closer" 2>/dev/null
    : >"$d/$pf" &
    fail "c22h: a fifo at the pid file hung the close"
  }
  wait "$closer" || fail "c22h: the close failed: $(cat "$rec/c22h.out")"
  # The headless close also reads the unit's launch marker, to tell its own run
  # from a relaunch; the stream-json rung keeps no such marker.
  if [ "$rung" = hl ]; then
    w=$(w_name 229)
    d=$(w_dir "$home" "$w")
    mkdir -p "$d" || fail "c22h: cannot plant the state dir"
    mkfifo "$d/launched" || fail "c22h: cannot plant the marker fifo"
    renv "$home" "$rec" -- stop "$w" --grace 1 >"$rec/c22h2.out" 2>&1 &
    closer=$!
    wait_until 200 sh -c "! kill -0 $closer 2>/dev/null" || {
      kill -9 "$closer" 2>/dev/null
      : >"$d/launched" &
      fail "c22h: a fifo at the launch marker hung the close"
    }
    wait "$closer" || fail "c22h: the close failed: $(cat "$rec/c22h2.out")"
  fi
  echo "ok: [$rung] c22h a fifo planted at the pid file does not hang the close (REQ-B1.3)"
}

# ---------------------------------------------------------------------------
c23() {
  if [ "$(id -u)" = 0 ]; then
    echo "skip: [$rung] c23 partial-close injection needs a non-root user (running as root)"
    return 0
  fi
  case_dirs 23
  w=$(w_name 23)
  d=$(w_dir "$home" "$w")
  printf 'partial close\n' >"$tmp/$rung/prompt23"
  w_finished "$w" "$d" "$tmp/$rung/prompt23"
  w_occupy_attention "$home" "$w" || fail "c23: no attention record to withhold"
  # An unwritable attention store: `clear` fails, the row stays held.
  chmod 500 "$home/attention" || fail "c23: cannot make the attention store unwritable"
  out=$(renv "$home" "$rec" -- stop "$w" --grace 2 2>/dev/null)
  rc=$?
  chmod 700 "$home/attention" || fail "c23: cannot restore the attention store"
  [ "$rc" = 6 ] || fail "c23: a partial close must report the partial exit code, got rc=$rc ($out)"
  [ "$out" = "stop $w partial released=$(w_partial_released) held=attention" ] \
    || fail "c23: expected the released and held sets named exactly, got: $out"
  [ "$(attention_rows "$home" "$w")" != 0 ] || fail "c23: the withheld class must still be held"
  # The retry takes exactly the class still held — and is not already-closed.
  out=$(renv "$home" "$rec" -- stop "$w" --grace 2)
  rc=$?
  [ "$rc" = 0 ] || fail "c23: the retry should complete the release, got rc=$rc ($out)"
  [ "$out" = "stop $w stopped released=attention" ] \
    || fail "c23: the retry must take exactly the class still held, got: $out"
  [ "$(attention_rows "$home" "$w")" = 0 ] || fail "c23: the retry must release the class"
  out=$(renv "$home" "$rec" -- stop "$w" --grace 2)
  [ "$out" = "stop $w already-closed" ] \
    || fail "c23: only a fully released worker reports already-closed, got: $out"
  if [ "$rung" = hl ]; then
    out=$(renv "$home" "$rec" -- status "$SPEC" 23)
    [ "$out" = "completed 0" ] || fail "c23: the runner's own exit must survive the close, got: $out"
  fi
  echo "ok: [$rung] c23 a partial close reports partial and the retry drains what is still held (REQ-A1.3, REQ-B1.7)"
}

# ---------------------------------------------------------------------------
# c40 (REQ-B1.3, REQ-B1.7): a unit whose run already ended keeps its own record,
#     and the pid its state still names is never a seed. The headless runner
#     leaves its pid file behind on every normal completion, so the host is free
#     to reissue that pid to anything, including an operator's own session.
#     The stream-json supervisor removes its pid files when it ends, so the
#     completed-unit leg has no counterpart there; a pid left by a crash is the
#     pid binding the floor records as open work on both rungs.
c40() {
  case $rung in
    sj)
      echo "skip: [sj] c40 the supervisor removes its own pid files when a run ends; a crash-left pid is the floor's open pid-binding work"
      return 0
      ;;
  esac
  case_dirs 40
  # (a) A completed unit whose recorded pid now names a live stranger.
  w=$(w_name 40)
  d=$(w_dir "$home" "$w")
  printf 'done\n' >"$tmp/$rung/prompt40"
  w_launch "$home" "$rec" "$w" "$tmp/$rung/prompt40" "$wt" || fail "c40: launch exited non-zero"
  wait_until 100 test -s "$d/exit" || fail "c40: the one-shot never completed"
  sleep 120 &
  stranger=$!
  strangers="$strangers $stranger"
  printf '%s\n' "$stranger" >"$d/pid"
  out=$(renv "$home" "$rec" -- stop "$w" --grace 1)
  rc=$?
  kill -0 "$stranger" 2>/dev/null || fail "c40: a close signalled the stranger its stale pid file named"
  kill "$stranger" 2>/dev/null
  wait "$stranger" 2>/dev/null
  [ "$rc" = 0 ] || fail "c40: stop on a finished unit should succeed, got rc=$rc ($out)"
  [ "$out" = "stop $w already-closed" ] \
    || fail "c40: a finished unit holds no process, got: $out"
  out=$(renv "$home" "$rec" -- status "$SPEC" 40)
  [ "$out" = "completed 0" ] || fail "c40: the runner's own record must survive a close, got: $out"
  # (b) A runner that died with no record keeps its death verdict: a close that
  #     signalled nothing has no termination to record.
  w=$(w_name 401)
  d=$(w_dir "$home" "$w")
  printf 'die\n' >"$tmp/$rung/prompt401"
  w_launch "$home" "$rec" "$w" "$tmp/$rung/prompt401" "$wt" SHIM_SLEEP=120 \
    || fail "c40: launch exited non-zero"
  wait_until 100 w_up "$d" || fail "c40: the worker never came up"
  runner=$(cat "$d/pid")
  wrk=$(w_worker_pid "$d")
  kid=$(first_child "$wrk")
  kill -9 "$runner" "$wrk" ${kid:+"$kid"} 2>/dev/null
  wait_until 100 all_gone "$runner" "$wrk" || fail "c40: the planted death did not take"
  out=$(renv "$home" "$rec" -- status "$SPEC" 401)
  case $out in
    "died $runner") : ;;
    *) fail "c40: expected the death verdict before the close, got: $out" ;;
  esac
  out=$(renv "$home" "$rec" -- stop "$w" --grace 1)
  [ "$out" = "stop $w already-closed" ] || fail "c40: a dead runner holds no process, got: $out"
  out=$(renv "$home" "$rec" -- status "$SPEC" 401)
  [ "$out" = "died $runner" ] || fail "c40: a close must not rewrite a death as a completion, got: $out"
  # (c) That dead runner's pid, reissued by the host. A death leaves no record,
  #     so a record cannot be what keeps the pid from seeding the close; a host
  #     whose `ps` reads argv in full is. A host whose `ps` truncates it seeds
  #     from the file by design, since nothing else finds a live runner there.
  if ! ps -A -ww -o pid=,ppid=,args= >/dev/null 2>&1; then
    echo "skip: [$rung] c40 reissued-pid leg: this host's ps truncates argv, where the pid file is the only seed by design"
  else
    sleep 120 &
    stranger=$!
    strangers="$strangers $stranger"
    printf '%s\n' "$stranger" >"$d/pid"
    out=$(renv "$home" "$rec" -- stop "$w" --grace 1)
    kill -0 "$stranger" 2>/dev/null \
      || fail "c40: a close signalled the stranger a dead runner's pid file named"
    [ "$out" = "stop $w already-closed" ] || fail "c40: a reissued pid holds nothing of the unit's, got: $out"
  fi
  echo "ok: [$rung] c40 a finished or dead unit keeps its record, and where argv is readable its stale pid is never signalled (REQ-B1.3, REQ-B1.7)"
}

# ---------------------------------------------------------------------------
# c32 (REQ-A1.3): when the attention probe cannot ANSWER, the class counts as
#     held. The walk reads any non-zero as "not held" and skips the class, so
#     an awk that failed outright would drop attention from the release set
#     and let the close report a success it never earned.
c32() {
  case_dirs 32
  w=$(w_name 32)
  d=$(w_dir "$home" "$w")
  printf 'held probe\n' >"$tmp/$rung/prompt32"
  w_finished "$w" "$d" "$tmp/$rung/prompt32"
  w_occupy_attention "$home" "$w" || fail "c32: no attention record to probe"
  # Fails only on the attention store: a shim failing for everything would stop
  # the close at its process-table read instead, which fails closed for a
  # different reason and would prove nothing about this one.
  mkdir -p "$tmp/$rung/bin32"
  c32_awk=$(command -v awk) || fail "c32: no awk to delegate to"
  cat >"$tmp/$rung/bin32/awk" <<AWKFAIL
#!/bin/sh
for a in "\$@"; do
  case \$a in *attention*) exit 2 ;; esac
done
exec $c32_awk "\$@"
AWKFAIL
  chmod +x "$tmp/$rung/bin32/awk"
  PATH="$tmp/$rung/bin32:$PATH" awk 'BEGIN { exit 0 }' </dev/null 2>/dev/null \
    || fail "c32: the shim broke ordinary awk — it must only fail on the attention store"
  PATH="$tmp/$rung/bin32:$PATH" awk '{ print }' "$home/attention" >/dev/null 2>&1
  [ "$?" = 2 ] || fail "c32: the shim does not fail on the attention store — this case would prove nothing"
  rc=0
  out=$(PATH="$tmp/$rung/bin32:$PATH" renv "$home" "$rec" -- stop "$w" --grace 1 2>&1) || rc=$?
  case $out in
    *"held="*attention*) : ;;
    *) fail "c32: an unanswerable attention probe should hold the class, got: $out" ;;
  esac
  # The exit code too: asserting the wording alone would let a regression that
  # reported success alongside a held class pass.
  [ "$rc" = 6 ] || fail "c32: a partial close must exit 6, got $rc: $out"
  echo "ok: [$rung] c32 an attention probe that cannot answer counts as held (REQ-A1.3)"
}

# ---------------------------------------------------------------------------
# c41 (REQ-B1.3, REQ-B1.4): the headless rung's default layout, where the unit's
#     state lives under its own spec bundle. Every other cell pins the state base
#     through the environment, which keys the directory on the task id alone.
#     Here the spec half of the handle has to matter, the state path the close
#     deletes inside is refused when it is a symlink, and a handle the rung could
#     not have printed is refused before it resolves anything.
c41() {
  case $rung in
    sj)
      echo "skip: [sj] c41 the stream-json state lives under the fleet home by handle alone; it has no spec layout to resolve"
      return 0
      ;;
  esac
  case_dirs 41
  repo="$tmp/$rung/repo41"
  mkdir -p "$repo/specs/$SPEC" "$repo/specs/other"
  # denv — the rung with the state base left to its default.
  denv() {
    env "${env_scrub[@]}" -u PLANWRIGHT_HEADLESS_STATE_DIR \
      PLANWRIGHT_FLEET_STATE_DIR="$home" \
      PLANWRIGHT_HEADLESS_CLAUDE="$tmp/bin/claude" \
      SHIM_RECORD_DIR="$rec" SHIM_SLEEP=120 /bin/sh "$FDH" "$@"
  }
  w=$(w_name 41)
  d="$repo/specs/$SPEC/.orchestrate/headless/41"
  printf 'default layout\n' | denv launch "$SPEC" 41 --worktree "$wt" --repo-root "$repo" \
    >/dev/null || fail "c41: launch in the default layout exited non-zero"
  wait_until 100 w_up "$d" || fail "c41: the worker never came up"
  runner=$(cat "$d/pid")
  denv stop "headless-other-task-41" --repo-root "$repo" --grace 1 >/dev/null 2>&1
  [ $? -eq 2 ] || fail "c41: another spec's handle for the same task id must be unknown (exit 2)"
  kill -0 "$runner" 2>/dev/null || fail "c41: a close for another spec's handle reached this unit"
  out=$(denv stop "$w" --repo-root "$repo" --grace 1)
  case $out in
    "stop $w stopped released=process"*) : ;;
    *) fail "c41: expected the default-layout close to stop the runner, got: $out" ;;
  esac
  wait_until 100 all_gone "$runner" || fail "c41: the runner survived its close"
  out=$(denv status "$SPEC" 41 --repo-root "$repo")
  [ "$out" = "completed 143" ] || fail "c41: the closed unit must read completed 143, got: $out"

  # A symlinked unit directory: refused, and the directory it points at keeps
  # everything a close would have deleted or written there.
  mkdir -p "$tmp/$rung/elsewhere42"
  : >"$tmp/$rung/elsewhere42/exit.tmp"
  ln -s "$tmp/$rung/elsewhere42" "$repo/specs/$SPEC/.orchestrate/headless/42" \
    || fail "c41: cannot plant the symlink"
  out=$(denv stop "$(w_name 42)" --repo-root "$repo" --grace 1 2>&1)
  rc=$?
  [ "$rc" = 2 ] || fail "c41: a symlinked state dir must be refused (exit 2), got rc=$rc ($out)"
  case $out in
    *"path-escape guard"*) : ;;
    *) fail "c41: the refusal must be the path-escape one, got: $out" ;;
  esac
  [ -e "$tmp/$rung/elsewhere42/exit.tmp" ] || fail "c41: the refused close deleted through the symlink"
  [ ! -e "$tmp/$rung/elsewhere42/exit" ] || fail "c41: the refused close wrote through the symlink"

  # Handles the rung could not have printed.
  for bad in "$SPEC-task-41" "headless-$SPEC-task-" "headless-$SPEC-task-4/1" \
    "headless--task-41" "headless-$SPEC-task-41x"; do
    out=$(denv stop "$bad" --repo-root "$repo" 2>&1)
    rc=$?
    [ "$rc" = 2 ] || fail "c41: handle '$bad' must be refused (exit 2), got rc=$rc ($out)"
    case $out in
      *"invalid worker handle"*) : ;;
      *) fail "c41: handle '$bad' must be refused as malformed, got: $out" ;;
    esac
  done
  echo "ok: [$rung] c41 the default layout keys on the spec, refuses a symlinked state dir and a malformed handle (REQ-B1.3, REQ-B1.4)"
}

# ---------------------------------------------------------------------------
# c42: a missing close library costs `stop` and no other verb. On the headless
#     rung `status` is a verdict channel whose exit codes callers act on, and an
#     exit 2 there would read as a usage error rather than any verdict.
c42() {
  case_dirs 42
  nolib="$tmp/$rung/scripts-nolib"
  cp -R "$here/../scripts" "$nolib" || fail "c42: cannot copy the scripts"
  rm -f "$nolib/fleet-stop-lib.sh"
  case $rung in
    sj)
      out=$(env "${env_scrub[@]}" PLANWRIGHT_FLEET_STATE_DIR="$home" \
        /bin/sh "$nolib/fleet-streamjson.sh" status sjw42 2>&1)
      case $out in
        *fleet-stop-lib*) fail "c42: status failed on the missing close library: $out" ;;
      esac
      out=$(env "${env_scrub[@]}" PLANWRIGHT_FLEET_STATE_DIR="$home" \
        /bin/sh "$nolib/fleet-streamjson.sh" stop sjw42 2>&1)
      rc=$?
      ;;
    hl)
      out=$(env "${env_scrub[@]}" PLANWRIGHT_HEADLESS_STATE_DIR="$home/headless" \
        /bin/sh "$nolib/fleet-dispatch-headless.sh" status "$SPEC" 42 2>&1)
      [ "$out" = absent ] || fail "c42: status must still answer its verdict, got: $out"
      out=$(env "${env_scrub[@]}" PLANWRIGHT_HEADLESS_STATE_DIR="$home/headless" \
        PLANWRIGHT_FLEET_STATE_DIR="$home" \
        /bin/sh "$nolib/fleet-dispatch-headless.sh" stop "$(w_name 42)" 2>&1)
      rc=$?
      ;;
  esac
  [ "$rc" = 2 ] || fail "c42: stop without its library must refuse (exit 2), got rc=$rc ($out)"
  case $out in
    *fleet-stop-lib*) : ;;
    *) fail "c42: the refusal must name the missing library, got: $out" ;;
  esac
  echo "ok: [$rung] c42 a missing close library costs stop and no other verb"
}

# run_table <rung> — every cell against one rung. STOP_CELLS narrows the run to
# the named cells for local debugging; a narrowed run says so, since it would
# otherwise pass exactly as the full table does.
run_table() {
  rung=$1
  mkdir -p "$tmp/$rung"
  if [ -n "${STOP_CELLS:-}" ]; then
    echo "skip: [$rung] every cell but '$STOP_CELLS' (narrowed by STOP_CELLS)"
  fi
  for cell in ${STOP_CELLS:-c19 c20 c21 c22 c22b c22d c22efg c23 c32 c40 c41 c42}; do
    "$cell"
  done
}
