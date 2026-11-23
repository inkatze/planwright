#!/bin/bash
# Tests for the worker command guard's declared check commands
# (worker-permission-ergonomics REQ-A1.18, D-36): a repository's own test and
# check runners, declared as word sequences with argument-shape placeholders in
# `worker_check_commands`, resolved by the launcher into the session record,
# and approved only by shape, after the `deny` block (REQ-A1.19). The rows run
# in the corpus sandbox (tests/lib/worker-guard-corpus.sh): a linked worktree
# on its unit branch, with one session record per policy column.
set -u
unset CDPATH
# shellcheck source=tests/lib/worker-command-guard-harness.sh
. "$(cd "$(dirname "$0")" && pwd)/lib/worker-command-guard-harness.sh"
# shellcheck source=tests/lib/worker-guard-corpus.sh
. "$REPO_ROOT/tests/lib/worker-guard-corpus.sh"

corpus_sandbox "$SANDBOX/box" "$REPO_ROOT" || {
  echo "FAIL: could not build the corpus sandbox" >&2
  exit 1
}
WT=$CORPUS_WORKTREE
OUT_DIR=$CORPUS_OUTSIDE
STATE=$CORPUS_BOX/state
GIT_ISO=("GIT_CONFIG_GLOBAL=/dev/null" "GIT_CONFIG_NOSYSTEM=1")
mkdir -p "$WT/test" "$WT/apps/web/test" "$OUT_DIR/test"
: >"$WT/test/a_test.exs"
: >"$WT/test/b_test.exs"
: >"$WT/apps/web/test/w_test.exs"
: >"$OUT_DIR/test/a_test.exs"
ln -s "$OUT_DIR/x" "$WT/test/escape_test.exs"
ln -s "$WT/githooks" "$WT/test/hooklink"
ln -s "$OUT_DIR/not-yet" "$WT/test/dangling"

# with_checks <name> <column> <declarations>: the column's record with a
# check_commands line; prints its path.
with_checks() {
  local f=$STATE/$1.record
  {
    cat "$STATE/record.$2"
    printf 'check_commands=%s\n' "$3"
  } >"$f"
  printf '%s\n' "$f"
}
under() {
  HOOK_ENV=("${GIT_ISO[@]}" "PLANWRIGHT_WORKER_SESSION_RECORD=$1")
}

DECLS='mix test <path>...; mix test --seed <int> <path>; mix format --check-formatted'
DECLS="$DECLS; mise exec -- mix credo <word>; bin/check <word>...; git reset --hard <word>"
DECLS="$DECLS; git config core.hooksPath <word>"
DECLS="$DECLS; gh pr merge <int>; mix lint <glob>; mix y a|b"
DECLS="$DECLS; <word> test; mix z \$(id); MIX_ENV=prod mix test"
REC=$(with_checks checks 1 "$DECLS")

echo "### REQ-A1.18 — a declared shape approves the matching command"
under "$REC"
assert_allow "A1.18: <path>" "mix test test/a_test.exs" Bash "$WT"
assert_allow "A1.18: a repeated <path>" "mix test test/a_test.exs test/b_test.exs" Bash "$WT"
assert_allow "A1.18: a directory <path>" "mix test test" Bash "$WT"
assert_allow "A1.18: a <path> with a line suffix" "mix test test/a_test.exs:12" Bash "$WT"
assert_allow "A1.18: a spelled flag, <int> and <path>" "mix test --seed 42 test/a_test.exs" Bash "$WT"
assert_allow "A1.18: a declaration of literal words alone" "mix format --check-formatted" Bash "$WT"
assert_allow "A1.18: a runner-prefixed declaration" "mise exec -- mix credo strict" Bash "$WT"
assert_allow "A1.18: a repeated <word>" "bin/check lint types" Bash "$WT"
assert_allow "A1.18: an fd-dup redirect, then a read" "mix test test 2>&1 | tail -n 20" Bash "$WT"
assert_allow "A1.18: a redirect to /dev/null" "mix test test > /dev/null" Bash "$WT"
assert_allow "A1.18: the worktree root as a <path>" "mix test ." Bash "$WT"
assert_allow "A1.18: each segment judged on its own" "git status && mix test test/a_test.exs" Bash "$WT"
assert_allow "A1.18: a <path> resolved from a cd inside the worktree" "cd apps/web && mix test test/w_test.exs" Bash "$WT"
assert_allow "A1.18: from a subdirectory of the worktree" "mix test test/w_test.exs" Bash "$WT/apps/web"
for col in 2 3 4; do
  under "$(with_checks "checks.$col" "$col" "$DECLS")"
  assert_allow "A1.18: approved under policy column $col too" "mix test test/a_test.exs" Bash "$WT"
