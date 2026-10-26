# shellcheck shell=bash
# shellcheck disable=SC2034 # wdir, tab and run_pid are read and set by the sourcing test
# Shared fixture for the watcher runner tests, sourced after
# tests/lib/mission-control-fixture.sh and tests/lib/poll-until.sh: the
# reaper and exit traps, the fixture watchers and adapter, setup <duties>
# [budget] [sources], and the record and run-count helpers.

: "${tmp:?}" "${core:?}" "${repo:?}" "${tracked:?}" "${repo_root:?}" "${fleet:?source mission-control-fixture.sh first}"

wdir="$fleet/mission-control/alpha/watchers"

# Every watcher loop this suite starts is recorded by pid in a .rec file;
# those pids are stopped on the way out, and only while the process is still
# that slot's loop.
reap() {
  for rp_f in "$wdir"/*.rec; do
    [ -f "$rp_f" ] || continue
    rp_pid=$(cut -f1 "$rp_f")
    rp_slot=${rp_f##*/}
    rp_slot=${rp_slot%.rec}
    case $rp_pid in
      "" | *[!0-9]*) continue ;;
    esac
    case $(ps -ww -o args= -p "$rp_pid" 2>/dev/null) in
      "/bin/bash /"*"/mc-watch.sh loop --program alpha --slot $rp_slot") kill "$rp_pid" 2>/dev/null ;;
    esac
  done
}
run_pid=""
cleanup() {
  [ -z "$run_pid" ] || kill "$run_pid" 2>/dev/null
  reap
  rm -rf "$tmp"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
trap 'exit 129' HUP

tab=$(printf '\t')

# Fixture watchers: each run logs a line. alpha-watch also reports an event,
# a line the store refuses, and how many watcher-stopped events the store
# held when it ran.
mkdir -p "$core/scripts" "$tmp/runs" "$repo/scripts"
cat >"$core/scripts/alpha-watch.sh" <<'EOF'
#!/bin/sh
seen=$(grep -l watcher-stopped "$WATCH_EVENTS"/e* 2>/dev/null | wc -l | tr -d ' ')
printf '%s %s\n' "$PLANWRIGHT_MC_DUTY" "$seen" >>"$WATCH_RUNS/alpha-watch"
printf 'event\talpha-due\tpr-7\tseven is due\n'
printf 'event\tBad Kind\tpr-7\n'
printf 'chatter that is not an event\n'
EOF
cat >"$core/scripts/alpha-sweep.sh" <<'EOF'
#!/bin/sh
printf 'run\n' >>"$WATCH_RUNS/alpha-sweep"
EOF
cat >"$core/scripts/fast-watch.sh" <<'EOF'
#!/bin/sh
printf 'run\n' >>"$WATCH_RUNS/fast-watch"
printf 'event\tfast-due\tlast-line'
EOF
cat >"$core/scripts/heavy-watch.sh" <<'EOF'
#!/bin/sh
printf 'run\n' >>"$WATCH_RUNS/heavy-watch"
sleep 60 &
printf '%s\n' "$!" >"$WATCH_RUNS/heavy-child"
wait
EOF
cat >"$repo/scripts/tracker-adapter.sh" <<'EOF'
#!/bin/sh
out=""
while [ $# -gt 0 ]; do
  [ "$1" = --out ] && out=$2
  shift
done
printf 'item\tT-1\topen\n' >"$out"
exit "${TRACKER_EXIT:-0}"
EOF
WATCH_RUNS="$tmp/runs"
WATCH_EVENTS="$fleet/attention/mission-control/alpha/events"
export WATCH_RUNS WATCH_EVENTS

# setup <duties> [budget] [sources]: program alpha with a host-load limit no
# host reaches, and the fixture duties fast-duty (a 1s low-cost watcher and
# an hourly high-cost one) and lost-duty (a script that does not exist)
# beside the core seed's.
setup() {
  reap
  reset_mc_fixture
  rm -rf "$fleet" "$tmp/runs"/*
  cat >"$repo/.claude/catalogs/duties.yaml" <<'EOF'
duties:
  - id: fast-duty
    summary: "A fast fixture duty"
    triggers: []
    watchers: [scripts/fast-watch.sh@1s/low, scripts/heavy-watch.sh@1h/high]
    wake: none
    rules: []
    kinds: []
    files: fast
    lifecycle: live
    never-propose: false
  - id: lost-duty
    summary: "A duty whose watcher is missing"
    triggers: []
    watchers: [scripts/nowhere.sh@5m/low]
    wake: none
    rules: []
    kinds: []
    files: lost
    lifecycle: live
    never-propose: false
EOF
  cat >"$repo/.claude/catalogs/snapshot-adapters.yaml" <<'EOF'
adapters:
  - id: tracker
    summary: "A fixture tracker"
    script: scripts/tracker-adapter.sh
    cadence: 10m
EOF
  st_sources=${3:-'{work-items: specs:record}'}
  cat >"$tracked" <<EOF
mission_control_programs: [alpha]
program_alpha_repositories: [$repo]
program_alpha_spec_root: $repo
program_alpha_duties: $1
program_alpha_sources: $st_sources
program_alpha_budget: {host_load: 1000000${2:+, $2}}
EOF
}

rec_pid() { cut -f1 "$wdir/$1".rec 2>/dev/null; }
slot_for() { # slot_for <script-basename>: the slot recording that script
  for sf_f in "$wdir"/*.rec; do
    [ -f "$sf_f" ] || continue
    case $(cut -f4 "$sf_f") in
      *"$1")
        sf_s=${sf_f##*/}
        printf '%s\n' "${sf_s%.rec}"
        return 0
        ;;
    esac
  done
  return 1
}
runs_of() { [ -f "$WATCH_RUNS/$1" ] && wc -l <"$WATCH_RUNS/$1" | tr -d ' ' || echo 0; }
ran() { [ "$(runs_of "$1")" -ge "$2" ]; }
check() { # check <label> <command...>
  ck_label=$1
  shift
  if "$@"; then ok "$ck_label"; else fail "$ck_label"; fi
}
seed_polls_now() { # seed_polls_now <n>: poll-log lines stamped now
  mkdir -p "$fleet/mission-control/alpha"
  sp_now=$(date +%s)
  sp_i=0
  while [ "$sp_i" -lt "$1" ]; do
    printf '%s\tforge\n' "$sp_now"
    sp_i=$((sp_i + 1))
  done >>"$fleet/mission-control/alpha/polls"
}
