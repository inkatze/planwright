#!/bin/bash
# Tests for scripts/mc-keeper.sh — the session-keeper duty: retire a tracked
# session once its pull request lands, and pipelining, the next ready unit
# named for dispatch while another waits on CI (mission-control REQ-D1.5,
# REQ-M1.3, REQ-M1.4; D-10, D-27).
#
# Runs standalone under /bin/bash (the bash 3.2 floor):
#   ./tests/test-mc-keeper.sh
set -u
LC_ALL=C
export LC_ALL
unset CDPATH
# Fixture git calls must reach the fixture repositories, never one an
# inherited selector (a git hook's GIT_DIR, say) points at.
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY GIT_CONFIG_PARAMETERS GIT_CONFIG_COUNT

here=$(cd "$(dirname "$0")" && pwd)
repo_root=$(cd "$here/.." && pwd)

failures=0
fail() {
  echo "FAIL: $1" >&2
  failures=$((failures + 1))
}
ok() { echo "ok: $1"; }

tmp=$(mktemp -d "${TMPDIR:-/tmp}/test-mc-keeper.XXXXXX") || exit 1
tmp=$(cd "$tmp" && pwd -P) || exit 1
trap 'rm -rf "$tmp"' EXIT

# shellcheck source=tests/lib/mission-control-fixture.sh
. "$here/lib/mission-control-fixture.sh"

tab=$(printf '\t')
reset_mc_fixture
cat >"$tracked" <<EOF
mission_control_programs: [alpha]
program_alpha_repositories: [$repo]
program_alpha_spec_root: $repo/specs
program_alpha_home: $tmp/mchome
program_alpha_budget: {host_load: 1000000}
EOF
ledger="$fleet/mission-control/alpha/keeper.tsv"

mkdir -p "$tmp/bin"
cat >"$tmp/bin/gh" <<EOF
#!/bin/sh
case "\$*" in
  *"pr view 7 "*) cat "$tmp/state7" ;;
  *"pr view 8 "*) cat "$tmp/state8" ;;
  *) exit 1 ;;
esac
EOF
chmod +x "$tmp/bin/gh"
echo OPEN >"$tmp/state8"

# ---------------------------------------------------------------------------
# REQ-D1.5: a session whose pull request landed is retired and dropped; an
# open one stays; a failed read keeps it.
# ---------------------------------------------------------------------------
mc_run mc-keeper.sh track --program alpha --session mc-alpha-worker-one --repo acme/web --pr 7
expect_rc "track" 0
mc_run mc-keeper.sh track --program alpha --session mc-alpha-worker-two --repo acme/web --pr 8
mc_run mc-keeper.sh track --program alpha --session mc-alpha-worker-bad --repo acme/web --pr 9
mc_run mc-keeper.sh track --program alpha --session mc-alpha-worker-one --repo acme/web --pr 7 --worktree relative/dir
expect_rc "a relative worktree is refused" 2
echo MERGED >"$tmp/state7"
PATH="$tmp/bin:$PATH" mc_run mc-keeper.sh sweep --program alpha
expect_rc "a sweep with a failed read reports it" 1
expect_out "REQ-D1.5: the landed pull request is seen" "landed${tab}mc-alpha-worker-one${tab}MERGED"
expect_out "REQ-D1.5: its session is retired" "retired${tab}mc-alpha-worker-one"
expect_out "and its line dropped" "dropped${tab}mc-alpha-worker-one"
expect_out "the open one is left" "open${tab}mc-alpha-worker-two"
expect_out "the failed read is named" "unknown${tab}mc-alpha-worker-bad"
if ! grep -q "worker-one" "$ledger" && grep -q "worker-two" "$ledger" && grep -q "worker-bad" "$ledger"; then
  ok "REQ-M1.3: the landed unit frees its slot within one sweep"
else
  fail "REQ-M1.3: the ledger after the sweep: $(cat "$ledger")"
fi

