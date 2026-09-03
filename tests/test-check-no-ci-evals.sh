#!/bin/bash
# Tests for scripts/check-no-ci-evals.sh — the standing CI-exclusion guard. The
# kept eval harnesses must never run in GitHub CI (cost, nondeterministic
# gating, and an API-key requirement in a public repo), and the guard enforces
# that structurally rather than relying on the eval tasks staying absent from
# the `check` aggregate. Three passes are covered here: the workflow-text scan,
# the mise task-graph closure from the CI-invoked roots, and the run-body scan
# that feeds that closure. Workflow files and mise.toml are PR-controllable, so
# the guard treats their contents as untrusted data (grep and awk over text; no
# eval, no path expansion).
set -u
unset CDPATH

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GUARD="$REPO_ROOT/scripts/check-no-ci-evals.sh"

failures=0
assert_exit() {
  # assert_exit <label> <expected-exit> <actual-exit>
  if [ "$2" -eq "$3" ]; then
    echo "ok: $1"
  else
    echo "FAIL: $1 (expected exit $2, got $3)" >&2
    failures=$((failures + 1))
  fi
}
assert_contains() {
  # assert_contains <label> <needle> <haystack>
  case "$3" in
    *"$2"*) echo "ok: $1" ;;
    *)
      echo "FAIL: $1 (missing '$2')" >&2
      echo "----- output -----" >&2
      printf '%s\n' "$3" >&2
      echo "------------------" >&2
      failures=$((failures + 1))
      ;;
  esac
}

if [ ! -f "$GUARD" ]; then
  echo "FAIL: guard script missing at $GUARD" >&2
  exit 1
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# The workflow-text pass in isolation. An absent mise.toml leaves the two graph
# passes with no graph to close over, so these cases exercise the text scan
# alone and stay unaffected by whatever mise.toml the runner's cwd happens to
# hold.
text_only() { "$GUARD" "$1" "$TMP/no-such-mise.toml" 2>&1; }

# A benign workflow: the aggregate gate only, no eval task wired in.
mk_benign() {
  dir="$1"
  mkdir -p "$dir"
  cat >"$dir/ci.yml" <<'EOF'
name: ci
"on":
  pull_request:
jobs:
  check:
    runs-on: ubuntu-latest
    steps:
      - run: mise run check
      - run: mise run lint:shell
EOF
}

# ---- benign workflow set passes ----
mk_benign "$TMP/benign"
out="$(text_only "$TMP/benign")"
assert_exit "benign workflow set passes" 0 $?

# ---- `mise run eval:skill` in a workflow fails, names the file ----
mkdir -p "$TMP/wired1"
cat >"$TMP/wired1/evals.yml" <<'EOF'
name: nightly-evals
"on":
  schedule:
    - cron: "0 3 * * *"
jobs:
  eval:
    runs-on: ubuntu-latest
    steps:
      - run: mise run eval:skill
EOF
out="$(text_only "$TMP/wired1")"
rc=$?
assert_exit "mise run eval:skill wired in CI fails" 1 "$rc"
assert_contains "names the offending workflow file" "evals.yml" "$out"

# ---- bare `mise eval:skill` (no run subcommand) also fails ----
mkdir -p "$TMP/wired2"
cat >"$TMP/wired2/ci.yml" <<'EOF'
name: ci
"on": [push]
jobs:
  check:
    steps:
      - run: mise eval:skill
EOF
out="$(text_only "$TMP/wired2")"
assert_exit "bare mise eval:skill wired in CI fails" 1 $?

# ---- a future eval task under the eval: namespace also fails ----
mkdir -p "$TMP/wired3"
cat >"$TMP/wired3/ci.yml" <<'EOF'
name: ci
"on": [push]
jobs:
  check:
    steps:
      - run: mise run eval:corpus
EOF
out="$(text_only "$TMP/wired3")"
assert_exit "any eval: namespace task wired in CI fails" 1 $?

# ---- the `run` alias `mise r eval:` must not bypass the guard ----
mkdir -p "$TMP/alias"
cat >"$TMP/alias/ci.yml" <<'EOF'
name: ci
"on": [push]
jobs:
  check:
    steps:
      - run: mise r eval:skill
EOF
out="$(text_only "$TMP/alias")"
assert_exit "mise r eval:skill (run alias) is caught" 1 $?

# ---- a flag between `run` and the task must not bypass the guard ----
mkdir -p "$TMP/flag"
cat >"$TMP/flag/ci.yml" <<'EOF'
name: ci
"on": [push]
jobs:
  check:
    steps:
      - run: mise run --verbose eval:skill
EOF
out="$(text_only "$TMP/flag")"
assert_exit "mise run --verbose eval:skill is caught" 1 $?

