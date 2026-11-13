#!/bin/bash
# Tests for scripts/mission-control-launch.sh: a repository-changing kind
# starts in its own worktree, and its brief carries the verification cadence
# (mission-control REQ-D1.10, REQ-D1.11).
#
# Split from tests/test-mission-control-launch.sh so each file fits the
# per-file test-time budget; the shared fixture is
# tests/lib/mc-launch-fixture.sh.
#
# Runs standalone under /bin/bash (the bash 3.2 floor).

# shellcheck disable=SC2015 # ok only prints, so a fail arm never follows a passing check
set -u
# The usage gate reads the status-line mirror when present; a fixture never
# reads the host's real one.
export PLANWRIGHT_USAGE_MIRROR=""
LC_ALL=C
export LC_ALL
unset CDPATH

here=$(cd "$(dirname "$0")" && pwd)
repo_root=$(cd "$here/.." && pwd -P)
LAUNCH="$repo_root/scripts/mission-control-launch.sh"
# shellcheck source=tests/lib/mc-launch-fixture.sh
. "$here/lib/mc-launch-fixture.sh"

# ---------------------------------------------------------------------------
# REQ-D1.10: a repository-changing kind starts in its own worktree, never in
# a primary checkout; the other kinds start where they are launched.
# ---------------------------------------------------------------------------
gitc() { git -C "$repo" -c user.name=fixture -c user.email=fixture@example.invalid -c commit.gpgsign=false "$@"; }
# no_session <scope> <kind> — no row and no supervisor exist for the launch.
no_session() {
  ns_name=$(cd "$repo" && /bin/sh "$LAUNCH" name --program alpha --kind "$2" --scope "$1")
  [ ! -e "$fleet/mission-control/sessions/$ns_name" ] && [ ! -d "$fleet/streamjson/$ns_name" ]
}
# launched_in <rec> — the directory the launched session ran in.
launched_in() {
  wait_for "$1/cwd" && cat "$1/cwd"
}

before_head=$(git -C "$repo" rev-parse HEAD)
before_branch=$(git -C "$repo" symbolic-ref HEAD)
before_status=$(git -C "$repo" status --porcelain)
rec="$tmp/rec-wt-new"
mkdir -p "$rec"
SHIM_RECORD_DIR=$rec ml launch --program alpha --kind worker --scope wt-new --brief "$tmp/brief.md"
if [ "$RC" != 0 ]; then
  fail "a worker launch with no directory exited $RC: $ERR"
else
  wt=$(launched_in "$rec")
  case $wt in
    "$repo/.claude/worktrees/"?*)
      wt_ref=$(git -C "$wt" symbolic-ref HEAD 2>/dev/null)
      if [ "$(git -C "$wt" rev-parse HEAD 2>/dev/null)" = "$before_head" ] \
        && [ "${wt_ref#refs/heads/planwright/flight/}" != "$wt_ref" ]; then
        ok "a worker launch with no directory starts in a new worktree off the default branch"
      else
        fail "the new worktree $wt is not a fresh branch off main: $(git -C "$wt" log --oneline -1 2>&1)"
      fi
      ;;
    *) fail "a worker launch with no directory started in '$wt', not a new worktree" ;;
  esac
  wait_done "$(field name)"
fi
[ "$(git -C "$repo" rev-parse HEAD)" = "$before_head" ] && [ "$(git -C "$repo" symbolic-ref HEAD)" = "$before_branch" ] \
  && [ "$(git -C "$repo" status --porcelain)" = "$before_status" ] \
  && ok "the primary checkout's HEAD, branch and status are unchanged" \
  || fail "the launch changed the primary checkout: $(git -C "$repo" status --porcelain)"

# The same inputs relaunched after a retire find the worktree on the branch
# they started, with no live session there, and reuse it.
first_wt=$(cat "$rec/cwd" 2>/dev/null)
# The result file lands while the supervisor is still winding down in the
# worktree; the launcher refuses a worktree a process still holds, so the
# relaunch waits for the first run's processes to leave it.
wait_cwd_free "$first_wt"
ml retire "$(field name)"
rec="$tmp/rec-wt-again"
mkdir -p "$rec"
SHIM_RECORD_DIR=$rec ml launch --program alpha --kind worker --scope wt-new --brief "$tmp/brief.md"
[ "$RC" = 0 ] && [ "$(launched_in "$rec")" = "$first_wt" ] \
  && ok "a relaunch reuses the worktree holding its branch when no live session runs there" \
  || fail "the relaunch exited $RC in '$(cat "$rec/cwd" 2>/dev/null)', not $first_wt: $ERR"
