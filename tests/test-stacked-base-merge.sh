#!/bin/bash
# A worker on a stacked pull request (whose base is another feature branch)
# may merge that base, learned once at launch and kept in its session record.
# Three surfaces, each with rows that must pass and rows that must keep
# refusing: the policy guard's base-merge act, scripts/converge-sync-main.sh
# --base, and scripts/worker-session-record.sh --base (the record's
# stack_base field), plus the suffixed task id (task-12a) every one of them
# parses.
#
# Runs standalone under /bin/bash (the bash 3.2 floor).
# shellcheck disable=SC2016 # the unexpanded $ forms are the inputs under test
unset CDPATH
# shellcheck source=tests/lib/policy-guard-harness.sh
. "$(cd "$(dirname "$0")" && pwd)/lib/policy-guard-harness.sh"

SYNC="$REPO_ROOT/scripts/converge-sync-main.sh"
WRITER="$REPO_ROOT/scripts/worker-session-record.sh"
STACK_BR=feat/base-x
OTHER_BR=feat/other
UNIT12=planwright/demo/task-12a

# --- fixtures: a stacked base and a sibling feature branch on origin ----------

for b in "$STACK_BR" "$OTHER_BR"; do
  gitq -C "$SEED" switch -c "$b" main
  gitq -C "$SEED" commit --allow-empty -m "pushed on $b"
  gitq -C "$SEED" push origin "$b"
done
gitq -C "$SEED" switch main

STACK="$SANDBOX/stack"
gitq clone "$ORIGIN" "$STACK"
gitq -C "$STACK" remote set-head origin main
gitq -C "$STACK" switch -c "$UNIT12" "origin/$STACK_BR"
gitq -C "$STACK" config user.name t
gitq -C "$STACK" config user.email t@example.invalid
gitq -C "$STACK" commit --allow-empty -m "unit work"

# write_rec <file> <stack_base-or-empty> [unit] — a session record as the writer
# would leave it, outside the worktree.
write_rec() {
  mkdir -p "$SANDBOX/rec"
  {
    printf 'policy=scratch\n'
    printf 'unit_branch=%s\n' "${3:-$UNIT12}"
    printf 'worktree_root=%s\n' "$STACK"
    printf 'pr_base=origin/main\n'
    [ -z "$2" ] || printf 'stack_base=%s\n' "$2"
    printf 'worker_base_merge=allow\n'
  } >"$1"
}
REC_OK="$SANDBOX/rec/ok.record"
write_rec "$REC_OK" "origin/$STACK_BR"

# sg <tier> <cmd> [record] — the guard on the stacked clone with a record.
sg() {
  local tier=$1 cmd=$2 rec=${3-$REC_OK}
  if [ -n "$rec" ]; then
    PLANWRIGHT_WORKER_SESSION_RECORD=$rec pg "$tier" "$cmd" "$STACK" "$STACK"
  else
    pg "$tier" "$cmd" "$STACK" "$STACK"
  fi
}

tip() { git -C "$STACK" rev-parse "refs/remotes/origin/$1"; }

set_knobs 'worker_base_merge: allow'

echo "# guard: a stacked PR's worker merges its own base"
sg worker 'git merge origin/main' ""
expect defer "[worker] a suffixed task id (task-12a) is a unit branch: the main merge defers"
sg worker "git merge origin/$STACK_BR"
expect defer "[worker] stacked: git merge origin/<base> defers"
sg worker "git merge --no-edit refs/remotes/origin/$STACK_BR"
expect defer "[worker] stacked: the full remote-tracking spelling defers"
sg worker "git merge $(tip "$STACK_BR")"
expect defer "[worker] stacked: a SHA equal to the base's current tip defers"
sg worker "git pull origin $STACK_BR"
expect defer "[worker] stacked: git pull origin <base> defers"