mc_run mc-keeper.sh track --program alpha --session mc-alpha-worker-three --repo acme/web --pr 7
echo CLOSED >"$tmp/state7"
OUT=$(cd "$repo" && mc_env env PATH="$tmp/bin:$PATH" PLANWRIGHT_MC_PROGRAM=alpha /bin/bash "$repo_root/scripts/mc-keeper.sh" 2>"$tmp/stderr")
RC=$?
ERR=$(cat "$tmp/stderr")
expect_rc "under the runner, the failed read still fails the run" 1
expect_eq "under the runner, a landing is announced and nothing else printed" "announced${tab}session-landed${tab}mc-alpha-worker-three"
mc_run mc-event.sh list --program alpha
expect_out "the landing lands in the event store" "session-landed${tab}mc-alpha-worker-three${tab}acme/web#7 CLOSED, retired"

# A landing that stays held wakes the session once, not every run.
mkdir -p "$tmp/dirty"
mc_run mc-keeper.sh track --program alpha --session mc-alpha-worker-four --repo acme/web --pr 7 --worktree "$tmp/dirty"
held_run_1=$(cd "$repo" && mc_env env PATH="$tmp/bin:$PATH" PLANWRIGHT_MC_PROGRAM=alpha /bin/bash "$repo_root/scripts/mc-keeper.sh" 2>"$tmp/held.err")
held_run_2=$(cd "$repo" && mc_env env PATH="$tmp/bin:$PATH" PLANWRIGHT_MC_PROGRAM=alpha /bin/bash "$repo_root/scripts/mc-keeper.sh" 2>/dev/null)
case $held_run_1 in *"announced${tab}session-landed${tab}mc-alpha-worker-four"*) ok "a held landing is announced" ;; *) fail "a held landing was not announced: $held_run_1 $(cat "$tmp/held.err")" ;; esac
case $held_run_2 in *worker-four*) fail "a held landing was announced again: $held_run_2" ;; *) ok "and not again while it stays held" ;; esac
if grep -q "^mc-alpha-worker-four${tab}.*${tab}retired$" "$ledger"; then
  ok "a held session stays tracked, marked retired so a relaunch under its name is never retired for it"
else
  fail "the held session's ledger row: $(cat "$ledger")"
fi
if [ "$(head -n 1 "$ledger")" = "# format: 1" ]; then ok "the ledger carries its format"; else fail "the ledger lacks its format line"; fi
mc_run mc-keeper.sh track --program alpha --session mc-alpha-worker-four --repo acme/web --pr 8
if grep -q "^mc-alpha-worker-four${tab}acme/web${tab}7${tab}.*${tab}retired$" "$ledger" && grep -q "^mc-alpha-worker-four${tab}acme/web${tab}8${tab}" "$ledger"; then
  ok "a relaunch tracked under the name keeps the retired line waiting on its worktree"
else
  fail "tracking a relaunch lost the retired line: $(cat "$ledger")"
fi

# The relaunch's own landing is its own event, not taken for the retired
# line's: the retired line waits on its worktree, the new one lands.
echo MERGED >"$tmp/state8"
OUT=$(cd "$repo" && mc_env env PATH="$tmp/bin:$PATH" PLANWRIGHT_MC_PROGRAM=alpha /bin/bash "$repo_root/scripts/mc-keeper.sh" 2>/dev/null)
mc_run mc-event.sh list --program alpha
expect_out "the relaunch's landing is raised" "session-landed${tab}mc-alpha-worker-four${tab}acme/web#8 MERGED, retired"
if grep -q "^mc-alpha-worker-four${tab}acme/web${tab}8${tab}" "$ledger"; then fail "the relaunch's landed line stayed"; else ok "and its line dropped"; fi
if grep -q "^mc-alpha-worker-four${tab}acme/web${tab}7${tab}.*${tab}retired$" "$ledger"; then ok "while the retired line still waits on its worktree"; else fail "the retired line went: $(cat "$ledger")"; fi
echo OPEN >"$tmp/state8"

