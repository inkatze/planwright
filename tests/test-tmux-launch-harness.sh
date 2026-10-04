#!/bin/bash
# Self-test for the tmux launch fixture harness (tests/lib/tmux-launch-harness.sh)
# and its stubs. Each case below shows one harness property able to fail:
#   h1  a blocking launch fails within the bound with a hang diagnosis, and a
#       launch that returns is not mistaken for one (REQ-H1.1)
#   h2  a stub session's command sees the server's environment, not the
#       dispatcher's (REQ-H1.2)
#   h3  under the symlinked temporary directory, canonical path assertions
#       pass and a raw compare would not (REQ-H1.4)
#   h4  concurrent stub calls leave intact, non-interleaved records, and a
#       contested session name goes to exactly one caller (REQ-H1.4)
#   h5  a leaked stub process fails the suite's leak check; reaped, it does
#       not (REQ-H1.4)
#   h6  the stub worker fires its startup confirmation by default, carrying
#       the launch token from its own environment, and not when turned off
#   h7  the stub tmux's refusal knobs and liveness answers
#
# Runs standalone under /bin/bash (the bash 3.2 floor):
#   ./tests/test-tmux-launch-harness.sh
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

# shellcheck source=tests/lib/tmux-launch-harness.sh
. "$here/lib/tmux-launch-harness.sh"

wt="$TLH_SANDBOX/wt"
mkdir -p "$wt"

# --- h1 ---------------------------------------------------------------------
h1() {
  [ "$TLH_LAUNCH_BOUND_SECONDS" -gt "$TLH_CONFIRM_CAP_SECONDS" ] \
    || fail "h1: the default bound must exceed the confirm cap"
  tlh_knob new-session block
  tlh_run_bounded --bound 2 tmux new-session -d -s blocker -c "$wt" -- "$TLH_BIN/claude"
  tlh_knob new-session ok
  [ "$TLH_RC" -eq 124 ] || fail "h1: a blocking launch must be cut off as a hang (rc 124), got $TLH_RC"
  [ "$TLH_ELAPSED" -le 3 ] || fail "h1: a blocking launch must fail within its bound, took ${TLH_ELAPSED}s"
  case $TLH_DIAG in
    *"did not return within 2s"*) ;;
    *) fail "h1: the diagnosis must name the hang and the bound, got: $TLH_DIAG" ;;
  esac
  _before=$fails
  tlh_expect_returned "h1 probe" 2>/dev/null
  _after=$fails
  fails=$_before
  [ "$_after" -eq $((_before + 1)) ] || fail "h1: tlh_expect_returned must fail a hung run"
  tmux kill-session -t =blocker 2>/dev/null

  tlh_run_bounded tmux new-session -d -s quick -P -F "#{session_name}${TAB}#{window_id}" -c "$wt" -- sleep 30
  tlh_expect_returned "h1: a returning launch"
  [ "$TLH_RC" -eq 0 ] || fail "h1: a returning launch must keep its own status, got $TLH_RC: $TLH_ERR"
  case $TLH_OUT in
    "quick${TAB}@"[0-9]*) ;;
    *) fail "h1: -P -F must print the session name and window id, got: $TLH_OUT" ;;
  esac
  tmux kill-session -t =quick
}

# --- h2 ---------------------------------------------------------------------
h2() {
  tlh_server_env TLH_PROBE_SERVER_ONLY=from-server
  TLH_PROBE_DISPATCHER_ONLY=from-dispatcher
  export TLH_PROBE_DISPATCHER_ONLY
  _n=$(tlh_worker_records | wc -l | tr -d ' ')
  tlh_run_bounded tmux new-session -d -s envprobe -c "$wt" -- "$TLH_BIN/claude" envprobe
  tlh_expect_returned "h2: the probe launch"
  unset TLH_PROBE_DISPATCHER_ONLY
  tlh_wait_workers $((_n + 1)) 10 || return
  rec=$(tlh_worker_records | tail -n 1)
  [ "$(tlh_worker_env "$rec" TLH_PROBE_SERVER_ONLY)" = from-server ] \
    || fail "h2: the session's command must see the server's environment"
  if tlh_worker_env "$rec" TLH_PROBE_DISPATCHER_ONLY >/dev/null; then
    fail "h2: the session's command must not see the dispatcher's environment"
  fi
  tmux kill-session -t =envprobe
}

