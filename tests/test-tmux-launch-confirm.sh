#!/bin/bash
# The tmux launch's confirm step, on the launch fixture harness
# (tests/lib/tmux-launch-harness.sh): the stub worker confirms through the real
# SessionStart arm unless a fixture turns that off (fleet-hardening REQ-G1.5,
# D-15). Every launch runs under the harness's bounded runner.
#   c1  a worker that confirms reports started (exit 0)
#   c2  a session that exits before confirming reports failed-at-startup
#       (exit 16) and leaves the dispatch marker cleared
#   c3  a session that stays up unconfirmed reports started-unconfirmed (exit
#       14) with the session and handle, and the task is then in flight: a
#       repeat dispatch aborts rather than starting a second worker
#   c4  an unreachable server reads as started-unconfirmed, never failed,
#       even once the session is gone
#   c5  a row stamped before the dispatch start, a row without this launch's
#       token, a missing token, and an unknown start time do not confirm; the
#       same row with the right token and start does
#   c6  a flight whose worker dies at startup reports failed-at-startup and
#       names the hand removal of its worktree; one that confirms reports
#       started
#   c7  every exit status the primitive returns is in its usage header, and
#       the confirm step makes no model or API call (REQ-E1.3)
#
# Runs standalone under /bin/bash (the bash 3.2 floor):
#   ./tests/test-tmux-launch-confirm.sh
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

confirm_field() {
  printf '%s\n' "$TLH_OUT" | awk -F"$TAB" -v k="$1" '$1 == "confirm" && $2 == k { print $3; exit }'
}

# --- c1: started -----------------------------------------------------------------
c1() {
  new_case
  tlh_knob worker-confirm on
  tlh_run_bounded "$PRIM" dispatch demo 1 --repo-root "$P"
  tlh_knob worker-confirm off
  tlh_expect_returned c1 || return
  [ "$TLH_RC" -eq 0 ] || fail "c1: a confirming worker must report started (exit 0), got $TLH_RC ($TLH_ERR)"
  [ "$(confirm_field outcome)" = started ] || fail "c1: the report does not say started: $TLH_OUT"
  [ -e "$C/markers/1" ] || fail "c1: a started dispatch lost its marker"
}

# --- c2: failed-at-startup --------------------------------------------------------
c2() {
  new_case
  tlh_knob worker-exit 0
  tlh_run_bounded "$PRIM" dispatch demo 2 --repo-root "$P"
  tlh_knob worker-exit run
  tlh_expect_returned c2 || return
  [ "$TLH_RC" -eq 16 ] || fail "c2: a session that exits unconfirmed must report failed-at-startup (exit 16), got $TLH_RC ($TLH_ERR)"
  [ "$(confirm_field outcome)" = failed-at-startup ] || fail "c2: the report does not say failed-at-startup: $TLH_OUT"
  case $(confirm_field reason) in *'session ended'*) ;; *) fail "c2: the report does not name the cause: $(confirm_field reason)" ;; esac
  [ ! -e "$C/markers/2" ] || fail "c2: the dispatch marker was not cleared"
  [ -d "$PP/.claude/worktrees/demo-task-2" ] || fail "c2: the worktree a retry adopts was removed"
}

# --- c3: started-unconfirmed ------------------------------------------------------
c3() {
  local sess
  new_case
  tlh_run_bounded "$PRIM" dispatch demo 3 --repo-root "$P"
  tlh_expect_returned c3 || return
  [ "$TLH_RC" -eq 14 ] || fail "c3: an unconfirmed live session must report started-unconfirmed (exit 14), got $TLH_RC ($TLH_ERR)"
  sess=$(expect_session "$PP" demo-task-3)
  [ "$(confirm_field outcome)" = started-unconfirmed ] || fail "c3: the report does not say started-unconfirmed: $TLH_OUT"
  [ "$(confirm_field session)" = "$sess" ] || fail "c3: the report does not carry the session"
  [ "$(confirm_field handle)" = tmux-demo-task-3 ] || fail "c3: the report does not carry the handle"
  [ "$TLH_ELAPSED" -ge $((TLH_CONFIRM_CAP_SECONDS - 1)) ] \
    || fail "c3: the wait ended after ${TLH_ELAPSED}s, before the ${TLH_CONFIRM_CAP_SECONDS}s cap"
  [ -e "$C/markers/3" ] || fail "c3: an unconfirmed dispatch cleared its marker"
  # Placed: a repeat dispatch takes no re-dispatch path.
  tlh_run_bounded "$PRIM" dispatch demo 3 --repo-root "$P"
  [ "$TLH_RC" -eq 3 ] || fail "c3: a repeat dispatch over an unconfirmed worker must abort in flight (exit 3), got $TLH_RC"
  [ "$(tlh_worker_count)" -ge 1 ] && [ "$(calls_matching new-session | grep -cF "$TAB$sess$TAB")" = 1 ] \
    || fail "c3: a second session was created over the unconfirmed worker"
}

