#!/bin/bash
# Tests for scripts/worker-branch-sync.sh: the record it reads, the shared
# checks every verb makes, and two of its routes, a hard reset to the branch's
# own remote branch and a fast-forward to a descendant commit, each only in
# its own clean worktree on the branch its session record names. The leased
# push is tests/test-worker-branch-sync-push.sh's; the policy guard decides
# which commands may run the helper (tests/test-policy-guard-branch-sync.sh).
#
# Runs standalone under /bin/bash (the bash 3.2 floor):
#   ./tests/test-worker-branch-sync.sh
unset CDPATH
here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=tests/lib/worker-branch-sync-fixture.sh
. "$here/lib/worker-branch-sync-fixture.sh"

record "$wt" "$B"
tip_before=$(remote_tip "$B")
nothing_moved() { [ "$(remote_tip "$B")" = "$tip_before" ] || fail "$1: a refused run moved origin's branch"; }

run "$wt" --force-if-includes reset "origin/$B"
[ "$RC" = 2 ] || fail "an option before the verb was not a usage error (exit $RC): $OUT"
pass "the verb comes first"

# --- the branch and the session record ----------------------------------------

for sub in demo-spec:planwright/demo/spec prot:planwright/flight/prot; do
  d="$tmp/wt-${sub%%:*}"
  br=${sub#*:}
  worktree "$d" "$br"
  g -C "$d" commit -q --allow-empty -m one
  record "$d" "$br" launcher=mission-control draft_rewrite=allow
  before=$(g -C "$d" rev-parse HEAD)
  run "$d" reset "origin/$br"
  refused "a reset on $br"
  case $br in
    */spec) has 'not a unit branch' "the spec-branch refusal says why" ;;
    *) has 'protected set' "the protected-branch refusal says why" ;;
  esac
  [ "$(g -C "$d" rev-parse HEAD)" = "$before" ] || fail "a refused reset moved $br"
  run "$d" ff "$(g -C "$d" commit-tree -p HEAD -m next "HEAD^{tree}")"
  refused "a fast-forward on $br"
done
pass "a spec branch and a protected branch are refused, even when the session record names them"

dmain="$tmp/wt-main"
g -C "$primary" worktree add -q --detach "$dmain" origin/main
g -C "$dmain" switch -q --ignore-other-worktrees main
record "$dmain" main
run "$dmain" reset origin/main
refused "a reset on main"
has 'not a unit branch' "the main refusal says why"
pass "main is refused, even when the session record names it"

fixed=$(rec_path "$wt")
mv "$fixed" "$tmp/saved.record"
run "$wt" reset "origin/$B"
refused "no session record"
has 'no session record' "the missing-record refusal names the record"
# A record the environment names is never read: only the worktree's own path.
cp "$tmp/saved.record" "$tmp/forged.record"
RC=0
OUT=$(cd "$wt" && PLANWRIGHT_WORKER_SESSION_RECORD="$tmp/forged.record" "$SCRIPT" reset "origin/$B" 2>&1) || RC=$?
refused "a record the environment names"
has 'no session record' "the environment-named record is not read"
mv "$tmp/saved.record" "$fixed"
record "$wt" "$B"
sed "s|^worktree_root=.*|worktree_root=$tmp/elsewhere|" "$fixed" >"$tmp/r" && mv "$tmp/r" "$fixed" && chmod 600 "$fixed"
run "$wt" reset "origin/$B"
refused "a record naming another worktree"
record "$wt" planwright/flight/other
run "$wt" reset "origin/$B"
refused "a record naming another branch"
record "$wt" "$B" "unit_branch=$B"
run "$wt" reset "origin/$B"
refused "a record naming the branch twice"
has 'malformed' "the doubled-key refusal names the record malformed"
record "$wt" "$B" 'not a key value line'
run "$wt" reset "origin/$B"
refused "a record with a line that is not key=value"
has 'malformed' "the malformed-line refusal says why"
record "$wt" "$B"
chmod 666 "$fixed"
run "$wt" reset "origin/$B"
refused "a record others can write"
record "$wt" "$B"
chmod 000 "$fixed"
if [ -r "$fixed" ]; then
  chmod 600 "$fixed"
  pass "an unreadable record: skipped, this user reads every file (root)"