wait_done "$(field name)"

# A unit whose branch exists starts on that branch, with its work.
work=$(gitc commit-tree -p main -m 'unit work' "$(git -C "$repo" rev-parse 'main^{tree}')")
gitc branch planwright/demo/task-1 "$work"
rec="$tmp/rec-task-a"
mkdir -p "$rec"
SHIM_RECORD_DIR=$rec ml launch --program alpha --kind worker --scope demo:task-1 --brief "$tmp/brief.md"
task_wt=''
if [ "$RC" != 0 ]; then
  fail "a launch for a unit with an existing branch exited $RC: $ERR"
else
  task_wt=$(launched_in "$rec")
  task_name=$(field name)
  [ "$(git -C "$task_wt" rev-parse HEAD 2>/dev/null)" = "$work" ] \
    && [ "$(git -C "$task_wt" symbolic-ref HEAD 2>/dev/null)" = refs/heads/planwright/demo/task-1 ] \
    && ok "a launch for a unit whose branch exists starts on that branch" \
    || fail "the unit launch in '$task_wt' is not on planwright/demo/task-1 at its work"
  wait_done "$task_name"
fi
# marker_present <id> — a dispatch marker for demo task <id> is on disk.
marker_present() {
  mp_dirs=$(mc_env /bin/sh "$repo_root/scripts/orchestrate-marker-home.sh" read "$repo/specs/demo" 2>/dev/null)
  for mp_d in $mp_dirs; do
    [ -f "$mp_d/$1" ] && return 0
  done
  return 1
}
marker_present 1 && ok "a task placement records the unit's dispatch marker" \
  || fail "the task placement left no dispatch marker for demo task 1"
[ "$(field cwd)" = "$task_wt" ] && ok "the launch report names the worktree" \
  || fail "the launch report's cwd is '$(field cwd)', not $task_wt"

# The worktree holding the branch has a live session (its row is not
# retired): a second launch for the unit is refused, naming it.
rec="$tmp/rec-task-b"
mkdir -p "$rec"
SHIM_RECORD_DIR=$rec ml launch --program alpha --kind reviewer --scope demo:task-1 --brief "$tmp/brief.md"
if [ "$RC" = 3 ] && case $ERR in *"${task_name:-unset}"*) true ;; *) false ;; esac && no_session demo:task-1 reviewer; then
  ok "a worktree holding the branch with a live session refuses the launch, naming the session"
else
  fail "a launch into a worktree with a live session: exit $RC, $ERR"
fi

# A live process in the worktree counts as a live session too.
ml retire "${task_name:-unset}"
marker_present 1 && fail "retiring the unit's session left its dispatch marker" \
  || ok "retiring a task session clears its dispatch marker"
if [ -n "$task_wt" ] && [ -d /proc/self ]; then
  (cd "$task_wt" && exec sleep 60) &
  sleeper=$!
  n=0
  until [ "$(readlink "/proc/$sleeper/cwd" 2>/dev/null)" = "$task_wt" ] || [ "$n" -ge 50 ]; do
    sleep 0.1
    n=$((n + 1))
  done
  SHIM_RECORD_DIR=$rec ml launch --program alpha --kind reviewer --scope demo:task-1 --brief "$tmp/brief.md"
  [ "$RC" = 3 ] && case $ERR in *"process "*"runs in $task_wt"*) true ;; *) false ;; esac && no_session demo:task-1 reviewer \
    && ok "a process running in the worktree holds it as a live session" \
    || fail "a launch beside a live process in the worktree: exit $RC, $ERR"
  kill "$sleeper" 2>/dev/null
  wait "$sleeper" 2>/dev/null
else
  ok "skip: no /proc to place a live process in the worktree"
fi
SHIM_RECORD_DIR=$rec ml launch --program alpha --kind reviewer --scope demo:task-1 --brief "$tmp/brief.md"
[ "$RC" = 0 ] && [ "$(launched_in "$rec")" = "$task_wt" ] \
  && ok "a worktree holding the branch with no live session is reused" \
  || fail "the reuse launch exited $RC in '$(cat "$rec/cwd" 2>/dev/null)': $ERR"
wait_done "$(field name)"
marker_present 1 && ok "a reused task worktree is marked in flight again" \
  || fail "the reuse launch left no dispatch marker for demo task 1"

