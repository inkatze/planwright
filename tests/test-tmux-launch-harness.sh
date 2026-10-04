#!/bin/bash
# Self-test for the tmux launch fixture harness (tests/lib/tmux-launch-harness.sh)
# and its stubs. Each case below shows one harness property able to fail:
#   h1  a blocking launch fails within the bound with a hang diagnosis and its
#       process tree killed, a launch that returns is never cut off early, and
#       a bound that does not exceed the confirm cap is refused (REQ-H1.1)
#   h2  a stub session's command sees the server's environment, not the
#       dispatcher's, and the harness scrubs the worker identity and the
#       fleet home it inherits (REQ-H1.2)
#   h3  under the symlinked temporary directory, canonical path assertions
#       pass, a raw compare would not, and two different missing paths never
#       compare equal (REQ-H1.4)
#   h4  concurrent stub calls leave intact, non-interleaved records, and a
#       contested session name, fresh or stale, goes to exactly one caller
#       (REQ-H1.4)
#   h5  a leaked stub process fails the suite's leak check; reaped, including
#       one that ignores TERM, it does not; a recycled pid is never taken for a
#       stub's; the suite's own status survives teardown, under set -e too
#       (REQ-H1.4)
#   h6  the stub worker fires its startup confirmation hook by default, in its
#       own environment, with a startup or resume payload, and not when turned
#       off; a worker that exits takes its session with it
#   h7  the stub tmux's parsing, refusal knobs, liveness answers, and
#       remain-on-exit, and a target that names a path outside the stub state
#
# Runs standalone under /bin/bash (the bash 3.2 floor):
#   ./tests/test-tmux-launch-harness.sh
# shellcheck disable=SC2016 # child-suite bodies are code that expands in the child
set -u
LC_ALL=C
export LC_ALL
unset CDPATH

here=$(cd "$(dirname "$0")" && pwd)
TAB=$(printf '\t')

fails=0
fail() {
  echo "FAIL: $1" >&2
  fails=$((fails + 1))
}

# expect_one_fail <label> <cmd...> — the command must report exactly one
# failure through `fail`; that failure is expected and not counted.
expect_one_fail() {
  local label=$1 before=$fails after
  shift
  "$@" 2>/dev/null
  after=$fails
  fails=$before
  [ "$after" -eq $((before + 1)) ] || fail "$label: expected exactly one reported failure, got $((after - before))"
}

# shellcheck source=tests/lib/tmux-launch-harness.sh
. "$here/lib/tmux-launch-harness.sh"

wt="$TLH_SANDBOX/wt"
mkdir -p "$wt"

# child_suite <name> <body> — a suite that sources the harness on its own, so
# setup and teardown can be observed from outside. Prints its script path.
child_suite() {
  local f="$TLH_SANDBOX/child-$1.sh"
  {
    printf '%s\n' "fail() { echo \"FAIL: \$1\" >&2; }"
    printf '%s\n' ". '$here/lib/tmux-launch-harness.sh'"
    printf '%s\n' "$2"
  } >"$f"
  printf '%s\n' "$f"
}

wait_gone() {
  local t=0
  while tmux has-session -t "=$1" 2>/dev/null && [ "$t" -lt 50 ]; do
    sleep 0.1
    t=$((t + 1))
  done
}