else
  run "$wt" reset "origin/$B"
  chmod 600 "$fixed"
  refused "an unreadable record"
  pass "an unreadable record is refused"
fi
mv "$fixed" "$tmp/target.record"
ln -s "$tmp/target.record" "$fixed"
run "$wt" reset "origin/$B"
refused "a record that is a symlink"
rm -f "$fixed" "$tmp/target.record"
record "$wt" "$B"
pass "no record, or one the environment names, naming another worktree or branch, malformed, loose, unreadable or linked, is refused"

g -C "$primary" switch -q --ignore-other-worktrees "$B"
record "$primary" "$B"
run "$primary" reset "origin/$B"
refused "the primary checkout"
has 'primary checkout|linked worktree' "the primary-checkout refusal says why"
g -C "$primary" switch -q --ignore-other-worktrees main
pass "a primary checkout is refused: the helper works in a linked worktree only"

g -C "$wt" switch -q -c planwright/flight/side
run "$wt" reset origin/planwright/flight/side
refused "a reset on another branch"
g -C "$wt" switch -q "$B"
pass "another branch checked out in the own worktree is refused"

# --- shared branches ---------------------------------------------------------

twin="$tmp/wt-twin"
g -C "$primary" worktree add -q --force "$twin" "$B"
run "$wt" reset "origin/$B"
refused "another worktree holding the branch"
has 'another worktree|wt-twin' "the shared refusal names the other worktree"
g -C "$primary" worktree remove --force "$twin"
pass "a branch another worktree holds is shared, and refused"

# A process working in the worktree that is no part of this run (a second
# session there), orphaned so its parent is not this test.
( (cd "$wt" && exec sleep 60 >/dev/null 2>&1) &)
sleeper=''
i=0
while [ -z "$sleeper" ] && [ "$i" -lt 50 ]; do
  for p in $(pgrep -x sleep 2>/dev/null || :); do
    c=$(readlink "/proc/$p/cwd" 2>/dev/null || lsof -a -p "$p" -d cwd -Fn 2>/dev/null | sed -n 's/^n//p')
    [ "$c" = "$wt" ] && sleeper=$p
  done
  [ -n "$sleeper" ] || sleep 0.1
  i=$((i + 1))
done
[ -n "$sleeper" ] || fail "fixture: the foreign process did not start in the worktree"
run "$wt" reset "origin/$B"
kill "$sleeper" 2>/dev/null || :
refused "a live process of another session in the worktree"
has "process $sleeper" "the live-session refusal names the process"
pass "a branch another live session works on is shared, and refused"
i=0
while kill -0 "$sleeper" 2>/dev/null && [ "$i" -lt 50 ]; do
  sleep 0.1
  i=$((i + 1))
done

# --- links and a detached HEAD ------------------------------------------------

ln -s "$SCRIPT" "$tmp/linked-sync.sh"
RC=0
OUT=$(cd "$wt" && "$tmp/linked-sync.sh" reset "origin/$B" 2>&1) || RC=$?
refused "a run through a symbolic link"
has 'symbolic link' "the link refusal says why"
nothing_moved "a run through a symbolic link"
pass "a run through a symbolic link to the helper is refused"

g -C "$wt" switch -q --detach
run "$wt" reset "origin/$B"
refused "a detached HEAD"
has 'detached' "the detached refusal says why"
g -C "$wt" switch -q "$B"
pass "a detached HEAD is refused"

# --- reset -------------------------------------------------------------------

