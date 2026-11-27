#!/bin/bash
# Tests for scripts/mission-control-launch.sh --pr <number>: a session put onto
# an open pull request works on the PR's own head branch, in the worktree that
# already holds it, never on a fresh flight branch cut at the base.
#
# The shared fixture is tests/lib/mc-launch-fixture.sh.
#
# Runs standalone under /bin/bash (the bash 3.2 floor).

# shellcheck disable=SC2015 # ok only prints, so a fail arm never follows a passing check
set -u
export PLANWRIGHT_USAGE_MIRROR=""
LC_ALL=C
export LC_ALL
unset CDPATH

here=$(cd "$(dirname "$0")" && pwd)
repo_root=$(cd "$here/.." && pwd -P)
LAUNCH="$repo_root/scripts/mission-control-launch.sh"
# shellcheck source=tests/lib/mc-launch-fixture.sh
. "$here/lib/mc-launch-fixture.sh"

gitc() { git -C "$repo" -c user.name=fixture -c user.email=fixture@example.invalid -c commit.gpgsign=false "$@"; }
launched_in() { wait_for "$1/cwd" && cat "$1/cwd"; }

# The gh stub answers `gh pr view <n>` from $tmp/pr-view (the JSON to print,
# or `fail`).
cat >"$tmp/bin/gh" <<EOF
#!/bin/sh
printf '%s\n' "gh \$*" >>"$tmp/gh.log"
v=\$(cat "$tmp/pr-view" 2>/dev/null) || exit 1
[ "\$v" != fail ] || exit 1
printf '%s\n' "\$v"
EOF
chmod +x "$tmp/bin/gh"
view() { # <head> [<state>] [<cross-repo>] [<head oid>]
  printf '{"headRefName":"%s","headRefOid":"%s","state":"%s","isCrossRepository":%s}\n' \
    "$1" "${4:-${work:-}}" "${2:-OPEN}" "${3:-false}" >"$tmp/pr-view"
}

PRB=planwright/flight/fix-thing-1a2b3c4d
work=$(gitc commit-tree -p main -m 'the PR work' "$(git -C "$repo" rev-parse 'main^{tree}')")
gitc branch "$PRB" "$work"
# Not `held`: the fixture's wait_cwd_free assigns that name.
pr_wt="$repo/.claude/worktrees/flight-fix-thing-1a2b3c4d"
gitc worktree add -q "$pr_wt" "$PRB"
pr_wt=$(cd "$pr_wt" && pwd -P)
branches_before=$(git -C "$repo" for-each-ref --format='%(refname)' refs/heads/planwright/flight/ | sort)

# --- the worktree holding the PR branch is reused ------------------------------

view "$PRB"
rec="$tmp/rec-pr-held"
mkdir -p "$rec"
SHIM_RECORD_DIR=$rec ml launch --program alpha --kind worker --scope fix-pr-12 --pr 12 --brief "$tmp/brief.md"
if [ "$RC" != 0 ]; then
  fail "a --pr launch onto a held PR branch exited $RC: $ERR"
else
  [ "$(launched_in "$rec")" = "$pr_wt" ] \
    && ok "a --pr launch reuses the worktree already holding the PR's head branch" \
    || fail "the --pr launch ran in '$(cat "$rec/cwd" 2>/dev/null)', not $pr_wt"
  [ "$(git -C "$pr_wt" rev-parse HEAD)" = "$work" ] && [ "$(git -C "$pr_wt" symbolic-ref HEAD)" = "refs/heads/$PRB" ] \
    && ok "the reused worktree keeps the PR branch at its work" \
    || fail "the reused worktree moved: $(git -C "$pr_wt" log --oneline -1 2>&1)"
  [ "$(git -C "$repo" for-each-ref --format='%(refname)' refs/heads/planwright/flight/ | sort)" = "$branches_before" ] \
    && ok "no fresh flight branch is cut for the launch" \
    || fail "the --pr launch created a branch: $(git -C "$repo" for-each-ref --format='%(refname)' refs/heads/planwright/flight/)"
  grep -q 'pr view 12 --json' "$tmp/gh.log" && ok "the launch asks gh for pull request 12's head" \
    || fail "gh was not asked about the PR: $(cat "$tmp/gh.log" 2>/dev/null)"
  pr_brief=$(field brief)
  grep -q 'scripts/worker-branch-sync.sh' "$pr_brief" && grep -q 'never with' "$pr_brief" \
    && ok "the brief names the branch-sync helper and the cwd form of git" \
    || fail "the brief lacks the branch-sync paragraph: $(cat "$pr_brief" 2>/dev/null | tail -n 8)"
  pr_name=$(field name)
  wait_done "$pr_name"
  wait_cwd_free "$pr_wt"
  ml retire "$pr_name"
fi

# --- with no holder, a local flight branch is adopted onto a placed worktree ----

gitc worktree remove --force "$pr_wt" || fail "fixture: the PR worktree '$pr_wt' could not be removed"
! git -C "$repo" worktree list --porcelain | grep -qFx "branch refs/heads/$PRB" \
  || fail "fixture: a worktree still holds $PRB"
