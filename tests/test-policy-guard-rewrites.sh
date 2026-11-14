#!/bin/bash
# Adversarial suite for scripts/policy-guard.sh: never-pushed rewrites, pushes and the protected set, a cd that may not run, the fail-closed reads, and the policy read location.
#
# Split from tests/test-policy-guard.sh to keep each file under the per-file test
# time budget; the harness and the clones are shared through tests/lib.
#
# Runs standalone under /bin/bash (the bash 3.2 floor).
# shellcheck disable=SC2016 # the unexpanded $ forms are the inputs under test
unset CDPATH
# shellcheck source=tests/lib/policy-guard-harness.sh
. "$(cd "$(dirname "$0")" && pwd)/lib/policy-guard-harness.sh"
# shellcheck source=tests/lib/policy-guard-clones.sh
. "$(cd "$(dirname "$0")" && pwd)/lib/policy-guard-clones.sh"
# shellcheck source=tests/lib/hermetic-env.sh
. "$REPO_ROOT/tests/lib/hermetic-env.sh"

# --- history rewrites (REQ-F1.1) ---------------------------------------------

echo "# never-pushed rewrites"
set_knobs 'unpushed_rewrite: allow'
for cmd in 'git commit --amend --no-edit' 'git commit -m wip --amend' 'git commit --am --no-edit' \
  'git commit --squash=HEAD~1' 'git commit --squash HEAD~1' 'git commit --fixup=amend:HEAD~1' \
  'git commit --fixu HEAD~2' 'git rebase -i HEAD~3' 'git rebase HEAD~2'; do
  pg worker "$cmd"
  expect defer "[worker] allow: $cmd on unpushed commits defers"
done
pg worker 'git commit --amend --no-edit'
reads 'unpushed_rewrite protected_branches' "[worker] a rewrite reads unpushed_rewrite and the protected set"
for cmd in 'git rebase origin/main' 'git rebase -i HEAD~4' 'git commit --fixup=HEAD~3' 'git rebase --root' \
  'git pull --rebase origin main' 'git rebase -i HEAD~3 --update-refs'; do
  pg worker "$cmd"
  expect deny "[worker] allow: $cmd reaches a pushed commit (or another branch) and denies"
done
pg worker 'git rebase origin/main'
reason_has 'remote-tracking ref already contains' "the pushed-commit deny says why"
for cmd in "git rebase -i HEAD~3 --exec='git push --force origin main'" \
  "git rebase -i HEAD~3 --exec 'make test'" "git rebase -i HEAD~3 --ex='make test'" \
  "git rebase -i HEAD~3 -x 'make test'" "git rebase -ix 'make test' HEAD~3" \
  "git rebase -i HEAD~3 -x'make test'" \
  'git rebase --no-update-refs --update-refs -i HEAD~3' 'git rebase --no-update-refs --upd -i HEAD~3'; do
  pg worker "$cmd"
  expect deny "[worker] allow: $cmd denies"
done
pg worker "git rebase -i HEAD~3 -x 'make test'"
reason_has 'exec' "the rebase exec deny names the option"
pg worker 'git rebase --update-refs --no-update-refs -i HEAD~3'
expect defer "[worker] allow: the last of --update-refs/--no-update-refs wins, so a trailing --no-update-refs defers"
pg worker 'git commit --amend --no-edit' "$PUSHED" "$PUSHED"
expect deny "[worker] allow: an amend of a commit a remote-tracking ref contains denies"
pg worker 'git commit --amend --no-edit' "$NOUP" "$NOUP"
expect deny "[worker] allow: an amend on a branch with no upstream denies"
reason_has 'no upstream' "the no-upstream deny says why"
pg worker 'git commit --amend --no-edit' "$BROKEN" "$BROKEN"
expect deny "[worker] allow: an amend whose upstream refresh fails denies"
reason_has 'refreshing the upstream' "the failed-refresh deny says why"
pg worker 'git commit --amend --no-edit' "$SPEC" "$SPEC"
expect deny "[worker] allow: an amend of an unpushed commit on a spec branch denies"
pg worker 'git commit --amend --no-edit' "$OTHER"
expect deny "[worker] allow: an amend in another unit's worktree denies"
# A commit pushed from another clone, read as unpushed through a stale
# tracking ref: the refresh must see it.
STALE="$SANDBOX/stale"
clone_on "$STALE" planwright/demo/task-1 1
gitq -C "$PUSHED" pull --ff-only "$STALE" planwright/demo/task-1
gitq -C "$PUSHED" push origin planwright/demo/task-1
if [ "$(git -C "$STALE" rev-list --count HEAD --not --remotes)" = 1 ]; then
  pg worker 'git commit --amend --no-edit' "$STALE" "$STALE"
  expect deny "[worker] allow: a commit another clone pushed is seen after the refresh and denies"
