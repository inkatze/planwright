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
# Column 1 has no write arm, so only the declaration approves each of these
# alone; column 4 adds both arms, whose own writes refuse the act anyway.
WDECLS='mix test <path>...; mise exec -- mix credo <word>; git commit -m <word>'
WDECLS="$WDECLS; git push origin <word>; git config user.name <word>; rm <path>; rm -rf <path>"
WDECLS="$WDECLS; tee <path>; cp <path> <path>; sed -i <word> <path>; mise exec -- rm <path>"
WDECLS="$WDECLS; ln -s <path> <path>; env mix test <path>; mise use <word>"
WDECLS="$WDECLS; npm test; python3 -m pytest <path>; node <path>; npx <word>; pnpm dlx <word>"
WDECLS="$WDECLS; osascript <path>; php -r <word>; /bin/rm <path>; mise exec -- <word>..."
: >"$WT/build.txt"
# Each row: a declared command that writes, acts on git or runs arbitrary
# code. It is approved alone (column 1), and never before the own push.
WRITERS=(
  "git config user.name x"
  "rm build.txt"
  "rm -rf build.txt"
  "tee build.txt"
  "cp build.txt test/c.txt"
  "sed -i 1d build.txt"
  "mise exec -- rm build.txt"
  "ln -s build.txt test/l.txt"
  "env mix test test"
  "mise use node"
  "python3 -m pytest test"
  "node build.txt"
  "npx cowsay"
  "pnpm dlx cowsay"
  "osascript build.txt"
  "php -r exit"
  "/bin/rm build.txt"
  "mise exec -- git status"
)
for col in 1 4; do
  under "$(with_checks "writes.$col" "$col" "$WDECLS")"
  assert_allow "F1.11 [$col]: a read-only check command still partners the own push" \
    "mix test test && git push origin $CORPUS_UNIT_BRANCH" Bash "$WT"
  assert_allow "F1.11 [$col]: a runner-prefixed check command still partners the own push" \
    "mise exec -- mix credo strict && git push origin $CORPUS_UNIT_BRANCH" Bash "$WT"
  assert_allow "F1.11 [$col]: a repository task runner still partners the own push" \
    "npm test && git push origin $CORPUS_UNIT_BRANCH" Bash "$WT"
  for w in "${WRITERS[@]}"; do
    [ "$col" != 1 ] || assert_allow "F1.11 [$col]: declared $w, alone as before" "$w" Bash "$WT"
    assert_defer "F1.11 [$col]: declared $w before the own push" \
      "$w && git push origin $CORPUS_UNIT_BRANCH" Bash "$WT"
  done
  # The own-branch arm's own commit is a partner by design (column 4).
  if [ "$col" = 1 ]; then
    assert_allow "F1.11 [$col]: a declared git commit alone, as before" "git commit -m wip" Bash "$WT"
    assert_defer "F1.11 [$col]: a declared git commit before the own push" \
      "git commit -m wip && git push origin $CORPUS_UNIT_BRANCH" Bash "$WT"
  fi
  assert_defer "F1.11 [$col]: the floor wins over a declared push of another branch" \
    "git push origin other" Bash "$WT"
  assert_defer "F1.11 [$col]: a declared push of another branch before the own push" \
    "git push origin other && git push origin $CORPUS_UNIT_BRANCH" Bash "$WT"
  [ "$col" != 1 ] || assert_defer "F1.11 [$col]: a check command's write redirect defers alone" \
    "mix test test > build.txt" Bash "$WT"
  assert_defer "F1.11 [$col]: a check command with a write redirect before the own push" \
    "mix test test > build.txt && git push origin $CORPUS_UNIT_BRANCH" Bash "$WT"
  assert_defer "F1.11 [$col]: a declared rm after the own push" \
    "git push origin $CORPUS_UNIT_BRANCH && rm build.txt" Bash "$WT"
done

echo "### REQ-F1.11 — the write scan reads any case, the text after =, and more tools"
RDECLS='make <word>...; cargo test; go test <path>; go run <path>; pytest <path>'
RDECLS="$RDECLS; mise exec -- <word>...; elixir -e <word>; gsed -i <word> <path>; RM <path>"
RDECLS="$RDECLS; java <word>; vim <path>; sponge <path>; gzip <path>; sqlite3 <path>; ssh <word>"
RDECLS="$RDECLS; docker <word>...; flock <path> <word>; perl5.34 <path>"
RDECLS="$RDECLS; GO run <path>; go -C <path> run <path>; mix lint --cmd=rm; gtouch <path>"
RDECLS="$RDECLS; tcsh <path>; zstd <path>; tmux <word>; julia <path>; gcc <path>"
under "$(with_checks scan 1 "$RDECLS")"
for r in "make check" "cargo test" "go test test" "pytest test" "mise exec -- pytest test"; do
  assert_allow "F1.11: declared $r still partners the own push" \
    "$r && git push origin $CORPUS_UNIT_BRANCH" Bash "$WT"