mc_run mc-keeper.sh track --program alpha --session mc-alpha-worker-six --repo acme/.github --pr 8
expect_rc "a repository named with a leading dot is a slug" 0
for bad in acme/.. acme/-x ./x acme; do
  mc_run mc-keeper.sh track --program alpha --session mc-alpha-worker-six --repo "$bad" --pr 8
  expect_rc "not a slug: $bad" 2
done

# A worktree already gone, its parent with it, has nothing to reclaim.
mc_run mc-keeper.sh track --program alpha --session mc-alpha-worker-eight --repo acme/web --pr 7 --worktree "$tmp/gone/deep/wt"
PATH="$tmp/bin:$PATH" mc_run mc-keeper.sh sweep --program alpha
expect_out "a gone worktree under a gone parent is dropped" "dropped${tab}mc-alpha-worker-eight"

# A worktree under a dangling link may come back, so it is held, not dropped.
ln -s "$tmp/unmounted" "$tmp/linked"
mc_run mc-keeper.sh track --program alpha --session mc-alpha-worker-nine --repo acme/web --pr 7 --worktree "$tmp/linked/wt"
PATH="$tmp/bin:$PATH" mc_run mc-keeper.sh sweep --program alpha
expect_out "a worktree under a dangling link is held" "held${tab}mc-alpha-worker-nine${tab}worktree"

# A worktree whose directory cannot be entered still exists: it goes to the
# reclaim, whose refusal holds the line, never treated as gone.
mkdir -p "$tmp/locked/wt"
mc_run mc-keeper.sh track --program alpha --session mc-alpha-worker-seven --repo acme/web --pr 7 --worktree "$tmp/locked/wt"
chmod 000 "$tmp/locked"
PATH="$tmp/bin:$PATH" mc_run mc-keeper.sh sweep --program alpha
chmod 700 "$tmp/locked"
expect_out "an unreadable worktree is held, not dropped" "held${tab}mc-alpha-worker-seven${tab}worktree"
if grep -q "^mc-alpha-worker-seven${tab}" "$ledger"; then ok "and its line stays"; else fail "the unreadable worktree's line was dropped"; fi

# A refused landing event keeps the line, so the next run raises it.
mc_run mc-keeper.sh track --program alpha --session mc-alpha-worker-five --repo acme/web --pr 7
events_dir="$fleet/attention/mission-control/alpha/events"
chmod 500 "$events_dir"
OUT=$(cd "$repo" && mc_env env PATH="$tmp/bin:$PATH" PLANWRIGHT_MC_PROGRAM=alpha /bin/bash "$repo_root/scripts/mc-keeper.sh" 2>/dev/null)
RC=$?
chmod 700 "$events_dir"
expect_rc "a refused landing event fails the run" 1
if grep -q "^mc-alpha-worker-five${tab}" "$ledger"; then ok "and keeps the line"; else fail "the line went with the event refused"; fi
OUT=$(cd "$repo" && mc_env env PATH="$tmp/bin:$PATH" PLANWRIGHT_MC_PROGRAM=alpha /bin/bash "$repo_root/scripts/mc-keeper.sh" 2>/dev/null)
expect_out "the next run raises it" "announced${tab}session-landed${tab}mc-alpha-worker-five"
if grep -q "^mc-alpha-worker-five${tab}" "$ledger"; then fail "the landed line stayed once its event was stored"; else ok "and then drops the line"; fi

# ---------------------------------------------------------------------------
# REQ-M1.4: the next ready unit dispatches while another waits on CI.
# ---------------------------------------------------------------------------
gr() { git -C "$repo" -c user.name=t -c user.email=t@example.invalid "$@" >/dev/null 2>&1; }
mkdir -p "$repo/specs/demo"
cat >"$repo/specs/demo/tasks.md" <<'EOF'
# Demo — Tasks

**Status:** Ready
**Format-version:** 2

## Tasks

### Task 1 — First