# Naming the primary checkout, and a worktree that cannot be created, are
# refused with no session started and no row.
ml launch --program alpha --kind worker --scope primary --brief "$tmp/brief.md" --cwd "$repo"
[ "$RC" = 4 ] && case $ERR in *"other than a primary checkout"*) true ;; *) false ;; esac && no_session primary worker \
  && ok "a launch naming the primary checkout is refused (exit $RC) with no session or row" \
  || fail "a launch into the primary checkout: exit $RC"
ml launch --program alpha --kind worker --scope nosuch:task-1 --brief "$tmp/brief.md"
[ "$RC" = 4 ] && case $ERR in *"could not be created"*) true ;; *) false ;; esac && no_session nosuch:task-1 worker \
  && ok "a launch whose worktree cannot be created is refused (exit $RC) with no session or row" \
  || fail "a launch with no creatable worktree: exit $RC"
mkdir -p "$tmp/plain-dir/sub"
if git -C "$tmp/plain-dir" rev-parse >/dev/null 2>&1; then
  ok "skip: the scratch directory sits inside a git checkout"
else
  ml launch --program alpha --kind worker --scope not-a-repo --repo "$tmp/plain-dir" --brief "$tmp/brief.md"
  [ "$RC" = 4 ] && case $ERR in *"in no repository"*) true ;; *) false ;; esac && no_session not-a-repo worker \
    && ok "a launch whose repository is not a git checkout is refused (exit 4)" \
    || fail "a launch outside a repository: exit $RC, $ERR"
  ml launch --program alpha --kind worker --scope plain-cwd --cwd "$tmp/plain-dir" --brief "$tmp/brief.md"
  [ "$RC" = 4 ] && case $ERR in *"other than a primary checkout"*) true ;; *) false ;; esac && no_session plain-cwd worker && ok "a named directory that is no worktree is refused (exit 4)" \
    || fail "a launch naming a plain directory: exit $RC"
fi
ml launch --program alpha --kind worker --scope primary-sub --cwd "$repo/specs" --brief "$tmp/brief.md"
[ "$RC" = 4 ] && case $ERR in *"other than a primary checkout"*) true ;; *) false ;; esac && no_session primary-sub worker && ok "a directory inside the primary checkout is refused (exit 4)" \
  || fail "a launch naming a primary subdirectory: exit $RC"

# Another worktree no live session uses is accepted as named.
gitc worktree add -q -b spare "$tmp/spare" main
rec="$tmp/rec-spare"
mkdir -p "$rec"
SHIM_RECORD_DIR=$rec ml launch --program alpha --kind ad-hoc --scope spare --brief "$tmp/brief.md" --cwd "$tmp/spare"
[ "$RC" = 0 ] && [ "$(launched_in "$rec")" = "$tmp/spare" ] \
  && ok "a launch naming another unused worktree starts there" \
  || fail "a launch naming an unused worktree exited $RC in '$(cat "$rec/cwd" 2>/dev/null)': $ERR"
wait_done "$(field name)"
ml launch --program alpha --kind reviewer --scope spare-2 --brief "$tmp/brief.md" --cwd "$tmp/spare"
spare_name=$(cd "$repo" && /bin/sh "$LAUNCH" name --program alpha --kind ad-hoc --scope spare)
[ "$RC" = 3 ] && case $ERR in *"session $spare_name"*) true ;; *) false ;; esac && no_session spare-2 reviewer \
  && ok "a named worktree a live session uses is refused, naming it" \
  || fail "a named worktree in use: exit $RC, $ERR"

# A tower starts in the caller's directory, with no worktree.
rec="$tmp/rec-tower-here"
mkdir -p "$rec"
SHIM_RECORD_DIR=$rec ml launch --program alpha --kind tower --scope tower-here --brief "$tmp/brief.md"
[ "$RC" = 0 ] && [ "$(launched_in "$rec")" = "$repo" ] && ok "a tower kind starts in the caller's directory" \
  || fail "the tower launch exited $RC in '$(cat "$rec/cwd" 2>/dev/null)': $ERR"
tower_brief=$(field brief)
wait_done "$(field name)"
ml launch --program alpha --kind tower --scope tower-repo --repo "$repo" --brief "$tmp/brief.md"
[ "$RC" = 2 ] && ok "a kind that starts where it is launched refuses --repo" || fail "a tower with --repo: exit $RC"