# --- h3 ---------------------------------------------------------------------
h3() {
  [ "$TLH_SANDBOX" != "$(tlh_canon "$TLH_SANDBOX")" ] \
    || fail "h3: the sandbox must sit under a symlinked directory, or the canonical compare proves nothing"
  _n=$(tlh_worker_records | wc -l | tr -d ' ')
  tlh_run_bounded tmux new-session -d -s pathprobe -c "$wt" -- "$TLH_BIN/claude"
  tlh_expect_returned "h3: the probe launch"
  tlh_wait_workers $((_n + 1)) 10 || return
  rec=$(tlh_worker_records | tail -n 1)
  cwd=$(tlh_record_field "$rec" cwd)
  [ "$cwd" != "$wt" ] || fail "h3: the worker's physical cwd must differ from the symlinked path as given"
  tlh_assert_path_eq "h3: the worker's start directory" "$wt" "$cwd"
  _before=$fails
  tlh_assert_path_eq "h3 probe" "$wt" "$TLH_SANDBOX" 2>/dev/null
  _after=$fails
  fails=$_before
  [ "$_after" -eq $((_before + 1)) ] || fail "h3: tlh_assert_path_eq must fail on different paths"
  tmux kill-session -t =pathprobe

  # A -c that names no directory starts in the server's HOME, without a word.
  _n=$(tlh_worker_records | wc -l | tr -d ' ')
  tlh_run_bounded tmux new-session -d -s nodir -c "$TLH_SANDBOX/missing" -- "$TLH_BIN/claude"
  [ "$TLH_RC" -eq 0 ] || fail "h3: a missing -c must not fail the stub launch, got $TLH_RC"
  tlh_wait_workers $((_n + 1)) 10 || return
  tlh_assert_path_eq "h3: a missing start directory falls back to the server HOME" \
    "$TLH_SANDBOX/server-home" "$(tlh_record_field "$(tlh_worker_records | tail -n 1)" cwd)"
  tmux kill-session -t =nodir
}

# --- h4 ---------------------------------------------------------------------
h4() {
  _pad=$(awk 'BEGIN { while (i++ < 2000) printf "x" }')
  _c0=$(tlh_tmux_calls | wc -l | tr -d ' ')
  _w0=$(tlh_worker_records | wc -l | tr -d ' ')
  for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16; do
    tmux display-message -p "msg-$i-$_pad" >/dev/null &
  done
  for i in 1 2 3 4 5 6; do
    tmux new-session -d -s "conc$i" -c "$wt" -- "$TLH_BIN/claude" "worker-$i-$_pad" &
  done
  for i in 1 2; do
    tmux new-session -d -s contested -c "$wt" -- sleep 30 2>"$TLH_SANDBOX/contested.$i" &
  done
  wait
  calls=$(tlh_tmux_calls | tail -n +$((_c0 + 1)))
  [ "$(printf '%s\n' "$calls" | wc -l | tr -d ' ')" -eq 24 ] \
    || fail "h4: 24 concurrent calls must leave 24 records, got $(printf '%s\n' "$calls" | wc -l)"
  for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16; do
    printf '%s\n' "$calls" | grep -qx "display-message${TAB}-p${TAB}msg-$i-$_pad" \
      || fail "h4: call record $i is missing or torn"
  done
  for i in 1 2 3 4 5 6; do
    printf '%s\n' "$calls" | grep -qx "new-session${TAB}-d${TAB}-s${TAB}conc$i${TAB}-c${TAB}$wt${TAB}--${TAB}$TLH_BIN/claude${TAB}worker-$i-$_pad" \
      || fail "h4: new-session record $i is missing or torn"
  done
  tlh_wait_workers $((_w0 + 6)) 10 || return
  for i in 1 2 3 4 5 6; do
    _hit=0
    for rec in $(tlh_worker_records | tail -n 6); do
      [ "$(tlh_record_field "$rec" argv)" = "worker-$i-$_pad" ] && _hit=$((_hit + 1))
      [ -n "$(tlh_record_field "$rec" pid)" ] && [ -n "$(tlh_record_field "$rec" cwd)" ] \
        || fail "h4: a worker record is torn: $rec"
    done
    [ "$_hit" -eq 1 ] || fail "h4: worker $i must leave exactly one intact record, found $_hit"
  done
  _dups=$(cat "$TLH_SANDBOX"/contested.* | grep -c '^duplicate session: contested$')
  [ "$_dups" -eq 1 ] || fail "h4: exactly one of two racing creates must be refused as a duplicate, got $_dups"
  for i in 1 2 3 4 5 6; do tmux kill-session -t "=conc$i"; done
  tmux kill-session -t =contested
}

