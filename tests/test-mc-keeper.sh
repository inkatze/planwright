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

# The fake forge below runs the caller's own --jq.
command -v jq >/dev/null 2>&1 || {
  echo "FAIL: jq is required (the gh stub runs the caller's --jq)" >&2
  exit 1
}

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

# A request that has just arrived is announced at once, as pending-prompt, so
# the operator need not wait for the overdue bound; the requests new to one
# pass are one event.
pp_fresh() { # pp_fresh <worker> <request-suffix> <received>
  mkdir -p "$fleet/streamjson/$1"
  printf 'bbbb2222-bbbb-cccc-dddd-eeee0000000%s\tpermission\t%s\tpending\n' "$2" "$3" >"$fleet/streamjson/$1/journal"
  printf '%s\n' "$$" >"$fleet/streamjson/$1/supervisor.pid"
  printf '%s\n' "$$" >"$fleet/streamjson/$1/worker.pid"
  printf 'demo:task-9\n' >"$fleet/streamjson/$1/scope"
}
pp_fresh cp-fresh-a 1 6990
pp_fresh cp-fresh-b 2 6995
OUT=$(cd "$repo" && mc_env env PATH="$tmp/bin:$PATH" PLANWRIGHT_MC_PROGRAM=alpha PLANWRIGHT_STREAMJSON_PENDING_AGE=900 /bin/bash "$repo_root/scripts/mc-keeper.sh" watch --now 7000 2>/dev/null)
expect_out "a request that just arrived is announced as pending-prompt" "announced${tab}pending-prompt${tab}cp-fresh-a"
expect_no_out "a burst's second arrival is folded into that one event" "announced${tab}pending-prompt${tab}cp-fresh-b"
mc_run mc-event.sh list --program alpha
expect_out "the batch lands in the event store, naming both workers" "pending-prompt${tab}cp-fresh-a${tab}2 requests waiting on a decision: cp-fresh-a bbbb2222-bbbb-cccc-dddd-eeee00000001; cp-fresh-b bbbb2222-bbbb-cccc-dddd-eeee00000002"
OUT=$(cd "$repo" && mc_env env PATH="$tmp/bin:$PATH" PLANWRIGHT_MC_PROGRAM=alpha PLANWRIGHT_STREAMJSON_PENDING_AGE=900 /bin/bash "$repo_root/scripts/mc-keeper.sh" watch --now 7020 2>/dev/null)
expect_no_out "and the burst is not announced again at the next pass" "announced${tab}pending-prompt${tab}cp-fresh-a"
rm -rf "$fleet/streamjson/cp-fresh-a" "$fleet/streamjson/cp-fresh-b"
pp_fresh cp-fresh-c 3 7010
OUT=$(cd "$repo" && mc_env env PATH="$tmp/bin:$PATH" PLANWRIGHT_MC_PROGRAM=alpha PLANWRIGHT_STREAMJSON_PENDING_AGE=900 /bin/bash "$repo_root/scripts/mc-keeper.sh" watch --now 7030 2>/dev/null)
expect_out "a request that arrives in a later pass is announced in that pass, not held for a window" "announced${tab}pending-prompt${tab}cp-fresh-c"
rm -rf "$fleet/streamjson/cp-fresh-c"

# Several prompts from one worker in a row: each arrives in its own pass after
# the last was answered, and each raises its own pending-prompt wake.
pp_series() { # pp_series <worker> <n> <received> [<previous answered at>]
  mkdir -p "$fleet/streamjson/$1"
  : >"$fleet/streamjson/$1/journal"
  if [ -n "${4:-}" ]; then
    printf 'bbbb2222-bbbb-cccc-dddd-eeee0000000%s\tpermission\t%s\tanswered\t%s\n' "$(($2 - 1))" "$(($3 - 200))" "$4" >>"$fleet/streamjson/$1/journal"
  fi
  printf 'bbbb2222-bbbb-cccc-dddd-eeee0000000%s\tpermission\t%s\tpending\n' "$2" "$3" >>"$fleet/streamjson/$1/journal"
  printf '%s\n' "$$" >"$fleet/streamjson/$1/supervisor.pid"
  printf '%s\n' "$$" >"$fleet/streamjson/$1/worker.pid"
  printf 'demo:task-9\n' >"$fleet/streamjson/$1/scope"
}
pp_series cp-series 1 7600
OUT=$(cd "$repo" && mc_env env PATH="$tmp/bin:$PATH" PLANWRIGHT_MC_PROGRAM=alpha PLANWRIGHT_STREAMJSON_PENDING_AGE=900 /bin/bash "$repo_root/scripts/mc-keeper.sh" watch --now 7610 2>/dev/null)
expect_out "a series' first prompt raises its wake" "announced${tab}pending-prompt${tab}cp-series"
pp_series cp-series 2 7800 7650
OUT=$(cd "$repo" && mc_env env PATH="$tmp/bin:$PATH" PLANWRIGHT_MC_PROGRAM=alpha PLANWRIGHT_STREAMJSON_PENDING_AGE=900 /bin/bash "$repo_root/scripts/mc-keeper.sh" watch --now 7810 2>/dev/null)
expect_out "the second prompt from the same worker raises its own wake" "announced${tab}pending-prompt${tab}cp-series"
pp_series cp-series 3 8000 7850
OUT=$(cd "$repo" && mc_env env PATH="$tmp/bin:$PATH" PLANWRIGHT_MC_PROGRAM=alpha PLANWRIGHT_STREAMJSON_PENDING_AGE=900 /bin/bash "$repo_root/scripts/mc-keeper.sh" watch --now 8010 2>/dev/null)
expect_out "and the third raises its own wake" "announced${tab}pending-prompt${tab}cp-series"
rm -rf "$fleet/streamjson/cp-series"