done

echo "### REQ-A1.18 — nothing else"
under "$REC"
assert_defer "A1.18: a repeat needs one word" "mix test" Bash "$WT"
assert_defer "A1.18: an undeclared flag" "mix test --trace test/a_test.exs" Bash "$WT"
assert_defer "A1.18: a leading dash in a <path>" "mix test -x" Bash "$WT"
assert_defer "A1.18: a leading dash in an <int>" "mix test --seed -1 test/a_test.exs" Bash "$WT"
assert_defer "A1.18: a word that is no <int>" "mix test --seed abc test/a_test.exs" Bash "$WT"
assert_defer "A1.18: a leading dash in a <word>" "bin/check --all" Bash "$WT"
assert_defer "A1.18: a slash in a <word>" "bin/check ../x" Bash "$WT"
assert_defer "A1.18: an extra word" "mix format --check-formatted --dry-run" Bash "$WT"
assert_defer "A1.18: a word short" "mise exec -- mix credo" Bash "$WT"
assert_defer "A1.18: a runner prefix admits no other command" "mise exec -- rm -rf build" Bash "$WT"
assert_defer "A1.18: a runner prefix admits no other mix verb" "mise exec -- mix test test" Bash "$WT"
assert_defer "A1.18: the sequence without its declared prefix" "mix credo strict" Bash "$WT"
assert_defer "A1.18: a leading assignment" "MIX_ENV=prod mix test test" Bash "$WT"
assert_defer "A1.18: a traversal" "mix test ../outside" Bash "$WT"
assert_defer "A1.18: a traversal inside a <path>" "mix test test/../../outside" Bash "$WT"
assert_defer "A1.18: an absolute <path>" "mix test $WT/test/a_test.exs" Bash "$WT"
assert_defer "A1.18: a symlink out of the worktree" "mix test test/escape_test.exs" Bash "$WT"
assert_defer "A1.18: a symlinked directory out of the worktree" "mix test outlink/x" Bash "$WT"
assert_defer "A1.18: the git directory" "mix test .git" Bash "$WT"
assert_defer "A1.18: the hooks directory" "mix test githooks/pre-commit" Bash "$WT"
assert_defer "A1.18: the mise configuration" "mix test mise.toml" Bash "$WT"
assert_defer "A1.18: the lefthook configuration" "mix test lefthook.yml" Bash "$WT"
assert_defer "A1.18: the .claude directory" "mix test .claude/settings.json" Bash "$WT"
assert_defer "A1.18: the git directory with a line suffix" "mix test .git:3" Bash "$WT"
assert_defer "A1.18: the mise configuration with a line suffix" "mix test mise.toml:3" Bash "$WT"
assert_defer "A1.18: the .claude directory with a suffix" "mix test .claude:1" Bash "$WT"
assert_defer "A1.18: a path after the suffix's colon" "mix test test:/etc/passwd" Bash "$WT"
assert_defer "A1.18: a symlinked directory inside the worktree" "mix test test/hooklink/pre-commit" Bash "$WT"
assert_defer "A1.18: a dangling symlink" "mix test test/dangling/x" Bash "$WT"
assert_defer "A1.18: a leading = in a <path>, which zsh expands" "mix test =ls" Bash "$WT"
assert_defer "A1.18: a leading = in a <word>, which zsh expands" "bin/check =ls" Bash "$WT"
assert_defer "A1.18: an = inside a <path>" "mix test a=b" Bash "$WT"
assert_defer "A1.18: a working directory in the hooks directory" "mix format --check-formatted" Bash "$WT/githooks"
assert_defer "A1.18: a cd into the .claude directory" "cd .claude && mix format --check-formatted" Bash "$WT"
many=''
for i in $(seq 1 65); do many="$many test/a_test.exs"; done
assert_defer "A1.18: more <path> words than one call may check" "mix test$many" Bash "$WT"
assert_defer "A1.18: a glob" "mix test 'test/*.exs'" Bash "$WT"
assert_defer "A1.18: an unquoted glob" "mix test test/*.exs" Bash "$WT"
assert_defer "A1.18: a variable" "mix test test/\$X" Bash "$WT"
assert_defer "A1.18: a command substitution" "mix test \$(echo test)" Bash "$WT"
assert_defer "A1.18: a backtick substitution" "mix test \`echo test\`" Bash "$WT"
assert_defer "A1.18: a quoted space" "mix test 'test/a b'" Bash "$WT"
assert_defer "A1.18: a write redirect" "mix test test > build/out.txt" Bash "$WT"
assert_defer "A1.18: an undeclared segment after a declared one" "mix test test; rm -rf build" Bash "$WT"
assert_defer "A1.18: a cd out of the worktree" "cd $OUT_DIR && mix test test/a_test.exs" Bash "$WT"
assert_defer "A1.18: a working directory outside the worktree" "mix test test/a_test.exs" Bash "$OUT_DIR"