# ---- a quoted task name must not bypass the guard ----
mkdir -p "$TMP/quoted"
cat >"$TMP/quoted/ci.yml" <<'EOF'
name: ci
"on": [push]
jobs:
  check:
    steps:
      - run: mise run "eval:skill"
EOF
out="$(text_only "$TMP/quoted")"
assert_exit "mise run \"eval:skill\" (quoted) is caught" 1 $?

# ---- invoking the runner script directly must not bypass the guard ----
mkdir -p "$TMP/direct"
cat >"$TMP/direct/ci.yml" <<'EOF'
name: ci
"on": [push]
jobs:
  check:
    steps:
      - run: sh scripts/prompt-eval.sh --suite tests/prompt-evals/fixtures
EOF
out="$(text_only "$TMP/direct")"
rc=$?
assert_exit "direct sh scripts/prompt-eval.sh is caught" 1 "$rc"
assert_contains "names the direct-runner offender" "direct/ci.yml" "$out"

# ---- the behavioral-eval harness is covered too (not only prompt-eval) ----
mkdir -p "$TMP/behav-task"
cat >"$TMP/behav-task/ci.yml" <<'EOF'
name: ci
"on": [push]
jobs:
  check:
    steps:
      - run: mise run eval:behavioral
EOF
out="$(text_only "$TMP/behav-task")"
assert_exit "mise run eval:behavioral wired in CI fails" 1 "$?"

mkdir -p "$TMP/behav-direct"
cat >"$TMP/behav-direct/ci.yml" <<'EOF'
name: ci
"on": [push]
jobs:
  check:
    steps:
      - run: sh scripts/behavioral-eval.sh --suite tests/behavioral-evals/fixtures
EOF
out="$(text_only "$TMP/behav-direct")"
rc=$?
assert_exit "direct sh scripts/behavioral-eval.sh is caught" 1 "$rc"
assert_contains "names the behavioral-eval offender" "behav-direct/ci.yml" "$out"

# ---- the TEST script name (test-behavioral-eval.sh) is NOT a false positive ----
# CI legitimately runs the eval harness's own tests via the tests/*.sh glob; the
# runner-name match is anchored at a token boundary so the `test-` prefix does
# not trip the guard.
mkdir -p "$TMP/testname"
cat >"$TMP/testname/ci.yml" <<'EOF'
name: ci
"on": [push]
jobs:
  check:
    steps:
      - run: bash tests/test-behavioral-eval.sh
      - run: bash tests/test-prompt-eval-runner.sh
EOF
out="$(text_only "$TMP/testname")"
assert_exit "the eval harness TEST scripts are not flagged as runners" 0 "$?"

# ---- a benign task whose name merely contains 'eval' is NOT flagged ----
# `evaluate-release` is not in the `eval:` namespace; a substring match would
# be a false positive that blocks legitimate task names.
mkdir -p "$TMP/falsepos"
cat >"$TMP/falsepos/ci.yml" <<'EOF'
name: ci
"on": [push]
jobs:
  check:
    steps:
      - run: mise run evaluate-release
      - run: echo "retrieval eval discussion in a comment is fine"
EOF
out="$(text_only "$TMP/falsepos")"
assert_exit "non-eval-namespace task named *eval* is not flagged" 0 $?

# ---- a namespace whose name ENDS in 'eval' is NOT flagged ----
# `retrieval:`, `medieval:` contain the substring `eval:` but are not the eval
# namespace (eval must sit at a token boundary). This is the regression the
# token-boundary match fixes.
mkdir -p "$TMP/retrieval"
cat >"$TMP/retrieval/ci.yml" <<'EOF'
name: ci
"on": [push]
jobs:
  check:
    steps:
      - run: mise run retrieval:index
      - run: mise run medieval:build
EOF
out="$(text_only "$TMP/retrieval")"
rc=$?
assert_exit "a namespace ending in 'eval' (retrieval:) is not flagged" 0 "$rc"

# ---- a word ENDING in 'mise' (premise) is NOT a mise invocation ----
# `grep 'mise[[:space:]]'` matches `premise ` as a substring; without a leading
# token boundary a benign line that merely contains the word `premise` AND an
# `eval:` mention (e.g. a prose comment) false-positives and spuriously fails CI.
# `mise` must sit at a token boundary, same as the `eval:` stage.
mkdir -p "$TMP/premise"
cat >"$TMP/premise/ci.yml" <<'EOF'
name: ci
"on": [push]
jobs:
  check:
    steps:
      # our premise here: the eval: namespace stays manual-only, never CI
      - run: mise run check
EOF
out="$(text_only "$TMP/premise")"
rc=$?
assert_exit "a word ending in 'mise' (premise) is not flagged" 0 "$rc"

# ---- no workflow directory: vacuously clean ----
out="$(text_only "$TMP/does-not-exist")"
assert_exit "absent workflow dir passes vacuously" 0 $?

