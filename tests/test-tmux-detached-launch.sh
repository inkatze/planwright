#!/bin/bash
# The tmux rung's detached launch, on the launch fixture harness
# (tests/lib/tmux-launch-harness.sh): its stub tmux runs a session's command
# with the stub server's environment, whose pinned values are decoys here, and
# its stub worker records the argv, directory, and environment it started with.
# Every launch runs under the harness's bounded runner.
#   l1  a task dispatch returns within the bound while its worker keeps
#       running, reports started-unconfirmed, and creates the session detached
#       in the physical placed worktree with remain-on-exit off, moving no
#       client; the worker takes no --worktree or --tmux and carries the pin,
#       the dispatcher's root and fleet home, the launch token, and the
#       registry record's handle and scope; the registry's death handle is the
#       session-creation output; a liveness hook run with the worker's
#       environment records a transition for its handle (REQ-F1.1-F1.5,
#       REQ-G1.2, REQ-G1.6, REQ-H1.2)
#   l2  a flight dispatch does the same for a flight's identity, names the
#       session from the launch's report line, treats started-unconfirmed as
#       placed, and releases its lock: a second dispatch with
#       PLANWRIGHT_FLIGHT_LOCK_WAIT=0 proceeds while the first worker runs
#       (REQ-F1.1, REQ-F1.5, REQ-G1.6)
#   l3  session names are `<base>-<hash6>_<suffix'>`: a dotted task id written
#       with `_`, a basename's leading and disallowed bytes mapped, two
#       checkouts sharing a basename kept apart (REQ-G1.4)
#   l4  liveness reads the new name and the prior launcher's spelling (a dotted
#       basename included) as live, a probe name outside the charset as live
#       with no has-session call, and the bare `<suffix>` and
#       `worktree-<suffix>` names as nothing (REQ-G1.7)
#   l5  no model or API call in the launch path, at runtime or in the launch
#       function's source (REQ-E1.3)
#   l6  every launch in this file and its refusal sibling goes through the
#       bounded runner (REQ-H1.1)
#   l7  a flight dispatch whose tmux hangs returns at the tmux call bound,
#       reports the failure, and leaves the flight lock free
#
# Runs standalone under /bin/bash (the bash 3.2 floor):
#   ./tests/test-tmux-detached-launch.sh
# shellcheck disable=SC2016 # the source assertions match literal `$` text
set -u
LC_ALL=C
export LC_ALL
unset CDPATH

here=$(cd "$(dirname "$0")" && pwd)

fails=0
fail() {
  echo "FAIL: $1" >&2
  fails=$((fails + 1))
}

# shellcheck source=tests/lib/tmux-launch-harness.sh
. "$here/lib/tmux-launch-harness.sh"
# shellcheck source=tests/lib/tmux-launch-cases.sh
. "$here/lib/tmux-launch-cases.sh"

# check_worker <label> <record> <worktree> <handle> <scope> — the worker's
# directory, argv, and environment.
check_worker() {
  local label=$1 rec=$2 wt=$3 handle=$4 scope=$5 pid argv v tok
  pid=$(tlh_record_field "$rec" pid)
  kill -0 "$pid" 2>/dev/null || fail "$label: the worker is not running once the dispatch has returned"
  tlh_assert_path_eq "$label: the worker's directory" "$wt" "$(tlh_record_field "$rec" cwd)"
  argv=$(grep "^argv" "$rec")
  case "$argv$TAB" in
    *"$TAB--worktree"* | *"$TAB--tmux"*) fail "$label: the worker argv carries --worktree or --tmux: $argv" ;;
  esac
  v=$(tlh_worker_env "$rec" CLAUDE_CODE_ENABLE_PROMPT_SUGGESTION) || v='<unset>'
  [ "$v" = false ] || fail "$label: the ghost-text pin did not reach the worker ($v)"
  v=$(tlh_worker_env "$rec" PLANWRIGHT_ROOT) || v='<unset>'
  [ "$v" = "$ROOT" ] || fail "$label: the worker's PLANWRIGHT_ROOT is not the dispatcher's ($v)"
  v=$(tlh_worker_env "$rec" CLAUDE_PLUGIN_ROOT) || v='<unset>'
  [ "$v" = "$ROOT" ] || fail "$label: the worker's CLAUDE_PLUGIN_ROOT is not the dispatcher's ($v)"
  v=$(tlh_worker_env "$rec" PLANWRIGHT_FLEET_STATE_DIR) || v='<unset>'
  [ "$v" = "$C/fleet" ] || fail "$label: the worker's fleet home is not the dispatcher's ($v)"
  v=$(tlh_worker_env "$rec" PLANWRIGHT_WORKER_HANDLE) || v='<unset>'
  [ "$v" = "$handle" ] || fail "$label: the worker's handle is '$v', not '$handle'"
  v=$(tlh_worker_env "$rec" PLANWRIGHT_WORKER_SCOPE) || v='<unset>'
  [ "$v" = "$scope" ] || fail "$label: the worker's scope is '$v', not '$scope'"
  tok=$(tlh_worker_env "$rec" PLANWRIGHT_WORKER_LAUNCH_TOKEN) || tok=''
  printf '%s' "$tok" | grep -Eq '^[0-9a-f]{16,64}$' \
    || fail "$label: the worker carries no launch token ('$tok')"
  # The registry record's identity is the worker's.
  [ "$(registry_col 2 | tail -n 1)" = "$handle" ] || fail "$label: the registry handle is not the worker's"
  [ "$(registry_col 3 | tail -n 1)" = "$scope" ] || fail "$label: the registry scope is not the worker's"
}