echo "### REQ-A1.19 — the deny block and the floor win over every declaration"
assert_defer "A1.19: a declared shape the deny block alone matches" "git config core.hooksPath x" Bash "$WT"
assert_defer "A1.19: a declared reserved act" "git reset --hard origin" Bash "$WT"
assert_defer "A1.19: a declared gh write" "gh pr merge 12" Bash "$WT"
assert_allow "F1.10: the own push alone still allows" "git push origin $CORPUS_UNIT_BRANCH" Bash "$WT"
assert_allow "F1.11: a declared check command is a chain partner before the own push" \
  "mix test test && git push origin $CORPUS_UNIT_BRANCH" Bash "$WT"
assert_defer "F1.11: a declared check command after the own push" \
  "git push origin $CORPUS_UNIT_BRANCH && mix test test" Bash "$WT"
assert_defer "F1.11: a declared check command joined to the own push by ;" \
  "mix test test; git push origin $CORPUS_UNIT_BRANCH" Bash "$WT"

echo "### REQ-F1.11 — a check command partners an own-unit act only by &&"
REC_OU=$(with_checks ouchk 4 'mix test <path>...')
under "$REC_OU"
assert_allow "F1.11: a check command before the own push, both arms" \
  "mix test test && git push origin $CORPUS_UNIT_BRANCH" Bash "$WT"
if [ "$(tail -n 1 "$STATE/audit.4/ouchk.log" 2>/dev/null | grep -o 'arm=[a-z,-]*')" = arm=own-unit ]; then
  pass "F1.11: a check-command chain is audited as own-unit"
else
  fail "F1.11: audit line, expected arm=own-unit: $(tail -n 1 "$STATE/audit.4/ouchk.log" 2>&1)"
fi
assert_allow "F1.11: a check command after a git add partner" \
  "git add test && mix test test && git push origin $CORPUS_UNIT_BRANCH" Bash "$WT"