- **Deliverables:** a
- **Dependencies:** none

### Task 2 — Second

- **Deliverables:** b
- **Dependencies:** none

### Task 3 — Third

- **Deliverables:** c
- **Dependencies:** 1
EOF
gr checkout -q -b main
gr add -A
gr commit -m spec
gr checkout -q -b planwright/demo/task-1
gr commit --allow-empty -m "task 1 work, CI pending"
gr checkout -q main
mc_run mc-keeper.sh next --program alpha --spec "$repo/specs/demo"
expect_rc "next" 0
expect_out "REQ-M1.4: the unit waiting on CI is named waiting" "waiting${tab}demo:task-1${tab}in-progress"
expect_out "REQ-M1.4: the next ready unit dispatches" "dispatch${tab}demo:task-2"
expect_no_out "a unit whose dependency is in flight does not" "demo:task-3"
expect_no_out "REQ-M1.3: a unit with a branch in flight is not dispatched again" "dispatch${tab}demo:task-1"

# The budget's admission holds dispatch when no session would be admitted.
sed -i.bak 's/^program_alpha_budget: .*/program_alpha_budget: {host_load: 1000000, sessions: 1}/' "$tracked"
mc_run mc-budget.sh record --program alpha sessions 1
mc_run mc-keeper.sh next --program alpha --spec "$repo/specs/demo"
expect_rc "next under a full budget" 0
expect_out "REQ-M1.4: a ready unit is held while the budget admits no session" "held${tab}demo:task-2${tab}the budget holds dispatch: hold-dispatch (sessions at 100%)"
expect_no_out "and is not dispatched" "dispatch${tab}"

# A stream-json worker the launcher never registered (an older planwright's,
# or /orchestrate's) waiting past the bound on a permission prompt reaches the
# operator: a high queue item and one event, announced once. One the launcher
# records for another program is that program's to announce.
pp_req() { # pp_req <worker>: an overdue pending request under live pids
  mkdir -p "$fleet/streamjson/$1"
  printf 'aaaa1111-bbbb-cccc-dddd-eeee00000001\tpermission\t1000\tpending\n' >"$fleet/streamjson/$1/journal"
  printf '%s\n' "$$" >"$fleet/streamjson/$1/supervisor.pid"
  printf '%s\n' "$$" >"$fleet/streamjson/$1/worker.pid"
  printf 'demo:task-9\n' >"$fleet/streamjson/$1/scope"
}
pp_req cp-old
pp_req mc-beta-worker-0123456789
mkdir -p "$fleet/mission-control/sessions"
printf 'format\t1\nname\tmc-beta-worker-0123456789\nprogram\tbeta\nkind\tworker\nscope\tx\nbackend\tstream-json\nlaunched\t1\n' \
  >"$fleet/mission-control/sessions/mc-beta-worker-0123456789"
OUT=$(cd "$repo" && mc_env env PATH="$tmp/bin:$PATH" PLANWRIGHT_MC_PROGRAM=alpha /bin/bash "$repo_root/scripts/mc-keeper.sh" watch --now 5000 2>"$tmp/pp.err")
expect_out "an unregistered worker's overdue prompt is announced" "announced${tab}pending-prompt-overdue${tab}cp-old"
expect_no_out "another program's worker is left to it" "mc-beta-worker-0123456789"
mc_run mc-event.sh list --program alpha
expect_out "the overdue prompt lands in the event store" "pending-prompt-overdue${tab}cp-old${tab}stream-json worker cp-old has waited 4000s"
mc_run fleet-attention.sh queue
expect_out "and in the decision queue, high" "- [high] demo:task-9  (cp-old"
OUT=$(cd "$repo" && mc_env env PATH="$tmp/bin:$PATH" PLANWRIGHT_MC_PROGRAM=alpha /bin/bash "$repo_root/scripts/mc-keeper.sh" watch --now 5120 2>/dev/null)
expect_no_out "and not announced again while it stays overdue" "pending-prompt-overdue"
# A dead one's request leaves the queue, so its death is what is announced.
pp_req cp-gone
printf '999999999\n' >"$fleet/streamjson/cp-gone/supervisor.pid"
printf '999999999\n' >"$fleet/streamjson/cp-gone/worker.pid"
OUT=$(cd "$repo" && mc_env env PATH="$tmp/bin:$PATH" PLANWRIGHT_MC_PROGRAM=alpha /bin/bash "$repo_root/scripts/mc-keeper.sh" watch --now 5180 2>/dev/null)
expect_out "a dead worker's settle is announced" "announced${tab}stream-json-worker-dead${tab}cp-gone"
expect_no_out "and its prompt is not" "pending-prompt-overdue${tab}cp-gone"
rm -rf "$fleet/streamjson/cp-old" "$fleet/streamjson/cp-gone" "$fleet/streamjson/mc-beta-worker-0123456789" "$fleet/mission-control/sessions/mc-beta-worker-0123456789"