# A pending-prompt event names every waiting request, worker and request id.
# A repeat ask from a worker whose earlier event mission control already read
# raises a new event naming it; an answered request is never named again.
pp_ask() { # pp_ask <worker> <req-suffix> <received> pending|answered [<answered at>]
  mkdir -p "$fleet/streamjson/$1"
  printf 'cccc3333-bbbb-cccc-dddd-eeee0000000%s\tpermission\t%s\t%s\t%s\n' "$2" "$3" "$4" "${5:-}" >>"$fleet/streamjson/$1/journal"
  printf '%s\n' "$$" >"$fleet/streamjson/$1/supervisor.pid"
  printf '%s\n' "$$" >"$fleet/streamjson/$1/worker.pid"
  printf 'demo:task-9\n' >"$fleet/streamjson/$1/scope"
}
pp_watch() { # pp_watch <now>
  OUT=$(cd "$repo" && mc_env env PATH="$tmp/bin:$PATH" PLANWRIGHT_MC_PROGRAM=alpha PLANWRIGHT_STREAMJSON_PENDING_AGE=900 /bin/bash "$repo_root/scripts/mc-keeper.sh" watch --now "$1" 2>/dev/null)
}
pp_events() { # the pending-prompt events of one worker, one line each
  mc_run mc-event.sh list --program alpha
  printf '%s\n' "$OUT" | awk -F '\t' -v w="$1" '$3 == "pending-prompt" && $4 == w'
}
rm -f "$fleet/streamjson/cp-rep/journal"
pp_ask cp-rep 1 9000 pending
pp_watch 9010
expect_out "a worker's first ask raises an event" "announced${tab}pending-prompt${tab}cp-rep"
ev_a=$(pp_events cp-rep | awk -F '\t' 'NR == 1 { print $1 }')
case $(pp_events cp-rep) in
  *"cp-rep cccc3333-bbbb-cccc-dddd-eeee00000001"*) ok "the event names the worker and the request id" ;;
  *) fail "the first event does not name the request: $(pp_events cp-rep)" ;;
esac
mc_run mc-event.sh mark --program alpha --target mc-alpha submitted "$ev_a"
expect_rc "mission control reads the event" 0
rm -f "$fleet/streamjson/cp-rep/journal"
pp_ask cp-rep 1 9000 answered 9020
pp_ask cp-rep 2 9030 pending
pp_watch 9040
expect_out "a repeat ask after a consumed event raises a new event" "announced${tab}pending-prompt${tab}cp-rep"
ev_b=$(pp_events cp-rep | awk -F '\t' -v a="$ev_a" '$1 != a { print $1 }' | tail -n 1)
if [ -n "$ev_b" ]; then ok "and it is a new event, not the consumed one"; else fail "no new event past $ev_a"; fi
case $(pp_events cp-rep | awk -F '\t' -v b="$ev_b" '$1 == b') in
  *"cccc3333-bbbb-cccc-dddd-eeee00000002"*) ok "the new event names the second request id" ;;
  *) fail "the new event does not name request 2: $(pp_events cp-rep)" ;;
esac
case $(pp_events cp-rep | awk -F '\t' -v b="$ev_b" '$1 == b') in
  *"eeee00000001"*) fail "the new event names the answered request" ;;
  *) ok "an answered request is not named again" ;;
esac
rm -rf "$fleet/streamjson/cp-rep"

# An earlier ask still waiting is named again beside a new one, so no waiting
# request is left out of the event that wakes mission control.
pp_ask cp-two 1 9100 pending
pp_watch 9110
ev_c=$(pp_events cp-two | awk -F '\t' 'NR == 1 { print $1 }')
mc_run mc-event.sh mark --program alpha --target mc-alpha submitted "$ev_c"
pp_ask cp-two 2 9120 pending
pp_watch 9130
case $(pp_events cp-two | awk -F '\t' -v c="$ev_c" '$1 != c') in
  *"eeee00000001"*"eeee00000002"* | *"eeee00000002"*"eeee00000001"*) ok "a new event names every request still waiting" ;;
  *) fail "the new event leaves a waiting request out: $(pp_events cp-two)" ;;
esac
rm -rf "$fleet/streamjson/cp-two"

# Two unread asks from different workers share one event naming both ids.
pp_ask cp-ua 1 9200 pending
pp_ask cp-ub 2 9205 pending
pp_watch 9210
ev_n=$(pp_events cp-ua | awk 'END { print NR }')
case $(pp_events cp-ua) in
  *"cp-ua cccc3333-bbbb-cccc-dddd-eeee00000001"*"cp-ub cccc3333-bbbb-cccc-dddd-eeee00000002"*) ok "two unread asks share one event naming both workers and ids" ;;
  *) fail "the shared event does not name both requests: $(pp_events cp-ua)" ;;
esac
if [ "$ev_n" = 1 ]; then ok "and it is one event"; else fail "expected one event, saw $ev_n"; fi
rm -rf "$fleet/streamjson/cp-ua" "$fleet/streamjson/cp-ub"

# A batch too large for one event's text is split over events, and every
# waiting request is still named in one of them.
for ck in 1 2 3 4 5 6 7 8; do pp_ask "cp-chunk-long-worker-name-pad-0$ck" "$ck" 9300 pending; done
pp_watch 9310
mc_run mc-event.sh list --program alpha
ck_events=$(printf '%s\n' "$OUT" | awk -F '\t' '$3 == "pending-prompt" && index($4, "cp-chunk-") == 1')
ck_n=$(printf '%s\n' "$ck_events" | awk 'NF { n++ } END { print n + 0 }')
if [ "$ck_n" -ge 2 ]; then ok "a batch too large for one event is split"; else fail "expected the batch split, saw $ck_n event(s)"; fi
ck_miss=0
for ck in 1 2 3 4 5 6 7 8; do
  case $ck_events in *"cp-chunk-long-worker-name-pad-0$ck cccc3333-bbbb-cccc-dddd-eeee0000000$ck"*) ;; *) ck_miss=1 ;; esac
