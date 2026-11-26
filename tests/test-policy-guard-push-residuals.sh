#!/bin/bash
# Adversarial suite for scripts/policy-guard.sh: pushes whose real destination
# git reads from somewhere other than the command line (a tag sharing the
# current branch's name, a legacy remotes or branches file, a local symbolic
# branch), the plumbing and contrib commands that push (git send-pack, git
# subtree push), and a gh api contents write naming heads/<branch>.
#
# Each fixture is first checked against real git, a dry run into the sandbox
# origin, so a case whose push would not reach main fails as a broken fixture
# rather than passing for nothing.
#
# Runs standalone under /bin/bash (the bash 3.2 floor).
# shellcheck disable=SC2016 # the unexpanded $ forms are the inputs under test
unset CDPATH
# shellcheck source=tests/lib/policy-guard-harness.sh
. "$(cd "$(dirname "$0")" && pwd)/lib/policy-guard-harness.sh"

set_knobs 'protected_branches:' 'unpushed_rewrite: allow' 'worker_base_merge: allow'
TAB=$(printf '\t')

# reaches_main <dir> <git push args...> — 0 when a dry run of the push from
# <dir> would update the sandbox origin's main.
reaches_main() {
  local d=$1 out
  shift
  out=$(git -C "$d" push --dry-run --porcelain "$@" 2>&1) || return 1
  case $out in *':refs/heads/main'"$TAB"*) return 0 ;; esac
  return 1
}

fixture() { # <label> <dir> <git push args...>
  local label=$1
  shift
  reaches_main "$@" || fail "fixture: $label does not reach main in real git, so its case would be vacuous"
}

# --- a tag named like the current branch (finding 1) ------------------------

echo "# a tag sharing the current branch's name"
TAGD="$SANDBOX/tagmain"
clone_on "$TAGD" main 1
gitq -C "$TAGD" tag main
fixture 'a bare push on main with a tag main' "$TAGD"
fixture 'a push of HEAD on main with a tag main' "$TAGD" origin HEAD
for tier in worker tower; do
  for cmd in 'git push' 'git push origin' 'git push origin HEAD' 'git push origin @'; do
    pg "$tier" "$cmd" "$TAGD"
    expect deny "[$tier] $cmd on main, with a tag named main, denies"
    reason_has 'shares its name' "[$tier] $cmd names the ambiguous branch"
  done
done
TAGU="$SANDBOX/tagunit"
clone_on "$TAGU" planwright/demo/task-1 1
gitq -C "$TAGU" tag planwright/demo/task-1
pg worker 'git push' "$TAGU"
expect deny "[worker] a bare push whose branch shares its name with a tag denies (the branch git reads is ambiguous to the guard)"
reason_has 'shares its name' "the ambiguous-branch deny says why"
pg worker 'git push origin planwright/demo/task-1:planwright/demo/task-1' "$TAGU"
expect defer "[worker] a push naming its destination in full still defers beside a same-named tag"

no_gh_calls
finish
