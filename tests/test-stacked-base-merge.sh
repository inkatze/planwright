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
ln -s "$STACK" "$SANDBOX/stack-alias"
write_rec "$STACK/aliased.record" "origin/$STACK_BR"
sg worker "git merge origin/$STACK_BR" "$SANDBOX/stack-alias/aliased.record"
expect deny "[worker] a record reached through a symlinked path into the worktree is no record"
{
  printf 'stack_base=origin/%s\n' "$OTHER_BR"
  cat "$REC_OK"
} >"$SANDBOX/rec/dup.record"
sg worker "git merge origin/$STACK_BR" "$SANDBOX/rec/dup.record"
expect deny "[worker] a record repeating stack_base is dropped whole"
{
  cat "$REC_OK"
  printf 'pad=%04097d\n' 0
} >"$SANDBOX/rec/big.record"
sg worker "git merge origin/$STACK_BR" "$SANDBOX/rec/big.record"
expect deny "[worker] a record past the 4096 bytes every reader accepts is no record"
gitq -C "$STACK" update-ref refs/remotes/origin/origin "$(tip "$STACK_BR")"
write_rec "$SANDBOX/rec/noslash.record" origin
sg worker 'git merge origin/origin' "$SANDBOX/rec/noslash.record"
expect deny "[worker] a record base naming only the remote is no branch"
gitq -C "$STACK" update-ref -d refs/remotes/origin/origin
sg worker "git merge remotes/origin/$STACK_BR"
expect defer "[worker] stacked: the remotes/<remote>/<base> spelling defers"
short_tip=$(tip "$STACK_BR")
sg worker "git merge ${short_tip%????????????????????????????}"
expect deny "[worker] stacked: an abbreviated id of the base's tip is refused"
sg worker "git pull origin $STACK_BR" ""
expect deny "[worker] no session record: a pull of the stacked base is refused"
sg worker "git pull origin $OTHER_BR"
reason_has "git pull origin $STACK_BR" "[worker] the pull refusal names the stacked base"
sg worker "PLANWRIGHT_WORKER_SESSION_RECORD=$SANDBOX/rec/ok.record /bin/bash $SYNC --base $STACK_BR"
expect deny "[worker] naming another session record for the sync script is refused"
sg worker "export PLANWRIGHT_WORKER_SESSION_RECORD=$SANDBOX/rec/ok.record"
expect deny "[worker] exporting another session record is refused"
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

echo "# guard: a record naming both a stacked base and a spec branch keeps each rule to its own"
SPEC_BR=planwright/demo/amendment-1
gitq -C "$SEED" switch -c "$SPEC_BR" main
gitq -C "$SEED" commit --allow-empty -m "pushed on $SPEC_BR"
gitq -C "$SEED" push origin "$SPEC_BR"
gitq -C "$SEED" switch main
gitq -C "$STACK" fetch origin
REC_BOTH="$SANDBOX/rec/both.record"
write_rec "$REC_BOTH" "origin/$STACK_BR"
printf 'spec_branch=%s\n' "$SPEC_BR" >>"$REC_BOTH"
sg worker "git merge --ff-only origin/$STACK_BR" "$REC_BOTH"
expect defer "[worker] both fields: a fast-forward of the stacked base defers"
sg worker "git merge --ff-only origin/$SPEC_BR" "$REC_BOTH"
expect defer "[worker] both fields: a fast-forward to the named spec branch defers"
sg worker "git merge origin/$OTHER_BR" "$REC_BOTH"
expect deny "[worker] both fields: another feature branch is refused"
SPECWT="$SANDBOX/stack-spec"
gitq -C "$STACK" worktree add -b "$SPEC_BR" "$SPECWT" "origin/$SPEC_BR"
PLANWRIGHT_WORKER_SESSION_RECORD=$REC_BOTH pg worker 'git merge origin/main' "$SPECWT" "$SPECWT"
expect defer "[worker] both fields, in the spec branch's worktree: the PR base merges"
PLANWRIGHT_WORKER_SESSION_RECORD=$REC_BOTH pg worker "git merge origin/$STACK_BR" "$SPECWT" "$SPECWT"
expect deny "[worker] both fields, in the spec branch's worktree: the unit's stacked base is refused"

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
wr "$WT" --base "$STACK_BR" --spec-branch planwright/demo/amendment-1
if [ "$RC" = 0 ] && [ "$(field stack_base)" = "origin/$STACK_BR" ] && [ "$(field spec_branch)" = planwright/demo/amendment-1 ]; then
  pass "[writer] --base beside --spec-branch records both fields"