done
if [ "$ck_miss" = 0 ]; then ok "and every waiting request is named in one of the events"; else fail "a request is left out: $ck_events"; fi
ck_long=$(printf '%s\n' "$ck_events" | awk -F '\t' 'length($5) > 500 { n++ } END { print n + 0 }')
if [ "$ck_long" = 0 ]; then ok "and no event text is cut short"; else fail "an event text outgrew its cap"; fi
rm -rf "$fleet"/streamjson/cp-chunk-*

# A reviewer the program launched, in a repository of its own, is woken the
# same as a worker: the sweep does not key on kind or repository.
mkdir -p "$fleet/mission-control/sessions" "$fleet/streamjson/cp-review"
printf 'format\t1\nname\tmc-alpha-reviewer-0123456789\nprogram\talpha\nkind\treviewer\nscope\treview-9-r1\nbackend\tstream-json\nlaunched\t1\n' \
  >"$fleet/mission-control/sessions/mc-alpha-reviewer-0123456789"
printf '%s\n' "$tmp/elsewhere/.claude/worktrees/review" >"$fleet/streamjson/cp-review/cwd"
pp_fresh cp-review 1 9000
OUT=$(cd "$repo" && mc_env env PATH="$tmp/bin:$PATH" PLANWRIGHT_MC_PROGRAM=alpha PLANWRIGHT_STREAMJSON_PENDING_AGE=900 /bin/bash "$repo_root/scripts/mc-keeper.sh" watch --now 9010 2>/dev/null)
expect_out "a registered reviewer's prompt in another repository is announced" "announced${tab}pending-prompt${tab}cp-review"
rm -rf "$fleet/streamjson/cp-review" "$fleet/mission-control/sessions/mc-alpha-reviewer-0123456789"

# A pending-age setting the sweeps cannot read (15m, 0) used to end both
# sweeps non-zero with nothing said, so no prompt was ever announced. It is now
# named on stderr, raised once, and the shipped default stands in for it; any
# sweep that still ends non-zero is raised too.
for bad_age in 15m 0; do
  pp_req cp-badage
  OUT=$(cd "$repo" && mc_env env PATH="$tmp/bin:$PATH" PLANWRIGHT_MC_PROGRAM=alpha PLANWRIGHT_STREAMJSON_PENDING_AGE="$bad_age" /bin/bash "$repo_root/scripts/mc-keeper.sh" watch --now 5000 2>"$tmp/age.err")
  expect_out "a pending age of $bad_age is raised as a failed setting" "announced${tab}keeper-sweep-failed${tab}pending-age-setting"
  expect_out "and the default age still announces the overdue prompt ($bad_age)" "announced${tab}pending-prompt-overdue${tab}cp-badage"
  case $(cat "$tmp/age.err") in
    *"PLANWRIGHT_STREAMJSON_PENDING_AGE is '$bad_age'"*) ok "and says so on stderr ($bad_age)" ;;
    *) fail "a pending age of $bad_age is not named on stderr" ;;
  esac
  OUT=$(cd "$repo" && mc_env env PATH="$tmp/bin:$PATH" PLANWRIGHT_MC_PROGRAM=alpha PLANWRIGHT_STREAMJSON_PENDING_AGE="$bad_age" /bin/bash "$repo_root/scripts/mc-keeper.sh" watch --now 5060 2>/dev/null)
  expect_no_out "the failed setting is raised once ($bad_age)" "keeper-sweep-failed"
  rm -rf "$fleet/streamjson/cp-badage"
  OUT=$(cd "$repo" && mc_env env PATH="$tmp/bin:$PATH" PLANWRIGHT_MC_PROGRAM=alpha /bin/bash "$repo_root/scripts/mc-keeper.sh" watch --now 5120 2>/dev/null)
done
mc_run mc-event.sh list --program alpha
expect_out "the failed setting lands in the event store" "keeper-sweep-failed${tab}pending-age-setting"
pp_req cp-failsweep
rm -f "$fleet/mission-control/alpha/keeper-prompts"
mkdir "$fleet/mission-control/alpha/keeper-prompts"
OUT=$(cd "$repo" && mc_env env PATH="$tmp/bin:$PATH" PLANWRIGHT_MC_PROGRAM=alpha /bin/bash "$repo_root/scripts/mc-keeper.sh" watch --now 5200 2>"$tmp/sweep.err")
expect_out "a sweep that ends non-zero is raised whatever the cause" "announced${tab}keeper-sweep-failed${tab}pending-prompts"
case $(cat "$tmp/sweep.err") in
  *"the pending-prompts sweep failed"*) ok "and said on stderr" ;;
  *) fail "a failed sweep is not said on stderr" ;;
esac
rmdir "$fleet/mission-control/alpha/keeper-prompts"
rm -rf "$fleet/streamjson/cp-failsweep"