echo "# guard: every other source keeps refusing"
sg worker "git merge origin/$OTHER_BR"
expect deny "[worker] stacked: another feature branch is refused"
reason_has "origin/$STACK_BR" "[worker] the refusal names the accepted form (the stacked base)"
sg worker "git merge $(tip "$OTHER_BR")"
expect deny "[worker] stacked: a SHA that is another branch's tip is refused"
sg worker "git merge $(git -C "$STACK" rev-parse HEAD)"
expect deny "[worker] stacked: a SHA that is the unit's own head is refused"
sg worker "git merge origin/$STACK_BR origin/$OTHER_BR"
expect deny "[worker] stacked: one good source beside a bad one is refused"
sg worker "git pull origin $OTHER_BR"
expect deny "[worker] stacked: a pull of another feature branch is refused"
sg worker "git merge origin/$STACK_BR" ""
expect deny "[worker] no session record: the stacked base is not learned, and refused"
write_rec "$SANDBOX/rec/none.record" ""
sg worker "git merge origin/$STACK_BR" "$SANDBOX/rec/none.record"
expect deny "[worker] a record that names no stacked base refuses the feature-branch merge"
write_rec "$SANDBOX/rec/other.record" "origin/$OTHER_BR"
sg worker "git merge origin/$STACK_BR" "$SANDBOX/rec/other.record"
expect deny "[worker] a record naming another base refuses this one"
write_rec "$SANDBOX/rec/unit.record" "origin/$STACK_BR" planwright/demo/task-3
sg worker "git merge origin/$STACK_BR" "$SANDBOX/rec/unit.record"
expect deny "[worker] a record for another unit branch is no record for this one"
write_rec "$SANDBOX/rec/fork.record" "fork/$STACK_BR"
sg worker "git merge origin/$STACK_BR" "$SANDBOX/rec/fork.record"
expect deny "[worker] a record base on a remote other than the unit's is refused"
sg worker "git merge origin/$STACK_BR" "$SANDBOX/rec/missing.record"
expect deny "[worker] an unreadable record is no record"
ln -sf "$REC_OK" "$SANDBOX/rec/link.record"
sg worker "git merge origin/$STACK_BR" "$SANDBOX/rec/link.record"
expect deny "[worker] a record that is a symlink is no record"
write_rec "$STACK/inside.record" "origin/$STACK_BR"
sg worker "git merge origin/$STACK_BR" "$STACK/inside.record"
expect deny "[worker] a record inside the worktree (which the worker can write) is no record"
{
  printf 'stack_base=origin/%s\n' "$OTHER_BR"
  cat "$REC_OK"
} >"$SANDBOX/rec/dup.record"
sg worker "git merge origin/$STACK_BR" "$SANDBOX/rec/dup.record"
expect deny "[worker] a record repeating stack_base is dropped whole"
sg tower "git merge origin/$STACK_BR"
expect deny "[tower] the stacked base merge is refused at the tower"
set_knobs 'worker_base_merge: deny'
sg worker "git merge origin/$STACK_BR"
expect deny "[worker] worker_base_merge deny refuses the stacked base merge"
reason_has 'worker_base_merge is deny' "[worker] and names the knob"
sg worker 'git merge origin/main'
expect deny "[worker] worker_base_merge deny refuses main on a stacked branch too"
reason_has 'worker_base_merge is deny' "[worker] and the main refusal names the knob"
set_knobs 'worker_base_merge: allow'

echo "# guard: the base moves, and a local ref shadows it"
old_tip=$(tip "$STACK_BR")
gitq -C "$SEED" switch "$STACK_BR"
gitq -C "$SEED" commit --allow-empty -m "base advances"
gitq -C "$SEED" push origin "$STACK_BR"
gitq -C "$SEED" switch main
gitq -C "$STACK" fetch origin
sg worker "git merge $old_tip"
expect deny "[worker] stacked: a SHA that was the base's tip before it moved is refused"
sg worker "git merge $(tip "$STACK_BR")"
expect defer "[worker] stacked: the new tip defers"
gitq -C "$STACK" branch "origin/$STACK_BR" "$old_tip"
sg worker "git merge origin/$STACK_BR"
expect deny "[worker] stacked: a local branch shadowing origin/<base> is refused"
gitq -C "$STACK" branch -D "origin/$STACK_BR"