# check_session_call <label> <session> <worktree> — the one new-session call.
check_session_call() {
  local label=$1 sess=$2 wt=$3 ns
  ns=$(calls_matching new-session | grep -F "$TAB-s$TAB$sess$TAB")
  [ "$(printf '%s\n' "$ns" | grep -c .)" = 1 ] \
    || fail "$label: expected one new-session call for $sess, got: $(tlh_tmux_calls)"
  case "$TAB$ns$TAB" in
    *"$TAB-d$TAB"*) ;;
    *) fail "$label: the session is not created detached: $ns" ;;
  esac
  # The physical path, byte for byte: tmux is handed no symlinked spelling.
  case "$TAB$ns$TAB" in
    *"$TAB-c$TAB$wt$TAB"*) ;;
    *) fail "$label: the start directory is not the physical worktree $wt: $ns" ;;
  esac
  case "$TAB$ns$TAB" in
    *"$TAB;${TAB}set-window-option$TAB-t$TAB=$sess:${TAB}remain-on-exit${TAB}off$TAB"*) ;;
    *) fail "$label: remain-on-exit is not turned off in the same invocation: $ns" ;;
  esac
  # Every command of every call, chained ones included.
  tlh_tmux_calls | awk -F"$TAB" '{
      print $1
      for (i = 1; i < NF; i++) if ($i ~ /;$/) print $(i + 1)
    }' | grep -Exq 'switch-client|switchc|attach-session|attach|a' \
    && fail "$label: a client-moving call reached tmux: $(tlh_tmux_calls)"
  return 0
}

# --- l1: a task dispatch ------------------------------------------------------
l1() {
  local sess wt rec death
  new_case
  tlh_run_bounded "$PRIM" dispatch demo 3 --repo-root "$P"
  tlh_expect_returned l1 || return
  [ "$TLH_RC" -eq 14 ] || fail "l1: a created session must report started-unconfirmed (exit 14), got $TLH_RC ($TLH_ERR)"
  printf '%s\n' "$TLH_OUT" | grep -qx "confirm${TAB}outcome${TAB}started-unconfirmed" \
    || fail "l1: the report does not say started-unconfirmed: $TLH_OUT"
  sess=$(expect_session "$PP" demo-task-3)
  wt="$PP/.claude/worktrees/demo-task-3"
  [ "$(launch_field session)" = "$sess" ] || fail "l1: the launch report names '$(launch_field session)', not $sess"
  check_session_call l1 "$sess" "$wt"
  tlh_wait_workers 1 10 || return
  rec=$(tlh_last_worker_record)
  check_worker l1 "$rec" "$wt" tmux-demo-task-3 demo:3
  [ "$(registry_col 2 | grep -c .)" = 1 ] || fail "l1: expected one registry record, got: $(cat "$C/fleet/registry" 2>/dev/null)"
  death="tmux-window $sess $(launch_field window)"
  [ "$(registry_col 7)" = "$death" ] || fail "l1: the death handle '$(registry_col 7)' is not the creation output '$death'"
  case $(launch_field window) in @[0-9]*) ;; *) fail "l1: the launch report carries no window id" ;; esac
  # A liveness hook run with the worker's own environment records a transition.
  env -i PATH="$PATH" HOME="$TLH_SANDBOX" \
    PLANWRIGHT_WORKER_HANDLE="$(tlh_worker_env "$rec" PLANWRIGHT_WORKER_HANDLE)" \
    PLANWRIGHT_WORKER_SCOPE="$(tlh_worker_env "$rec" PLANWRIGHT_WORKER_SCOPE)" \
    PLANWRIGHT_FLEET_STATE_DIR="$(tlh_worker_env "$rec" PLANWRIGHT_FLEET_STATE_DIR)" \
    /bin/sh "$ROOT/scripts/fleet-liveness.sh" hook stop </dev/null >/dev/null 2>&1
  grep -qF tmux-demo-task-3 "$C/fleet/attention/state" 2>/dev/null \
    || fail "l1: a liveness hook run with the worker's environment recorded no transition for its handle"
}

