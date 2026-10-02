#!/bin/bash
# Tests that a signal delivered mid-sweep leaves no temp artifact behind at
# any temp-beside-target site the sweep cycle writes through (REQ-F1.5).
#
# A watch loop stopped by signal is the normal way a sweep ends, so every temp
# a cycle creates beside a store it is about to replace has to be removed by a
# trap, not only on the paths that return normally. Each site is reached by
# running a real sweep cycle with one tool on PATH replaced by a shim that
# parks when it is handed that site's temp, so the signal lands exactly while
# the temp exists. The whole cycle's process group is then signalled, the way
# a terminal or a supervisor stops it, and the store's directory must hold no
# temp afterwards. Every site takes INT, TERM and HUP in turn.
#
# Runs standalone under /bin/bash (the bash 3.2 floor):
#   ./tests/test-fleet-sweep-temps.sh
set -eu
LC_ALL=C
export LC_ALL
unset CDPATH

export GIT_CONFIG_GLOBAL=/dev/null
export GIT_CONFIG_SYSTEM=/dev/null
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY

here=$(cd "$(dirname "$0")" && pwd)
SWEEP="$here/../scripts/fleet-sweep.sh"

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

[ -x "$SWEEP" ] || fail "scripts/fleet-sweep.sh missing or not executable"

tmp=$(cd "$(mktemp -d)" && pwd -P)
cleanup() {
  set +e
  cl_snap=$(ps -A -ww -o pid=,args= 2>/dev/null) || cl_snap=''
  while read -r p a; do
    case $a in
      *"$tmp"*) [ "$p" = "$$" ] || kill -9 "$p" 2>/dev/null ;;
    esac
  done <<EOF
$cl_snap
EOF
  rm -rf "$tmp"
}
trap cleanup EXIT

core_cfg="$tmp/core-defaults.yml"
printf 'fleet_daemon_pause: false\nfleet_dirty_tree_threshold: 0m\n' >"$core_cfg"
repo_cfg="$tmp/cfg-repo"
mkdir -p "$repo_cfg/.claude"

# The parking shims: a tool handed an argument containing $PARK_ON marks
# $PARK_REACHED and waits to be signalled; any other call is the real tool.
shims="$tmp/shims"
mkdir -p "$shims"
for t in mv cat; do
  real=$(command -v "$t")
  cat >"$shims/$t" <<SHIM
#!/bin/sh
for a; do
  case \$a in
    *"\$PARK_ON"*)
      : >"\$PARK_REACHED"
      while :; do sleep 1; done
      ;;
  esac
done
exec "$real" "\$@"
SHIM
  chmod +x "$shims/$t"
done

git_env() {
  GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t \
    GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t "$@"
}

# fresh <n> — a clean pushed tower checkout and an empty fleet home for one run.
fresh() {
  repo="$tmp/run$1/repo"
  home="$tmp/run$1/home"
  mkdir -p "$home"
  git_env git init -q -b main "$repo"
  (cd "$repo" && echo seed >f && git_env git add f && git_env git commit -qm seed)
  git_env git init -q --bare "$repo.git"
  (cd "$repo" && git_env git remote add origin "$repo.git" && git_env git push -q -u origin main)
}

# sweep_env — the hermetic environment prefix for a sweep of this run, in SW.
sweep_env() {
  SW=(env -u PLANWRIGHT_TOWER_ID -u PLANWRIGHT_TOWER_SESSION_ID -u PLANWRIGHT_TOWER_PID
    -u CLAUDE_PLUGIN_DATA -u PLANWRIGHT_FLEET_LOCK_HELD -u TMUX -u TMUX_PANE
    PLANWRIGHT_FLEET_STATE_DIR="$home"
    PLANWRIGHT_CONFIG_DEFAULTS="$core_cfg"
    PLANWRIGHT_REPO_ROOT=none
    PLANWRIGHT_ADOPTER_OVERLAY="$tmp/adopter"
    PLANWRIGHT_LOCAL_CONFIG="")
}

# One plain sweep, used to put a fixture into the state a site needs.
plain_sweep() {
  sweep_env
  "${SW[@]}" /bin/sh "$SWEEP" --repo "$repo" >/dev/null 2>&1 || :
}

wait_for() {
  wf_end=$((SECONDS + $1))
  while [ "$SECONDS" -lt "$wf_end" ]; do
    [ -e "$2" ] && return 0
    sleep 0.05
  done
  [ -e "$2" ]
}