# A landed session the launcher never registered, whose stream-json worker
# has a recover in flight, is held rather than retired: retire refuses it as
# in flight, and the sweep keeps the line for the next pass.
mkdir -p "$fleet/streamjson/mc-alpha-worker-inflight"
ln -s "$$-$(date +%s)-1" "$fleet/streamjson/mc-alpha-worker-inflight/recover.lock"
mc_run mc-keeper.sh track --program alpha --session mc-alpha-worker-inflight --repo acme/web --pr 7
echo MERGED >"$tmp/state7"
PATH="$tmp/bin:$PATH" mc_run mc-keeper.sh sweep --program alpha
expect_out "a session with an operation in flight is held" "held${tab}mc-alpha-worker-inflight${tab}session ("
expect_no_out "and not retired" "retired${tab}mc-alpha-worker-inflight"
if grep -q "^mc-alpha-worker-inflight${tab}acme/web${tab}7${tab}" "$ledger" && ! grep -q "^mc-alpha-worker-inflight${tab}.*${tab}retired$" "$ledger"; then
  ok "its line stays tracked, not marked retired"
else
  fail "the in-flight session's ledger row: $(cat "$ledger")"
fi
[ -L "$fleet/streamjson/mc-alpha-worker-inflight/recover.lock" ] || fail "the in-flight election must be left alone"
rm -rf "$fleet/streamjson/mc-alpha-worker-inflight"

# ---------------------------------------------------------------------------
# Short-lived workers: a session idle past mission_control_worker_idle is
# retired, one past mission_control_worker_lifetime hands over; a tower, a
# busy young session and one parked on its own question are left alone.
# ---------------------------------------------------------------------------
sleep 600 >/dev/null 2>&1 &
bound_pid=$!
mkdir -p "$tmp/tmux"
cat >"$tmp/bin/tmux" <<'STUB'
#!/bin/sh
verb=$1
shift
w='' fmt=''
while [ "$#" -gt 0 ]; do
  case $1 in
    -t) w=$2; shift 2 ;;
    -F | -p | -a) shift ;;
    *) fmt=$1; shift ;;
  esac
done
n=${w#@}
case $verb in
  ls) exit 0 ;;
  list-windows)
    for f in "$TMUX_STUB"/*.name; do
      [ -f "$f" ] || continue
      id=${f##*/}
      printf '@%s\t%s\n' "${id%.name}" "$(cat "$f")"
    done
    ;;
  display-message)
    [ -f "$TMUX_STUB/$n.name" ] || { echo "can't find window: $w" >&2; exit 1; }
    case $fmt in
      *window_name*) printf '%s\t%s\n' "$(cat "$TMUX_STUB/$n.name")" "$(cat "$TMUX_STUB/$n.pid")" ;;
      *) cat "$TMUX_STUB/$n.pid" ;;
    esac
    ;;
  capture-pane)
    [ -f "$TMUX_STUB/$n.name" ] || exit 1
    cat "$TMUX_STUB/$n.pane"
    ;;
  kill-window) rm -f "$TMUX_STUB/$n.name" ;;
  *) exit 1 ;;
