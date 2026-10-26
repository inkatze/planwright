#!/bin/bash
# Tests for scripts/worker-session-record.sh, the launcher-side half of the
# worker's self-approval surface: the policy knob resolved through the overlay
# layers last-value-wins with its fail-closed fallback (REQ-F1.1), and the
# record the launchers write outside the worktree and hand the command guard
# (REQ-G1.8), which keeps the guard's verdicts fixed until a relaunch.
set -u
unset CDPATH
LC_ALL=C
export LC_ALL
for v in $(compgen -e); do
  case $v in
    GIT_* | PLANWRIGHT_* | CLAUDE_*) unset "$v" ;;
  esac
done

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
WRITER="$REPO_ROOT/scripts/worker-session-record.sh"
GUARD="$REPO_ROOT/scripts/worker-command-guard.sh"
ENVWRAP="$REPO_ROOT/scripts/fleet-dispatch-env.sh"

failures=0
passes=0
pass() {
  echo "ok: $1"
  passes=$((passes + 1))
}
fail() {
  echo "FAIL: $1" >&2
  failures=$((failures + 1))
}

command -v jq >/dev/null 2>&1 || {
  echo "FAIL: jq is required to run this suite" >&2
  exit 1
}

T=$(mktemp -d) || exit 1
trap 'rm -rf "$T"' EXIT
T=$(cd "$T" && pwd -P)
export HOME="$T/home" GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export PLANWRIGHT_FLEET_STATE_DIR="$T/fleet"
export PLANWRIGHT_ADOPTER_OVERLAY="$T/adopter"
mkdir -p "$HOME" "$T/adopter"

MAIN=$T/main
WT=$MAIN/.claude/worktrees/demo-task-1
UNIT=planwright/demo/task-1
git init -q "$T/origin.git" --bare
git init -q "$MAIN"
git -C "$MAIN" symbolic-ref HEAD refs/heads/main
git -C "$MAIN" -c user.name=t -c user.email=t@example.invalid -c commit.gpgsign=false commit -q --allow-empty -m init
git -C "$MAIN" remote add origin "$T/origin.git"
git -C "$MAIN" push -q origin main
git -C "$MAIN" fetch -q origin
git -C "$MAIN" remote set-head origin main
git -C "$MAIN" branch -q other
git -C "$MAIN" worktree add -q -b "$UNIT" "$WT" main

# write <dir>: run the writer, leaving its stdout in REC and its status in RC.
write() {
  REC=$(/bin/sh "$WRITER" write "$1" 2>"$T/err")
  RC=$?
}
field() { grep "^$1=" "$REC" | head -n 1 | cut -d= -f2-; }
set_layer() {
  # set_layer <repo-tracked|machine-local> <line or empty>
  local f
  case $1 in
    repo-tracked) f=$MAIN/.claude/planwright.yml ;;
    machine-local) f=$MAIN/.claude/planwright.local.yml ;;
  esac
  mkdir -p "$MAIN/.claude"
  if [ -n "$2" ]; then printf '%s\n' "$2" >"$f"; else rm -f "$f"; fi
}

echo "### REQ-F1.1 — the knob, its layers, and its fallback"
write "$WT"
if [ "$RC" -eq 0 ] && [ -f "$REC" ] && [ "$(field policy)" = "" ] && grep -qx 'policy=' "$REC"; then
  pass "F1.1: no overlay resolves to the empty list"
else
  fail "F1.1: default policy (rc=$RC, $(cat "$T/err"))"
fi
set_layer repo-tracked 'worker_self_approval: own-branch'
write "$WT"
if [ "$(field policy)" = own-branch ]; then
  pass "F1.1: a repo-tracked overlay is honoured"
else
  fail "F1.1: repo-tracked own-branch read as '$(field policy)'"
fi
set_layer repo-tracked 'worker_self_approval: own-branch scratch'
set_layer machine-local 'worker_self_approval:'
write "$WT"
if [ "$(field policy)" = "" ]; then
  pass "F1.1: a machine-local empty list narrows a repo-tracked list (last value wins)"
else
  fail "F1.1: last-value-wins narrowing read '$(field policy)'"
fi
set_layer machine-local ''
printf 'worker_self_approval: scratch\n' >"$T/adopter/planwright.yml"
write "$WT"
if [ "$(field policy)" = "own-branch scratch" ]; then
  pass "F1.1: the repo-tracked layer wins over the adopter layer, no union"