# --- h1 ---------------------------------------------------------------------
h1() {
  local b=2 pid err rc i
  [ "$TLH_LAUNCH_BOUND_SECONDS" -gt "$TLH_CONFIRM_CAP_SECONDS" ] \
    || fail "h1: the default bound must exceed the confirm cap"
  err=$(TLH_LAUNCH_BOUND_SECONDS=2 TLH_CONFIRM_CAP_SECONDS=2 /bin/bash "$(child_suite cap 'exit 0')" 2>&1)
  rc=$?
  [ "$rc" -ne 0 ] || fail "h1: a bound that does not exceed the confirm cap must be refused at setup"
  case $err in *"must exceed the confirm cap"*) ;; *) fail "h1: the cap refusal must say why, got: $err" ;; esac

  tlh_knob new-session block
  tlh_run_bounded --bound "$b" tmux new-session -d -s blocker -c "$wt" -- sleep 60
  tlh_knob new-session ok
  [ "$TLH_RC" -eq 124 ] || fail "h1: a blocking launch must be cut off as a hang (rc 124), got $TLH_RC"
  [ "$TLH_ELAPSED" -le $((b + 1)) ] || fail "h1: a blocking launch must fail within its bound, took ${TLH_ELAPSED}s"
  case $TLH_DIAG in
    *"did not return within ${b}s"*) ;;
    *) fail "h1: the diagnosis must name the hang and the bound, got: $TLH_DIAG" ;;
  esac
  pid=$(tlh_session_pid blocker)
  [ -n "$pid" ] || fail "h1: the blocking stub must have created its session before blocking"
  [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null && fail "h1: a hang must kill the launch's whole process tree, the session's command included"
  expect_one_fail "h1: tlh_expect_returned on a hung run" tlh_expect_returned "h1 probe"

  # A run that returns before its bound is never reported as a hang, however
  # the start falls against a whole-second clock.
  for i in 1 2 3; do
    tlh_run_bounded --bound 1 sleep 0.6
    [ "$TLH_RC" -eq 0 ] || fail "h1: a 0.6s run under a 1s bound was cut off (round $i, rc $TLH_RC)"
  done
  expect_one_fail "h1: a fractional bound" tlh_run_bounded --bound 1.5 true

  tlh_run_bounded tmux new-session -d -s quick -P -F "#{session_name}${TAB}#{window_id}" -c "$wt" -- sleep 30
  tlh_expect_returned "h1: a returning launch"
  [ "$TLH_RC" -eq 0 ] || fail "h1: a returning launch must keep its own status, got $TLH_RC: $TLH_ERR"
  case $TLH_OUT in
    "quick${TAB}@"[0-9]*) ;;
    *) fail "h1: -P -F must print the session name and window id, got: $TLH_OUT" ;;
  esac
  tlh_run_bounded tmux has-session -t =nosuch
  [ "$TLH_RC" -eq 1 ] || fail "h1: a failing command's status must come through, got $TLH_RC"
  tmux kill-session -t =quick
}

# --- h2 ---------------------------------------------------------------------
h2() {
  local rec n out
  tlh_server_env TLH_PROBE_SERVER_ONLY=from-server CDPATH=/server-cdpath
  TLH_PROBE_DISPATCHER_ONLY=from-dispatcher
  export TLH_PROBE_DISPATCHER_ONLY
  n=$(tlh_worker_count)
  tlh_run_bounded tmux new-session -d -s envprobe -e TLH_PROBE_DASH_E=from-e -c "$wt" -- "$TLH_BIN/claude" envprobe
  tlh_expect_returned "h2: the probe launch"
  unset TLH_PROBE_DISPATCHER_ONLY
  tlh_wait_workers $((n + 1)) 10 || return
  rec=$(tlh_last_worker_record)
  [ "$(tlh_worker_env "$rec" TLH_PROBE_SERVER_ONLY)" = from-server ] \
    || fail "h2: the session's command must see the server's environment"
  tlh_worker_env "$rec" TLH_PROBE_DISPATCHER_ONLY >/dev/null \
    && fail "h2: the session's command must not see the dispatcher's environment"
  [ "$(tlh_worker_env "$rec" TLH_PROBE_DASH_E)" = from-e ] \
    || fail "h2: new-session -e must reach the session's environment, as it does under tmux"
  [ "$(tlh_worker_env "$rec" CDPATH)" = /server-cdpath ] \
    || fail "h2: the worker record must show the environment it was given, not one the stub adjusted"
  case $(tlh_worker_env "$rec" TMUX_PANE) in
    %[0-9]*) ;;
    *) fail "h2: a pane's command must see TMUX_PANE, as under tmux" ;;
  esac
  tlh_worker_env "$rec" TMUX >/dev/null || fail "h2: a pane's command must see TMUX, as under tmux"
  tmux kill-session -t =envprobe

  out=$(PLANWRIGHT_WORKER_HANDLE=leak PLANWRIGHT_WORKER_SCOPE=leak:1 PLANWRIGHT_WORKER_LAUNCH_TOKEN=ab \
    CLAUDE_PLUGIN_DATA=/leak PLANWRIGHT_FLEET_STATE_DIR=/leak /bin/bash "$(child_suite scrub \
      'printf "%s|%s|%s|%s|%s|%s\n" "${PLANWRIGHT_WORKER_HANDLE-unset}" "${PLANWRIGHT_WORKER_SCOPE-unset}" "${PLANWRIGHT_WORKER_LAUNCH_TOKEN-unset}" "${CLAUDE_PLUGIN_DATA-unset}" "$PLANWRIGHT_FLEET_STATE_DIR" "$TLH_SANDBOX"')" 2>&1)
  case $out in
    "unset|unset|unset|unset|"*) ;;
    *) fail "h2: the harness must scrub the inherited worker identity and plugin data, got: $out" ;;
  esac
  case ${out#unset|unset|unset|unset|} in
    "/leak|"*) fail "h2: the fleet home must be pinned inside the sandbox, got: $out" ;;
  esac
}