# record_for <handle> — the worker record whose environment carries <handle>.
record_for() {
  local r
  for r in $(tlh_worker_records); do
    [ "$(tlh_worker_env "$r" PLANWRIGHT_WORKER_HANDLE 2>/dev/null)" = "$1" ] && {
      printf '%s\n' "$r"
      return 0
    }
  done
  return 1
}

# --- l2: a flight dispatch ----------------------------------------------------
# The flight dispatch reads these from the environment; exported for l2 only.
l2() {
  new_case
  mkdir -p "$C/adopter" "$C/claude"
  export CLAUDE_DIR="$C/claude" PLANWRIGHT_ADOPTER_OVERLAY="$C/adopter" PLANWRIGHT_FLIGHT_LOCK_WAIT=0 \
    PLANWRIGHT_REPO_ROOT="$P"
  l2_flight
  unset CLAUDE_DIR PLANWRIGHT_ADOPTER_OVERLAY PLANWRIGHT_FLIGHT_LOCK_WAIT PLANWRIGHT_REPO_ROOT
}

l2_flight() {
  local fid fid2 sess wt rec n0
  printf 'Fix the typo in the README heading.\n' >"$C/ask.txt"
  printf 'visual flight: a one-line wording change\n' >"$C/grounds.txt"
  n0=$(tlh_worker_count)
  # The regression the detached launch fixed: the worker CLI behaves as the
  # native launcher does inside tmux, handing off and never returning when it
  # is given --tmux, so a dispatch that still launched it that way would hang
  # here and be cut off by the bound.
  mkdir -p "$C/regbin"
  printf '#!/bin/sh\nfor a; do case $a in --tmux | --tmux=*) exec sleep 600 ;; esac; done\nexec %s "$@"\n' \
    "'$TLH_BIN/claude'" >"$C/regbin/claude"
  chmod +x "$C/regbin/claude"
  PATH="$C/regbin:$PATH" tlh_run_bounded "$FLIGHT" dispatch readme-typo --backend tmux --ask-file "$C/ask.txt" \
    --grounds-file "$C/grounds.txt" --home file --repo-root "$P"
  tlh_expect_returned l2 || return
  [ "$TLH_RC" -eq 0 ] || {
    fail "l2: a flight whose session was created is placed (exit 0), got $TLH_RC ($TLH_ERR)"
    return
  }
  [ "$(report_field outcome)" = started-unconfirmed ] \
    || fail "l2: the flight report does not say started-unconfirmed: $TLH_OUT"
  fid=$(report_field flight)
  sess=$(expect_session "$PP" "flight-$fid")
  wt="$PP/.claude/worktrees/flight-$fid"
  [ "$(report_field observe)" = "tmux capture-pane -p -t '=$sess:'" ] \
    || fail "l2: the observe hint does not target '=$sess:': $(report_field observe)"
  [ "$(report_field attach)" = "tmux attach -t '=$sess'" ] \
    || fail "l2: the attach hint does not name the session: $(report_field attach)"
  check_session_call l2 "$sess" "$wt"
  tlh_wait_workers "$((n0 + 1))" 10 || return
  rec=$(record_for "tmux-flight-$fid") || {
    fail "l2: no worker record carries the flight's handle tmux-flight-$fid"
    return
  }
  check_worker l2 "$rec" "$wt" "tmux-flight-$fid" "flight:$fid"
  grep -q "^argv.*$TAB--${TAB}Read [^$TAB]*/brief.md and follow it exactly.\$" "$rec" \
    || fail "l2: the flight worker was not handed its brief: $(grep '^argv' "$rec")"
  # The lock went with the launch: a second flight from the same checkout,
  # unwilling to wait for it, is placed while the first worker runs.
  tlh_run_bounded "$FLIGHT" dispatch readme-typo --backend tmux --ask-file "$C/ask.txt" \
    --grounds-file "$C/grounds.txt" --home file --repo-root "$P"
  tlh_expect_returned "l2 second dispatch" || return
  [ "$TLH_RC" -eq 0 ] || fail "l2: a second flight must proceed while the first worker runs, got $TLH_RC ($TLH_ERR)"
  fid2=$(report_field flight)
  [ -n "$fid2" ] && [ "$fid2" != "$fid" ] || fail "l2: the second dispatch did not place its own flight"
  kill -0 "$(tlh_record_field "$rec" pid)" 2>/dev/null || fail "l2: the first worker stopped"
  # The confirm step runs once the lock is released, never under it: the
  # startup wait the confirm step grows into would otherwise queue every
  # other flight from this checkout.
  awk '/^cmd_dispatch\(\) \{/,/^}/' "$FLIGHT" | awk '
      /^[[:space:]]*release_lock$/ && !rel { rel = NR }
      /"\$WORKTREE" confirm/ && !conf { conf = NR }
      END { exit !(rel && conf && rel < conf) }' \
    || fail "l2: the flight dispatch does not release its lock before the confirm step"
  return 0
}