echo "# record writer: stack_base"
FLEET="$SANDBOX/fleet"
mkdir -p "$FLEET"
PRIM="$SANDBOX/prim"
gitq clone "$ORIGIN" "$PRIM"
gitq -C "$PRIM" remote set-head origin main
WT="$PRIM/.claude/worktrees/stack"
gitq -C "$PRIM" worktree add -b "$UNIT12" "$WT" "origin/$STACK_BR"
wr() { # <args...> — the writer, REC and RC set
  REC=$(PLANWRIGHT_FLEET_STATE_DIR=$FLEET PLANWRIGHT_ADOPTER_OVERLAY=$SANDBOX/adopter \
    PATH="$BIN:$PATH" /bin/sh "$WRITER" write "$@" 2>"$SANDBOX/wr.err")
  RC=$?
}
field() { grep "^$1=" "$REC" | head -n 1 | cut -d= -f2-; }
wr "$WT"
if [ "$RC" = 0 ] && ! grep -q '^stack_base=' "$REC"; then
  pass "[writer] no --base and no PR: no stack_base"
else
  fail "[writer] no --base and no PR: rc=$RC, $(cat "$SANDBOX/wr.err")"
fi
if [ "$(field unit_branch)" = "$UNIT12" ]; then
  pass "[writer] a suffixed task id (task-12a) is recorded as the unit branch"
else
  fail "[writer] unit_branch for task-12a is '$(field unit_branch)'"
fi
wr "$WT" --base "$STACK_BR"
if [ "$RC" = 0 ] && [ "$(field stack_base)" = "origin/$STACK_BR" ]; then
  pass "[writer] --base records stack_base as <remote>/<branch>"
else
  fail "[writer] --base: rc=$RC stack_base='$(field stack_base)'"
fi
wr "$WT" --base main
if [ "$RC" = 0 ] && ! grep -q '^stack_base=' "$REC"; then
  pass "[writer] --base naming the default base records no stack_base"
else
  fail "[writer] --base main wrote stack_base='$(field stack_base)'"
fi
for bad in '-x' '../evil' 'a b' 'a..b' '' 'feat/' 'x.lock'; do
  wr "$WT" --base "$bad"
  if [ "$RC" = 2 ]; then
    pass "[writer] --base '$bad' is a usage error"
  else
    fail "[writer] --base '$bad' exited $RC"
  fi
done
cat >"$SANDBOX/bin-gh-pr" <<EOF
#!/bin/sh
[ "\$1 \$2" = "pr view" ] || exit 1
printf '%s\n' "\${STUB_PR_BASE:-}"
EOF
mkdir -p "$SANDBOX/ghpr"
cp "$SANDBOX/bin-gh-pr" "$SANDBOX/ghpr/gh"
chmod +x "$SANDBOX/ghpr/gh"
REC=$(PLANWRIGHT_FLEET_STATE_DIR=$FLEET PLANWRIGHT_ADOPTER_OVERLAY=$SANDBOX/adopter STUB_PR_BASE=$STACK_BR \
  PATH="$SANDBOX/ghpr:$PATH" /bin/sh "$WRITER" write "$WT" 2>/dev/null)
if [ "$(field stack_base)" = "origin/$STACK_BR" ]; then
  pass "[writer] a PR whose baseRefName is a feature branch is read once into stack_base"
else
  fail "[writer] the PR's base was not read: '$(field stack_base)'"
fi
REC=$(PLANWRIGHT_FLEET_STATE_DIR=$FLEET PLANWRIGHT_ADOPTER_OVERLAY=$SANDBOX/adopter STUB_PR_BASE='bad base!' \
  PATH="$SANDBOX/ghpr:$PATH" /bin/sh "$WRITER" write "$WT" 2>/dev/null)
if ! grep -q '^stack_base=' "$REC"; then
  pass "[writer] a PR base outside the branch grammar is dropped"
else
  fail "[writer] a malformed PR base reached the record: '$(field stack_base)'"
fi