if [ "$(tail -n 1 "$STATE/audit.4/ouchk.log" 2>/dev/null | grep -o 'arm=[a-z,-]*')" = arm=own-branch,own-unit ]; then
  pass "F1.11: a check-command chain with a git add is audited as own-branch,own-unit"
else
  fail "F1.11: audit line, expected arm=own-branch,own-unit: $(tail -n 1 "$STATE/audit.4/ouchk.log" 2>&1)"
fi
assert_allow "F1.11: a check command before a git add partner" \
  "mix test test && git add test && git push origin $CORPUS_UNIT_BRANCH" Bash "$WT"
assert_defer "F1.11: a check command piped into a read before the own push" \
  "mix test test 2>&1 | tail -n 5 && git push origin $CORPUS_UNIT_BRANCH" Bash "$WT"
assert_defer "F1.11: a check command opened by a pipe" \
  "git status | mix test test && git push origin $CORPUS_UNIT_BRANCH" Bash "$WT"
assert_defer "F1.11: a check command opened by &" \
  "git status & mix test test && git push origin $CORPUS_UNIT_BRANCH" Bash "$WT"
assert_defer "F1.11: a check command joined to the own push by ||" \
  "mix test test || git push origin $CORPUS_UNIT_BRANCH" Bash "$WT"
assert_defer "F1.11: a check command joined to the own push by &" \
  "mix test test & git push origin $CORPUS_UNIT_BRANCH" Bash "$WT"
assert_defer "F1.11: a check command piped into the own push" \
  "mix test test | git push origin $CORPUS_UNIT_BRANCH" Bash "$WT"
assert_defer "F1.11: a check command before a line break" \
  "mix test test
git push origin $CORPUS_UNIT_BRANCH" Bash "$WT"
assert_defer "F1.11: a check command, && and a line break" \
  "mix test test &&
git push origin $CORPUS_UNIT_BRANCH" Bash "$WT"
assert_defer "F1.11: a check command in a loop" \
  "for f in a; do mix test test; done && git push origin $CORPUS_UNIT_BRANCH" Bash "$WT"
assert_defer "F1.11: a check command in a subshell" \
  "(mix test test) && git push origin $CORPUS_UNIT_BRANCH" Bash "$WT"
assert_allow "the file write alone allows under own-branch (control)" "touch build.txt" Bash "$WT"
assert_defer "F1.11: a check command chained with a file write" \
  "mix test test && touch build.txt && git push origin $CORPUS_UNIT_BRANCH" Bash "$WT"
assert_defer "F1.11: a check command chained with a fetch" \
  "mix test test && git fetch origin && git push origin $CORPUS_UNIT_BRANCH" Bash "$WT"