# --- l3: session names --------------------------------------------------------
l3() {
  local a b
  new_case
  tlh_run_bounded "$PRIM" dispatch demo 2.1 --repo-root "$P" --attach-dry-run
  [ "$TLH_RC" -eq 0 ] || fail "l3: dry run exited $TLH_RC ($TLH_ERR)"
  a=$(printf '%s\n' "$TLH_OUT" | awk -F"$TAB" '$1 == "attach-plan" && $2 == "session" { print $3 }')
  [ "$a" = "$(expect_session "$PP" demo-task-2.1)" ] || fail "l3: dotted id session '$a'"
  case $a in *_demo-task-2_1) ;; *) fail "l3: a dotted task id is not written with _: $a" ;; esac
  # Leading and disallowed basename bytes.
  new_case "_my.repo+x"
  tlh_run_bounded "$PRIM" dispatch demo 4 --repo-root "$P" --attach-dry-run
  a=$(printf '%s\n' "$TLH_OUT" | awk -F"$TAB" '$1 == "attach-plan" && $2 == "session" { print $3 }')
  case $a in my-repo-x-[0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f]_demo-task-4) ;; *) fail "l3: basename mapping gave '$a'" ;; esac
  printf '%s' "$a" | grep -Eq '^[A-Za-z0-9][A-Za-z0-9_@-]*$' || fail "l3: '$a' is outside the session charset"
  # Two checkouts sharing a basename.
  new_case "one/primary"
  tlh_run_bounded "$PRIM" dispatch demo 4 --repo-root "$P" --attach-dry-run
  a=$(printf '%s\n' "$TLH_OUT" | awk -F"$TAB" '$1 == "attach-plan" && $2 == "session" { print $3 }')
  new_case "two/primary"
  tlh_run_bounded "$PRIM" dispatch demo 4 --repo-root "$P" --attach-dry-run
  b=$(printf '%s\n' "$TLH_OUT" | awk -F"$TAB" '$1 == "attach-plan" && $2 == "session" { print $3 }')
  [ -n "$a" ] && [ -n "$b" ] && [ "$a" != "$b" ] || fail "l3: two checkouts named primary must get two session names ('$a', '$b')"
  # The dry-run plan is the detached launch.
  case $(printf '%s\n' "$TLH_OUT" | grep "^attach-plan${TAB}launch") in
    *"${TAB}new-session$TAB-d$TAB-s$TAB$b$TAB-c$TAB$PP/.claude/worktrees/demo-task-4$TAB"*) ;;
    *) fail "l3: the dry-run plan is not the detached launch: $TLH_OUT" ;;
  esac
}