echo "# sync: converge-sync-main.sh --base"
SYNC_CFG="$SANDBOX/sync.yml"
printf '%s\n' 'converge_sync_main: always' 'worker_base_merge: allow' >"$SYNC_CFG"
sync_clone() { # <dir> — a worker clone on the suffixed unit branch over the stacked base
  gitq clone "$ORIGIN" "$1"
  gitq -C "$1" remote set-head origin main
  gitq -C "$1" config user.name t
  gitq -C "$1" config user.email t@example.invalid
  gitq -C "$1" switch -c "$UNIT12" "origin/$STACK_BR"
  gitq -C "$1" commit --allow-empty -m "unit work"
}
run_sync() { # <repo> <record-or-empty> <args...> — OUT and RC set
  local repo=$1 rec=$2
  shift 2
  OUT=$(cd "$repo" && PLANWRIGHT_ADOPTER_OVERLAY=/nonexistent/planwright-adopter PLANWRIGHT_LOCAL_CONFIG=$SYNC_CFG \
    PLANWRIGHT_WORKER_SESSION_RECORD=$rec PLANWRIGHT_REPO_ROOT=$repo \
    /bin/bash "$SYNC" "$@" 2>"$SANDBOX/sync.err")
  RC=$?
}
adv_base() { # <branch> — move a feature branch on origin
  gitq -C "$SEED" switch "$1"
  gitq -C "$SEED" commit --allow-empty -m "advance $1"
  gitq -C "$SEED" push origin "$1"
  gitq -C "$SEED" switch main
}
SY="$SANDBOX/sy"
sync_clone "$SY"
write_rec "$SANDBOX/rec/sy.record" "origin/$STACK_BR"
sed -i.bak "s|^worktree_root=.*|worktree_root=$SY|" "$SANDBOX/rec/sy.record" && rm -f "$SANDBOX/rec/sy.record.bak"
adv_base "$STACK_BR"
want=$(git -C "$ORIGIN" rev-parse "refs/heads/$STACK_BR")
run_sync "$SY" "$SANDBOX/rec/sy.record" --base "$STACK_BR"
if [ "$RC" = 0 ] && git -C "$SY" merge-base --is-ancestor "$want" HEAD; then
  pass "[sync] --base merges the stacked base's new head into the unit branch"
else
  fail "[sync] --base: rc=$RC out='$OUT' err='$(cat "$SANDBOX/sync.err")'"
fi
case $OUT in
  *"sync"*"merged"* | *"sync"*"fast-forward"*) pass "[sync] --base prints the sync record" ;;
  *) fail "[sync] --base printed '$OUT'" ;;
esac

SY2="$SANDBOX/sy2"
sync_clone "$SY2"
sed "s|^worktree_root=.*|worktree_root=$SY2|" "$SANDBOX/rec/sy.record" >"$SANDBOX/rec/sy2.record"
adv_base "$STACK_BR"
before=$(git -C "$SY2" rev-parse HEAD)
run_sync "$SY2" "$SANDBOX/rec/sy2.record" --base "$OTHER_BR"
if [ "$RC" = 2 ] && grep -q "launch record" "$SANDBOX/sync.err" && [ "$(git -C "$SY2" rev-parse HEAD)" = "$before" ]; then
  pass "[sync] --base naming a branch the record does not name is refused, head unchanged"
else
  fail "[sync] another base: rc=$RC head moved or accepted"
fi
run_sync "$SY2" "" --base "$STACK_BR"
if [ "$RC" = 2 ] && grep -q "launch record" "$SANDBOX/sync.err" && [ "$(git -C "$SY2" rev-parse HEAD)" = "$before" ]; then
  pass "[sync] --base with no session record is refused"
else
  fail "[sync] --base with no record: rc=$RC"
fi
write_rec "$SANDBOX/rec/sy2none.record" ""
run_sync "$SY2" "$SANDBOX/rec/sy2none.record" --base "$STACK_BR"
if [ "$RC" = 2 ] && grep -q "launch record" "$SANDBOX/sync.err" && [ "$(git -C "$SY2" rev-parse HEAD)" = "$before" ]; then
  pass "[sync] --base with a record that names no stacked base is refused"