esac
STUB
chmod +x "$tmp/bin/tmux"
cat >"$tmp/idle.pane" <<'EOF'
⏺ The pull request is open.

────────────────────────────────────────
❯
────────────────────────────────────────
  ⏵⏵ auto mode on (shift+tab to cycle)
EOF
cat >"$tmp/question.pane" <<'EOF'
⏺ Two readings of the Done-when fit the code.
  Should I take the narrower one?

────────────────────────────────────────
❯
────────────────────────────────────────
  ⏵⏵ auto mode on (shift+tab to cycle)
EOF
cat >"$tmp/busy.pane" <<'EOF'
⏺ Running the gate.

✻ Herding… (12s · esc to interrupt)

────────────────────────────────────────
❯
────────────────────────────────────────
  ⏵⏵ auto mode on (shift+tab to cycle)
EOF
sessions="$fleet/mission-control/sessions"
mkdir -p "$sessions"
# bound_row <name> <kind> <window n> <launched> <pane>: a launched tmux
# session, its window live in the stub.
bound_row() {
  printf 'format\t1\nname\t%s\nstate\tlaunched\ntoken\tt\npid\t1\nprogram\talpha\nowner\tmission-control:alpha\nkind\t%s\nscope\ts-%s\nbackend\ttmux\nhandle\t@%s\nprofile\tworker\ntier\t-\nbrief\t-\ncwd\t-\ntask\t-\nprimary\t-\nmarker\t-\nlaunched\t%s\n' \
    "$1" "$2" "$3" "$3" "$4" >"$sessions/$1"
  printf '%s\n' "$1" >"$tmp/tmux/$3.name"
  printf '%s\n' "$bound_pid" >"$tmp/tmux/$3.pid"
  cp "$5" "$tmp/tmux/$3.pane"
}
t1=20000
t2=$((t1 + 1900))
bound_row mc-alpha-worker-idle worker 21 "$t1" "$tmp/idle.pane"
bound_row mc-alpha-reviewer-old reviewer 22 0 "$tmp/busy.pane"
bound_row mc-alpha-worker-young worker 23 "$t1" "$tmp/busy.pane"
bound_row mc-alpha-worker-asks worker 24 "$t1" "$tmp/question.pane"
bound_row mc-alpha-tower-old tower 25 0 "$tmp/idle.pane"
bound_env() { mc_env env PATH="$tmp/bin:$PATH" TMUX_STUB="$tmp/tmux" "$@"; }
(bound_env /bin/bash "$repo_root/scripts/mc-stall.sh" scan --program alpha --now "$t1" >/dev/null 2>&1)
OUT=$(bound_env /bin/bash "$repo_root/scripts/mc-keeper.sh" bounds --program alpha --now "$t2" 2>"$tmp/stderr")
RC=$?
expect_rc "bounds reads every session" 0
expect_out "idle past the idle bound retires" "retire${tab}mc-alpha-worker-idle${tab}idle 1900s, bound 1800s"
expect_out "lived past the lifetime hands over" "handover${tab}mc-alpha-reviewer-old${tab}lived ${t2}s, bound 14400s"
expect_no_out "a busy young session is left alone" "mc-alpha-worker-young"
expect_no_out "a session parked on its own question is never retired" "mc-alpha-worker-asks"
expect_no_out "a tower is not bound" "mc-alpha-tower-old"
OUT=$(bound_env /bin/bash "$repo_root/scripts/mc-keeper.sh" bounds --program alpha --now $((t1 + 60)) 2>/dev/null)
expect_no_out "an idle session inside the bound stays" "mc-alpha-worker-idle"