# stale_branch <id> — a branch carrying work with no worktree, so the create
# collides and the dispatch has to ask whether a live dispatch holds it.
stale_branch() {
  gitc "$P" branch "planwright/demo/task-$1" main
  gitc "$P" checkout -q "planwright/demo/task-$1"
  printf 'w\n' >"$P/work-$1"
  gitc "$P" add -A
  gitc "$P" commit -q -m work
  gitc "$P" checkout -q main
}

# --- l4: liveness probes ------------------------------------------------------
l4() {
  local s
  # The prior launcher's spelling, for a dotted basename.
  new_case "my.repo"
  stale_branch 5
  tmux new-session -d -s "my_repo_worktree-demo-task-5"
  tlh_run_bounded "$PRIM" dispatch demo 5 --repo-root "$P"
  [ "$TLH_RC" -eq 3 ] || fail "l4: a session under the prior launcher's spelling must read live (exit 3), got $TLH_RC"
  # Live because the mapped name was asked about, not because an unmapped
  # name fell outside the charset and read as live unasked.
  calls_matching has-session | grep -q "$TAB=my_repo_worktree-demo-task-5\$" \
    || fail "l4: the prior launcher's spelling was not probed with the basename mapped as tmux maps it"
  tmux kill-session -t "=my_repo_worktree-demo-task-5"
  # The create-only arm probes the same names, so with no session a stale
  # branch is adopted rather than read as in flight.
  stale_branch 9
  tlh_run_bounded "$PRIM" dispatch demo 9 --repo-root "$P" --no-attach
  [ "$TLH_RC" -eq 0 ] || fail "l4: a --no-attach dispatch over a stale branch must adopt it (exit 0), got $TLH_RC ($TLH_ERR)"
  # The new name for a worktree holding the branch elsewhere (the alternate
  # name): live, so the dispatch aborts in flight rather than naming the move.
  new_case
  gitc "$P" worktree add -q -b planwright/demo/task-6 "$P/.claude/worktrees/task-6" main
  s=$(expect_session "$PP" task-6)
  tmux new-session -d -s "$s"
  tlh_run_bounded "$PRIM" dispatch demo 6 --repo-root "$P"
  [ "$TLH_RC" -eq 3 ] || fail "l4: a session under the new name for the alternate worktree must read live (exit 3), got $TLH_RC"
  tmux kill-session -t "=$s"
  # The bare and worktree- names match nothing a launch creates.
  new_case
  stale_branch 7
  tmux new-session -d -s demo-task-7
  tmux new-session -d -s worktree-demo-task-7
  tlh_run_bounded "$PRIM" dispatch demo 7 --repo-root "$P"
  [ "$TLH_RC" -eq 14 ] || fail "l4: bare and worktree- sessions must not read live, got $TLH_RC ($TLH_ERR)"
  calls_matching has-session | grep -E "$TAB=(worktree-)?demo-task-7(${TAB}|\$)" \
    && fail "l4: a bare or worktree- probe was sent"
  tmux kill-session -t =demo-task-7
  tmux kill-session -t =worktree-demo-task-7
  # A probe name outside the charset reads live and is never sent.
  new_case "my+repo"
  stale_branch 8
  tlh_run_bounded "$PRIM" dispatch demo 8 --repo-root "$P"
  [ "$TLH_RC" -eq 3 ] || fail "l4: a probe name outside the charset must read live (exit 3), got $TLH_RC"
  calls_matching has-session | grep -F 'my+repo' && fail "l4: a probe outside the charset was sent"
  # The source keeps no probe for the bare or worktree- names.
  grep -v '^[[:space:]]*#' "$PRIM" | grep -E '=worktree-\$|"=\$_(suffix|alt)"|"=\$\(worker_session "\$_(suffix|alt)"\)"' \
    && fail "l4: the primitive still probes a bare or worktree- session name"
  return 0
}