else
  fail "[sync] --base with a baseless record: rc=$RC"
fi
write_rec "$SANDBOX/rec/sy2unit.record" "origin/$STACK_BR" planwright/demo/task-3
run_sync "$SY2" "$SANDBOX/rec/sy2unit.record" --base "$STACK_BR"
if [ "$RC" = 2 ] && grep -q "launch record" "$SANDBOX/sync.err" && [ "$(git -C "$SY2" rev-parse HEAD)" = "$before" ]; then
  pass "[sync] --base with a record for another unit branch is refused"
else
  fail "[sync] --base with another unit's record: rc=$RC"
fi
ln -sf "$SANDBOX/rec/sy2.record" "$SANDBOX/rec/sy2link.record"
run_sync "$SY2" "$SANDBOX/rec/sy2link.record" --base "$STACK_BR"
if [ "$RC" = 2 ] && grep -q "launch record" "$SANDBOX/sync.err"; then
  pass "[sync] --base with a symlinked record is refused"
else
  fail "[sync] --base with a symlinked record: rc=$RC"
fi
sed "s|^worktree_root=.*|worktree_root=$SY2|" "$SANDBOX/rec/sy.record" >"$SY2/inside.record"
run_sync "$SY2" "$SY2/inside.record" --base "$STACK_BR"
if [ "$RC" = 2 ] && grep -q "launch record" "$SANDBOX/sync.err"; then
  pass "[sync] --base with a record inside the worktree is refused"
else
  fail "[sync] --base with an in-worktree record: rc=$RC"
fi
{
  printf 'stack_base=origin/%s\n' "$OTHER_BR"
  cat "$SANDBOX/rec/sy2.record"
} >"$SANDBOX/rec/sy2dup.record"
run_sync "$SY2" "$SANDBOX/rec/sy2dup.record" --base "$STACK_BR"
if [ "$RC" = 2 ] && grep -q "launch record" "$SANDBOX/sync.err"; then
  pass "[sync] --base with a record repeating stack_base is refused"
else
  fail "[sync] --base with a duplicated stack_base: rc=$RC"
fi
write_rec "$SANDBOX/rec/sy2evil.record" "origin/a..b"
run_sync "$SY2" "$SANDBOX/rec/sy2evil.record" --base "a..b"
if [ "$RC" = 2 ] && grep -q "launch record" "$SANDBOX/sync.err"; then
  pass "[sync] --base outside the branch grammar is refused even when the record names it"
else
  fail "[sync] --base a..b: rc=$RC"
fi
printf '%s\n' 'converge_sync_main: always' 'worker_base_merge: deny' >"$SYNC_CFG"
run_sync "$SY2" "$SANDBOX/rec/sy2.record" --base "$STACK_BR"
case $OUT in
  *denied*) pass "[sync] worker_base_merge deny skips the stacked merge (denied record)" ;;
  *) fail "[sync] deny: rc=$RC out='$OUT'" ;;
esac
printf '%s\n' 'converge_sync_main: always' 'worker_base_merge: allow' >"$SYNC_CFG"
run_sync "$SY2" "" --base main
if [ "$RC" = 2 ] && grep -q "launch record" "$SANDBOX/sync.err"; then
  pass "[sync] --base main with no record is refused (the default form takes no flag)"
else
  fail "[sync] --base main with no record exited 0"
fi
run_sync "$SY2" ""
if [ "$RC" = 0 ] || [ "$RC" = 5 ] || [ "$RC" = 6 ]; then
  pass "[sync] the plain form, with no --base, still syncs main as before"
else
  fail "[sync] the plain form: rc=$RC err='$(cat "$SANDBOX/sync.err")'"
fi
SY3="$SANDBOX/sy3"
sync_clone "$SY3"
adv_base main
run_sync "$SY3" "" --need test
if [ "$RC" = 0 ]; then
  pass "[sync] a suffixed task id (task-12a) is a unit branch to the sync script"
else
  fail "[sync] task-12a rejected: rc=$RC err='$(cat "$SANDBOX/sync.err")'"
fi

finish