else
  fail "fixture: the stale clone does not read its commit as unpushed before the refresh; the stale-ref case would be vacuous"
fi
set_knobs 'unpushed_rewrite: allow' 'worker_base_merge: allow'
gitq -C "$UNIT" config pull.rebase true
pg worker 'git pull origin main'
expect deny "[worker] under pull.rebase=true a plain git pull of the base is a rebase over pushed commits, and denies"
pg worker 'git pull'
expect defer "[worker] under pull.rebase=true a bare git pull rebases only the unpushed commits onto the upstream, and defers"
pg worker 'git pull --no-rebase origin main'
expect defer "[worker] --no-rebase overrides pull.rebase, so the base merge defers"
gitq -C "$UNIT" config --unset pull.rebase
gitq -C "$UNIT" config rebase.updateRefs true
pg worker 'git rebase -i HEAD~3'
expect deny "[worker] rebase.updateRefs makes a rebase move other branches, and denies"
pg worker 'git rebase -i --no-update-refs HEAD~3'
expect defer "[worker] --no-update-refs overrides rebase.updateRefs"
gitq -C "$UNIT" config --unset rebase.updateRefs
set_knobs 'unpushed_rewrite: deny'
for cmd in 'git commit --amend --no-edit' 'git rebase -i HEAD~3' 'git commit --fixup=HEAD~1'; do
  pg worker "$cmd"
  expect deny "[worker] deny: $cmd denies"
done
reason_has 'unpushed_rewrite is deny' "[worker] the rewrite deny names the knob"
set_knobs 'unpushed_rewrite: allow'
for cmd in 'git commit --amend --no-edit' 'git commit --am""end --no-edit' 'git rebase -i HEAD~3' 'git re""base origin/main' \
  'git commit --squash=HEAD~1' 'git commit --fix=HEAD~1'; do
  pg tower "$cmd"
  expect deny "[tower] $cmd denies under allow"
  reads none "[tower] $cmd reads no knob"
done

# --- pushes and the protected set (REQ-F1.5) ---------------------------------

echo "# pushes and the protected set"
set_knobs 'protected_branches:'
for tier in worker tower; do
  for cmd in 'git push origin main' 'git push origin HEAD:refs/heads/main' 'git push origin HEAD:heads/master' \
    'git push origin planwright/demo/spec' 'git push -u origin Main' 'git push origin --delete main' 'git push origin :main'; do
    pg "$tier" "$cmd"
    expect deny "[$tier] $cmd denies (protected)"
  done
  pg "$tier" 'git push origin main'
  reads protected_branches "[$tier] a push reads only the protected set"
  for cmd in 'git push --force origin feature' 'git push -fu origin feature' 'git push origin +feature' \
    'git push --force-with-lease=feature origin feature' 'git push --mirr origin' 'git push origin --al' \
    'git push --b origin' 'git push origin :' "git push origin 'refs/heads/*:refs/heads/*'"; do
    pg "$tier" "$cmd"
    expect deny "[$tier] $cmd denies (force or bulk)"
    reads none "[$tier] $cmd reads no knob"
  done
  for cmd in 'git push origin planwright/demo/task-1' 'git push -u origin HEAD' 'git push origin feature/c++' \
    'git push origin planwright/demo/spec-notes' 'git push --tags origin' 'git push origin v1.0:refs/tags/v1.0'; do
    pg "$tier" "$cmd"
    expect defer "[$tier] $cmd defers"
  done