# --- h3 ---------------------------------------------------------------------
h3() {
  local rec cwd n
  [ "$TLH_SANDBOX" != "$(tlh_canon "$TLH_SANDBOX")" ] \
    || fail "h3: the sandbox must sit under a symlinked directory, or the canonical compare proves nothing"
  n=$(tlh_worker_count)
  tlh_run_bounded tmux new-session -d -s pathprobe -c "$wt" -- "$TLH_BIN/claude"
  tlh_expect_returned "h3: the probe launch"
  tlh_wait_workers $((n + 1)) 10 || return
  rec=$(tlh_last_worker_record)
  cwd=$(tlh_record_field "$rec" cwd)
  [ "$cwd" != "$wt" ] || fail "h3: the worker's physical cwd must differ from the symlinked path as given"
  tlh_assert_path_eq "h3: the worker's start directory" "$wt" "$cwd"
  expect_one_fail "h3: different existing paths" tlh_assert_path_eq "h3 probe" "$wt" "$TLH_SANDBOX"
  expect_one_fail "h3: different missing paths sharing a basename" \
    tlh_assert_path_eq "h3 probe" /nonexistent-a/m/x /nonexistent-b/m/x
  [ -z "$(tlh_record_field "$rec" argv)" ] || fail "h3: a worker given no arguments must record an empty argv"
  tmux kill-session -t =pathprobe

  # A -c that names no directory starts in the server's HOME, without a word.
  n=$(tlh_worker_count)
  tlh_run_bounded tmux new-session -d -s nodir -c "$TLH_SANDBOX/missing" -- "$TLH_BIN/claude"
  tlh_expect_returned "h3: the missing-directory launch"
  [ "$TLH_RC" -eq 0 ] || fail "h3: a missing -c must not fail the stub launch, got $TLH_RC"
  tlh_wait_workers $((n + 1)) 10 || return
  tlh_assert_path_eq "h3: a missing start directory falls back to the server HOME" \
    "$TLH_SANDBOX/server-home" "$(tlh_record_field "$(tlh_last_worker_record)" cwd)"
  tmux kill-session -t =nodir
}