echo "### REQ-F1.11 — a declared check command that writes or acts on git never partners"
# Columns 1 and 3 carry no own-branch arm, so only the declaration approves
# these on their own; column 2 adds the arm's own refusals.
WDECLS='mix test <path>...; mise exec -- mix credo <word>; git commit -m <word>'
WDECLS="$WDECLS; git push origin <word>; git config user.name <word>; rm <path>; rm -rf <path>"
WDECLS="$WDECLS; tee <path>; cp <path> <path>; sed -i <word> <path>; mise exec -- rm <path>"
WDECLS="$WDECLS; ln -s <path> <path>; env mix test <path>; mise use <word>"
WDECLS="$WDECLS; npm test; python3 -m pytest <path>; node <path>; npx <word>; pnpm dlx <word>"
WDECLS="$WDECLS; osascript <path>; php -r <word>"
: >"$WT/build.txt"
for col in 1 2 3; do
  under "$(with_checks "writes.$col" "$col" "$WDECLS")"
  assert_allow "F1.11 [$col]: a read-only check command still partners the own push" \
    "mix test test && git push origin $CORPUS_UNIT_BRANCH" Bash "$WT"
  assert_allow "F1.11 [$col]: a runner-prefixed check command still partners the own push" \
    "mise exec -- mix credo strict && git push origin $CORPUS_UNIT_BRANCH" Bash "$WT"
  assert_allow "F1.11 [$col]: a declared rm alone, as before" "rm build.txt" Bash "$WT"
  assert_allow "F1.11 [$col]: a declared sed -i alone, as before" "sed -i 1d build.txt" Bash "$WT"
  assert_allow "F1.11 [$col]: a declared git config alone, as before" "git config user.name x" Bash "$WT"
  assert_allow "F1.11 [$col]: a runner-prefixed rm alone, as before" "mise exec -- rm build.txt" Bash "$WT"
  # The own-branch arm's own commit is a partner by design, so column 2 is
  # left out here.
  [ "$col" = 2 ] || assert_defer "F1.11 [$col]: a declared git commit before the own push" \
    "git commit -m wip && git push origin $CORPUS_UNIT_BRANCH" Bash "$WT"
  assert_defer "F1.11 [$col]: a declared git push of another branch before the own push" \
    "git push origin other && git push origin $CORPUS_UNIT_BRANCH" Bash "$WT"
  assert_defer "F1.11 [$col]: a declared git config before the own push" \
    "git config user.name x && git push origin $CORPUS_UNIT_BRANCH" Bash "$WT"
  assert_defer "F1.11 [$col]: a check command with a write redirect before the own push" \
    "mix test test > build.txt && git push origin $CORPUS_UNIT_BRANCH" Bash "$WT"
  assert_defer "F1.11 [$col]: a declared rm before the own push" \
    "rm build.txt && git push origin $CORPUS_UNIT_BRANCH" Bash "$WT"
  assert_defer "F1.11 [$col]: a declared rm -rf before the own push" \
    "rm -rf build.txt && git push origin $CORPUS_UNIT_BRANCH" Bash "$WT"
  assert_defer "F1.11 [$col]: a declared tee before the own push" \
    "tee build.txt && git push origin $CORPUS_UNIT_BRANCH" Bash "$WT"
  assert_defer "F1.11 [$col]: a declared cp before the own push" \
    "cp build.txt test/c.txt && git push origin $CORPUS_UNIT_BRANCH" Bash "$WT"
  assert_defer "F1.11 [$col]: a declared sed -i before the own push" \
    "sed -i 1d build.txt && git push origin $CORPUS_UNIT_BRANCH" Bash "$WT"
  assert_defer "F1.11 [$col]: a runner-prefixed rm before the own push" \
    "mise exec -- rm build.txt && git push origin $CORPUS_UNIT_BRANCH" Bash "$WT"
  assert_defer "F1.11 [$col]: a declared ln before the own push" \
    "ln -s build.txt test/l.txt && git push origin $CORPUS_UNIT_BRANCH" Bash "$WT"
  assert_defer "F1.11 [$col]: a check command behind env before the own push" \
    "env mix test test && git push origin $CORPUS_UNIT_BRANCH" Bash "$WT"
  assert_defer "F1.11 [$col]: a declared mise use before the own push" \
    "mise use node && git push origin $CORPUS_UNIT_BRANCH" Bash "$WT"
  assert_allow "F1.11 [$col]: a repository task runner still partners the own push" \
    "npm test && git push origin $CORPUS_UNIT_BRANCH" Bash "$WT"
  assert_allow "F1.11 [$col]: a declared interpreter alone, as before" "python3 -m pytest test" Bash "$WT"
  assert_defer "F1.11 [$col]: a declared python before the own push" \
    "python3 -m pytest test && git push origin $CORPUS_UNIT_BRANCH" Bash "$WT"
  assert_defer "F1.11 [$col]: a declared node before the own push" \
    "node build.txt && git push origin $CORPUS_UNIT_BRANCH" Bash "$WT"
  assert_defer "F1.11 [$col]: a declared npx before the own push" \
    "npx cowsay && git push origin $CORPUS_UNIT_BRANCH" Bash "$WT"
  assert_defer "F1.11 [$col]: a declared pnpm dlx before the own push" \
    "pnpm dlx cowsay && git push origin $CORPUS_UNIT_BRANCH" Bash "$WT"
  assert_defer "F1.11 [$col]: a declared osascript before the own push" \
    "osascript build.txt && git push origin $CORPUS_UNIT_BRANCH" Bash "$WT"
  assert_defer "F1.11 [$col]: a declared php -r before the own push" \
    "php -r exit && git push origin $CORPUS_UNIT_BRANCH" Bash "$WT"
  assert_defer "F1.11 [$col]: a declared rm after the own push" \
    "git push origin $CORPUS_UNIT_BRANCH && rm build.txt" Bash "$WT"
