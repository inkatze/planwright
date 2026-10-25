#!/bin/bash
# Tests for scripts/worker-command-guard.sh: guard parity between unit kinds
# (tower-front-door D-19 · REQ-C1.10). A command step on a flight is approved
# on exactly the terms a task worker's declared command line is: one corpus
# of command lines runs under unit kind `task` and `flight`, and every row
# must reach its expected verdict, the same under both. The adversarial rows
# are a flight worker's attempts at an approval a task worker lacks. The
# root-skew rows: a command step only the brief's pinned root declares is
# deferred, not approved, by a guard that resolves its own root.
# tests/test-worker-command-guard.sh holds the suite's overview; all its files
# source tests/lib/worker-command-guard-harness.sh, which states the contract.
set -u
unset CDPATH
# shellcheck source=tests/lib/worker-command-guard-harness.sh
. "$(cd "$(dirname "$0")" && pwd)/lib/worker-command-guard-harness.sh"

TAB=$(printf '\t')
gitq() {
  GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 git -C "$1" -c user.name=t \
    -c user.email=t@example.invalid -c commit.gpgsign=false "${@:2}"
}

# The overlay stack the steps suite uses: a core root whose defaults leave
# every point empty, and a repo-tracked layer declaring command steps.
FX="$(cd "$SANDBOX" && pwd -P)/parity-fx"
WT="$FX/repo"
mkdir -p "$FX/core/config" "$WT/.claude/catalogs" "$WT/tools" "$FX/records" "$FX/claude"
GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 git init -q "$WT"
cp "$REPO_ROOT/config/steps.yaml" "$FX/core/config/steps.yaml"
{
  printf 'dispatch_isolation: per-unit\n'
  for p in pre-implementation pre-ci convergence pre-pr post-pr pre-ready-flip \
    pre-spec-ready-flip spec-drafted kickoff-signed-off unit-selected pre-dispatch \
    post-dispatch unit-halted post-merge orchestrator-idle; do
    printf 'steps_%s: []\n' "${p//-/_}"
  done
} >"$FX/core/config/defaults.yml"
for t in declared.sh other.sh; do
  printf '#!/bin/sh\nexit 0\n' >"$WT/tools/$t"
  chmod +x "$WT/tools/$t"
done
cp "$WT/tools/declared.sh" "$WT/tools/gh"
DECLARED="$WT/tools/declared.sh"
OTHER="$WT/tools/other.sh"
cat >"$WT/.claude/catalogs/steps.yaml" <<YAML
steps:
  - id: declared
    kind: command
    target: $DECLARED
    args: --mode strict
  - id: noargs
    kind: command
    target: $OTHER
  - id: ghwrite
    kind: command
    target: $WT/tools/gh
    args: pr ready 5
YAML
printf 'steps_pre_ci: [declared, ghwrite]\nsteps_post_pr: [noargs]\n' >"$WT/.claude/planwright.yml"
printf 'notes\n' >"$WT/notes.txt"
gitq "$WT" add -A
gitq "$WT" commit -q -m init
gitq "$WT" branch -M main
FX_ENV=("PLANWRIGHT_ROOT=$FX/core" "CLAUDE_PLUGIN_ROOT=$FX/core"
  "PLANWRIGHT_CONFIG_DEFAULTS=$FX/core/config/defaults.yml"
  "PLANWRIGHT_ADOPTER_OVERLAY=" "PLANWRIGHT_REPO_ROOT=$WT"
  "PLANWRIGHT_LOCAL_CONFIG=" "CLAUDE_DIR=$FX/claude" "PLANWRIGHT_GUARD_STEPS_DEADLINE=60")

# The unit branch each kind's launcher records, in policy-guard.sh's grammar.
branch_of() {
  case $1 in
    task) printf 'planwright/demo/task-1' ;;
    flight) printf 'planwright/flight/readme-typo-0123abcd' ;;
  esac
}
for k in task flight; do
  write_record "$FX/records/$k.rec" "$WT" own-branch "$(branch_of "$k")"
done