done
for r in "mise exec -- GIT status" "RM build.txt" "make check SHELL=bash" "make check X=rm" \
  "go run test" "elixir -e exit" "gsed -i 1d build.txt" "java Main" "vim build.txt" \
  "sponge build.txt" "gzip build.txt" "sqlite3 build.txt" "ssh host" "docker run img" \
  "flock build.txt make" "perl5.34 build.txt" "GO run test" "go -C test run test" \
  "mix lint --cmd=rm" "gtouch build.txt" "tcsh build.txt" "zstd build.txt" "tmux new" \
  "julia build.txt" "gcc build.txt"; do
  assert_allow "F1.11: declared $r, alone as before" "$r" Bash "$WT"
  assert_defer "F1.11: declared $r before the own push" \
    "$r && git push origin $CORPUS_UNIT_BRANCH" Bash "$WT"
done

echo "### REQ-F1.12 — a declaration naming a step script is never a check command"
# The step-script rules, and the prompt they keep for a hand-timed record,
# hold over any declaration: under any runner prefix or path spelling, in any
# letter case, or through a link of the installed copy under another name.
T=2026-11-22T10:00:00Z
SREC=$REPO_ROOT/scripts/step-record.sh
SRUN=$REPO_ROOT/scripts/step-run.sh
# bin/sr and bin/sn are the installed step scripts under other names; as a
# declaration's literal words they also fail the committed-file rule. Given
# as a `<word>`, which that rule leaves to the declarer, `rec` and `run` reach
# only the link reading, and `ok`, a link of a non-step installed script,
# shows the link reading does not over-match. The worktree's own (empty)
# scripts/step-record.sh lets the <path> rows below name an existing file.
mkdir -p "$WT/bin"
ln -s "$SREC" "$WT/bin/sr"
ln -s "$SRUN" "$WT/bin/sn"
ln -s "$SREC" "$WT/rec"
ln -s "$SRUN" "$WT/run"
ln -s "$REPO_ROOT/scripts/resolve-steps.sh" "$WT/ok"
: >"$WT/scripts/step-record.sh"
# Every STEPPED and CONTROLS row below needs its declaration here: an
# undeclared row would defer for want of one and prove nothing.
SARGS='write --run <word> --point <word> --step <word> --start <word> --outcome <word>'
SDECLS="scripts/step-record.sh $SARGS; ./scripts/step-record.sh $SARGS"
SDECLS="$SDECLS; mise exec -- scripts/step-record.sh $SARGS; mise exec -- $SREC $SARGS"
SDECLS="$SDECLS; $SREC $SARGS; SCRIPTS/STEP-RECORD.SH $SARGS; mise exec -- Scripts/Step-Record.sh $SARGS"
SDECLS="$SDECLS; mise exec -- ./scripts/step-record.sh $SARGS; mise exec -- step-record.sh $SARGS"
SDECLS="$SDECLS; bin/sr $SARGS; make check SCRIPT=scripts/step-record.sh"
SDECLS="$SDECLS; mise exec -- scripts/step-run.sh <word>...; mise exec -- $SRUN <word>..."
SDECLS="$SDECLS; make check SCRIPT=scripts/step-run.sh; make check A=B=scripts/step-record.sh"
SDECLS="$SDECLS; bin/sn <word>...; bin/lint <path>...; make check SCRIPT=scripts/ok.sh"
SDECLS="$SDECLS; mix test <path>...; mise exec -- mix credo <word>; bin/lint <word>..."
SDECLS="$SDECLS; make check SHELL=bash SCRIPT=scripts/step-record.sh"
# No word of these write arguments is one the partner scan refuses, so only
# the step-script reading keeps the rows below from the own push.
SW="write --run 000001 --point pre-pr --step lint --start $T --outcome passed"
STEPPED=(
  "scripts/step-record.sh $SW"
  "./scripts/step-record.sh $SW"
  "mise exec -- scripts/step-record.sh $SW"
  "mise exec -- $SREC $SW"
  "$SREC $SW"
  "SCRIPTS/STEP-RECORD.SH $SW"
  "mise exec -- Scripts/Step-Record.sh $SW"
  "bin/sr $SW"
  "mise exec -- ./scripts/step-record.sh $SW"
  "mise exec -- step-record.sh $SW"
  "make check SCRIPT=scripts/step-record.sh"
  "mise exec -- scripts/step-run.sh frobnicate"
  "mise exec -- $SRUN frobnicate"
  "make check SCRIPT=scripts/step-run.sh"
  "make check A=B=scripts/step-record.sh"
  "bin/sn frobnicate"
  # Every word is read, so a step script given only as an argument defers too.
  "bin/lint scripts/step-record.sh"
  "bin/lint rec"
  "bin/lint run"
  # A word the partner scan refuses leaves a match that is approved only
  # alone; naming a step script, it must still defer.
  "make check SHELL=bash SCRIPT=scripts/step-record.sh"
)
# Each control: a declared read-only command naming no step script, which
# still runs alone and partners the own push.
CONTROLS=(
  "mix test test"
  "mise exec -- mix credo strict"
  "make check SCRIPT=scripts/ok.sh"
  "bin/lint scripts/ok.sh"
  "bin/lint ok"
)
for col in 1 4; do
  under "$(with_checks "stepped.$col" "$col" "$SDECLS")"
  for c in "${CONTROLS[@]}"; do
    assert_allow "F1.12 [$col]: declared $c, alone as before" "$c" Bash "$WT"
    assert_allow "F1.12 [$col]: declared $c still partners the own push" \
      "$c && git push origin $CORPUS_UNIT_BRANCH" Bash "$WT"
  done
  for s in "${STEPPED[@]}"; do
    assert_defer "F1.12 [$col]: declared $s, alone" "$s" Bash "$WT"
    assert_defer "F1.12 [$col]: declared $s before the own push" \
      "$s && git push origin $CORPUS_UNIT_BRANCH" Bash "$WT"
  done
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