# launch_only <id> — a launch with no confirm step; sets SESS, HANDLE, SINCE, TOKEN.
launch_only() {
  tlh_run_bounded "$PRIM" dispatch demo "$1" --repo-root "$P" --launch-only
  [ "$TLH_RC" -eq 0 ] || fail "launch_only $1: exit $TLH_RC ($TLH_ERR)"
  SESS=$(launch_field session)
  HANDLE=$(launch_field handle)
  SINCE=$(launch_field since)
  TOKEN=$(launch_field token)
  printf '%s' "$TOKEN" | grep -Eq '^[0-9a-f]{16,64}$' || fail "launch_only $1: the report carries no launch token ('$TOKEN')"
}

# --- c4: an unreachable server ----------------------------------------------------
c4() {
  new_case
  launch_only 4
  tlh_knob server unreachable
  tlh_run_bounded "$PRIM" confirm --session "$SESS" --handle "$HANDLE" --since "$SINCE" --token "$TOKEN"
  [ "$TLH_RC" -eq 14 ] || fail "c4: an unreachable server must read started-unconfirmed (exit 14), got $TLH_RC ($TLH_ERR)"
  case $(confirm_field reason) in *'could not say'*) ;; *) fail "c4: the reason does not say tmux could not answer: $(confirm_field reason)" ;; esac
  # Gone, but the server cannot say so: still never failed.
  kill "$(tlh_session_pid "$SESS")" 2>/dev/null
  tlh_run_bounded "$PRIM" confirm --session "$SESS" --handle "$HANDLE" --since "$SINCE" --token "$TOKEN"
  [ "$TLH_RC" -eq 14 ] || fail "c4: a session lost behind an unreachable server must not read failed, got $TLH_RC"
  tlh_knob server up
}

# attn <args...> — the case's attention store.
attn() {
  /bin/sh "$ROOT/scripts/fleet-attention.sh" "$@" >/dev/null 2>&1
}

# --- c5: rows that do not confirm -------------------------------------------------
c5() {
  local ts other=fedcba9876543210fedcba9876543210
  new_case
  launch_only 5
  attn heartbeat "$HANDLE" demo:5 working --launch-token "$TOKEN" || fail "c5: setup heartbeat failed"
  ts=$(awk -F"$TAB" -v w="$HANDLE" '$1 == w { print $4 }' "$C/fleet/attention/state")
  # Stamped before the dispatch start.
  tlh_run_bounded "$PRIM" confirm --session "$SESS" --handle "$HANDLE" --since "$((ts + 1))" --token "$TOKEN"
  [ "$TLH_RC" -eq 14 ] || fail "c5: a row stamped before the dispatch start confirmed (exit $TLH_RC)"
  # An unknown start time.
  tlh_run_bounded "$PRIM" confirm --session "$SESS" --handle "$HANDLE" --since unknown --token "$TOKEN"
  [ "$TLH_RC" -eq 14 ] || fail "c5: an unknown start time confirmed (exit $TLH_RC)"
  # No token given.
  tlh_run_bounded "$PRIM" confirm --session "$SESS" --handle "$HANDLE" --since "$ts"
  [ "$TLH_RC" -eq 14 ] || fail "c5: a confirm with no token confirmed (exit $TLH_RC)"
  # The positive control: the same row, the right token and start.
  tlh_run_bounded "$PRIM" confirm --session "$SESS" --handle "$HANDLE" --since "$ts" --token "$TOKEN"
  [ "$TLH_RC" -eq 0 ] || fail "c5: the matching row did not confirm (exit $TLH_RC, $TLH_ERR)"
  # A row for the handle carrying another launch's token.
  attn heartbeat "$HANDLE" demo:5 working --launch-token "$other" || fail "c5: setup heartbeat failed"
  tlh_run_bounded "$PRIM" confirm --session "$SESS" --handle "$HANDLE" --since "$ts" --token "$TOKEN"
  [ "$TLH_RC" -eq 14 ] || fail "c5: a row without this launch's token confirmed (exit $TLH_RC)"
}