# --- h4 ---------------------------------------------------------------------
h4() {
  local n_msg=40 n_new=6 n_race=4 rounds=3 pad c0 w0 calls i r wins hit rec
  pad=$(awk 'BEGIN { while (i++ < 2000) printf "x" }')
  c0=$(tlh_tmux_calls | wc -l | tr -d ' ')
  w0=$(tlh_worker_count)
  # The real liveness hook is the slow part of a worker start; h6 covers it.
  tlh_knob worker-confirm off
  i=1
  while [ "$i" -le "$n_msg" ]; do
    tmux display-message -p "msg-$i-$pad" >/dev/null 2>&1 &
    i=$((i + 1))
  done
  i=1
  while [ "$i" -le "$n_new" ]; do
    tmux new-session -d -s "conc$i" -c "$wt" -- "$TLH_BIN/claude" "worker-$i-$pad" &
    i=$((i + 1))
  done
  wait
  calls=$(tlh_tmux_calls | tail -n +$((c0 + 1)))
  [ "$(printf '%s\n' "$calls" | wc -l | tr -d ' ')" -eq $((n_msg + n_new)) ] \
    || fail "h4: $((n_msg + n_new)) concurrent calls must leave as many records, got $(printf '%s\n' "$calls" | wc -l)"
  i=1
  while [ "$i" -le "$n_msg" ]; do
    printf '%s\n' "$calls" | grep -qx "display-message${TAB}-p${TAB}msg-$i-$pad" \
      || fail "h4: call record $i is missing or torn"
    i=$((i + 1))
  done
  i=1
  while [ "$i" -le "$n_new" ]; do
    printf '%s\n' "$calls" | grep -qx "new-session${TAB}-d${TAB}-s${TAB}conc$i${TAB}-c${TAB}$wt${TAB}--${TAB}$TLH_BIN/claude${TAB}worker-$i-$pad" \
      || fail "h4: new-session record $i is missing or torn"
    i=$((i + 1))
  done
  tlh_wait_workers $((w0 + n_new)) 10 || return
  i=1
  while [ "$i" -le "$n_new" ]; do
    hit=0
    while IFS= read -r rec; do
      [ "$(tlh_record_field "$rec" argv)" = "worker-$i-$pad" ] && hit=$((hit + 1))
      [ -n "$(tlh_record_field "$rec" pid)" ] && [ -n "$(tlh_record_field "$rec" cwd)" ] \
        || fail "h4: a worker record is torn: $rec"
    done <<EOF
$(tlh_worker_records | tail -n "$n_new")
EOF
    [ "$hit" -eq 1 ] || fail "h4: worker $i must leave exactly one intact record, found $hit"
    tmux kill-session -t "=conc$i"
    i=$((i + 1))
  done
  tlh_knob worker-confirm on

  # A contested name, fresh and then stale (its command has exited), goes to
  # exactly one creator.
  tmux new-session -d -s contested -c "$wt" -- true
  r=1
  while [ "$r" -le "$rounds" ]; do
    wait_gone contested
    i=1
    while [ "$i" -le "$n_race" ]; do
      { tmux new-session -d -s contested -c "$wt" -- sleep 30 2>/dev/null && : >"$TLH_SANDBOX/won.$r.$i"; } &
      i=$((i + 1))
    done
    wait
    set -- "$TLH_SANDBOX"/won."$r".*
    wins=$#
    [ -e "$1" ] || wins=0
    [ "$wins" -eq 1 ] || fail "h4: round $r: $n_race racing creates over a stale name must yield one session, got $wins"
    tmux kill-session -t =contested
    r=$((r + 1))
  done
}