done
pg worker 'git push origin $BRANCH'
expect deny "[worker] a push naming its target through a variable denies"
set_knobs 'protected_branches: release/*'
pg worker 'git push origin release/1.0'
expect deny "[worker] an overlay glob in protected_branches protects its matches"
pg worker 'git push origin release/1.0/rc'
expect defer "[worker] an overlay glob's * does not span a /"
set_knobs 'protected_branches: feature-x'
pg worker 'git push origin main'
expect deny "[worker] an overlay naming only a feature branch leaves main protected"
set_knobs 'protected_branches: main,master'
pg worker 'git push origin feature-y'
expect deny "[worker] a malformed protected_branches denies the push"
set_knobs 'protected_branches:'
pg worker "git push origin 'feat$(printf '\033')x'"
expect deny "[worker] a control sequence in a branch name is refused"
case $OUT in
  *"$(printf '\033')"*) fail "the deny reason carries a raw control byte" ;;
  *) pass "the deny reason is stripped of control bytes" ;;
esac

# --- a cd that may not run --------------------------------------------------

echo "# a cd is followed only when it runs"
set_knobs 'protected_branches:' 'unpushed_rewrite: allow' 'worker_base_merge: allow' 'ready_flip_policy: unit-owner'
# Each pair is <cwd>|<command>: the guard cannot tell that the shell runs the
# cd, in this shell, before the last act; where it skips the cd or runs it in
# a subshell, the act runs in the directory before it, a main checkout.
for spec in "$UNIT|cd $MAIN; false && cd $UNIT; git push" \
  "$UNIT|cd $MAIN; false && cd $UNIT; git commit --amend --no-edit" \
  "$MAIN|true || cd $UNIT; git push" "$MAIN|true || cd $UNIT; git commit --amend --no-edit" \
  "$MAIN|false && cd $UNIT
git push" "$MAIN|false && cd $UNIT
git merge origin/main" "$MAIN|false && cd $UNIT; gh pr ready 42" \
  "$MAIN|if false; then cd $UNIT; fi; git push" "$MAIN|if false; then cd $UNIT; fi; git commit --amend --no-edit" \
  "$MAIN|if true; then :; else cd $UNIT; fi; git push" "$MAIN|if false; then :; elif true; then cd $UNIT; fi; git push" \
  "$MAIN|if cd $UNIT; then git push; fi" "$MAIN|while false; do cd $UNIT; done; git push" \
  "$MAIN|until true; do cd $UNIT; done; git push" "$MAIN|for x in a; do cd $UNIT; done; git push" \
  "$MAIN|time if false; then cd $UNIT; fi; git push" "$MAIN|time -p while false; do cd $UNIT; done; git push" \
  "$MAIN|if false; then 'fi'; cd $UNIT; fi; git push" "$MAIN|\"then\" cd $UNIT; git push" \
  "$MAIN|function f if true; then cd $UNIT; fi
f; git push" "$MAIN|false && cd $UNIT || git push" \
  "$MAIN|false && cd $UNIT || >/dev/null && git push" "$MAIN|false && cd $UNIT && >/dev/null; git push" \
  "$MAIN|>/dev/null || cd $UNIT; git push" "$MAIN|<<EOF || cd $UNIT
x
EOF
git push" "$MAIN|x=1 then cd $UNIT; git push" "$MAIN|x=1 coproc cd $UNIT; git push" \
  "$MAIN|command time cd $UNIT; git push" "$MAIN|>/dev/null then cd $UNIT; git push" \
  "$MAIN|shopt -s execfail; exec cd $UNIT; git push" \
  "$MAIN|if false; then >/dev/null fi; cd $UNIT; fi; git push" \
  "$MAIN|if false; then noglob fi; cd $UNIT; fi; git push" \
  "$MAIN|a+b=1 cd $UNIT; git push" "$MAIN|\"x=1\" cd $UNIT; git push" "$MAIN|'x'=1 cd $UNIT; git push" \
  "$MAIN|cd $UNIT && true & git push" "$MAIN|coproc cd $UNIT; git push" \
  "$MAIN|! cd $UNIT && git push" "$MAIN|time ! cd $UNIT && git push" \
  "$MAIN|true | cd $UNIT && git push" "$MAIN|true |& cd $UNIT && git push" \
  "$MAIN|coproc foo if true; then cd $UNIT; fi; git push" \
  "$MAIN|x=1 noglob if false; then cd $UNIT; fi; git push" \
  "$MAIN|cd /nonexistent && cd $UNIT; git push" "$MAIN|cd - && cd $UNIT; git push" \
  "$MAIN|cd nosuch && cd $UNIT; git commit --amend --no-edit" \
  "$MAIN|cd /nonexistent && cd $UNIT && false || git push" \
  "$MAIN|repeat 0; do cd $UNIT; done; git push" "$MAIN|repeat 0