# --- l5: no model or API call in the launch path ------------------------------
l5() {
  local body rec
  body=$(awk '/^tmux_launch\(\) \{/,/^}/' "$PRIM")
  [ -n "$body" ] || {
    fail "l5: the launch function tmux_launch was not found"
    return
  }
  printf '%s\n' "$body" | grep -v '^[[:space:]]*#' | grep -Eiq 'curl|wget|https?:|anthropic' \
    && fail "l5: the launch function makes a network call"
  printf '%s\n' "$body" | grep -v '^[[:space:]]*#' | grep -Eq '(^|[[:space:]])(-p|--print)([[:space:]]|$)|--output-format' \
    && fail "l5: the launch function runs the worker CLI in print mode"
  printf '%s\n' "$body" | grep -Eq 'pane_current_path|list-panes' \
    && fail "l5: the launch function looks a pane's working directory up"
  # At runtime: every worker CLI invocation is the worker itself.
  for rec in $(tlh_worker_records); do
    grep -Eq "^argv.*$TAB(-p|--print)($TAB|\$)" "$rec" && fail "l5: a print-mode worker CLI call was made: $rec"
  done
  return 0
}

# --- l6: every launch is bounded ----------------------------------------------
l6() {
  local f
  for f in "$here/test-tmux-detached-launch.sh" "$here/test-tmux-launch-refusals.sh"; do
    grep -nE '"\$(PRIM|FLIGHT|seam/fleet-dispatch-worktree\.sh)" (dispatch|attach)' "$f" | grep -v 'tlh_run_bounded' \
      | grep -v '^[0-9]*:[[:space:]]*#' && fail "l6: a launch in ${f##*/} is not bounded"
  done
  return 0
}

# --- l7: a hung tmux under the flight lock -------------------------------------
l7() {
  new_case
  mkdir -p "$C/adopter" "$C/claude"
  export CLAUDE_DIR="$C/claude" PLANWRIGHT_ADOPTER_OVERLAY="$C/adopter" PLANWRIGHT_FLIGHT_LOCK_WAIT=0 \
    PLANWRIGHT_REPO_ROOT="$P"
  l7_flight
  unset CLAUDE_DIR PLANWRIGHT_ADOPTER_OVERLAY PLANWRIGHT_FLIGHT_LOCK_WAIT PLANWRIGHT_REPO_ROOT
}

l7_flight() {
  printf 'Fix the typo in the README heading.\n' >"$C/ask.txt"
  printf 'visual flight: a one-line wording change\n' >"$C/grounds.txt"
  tmux_shim "$C/hang" hang-new
  PATH="$C/hang:$PATH" PLANWRIGHT_DISPATCH_TMUX_TIMEOUT=2 tlh_run_bounded --bound 25 "$FLIGHT" dispatch \
    readme-typo --backend tmux --ask-file "$C/ask.txt" --grounds-file "$C/grounds.txt" --home file --repo-root "$P"
  tlh_expect_returned "l7: a flight dispatch must end a hung tmux itself" || return
  [ "$TLH_RC" -eq 5 ] || fail "l7: a hung launch must fail the placement (exit 5), got $TLH_RC ($TLH_ERR)"
  case $TLH_ERR in *'did not return'*) ;; *) fail "l7: the hang is not reported: $TLH_ERR" ;; esac
  [ "$(report_field failed)" != '' ] || fail "l7: the report carries no failed line: $TLH_OUT"
  # Nothing was launched and the primitive undid its worktree, so no slot is held.
  [ "$(report_field worktree)" = '' ] || fail "l7: the hung launch left a worktree: $(report_field worktree)"
  # Its lock went with it: a dispatch that will not wait for the lock is placed.
  tlh_run_bounded "$FLIGHT" dispatch readme-typo --backend tmux --ask-file "$C/ask.txt" \
    --grounds-file "$C/grounds.txt" --home file --repo-root "$P"
  [ "$TLH_RC" -eq 0 ] || fail "l7: the flight lock is still held after the hung dispatch returned ($TLH_RC: $TLH_ERR)"
  return 0
}

l1
l2
l3
l4
l5
l6
l7

[ "$fails" -eq 0 ] || {
  echo "test-tmux-detached-launch: $fails failure(s)" >&2
  exit 1
}
echo "ok: test-tmux-detached-launch"