# A prompt left pending for a day (far past the overdue bound) raises the
# overdue event exactly once across passes, and that event's kind wakes the
# supervisor (class blocker, never routine).
pp_req cp-day
OUT=$(cd "$repo" && mc_env env PATH="$tmp/bin:$PATH" PLANWRIGHT_MC_PROGRAM=alpha /bin/bash "$repo_root/scripts/mc-keeper.sh" watch --now 87400 2>/dev/null)
expect_out "a prompt pending a day raises the overdue event" "announced${tab}pending-prompt-overdue${tab}cp-day"
OUT=$(cd "$repo" && mc_env env PATH="$tmp/bin:$PATH" PLANWRIGHT_MC_PROGRAM=alpha /bin/bash "$repo_root/scripts/mc-keeper.sh" watch --now 87500 2>/dev/null)
expect_no_out "and only once while it stays pending" "pending-prompt-overdue${tab}cp-day"
mc_run mc-event.sh list --program alpha
overdue_n=$(printf '%s\n' "$OUT" | awk -F '\t' '$3 == "pending-prompt-overdue" && $4 == "cp-day" { n++ } END { print n + 0 }')
if [ "$overdue_n" = 1 ]; then
  ok "the store holds exactly one overdue event for it"
else
  fail "the store holds $overdue_n overdue events for it"
fi
if awk -F '\t' '$1 == "pending-prompt-overdue" && $2 == "blocker" { f = 1 } END { exit !f }' "$repo_root/config/mc-event-classes.tsv"; then
  ok "the overdue kind wakes the supervisor (class blocker)"
else
  fail "pending-prompt-overdue is not a waking class"
fi
rm -rf "$fleet/streamjson/cp-day"

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
# kickoff relay, a busy young session and one parked on its own question are
# left alone.
# ---------------------------------------------------------------------------
sleep 600 >/dev/null 2>&1 &
bound_pid=$!
trap 'kill "$bound_pid" 2>/dev/null; rm -rf "$tmp"' EXIT
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
    # A window with a .switch count shows .pane2 from that capture on.
    if [ -f "$TMUX_STUB/$n.switch" ]; then
      c=$(($(cat "$TMUX_STUB/$n.count" 2>/dev/null || echo 0) + 1))
      echo "$c" >"$TMUX_STUB/$n.count"
      [ "$c" -lt "$(cat "$TMUX_STUB/$n.switch")" ] || { cat "$TMUX_STUB/$n.pane2"; exit 0; }
    fi
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
# bound_row <name> <kind> <window n> <launched> <pane> [<scope>]: a launched
# tmux session, its window live in the stub.
bound_row() {
  printf 'format\t1\nname\t%s\nstate\tlaunched\ntoken\tt\npid\t1\nprogram\talpha\nowner\tmission-control:alpha\nkind\t%s\nscope\t%s\nbackend\ttmux\nhandle\t@%s\nprofile\tworker\ntier\t-\nbrief\t-\ncwd\t-\ntask\t-\nprimary\t-\nmarker\t-\nlaunched\t%s\n' \
    "$1" "$2" "${6:-s-$3}" "$3" "$4" >"$sessions/$1"
  printf '%s\n' "$1" >"$tmp/tmux/$3.name"
  printf '%s\n' "$bound_pid" >"$tmp/tmux/$3.pid"
  cp "$5" "$tmp/tmux/$3.pane"
}
# relaunch_row <name> <launched>: the same name, a later launch.
relaunch_row() {
  awk -v l="$2" -F '\t' 'BEGIN { OFS = "\t" } $1 == "launched" { $2 = l } { print }' "$sessions/$1" >"$sessions/$1.new" \
    && mv -f "$sessions/$1.new" "$sessions/$1"
}
# sj_row <name> <launched> <turn ended> <final text> [<is_error>]: a
# stream-json session whose last turn ended at <turn ended>, its final text
# <final text>.
sj_row() {
  printf 'format\t1\nname\t%s\nstate\tlaunched\nprogram\talpha\nkind\tworker\nscope\ts\nbackend\tstream-json\nlaunched\t%s\n' \
    "$1" "$2" >"$sessions/$1"
  mkdir -p "$fleet/streamjson/$1"
  printf 'result\tsuccess\t%s\t%s\n' "$3" "${5:-false}" >"$fleet/streamjson/$1/result"
  jq -nc --arg r "$4" '{type:"result",subtype:"success",result:$r}' >"$fleet/streamjson/$1/events.jsonl"
}
t1=20000
t2=$((t1 + 1900))
bound_row mc-alpha-worker-idle worker 21 "$t1" "$tmp/idle.pane"
bound_row mc-alpha-reviewer-old reviewer 22 0 "$tmp/busy.pane"
bound_row mc-alpha-worker-young worker 23 "$t1" "$tmp/busy.pane"
bound_row mc-alpha-worker-asks worker 24 "$t1" "$tmp/question.pane"
bound_row mc-alpha-tower-old tower 25 0 "$tmp/idle.pane"
bound_row mc-alpha-worker-old worker 26 0 "$tmp/busy.pane"
bound_row mc-alpha-worker-kickoff worker 27 0 "$tmp/idle.pane" kickoff-demo
bound_row mc-alpha-worker-again worker 28 "$t1" "$tmp/idle.pane"
sj_row mc-alpha-worker-sjidle "$t1" "$t1" "Done: the pull request is open."
sj_row mc-alpha-worker-sjasks "$t1" "$t1" "Two readings fit.
Should I take the narrower one?  "
sj_row mc-alpha-worker-sjended "$t1" "$t1" "Done." true
sj_row mc-alpha-worker-sjstale $((t1 + 5)) "$t1" "Done."
bound_row mc-alpha-ad-hoc-idle ad-hoc 30 "$t1" "$tmp/idle.pane"
bound_row mc-beta-worker-idle worker 31 "$t1" "$tmp/idle.pane"
# Input lands after the watch's own stall scan: the re-check samples again.
bound_row mc-alpha-worker-typed worker 32 "$t1" "$tmp/idle.pane"
cp "$tmp/busy.pane" "$tmp/tmux/32.pane2"
echo 1000 >"$tmp/tmux/32.switch"
sj_row mc-alpha-worker-sjbusy "$t1" "$t1" "Done."
printf '{"type":"assistant","message":"working on the steered turn"}\n' >>"$fleet/streamjson/mc-alpha-worker-sjbusy/events.jsonl"
sed -i.bak 's/^program\talpha$/program\tbeta/' "$sessions/mc-beta-worker-idle" && rm -f "$sessions/mc-beta-worker-idle.bak"
bound_env() { mc_env env PATH="$tmp/bin:$PATH" TMUX_STUB="$tmp/tmux" "$@"; }
(bound_env /bin/bash "$repo_root/scripts/mc-stall.sh" scan --program alpha --now "$t1" >/dev/null 2>&1)
# Captures per sample, so the switch lands on the re-check's, after the
# watch's own scan.
echo $(($(cat "$tmp/tmux/32.count") * 2 + 1)) >"$tmp/tmux/32.switch"
# The stall scan sampled mc-alpha-worker-again's first launch; its relaunch
# under the same name has no sample of its own yet.
relaunch_row mc-alpha-worker-again $((t1 + 10))
OUT=$(bound_env /bin/bash "$repo_root/scripts/mc-keeper.sh" bounds --program alpha --now "$t2" 2>"$tmp/stderr")
RC=$?
expect_rc "bounds reads every session" 0
expect_out "idle past the idle bound retires" "retire${tab}mc-alpha-worker-idle${tab}${t1}${tab}idle 1900s, bound 1800s"
expect_out "lived past the lifetime hands over" "handover${tab}mc-alpha-reviewer-old${tab}0${tab}lived ${t2}s, bound 14400s"
expect_out "a stream-json session whose last turn completed past the grace retires, naming its last result" "retire${tab}mc-alpha-worker-sjidle${tab}${t1}${tab}completed result=success 1900s ago, grace 300s"
expect_no_out "a busy young session is left alone" "mc-alpha-worker-young"
expect_no_out "a session parked on its own question is never retired" "mc-alpha-worker-asks"
expect_no_out "nor a stream-json one whose last turn asked" "mc-alpha-worker-sjasks"
expect_no_out "a tower is not bound" "mc-alpha-tower-old"
expect_no_out "a kickoff relay is not bound" "mc-alpha-worker-kickoff"
expect_no_out "a sample from an earlier launch under the name is ignored" "mc-alpha-worker-again"
expect_out "an ad-hoc session is bound too" "retire${tab}mc-alpha-ad-hoc-idle${tab}"
expect_no_out "another program's session is its own program's" "mc-beta-worker-idle"
expect_no_out "a stream-json turn that ended in error is not idle" "mc-alpha-worker-sjended"
expect_no_out "nor one whose result predates its launch" "mc-alpha-worker-sjstale"
expect_no_out "a session whose events follow its last result is mid-turn, not idle" "mc-alpha-worker-sjbusy"
OUT=$(bound_env /bin/bash "$repo_root/scripts/mc-keeper.sh" bounds --program alpha --now $((t1 + 60)) 2>"$tmp/stderr")
RC=$?
expect_rc "bounds inside the bound" 0
expect_no_out "an idle session inside the bound stays" "mc-alpha-worker-idle"
expect_no_out "a completed stream-json session inside the grace stays" "mc-alpha-worker-sjidle"

