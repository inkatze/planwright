#!/bin/bash
# Tests for scripts/worker-branch-sync.sh, the routes a dispatched worker syncs
# its own unit branch's worktree by: a hard reset to its own remote branch and
# a fast-forward to a descendant commit, each only in its own clean worktree on
# the branch its session record names. It publishes nothing: push is refused.
# The policy guard decides which commands may run it
# (tests/test-policy-guard-branch-sync.sh); these cases pin what the script
# itself will and will not do.
#
# Runs standalone under /bin/bash (the bash 3.2 floor):
#   ./tests/test-worker-branch-sync.sh
set -euf
LC_ALL=C
export LC_ALL
unset CDPATH
unset GIT_DIR GIT_WORK_TREE GIT_COMMON_DIR GIT_INDEX_FILE GIT_OBJECT_DIRECTORY \
  GIT_CONFIG GIT_CONFIG_PARAMETERS GIT_CONFIG_COUNT GIT_NAMESPACE GIT_PREFIX \
  PLANWRIGHT_WORKER_SESSION_RECORD

here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=tests/lib/hermetic-env.sh
. "$here/lib/hermetic-env.sh"
SCRIPT="$here/../scripts/worker-branch-sync.sh"

passes=0
fail() {
  printf '%s\n' "FAIL: $1" >&2
  exit 1
}
pass() {
  printf '%s\n' "ok: $1"
  passes=$((passes + 1))
}

[ -x "$SCRIPT" ] || fail "scripts/worker-branch-sync.sh missing or not executable"

tmp=$(mktemp -d "${TMPDIR:-/tmp}/test-worker-branch-sync.XXXXXX") || fail "could not create a scratch directory"
tmp=$(cd "$tmp" && pwd -P)
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/home" "$tmp/xdg" "$tmp/bin" "$tmp/fleet/session-records"
HOME="$tmp/home"
XDG_CONFIG_HOME="$tmp/xdg"
GIT_CONFIG_GLOBAL=/dev/null
GIT_CONFIG_NOSYSTEM=1
PLANWRIGHT_LOCAL_CONFIG="$tmp/local.yml"
export HOME XDG_CONFIG_HOME GIT_CONFIG_GLOBAL GIT_CONFIG_NOSYSTEM PLANWRIGHT_LOCAL_CONFIG
printf 'protected_branches: planwright/flight/prot\n' >"$PLANWRIGHT_LOCAL_CONFIG"

g() {
  git -c init.defaultBranch=main -c user.name=t -c user.email=t@example.invalid -c commit.gpgSign=false "$@"
}

origin="$tmp/origin.git"
seed="$tmp/seed"
g init -q --bare "$origin"
g init -q "$seed"
g -C "$seed" commit -q --allow-empty -m base
g -C "$seed" remote add origin "$origin"
g -C "$seed" push -q origin main
for b in planwright/flight/demo planwright/flight/other planwright/flight/prot planwright/demo/spec; do
  g -C "$seed" switch -q -c "$b" main
  g -C "$seed" commit -q --allow-empty -m "pushed on $b"
  g -C "$seed" push -q origin "$b"
done

primary="$tmp/primary"
g clone -q "$origin" "$primary"
# worktree <dir> <branch> — a linked worktree of the primary on <branch>.
worktree() {
  g -C "$primary" branch -q --track "$2" "origin/$2" 2>/dev/null || :
  g -C "$primary" worktree add -q "$1" "$2"
}
wt="$tmp/wt"
worktree "$wt" planwright/flight/demo

# record <file> <unit branch> <worktree root> — a session record as the
# launcher writes one, outside the worktree.
record() {
  printf 'policy=own-branch\nunit_branch=%s\nworktree_root=%s\n' "$2" "$3" >"$1"
  chmod 600 "$1"
}
rec="$tmp/fleet/session-records/demo.record"
record "$rec" planwright/flight/demo "$wt"

# run <dir> <args...> — the helper in <dir> under the session record; sets RC
# and OUT (stdout and stderr together).
REC=$rec
run() {
  local d=$1
  shift
  RC=0
  OUT=$(cd "$d" && PLANWRIGHT_WORKER_SESSION_RECORD=$REC "$SCRIPT" "$@" 2>&1) || RC=$?
}
refused() { # <label> — the last run refused (exit 1)
  [ "$RC" = 1 ] || fail "$1: expected a refusal (exit 1), got exit $RC: $OUT"
}
has() { # <ERE> <label>
  printf '%s' "$OUT" | grep -Eq -- "$1" || fail "$2: the output does not match /$1/: $OUT"
}
remote_tip() { g -C "$origin" rev-parse "$1"; }

B=planwright/flight/demo

# --- the helper publishes nothing ----------------------------------------------

g -C "$wt" commit -q --allow-empty -m "work 1"
g -C "$wt" push -q origin "$B"
lease=$(g -C "$wt" rev-parse HEAD)
g -C "$wt" commit -q --amend --allow-empty -m "work 1, reworded"
tip_before=$(remote_tip "$B")
nothing_moved() { [ "$(remote_tip "$B")" = "$tip_before" ] || fail "$1: a refused run moved origin's branch"; }
for args in "push --force-with-lease=$B:$lease --force-if-includes" "push --force" "push"; do
  # shellcheck disable=SC2086 # the words are the arguments under test
  run "$wt" $args
  refused "$args"
  has 'no verb of this helper' "the push refusal says why"