view "$PRB" OPEN false 0123456789abcdef0123456789abcdef01234567
rec="$tmp/rec-pr-stale"
mkdir -p "$rec"
SHIM_RECORD_DIR=$rec ml launch --program alpha --kind worker --scope fix-pr-12s --pr 12 --brief "$tmp/brief.md"
[ "$RC" = 4 ] && [ ! -e "$rec/cwd" ] && case $ERR in *"not at pull request #12's head"*) true ;; *) false ;; esac \
  && ok "a local PR branch behind the PR's head is refused, not placed" \
  || fail "a stale local PR branch: exit $RC: $ERR"
view "$PRB"
rec="$tmp/rec-pr-placed"
mkdir -p "$rec"
SHIM_RECORD_DIR=$rec ml launch --program alpha --kind worker --scope fix-pr-12b --pr 12 --brief "$tmp/brief.md"
if [ "$RC" != 0 ]; then
  fail "a --pr launch onto an unheld local PR branch exited $RC: $ERR"
else
  placed=$(launched_in "$rec")
  [ "$(git -C "$placed" symbolic-ref HEAD 2>/dev/null)" = "refs/heads/$PRB" ] && [ "$(git -C "$placed" rev-parse HEAD)" = "$work" ] \
    && ok "with no worktree holding it, the local PR branch is placed on a worktree with its work" \
    || fail "the placed worktree '$placed' is not $PRB at its work: $(git -C "$placed" log --oneline -1 2>&1)"
  placed_name=$(field name)
  wait_done "$placed_name"
  wait_cwd_free "$placed"
  ml retire "$placed_name"
fi

# --- refusals -------------------------------------------------------------------

refused_launch() { # <label> <expected rc> <launch args...>
  rl_label=$1 rl_rc=$2
  shift 2
  rec="$tmp/rec-refused"
  rm -rf "$rec"
  mkdir -p "$rec"
  SHIM_RECORD_DIR=$rec ml launch --program alpha --kind worker --brief "$tmp/brief.md" "$@"
  [ "$RC" = "$rl_rc" ] && [ ! -e "$rec/cwd" ] && ok "$rl_label" || fail "$rl_label: exit $RC (wanted $rl_rc): $ERR"
}
view "$PRB" CLOSED
refused_launch "a closed pull request is refused" 4 --scope fix-closed --pr 12
view "$PRB" OPEN true
refused_launch "a pull request from a fork is refused" 4 --scope fix-fork --pr 12
view main
refused_launch "a pull request whose head is main is refused" 4 --scope fix-main --pr 12
view "feature/x"
refused_launch "a pull request whose head is not a flight or task branch is refused" 4 --scope fix-other --pr 12
printf 'fail\n' >"$tmp/pr-view"
refused_launch "a pull request gh cannot read is refused" 4 --scope fix-nogh --pr 12
view planwright/flight/nowhere-0000aaaa
refused_launch "a PR branch no worktree holds and no local branch carries is refused" 4 --scope fix-nowhere --pr 12
git -C "$repo" show-ref --verify --quiet refs/heads/planwright/flight/nowhere-0000aaaa \
  && fail "the refused launch created the missing branch" || ok "the refused launch created no branch"
view planwright/demo/task-9
refused_launch "a task-branch head is refused" 4 --scope fix-task --pr 12
case $ERR in *'task-<id> scope'*) ok "the task-branch refusal names the task scope" ;; *) fail "the refusal does not name the task scope: $ERR" ;; esac
for bad in planwright/flight/legacy-name planwright/flight/task-3-1a2b3c4d planwright/a/b/task-1 'planwright/flight/Bad-1a2b3c4d'; do
  view "$bad"
  refused_launch "the head $bad, outside the session record's unit grammar, is refused" 4 --scope fix-gram --pr 12
done
view "$PRB"
refused_launch "--pr with --cwd is a usage error" 2 --scope fix-cwd --pr 12 --cwd "$tmp"
refused_launch "--pr with a task scope is a usage error" 2 --scope demo:task-1 --pr 12
refused_launch "--pr with --spec-branch is a usage error" 2 --scope fix-spec --pr 12 --spec-branch planwright/demo/spec
case $ERR in *'one or the other'*) ok "the --pr and --spec-branch refusal says why" ;; *) fail "the --pr and --spec-branch refusal does not say why: $ERR" ;; esac
for bad in 0 012 12a -1 1234567890; do
  refused_launch "--pr $bad is a usage error" 2 --scope fix-bad --pr "$bad"
done
rec="$tmp/rec-pr-tower"
mkdir -p "$rec"
SHIM_RECORD_DIR=$rec ml launch --program alpha --kind tower --scope fix-tower --pr 12 --brief "$tmp/brief.md"
[ "$RC" = 2 ] && ok "a kind that changes no repository takes no --pr" || fail "a tower launch with --pr exited $RC: $ERR"

if [ "$failures" -gt 0 ]; then
  echo "$failures failure(s)" >&2
  exit 1
fi
echo "all mission-control-launch --pr tests passed"