# ctx_prefix <kind> <branch> <point>: the twelve context assignments in the
# resolver's order, as a runner renders them for that unit kind: a task names
# its spec and task ids, a flight leaves both empty (its brief's mapping).
ctx_prefix() {
  local spec='demo' ids='1'
  [ "$1" = flight ] && spec='' ids=''
  printf "PLANWRIGHT_STEP_SPEC='%s' PLANWRIGHT_STEP_TASK_IDS='%s' PLANWRIGHT_STEP_UNIT_KIND='%s' PLANWRIGHT_STEP_BRANCH='%s' PLANWRIGHT_STEP_BASE_BRANCH='main' PLANWRIGHT_STEP_WORKTREE='%s' PLANWRIGHT_STEP_PR_NUMBER='' PLANWRIGHT_STEP_POINT='%s' PLANWRIGHT_STEP_ID='declared' PLANWRIGHT_STEP_PREV_RECORD='' PLANWRIGHT_STEP_PREV_HEAD='' PLANWRIGHT_STEP_NEW_HEAD=''" \
    "$spec" "$ids" "$1" "$2" "$WT" "$3"
}

# The corpus: <class> TAB <expected> TAB <label> TAB <command>, `@CTX@`
# replaced by the kind's context prefix at pre-ci, `@K@` by the kind, and
# `@B@` by its unit branch. `shared` rows are the declared lines and the
# shapes around them; `adversarial` rows are a flight worker's attempts.
CORPUS="$FX/corpus.tsv"
cat >"$CORPUS" <<EOF
shared${TAB}allow${TAB}a declared line${TAB}$DECLARED --mode strict
shared${TAB}allow${TAB}a declared line under the kind's context prefix${TAB}@CTX@ $DECLARED --mode strict
shared${TAB}allow${TAB}a declared no-args line${TAB}$OTHER
shared${TAB}allow${TAB}a declared line chained with a known-safe segment${TAB}$DECLARED --mode strict && git status
shared${TAB}allow${TAB}a declared line inside fish -c${TAB}fish -c '$DECLARED --mode strict'
shared${TAB}allow${TAB}a read-only git shape${TAB}git log --oneline -1
shared${TAB}allow${TAB}an own-branch stage${TAB}git add notes.txt
shared${TAB}allow${TAB}an own-branch commit${TAB}git commit -m 'x'
shared${TAB}defer${TAB}a declared line given another arg${TAB}$DECLARED --mode lax
shared${TAB}defer${TAB}a declared line plus an extra arg${TAB}$DECLARED --mode strict --extra
shared${TAB}defer${TAB}a declared location without its args${TAB}$DECLARED
shared${TAB}defer${TAB}a declared line with a write redirect${TAB}$DECLARED --mode strict > out
shared${TAB}defer${TAB}a declared line behind a non-context assignment${TAB}LD_PRELOAD=/x.so $DECLARED --mode strict
shared${TAB}defer${TAB}a declared line chained with a write outside the worktree${TAB}$DECLARED --mode strict; rm -rf $SANDBOX/outside
shared${TAB}defer${TAB}a declared line inside a substitution${TAB}echo \$($DECLARED --mode strict)
shared${TAB}defer${TAB}a declared reserved act${TAB}$WT/tools/gh pr ready 5
adversarial${TAB}defer${TAB}a push of the unit branch${TAB}git push origin @B@
adversarial${TAB}defer${TAB}a force push of the unit branch${TAB}git push --force origin @B@
adversarial${TAB}defer${TAB}a ready flip of the unit's PR${TAB}gh pr ready 5
adversarial${TAB}defer${TAB}a merge of the unit's PR${TAB}gh pr merge 5 --squash
adversarial${TAB}defer${TAB}a switch to the base branch${TAB}git switch main
adversarial${TAB}defer${TAB}a branch reset to the base${TAB}git reset --hard main
adversarial${TAB}defer${TAB}an amend on the unit branch${TAB}git commit --amend -m 'x'
adversarial${TAB}defer${TAB}the tower's force-push helper${TAB}$REPO_ROOT/scripts/tower-force-push.sh @B@
adversarial${TAB}defer${TAB}a context prefix naming a unit kind the resolver refuses${TAB}PLANWRIGHT_STEP_SPEC='' PLANWRIGHT_STEP_TASK_IDS='' PLANWRIGHT_STEP_UNIT_KIND='@K@-x' PLANWRIGHT_STEP_BRANCH='@B@' PLANWRIGHT_STEP_BASE_BRANCH='main' PLANWRIGHT_STEP_WORKTREE='$WT' PLANWRIGHT_STEP_PR_NUMBER='' PLANWRIGHT_STEP_POINT='pre-ci' PLANWRIGHT_STEP_ID='declared' PLANWRIGHT_STEP_PREV_RECORD='' PLANWRIGHT_STEP_PREV_HEAD='' PLANWRIGHT_STEP_NEW_HEAD='' $DECLARED --mode strict
adversarial${TAB}defer${TAB}a context prefix naming the unwired post-merge point${TAB}PLANWRIGHT_STEP_SPEC='' PLANWRIGHT_STEP_TASK_IDS='' PLANWRIGHT_STEP_UNIT_KIND='@K@' PLANWRIGHT_STEP_BRANCH='@B@' PLANWRIGHT_STEP_BASE_BRANCH='main' PLANWRIGHT_STEP_WORKTREE='$WT' PLANWRIGHT_STEP_PR_NUMBER='' PLANWRIGHT_STEP_POINT='post-merge' PLANWRIGHT_STEP_ID='declared' PLANWRIGHT_STEP_PREV_RECORD='' PLANWRIGHT_STEP_PREV_HEAD='' PLANWRIGHT_STEP_NEW_HEAD='' $DECLARED --mode strict
adversarial${TAB}defer${TAB}a step-context unit kind exported ahead of a declared line${TAB}PLANWRIGHT_STEP_UNIT_KIND=@K@ $DECLARED --mode strict
adversarial${TAB}defer${TAB}the flight dispatcher's resolver named by an environment root${TAB}\$PLANWRIGHT_ROOT/scripts/resolve-steps.sh pre-ci --line $DECLARED --mode strict
EOF