else
  fail "[writer] --base with --spec-branch: rc=$RC stack_base='$(field stack_base)' spec_branch='$(field spec_branch)'"
fi
wr "$WT" --base main
if [ "$RC" = 0 ] && ! grep -q '^stack_base=' "$REC"; then
  pass "[writer] --base naming the default base records no stack_base"
else
  fail "[writer] --base main wrote stack_base='$(field stack_base)'"
fi
for bad in '-x' '../evil' 'a b' 'a..b' '' 'feat/' 'x.lock' HEAD @ "feat/$(printf '%0260d' 0)"; do
  wr "$WT" --base "$bad"
  if [ "$RC" = 2 ]; then
    pass "[writer] --base '${bad:0:16}' is a usage error"
  else
    fail "[writer] --base '${bad:0:16}' exited $RC"
  fi
done
cat >"$SANDBOX/bin-gh-pr" <<EOF
#!/bin/sh
[ "\$1 \$2" = "pr view" ] || exit 1
printf "gh %s\n" "\$*" >>"$SANDBOX/ghpr.log"
printf '%s %s %s\n' "\${STUB_PR_STATE:-OPEN}" "\${STUB_PR_CROSS:-false}" "\${STUB_PR_BASE:-}"
EOF
mkdir -p "$SANDBOX/ghpr"
cp "$SANDBOX/bin-gh-pr" "$SANDBOX/ghpr/gh"
chmod +x "$SANDBOX/ghpr/gh"
REC=$(PLANWRIGHT_FLEET_STATE_DIR=$FLEET PLANWRIGHT_ADOPTER_OVERLAY=$SANDBOX/adopter STUB_PR_BASE=$STACK_BR \
  PATH="$SANDBOX/ghpr:$PATH" /bin/sh "$WRITER" write "$WT" --base-from-pr 2>/dev/null)
if [ "$(field stack_base)" = "origin/$STACK_BR" ]; then
  pass "[writer] a PR whose baseRefName is a feature branch is read once into stack_base"
else
  fail "[writer] the PR's base was not read: '$(field stack_base)'"
fi
REC=$(PLANWRIGHT_FLEET_STATE_DIR=$FLEET PLANWRIGHT_ADOPTER_OVERLAY=$SANDBOX/adopter STUB_PR_BASE='bad base!' \
  PATH="$SANDBOX/ghpr:$PATH" /bin/sh "$WRITER" write "$WT" --base-from-pr 2>/dev/null)
if ! grep -q '^stack_base=' "$REC"; then
  pass "[writer] a PR base outside the branch grammar is dropped"
else
  fail "[writer] a malformed PR base reached the record: '$(field stack_base)'"
fi
if grep -q 'isCrossRepository' "$SANDBOX/ghpr.log" && grep -q 'state' "$SANDBOX/ghpr.log"; then
  pass "[writer] the PR read asks for the PR's state and whether it comes from a fork"
else
  fail "[writer] the PR read does not ask for state and fork: $(cat "$SANDBOX/ghpr.log")"
fi
for odd in "STUB_PR_STATE=MERGED" "STUB_PR_STATE=CLOSED" "STUB_PR_CROSS=true"; do
  REC=$(env "$odd" PLANWRIGHT_FLEET_STATE_DIR="$FLEET" PLANWRIGHT_ADOPTER_OVERLAY="$SANDBOX/adopter" STUB_PR_BASE="$STACK_BR" \
    PATH="$SANDBOX/ghpr:$PATH" /bin/sh "$WRITER" write "$WT" --base-from-pr 2>"$SANDBOX/wr.err")
  if ! grep -q '^stack_base=' "$REC" && grep -q 'no stacked base' "$SANDBOX/wr.err"; then
    pass "[writer] a PR read with $odd records no stacked base, and says so"
  else
    fail "[writer] $odd: stack_base='$(field stack_base)' err='$(cat "$SANDBOX/wr.err")'"
  fi