else
  fail "F1.1: layer precedence read '$(field policy)'"
fi
rm -f "$T/adopter/planwright.yml"
set_layer repo-tracked 'worker_self_approval: own-branch everything'
write "$WT"
if [ "$RC" -eq 0 ] && [ "$(field policy)" = "" ]; then
  pass "F1.1: an unknown member resolves the whole value to the empty list"
else
  fail "F1.1: unknown member read '$(field policy)'"
fi
set_layer repo-tracked 'worker_self_approval: [own-branch]'
write "$WT"
if [ "$RC" -eq 0 ] && [ "$(field policy)" = "" ]; then
  pass "F1.1: a malformed value resolves to the empty list"
else
  fail "F1.1: malformed value read '$(field policy)'"
fi
set_layer repo-tracked '  nested: map'
write "$WT"
if [ "$RC" -eq 0 ] && [ "$(field policy)" = "" ]; then
  pass "F1.1: a repo-tracked read failure resolves to the empty list"
else
  fail "F1.1: unreadable layer read '$(field policy)' (rc=$RC)"
fi
mkdir -p "$WT/.claude"
printf 'worker_self_approval: own-branch\n' >"$WT/.claude/planwright.local.yml"
set_layer repo-tracked ''
write "$WT"
if [ "$(field policy)" = "" ]; then
  pass "F1.1: an overlay inside the worker's own worktree governs nothing"
else
  fail "F1.1: the worktree's overlay was read: '$(field policy)'"
fi
rm -rf "$WT/.claude"