# A completed stream-json worker stops holding a slot after the grace, well
# inside the idle bound; a running one, an unreadable one and a tmux one
# are left alone.
sj_row mc-alpha-worker-sjgrace "$t1" "$t1" "Done: the pull request is open."
sj_row mc-alpha-worker-sjunread "$t1" "$t1" "Done."
chmod 000 "$fleet/streamjson/mc-alpha-worker-sjunread/result"
sj_row mc-alpha-worker-sjrunning "$t1" "$t1" "Done."
printf '{"type":"assistant","message":"next turn"}\n' >>"$fleet/streamjson/mc-alpha-worker-sjrunning/events.jsonl"
bound_row mc-alpha-worker-tmuxgrace worker 33 "$t1" "$tmp/busy.pane"
mkdir -p "$fleet/streamjson/mc-alpha-worker-tmuxgrace"
printf 'result\tsuccess\t%s\tfalse\n' "$t1" >"$fleet/streamjson/mc-alpha-worker-tmuxgrace/result"
OUT=$(bound_env /bin/bash "$repo_root/scripts/mc-keeper.sh" bounds --program alpha --now $((t1 + 400)) 2>"$tmp/stderr")
expect_out "a completed stream-json worker retires after the grace, far inside the idle bound" "retire${tab}mc-alpha-worker-sjgrace${tab}${t1}${tab}completed result=success 400s ago, grace 300s"
expect_no_out "a stream-json worker whose status cannot be read counts as live" "mc-alpha-worker-sjunread"
expect_no_out "a running stream-json worker is untouched" "mc-alpha-worker-sjrunning"
expect_no_out "a tmux worker is untouched by the completed rule" "mc-alpha-worker-tmuxgrace"
chmod 600 "$fleet/streamjson/mc-alpha-worker-sjunread/result"
for s in mc-alpha-worker-sjunread mc-alpha-worker-sjrunning mc-alpha-worker-tmuxgrace; do rm -f "$sessions/$s" && rm -rf "$fleet/streamjson/$s"; done