# A unit with no branch yet gets one off the default branch, and a worker
# scoped <spec>:task-<id> runs on that unit's branch.
rec="$tmp/rec-task-new"
mkdir -p "$rec"
SHIM_RECORD_DIR=$rec ml launch --program alpha --kind worker --scope demo:task-2 --brief "$tmp/brief.md"
if [ "$RC" = 0 ]; then
  tn_wt=$(launched_in "$rec")
  [ "$(git -C "$tn_wt" symbolic-ref HEAD 2>/dev/null)" = refs/heads/planwright/demo/task-2 ] \
    && [ "$(git -C "$tn_wt" rev-parse HEAD)" = "$(git -C "$repo" rev-parse main)" ] \
    && ok "a unit's scope with no branch yet starts a new unit branch off the default branch" \
    || fail "the demo:task-2 launch in '$tn_wt' is not a fresh planwright/demo/task-2"
  # shellcheck disable=SC2016 # literal backticks around the ids
  grep -qF 'PLANWRIGHT_STEP_UNIT_KIND=task' "$(field brief)" && grep -qF 'spec id `demo`, task id `2`' "$(field brief)" \
    && ok "a unit launch's cadence names its task unit" || fail "a unit launch's cadence is not the task unit's"
  wait_done "$(field name)"
else
  fail "the demo:task-2 launch exited $RC: $ERR"
fi

# The tmux rung starts a repository-changing kind in its worktree too.
ml launch --program alpha --kind worker --scope tmux-wt --brief "$tmp/brief.md" --backend tmux
if [ "$RC" = 0 ]; then
  tw_dir=$(field cwd)
  tw_handle=$(awk -F '\t' '$1 == "handle" { print $2 }' "$fleet/mission-control/sessions/$(field name)")
  case $tw_dir in
    "$repo/.claude/worktrees/"?*)
      [ "$(awk 'p { print; exit } $0 == "-c" { p = 1 }' "$tmp/tmux/argv-$tw_handle")" = "$tw_dir" ] \
        && ok "a tmux launch of a repository-changing kind starts in its worktree" \
        || fail "the tmux window was not started in $tw_dir: $(tr '\n' ' ' <"$tmp/tmux/argv-$tw_handle" 2>/dev/null)"
      ;;
    *) fail "the tmux worker launch reported '$tw_dir', not a worktree" ;;
  esac
else
  fail "the tmux worker launch exited $RC: $ERR"
fi

# A primary checkout on another branch: a new worktree still starts off the
# default branch, and the primary keeps its branch.
gitc checkout -q -b side
gitc commit -q --allow-empty -m side
rec="$tmp/rec-off-side"
mkdir -p "$rec"
SHIM_RECORD_DIR=$rec ml launch --program alpha --kind ad-hoc --scope off-side --brief "$tmp/brief.md"
[ "$RC" = 0 ] && [ "$(git -C "$(launched_in "$rec")" rev-parse HEAD)" = "$(git -C "$repo" rev-parse main)" ] \
  && [ "$(git -C "$repo" symbolic-ref HEAD)" = refs/heads/side ] \
  && ok "a new worktree starts off the default branch whatever the primary has checked out" \
  || fail "the launch beside a primary on another branch: exit $RC, HEAD $(git -C "$(cat "$rec/cwd" 2>/dev/null)" log --oneline -1 2>&1)"
wait_done "$(field name)"
gitc checkout -q main

# A unit whose branch the primary checkout itself has checked out is refused
# rather than started in the primary, with no session and no marker.
gitc checkout -q -b planwright/demo/task-3 main
ml launch --program alpha --kind worker --scope demo:task-3 --brief "$tmp/brief.md"
[ "$RC" = 4 ] && case $ERR in *"checked out in the primary checkout"*) true ;; *) false ;; esac \
  && no_session demo:task-3 worker && ! marker_present 3 \
  && ok "a unit whose branch the primary checkout holds is refused (exit 4) with no session or marker" \
  || fail "a launch for a unit checked out in the primary: exit $RC, $ERR"
gitc checkout -q main

# Usage refusals, each with no row: "<kind>|<scope>|<extra args>|<message>".
for case_ in "worker|usage-a|--repo relative/dir|absolute path" "tower|usage-b|--repo $repo|no --repo" \
  "worker|usage-c|--repo $repo --cwd $tmp/spare|neither --repo" "worker|demo:task-7|--cwd $tmp/spare|neither --repo nor a task scope" \
  "worker|demo:task-1.2.3||a task scope is" "worker|Demo:task-1||a task scope is" "ad-hoc|demo:task-x||a task scope is"; do
  IFS='|' read -r u_kind u_scope u_extra u_msg <<EOF
