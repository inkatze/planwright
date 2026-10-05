#!/bin/bash
# The flight relaunch arm of the dispatch primitive,
# `fleet-dispatch-worktree.sh dispatch --flight <id> --brief <brief> --relaunch`,
# on the launch fixture harness (tests/lib/tmux-launch-harness.sh). The crash
# policy relaunches a dead flight worker through it, so it must start the new
# worker in the flight's own worktree and branch through the one guarded
# launch, and create, move, or remove nothing (tower-front-door REQ-F1.5).
#   r1  a relaunch over a dead worker starts one new worker in the same physical
#       worktree, on the same branch with its commits, with the flight's brief;
#       it creates no worktree and no branch, and registers the new worker
#       under the flight's handle with the new session as its death handle
#   r2  a relaunch while the worker's session still runs is refused as
#       already-in-flight, and no worker starts
#   r3  a relaunch of a flight with no placed worktree is refused, and nothing
#       is created
#   r4  --relaunch is a flight option that needs the brief and a launch: it is
#       refused without --flight, without --brief, and beside --no-attach or
#       --attach-dry-run
#   r5  a relaunch whose launch fails leaves the flight's worktree and branch
#       where they were
#
# Runs standalone under /bin/bash (the bash 3.2 floor):
#   ./tests/test-flight-relaunch.sh
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

# place_flight — a fresh case with one flight placed and its worker started
# through the flight dispatch, as the tower does. Sets FID, BRIEF, WT, SESS,
# and HANDLE.
place_flight() {
  new_case
  mkdir -p "$C/adopter" "$C/claude"
  export CLAUDE_DIR="$C/claude" PLANWRIGHT_ADOPTER_OVERLAY="$C/adopter" PLANWRIGHT_REPO_ROOT="$P"
  printf 'Fix the typo in the README heading.\n' >"$C/ask.txt"
  printf 'visual flight: a one-line wording change\n' >"$C/grounds.txt"
  tlh_run_bounded "$FLIGHT" dispatch readme-typo --backend tmux --ask-file "$C/ask.txt" \
    --grounds-file "$C/grounds.txt" --home file --repo-root "$P"
  [ "$TLH_RC" -eq 0 ] || fail "fixture: the flight dispatch failed ($TLH_RC: $TLH_ERR)"
  FID=$(report_field flight)
  BRIEF=$(report_field brief)
  WT=$(report_field worktree)
  HANDLE="tmux-flight-$FID"
  SESS=$(expect_session "$PP" "flight-$FID")
}

# kill_worker — end the worker's session, as a crash does.
kill_worker() {
  "$TLH_BIN/tmux" kill-session -t "=$SESS" >/dev/null 2>&1 || fail "fixture: could not end the worker's session"
}

relaunch() {
  tlh_run_bounded "$PRIM" dispatch --flight "$FID" --brief "$BRIEF" --relaunch --launch-only --repo-root "$P" "$@"
}

r1() {
  local head_before wt_list_before workers_before rec death adds
  place_flight
  printf 'work\n' >"$WT/WORK.md"
  gitc "$WT" add -A
  gitc "$WT" commit -q -m "wip: the worker's first commit"
  head_before=$(gitc "$WT" rev-parse HEAD)
  wt_list_before=$(gitc "$P" worktree list --porcelain | grep '^worktree ')
  workers_before=$(tlh_worker_count)
  kill_worker
  relaunch
  tlh_expect_returned r1 || return
  [ "$TLH_RC" -eq 0 ] || fail "r1: a relaunch over a dead worker must start it (rc $TLH_RC: $TLH_ERR)"
  tlh_wait_workers "$((workers_before + 1))" 10 || fail "r1: no new worker started"
  rec=$(tlh_last_worker_record)
  tlh_assert_path_eq "r1: the new worker's directory" "$WT" "$(tlh_record_field "$rec" cwd)"
  grep "^argv" "$rec" | grep -Fq "Read $BRIEF and follow it exactly." \
    || fail "r1: the new worker was not handed the flight's brief: $(grep '^argv' "$rec")"
  [ "$(gitc "$WT" rev-parse HEAD)" = "$head_before" ] || fail "r1: the relaunch moved the flight's branch"
  [ "$(gitc "$WT" rev-parse --abbrev-ref HEAD)" = "planwright/flight/$FID" ] \
    || fail "r1: the relaunched worktree is not on the flight's branch"
  [ "$(gitc "$P" worktree list --porcelain | grep '^worktree ')" = "$wt_list_before" ] \
    || fail "r1: the relaunch changed the worktree list"
  adds=$(calls_matching new-session | grep -cF "$TAB-s$TAB$SESS$TAB")
  [ "$adds" = 2 ] || fail "r1: expected the dispatch's and the relaunch's new-session calls, got $adds"
  [ "$(registry_col 2 | tail -n 1)" = "$HANDLE" ] || fail "r1: the new worker is not registered under the flight's handle"
  [ "$(registry_col 3 | tail -n 1)" = "flight:$FID" ] || fail "r1: the new worker's record does not carry the flight's scope"
  death=$(registry_col 7 | tail -n 1)
  case $death in
    "tmux-window $SESS @"*) ;;
    *) fail "r1: the new worker's death handle is not its session ('$death')" ;;
  esac
  [ "$(launch_field session)" = "$SESS" ] || fail "r1: the relaunch report names no session: $TLH_OUT"
}