# parked_sweep <signal> <park-on> <dir> <prefix> <what> — run a sweep cycle
# that parks at the site, signal its process group, and assert <dir> holds no
# entry starting with <prefix>.
parked_sweep() {
  ps_sig=$1
  reached="$tmp/reached.$$.$RANDOM"
  sweep_env
  # exec'd, so the job's pid is the sweep itself: waiting on a wrapper shell
  # that died of the signal would return before the sweep's traps had run.
  set -m
  (exec "${SW[@]}" PATH="$shims:$PATH" PARK_ON="$2" PARK_REACHED="$reached" \
    /bin/sh "$SWEEP" --repo "$repo" >/dev/null 2>"$tmp/err") &
  ps_pid=$!
  set +m
  wait_for 60 "$reached" || fail "$5 ($ps_sig): the sweep never reached the site: $(cat "$tmp/err")"
  kill -"$ps_sig" -- "-$ps_pid"
  ps_rc=0
  wait "$ps_pid" || ps_rc=$?
  [ "$ps_rc" != 0 ] || fail "$5 ($ps_sig): a sweep stopped by a signal exited 0"
  # A site several processes below the sweep runs its trap after the sweep
  # itself has exited, so the check waits, boundedly, for the group to finish.
  ps_end=$((SECONDS + 10))
  while :; do
    left=$(cd "$3" && find . -maxdepth 1 -name "$4*" -print)
    [ -n "$left" ] && [ "$SECONDS" -lt "$ps_end" ] || break
    sleep 0.1
  done
  [ -z "$left" ] || fail "$5 ($ps_sig): the signal left temp artifacts behind: $left"
}

n=0
for sig in INT TERM HUP; do
  # The sweep's own dirty-since clock.
  n=$((n + 1))
  fresh "$n"
  echo dirt >"$repo/untracked"
  parked_sweep "$sig" /.since. "$home/worktrees/dirty-since" .since. "the dirty-since clock"

  # The worktree scan: its git-list and merge temps, then its registry rewrite.
  n=$((n + 1))
  fresh "$n"
  parked_sweep "$sig" /.reg-git. "$home/worktrees" .reg- "the worktree scan's list temp"
  n=$((n + 1))
  fresh "$n"
  parked_sweep "$sig" /.registry. "$home/worktrees" .re "the worktree registry rewrite"

  # The audit trail, written for the escalation of a dirty tree.
  n=$((n + 1))
  fresh "$n"
  echo dirt >"$repo/untracked"
  parked_sweep "$sig" /.audit. "$home/audit" .audit. "the audit trail write"

  # The decision queue: the escalation's write, then the retraction's.
  n=$((n + 1))
  fresh "$n"
  echo dirt >"$repo/untracked"
  parked_sweep "$sig" /attention/.state. "$home/attention" .state. "the escalation's queue write"
  n=$((n + 1))
  fresh "$n"
  echo dirt >"$repo/untracked"
  plain_sweep
  [ -s "$home/attention/state" ] || fail "fixture: the dirty tree was not escalated"
  rm -f "$repo/untracked"
  parked_sweep "$sig" /attention/.state. "$home/attention" .state. "the retraction's queue write"

  # The dispatch registry, written by the reconcile healing a missing record.
  n=$((n + 1))
  fresh "$n"
  mkdir -p "$home/dispatch-markers"
  printf 'w-temps\tspec:1\t-\theadless-oneshot\t-\t-\n' >"$home/dispatch-markers/w-temps"
  parked_sweep "$sig" "$home/.registry." "$home" .registry. "the dispatch registry heal"
  # The store's lock goes with its temp: a held one wedges every fleet writer.
  lk_end=$((SECONDS + 10))
  while { [ -e "$home/.fleet.lock" ] || [ -L "$home/.fleet.lock" ]; } && [ "$SECONDS" -lt "$lk_end" ]; do
    sleep 0.1
  done
  [ ! -e "$home/.fleet.lock" ] && [ ! -L "$home/.fleet.lock" ] \
    || fail "the dispatch registry heal ($sig): the signal left the fleet lock held"
  echo "ok: $sig mid-sweep leaves no temp at any site (dirty-since clock, scan list, registry rewrite, audit write, queue write, queue retraction, dispatch registry heal)"
done