# The bounds are knobs.
cp "$tracked" "$tmp/tracked.keep"
printf 'mission_control_worker_idle: 1m\nmission_control_worker_lifetime: 30m\n' >>"$tracked"
OUT=$(bound_env /bin/bash "$repo_root/scripts/mc-keeper.sh" bounds --program alpha --now $((t1 + 1801)) 2>/dev/null)
expect_out "a shorter idle knob retires sooner" "retire${tab}mc-alpha-worker-idle${tab}${t1}${tab}idle 1801s, bound 60s"
expect_out "a shorter lifetime knob hands over sooner" "handover${tab}mc-alpha-worker-young${tab}${t1}${tab}lived 1801s, bound 1800s"
expect_no_out "a session past both bounds is retired, not asked to hand over" "handover${tab}mc-alpha-worker-idle"
cp "$tmp/tracked.keep" "$tracked"
for s in mc-alpha-worker-sjasks mc-alpha-worker-sjended mc-alpha-worker-sjstale mc-alpha-worker-sjbusy; do rm -f "$sessions/$s" && rm -rf "$fleet/streamjson/$s"; done

# watch acts: the idle session is retired through the launcher, its window
# closed and row gone; each old one's handover is announced once per launch.
OUT=$(cd "$repo" && bound_env PLANWRIGHT_MC_PROGRAM=alpha /bin/bash "$repo_root/scripts/mc-keeper.sh" watch --now "$t2" 2>"$tmp/stderr")
ERR=$(cat "$tmp/stderr")
expect_out "the idle retire is announced" "announced${tab}worker-retired-idle${tab}mc-alpha-worker-idle"
if [ ! -e "$sessions/mc-alpha-worker-idle" ] && [ ! -e "$tmp/tmux/21.name" ]; then
  ok "the idle session is retired: its window closed and its row released"
else
  fail "the idle session was not retired: $(ls "$sessions") $ERR"
fi
expect_out "an idle stream-json session is retired too" "announced${tab}worker-retired-idle${tab}mc-alpha-worker-sjidle"
if [ ! -e "$sessions/mc-alpha-worker-sjidle" ]; then ok "and its row released"; else fail "the stream-json session's row stayed: $ERR"; fi
expect_out "the lifetime handover is announced" "announced${tab}worker-handover-due${tab}mc-alpha-reviewer-old"
expect_out "each session's own" "announced${tab}worker-handover-due${tab}mc-alpha-worker-old"
expect_no_out "input since the scan stops the retire" "worker-retired-idle${tab}mc-alpha-worker-typed"
if [ -e "$sessions/mc-alpha-worker-typed" ]; then ok "and the session stays"; else fail "a session typed into was retired"; fi
if [ -e "$sessions/mc-alpha-reviewer-old" ] && [ -e "$sessions/mc-alpha-worker-kickoff" ]; then
  ok "a handover leaves the session running, and a kickoff relay stays"
else
  fail "a session that should stay was retired: $(ls "$sessions")"
fi
case $ERR in
  *"not fully retired"* | *"could not be requested"* | *"bounds lock"* | *"left for a pass"* | *"cannot be listed"*)
    fail "the happy path's bounds reported an error: $ERR"
    ;;
  *) ok "the happy path's bounds report no error" ;;
esac
mc_run mc-event.sh list --program alpha
expect_out "the retire lands in the event store" "worker-retired-idle${tab}mc-alpha-worker-idle${tab}mc-alpha-worker-idle retired: idle 1900s, bound 1800s"
expect_out "the completed worker's retire event names it and its last result" "worker-retired-idle${tab}mc-alpha-worker-sjgrace${tab}mc-alpha-worker-sjgrace retired: completed result=success 1900s ago, grace 300s"
if [ "$(printf '%s\n' "$OUT" | grep -c "worker-retired-idle${tab}mc-alpha-worker-sjgrace${tab}")" = 1 ]; then ok "and it is raised once, under the owning program"; else fail "the completed worker's event count: $OUT"; fi
expect_out "the handover names the successor launch where no handover path is installed" "worker-handover-due${tab}mc-alpha-reviewer-old${tab}mc-alpha-reviewer-old is past its lifetime (lived ${t2}s, bound 14400s); retire it and launch its successor"

# Where scripts/session-handover.sh is installed, the handover is requested
# through it, so the session hands over at its own next safe point. A
# relaunch under the name is a new launch, so it is raised again; a session
# already raised for its launch is not.
cp -R "$repo_root/scripts" "$tmp/scripts-alt"
cat >"$tmp/scripts-alt/session-handover.sh" <<EOF
#!/bin/bash
printf '%s\n' "\$*" >>"$tmp/handover-requests"
printf 'requested\t%s\n' "\$3"
EOF
relaunch_row mc-alpha-reviewer-old 1
printf 'mc-alpha-worker-gone\tidle 9999s, bound 1800s\n' >"$fleet/mission-control/alpha/keeper-retired-owed"
OUT=$(cd "$repo" && bound_env PLANWRIGHT_MC_PROGRAM=alpha /bin/bash "$tmp/scripts-alt/mc-keeper.sh" watch --now $((t2 + 60)) 2>/dev/null)
expect_out "a retire event the store refused earlier is raised" "announced${tab}worker-retired-idle${tab}mc-alpha-worker-gone"
if [ ! -s "$fleet/mission-control/alpha/keeper-retired-owed" ]; then ok "and no longer owed"; else fail "the owed event stayed owed"; fi
expect_out "a relaunch past its lifetime is raised again, through the installed path" "announced${tab}worker-handover-due${tab}mc-alpha-reviewer-old"
expect_no_out "the handover is raised once per launch" "worker-handover-due${tab}mc-alpha-worker-old"
if grep -q "^request --session mc-alpha-reviewer-old --reason lived " "$tmp/handover-requests" 2>/dev/null \
  && ! grep -q "mc-alpha-worker-old" "$tmp/handover-requests"; then
  ok "the lifetime bound requests the session's own handover, once per launch"
else
  fail "the handover requests: $(cat "$tmp/handover-requests" 2>&1)"