# --- h5 ---------------------------------------------------------------------
h5() {
  local child err rc leaked p sb
  child=$(child_suite leak "mkdir -p \"\$TLH_SANDBOX/w\"
tmux new-session -d -s leak -c \"\$TLH_SANDBOX/w\" -- sleep 60
tmux new-session -d -s stubborn -c \"\$TLH_SANDBOX/w\" -- sh -c \"trap '' TERM; exec sleep 60\"
sleep 0.3
tlh_stub_pids_alive >'$TLH_SANDBOX/child.pids'")
  err=$(TLH_REAP=0 /bin/bash "$child" 2>&1)
  rc=$?
  leaked=$(cat "$TLH_SANDBOX/child.pids")
  [ -n "$leaked" ] || fail "h5: the leaking child started no process to leak"
  [ "$rc" -ne 0 ] || fail "h5: a leaked stub process must fail the suite"
  case $err in
    *"leaked stub process"*) ;;
    *) fail "h5: the leak must be named, got: $err" ;;
  esac
  for p in $leaked; do kill -9 "$p" 2>/dev/null; done

  err=$(/bin/bash "$child" 2>&1)
  rc=$?
  [ "$rc" -eq 0 ] || fail "h5: a reaped suite must pass its leak check, TERM-ignoring process included, got $rc: $err"
  while read -r p; do
    kill -0 "$p" 2>/dev/null && {
      fail "h5: the reaper left pid $p running"
      kill -9 "$p" 2>/dev/null
    }
  done <"$TLH_SANDBOX/child.pids"

  # A pid file whose process has been replaced is not a stub's.
  printf '%s\n' 'Thu Jan  1 00:00:00 1970' >"$TLH_STATE/pids/$$"
  tlh_stub_pids_alive | grep -qx "$$" && fail "h5: a recycled pid must not be taken for a stub-started process"
  rm -f "$TLH_STATE/pids/$$"

  rc=0
  /bin/bash "$(child_suite status 'trap '\''st=$?; true; tlh_teardown "$st"'\'' EXIT
exit 3')" 2>/dev/null || rc=$?
  [ "$rc" -eq 3 ] || fail "h5: a suite's own failing status must survive its own trap's teardown, got $rc"

  rc=0
  err=$(/bin/bash "$(child_suite errexit 'set -e
printf "%s\n" "$TLH_SANDBOX" >'"'$TLH_SANDBOX/errexit.sb'"'
tmux new-session -d -s brief -- true
sleep 0.3
tlh_run_bounded sh -c "exit 3"
echo "rc=$TLH_RC"')" 2>&1) || rc=$?
  [ "$rc" -eq 0 ] || fail "h5: a passing set -e suite must exit 0, got $rc: $err"
  case $err in *"rc=3"*) ;; *) fail "h5: under set -e a bounded run's failing status must be captured, got: $err" ;; esac
  sb=$(cat "$TLH_SANDBOX/errexit.sb" 2>/dev/null)
  [ -n "$sb" ] && [ ! -e "$sb" ] || fail "h5: a set -e suite's teardown must remove its sandbox"
}