done
under "$REC"

echo "### REQ-A1.18 — a malformed declaration drops alone"
assert_defer "A1.18: an unknown placeholder" "mix lint x" Bash "$WT"
assert_defer "A1.18: a metacharacter in a declaration" "mix y 'a|b'" Bash "$WT"
assert_defer "A1.18: a declaration led by a placeholder" "foo test" Bash "$WT"
assert_defer "A1.18: a substitution in a declaration" "mix z '\$(id)'" Bash "$WT"
assert_defer "A1.18: an assignment leading a declaration" "MIX_ENV=prod mix test" Bash "$WT"
assert_allow "A1.18: the well-formed declarations still match" "mix format --check-formatted" Bash "$WT"

echo "### REQ-A1.18 — no declaration, no approval"
under "$STATE/record.1"
assert_defer "A1.18: a record with no check_commands" "mix test test/a_test.exs" Bash "$WT"
HOOK_ENV=("${GIT_ISO[@]}")
assert_defer "A1.18: no session record" "mix test test/a_test.exs" Bash "$WT"
under "$(with_checks dup 1 "$DECLS")"
printf 'check_commands=%s\n' 'mix test <path>' >>"$STATE/dup.record"
assert_defer "A1.18: a repeated check_commands field drops both" "mix test test/a_test.exs" Bash "$WT"
under "$(with_checks bad 1 'mix test <path>;;')"
assert_allow "A1.18: an empty declaration is skipped" "mix test test/a_test.exs" Bash "$WT"
long=''
for i in $(seq 1 130); do long="${long}mix t$i <path>; "; done
under "$(with_checks long 1 "${long}mix test <path>")"
assert_defer "A1.18: a check_commands field past the bound drops whole" "mix test test/a_test.exs" Bash "$WT"

under "$(with_checks opened 2 'mix test <path>...')"
printf '%s\n' mise_task_edit=1 lefthook_edit=1 >>"$STATE/opened.record"
assert_allow "A1.18: the opt-ins are read: the own-branch arm opens lefthook.yml" "touch lefthook.yml" Bash "$WT"
assert_allow "A1.18: an opted-in launch still approves a plain path" "mix test test" Bash "$WT"
assert_defer "A1.18: the lefthook opt-in never reaches a check command" "mix test lefthook.yml" Bash "$WT"
assert_defer "A1.18: the mise opt-in never reaches a check command" "mix test mise.toml" Bash "$WT"

echo "### REQ-H1.4 — a check command is audited on the read-only arm"
REC_A=$(with_checks audited 1 'mix test <path>')
under "$REC_A"
assert_allow "H1.4: the audited approval" "mix test test/a_test.exs" Bash "$WT"
if [ "$(tail -n 1 "$STATE/audit.1/audited.log" 2>/dev/null | grep -o 'arm=[a-z,-]*')" = arm=read-only ]; then
  pass "H1.4: the audit line names the read-only arm"
else
  fail "H1.4: audit line: $(tail -n 1 "$STATE/audit.1/audited.log" 2>&1)"
fi
HOOK_ENV=()

finish_suite worker-command-guard-checks