fi
mc_run mc-event.sh list --program alpha
expect_out "the installed path's event says the session hands over itself" "mc-alpha-reviewer-old is past its lifetime (lived $((t2 + 59))s, bound 14400s); it hands over at its next safe point"

# A failed handover request is not announced, and a pass whose stall scan
# failed retires no tmux session, its samples possibly stale; a stream-json
# one is still tried, here by a launcher whose retire fails.
printf '#!/bin/sh\nexit 1\n' >"$tmp/scripts-alt/session-handover.sh"
printf '#!/bin/sh\nexit 1\n' >"$tmp/scripts-alt/mc-stall.sh"
mv "$tmp/scripts-alt/mission-control-launch.sh" "$tmp/scripts-alt/mission-control-launch.real.sh"
cat >"$tmp/scripts-alt/mission-control-launch.sh" <<'EOF'
#!/bin/bash
if [ "$1" = retire ]; then
  case $2 in
    *-sjgone)
      rm -f "$PLANWRIGHT_FLEET_STATE_DIR/mission-control/sessions/$2"
      exit 3
      ;;
    *) printf 'retire\t%s\tpartial\n' "$2" ;;
  esac
  exit 6
fi
exec /bin/bash "$(dirname "$0")/mission-control-launch.real.sh" "$@"
EOF
sj_row mc-alpha-worker-sjidle2 "$t1" "$t1" "Done."
sj_row mc-alpha-worker-sjgone "$t1" "$t1" "Done."
relaunch_row mc-alpha-reviewer-old 2
bound_row mc-alpha-worker-idle2 worker 29 "$t1" "$tmp/idle.pane"
printf '%s:t\th\t%s\tidle\n' "$t1" "$t1" >"$fleet/mission-control/alpha/stall/mc-alpha-worker-idle2"
OUT=$(cd "$repo" && bound_env PLANWRIGHT_MC_PROGRAM=alpha /bin/bash "$tmp/scripts-alt/mc-keeper.sh" watch --now $((t2 + 120)) 2>"$tmp/stderr")
ERR=$(cat "$tmp/stderr")
expect_no_out "a failed handover request is not announced" "worker-handover-due${tab}mc-alpha-reviewer-old"
case $ERR in *"the handover of mc-alpha-reviewer-old could not be requested"*) ok "and is reported" ;; *) fail "the failed request was not reported: $ERR" ;; esac
expect_no_out "a pass whose stall scan failed retires nothing" "worker-retired-idle"
if [ -e "$sessions/mc-alpha-worker-idle2" ] && [ -e "$tmp/tmux/29.name" ]; then
  ok "the idle session waits for a pass whose scan succeeds"
else
  fail "the idle session was retired on a failed scan"
fi
case $ERR in *"mc-alpha-worker-idle2 is idle past its bound, left for a pass whose stall scan succeeds"*) ok "and says so" ;; *) fail "the skipped retire was not reported: $ERR" ;; esac
case $ERR in *"the idle session mc-alpha-worker-sjidle2 was not fully retired: retire"*) ok "a stream-json retire is still tried, and its failure reported" ;; *) fail "the stream-json retire on a failed scan: $ERR" ;; esac
case $ERR in *mc-alpha-worker-sjgone*) fail "a session retired meanwhile was reported: $ERR" ;; *) ok "a session retired meanwhile is not a failed retire" ;; esac
if [ ! -e "$sessions/mc-alpha-worker-sjgone" ]; then ok "(its retire was reached)"; else fail "the gone-meanwhile retire was never reached"; fi

kill "$bound_pid" 2>/dev/null
rm -rf "$tmp/scripts-alt"
for s in mc-alpha-reviewer-old mc-alpha-worker-young mc-alpha-worker-asks mc-alpha-tower-old mc-alpha-worker-old \
  mc-alpha-worker-kickoff mc-alpha-worker-again mc-alpha-worker-idle2 mc-beta-worker-idle mc-alpha-worker-sjidle2 \
  mc-alpha-worker-sjgone mc-alpha-worker-typed; do
  rm -f "$sessions/$s" && rm -rf "$fleet/streamjson/$s"
done

# A flight parked for the operator whose pull request has since merged or
# closed waits on nobody: the sweep clears its queue row. One still open, one
# with no pull request, one from a repository outside the program, one whose
# read fails, and a question that is not a park all stay.
mkdir -p "$tmp/bin2" "$tmp/other"
# The fake forge answers in JSON, filtered by the caller's --state and then
# its own --jq, so the state split and the fork filter are exercised, not
# just named.
cat >"$tmp/bin2/gh" <<EOF
#!/bin/sh
case "\$*" in
  *"pr list"*) printf '%s\n' "\$*" >>"$tmp/gh-flight.log" ;;
  *) exec "$tmp/bin/gh" "\$@" ;;
esac
q=''
st=all
lim=30
prev=''
for a in "\$@"; do
  [ "\$prev" != --jq ] || q=\$a
  [ "\$prev" != --state ] || st=\$a
  [ "\$prev" != --limit ] || lim=\$a
  prev=\$a
done
m='{"state":"MERGED","isCrossRepository":false}'
c='{"state":"CLOSED","isCrossRepository":false}'
o='{"state":"OPEN","isCrossRepository":false}'
fork_open='{"state":"OPEN","isCrossRepository":true}'
fork_merged='{"state":"MERGED","isCrossRepository":true}'
case "\$*" in
  *"--head planwright/flight/fl-closed "*) j="[\$c]" ;;
  *"--head planwright/flight/fl-open "*) j="[\$m,\$o]" ;;
  *"--head planwright/flight/fl-nopr "*) j='[]' ;;
  *"--head planwright/flight/fl-fork "*) j="[\$fork_open,\$c]" ;;
  *"--head planwright/flight/fl-forkonly "*) j="[\$fork_merged]" ;;
  *"--head planwright/flight/fl-both "*) j="[\$c,\$m,\$c]" ;;
  *"--head planwright/flight/fl-many "*) j="[\$(i=0; while [ \$i -lt 25 ]; do printf '%s,' "\$c"; i=\$((i + 1)); done)\$o]" ;;
  *"--head planwright/flight/fl-fails "*) exit 1 ;;
  *) j="[\$m]" ;;