# --- h6 ---------------------------------------------------------------------
# A fake plugin root whose liveness hook records how it was called, so the
# confirmation is observed at the hook rather than in the stub's own record.
h6() {
  local root out
  root="$TLH_SANDBOX/fake-root"
  mkdir -p "$root/scripts"
  cat >"$root/scripts/fleet-liveness.sh" <<'EOF'
#!/bin/sh
payload=$(cat)
{
  printf 'argv'
  for a; do printf '\t%s' "$a"; done
  printf '\npayload\t%s\ntoken\t%s\n' "$payload" "${PLANWRIGHT_WORKER_LAUNCH_TOKEN-unset}"
} >"$HOOK_LOG.$(sh -c 'echo "$PPID"')"
EOF
  chmod +x "$root/scripts/fleet-liveness.sh"
  out=$(TLH_PLUGIN_ROOT=$root /bin/bash "$(child_suite confirm '
hook_log="$TLH_SANDBOX/hook"
tlh_server_env "HOOK_LOG=$hook_log"
mkdir -p "$TLH_SANDBOX/w"
launch() {
  s=$1
  shift
  n=$(tlh_worker_count)
  tmux new-session -d -s "$s" -c "$TLH_SANDBOX/w" -- "$@"
  tlh_wait_workers $((n + 1)) 10
  rec=$(tlh_last_worker_record)
  printf "%s confirm=%s\n" "$s" "$(tlh_record_field "$rec" confirm)"
  for f in "$hook_log".*; do [ -f "$f" ] && { printf "%s hook:" "$s"; tr "\n" "|" <"$f"; echo; rm -f "$f"; }; done
  tmux kill-session -t "=$s"
}
launch s1 env PLANWRIGHT_WORKER_LAUNCH_TOKEN=0123abcd "$TLH_BIN/claude"
launch s2 "$TLH_BIN/claude" --continue
launch s3 "$TLH_BIN/claude" -r
tlh_knob worker-confirm off
launch s4 "$TLH_BIN/claude"
tlh_knob worker-confirm on
tlh_knob worker-exit 3
tmux new-session -d -s dies -c "$TLH_SANDBOX/w" -- "$TLH_BIN/claude"
tlh_wait_workers $(($(tlh_worker_count) + 1)) 10
t=0
while tmux has-session -t =dies 2>/dev/null && [ "$t" -lt 50 ]; do sleep 0.1; t=$((t + 1)); done
tmux has-session -t =dies 2>/dev/null && echo "dies: still live" || echo "dies: gone"
')" 2>&1)
  case $out in
    *"s1 confirm=0${TAB}0123abcd"*) ;;
    *) fail "h6: a default launch must confirm through the hook, with its own token, got: $out" ;;
  esac
  case $out in
    *"s1 hook:argv${TAB}hook${TAB}session-start|payload${TAB}"*'"source":"startup"'*"|token${TAB}0123abcd|"*) ;;
    *) fail "h6: the hook must get the session-start event, a startup payload, and the worker's token, got: $out" ;;
  esac
  case $out in *'s2 hook:'*'"source":"resume"'*) ;; *) fail "h6: --continue must confirm as a resume, got: $out" ;; esac
  case $out in *'s3 hook:'*'"source":"resume"'*) ;; *) fail "h6: -r must confirm as a resume, got: $out" ;; esac
  case $out in *"s4 confirm=off"*) ;; *) fail "h6: a fixture must be able to turn the confirmation off, got: $out" ;; esac
  case $out in *"s4 hook:"*) fail "h6: confirmation off must not call the hook, got: $out" ;; esac
  case $out in *"dies: gone"*) ;; *) fail "h6: a session whose worker exits must be gone, got: $out" ;; esac
}