# ---------------------------------------------------------------------------
# Task-graph closure and run-body passes.
#
# Each case pairs a synthetic mise.toml with a workflow whose only mise
# invocation is `mise run check`, so `check` is the sole CI-invoked root and
# nothing the text pass matches on can account for the verdict.
# ---------------------------------------------------------------------------

mk_case() {
  # mk_case <name>  — writes the shared workflow; the caller writes mise.toml.
  mkdir -p "$TMP/$1/workflows"
  cat >"$TMP/$1/workflows/ci.yml" <<'EOF'
name: ci
"on": [push]
jobs:
  check:
    runs-on: ubuntu-latest
    steps:
      - run: mise run check
EOF
}
run_case() { "$GUARD" "$TMP/$1/workflows" "$TMP/$1/mise.toml" 2>&1; }

# ---- transitive `depends` chain from a CI-run task reaches eval: ----
mk_case depends-chain
cat >"$TMP/depends-chain/mise.toml" <<'EOF'
[tasks.check]
depends = ["lint:shell"]

[tasks."lint:shell"]
depends = ["eval:skill"]
run = "shellcheck scripts/*.sh"

[tasks."eval:skill"]
run = "/bin/sh scripts/prompt-eval.sh --suite tests/prompt-evals/fixtures"
EOF
out="$(run_case depends-chain)"
rc=$?
assert_exit "transitive depends chain to eval: fails" 1 "$rc"
assert_contains "names the eval task it reached" "eval:skill" "$out"
assert_contains "reports the chain from the CI-invoked root" "check" "$out"

# ---- `depends_post` is an edge too ----
mk_case depends-post-chain
cat >"$TMP/depends-post-chain/mise.toml" <<'EOF'
[tasks.check]
depends_post = ["report"]
run = "true"

[tasks.report]
depends = ["eval:behavioral"]
run = "true"

[tasks."eval:behavioral"]
run = "true"
EOF
out="$(run_case depends-post-chain)"
rc=$?
assert_exit "transitive depends_post chain to eval: fails" 1 "$rc"
assert_contains "names the eval task reached via depends_post" "eval:behavioral" "$out"

# ---- `wait_for` is an edge too ----
mk_case wait-for-chain
cat >"$TMP/wait-for-chain/mise.toml" <<'EOF'
[tasks.check]
wait_for = ["publish"]
run = "true"

[tasks.publish]
depends = ["eval:skill"]
run = "true"

[tasks."eval:skill"]
run = "true"
EOF
out="$(run_case wait-for-chain)"
rc=$?
assert_exit "transitive wait_for chain to eval: fails" 1 "$rc"
assert_contains "names the eval task reached via wait_for" "eval:skill" "$out"

# ---- a wildcard dependency onto the eval: namespace is caught ----
# mise expands `eval:*`, so an exact-name edge lookup alone would let this
# through even though it wires every eval task into the aggregate.
mk_case glob-dep
cat >"$TMP/glob-dep/mise.toml" <<'EOF'
[tasks.check]
depends = ["eval:*"]
run = "true"

[tasks."eval:skill"]
run = "true"
EOF
out="$(run_case glob-dep)"
rc=$?
assert_exit "a wildcard depends onto eval:* fails" 1 "$rc"
assert_contains "names the eval task the wildcard expands to" "eval:skill" "$out"

# ---- a dependency on an eval task defined outside the parse boundary ----
# The edge resolves to nothing in this file, so only the dependency's own name
# is left to read.
mk_case dangling-eval-dep
cat >"$TMP/dangling-eval-dep/mise.toml" <<'EOF'
[tasks.check]
depends = ["eval:skill"]
run = "true"
EOF
out="$(run_case dangling-eval-dep)"
rc=$?
assert_exit "a depends on an undefined eval: task fails" 1 "$rc"
assert_contains "names the unresolvable eval dependency" "eval:skill" "$out"

# ---- a reachable task whose run body invokes an eval task ----
# The invoked task is not defined in this mise.toml, so only the run-body
# invocation-form match can catch it.
mk_case run-body-direct
cat >"$TMP/run-body-direct/mise.toml" <<'EOF'
[tasks.check]
depends = ["report"]
run = "true"

[tasks.report]
run = '''
set -e
mise run eval:skill
'''
EOF
out="$(run_case run-body-direct)"
rc=$?
assert_exit "a reachable run body invoking mise run eval: fails" 1 "$rc"
assert_contains "names the task whose run body wires it in" "report" "$out"

# ---- a reachable task whose run body calls the eval runner directly ----
mk_case run-body-runner
cat >"$TMP/run-body-runner/mise.toml" <<'EOF'
[tasks.check]
depends = ["report"]
run = "true"