esac
case \$st in
  open) f='[.[] | select(.state == "OPEN")]' ;;
  closed) f='[.[] | select(.state != "OPEN")]' ;;
  *) f='.' ;;
esac
# Newest first, cut at the caller's --limit, as the forge does.
printf '%s\n' "\$j" | jq -c "\$f | .[:\$lim]" | jq -r "\$q"
EOF
chmod +x "$tmp/bin2/gh"
: >"$tmp/gh-flight.log"
for fl in fl-merged:print fl-closed:tmux fl-owes:tmux fl-wt:print fl-fork:print fl-forkonly:print fl-both:print fl-many:print fl-open:print fl-nopr:print fl-elsewhere:print fl-asks:print fl-fails:print fl-after:print; do
  id=${fl%%:*}
  mkdir -p "$fleet/flights/$id"
  case $id in
    fl-elsewhere) printf '%s\n' "$tmp/other" >"$fleet/flights/$id/checkout" ;;
    fl-wt) printf '%s\n' "$repo/.claude/worktrees/flight-fl-wt" >"$fleet/flights/$id/checkout" ;;
    *) printf '%s\n' "$repo" >"$fleet/flights/$id/checkout" ;;
  esac
  [ "$id" != fl-closed ] || printf 'pr:https://github.com/acme/web/pull/3\n' >"$fleet/flights/$id/landing"
  if [ "$id" = fl-asks ]; then
    mc_run fleet-attention.sh decide "print-flight-$id" "flight:$id" 'Ship it?' yes 'yes|no'
  else
    mc_run fleet-attention.sh park "${fl#*:}-flight-$id" "flight:$id" 'flight-parked: point'
  fi
done
PATH="$tmp/bin2:$PATH" mc_run mc-keeper.sh sweep --program alpha
expect_out "a park on a merged pull request is settled" "settled${tab}print-flight-fl-merged${tab}MERGED"
expect_out "a park on a closed pull request is settled" "settled${tab}tmux-flight-fl-closed${tab}CLOSED"
expect_out "a park from a since-removed worktree of a program repository is settled" "settled${tab}print-flight-fl-wt${tab}MERGED"
expect_out "a fork's open pull request does not keep a park" "settled${tab}print-flight-fl-fork${tab}CLOSED"
expect_out "a merged pull request wins over a closed one" "settled${tab}print-flight-fl-both${tab}MERGED"
expect_out "a park whose read failed is named" "park-unknown${tab}print-flight-fl-fails"
expect_out "a failed read stops the pass, the rest named unread" "park-unknown${tab}print-flight-fl-after${tab}an earlier"
mc_run fleet-attention.sh queue
expect_no_out "the merged flight's park leaves the queue" "fl-merged"
expect_no_out "the closed flight's park leaves the queue" "fl-closed"
expect_out "a park with an open pull request stays" "flight:fl-open"
expect_out "an open pull request older than many closed ones still keeps a park" "flight:fl-many"
expect_out "a park with no pull request stays" "flight:fl-nopr"
expect_out "a fork's merged pull request does not settle a park" "flight:fl-forkonly"
expect_out "a park from a repository outside the program stays" "flight:fl-elsewhere"
expect_out "a question that is not a park stays" "flight:fl-asks"
expect_out "a park whose read failed stays" "flight:fl-fails"
expect_out "a park left unread after a failure stays" "flight:fl-after"
expect_out "a tmux flight whose completion was never pushed keeps its park" "flight:fl-owes"
if grep -q "fl-after" "$tmp/gh-flight.log"; then fail "the forge was asked again after a failed read"; else ok "the forge is not asked again after a failed read"; fi
if grep -q "fl-elsewhere" "$tmp/gh-flight.log"; then fail "the forge was asked about a flight outside the program"; else ok "the forge is not asked about a flight outside the program"; fi
if grep -q "fl-asks" "$tmp/gh-flight.log"; then fail "the forge was asked about a row that is not a park"; else ok "the forge is not asked about a row that is not a park"; fi
# The re-raised park lands after the failing one, which would stop the pass.
mc_run fleet-attention.sh clear print-flight-fl-fails
mc_run fleet-attention.sh park print-flight-fl-merged flight:fl-merged 'flight-parked: point'
OUT=$(cd "$repo" && mc_env env PATH="$tmp/bin2:$PATH" PLANWRIGHT_MC_PROGRAM=alpha /bin/bash "$repo_root/scripts/mc-keeper.sh" 2>/dev/null)
expect_no_out "under the runner a settle prints nothing" "settled"
mc_run fleet-attention.sh queue
expect_no_out "under the runner the park is settled too" "fl-merged"
for id in fl-open fl-many fl-nopr fl-forkonly fl-elsewhere fl-asks fl-fails fl-after; do
  mc_run fleet-attention.sh clear "print-flight-$id"
done
mc_run fleet-attention.sh clear tmux-flight-fl-owes
rm -rf "$fleet/flights"

if [ "$failures" -ne 0 ]; then
  echo "test-mc-keeper: $failures failure(s)" >&2
  exit 1
fi
echo "test-mc-keeper: all passed"