# --- h7 ---------------------------------------------------------------------
h7() {
  local err n rec
  tmux new-session -d -s live.one -c "$wt" -- sleep 30
  tmux has-session -t =live_one || fail "h7: a dotted name must be stored with '.' written '_'"
  tmux has-session -t '=live_one:' || fail "h7: a '=<session>:' target must resolve"
  tmux has-session -t live_ || fail "h7: an unprefixed target must match a unique prefix"
  tmux has-session -t =live_ 2>/dev/null && fail "h7: an '=' target must match exactly"
  err=$(tmux new-session -d -s live.one -c "$wt" -- sleep 30 2>&1) \
    && fail "h7: a live name must be refused as a duplicate"
  case $err in "duplicate session: live_one") ;; *) fail "h7: a duplicate must be named as tmux stores it, got: $err" ;; esac
  tmux switch-client -t =live_one
  tlh_tmux_calls | grep -Eq "^switch-client${TAB}" \
    || fail "h7: a client move must land in the call records, or a fixture cannot assert its absence"

  tlh_knob server unreachable
  tmux has-session -t =live_one 2>/dev/null && fail "h7: an unreachable server must not answer live"
  tmux capture-pane -p -t =live_one: 2>/dev/null && fail "h7: an unreachable server must refuse every command"
  tmux new-session -d -s other -c "$wt" -- sleep 30 2>/dev/null \
    && fail "h7: an unreachable server must refuse new-session"
  tlh_knob server none
  err=$(tmux has-session -t =live_one 2>&1) && fail "h7: no server must not answer live"
  case $err in *"no server running"*) ;; *) fail "h7: no server must say so, got: $err" ;; esac
  tmux capture-pane -p -t =live_one: 2>/dev/null && fail "h7: no server must refuse every command"
  tlh_knob server up
  for k in fail duplicate; do
    tlh_knob new-session "$k"
    err=$(tmux new-session -d -s "knob.$k" -c "$wt" -- sleep 30 2>&1) \
      && fail "h7: new-session knob $k must refuse"
    tmux has-session -t "=knob_$k" 2>/dev/null && fail "h7: a refused new-session ($k) must create nothing"
  done
  case $err in "duplicate session: knob_duplicate") ;; *) fail "h7: the duplicate knob must name the session as tmux stores it, got: $err" ;; esac
  tlh_knob new-session ok

  # Command parsing: a word ending in ';' ends a command, '\;' escapes it, an
  # unknown command refuses the whole invocation, a failure stops the rest.
  n=$(tlh_worker_count)
  tmux new-session -d -s semi -c "$wt" -- "$TLH_BIN/claude" 'a\;' 'b;' has-session -t =semi \
    || fail "h7: a word ending in ';' must end the command"
  tlh_wait_workers $((n + 1)) 10 || return
  rec=$(tlh_last_worker_record)
  [ "$(tlh_record_field "$rec" argv)" = "a;${TAB}b" ] \
    || fail "h7: '\\;' must reach the command as ';' and a trailing ';' must be stripped, got: $(tlh_record_field "$rec" argv)"
  err=$(tmux new-session -d -s unknown -c "$wt" -- sleep 30 ';' no-such-command 2>&1) \
    && fail "h7: an unknown command must refuse the invocation"
  case $err in *"unknown command: no-such-command"*) ;; *) fail "h7: the refusal must name the command, got: $err" ;; esac
  tmux has-session -t =unknown 2>/dev/null && fail "h7: an invocation with an unknown command must run nothing"
  tmux has-session -t =nosuch ';' new-session -d -s after -c "$wt" -- sleep 30 2>/dev/null \
    && fail "h7: a failing command must fail the invocation"
  tmux has-session -t =after 2>/dev/null && fail "h7: a failing command must stop the commands after it"

  # remain-on-exit: on (the operator's global option) keeps a dead pane's
  # session; the launch's own set-option in the same invocation turns it off.
  tlh_knob remain-on-exit on
  tmux new-session -d -s keeps -c "$wt" -- true
  sleep 0.5
  tmux has-session -t =keeps || fail "h7: with remain-on-exit on, a session whose command exits must remain"
  tmux new-session -d -s goes -c "$wt" -- true ';' set-option -w remain-on-exit off
  wait_gone goes
  tmux has-session -t =goes 2>/dev/null && fail "h7: set-option -w remain-on-exit off in the launch must let the session go"
  tmux kill-session -t =keeps
  tlh_knob remain-on-exit off

  # A target is a session name, never a path into or out of the stub state.
  mkdir -p "$TLH_SANDBOX/outside"
  : >"$TLH_SANDBOX/outside/keep"
  tmux kill-session -t "=../../outside" 2>/dev/null && fail "h7: a path-shaped target must not resolve"
  [ -f "$TLH_SANDBOX/outside/keep" ] || fail "h7: a path-shaped target must never remove anything"

  # An unnamed session takes its session number, as tmux names it.
  n=$(tmux new-session -d -P -F '#{session_name}' -c "$wt" -- sleep 30)
  case $n in '' | *[!0-9]*) fail "h7: an unnamed session must be named by its number, got: $n" ;; esac
  tmux has-session -t "=$n" || fail "h7: an unnamed session must resolve by its number"
  tmux kill-session -t "=$n"

  # The last session gone, the server has exited, as tmux's does.
  tmux kill-session -t =live_one
  tmux kill-session -t =semi
  err=$(tmux has-session -t =live_one 2>&1) && fail "h7: a killed session must be gone"
  case $err in
    *"no server running"*) ;;
    *) fail "h7: with no session left the server must have exited, got: $err (live: $(tmux list-sessions 2>&1 | tr '\n' ' '))" ;;
  esac
}

for c in h1 h2 h3 h4 h5 h6 h7; do
  _before=$fails
  "$c"
  [ "$fails" -eq "$_before" ] && echo "ok $c" || true
done

if [ "$fails" -ne 0 ]; then
  echo "FAILED: $fails assertion(s)" >&2
  exit 1
fi