$case_
EOF
  # shellcheck disable=SC2086 # the extra arguments are a word list
  ml launch --program alpha --kind "$u_kind" --scope "$u_scope" $u_extra --brief "$tmp/brief.md"
  if [ "$RC" = 2 ] && case $ERR in *"$u_msg"*) true ;; *) false ;; esac && no_session "$u_scope" "$u_kind"; then
    ok "usage refusal: $u_kind $u_scope $u_extra (exit 2)"
  else
    fail "usage case '$case_' exited $RC: $ERR"
  fi
done

# A refusal after a task placement clears the marker the placement wrote.
cp "$tracked" "$tmp/tracked-marker.bak"
printf 'allocation_model_execution: nonsense\n' >>"$tracked"
ml launch --program alpha --kind worker --scope demo:task-5 --brief "$tmp/brief.md"
[ "$RC" = 4 ] && ! marker_present 5 && no_session demo:task-5 worker \
  && ok "a launch refused after its task placement leaves no dispatch marker" \
  || fail "the post-placement refusal: exit $RC, marker $(marker_present 5 && echo present || echo absent)"
cp "$tmp/tracked-marker.bak" "$tracked"

# The launcher's caller may work inside the worktree it names.
gitc worktree add -q -b inside "$tmp/inside" main
rec="$tmp/rec-inside"
mkdir -p "$rec"
SHIM_RECORD_DIR=$rec ML_CD="$tmp/inside" ml launch --program alpha --kind ad-hoc --scope inside --cwd "$tmp/inside" --brief "$tmp/brief.md"
[ "$RC" = 0 ] && [ "$(launched_in "$rec")" = "$tmp/inside" ] \
  && ok "a caller working inside the named worktree is not a live session there" \
  || fail "a launch from inside its worktree exited $RC: $ERR"
wait_done "$(field name)"

# ---------------------------------------------------------------------------
# REQ-D1.11: a repository-changing brief carries the cadence; a skill command
# carries its own.
# ---------------------------------------------------------------------------
ml name --program alpha --kind worker --scope wt-new
wt_brief="$fleet/mission-control/launch/$OUT/brief.md"
if grep -qx '## Verification cadence' "$wt_brief" && grep -qF 'scripts/step-run.sh audit --through post-pr' "$wt_brief" \
  && grep -qF "*Points*" "$wt_brief"; then
  ok "a repository-changing brief carries the cadence section with the audit command"
else
  fail "the worker brief lacks the cadence section: $(cat "$wt_brief" 2>/dev/null)"
fi
[ -f "$tower_brief" ] && grep -qx '## Verification cadence' "$tower_brief" && fail "a tower brief carries the cadence section" \
  || ok "a kind that changes no repository gets no cadence section"
printf '%s\n' '/planwright:execute-task 1 demo' >"$tmp/unit-skill-brief.md"
ml retire "$(cd "$repo" && /bin/sh "$LAUNCH" name --program alpha --kind reviewer --scope demo:task-1)"
rec="$tmp/rec-unit-skill"
mkdir -p "$rec"
SHIM_RECORD_DIR=$rec ml launch --program alpha --kind reviewer --scope demo:task-1 --brief "$tmp/unit-skill-brief.md"
if [ "$RC" = 0 ]; then
  grep -qx '## Verification cadence' "$(field brief)" && fail "a brief that is a skill command carries the cadence section" \
    || ok "a brief that is a skill command carries no cadence section"
  wait_done "$(field name)"
else
  fail "the skill-command launch exited $RC: $ERR"
fi

# The skill's kickoff relay leaves the directory to the launcher.
relay=$(awk '/^- `relay` —/ { on = 1 } on && /^- `manual`/ { exit } on { print }' "$repo_root/skills/mission-control/SKILL.md")
if [ -n "$relay" ] && printf '%s\n' "$relay" | grep -qF -- '--repo' && ! printf '%s\n' "$relay" | grep -qw -- 'cwd'; then
  ok "the skill's kickoff relay passes the repository, not a start directory"
else
  fail "the kickoff relay names a directory: $relay"
fi

if [ "$failures" -gt 0 ]; then
  echo "$failures failure(s)" >&2
  exit 1
fi
echo "all mission-control-launch tests passed"