# The bounds are knobs.
cp "$tracked" "$tmp/tracked.keep"
printf 'mission_control_worker_idle: 1m\nmission_control_worker_lifetime: 30m\n' >>"$tracked"
OUT=$(bound_env /bin/bash "$repo_root/scripts/mc-keeper.sh" bounds --program alpha --now $((t1 + 1801)) 2>/dev/null)
expect_out "a shorter idle knob retires sooner" "retire${tab}mc-alpha-worker-idle${tab}idle 1801s, bound 60s"
expect_out "a shorter lifetime knob hands over sooner" "handover${tab}mc-alpha-worker-young${tab}lived 1801s, bound 1800s"
cp "$tmp/tracked.keep" "$tracked"

# watch acts: the idle session is retired through the launcher, its window
# closed and row gone; the old one's handover is announced once per launch.
OUT=$(cd "$repo" && bound_env PLANWRIGHT_MC_PROGRAM=alpha /bin/bash "$repo_root/scripts/mc-keeper.sh" watch --now "$t2" 2>"$tmp/stderr")
expect_out "the idle retire is announced" "announced${tab}worker-retired-idle${tab}mc-alpha-worker-idle"
if [ ! -e "$sessions/mc-alpha-worker-idle" ] && [ ! -e "$tmp/tmux/21.name" ]; then
  ok "the idle session is retired: its window closed and its row released"
else
  fail "the idle session was not retired: $(ls "$sessions") $(cat "$tmp/stderr")"
fi
expect_out "the lifetime handover is announced" "announced${tab}worker-handover-due${tab}mc-alpha-reviewer-old"
if [ -e "$sessions/mc-alpha-reviewer-old" ]; then ok "a handover leaves the session running"; else fail "the old session was retired"; fi
mc_run mc-event.sh list --program alpha
expect_out "the retire lands in the event store" "worker-retired-idle${tab}mc-alpha-worker-idle${tab}mc-alpha-worker-idle retired: idle 1900s, bound 1800s"
expect_out "the handover names the successor launch where no handover path is installed" "worker-handover-due${tab}mc-alpha-reviewer-old${tab}mc-alpha-reviewer-old is past its lifetime (lived ${t2}s, bound 14400s); launch its successor"
OUT=$(cd "$repo" && bound_env PLANWRIGHT_MC_PROGRAM=alpha /bin/bash "$repo_root/scripts/mc-keeper.sh" watch --now $((t2 + 60)) 2>/dev/null)
expect_no_out "the handover is raised once per launch" "worker-handover-due${tab}mc-alpha-reviewer-old"

# Where scripts/session-handover.sh is installed, the handover is requested
# through it, so the session hands over at its own next safe point.
cp -R "$repo_root/scripts" "$tmp/scripts-ho"
cat >"$tmp/scripts-ho/session-handover.sh" <<EOF
#!/bin/bash
printf '%s\n' "\$*" >>"$tmp/handover-requests"
printf 'requested\t%s\n' "\$3"
EOF
rm -f "$fleet/mission-control/alpha/keeper-bounds"
OUT=$(cd "$repo" && bound_env PLANWRIGHT_MC_PROGRAM=alpha /bin/bash "$tmp/scripts-ho/mc-keeper.sh" watch --now $((t2 + 120)) 2>/dev/null)
expect_out "an installed handover path is announced" "announced${tab}worker-handover-due${tab}mc-alpha-reviewer-old"
if grep -q "^request --session mc-alpha-reviewer-old --reason lived " "$tmp/handover-requests" 2>/dev/null; then
  ok "the lifetime bound requests the session's own handover"
else
  fail "no handover request: $(cat "$tmp/handover-requests" 2>&1)"
fi
kill "$bound_pid" 2>/dev/null
rm -rf "$tmp/scripts-ho"
for s in mc-alpha-reviewer-old mc-alpha-worker-young mc-alpha-worker-asks mc-alpha-tower-old; do rm -f "$sessions/$s"; done

if [ "$failures" -ne 0 ]; then
  echo "test-mc-keeper: $failures failure(s)" >&2
  exit 1
fi
echo "test-mc-keeper: all passed"