echo "### REQ-G1.8 — the record, outside the worktree"
set_layer repo-tracked 'worker_self_approval: own-branch'
write "$WT"
case $REC in
  "$PLANWRIGHT_FLEET_STATE_DIR"/session-records/*.record) pass "G1.8: the record lies under the fleet home" ;;
  *) fail "G1.8: record path $REC" ;;
esac
if [ "$(field unit_branch)" = "$UNIT" ] && [ "$(field worktree_root)" = "$WT" ] \
  && [ "$(field pr_base)" = origin/main ] && [ "$(field worker_base_merge)" = allow ]; then
  pass "G1.8: the record names the unit branch, worktree root, PR base, and base-merge gate"
else
  fail "G1.8: record fields: $(tr '\n' ' ' <"$REC")"
fi
mode=$(stat -c %a "$REC" 2>/dev/null || stat -f %Lp "$REC")
if [ "$mode" = 600 ]; then
  pass "G1.8: the record is owner-only"
else
  fail "G1.8: record mode $mode"
fi
printf 'worker_base_merge: deny\n' >>"$MAIN/.claude/planwright.yml"
write "$WT"
if [ "$(field worker_base_merge)" = deny ]; then
  pass "G1.8: worker_base_merge is resolved into the record"
else
  fail "G1.8: worker_base_merge read '$(field worker_base_merge)'"
fi
set_layer repo-tracked 'worker_self_approval: own-branch'
write "$WT/sub-not-there" 2>/dev/null
if [ "$RC" -ne 0 ]; then
  pass "G1.8: a missing worktree writes no record"
else
  fail "G1.8: a missing worktree wrote $REC"
fi
mkdir -p "$WT/sub"
write "$WT/sub"
if [ "$RC" -eq 0 ] && [ "$(field worktree_root)" = "$WT" ]; then
  pass "G1.8: a subdirectory resolves to its worktree's top level"
else
  fail "G1.8: subdirectory worktree_root '$(field worktree_root)'"
fi
write "$MAIN"
if [ "$RC" -eq 0 ] && [ -z "$(field unit_branch)" ] && ! grep -q '^unit_branch=' "$REC"; then
  pass "G1.8: a checkout on main records no unit branch"
else
  fail "G1.8: main recorded unit_branch '$(field unit_branch)'"
fi
PLANWRIGHT_FLEET_STATE_DIR="$WT/fleet" /bin/sh "$WRITER" write "$WT" >/dev/null 2>&1
rc=$?
if [ "$rc" -ne 0 ] && [ -z "$(find "$WT/fleet" -name '*.record' 2>/dev/null)" ]; then
  pass "G1.8: a fleet home inside the worktree is refused"
else
  fail "G1.8: a record was written inside the worktree (rc=$rc)"
fi
rm -rf "$WT/fleet"

GIT_DIR="$T/origin.git" /bin/sh "$WRITER" write "$WT" >"$T/out" 2>/dev/null
REC=$(cat "$T/out")
if [ "$(field worktree_root)" = "$WT" ] && [ "$(field unit_branch)" = "$UNIT" ]; then
  pass "G1.8: an inherited GIT_DIR does not redirect the record"
else
  fail "G1.8: GIT_DIR redirected the record: $(tr '\n' ' ' <"$REC" 2>/dev/null)"
fi
id=0123456789abcdef0123456789abcdef
write "$WT"
shared=$REC
REC=$(/bin/sh "$WRITER" write "$WT" "$id" 2>/dev/null)
case $REC in
  "${shared%.record}-$id.record")
    pass "G1.8: a launch id names a record of that launch alone"
    ;;
  *) fail "G1.8: launch-id record path $REC" ;;
esac
if /bin/sh "$WRITER" write "$WT" NOT-HEX >/dev/null 2>&1; then
  fail "G1.8: a malformed launch id was accepted"
else
  pass "G1.8: a malformed launch id is refused"
fi

echo "### REQ-G1.2 — the scratch root"
wt_key=$(printf '%s' "$WT" | git hash-object --stdin)
root="$PLANWRIGHT_FLEET_STATE_DIR/scratch/$wt_key"
REC=$(/bin/sh "$WRITER" write "$WT" --scratch 2>"$T/err")
RC=$?
mode=$(stat -c %a "$root" 2>/dev/null || stat -f %Lp "$root" 2>/dev/null)
if [ "$RC" -eq 0 ] && [ "$(field scratch_root)" = "$root" ] && [ -d "$root" ] && [ -O "$root" ] \
  && [ "$mode" = 700 ]; then
  pass "G1.2: --scratch creates the worktree's owner-only root under the fleet home and records it"
else
  fail "G1.2: --scratch (rc=$RC, mode=$mode, $(tr '\n' ' ' <"$REC" 2>/dev/null) $(cat "$T/err"))"
fi
: >"$root/kept"
REC=$(/bin/sh "$WRITER" write "$WT" "$id" --scratch 2>/dev/null)
if [ "$(field scratch_root)" = "$root" ] && [ -f "$root/kept" ]; then
  pass "G1.2: another launch of the worktree keeps the same root and its contents"
else
  fail "G1.2: the relaunch did not keep the root ('$(field scratch_root)')"
fi
REC=$(/bin/sh "$WRITER" write "$WT" 2>/dev/null)
if [ -n "$REC" ] && ! grep -q '^scratch_root=' "$REC"; then
  pass "G1.2: no scratch option records no scratch root"
else
  fail "G1.2: a scratch root was recorded unasked"
fi
if /bin/sh "$WRITER" write "$WT" --scratch --scratch >/dev/null 2>&1; then
  fail "G1.2: a repeated --scratch was accepted"
else
  pass "G1.2: a repeated --scratch is a usage error"
fi
mkdir -p "$T/elsewhere"
mv "$root" "$root.moved"
ln -s "$T/elsewhere" "$root"
REC=$(/bin/sh "$WRITER" write "$WT" --scratch 2>"$T/err")
RC=$?
if [ "$RC" -eq 0 ] && [ -n "$REC" ] && ! grep -q '^scratch_root=' "$REC" && [ -s "$T/err" ]; then
  pass "G1.2: a root that is a symlink is omitted with a warning, the record still written"
else
  fail "G1.2: a symlinked root (rc=$RC, $(tr '\n' ' ' <"$REC" 2>/dev/null))"
fi
rm -f "$root"
mv "$root.moved" "$root"
set_layer repo-tracked 'worker_self_approval: scratch'
REC=$(/bin/sh "$WRITER" write "$WT" --scratch 2>/dev/null)
out=$(jq -cn --arg c 'touch $TMPDIR/x && mktemp -d' --arg w "$WT" '{tool_name:"Bash",tool_input:{command:$c},cwd:$w}' \
  | (cd "$WT" && TMPDIR=$root PLANWRIGHT_WORKER_SESSION_RECORD=$REC /bin/bash "$GUARD" 2>/dev/null))
if [ "$(printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null)" = allow ]; then
  pass "G1.2: the guard takes the launched record's scratch root"
else
  fail "G1.2: the guard did not approve a scratch write under the launched record"
fi
set_layer repo-tracked 'worker_self_approval: own-branch'

echo "### REQ-G1.8 — the guard's verdicts are fixed at launch"
write "$WT"
decide() {
  local out
  # Only an empty output from a clean exit is a defer: a guard that failed to
  # run, or printed anything but an allow, is an error, never a pass.
  out=$(jq -cn --arg c "$1" --arg w "$WT" '{tool_name:"Bash",tool_input:{command:$c},cwd:$w}' \
    | (cd "$WT" && PLANWRIGHT_WORKER_SESSION_RECORD=$REC /bin/bash "$GUARD" 2>/dev/null)) || {
    echo error
    return
  }
  if [ -z "$out" ]; then
    echo defer
  elif [ "$(printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null)" = allow ]; then
    echo allow
  else
    echo error
  fi
}
: >"$WT/f"
if [ "$(decide 'touch f')" = allow ]; then
  pass "G1.8: own-branch from the record approves a worktree write"
else
  fail "G1.8: own-branch write deferred under the launched record"
fi
set_layer repo-tracked 'worker_self_approval:'
if [ "$(decide 'touch f')" = allow ]; then
  pass "G1.8: an overlay change after launch does not change the verdict"
else
  fail "G1.8: the guard read live config"
fi
write "$WT"
if [ "$(decide 'touch f')" = defer ]; then
  pass "G1.8: the relaunch's record carries the change"
else
  fail "G1.8: the rewritten record did not narrow the policy"
fi
set_layer repo-tracked 'worker_self_approval: own-branch'
write "$WT"
git -C "$WT" switch -q other
if [ "$(field unit_branch)" = "$UNIT" ] && [ "$(decide 'git add -A')" = defer ]; then
  pass "G1.8: after git switch other the record still names the unit branch, and no git act passes"
else
  fail "G1.8: git switch changed the unit identity"
fi
git -C "$WT" switch -q "$UNIT"

echo "### REQ-G1.8 — the tmux rung's wrapper exports the record"
out=$(/bin/sh "$ENVWRAP" --session-record "$REC" /bin/sh -c 'printf %s "$PLANWRIGHT_WORKER_SESSION_RECORD"' 2>&1)
if [ "$out" = "$REC" ]; then
  pass "G1.8: --session-record is exported as PLANWRIGHT_WORKER_SESSION_RECORD"
else
  fail "G1.8: wrapper exported '$out'"
fi
out=$(PLANWRIGHT_WORKER_SESSION_RECORD=/inherited /bin/sh "$ENVWRAP" --root "$REPO_ROOT" /bin/sh -c 'printf %s "${PLANWRIGHT_WORKER_SESSION_RECORD-unset}"' 2>&1)
if [ "$out" = unset ]; then
  pass "G1.8: an inherited record path never reaches a launched worker"
else
  fail "G1.8: inherited record leaked: '$out'"
fi
/bin/sh "$ENVWRAP" --session-record relative.record true 2>/dev/null
if [ $? -eq 2 ]; then
  pass "G1.8: a relative record path is refused"
else
  fail "G1.8: a relative record path was accepted"
fi
/bin/sh "$ENVWRAP" --session-record "$T/none.record" true 2>/dev/null
if [ $? -eq 2 ]; then
  pass "G1.8: a missing record file is refused"
else
  fail "G1.8: a missing record was accepted"
fi
out=$(TMPDIR=/inherited /bin/sh "$ENVWRAP" --tmpdir "$root" /bin/sh -c 'printf %s "$TMPDIR"' 2>&1)
if [ "$out" = "$root" ]; then
  pass "G1.2: --tmpdir is exported as the worker's TMPDIR"
else
  fail "G1.2: wrapper exported TMPDIR '$out'"
fi
/bin/sh "$ENVWRAP" --tmpdir relative/tmp true 2>/dev/null
if [ $? -eq 2 ]; then
  pass "G1.2: a relative --tmpdir is refused"
else
  fail "G1.2: a relative --tmpdir was accepted"
fi
/bin/sh "$ENVWRAP" --tmpdir "$T/none-dir" true 2>/dev/null
if [ $? -eq 2 ]; then
  pass "G1.2: a missing --tmpdir directory is refused"
else
  fail "G1.2: a missing --tmpdir directory was accepted"
fi

echo
echo "worker-session-record: $passes passed, $failures failed"
[ "$failures" -eq 0 ]