done
nothing_moved "push"
pass "push in every spelling is refused: a rewrite of a pushed branch stays the tower's"

run "$wt" --force-if-includes reset "origin/$B"
[ "$RC" = 2 ] || fail "an option before the verb was not a usage error (exit $RC): $OUT"
pass "the verb comes first"

# --- the branch and the session record ----------------------------------------

for sub in demo-spec:planwright/demo/spec prot:planwright/flight/prot; do
  d="$tmp/wt-${sub%%:*}"
  br=${sub#*:}
  worktree "$d" "$br"
  g -C "$d" commit -q --allow-empty -m one
  REC="$tmp/fleet/session-records/${sub%%:*}.record"
  record "$REC" "$br" "$d"
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
REC=$rec

dmain="$tmp/wt-main"
g -C "$primary" worktree add -q --detach "$dmain" origin/main
g -C "$dmain" switch -q --ignore-other-worktrees main
REC="$tmp/fleet/session-records/main.record"
record "$REC" main "$dmain"
run "$dmain" reset origin/main
refused "a reset on main"
has 'not a unit branch' "the main refusal says why"
REC=$rec
pass "main is refused, even when the session record names it"

REC=''
run "$wt" reset "origin/$B"
refused "no session record"
has 'session record' "the missing-record refusal names the record"
REC="$wt/inside.record"
record "$REC" "$B" "$wt"
run "$wt" reset "origin/$B"
refused "a record inside the worktree"
has "record's path lies inside" "the inside-the-worktree refusal names the path check"
rm -f "$wt/inside.record"
REC="$tmp/fleet/session-records/wrong-top.record"
record "$REC" "$B" "$tmp/elsewhere"
run "$wt" reset "origin/$B"
refused "a record naming another worktree"
REC="$tmp/fleet/session-records/wrong-branch.record"
record "$REC" planwright/flight/other "$wt"
run "$wt" reset "origin/$B"
refused "a record naming another branch"
REC="$tmp/fleet/session-records/twice.record"
record "$REC" "$B" "$wt"
printf 'unit_branch=%s\n' "$B" >>"$REC"
run "$wt" reset "origin/$B"
refused "a record naming the branch twice"
REC="$tmp/fleet/session-records/loose.record"
record "$REC" "$B" "$wt"
chmod 666 "$REC"
run "$wt" reset "origin/$B"
refused "a record others can write"
REC="$tmp/fleet/session-records/link.record"
ln -s "$rec" "$REC"
run "$wt" reset "origin/$B"
refused "a record that is a symlink"
REC=$rec
pass "no record, or one inside the worktree, naming another worktree or branch, malformed, loose or linked, is refused"

g -C "$primary" switch -q --ignore-other-worktrees "$B"
REC="$tmp/fleet/session-records/primary.record"
record "$REC" "$B" "$primary"
run "$primary" reset "origin/$B"
refused "the primary checkout"
has 'primary checkout|linked worktree' "the primary-checkout refusal says why"
g -C "$primary" switch -q --ignore-other-worktrees main
REC=$rec
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
run "$wt" reset "origin/$B"
refused "a reset while another worktree holds the branch"
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
OUT=$(cd "$wt" && PLANWRIGHT_WORKER_SESSION_RECORD=$REC "$tmp/linked-sync.sh" reset "origin/$B" 2>&1) || RC=$?
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
printf 'protected_branches: planwright/flight/prot\nunpushed_rewrite: deny\n' >"$PLANWRIGHT_LOCAL_CONFIG"
run "$wt" reset "origin/$B"
refused "a reset dropping local commits under unpushed_rewrite deny"
has 'unpushed_rewrite is deny' "the unpushed_rewrite refusal says why"
[ "$(g -C "$wt" rev-parse HEAD)" = "$dropped" ] || fail "a refused reset moved HEAD"
printf 'protected_branches: planwright/flight/prot\n' >"$PLANWRIGHT_LOCAL_CONFIG"
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

onext=$(g -C "$other_wt" commit-tree -p HEAD -m "next" "HEAD^{tree}")
run "$other_wt" ff "$onext"
refused "a fast-forward outside the own worktree"
g -C "$wt" switch -q -c planwright/flight/side2
side_next=$(g -C "$wt" commit-tree -p HEAD -m "next" "HEAD^{tree}")
run "$wt" ff "$side_next"
refused "a fast-forward on another branch"
g -C "$wt" switch -q "$B"
pass "a fast-forward outside the own worktree, or on another branch, is refused"

run "$wt" ff "$next"
[ "$RC" = 0 ] || fail "the fast-forward after the refusals did not succeed: $OUT"
pass "after every refusal, the own fast-forward still lands"

# --- usage -------------------------------------------------------------------

for v in '' bogus rebase merge; do
  if [ -z "$v" ]; then run "$wt"; else run "$wt" "$v"; fi
  [ "$RC" = 2 ] || fail "the verb '$v' did not exit as a usage error (exit $RC): $OUT"
done
pass "an unknown or missing verb is a usage error"
REC=''
run "$tmp" --help
[ "$RC" = 0 ] || fail "--help exited $RC: $OUT"
has 'reset <origin/branch>' "the usage text names the reset grammar"
pass "--help prints the usage, anywhere and with no record"

printf '\npasses: %s\n' "$passes"