cd $UNIT
git push" "$MAIN|if false; then repeat 1 do :; done; cd $UNIT; fi; git push" \
  "$MAIN|cd $UNIT </nonexistent; git push" "$MAIN|cd $UNIT >/; git push" \
  "$MAIN|cd $UNIT 2>/dev/null && false || git push" \
  "$MAIN|noglob cd $UNIT; git push" "$MAIN|nocorrect cd $UNIT; git push"; do
  cmd=${spec#*|}
  pg worker "$cmd" "${spec%%|*}"
  expect deny "[worker] a cd the guard cannot place before the act is not followed: ${cmd//$'\n'/ \\n }"
  reason_has 'cannot follow' "[worker] the deny says the guard cannot follow the cd: ${cmd//$'\n'/ \\n }"
done
NOENTER="$SANDBOX/noenter"
mkdir -p "$NOENTER"
chmod 000 "$NOENTER"
noenter_denied=0
if hermetic_access_denied r "$NOENTER"; then noenter_denied=1; fi
if [ ! -x "$NOENTER" ] && [ "$noenter_denied" -eq 1 ]; then # root enters it anyway
  pg worker "cd $NOENTER && cd $UNIT; git push" "$MAIN"
  expect deny "[worker] a cd into a directory the shell cannot enter does not vouch for the cd after it"
else
  printf '%s\n' 'skip: a cd into a directory the shell cannot enter (this user enters any directory)'
fi
chmod 755 "$NOENTER"
pg worker "function f if true; then :; fi
cd $UNIT; git push" "$MAIN"
expect deny "[worker] an absolute cd after a function definition does not name the directory again"
# An alias lives in the repository the shell is in, which a cd the guard cannot
# follow hides.
gitq -C "$MAIN" config alias.p push
for cmd in "true && cd $MAIN; git p" "if true; then cd $MAIN; fi; git p"; do
  pg worker "$cmd"
  expect deny "[worker] an unknown git subcommand after a cd the guard cannot follow denies: $cmd"
  reason_has 'may be an alias' "[worker] the deny says the subcommand may be an alias: $cmd"
done
gitq -C "$MAIN" config --unset alias.p
# A cd its list is sure to run before the later act is still followed.
for cmd in "cd $UNIT; git push" "cd $UNIT
git push" "true && cd $UNIT && git push" "true || false && cd $UNIT && git push" \
  "git status; cd $UNIT && git commit --amend --no-edit" "cd $UNIT; false || git push" \
  "cd $UNIT && git status || true; git push" "cd ${UNIT%/*} && cd ${UNIT##*/}; git push" \
  "x=\"1\" cd $UNIT; git push" "cd $UNIT; >/dev/null; git push" "2>/dev/null; cd $UNIT && git push" \
  ">/tmp/x echo hi; cd $UNIT; git push" "exec 2>&1; cd $UNIT; git push" "a+=1 cd $UNIT; git push" \
  "false && cd /tmp; cd $UNIT && git push" \
  "true || echo x; cd $UNIT; git push" "if true; then echo x; fi; cd $UNIT && git push" \
  "for x in a; do echo x; done; cd $UNIT; git commit --amend --no-edit" \
  "cd $UNIT 2>/dev/null && git push"; do
  pg worker "$cmd" "$MAIN"
  expect defer "[worker] a cd sure to run is followed: ${cmd//$'\n'/ \\n }"
done
# A reserved word after a redirect only stops later cds being followed.
pg worker '>/dev/null time true; git push'
expect defer "[worker] a redirect before a reserved word leaves a command with no cd judged as before"
for cmd in 'repeat 1 true; git push' 'coproc true; git push'; do
  pg worker "$cmd"
  expect defer "[worker] $cmd stops only later cds being followed"
done
# zsh runs a command of redirects alone as cat, passing piped text on.
for cmd in "echo 'git push origin main' | >/dev/stdout | bash" "echo 'git push origin main' |& >/dev/stdout | bash" \
  "echo 'git push origin main' | x=1 >/dev/stdout | bash"; do
  pg worker "$cmd" "$MAIN"
  expect deny "[worker] text piped through a redirect-only command into a shell is screened: $cmd"
  reason_has 'pipes text' "[worker] the pipe screen refuses it: $cmd"
done
for cmd in "echo hi | >/dev/stdout | bash" "echo 'git push origin main' | x=1 | bash"; do
  pg worker "$cmd" "$MAIN"
  expect defer "[worker] a pipe that carries no reserved act into a shell is not refused: $cmd"
done

# --- fail-closed reads (REQ-G1.4) --------------------------------------------

echo "# fail-closed reads"
set_knobs 'ready_flip_policy: unit-owner' 'worker_base_merge: allow' 'unpushed_rewrite: allow'
for spec in 'ready_flip_policy|gh pr ready 42' 'worker_base_merge|git merge origin/main' \
  'unpushed_rewrite|git commit --amend --no-edit' 'protected_branches|git push origin feature'; do
  knob=${spec%%|*}
  STUB_FAIL_KNOB=$knob pg worker "${spec#*|}"
  expect deny "[worker] an unresolvable $knob denies ${spec#*|}"
  reason_has 'could not be' "the read-failure deny says the knob could not be read"
done
# A broken install beside the guard (the sanitizer missing) makes the
# protected-set reader exit 5, and the push is still refused as a read failure.
mv "$S/echo-safety.sh" "$S/echo-safety.sh.away"
pg worker 'git push origin feature'
expect deny "[worker] a missing echo-safety.sh beside the reader denies the push"
reason_has 'could not be read \(exit 5\)' "the broken-install deny names the read failure, not a bad branch name"
mv "$S/echo-safety.sh.away" "$S/echo-safety.sh"
set_knobs 'ready_flip_policy: agent'
pg worker 'gh pr ready 42'
expect deny "[worker] a malformed machine-local ready_flip_policy degrades to human and denies"
set_knobs 'ready_flip_policy: unit-owner'
STUB_SLEEP=3 PG_TIMEOUT=1 pg worker 'git push origin feature'
expect deny "[worker] a protected-set read past the wall-clock bound denies"
reason_has 'protected set did not finish' "the protected-set timeout deny names the timeout"
# With neither timeout nor gtimeout on PATH (stock macOS) the guard bounds its
# reads itself, so the same stall is still a timeout, not a missing tool.
NT_PATH=$(no_timeout_path "$SANDBOX/no-timeout")
PG_PATH=$NT_PATH STUB_SLEEP=3 PG_TIMEOUT=1 pg worker 'git push origin feature'
expect deny "[worker] without timeout or gtimeout, a protected-set read past its bound denies"
reason_has 'protected set did not finish' "without timeout or gtimeout, the deny still names the timeout"
PG_PATH=$NT_PATH pg worker 'git push origin main'
expect deny "[worker] without timeout or gtimeout, a push to main is still read and refused"
reason_has 'targets a protected branch' "without timeout or gtimeout, the bounded read's own answer decides"
# An upstream refresh that hangs is cut off at its bound and refuses.
SLOW="$SANDBOX/slow"
clone_on "$SLOW" planwright/demo/task-1 1
gitq -C "$SLOW" remote set-url origin 'ssh://example.invalid/x.git'
GIT_SSH_COMMAND='sleep 5; :' PLANWRIGHT_POLICY_GUARD_FETCH_TIMEOUT=1 pg worker 'git commit --amend --no-edit' "$SLOW" "$SLOW"
expect deny "[worker] an upstream refresh past its bound denies the rewrite"
reason_has 'exit 1(24|43)' "the refresh-timeout deny reports the timeout's exit"
STUB_SLEEP=3 PG_TIMEOUT=1 pg worker 'gh pr ready 42'
expect deny "[worker] a policy read past the wall-clock bound denies"
reason_has 'timeout' "the timeout deny names the timeout"
pg worker 'git merge origin/main' "$UNIT" "$SANDBOX/no-such-dir"
expect deny "[worker] a base merge with no readable project directory denies"
pg worker ''
expect defer "[worker] an empty command string defers"
pg_payload worker bash ''
expect deny "[worker] an empty payload denies"
pg_payload worker bash 'not json git push origin main'
expect deny "[worker] an unparseable payload naming a reserved act denies"
pg_payload worker bash 'not json at all'
expect defer "[worker] an unparseable payload naming no act defers"
pg worker 'x=$(git rev-parse HEAD); echo "$x"'
expect defer "[worker] a substitution naming no act defers"
pg worker 'x=$(git rebase origin/main)'
expect deny "[worker] a substitution hiding a rebase denies"
pg worker '(git merge origin/main)'
expect deny "[worker] a subshell hiding a merge denies"
pg worker 'git commit -m "$(cat <<'"'"'EOF'"'"'
feat: describe git push origin main and gh api graphql
EOF
)"'
expect defer "[worker] a heredoc commit message naming reserved acts defers"
pg worker "timeout 30 git rebase origin/main"
expect deny "[worker] a wrapper hiding a rebase denies"
pg worker 'sh <<EOF
git push origin main
EOF'
expect deny "[worker] a here-document fed to a shell naming a push denies"
# bash ends these bodies at E and E\F, so the lines between are commands.
pg worker 'cat <<$'"'"'E'"'"'
x
E
git push
$E' "$MAIN"
expect deny "[worker] a dollar-quoted here-document delimiter cannot hide a push"
pg worker 'cat <<E\\F
x
E\F
git push
EF' "$MAIN"
expect deny "[worker] a backslash-quoted here-document delimiter cannot hide a push"
pg worker 'cat <<"E\"F"
x
E"F
git push
E\"F' "$MAIN"
expect deny "[worker] an escape inside a double-quoted here-document delimiter cannot hide a push"
pg worker 'cat <<E\
F
x
EF
git push
E' "$MAIN"
expect deny "[worker] a line-continued here-document delimiter cannot hide a push"
pg worker 'cat <<E
x
E\