# --- c6: the flight dispatch ------------------------------------------------------
c6() {
  local wt
  new_case
  mkdir -p "$C/adopter" "$C/claude"
  export CLAUDE_DIR="$C/claude" PLANWRIGHT_ADOPTER_OVERLAY="$C/adopter" PLANWRIGHT_FLIGHT_LOCK_WAIT=0 \
    PLANWRIGHT_REPO_ROOT="$P"
  printf 'Fix the typo in the README heading.\n' >"$C/ask.txt"
  printf 'visual flight: a one-line wording change\n' >"$C/grounds.txt"
  tlh_knob worker-exit 0
  tlh_run_bounded "$FLIGHT" dispatch readme-typo --backend tmux --ask-file "$C/ask.txt" \
    --grounds-file "$C/grounds.txt" --home file --repo-root "$P"
  tlh_knob worker-exit run
  tlh_expect_returned c6 || return
  [ "$TLH_RC" -eq 5 ] || fail "c6: a flight whose worker died at startup must fail (exit 5), got $TLH_RC ($TLH_ERR)"
  [ "$(report_field outcome)" = failed-at-startup ] || fail "c6: the flight report does not say failed-at-startup: $TLH_OUT"
  case $(report_field failed) in *'died at startup'*) ;; *) fail "c6: the failed line does not name the cause: $(report_field failed)" ;; esac
  wt=$(report_field worktree)
  case $(report_field reask) in *"worktree remove '$wt'"*) ;; *) fail "c6: the reask does not name the hand removal of $wt: $(report_field reask)" ;; esac
  tlh_knob worker-confirm on
  tlh_run_bounded "$FLIGHT" dispatch readme-typo --backend tmux --ask-file "$C/ask.txt" \
    --grounds-file "$C/grounds.txt" --home file --repo-root "$P"
  tlh_knob worker-confirm off
  [ "$TLH_RC" -eq 0 ] || fail "c6: a confirming flight must be placed (exit 0), got $TLH_RC ($TLH_ERR)"
  [ "$(report_field outcome)" = started ] || fail "c6: a confirming flight does not report started: $TLH_OUT"
  unset CLAUDE_DIR PLANWRIGHT_ADOPTER_OVERLAY PLANWRIGHT_FLIGHT_LOCK_WAIT PLANWRIGHT_REPO_ROOT
}

# --- c7: the header and the source ------------------------------------------------
c7() {
  local codes c header body
  header=$(awk '/^# Exit codes:/,/^#$/' "$PRIM")
  codes=$(grep -v '^[[:space:]]*#' "$PRIM" | grep -Eo '(^|[^A-Za-z_])exit [0-9]+' | grep -Eo '[0-9]+$' | sort -un)
  [ -n "$codes" ] || fail "c7: no exit status found in the primitive"
  for c in $codes; do
    printf '%s\n' "$header" | grep -Eq "^#   $c( |\$)" || fail "c7: exit $c is not documented in the usage header"
  done
  body=$(awk '/^(store_confirms|confirm_wait|confirm_report|confirm_exit|do_confirm)\(\) \{/,/^}/' "$PRIM")
  [ "$(printf '%s\n' "$body" | grep -c '() {')" = 5 ] || fail "c7: the confirm step's functions were not all found"
  printf '%s\n' "$body" | grep -v '^[[:space:]]*#' | grep -Eiq 'curl|wget|https?:|anthropic|claude' \
    && fail "c7: the confirm step makes a model or network call"
  return 0
}

c1
c2
c3
c4
c5
c6
c7

[ "$fails" -eq 0 ] || {
  echo "test-tmux-launch-confirm: $fails failure(s)" >&2
  exit 1
}
echo "ok: test-tmux-launch-confirm"