g -C "$wt" commit -q --allow-empty -m "a local commit to drop"
dropped=$(g -C "$wt" rev-parse HEAD)
printf 'protected_branches: planwright/flight/prot\nunpushed_rewrite: deny\n' >"$LOCAL_CFG"
run "$wt" reset "origin/$B"
refused "a reset dropping local commits under unpushed_rewrite deny"
has 'unpushed_rewrite is deny' "the unpushed_rewrite refusal says why"
[ "$(g -C "$wt" rev-parse HEAD)" = "$dropped" ] || fail "a refused reset moved HEAD"
printf 'protected_branches: planwright/flight/prot\n' >"$LOCAL_CFG"
pass "a reset that would drop local commits needs unpushed_rewrite to allow it"
run "$wt" reset "origin/$B"
[ "$RC" = 0 ] || fail "the reset to the own remote branch did not succeed: $OUT"
[ "$(g -C "$wt" rev-parse HEAD)" = "$(g -C "$wt" rev-parse "origin/$B")" ] || fail "the reset did not land on origin/$B"
has "$dropped" "the reset names the commit it dropped"
pass "a reset to the own remote branch lands on it and names what it dropped"

g -C "$wt" commit -q --allow-empty -m "kept"
keep=$(g -C "$wt" rev-parse HEAD)
printf 'dirty\n' >"$wt/untracked.txt"
run "$wt" reset "origin/$B"
refused "a reset with an untracked file"
[ "$(g -C "$wt" rev-parse HEAD)" = "$keep" ] || fail "a refused reset moved HEAD"
rm -f "$wt/untracked.txt"
printf 'x\n' >"$wt/tracked.txt"
g -C "$wt" add tracked.txt
run "$wt" reset "origin/$B"
refused "a reset with a staged change"
g -C "$wt" reset -q
g -C "$wt" add tracked.txt
g -C "$wt" commit -q -m "a tracked file"
keep=$(g -C "$wt" rev-parse HEAD)
printf 'changed\n' >"$wt/tracked.txt"
run "$wt" reset "origin/$B"
refused "a reset with an unstaged change"
g -C "$wt" checkout -q -- tracked.txt
merge_head=$(g -C "$wt" rev-parse --git-path MERGE_HEAD)
case $merge_head in /*) ;; *) merge_head="$wt/$merge_head" ;; esac
printf '%s\n' "$keep" >"$merge_head"
run "$wt" reset "origin/$B"
refused "a reset with a merge in progress"
has 'in progress' "the in-progress refusal says why"
rm -f "$merge_head"
[ "$(g -C "$wt" rev-parse HEAD)" = "$keep" ] || fail "a refused reset moved HEAD"
pass "a reset in a dirty tree (staged, unstaged or untracked) or mid-merge is refused and moves nothing"

for t in origin/main origin/planwright/flight/other "$B" "refs/remotes/origin/$B" "origin/$B~1" HEAD; do
  run "$wt" reset "$t"
  refused "a reset to $t"
done
run "$wt" reset
refused "a reset with no target"
run "$wt" reset "origin/$B" --hard
refused "a reset with an extra argument"
[ "$(g -C "$wt" rev-parse HEAD)" = "$keep" ] || fail "a refused reset moved HEAD"
pass "a reset to anything but origin/<own branch> is refused"

other_wt="$tmp/wt-other"
worktree "$other_wt" planwright/flight/other
run "$other_wt" reset origin/planwright/flight/other
refused "a reset outside the own worktree"
run "$other_wt" reset "origin/$B"
refused "a reset naming the own branch from another worktree"
pass "a reset outside the own worktree is refused"

# The reset refreshes the remote branch itself: a commit pushed elsewhere and
# never fetched here is where it lands.
other_clone="$tmp/other-clone"
g clone -q "$origin" "$other_clone"
g -C "$other_clone" switch -q "$B"
g -C "$other_clone" commit -q --allow-empty -m "someone else's commit"
g -C "$other_clone" push -q origin "$B"
theirs=$(g -C "$origin" rev-parse "$B")
[ "$(g -C "$wt" rev-parse "origin/$B")" != "$theirs" ] || fail "fixture: the worktree already had the other push"
run "$wt" reset "origin/$B"
[ "$RC" = 0 ] || fail "the refreshing reset did not succeed: $OUT"
[ "$(g -C "$wt" rev-parse HEAD)" = "$theirs" ] || fail "the reset did not land on the freshly fetched tip"
pass "a reset refreshes origin/<own branch> first and lands on its current tip"
g -C "$primary" remote set-url origin git@github.com:acme/no-such.git
run "$wt" reset "origin/$B"
g -C "$primary" remote set-url origin "$URL"
refused "a reset whose remote branch cannot be refreshed"
has 'could not be refreshed' "the refresh refusal says why"
pass "a reset whose remote branch cannot be refreshed is refused"

# --- ff ----------------------------------------------------------------------

desc=$(g -C "$wt" commit-tree -p HEAD -m "a descendant" "HEAD^{tree}")
run "$wt" ff "$desc"
[ "$RC" = 0 ] || fail "the fast-forward to a descendant did not succeed: $OUT"
[ "$(g -C "$wt" rev-parse HEAD)" = "$desc" ] || fail "the fast-forward did not land on the descendant"
pass "a fast-forward to a descendant commit lands on it"

sibling=$(g -C "$wt" commit-tree -p HEAD~1 -m "a sibling" "HEAD^{tree}")
run "$wt" ff "$sibling"
refused "a non-descendant"
has 'descendant' "the non-descendant refusal says why"
run "$wt" ff "$desc"
refused "a target equal to HEAD"
[ "$(g -C "$wt" rev-parse HEAD)" = "$desc" ] || fail "a refused fast-forward moved HEAD"
pass "a non-descendant target, or HEAD itself, is refused"

next=$(g -C "$wt" commit-tree -p HEAD -m "next" "HEAD^{tree}")
printf 'dirty\n' >"$wt/untracked.txt"
run "$wt" ff "$next"
refused "a fast-forward in a dirty tree"
rm -f "$wt/untracked.txt"
for t in "${next%????}" HEAD "origin/$B" "$next $next" "-$next"; do
  run "$wt" ff "$t"
  refused "a fast-forward to $t"
done
run "$wt" ff
refused "a fast-forward with no target"
run "$wt" ff "$next" extra
refused "a fast-forward with an extra argument"
[ "$(g -C "$wt" rev-parse HEAD)" = "$desc" ] || fail "a refused fast-forward moved HEAD"
pass "a dirty tree, a short or symbolic target, or extra words are refused"

g -C "$wt" switch -q -c planwright/flight/side2
side_next=$(g -C "$wt" commit-tree -p HEAD -m "next" "HEAD^{tree}")
run "$wt" ff "$side_next"
refused "a fast-forward on another branch"
g -C "$wt" switch -q "$B"
pass "a fast-forward on another branch than the record names is refused"

run "$wt" ff "$next"
[ "$RC" = 0 ] || fail "the fast-forward after the refusals did not succeed: $OUT"
pass "after every refusal, the own fast-forward still lands"

# --- usage -------------------------------------------------------------------

for v in '' bogus rebase merge; do
  if [ -z "$v" ]; then run "$wt"; else run "$wt" "$v"; fi
  [ "$RC" = 2 ] || fail "the verb '$v' did not exit as a usage error (exit $RC): $OUT"
done
pass "an unknown or missing verb is a usage error"
run "$tmp" --help
[ "$RC" = 0 ] || fail "--help exited $RC: $OUT"
has 'reset <origin/branch>' "the usage text names the reset grammar"
has 'push --force-with-lease=<branch:sha> --force-if-includes' "the usage text names the push grammar"
pass "--help prints the usage, anywhere and with no record"

printf '\npasses: %s\n' "$passes"