git push
E' "$MAIN"
expect deny "[worker] a line continuation in a here-document body cannot hide a push"
pg worker 'cat <<'"'"'E'"'"'
x\
E
git push' "$UNIT"
expect defer "[worker] a quoted here-document body may end a line with a backslash"
for open in '<<\EOF' '<<"EOF"' "<<'E\\F'"; do
  d=${open:2}
  d=${d//[\"\']/}
  [ "$d" = '\EOF' ] && d=EOF
  pg worker "cat $open
x
$d
git push" "$UNIT"
  expect defer "[worker] a quoted here-document delimiter is read as bash reads it, so the push after it is judged: $open"
done
HT=$'\t'
for open in "<<-\"${HT}E\"" "<<-'${HT}E'" "<<-\\${HT}E"; do
  pg worker "cat $open
x
${HT}E
git push
E" "$MAIN"
  expect deny "[worker] bash ends a <<- body at a tab-led delimiter as written, so it cannot hide a push: ${open//$HT/<tab>}"
done
pg worker 'cat <<E
x\\
E
cd '"$UNIT"'; git push' "$MAIN"
expect defer "[worker] an escaped backslash ending a here-document body line does not join it to the next"
pg worker 'cat <<E
x\\\
E
cat <<F
E
git push
F' "$MAIN"
expect deny "[worker] an odd run of backslashes ending a here-document body line still joins it to the next"
mkdir -p "$SANDBOX/nojq"
for t in head tr dirname cat; do ln -sf "$(command -v "$t")" "$SANDBOX/nojq/$t"; done
NOJQ_OUT=$(printf '%s' '{"tool_name":"Bash","tool_input":{"command":"gh pr ready 42"}}' \
  | env -i PATH="$SANDBOX/nojq" /bin/bash "$HOOK" worker bash 2>/dev/null)
case $NOJQ_OUT in
  *'"deny"'*) pass "[worker] with jq absent a payload naming a flip denies" ;;
  *) fail "[worker] with jq absent a payload naming a flip did not deny: $NOJQ_OUT" ;;