# verdict_of <command>: `allow` or `defer` from one hook run; anything else
# (a non-zero exit, a deny or ask) is `broken`.
verdict_of() {
  run_hook "$1" Bash "$WT"
  if [ "$CODE" -ne 0 ] || has_deny_or_ask; then
    printf 'broken'
  elif is_allow; then
    printf 'allow'
  elif is_empty; then
    printf 'defer'
  else
    printf 'broken'
  fi
}

# corpus_verdicts <kind> <out>: every row's verdict under that unit kind,
# written as <label> TAB <verdict>: the kind's session record handed in, the
# worktree on the kind's unit branch, and the step-context unit kind in the
# hook's environment as a runner exports it.
corpus_verdicts() {
  local kind=$1 out=$2 b cls want label cmd
  b=$(branch_of "$kind")
  gitq "$WT" checkout -q -B "$b" main
  HOOK_ENV=("${FX_ENV[@]}" "PLANWRIGHT_WORKER_SESSION_RECORD=$FX/records/$kind.rec"
    "PLANWRIGHT_STEP_UNIT_KIND=$kind")
  : >"$out"
  while IFS=$TAB read -r cls want label cmd; do
    cmd=${cmd//@CTX@/$(ctx_prefix "$kind" "$b" pre-ci)}
    cmd=${cmd//@K@/$kind}
    cmd=${cmd//@B@/$b}
    printf '%s\t%s\t%s\t%s\n' "$cls" "$want" "$label" "$(verdict_of "$cmd")" >>"$out"
  done <"$CORPUS"
  HOOK_ENV=()
}

# kinds_differ <task-out> <flight-out>: print each row whose verdicts differ
# between the kinds; non-zero when either run is not the whole corpus.
kinds_differ() {
  local rows
  rows=$(wc -l <"$CORPUS" | tr -d ' ')
  [ "$(wc -l <"$1" | tr -d ' ')" = "$rows" ] && [ "$(wc -l <"$2" | tr -d ' ')" = "$rows" ] || return 1
  paste -d "$TAB" "$1" "$2" | awk -F"$TAB" '$4 != $8 { print $3 ": task " $4 ", flight " $8 }'
}

check_rows() {
  local out=$1 kind=$2 cls want label got
  while IFS=$TAB read -r cls want label got; do
    if [ "$got" = "$want" ]; then
      pass "$kind ($cls): $label"
    elif [ "$got" = allow ]; then
      fail "$kind ($cls): $label — FALSE-ALLOW: expected DEFER, hook approved it"
      false_allows=$((false_allows + 1))
    else
      fail "$kind ($cls): $label — expected $want, got $got"
    fi
  done <"$out"
}

echo "### REQ-C1.10 — one corpus, identical verdicts under task and flight"
corpus_verdicts task "$FX/v-task"
corpus_verdicts flight "$FX/v-flight"
check_rows "$FX/v-task" task
check_rows "$FX/v-flight" flight
if ! diffs=$(kinds_differ "$FX/v-task" "$FX/v-flight"); then
  fail "the corpus did not run whole under both kinds"
elif [ -n "$diffs" ]; then
  fail "the unit kinds' verdicts differ: $diffs"
else
  pass "the corpus yields identical verdicts under unit kinds task and flight"
fi
# The adversarial rows keep a flight worker to a task worker's approvals: no
# row a task worker defers is approved for a flight worker.
widened=$(paste -d "$TAB" "$FX/v-task" "$FX/v-flight" | awk -F"$TAB" '$4 == "defer" && $8 == "allow" { print $3 }')
if [ -z "$widened" ]; then
  pass "REQ-C1.10: a flight worker gains no approval a task worker lacks"
else
  fail "REQ-C1.10: approvals only a flight worker gets: $widened"
fi

# The comparison checks itself against a guard that approves only for a
# flight: a parity check that cannot fail reads exactly like a green one.
REAL_HOOK=$HOOK
mkdir -p "$FX/kind-biased/scripts"
cat >"$FX/kind-biased/scripts/worker-command-guard.sh" <<'STUB'
#!/bin/bash
[ "${PLANWRIGHT_STEP_UNIT_KIND:-}" = flight ] || exit 0
printf '%s\n' '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow","permissionDecisionReason":"t"}}'
STUB
HOOK="$FX/kind-biased/scripts/worker-command-guard.sh"
corpus_verdicts task "$FX/b-task"
corpus_verdicts flight "$FX/b-flight"
HOOK=$REAL_HOOK
if diffs=$(kinds_differ "$FX/b-task" "$FX/b-flight") && [ -n "$diffs" ]; then
  pass "self-check: the comparison catches a guard that approves only for a flight"
else
  fail "self-check: the comparison passed a guard that approves only for a flight"
fi

echo "### D-19 — root skew: a step only the pinned root declares is deferred"
# Two installed roots, each a runnable copy: the guard's own and the one a
# brief pins, whose core catalog alone declares a command step. The launch
# exports the pinned root as PLANWRIGHT_ROOT and CLAUDE_PLUGIN_ROOT. The step's
# target lies outside any root's scripts/, so only the declared-line path can
# approve it.
install_root() {
  mkdir -p "$1"
  cp -R "$REPO_ROOT/scripts" "$REPO_ROOT/skills" "$REPO_ROOT/config" "$REPO_ROOT/doctrine" \
    "$REPO_ROOT/.claude-plugin" "$1/"
}
SK="$FX/skew"
PINNED="$SK/pinned"
OWN="$SK/own"
mkdir -p "$SK/tools" "$SK/repo"
GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 git init -q "$SK/repo"
printf '#!/bin/sh\nexit 0\n' >"$SK/tools/pinned-tool.sh"
chmod +x "$SK/tools/pinned-tool.sh"
install_root "$PINNED"
install_root "$OWN"
printf '  - id: pinned-tool\n    kind: command\n    target: %s\n' "$SK/tools/pinned-tool.sh" >>"$PINNED/config/steps.yaml"
sed 's/^steps_pre_ci:.*/steps_pre_ci: [pinned-tool]/' "$REPO_ROOT/config/defaults.yml" >"$PINNED/config/defaults.yml"
grep -qx 'steps_pre_ci: \[pinned-tool\]' "$PINNED/config/defaults.yml" \
  || fail "fixture: the pinned root's core list does not name its step"
SKEW_LINE="$SK/tools/pinned-tool.sh"
for k in task flight; do
  SKEW_ENV=("PLANWRIGHT_ROOT=$PINNED" "CLAUDE_PLUGIN_ROOT=$PINNED" "PLANWRIGHT_ADOPTER_OVERLAY="
    "PLANWRIGHT_LOCAL_CONFIG=" "CLAUDE_DIR=$SK/claude" "PLANWRIGHT_GUARD_STEPS_DEADLINE=60"
    "PLANWRIGHT_STEP_UNIT_KIND=$k")
  # Unskewed, the pinned root's own guard approves its step's line: the shape
  # is a declared line's, so a deferral below is the skew's.
  HOOK="$PINNED/scripts/worker-command-guard.sh"
  HOOK_ENV=("${SKEW_ENV[@]}")
  assert_allow "$k: the pinned root's own guard approves its declared step" "$SKEW_LINE" Bash "$SK/repo"
  HOOK="$OWN/scripts/worker-command-guard.sh"
  HOOK_ENV=("${SKEW_ENV[@]}")
  assert_defer "$k: under root skew a step only the pinned root declares is deferred, not approved" \
    "$SKEW_LINE" Bash "$SK/repo"
  HOOK=$REAL_HOOK
done

finish_suite worker-command-guard-parity