done
for both in "--base $STACK_BR --base-from-pr" "--base-from-pr --base $STACK_BR"; do
  # shellcheck disable=SC2086 # the two flags, split on purpose
  wr "$WT" $both
  if [ "$RC" = 2 ]; then
    pass "[writer] --base and --base-from-pr together are a usage error: $both"
  else
    fail "[writer] '$both' exited $RC"
  fi
done
: >"$SANDBOX/ghpr.log"
REC=$(PLANWRIGHT_FLEET_STATE_DIR=$FLEET PLANWRIGHT_ADOPTER_OVERLAY=$SANDBOX/adopter STUB_PR_BASE=$STACK_BR \
  PATH="$SANDBOX/ghpr:$PATH" /bin/sh "$WRITER" write "$WT" 2>/dev/null)
if [ -f "$REC" ] && [ ! -s "$SANDBOX/ghpr.log" ] && ! grep -q '^stack_base=' "$REC"; then
  pass "[writer] without --base-from-pr the writer makes no gh call (decision paths stay offline)"
else
  fail "[writer] a plain write called gh or recorded a base: $(cat "$SANDBOX/ghpr.log")"
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
ln -s "$SY2" "$SANDBOX/sy2-alias"
run_sync "$SY2" "$SANDBOX/sy2-alias/inside.record" --base "$STACK_BR"
if [ "$RC" = 2 ] && grep -q "launch record" "$SANDBOX/sync.err"; then
  pass "[sync] --base with a record reached through a symlinked path into the worktree is refused"
else
  fail "[sync] --base with an aliased in-worktree record: rc=$RC"
fi
run_sync "$SY2" inside.record --base "$STACK_BR"
if [ "$RC" = 2 ] && grep -q "launch record" "$SANDBOX/sync.err"; then
  pass "[sync] --base with a relative record path is refused"
else
  fail "[sync] --base with a relative record path: rc=$RC"
fi
{
  printf 'stack_base=\n'
  cat "$SANDBOX/rec/sy2.record"
} >"$SANDBOX/rec/sy2dup.record"
run_sync "$SY2" "$SANDBOX/rec/sy2dup.record" --base "$STACK_BR"
if [ "$RC" = 2 ] && grep -q "launch record" "$SANDBOX/sync.err"; then
  pass "[sync] --base with a record repeating stack_base is refused"
else
  fail "[sync] --base with a duplicated stack_base: rc=$RC"
fi
{
  cat "$SANDBOX/rec/sy2.record"
  printf 'pad=%04097d\n' 0
} >"$SANDBOX/rec/sy2big.record"
run_sync "$SY2" "$SANDBOX/rec/sy2big.record" --base "$STACK_BR"
if [ "$RC" = 2 ] && grep -q "launch record" "$SANDBOX/sync.err" && [ "$(git -C "$SY2" rev-parse HEAD)" = "$before" ]; then
  pass "[sync] --base with a record past 4096 bytes is refused"
else
  fail "[sync] --base with an oversized record: rc=$RC"
fi
write_rec "$SANDBOX/rec/sy2evil.record" "origin/a..b"
run_sync "$SY2" "$SANDBOX/rec/sy2evil.record" --base "a..b"
if [ "$RC" = 2 ] && grep -q "launch record" "$SANDBOX/sync.err"; then
  pass "[sync] --base outside the branch grammar is refused even when the record names it"
else
  fail "[sync] --base a..b: rc=$RC"
fi
long_br=feat/$(printf '%0260d' 0)
for bad in HEAD @ "$long_br"; do
  write_rec "$SANDBOX/rec/sy2bad.record" "origin/$bad"
  sed -i.bak "s|^worktree_root=.*|worktree_root=$SY2|" "$SANDBOX/rec/sy2bad.record" && rm -f "$SANDBOX/rec/sy2bad.record.bak"
  run_sync "$SY2" "$SANDBOX/rec/sy2bad.record" --base "$bad"
  if [ "$RC" = 2 ] && grep -q "launch record" "$SANDBOX/sync.err" && [ "$(git -C "$SY2" rev-parse HEAD)" = "$before" ]; then
    pass "[sync] --base '${bad:0:16}' is outside the guard's branch grammar and refused even when the record names it"
  else
    fail "[sync] --base '${bad:0:16}': rc=$RC"
  fi