esac
NOJQ_OUT=$(printf '%s' '{"tool_name":"Bash","tool_input":{"command":"ls"}}' \
  | env -i PATH="$SANDBOX/nojq" /bin/bash "$HOOK" worker bash 2>/dev/null)
if [ -z "$NOJQ_OUT" ]; then
  pass "[worker] with jq absent a payload naming no act defers"
else
  fail "[worker] with jq absent an unrelated payload did not defer: $NOJQ_OUT"
fi

# --- static properties -------------------------------------------------------

echo "# static properties"
if grep -Eq '(^|[^[:alnum:]_-])(claude|anthropic|curl|wget)([^[:alnum:]_-]|$)' <(grep -v '^[[:space:]]*#' "$REAL_SCRIPTS/policy-guard.sh"); then
  fail "the guard's code names a model or network client"
else
  pass "the guard's code names no model or network client"
fi
if grep -Eq '^[[:space:]]*\.[[:space:]]+"[^"]*/echo-safety\.sh"' "$REAL_SCRIPTS/policy-guard.sh"; then
  pass "the guard sources scripts/echo-safety.sh"
else
  fail "the guard does not source scripts/echo-safety.sh"
fi

echo "# policy is read from the primary checkout, never the command's own worktree"
WT="$SANDBOX/linked"
gitq -C "$UNIT" worktree add -b planwright/demo/task-7 "$WT" HEAD
mkdir -p "$UNIT/.claude" "$WT/.claude"
printf 'ready_flip_policy: human\n' >"$UNIT/.claude/planwright.local.yml"
printf 'ready_flip_policy: unit-owner\n' >"$WT/.claude/planwright.local.yml"
printf 'ready_flip_policy: unit-owner\n' >"$WT/.claude/planwright.yml"
PG_LOCAL_CONFIG='' PG_REPO_ROOT='' pg worker 'gh pr ready 42' "$WT" "$WT"
expect deny "[worker] a worktree's own config cannot raise ready_flip_policy over the primary checkout's"
printf 'ready_flip_policy: unit-owner\n' >"$UNIT/.claude/planwright.local.yml"
printf 'ready_flip_policy: human\n' >"$WT/.claude/planwright.local.yml"
PG_LOCAL_CONFIG='' PG_REPO_ROOT='' pg worker 'gh pr ready 42' "$WT" "$WT"
expect defer "[worker] the primary checkout's ready_flip_policy governs a linked worktree"
rm -f "$UNIT/.claude/planwright.local.yml" "$WT/.claude/planwright.local.yml" "$WT/.claude/planwright.yml"
printf 'protected_branches: release/*\n' >"$UNIT/.claude/planwright.yml"
printf 'protected_branches:\n' >"$WT/.claude/planwright.yml"
PG_LOCAL_CONFIG='' PG_REPO_ROOT='' pg worker 'gh api -X PATCH repos/acme/widgets/git/refs/heads/release/1 -f sha=abc' "$WT" "$WT"
expect deny "[worker] a worktree's own config cannot shrink the primary checkout's protected set"
rm -f "$UNIT/.claude/planwright.yml" "$WT/.claude/planwright.yml"
BARE="$SANDBOX/bare.git"
BWT="$SANDBOX/bare-linked"
gitq clone --bare "$ORIGIN" "$BARE"
gitq -C "$BARE" worktree add "$BWT" planwright/demo/task-1
for d in "$BWT" "$SANDBOX"; do
  pg worker 'gh pr ready 42' "$d" "$d"
  expect deny "[worker] no primary checkout to read policy from denies: $d"
  reads none "[worker] the unresolvable primary checkout denies before any read: $d"
done
reason_has 'primary checkout' "the unresolvable-primary deny says why"

no_gh_calls
finish
