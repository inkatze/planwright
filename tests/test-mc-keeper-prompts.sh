#!/bin/bash
# Tests for scripts/mc-keeper.sh's pending-prompt announcements: a stream-json
# worker's overdue request, one that has just arrived, a series from one
# worker, repeat asks, a batch split over events, and a reviewer's prompt.
#
# Companions: the other tests/test-mc-keeper*.sh suites; all but
# test-mc-keeper-rowless.sh share tests/lib/mc-keeper-fixture.sh.
#
# Runs standalone under /bin/bash (the bash 3.2 floor):
#   ./tests/test-mc-keeper-prompts.sh
set -u
unset CDPATH

here=$(cd "$(dirname "$0")" && pwd)
repo_root=$(cd "$here/.." && pwd)
# shellcheck source=tests/lib/mc-keeper-fixture.sh
. "$here/lib/mc-keeper-fixture.sh" || exit 1

# A stream-json worker the launcher holds no row for, its dispatch record
# naming this program, waiting past the bound on a permission prompt reaches the
# operator: a high queue item and one event, announced once. One the launcher
# records for another program is that program's to announce.
mc_row alpha live
mc_row beta live
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
  own_worker "$1" mission-control:alpha
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
  own_worker "$1" mission-control:alpha
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

if [ "$failures" -ne 0 ]; then
  echo "test-mc-keeper-prompts: $failures failure(s)" >&2
  exit 1
fi
echo "test-mc-keeper-prompts: all passed"