[tasks.report]
run = "/bin/sh scripts/behavioral-eval.sh --suite tests/behavioral-evals/fixtures"
EOF
out="$(run_case run-body-runner)"
rc=$?
assert_exit "a reachable run body calling the eval runner directly fails" 1 "$rc"

# ---- second order: a run-body invocation feeds the closure as an edge ----
mk_case run-body-second-order
cat >"$TMP/run-body-second-order/mise.toml" <<'EOF'
[tasks.check]
run = "mise run bundle"

[tasks.bundle]
depends = ["eval:skill"]
run = "true"

[tasks."eval:skill"]
run = "true"
EOF
out="$(run_case run-body-second-order)"
rc=$?
assert_exit "a run-body invocation feeding a depends chain to eval: fails" 1 "$rc"
assert_contains "names the eval task reached through the run-body edge" "eval:skill" "$out"

# ---- an eval task nothing CI-invoked reaches is fine ----
# The shape of the real repo: the eval: namespace exists, and stays outside the
# closure of every CI-invoked task.
mk_case unreachable-eval
cat >"$TMP/unreachable-eval/mise.toml" <<'EOF'
[tasks.check]
depends = [
  "test",
  "lint:shell",
]
run = "true"

[tasks.test]
run = "/bin/bash scripts/run-tests.sh"

[tasks."lint:shell"]
run = "shellcheck scripts/*.sh"

[tasks."eval:skill"]
description = "on demand only, never in CI"
run = "/bin/sh scripts/prompt-eval.sh --suite tests/prompt-evals/fixtures"
EOF
out="$(run_case unreachable-eval)"
rc=$?
assert_exit "a clean graph with an unreachable eval task passes" 0 "$rc"

# ---- an unparseable mise.toml fails closed ----
mk_case unparseable
cat >"$TMP/unparseable/mise.toml" <<'EOF'
[tasks.check]
run = '''
echo never terminated
EOF
out="$(run_case unparseable)"
rc=$?
assert_exit "an unparseable mise.toml fails closed" 1 "$rc"
assert_contains "says it could not parse the task graph" "parse" "$out"

# ---- a mise.toml that parses to zero tasks fails closed ----
mk_case zero-tasks
cat >"$TMP/zero-tasks/mise.toml" <<'EOF'
[tools]
shellcheck = "0.11.0"
EOF
out="$(run_case zero-tasks)"
rc=$?
assert_exit "a zero-task mise.toml fails closed" 1 "$rc"
assert_contains "says the graph held no tasks" "zero task" "$out"

# ---- workflows that invoke no known mise task fail closed ----
# Zero roots means the closure would pass vacuously over the whole graph, which
# is indistinguishable from the root extraction having broken.
mkdir -p "$TMP/zero-roots/workflows"
cat >"$TMP/zero-roots/workflows/ci.yml" <<'EOF'
name: ci
"on": [push]
jobs:
  check:
    steps:
      - run: mise run not-a-task
EOF
cat >"$TMP/zero-roots/mise.toml" <<'EOF'
[tasks.check]
run = "true"

[tasks."eval:skill"]
run = "true"
EOF
out="$(run_case zero-roots)"
rc=$?
assert_exit "zero workflow roots with a non-empty graph fails closed" 1 "$rc"
assert_contains "says no CI-invoked task was found" "root" "$out"

# ---- an absent mise.toml leaves the graph passes with nothing to close ----
mk_case absent-mise
out="$(run_case absent-mise)"
rc=$?
assert_exit "an absent mise.toml passes with the graph passes skipped" 0 "$rc"
assert_contains "says the graph passes were skipped" "mise.toml" "$out"

# ---- --help documents the passes and the parse boundary ----
out="$("$GUARD" --help 2>&1)"
rc=$?
assert_exit "--help exits clean" 0 "$rc"
assert_contains "--help documents the workflow-text pass" "WORKFLOW-TEXT" "$out"
assert_contains "--help documents the task-graph closure pass" "TASK-GRAPH CLOSURE" "$out"
assert_contains "--help documents the run-body pass" "RUN-BODY" "$out"
assert_contains "--help documents the parse boundary" "PARSE BOUNDARY" "$out"

# ---- the REAL repo workflow set and task graph pass ----
out="$("$GUARD" "$REPO_ROOT/.github/workflows" "$REPO_ROOT/mise.toml" 2>&1)"
rc=$?
assert_exit "real repo workflow set and task graph pass" 0 "$rc"

# ---- default args resolve to .github/workflows and mise.toml ----
out="$(cd "$REPO_ROOT" && "$GUARD" 2>&1)"
assert_exit "defaults pass on the real repo" 0 $?

if [ "$failures" -ne 0 ]; then
  echo "$failures test(s) failed" >&2
  exit 1
fi
echo "all check-no-ci-evals tests passed"