echo "### a script a declaration names is held to what HEAD commits"
# scripts/ok.sh is committed in the corpus base; tests/run.sh is not.
printf '#!/bin/sh\n' >"$WT/tests/run.sh"
mkdir -p "$WT/tools"
printf '#!/bin/sh\n' >"$WT/tools/run"
printf '#!/bin/sh\n' >"$WT/check.sh"
printf '#!/bin/sh\n' >"$WT/mix"
ln -s scripts/ok.sh "$WT/linked.sh"
LIT='scripts/ok.sh <word>; bash tests/run.sh; bash tests/ok.sh; tools/run; bash check.sh; mix test tests'
LIT="$LIT; mix format; bash linked.sh"
under "$(with_checks literal 1 "$LIT")"
assert_allow "a committed script a declaration names" "scripts/ok.sh lint" Bash "$WT"
assert_defer "an untracked script a declaration names" "bash tests/run.sh" Bash "$WT"
assert_defer "an untracked runner outside scripts/ a declaration names" "tools/run" Bash "$WT"
assert_defer "an untracked script a declaration names by a bare word" "bash check.sh" Bash "$WT"
assert_allow "a directory a declaration names stays as declared" "mix test tests" Bash "$WT"
assert_allow "a bare first word stays a PATH lookup, a file of its name aside" "mix format" Bash "$WT"
assert_defer "a symlink a declaration names by a bare word" "bash linked.sh" Bash "$WT"
cp "$WT/scripts/ok.sh" "$STATE/ok.orig"
printf 'printf pwned\n' >>"$WT/scripts/ok.sh"
assert_defer "a named script edited since HEAD" "scripts/ok.sh lint" Bash "$WT"
cp "$STATE/ok.orig" "$WT/scripts/ok.sh"
assert_allow "the named script put back" "scripts/ok.sh lint" Bash "$WT"
# The check reads the file before the command runs, so a write beside the run
# turns the trust off for the whole command.
under "$(with_checks literal.ob 2 "$LIT")"
assert_defer "a write beside a committed script a declaration names" "cp f scripts/ok.sh && scripts/ok.sh lint" Bash "$WT"
assert_allow "the same run with no write beside it" "scripts/ok.sh lint" Bash "$WT"
rm -rf "$WT/tests/run.sh" "$WT/tools" "$WT/check.sh" "$WT/mix" "$WT/linked.sh"
HOOK_ENV=()

finish_suite worker-command-guard-checks
