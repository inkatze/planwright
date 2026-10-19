#!/bin/bash
# The worker command guard never approves a command the worker profile's deny
# block matches, under any policy value and for any approval category
# (REQ-A1.11), asserted against the actual block rather than Claude Code's
# evaluation order: for every `Bash(…)` rule, a generated command it matches
# defers under each policy column, and so does a curated collision wherever
# the rule's verb is otherwise approvable, which a deny-free copy of the guard
# shows it would approve. A rule with neither a collision row nor a declared
# reason why none exists fails the suite, so a new rule cannot land
# unclassified. The declared-step category is in
# tests/test-worker-command-guard-steps.sh.
set -u
unset CDPATH
# shellcheck source=tests/lib/worker-command-guard-harness.sh
. "$(cd "$(dirname "$0")" && pwd)/lib/worker-command-guard-harness.sh"
# shellcheck source=tests/lib/worker-guard-corpus.sh
. "$REPO_ROOT/tests/lib/worker-guard-corpus.sh"
# shellcheck source=tests/lib/permission-matcher.sh
. "$REPO_ROOT/tests/lib/permission-matcher.sh"

corpus_sandbox "$SANDBOX/box" "$REPO_ROOT" || {
  echo "FAIL: could not build the corpus sandbox" >&2
  exit 1
}
WT=$CORPUS_WORKTREE
STATE=$CORPUS_BOX/state
GIT_ISO=("GIT_CONFIG_GLOBAL=/dev/null" "GIT_CONFIG_NOSYSTEM=1")
POLICIES=("" "own-branch" "scratch" "own-branch scratch")
under() {
  HOOK_ENV=("${GIT_ISO[@]}" "PLANWRIGHT_WORKER_SESSION_RECORD=$1")
}

echo "### REQ-A1.11 — no deny-matched command is ever approved"
SETTINGS=$REPO_ROOT/config/worker-settings.json
rules=$(jq -r '.permissions.deny[] | select(startswith("Bash("))' "$SETTINGS")
[ -n "$rules" ] || fail "A1.11: no Bash rule read from the deny block"
# A deny-free stand-in for the guard: the same script beside a profile whose
# only Bash deny rule matches nothing, so a collision row can prove the guard
# would otherwise approve it.
mkdir -p "$SANDBOX/nodeny/scripts" "$SANDBOX/nodeny/config"
cp "$HOOK" "$SANDBOX/nodeny/scripts/worker-command-guard.sh"
jq '.permissions.deny = ["Bash(zz-matches-nothing)"]' "$SETTINGS" >"$SANDBOX/nodeny/config/worker-settings.json"
REAL_HOOK=$HOOK
# collision <rule>: a command the rule matches that some arm would approve, or
# `-` for a rule whose verb no arm approves in any form.
collision() {
  case $1 in
    'Bash(git * --no-verify*)') echo 'git log --no-verify' ;;
    'Bash(git * --no-veri*)') echo 'git log --no-veri' ;;
    'Bash(git commit * -n*)') echo 'git commit -m x -- -nfile' ;;
    'Bash(git * -c core.hooksPath*)') echo 'git log -c core.hooksPath' ;;
    'Bash(git * -c core.hookspath*)') echo 'git log -c core.hookspath' ;;
    'Bash(git config core.hooksPath*)') echo 'git config core.hooksPath' ;;
    'Bash(git config core.hookspath*)') echo 'git config core.hookspath' ;;
    'Bash(git config * core.hooksPath*)') echo 'git config --get core.hooksPath' ;;
    'Bash(git config * core.hookspath*)') echo 'git config --get core.hookspath' ;;
    'Bash(git * --config-env*)') echo 'git log --config-env=x' ;;
    'Bash(git * --hooks-path*)') echo 'git log --hooks-path=x' ;;
    # Pushes, PR merges and flips, resets, history filters, and every
    # global-option form: no arm approves the verb in any spelling.
    'Bash(gh pr '* | 'Bash(git push'* | 'Bash(git reset'* | 'Bash(git filter-'* | 'Bash(git -'* | \
      'Bash(git commit -n*)') echo - ;;
  esac
}
# generated <pattern>: a command the pattern matches, each `*` filled.
generated() {
  local p=$1
  case $p in
    *':*') p="${p%:\*} x" ;;
  esac
  printf '%s' "${p//\*/x}"
}
while IFS= read -r rule; do
  [ -n "$rule" ] || continue
  pat=${rule#Bash(}
  pat=${pat%)}
  g=$(generated "$pat")
  if ! pm_matches "$pat" "$g"; then
    fail "A1.11: the generated command does not match $rule: $g"
    continue
  fi
  c=$(collision "$rule")
  if [ -z "$c" ]; then
    fail "A1.11: $rule has no curated collision row and is not declared unapprovable"
    continue
  fi
  for col in 1 2 3 4; do
    under "$STATE/record.$col"
    HOOK=$REAL_HOOK
    assert_defer "A1.11 [${POLICIES[col - 1]}]: generated for $rule" "$g" Bash "$WT"
    [ "$c" != - ] || continue
    pm_matches "$pat" "$c" || fail "A1.11: the collision row does not match $rule: $c"
    assert_defer "A1.11 [${POLICIES[col - 1]}]: collision for $rule" "$c" Bash "$WT"
  done
  if [ "$c" != - ]; then
    under "$STATE/record.4"
    HOOK=$SANDBOX/nodeny/scripts/worker-command-guard.sh
    assert_allow "A1.11: without the rule, its collision row is approvable" "$c" Bash "$WT"
    HOOK=$REAL_HOOK
  fi
done <<EOF
$rules
EOF

echo "### REQ-A1.11 — a profile the guard cannot read approves nothing"
mkdir -p "$SANDBOX/noprofile/scripts"
cp "$REAL_HOOK" "$SANDBOX/noprofile/scripts/worker-command-guard.sh"
HOOK=$SANDBOX/noprofile/scripts/worker-command-guard.sh
under "$STATE/record.4"
assert_defer "A1.11: no profile beside the guard, so not even a read" "ls" Bash "$WT"
mkdir -p "$SANDBOX/noprofile/config"
jq '.permissions.deny = []' "$SETTINGS" >"$SANDBOX/noprofile/config/worker-settings.json"
assert_defer "A1.11: a deny block with no Bash rule approves nothing" "ls" Bash "$WT"
jq '.permissions.deny += ["Bash(git push"]' "$SETTINGS" >"$SANDBOX/noprofile/config/worker-settings.json"
assert_defer "A1.11: a malformed Bash rule approves nothing" "ls" Bash "$WT"
HOOK=$REAL_HOOK

finish_suite worker-command-guard-deny