# --- h5 ---------------------------------------------------------------------
# Child suites source the harness on their own; one leaks with its reap
# skipped, one reaps.
h5() {
  child="$TLH_SANDBOX/child.sh"
  cat >"$child" <<EOF
set -u
fail() { echo "FAIL: \$1" >&2; }
. '$here/lib/tmux-launch-harness.sh'
mkdir -p "\$TLH_SANDBOX/w"
tmux new-session -d -s leak -c "\$TLH_SANDBOX/w" -- sleep 60
tlh_stub_pids_alive >'$TLH_SANDBOX/child.pids'
EOF
  err=$(TLH_REAP=0 /bin/bash "$child" 2>&1)
  rc=$?
  leaked=$(cat "$TLH_SANDBOX/child.pids")
  [ -n "$leaked" ] || fail "h5: the leaking child started no process to leak"
  [ "$rc" -ne 0 ] || fail "h5: a leaked stub process must fail the suite"
  case $err in
    *"leaked stub process"*) ;;
    *) fail "h5: the leak must be named, got: $err" ;;
  esac
  for p in $leaked; do kill "$p" 2>/dev/null; done

  err=$(/bin/bash "$child" 2>&1)
  rc=$?
  [ "$rc" -eq 0 ] || fail "h5: a reaped suite must pass its leak check, got $rc: $err"
  while read -r p; do
    kill -0 "$p" 2>/dev/null && fail "h5: the reaper left pid $p running"
  done <"$TLH_SANDBOX/child.pids"
}

# --- h6 ---------------------------------------------------------------------
h6() {
  _n=$(tlh_worker_records | wc -l | tr -d ' ')
  tlh_run_bounded tmux new-session -d -s confirm -c "$wt" -- \
    env PLANWRIGHT_WORKER_LAUNCH_TOKEN=0123abcd "$TLH_BIN/claude"
  tlh_expect_returned "h6: the confirming launch"
  tlh_wait_workers $((_n + 1)) 10 || return
  rec=$(tlh_worker_records | tail -n 1)
  case $(tlh_record_field "$rec" confirm) in
    [0-9]*"${TAB}0123abcd") ;;
    *) fail "h6: the worker must fire its confirmation with its own launch token, got: $(tlh_record_field "$rec" confirm)" ;;
  esac
  tmux kill-session -t =confirm

  tlh_knob worker-confirm off
  tlh_run_bounded tmux new-session -d -s quiet -c "$wt" -- "$TLH_BIN/claude"
  tlh_wait_workers $((_n + 2)) 10 || return
  [ "$(tlh_record_field "$(tlh_worker_records | tail -n 1)" confirm)" = off ] \
    || fail "h6: a fixture must be able to turn the confirmation off"
  tlh_knob worker-confirm on
  tmux kill-session -t =quiet

  tlh_knob worker-exit 3
  tlh_run_bounded tmux new-session -d -s dies -c "$wt" -- "$TLH_BIN/claude"
  tlh_wait_workers $((_n + 3)) 10 || return
  _t=0
  while tmux has-session -t =dies 2>/dev/null && [ "$_t" -lt 50 ]; do
    sleep 0.1
    _t=$((_t + 1))
  done
  tmux has-session -t =dies 2>/dev/null && fail "h6: a session whose worker exits must be gone"
  tlh_knob worker-exit run
}

# --- h7 ---------------------------------------------------------------------
h7() {
  tmux new-session -d -s live.one -c "$wt" -- sleep 30
  tmux has-session -t =live_one || fail "h7: a dotted name must be stored with '.' written '_'"
  tmux has-session -t '=live_one:' || fail "h7: a '=<session>:' target must resolve"
  tmux has-session -t live_ || fail "h7: an unprefixed target must match a unique prefix"
  tmux has-session -t =live_ 2>/dev/null && fail "h7: an '=' target must match exactly"
  tmux new-session -d -s live.one -c "$wt" -- sleep 30 2>/dev/null \
    && fail "h7: a live name must be refused as a duplicate"
  tlh_knob server unreachable
  tmux has-session -t =live_one 2>/dev/null && fail "h7: an unreachable server must not answer live"
  tmux new-session -d -s other -c "$wt" -- sleep 30 2>/dev/null \
    && fail "h7: an unreachable server must refuse new-session"
  tlh_knob server none
  _err=$(tmux has-session -t =live_one 2>&1) && fail "h7: no server must not answer live"
  case $_err in *"no server running"*) ;; *) fail "h7: no server must say so, got: $_err" ;; esac
  tlh_knob server up
  for k in fail duplicate; do
    tlh_knob new-session "$k"
    tmux new-session -d -s "knob-$k" -c "$wt" -- sleep 30 2>/dev/null \
      && fail "h7: new-session knob $k must refuse"
    tmux has-session -t "=knob-$k" 2>/dev/null && fail "h7: a refused new-session ($k) must create nothing"
  done
  tlh_knob new-session ok
  tmux new-session -d -s chained -c "$wt" -- sleep 30 ';' set-option -w remain-on-exit off \
    || fail "h7: a ';'-chained invocation must run both commands"
  tmux kill-session -t =live_one
  tmux kill-session -t =chained
  tmux has-session -t =live_one 2>/dev/null && fail "h7: a killed session must be gone"
  tlh_tmux_calls | grep -q "^switch-client\|^attach-session" \
    && fail "h7: the self-test itself must never move a client"
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