done
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
if [ "$RC" = 0 ] && git -C "$SY2" merge-base --is-ancestor "$(git -C "$ORIGIN" rev-parse refs/heads/main)" HEAD; then
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

printf '%s\n' 'converge_sync_main: always' 'worker_base_merge: allow' 'worker_merge_conflict_policy: resolve' >"$SYNC_CFG"
SY4="$SANDBOX/sy4"
sync_clone "$SY4"
printf 'unit\n' >"$SY4/clash.txt"
gitq -C "$SY4" add clash.txt
gitq -C "$SY4" commit -m "unit clash"
gitq -C "$SEED" switch "$STACK_BR"
printf 'base\n' >"$SEED/clash.txt"
gitq -C "$SEED" add clash.txt
gitq -C "$SEED" commit -m "base clash"
gitq -C "$SEED" push origin "$STACK_BR"
gitq -C "$SEED" switch main
write_rec "$SANDBOX/rec/sy4.record" "origin/$STACK_BR"
sed -i.bak "s|^worktree_root=.*|worktree_root=$SY4|" "$SANDBOX/rec/sy4.record" && rm -f "$SANDBOX/rec/sy4.record.bak"
run_sync "$SY4" "$SANDBOX/rec/sy4.record" --base "$STACK_BR"
case $OUT in
  *"converge-sync-main.sh --base $STACK_BR --commit-resolution"*)
    pass "[sync] a stacked resolve conflict tells the worker to commit with the same --base"
    ;;
  *) fail "[sync] the resolve instruction omits --base: rc=$RC out='$OUT'" ;;
esac
printf 'resolved\n' >"$SY4/clash.txt"
gitq -C "$SY4" add clash.txt
want=$(git -C "$ORIGIN" rev-parse "refs/heads/$STACK_BR")
run_sync "$SY4" "$SANDBOX/rec/sy4.record" --base "$STACK_BR" --commit-resolution demo/12
if [ "$RC" = 0 ] && [ "$(git -C "$SY4" rev-parse HEAD^2)" = "$want" ] \
  && git -C "$SY4" log -1 --format=%s | grep -qF "Merge origin/$STACK_BR, resolving conflicts"; then
  pass "[sync] --base with --commit-resolution commits the stacked merge as a merge of that base"
else
  fail "[sync] stacked --commit-resolution: rc=$RC out='$OUT' err='$(cat "$SANDBOX/sync.err")'"
fi

printf '%s\n' 'converge_sync_main: always' 'worker_base_merge: allow' >"$SYNC_CFG"
gitq -C "$SEED" switch -c shadow main
printf 'shadow\n' >"$SEED/shadow.txt"
gitq -C "$SEED" add shadow.txt
gitq -C "$SEED" commit -m "a tag named like the stacked base"
gitq -C "$SEED" tag "$STACK_BR"
gitq -C "$SEED" push origin "refs/tags/$STACK_BR"
shadow=$(git -C "$SEED" rev-parse HEAD)
gitq -C "$SEED" switch main
SY5="$SANDBOX/sy5"
sync_clone "$SY5"
write_rec "$SANDBOX/rec/sy5.record" "origin/$STACK_BR"
sed -i.bak "s|^worktree_root=.*|worktree_root=$SY5|" "$SANDBOX/rec/sy5.record" && rm -f "$SANDBOX/rec/sy5.record.bak"
adv_base "$STACK_BR"
want=$(git -C "$ORIGIN" rev-parse "refs/heads/$STACK_BR")
run_sync "$SY5" "$SANDBOX/rec/sy5.record" --base "$STACK_BR"
if [ "$RC" = 0 ] && git -C "$SY5" merge-base --is-ancestor "$want" HEAD \
  && ! git -C "$SY5" merge-base --is-ancestor "$shadow" HEAD; then
  pass "[sync] --base fetches the base branch, never a tag of the same name"
else
  fail "[sync] a tag named like the base: rc=$RC err='$(cat "$SANDBOX/sync.err")'"
fi

finish