r2() {
  local workers_before
  place_flight
  workers_before=$(tlh_worker_count)
  relaunch
  tlh_expect_returned r2 || return
  [ "$TLH_RC" -eq 3 ] || fail "r2: a relaunch beside a live session must be refused as already-in-flight (rc $TLH_RC: $TLH_ERR)"
  sleep 1
  [ "$(tlh_worker_count)" = "$workers_before" ] || fail "r2: a refused relaunch started a worker"
}

r3() {
  local missing
  place_flight
  kill_worker
  missing=nowt-0123abcd
  mkdir -p "$C/fleet/flights/$missing"
  chmod 700 "$C/fleet/flights/$missing"
  printf '# brief\n' >"$C/fleet/flights/$missing/brief.md"
  tlh_run_bounded "$PRIM" dispatch --flight "$missing" --brief "$C/fleet/flights/$missing/brief.md" \
    --relaunch --launch-only --repo-root "$P"
  tlh_expect_returned r3 || return
  [ "$TLH_RC" -ne 0 ] || fail "r3: a relaunch with no placed worktree must be refused"
  [ ! -e "$P/.claude/worktrees/flight-$missing" ] || fail "r3: a refused relaunch created a worktree"
  gitc "$P" show-ref --verify --quiet "refs/heads/planwright/flight/$missing" \
    && fail "r3: a refused relaunch created a branch"
  return 0
}

r4() {
  place_flight
  kill_worker
  tlh_run_bounded "$PRIM" dispatch demo 3 --relaunch --repo-root "$P"
  [ "$TLH_RC" -eq 2 ] || fail "r4: --relaunch without --flight must be refused (rc $TLH_RC)"
  tlh_run_bounded "$PRIM" dispatch --flight "$FID" --relaunch --launch-only --repo-root "$P"
  [ "$TLH_RC" -eq 2 ] || fail "r4: --relaunch without --brief must be refused (rc $TLH_RC)"
  tlh_run_bounded "$PRIM" dispatch --flight "$FID" --brief "$BRIEF" --relaunch --no-attach --repo-root "$P"
  [ "$TLH_RC" -eq 2 ] || fail "r4: --relaunch beside --no-attach must be refused (rc $TLH_RC)"
  tlh_run_bounded "$PRIM" dispatch --flight "$FID" --brief "$BRIEF" --relaunch --attach-dry-run --repo-root "$P"
  [ "$TLH_RC" -eq 2 ] || fail "r4: --relaunch beside --attach-dry-run must be refused (rc $TLH_RC)"
}

r5() {
  local head_before
  place_flight
  head_before=$(gitc "$WT" rev-parse HEAD)
  kill_worker
  tmux_shim "$C/hang" hang-new
  PATH="$C/hang:$PATH" PLANWRIGHT_DISPATCH_TMUX_TIMEOUT=2 tlh_run_bounded --bound 25 \
    "$PRIM" dispatch --flight "$FID" --brief "$BRIEF" --relaunch --launch-only --repo-root "$P"
  tlh_expect_returned r5 || return
  [ "$TLH_RC" -ne 0 ] || fail "r5: a hung relaunch must fail"
  [ -d "$WT" ] || fail "r5: a failed relaunch removed the flight's worktree"
  gitc "$P" show-ref --verify --quiet "refs/heads/planwright/flight/$FID" \
    || fail "r5: a failed relaunch removed the flight's branch"
  [ "$(gitc "$WT" rev-parse HEAD)" = "$head_before" ] || fail "r5: a failed relaunch moved the flight's branch"
}

r1
r2
r3
r4
r5

[ "$fails" -eq 0 ] || {
  echo "test-flight-relaunch: $fails failure(s)" >&2
  exit 1
}
echo "ok: test-flight-relaunch"
