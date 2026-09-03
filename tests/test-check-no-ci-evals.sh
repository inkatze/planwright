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
#
# Assertion discipline this file learned the hard way: a needle must not be
# satisfiable by the fixture PATH the guard echoes back, nor by the
# `check-no-ci-evals:` prefix every message carries. Needles below are phrases
# only the intended verdict produces.
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
assert_lacks() {
  # assert_lacks <label> <needle> <haystack>
  case "$3" in
    *"$2"*)
      echo "FAIL: $1 (unexpectedly contains '$2')" >&2
      echo "----- output -----" >&2
      printf '%s\n' "$3" >&2
      echo "------------------" >&2
      failures=$((failures + 1))
      ;;
    *) echo "ok: $1" ;;
  esac
}

if [ ! -f "$GUARD" ]; then
  echo "FAIL: guard script missing at $GUARD" >&2
  exit 1
fi

TMP="$(mktemp -d)" || {
  echo "FAIL: mktemp -d failed; cannot build fixtures" >&2
  exit 1
}
trap 'rm -rf "$TMP"' EXIT INT TERM HUP

# The workflow-text pass in isolation. `-` is the guard's documented "no task
# graph" argument, so these cases exercise the text scan alone.
text_only() { "$GUARD" "$1" - 2>&1; }

# Runs the guard keeping the two streams apart, so the "verdicts go to stderr"
# contract is testable rather than assumed.
OUT=""
ERR=""
RC=0
run_split() {
  OUT="$("$@" 2>"$TMP/.stderr")"
  RC=$?
  ERR="$(cat "$TMP/.stderr")"
}

# A benign workflow: the aggregate gate only, no eval task wired in.
mk_benign() {
  mkdir -p "$1"
  cat >"$1/ci.yml" <<'EOF'
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
assert_contains "says the eval task is wired into a workflow" "wired into a CI workflow" "$out"

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

# ---- a NUL byte must not let grep report the file as binary and skip it ----
mkdir -p "$TMP/nul"
printf 'jobs:\n  a:\n    steps:\n      - run: mise run check\n\000\n      - run: mise run eval:skill\n' \
  >"$TMP/nul/ci.yml"
out="$(text_only "$TMP/nul")"
rc=$?
assert_exit "a NUL byte in a workflow does not blind the text pass" 1 "$rc"
assert_contains "still names the eval wiring past the NUL" "wired into a CI workflow" "$out"

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
out="$("$GUARD" "$TMP/does-not-exist" - 2>&1)"
rc=$?
assert_exit "an absent default workflow dir is a usage error when passed" 2 "$rc"

# ---------------------------------------------------------------------------
# Task-graph closure and run-body passes.
#
# Each case pairs a synthetic mise.toml with a workflow whose only mise
# invocation is `mise run check`, so `check` is the sole CI-invoked root and
# nothing the text pass matches on can account for the verdict.
# ---------------------------------------------------------------------------

mk_case() {
  # mk_case <name> — writes the shared workflow; the caller writes mise.toml.
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
# The eval task's run body is inert, so only pass 2 can produce this verdict.
mk_case depends-chain
cat >"$TMP/depends-chain/mise.toml" <<'EOF'
[tasks.check]
depends = ["lint:shell"]

[tasks."lint:shell"]
depends = ["eval:skill"]
run = "shellcheck scripts/*.sh"

[tasks."eval:skill"]
run = "true"
EOF
out="$(run_case depends-chain)"
rc=$?
assert_exit "transitive depends chain to eval: fails" 1 "$rc"
assert_contains "names the eval task it reached" "CI reaches eval task eval:skill" "$out"
assert_contains "renders the chain with its edge kinds" \
  "check -(depends)-> lint:shell -(depends)-> eval:skill" "$out"
assert_contains "roots the chain at the workflow line" "workflows/ci.yml:7 invokes" "$out"

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
assert_contains "labels the depends_post edge" "check -(depends_post)-> report" "$out"

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
assert_contains "labels the wait_for edge" "check -(wait_for)-> publish" "$out"

# ---- `depends` as a bare string, not an array ----
mk_case scalar-depends
cat >"$TMP/scalar-depends/mise.toml" <<'EOF'
[tasks.check]
depends = "eval:skill"
run = "true"

[tasks."eval:skill"]
run = "true"
EOF
out="$(run_case scalar-depends)"
rc=$?
assert_exit "a scalar depends string is followed" 1 "$rc"
assert_contains "names the eval task from a scalar depends" "CI reaches eval task eval:skill" "$out"

# ---- a multi-line array survives comments, nesting, and brackets in strings ----
# Closing the array on the first line holding any `]` would drop every element
# after it, which is a silent bypass rather than a parse failure.
mk_case array-shapes
cat >"$TMP/array-shapes/mise.toml" <<'EOF'
[tasks.check]
depends = [
  "build", # the fast ones ] first
  ["lint", "--fix"],
  "eval:skill",
]
run = "true"

[tasks.build]
run = "true"

[tasks.lint]
run = "true"

[tasks."eval:skill"]
run = "true"
EOF
out="$(run_case array-shapes)"
rc=$?
assert_exit "a bracket in a comment or a nested array does not truncate depends" 1 "$rc"
assert_contains "still reaches the element after the bracket" "CI reaches eval task eval:skill" "$out"

# ---- whitespace inside a table header must not hide the task ----
mk_case header-whitespace
cat >"$TMP/header-whitespace/mise.toml" <<'EOF'
[tasks.check]
depends = ["build"]

[ tasks.build ]
depends = ["eval:skill"]
run = "true"

[tasks."eval:skill"]
run = "true"
EOF
out="$(run_case header-whitespace)"
rc=$?
assert_exit "a header with interior whitespace still defines its task" 1 "$rc"
assert_contains "walks through the whitespace-header task" "check -(depends)-> build" "$out"

# ---- TOML's permitted whitespace and quoting around the dot ----
mk_case header-dot-spacing
cat >"$TMP/header-dot-spacing/mise.toml" <<'EOF'
[tasks.check]
depends = ["build", "publish"]

[tasks . build]
depends = ["eval:skill"]
run = "true"

["tasks".publish]
run = "true"

[tasks."eval:skill"]
run = "true"
EOF
out="$(run_case header-dot-spacing)"
rc=$?
assert_exit "a spaced or quoted dotted header still defines its task" 1 "$rc"
assert_contains "walks through the spaced-header task" "check -(depends)-> build" "$out"

# ---- whitespace around a quoted header segment is not part of the name ----
mk_case header-quoted-spacing
cat >"$TMP/header-quoted-spacing/mise.toml" <<'EOF'
[tasks.check]
depends = ["ci-gate"]
run = "true"

[tasks . "ci-gate"]
depends = ["eval:skill"]
run = "true"

[tasks."eval:skill"]
run = "true"
EOF
out="$(run_case header-quoted-spacing)"
rc=$?
assert_exit "a spaced quoted header name still resolves its edge" 1 "$rc"
assert_contains "walks into the quoted-header task" "check -(depends)-> ci-gate" "$out"

# ---- an escaped header name resolves against a plainly written dependency ----
mk_case header-escaped-name
cat >"$TMP/header-escaped-name/mise.toml" <<'EOF'
[tasks.check]
depends = ["ci-gate"]
run = "true"

[tasks."\u0063i-gate"]
depends = ["eval:skill"]
run = "true"

[tasks."eval:skill"]
run = "true"
EOF
out="$(run_case header-escaped-name)"
rc=$?
assert_exit "an escaped header name resolves its edge" 1 "$rc"
assert_contains "walks into the escaped-header task" "check -(depends)-> ci-gate" "$out"

# ---- a non-ASCII escape resolves to the task it names ----
# The C locale makes awk byte-oriented, so the codepoint has to be re-spelled
# as UTF-8 or the decoded name matches nothing.
mk_case wide-escape
cat >"$TMP/wide-escape/mise.toml" <<'EOF'
[tasks.check]
depends = ["\u00e9tape"]
run = "true"

[tasks."étape"]
depends = ["eval:skill"]
run = "true"

[tasks."eval:skill"]
run = "true"
EOF
out="$(run_case wide-escape)"
rc=$?
assert_exit "a non-ASCII escape resolves to its task" 1 "$rc"
assert_contains "walks the escaped non-ASCII name" "check -(depends)-> étape" "$out"

# ---- a task defined by a dotted key is a parse failure, never half-read ----
mk_case dotted-key
cat >"$TMP/dotted-key/mise.toml" <<'EOF'
tasks.build.run = "mise run eval:skill"

[tasks.check]
depends = ["build"]
run = "true"
EOF
out="$(run_case dotted-key)"
rc=$?
assert_exit "a dotted-key task definition fails closed" 1 "$rc"
assert_contains "says the task definition is not modeled" "is not modeled" "$out"

# ---- a multi-line string under a non-run key must not desynchronize the parse ----
mk_case multiline-description
cat >"$TMP/multiline-description/mise.toml" <<'EOF'
[tasks.check]
description = """
Example:
  [tasks.foo]
"""
depends = ["eval:skill"]
run = "true"

[tasks."eval:skill"]
run = "true"
EOF
out="$(run_case multiline-description)"
rc=$?
assert_exit "a multi-line description does not swallow the task's depends" 1 "$rc"
assert_contains "still sees the depends after the description body" "CI reaches eval task eval:skill" "$out"

# ---- a UTF-8 BOM must not hide the first table header ----
mk_case bom
printf '\357\273\277[tasks.check]\ndepends = ["eval:skill"]\nrun = "true"\n\n[tasks."eval:skill"]\nrun = "true"\n' \
  >"$TMP/bom/mise.toml"
out="$(run_case bom)"
rc=$?
assert_exit "a BOM does not hide the first task" 1 "$rc"
assert_contains "reaches the eval task past the BOM" "CI reaches eval task eval:skill" "$out"

# ---- wildcard dependencies onto the eval: namespace are caught ----
# mise expands these, so an exact-name edge lookup alone would let them through.
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
assert_contains "names the eval task the wildcard expands to" "CI reaches eval task eval:skill" "$out"

# A wildcard with no colon, and the catch-all, expand over tasks defined
# outside this file too, so the name is the only honest test.
mk_case glob-dep-prefix
cat >"$TMP/glob-dep-prefix/mise.toml" <<'EOF'
[tasks.check]
depends = ["eval*"]
run = "true"

[tasks.build]
run = "true"
EOF
out="$(run_case glob-dep-prefix)"
rc=$?
assert_exit "a colon-less eval* wildcard fails" 1 "$rc"
assert_contains "reports the wildcard dependency" "can name the eval: namespace" "$out"

mk_case glob-dep-all
cat >"$TMP/glob-dep-all/mise.toml" <<'EOF'
[tasks.check]
depends = ["*"]
run = "true"

[tasks.lint]
run = "true"
EOF
out="$(run_case glob-dep-all)"
assert_exit "a catch-all depends wildcard fails" 1 $?

# ---- a wildcard reaching a future eval task by shape is caught ----
mk_case glob-dep-suffix
cat >"$TMP/glob-dep-suffix/mise.toml" <<'EOF'
[tasks.check]
depends = ["*:skill"]
run = "true"

[tasks.build]
run = "true"
EOF
out="$(run_case glob-dep-suffix)"
rc=$?
assert_exit "a suffix wildcard reaching eval:skill fails" 1 "$rc"
assert_contains "reports it as a wildcard that can name the namespace" "can name the eval: namespace" "$out"

# ---- a wildcard that cannot name the namespace is not flagged ----
# `lint:` diverges from `eval:` at the first character, so no expansion of it
# can land in the namespace. Flagging it would block a normal aggregate.
mk_case glob-dep-clear
cat >"$TMP/glob-dep-clear/mise.toml" <<'EOF'
[tasks.check]
depends = ["lint:*"]
run = "true"

[tasks."lint:shell"]
run = "true"
EOF
out="$(run_case glob-dep-clear)"
assert_exit "a wildcard that cannot reach the namespace passes" 0 $?

# ---- a wildcard matching nothing here cannot be shown clear ----
# mise expands it over tasks this parse cannot see, so passing would be a
# guess rather than a proof.
mk_case glob-dep-unresolved
cat >"$TMP/glob-dep-unresolved/mise.toml" <<'EOF'
[tasks.check]
depends = ["*:corpus"]
run = "true"

[tasks.build]
run = "true"
EOF
out="$(run_case glob-dep-unresolved)"
rc=$?
assert_exit "a wildcard matching no task in this file fails" 1 "$rc"
assert_contains "says the wildcard can name the namespace" "can name the eval: namespace" "$out"

# ---- a shell operator ends a run-body operand ----
# `mise run lint:*;echo` must not read as the single token `lint:*;echo`,
# which would expand to nothing and skip the whole sub-graph.
mk_case run-body-operator
cat >"$TMP/run-body-operator/mise.toml" <<'EOF'
[tasks.check]
run = "mise run all:*;echo done"

[tasks."all:evals"]
depends = ["eval:skill"]
run = "true"

[tasks."eval:skill"]
run = "true"
EOF
out="$(run_case run-body-operator)"
rc=$?
assert_exit "a shell operator does not hide a wildcard operand" 1 "$rc"
assert_contains "walks the task the operand expands to" "check -(run body)-> all:evals" "$out"

# ---- a backslash-escaped wildcard is what the shell hands mise ----
mk_case run-body-escaped-glob
cat >"$TMP/run-body-escaped-glob/mise.toml" <<'EOF'
[tasks.check]
run = 'mise run all:\*'

[tasks."all:evals"]
depends = ["eval:skill"]
run = "true"

[tasks."eval:skill"]
run = "true"
EOF
out="$(run_case run-body-escaped-glob)"
rc=$?
assert_exit "an escaped wildcard operand is still expanded" 1 "$rc"
assert_contains "walks the escaped operand's task" "check -(run body)-> all:evals" "$out"

# ---- an operand that begins with the wildcard is still an operand ----
# Only a token that is nothing but wildcards is shell noise like `rm -rf *`.
mk_case run-body-leading-glob
cat >"$TMP/run-body-leading-glob/mise.toml" <<'EOF'
[tasks.check]
run = "mise run *:evals"

[tasks."all:evals"]
depends = ["eval:skill"]
run = "true"

[tasks."eval:skill"]
run = "true"
EOF
out="$(run_case run-body-leading-glob)"
rc=$?
assert_exit "a leading-wildcard operand is expanded" 1 "$rc"
assert_contains "walks the leading-wildcard operand's task" "check -(run body)-> all:evals" "$out"

# ---- partial shell quoting inside an operand is removed like the shell does ----
mk_case run-body-split-quote
cat >"$TMP/run-body-split-quote/mise.toml" <<'EOF'
[tasks.check]
run = 'mise run a"ll":*'

[tasks."all:evals"]
depends = ["eval:skill"]
run = "true"

[tasks."eval:skill"]
run = "true"
EOF
out="$(run_case run-body-split-quote)"
rc=$?
assert_exit "quoting inside an operand does not hide it" 1 "$rc"
assert_contains "walks the requoted operand's task" "check -(run body)-> all:evals" "$out"

# ---- a bare wildcard is shell noise, not a task selector ----
mk_case run-body-bare-glob
cat >"$TMP/run-body-bare-glob/mise.toml" <<'EOF'
[tasks.check]
run = "mise run build && rm -rf *"

[tasks.build]
run = "true"

[tasks."eval:skill"]
run = "true"
EOF
out="$(run_case run-body-bare-glob)"
assert_exit "a bare wildcard in a run body is not read as a selector" 0 $?

# ---- a multi-line string is not modeled outside a run body ----
mk_case multiline-dep
cat >"$TMP/multiline-dep/mise.toml" <<'EOF'
[tasks.check]
depends = """eval:skill"""
run = "true"

[tasks."eval:skill"]
run = "true"
EOF
out="$(run_case multiline-dep)"
rc=$?
assert_exit "a multi-line string as a dependency fails closed" 1 "$rc"
assert_contains "names the unmodeled dependency form" "not modeled as a depends value" "$out"

mk_case multiline-in-array
cat >"$TMP/multiline-in-array/mise.toml" <<'EOF'
[tasks.check]
depends = [
  """build""",
]
run = "true"

[tasks.build]
run = "true"
EOF
out="$(run_case multiline-in-array)"
rc=$?
assert_exit "a multi-line string inside an array fails closed" 1 "$rc"
assert_contains "names the unmodeled array element" "multi-line string inside a depends value" "$out"

# ---- a dependency on an eval task defined outside the parse boundary ----
mk_case dangling-eval-dep
cat >"$TMP/dangling-eval-dep/mise.toml" <<'EOF'
[tasks.check]
depends = ["eval:skill"]
run = "true"
EOF
out="$(run_case dangling-eval-dep)"
rc=$?
assert_exit "a depends on an undefined eval: task fails" 1 "$rc"
assert_contains "names the unresolvable eval dependency" "depends on the eval: namespace" "$out"

# ---- an escaped quote must not end a string and desynchronize the array ----
mk_case escaped-quote
cat >"$TMP/escaped-quote/mise.toml" <<'EOF'
[tasks.check]
depends = ["a\"b", "eval:skill"]
run = "true"

[tasks."eval:skill"]
run = "true"
EOF
out="$(run_case escaped-quote)"
rc=$?
assert_exit "an escaped quote does not drop the rest of the array" 1 "$rc"
assert_contains "still reaches the element after the escaped quote" "CI reaches eval task eval:skill" "$out"

# ---- basic-string escapes are decoded before matching ----
# mise resolves `eval:skill` to `eval:skill`; matching the raw text would
# let an escape hide the namespace from every pass.
mk_case unicode-escape
cat >"$TMP/unicode-escape/mise.toml" <<'EOF'
[tasks.check]
depends = ["\u0065val:skill"]
run = "true"

[tasks."eval:skill"]
run = "true"
EOF
out="$(run_case unicode-escape)"
rc=$?
assert_exit "a unicode escape in a dependency is decoded" 1 "$rc"
assert_contains "resolves the escaped name to the real task" "CI reaches eval task eval:skill" "$out"

mk_case unicode-escape-run
cat >"$TMP/unicode-escape-run/mise.toml" <<'EOF'
[tasks.check]
run = "mise run \u0065val:skill"
EOF
out="$(run_case unicode-escape-run)"
assert_exit "a unicode escape in a run body is decoded" 1 $?

# ---- a newline escape must not swallow the token boundary ----
mk_case newline-escape
cat >"$TMP/newline-escape/mise.toml" <<'EOF'
[tasks.check]
run = "mise run\neval:skill"
EOF
out="$(run_case newline-escape)"
assert_exit "a newline escape does not hide the eval: token boundary" 1 $?

# ---- a run body given as an array is read per element ----
# Keeping the raw array text would leave `]` glued to the operand, so the
# wildcard would expand to nothing.
mk_case run-array
cat >"$TMP/run-array/mise.toml" <<'EOF'
[tasks.check]
run = [
  "echo [start]",
  "mise run e*"
]

[tasks."eval:skill"]
run = "true"
EOF
out="$(run_case run-array)"
assert_exit "a run array's wildcard operand is expanded" 1 $?

# ---- escapes a clean file legitimately uses must not fail it ----
mk_case escape-falsepos
cat >"$TMP/escape-falsepos/mise.toml" <<'EOF'
[tasks.check]
depends = ["build"]
run = "grep '\\usepackage' file"

[tasks.build]
run = "printf 'a\nb'"
EOF
out="$(run_case escape-falsepos)"
rc=$?
assert_exit "legitimate escapes in a clean file still pass" 0 "$rc"

# ---- a task alias is a root name too ----
mk_case task-alias
cat >"$TMP/task-alias/mise.toml" <<'EOF'
[tasks.check]
run = "true"

[tasks."ci-evals"]
aliases = ["ci"]
depends = ["eval:skill"]

[tasks."eval:skill"]
run = "true"
EOF
cat >"$TMP/task-alias/workflows/ci.yml" <<'EOF'
name: ci
"on": [push]
jobs:
  check:
    steps:
      - run: mise run check
      - run: mise run ci
EOF
out="$(run_case task-alias)"
rc=$?
assert_exit "an aliased CI invocation roots its task" 1 "$rc"
assert_contains "reaches the eval task through the alias" "CI reaches eval task eval:skill" "$out"

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
assert_contains "names the task whose run body wires it in" \
  "run body of CI-invoked task report invokes an eval harness" "$out"

# ---- the same, in a `\"\"\"` multi-line body ----
mk_case run-body-basic-multiline
cat >"$TMP/run-body-basic-multiline/mise.toml" <<'EOF'
[tasks.check]
depends = ["report"]
run = "true"

[tasks.report]
run = """
mise run eval:skill
"""
EOF
out="$(run_case run-body-basic-multiline)"
assert_exit "a basic-string multi-line run body is scanned" 1 $?

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
assert_contains "names the run-body runner offender" \
  "run body of CI-invoked task report invokes an eval harness" "$out"
assert_contains "quotes the offending runner call" "behavioral-eval.sh" "$out"

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
assert_contains "labels the run-body edge" "check -(run body)-> bundle" "$out"

# ---- a wildcard run-body operand expands the same way ----
mk_case run-body-wildcard
cat >"$TMP/run-body-wildcard/mise.toml" <<'EOF'
[tasks.check]
run = "mise run all:*"

[tasks."all:evals"]
depends = ["eval:skill"]
run = "true"

[tasks."eval:skill"]
run = "true"
EOF
out="$(run_case run-body-wildcard)"
rc=$?
assert_exit "a wildcard run-body operand is expanded" 1 "$rc"
assert_contains "walks the wildcard-matched task" "check -(run body)-> all:evals" "$out"

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
description = "on demand only, never run mise run eval:skill in CI"
run = "/bin/sh scripts/prompt-eval.sh --suite tests/prompt-evals/fixtures"
EOF
out="$(run_case unreachable-eval)"
rc=$?
assert_exit "a clean graph with an unreachable eval task passes" 0 "$rc"
assert_contains "says the closure reaches no eval task" "reaches the eval: namespace" "$out"

# ---- false positives the graph passes must not produce ----
# A description is prose, not a run body; a TOML comment cannot create a
# dependency or a runner call; and a task whose name merely contains `eval` is
# not in the namespace. Each of these would block the whole `check` aggregate.
mk_case graph-falsepos
cat >"$TMP/graph-falsepos/mise.toml" <<'EOF'
[tasks.check]
depends = ["retrieval:index", "evaluate-release"] # never add "eval:skill" here
run = "mise run medieval:build" # do not wire mise run eval:skill in here

[tasks."retrieval:index"]
description = "mise run eval:skill is the manual command"
run = "true"

[tasks.evaluate-release]
run = "true"

[tasks."medieval:build"]
run = "true"
EOF
out="$(run_case graph-falsepos)"
rc=$?
assert_exit "descriptions, TOML comments and eval-like names are not flagged" 0 "$rc"
assert_lacks "no spurious eval verdict" "reachable from CI" "$out"

# ---- a SHELL comment inside a run body still over-blocks, deliberately ----
# The `#` sits inside the TOML string, so it is body text the guard cannot tell
# apart from a live invocation. Same fail-loud direction as the text pass.
mk_case run-body-shell-comment
cat >"$TMP/run-body-shell-comment/mise.toml" <<'EOF'
[tasks.check]
run = "mise run build   # never mise run eval:skill here"

[tasks.build]
run = "true"
EOF
out="$(run_case run-body-shell-comment)"
assert_exit "a shell comment inside a run body over-blocks" 1 $?

# ---- parse failures, each reported rather than half-read ----
mk_case unparseable
cat >"$TMP/unparseable/mise.toml" <<'EOF'
[tasks.check]
run = '''
echo never terminated
EOF
out="$(run_case unparseable)"
rc=$?
assert_exit "an unterminated multi-line string fails closed" 1 "$rc"
assert_contains "says it could not parse the task graph" "could not parse the mise task graph" "$out"
assert_contains "names the parse reason" "unterminated multi-line string" "$out"

mk_case array-of-tables
cat >"$TMP/array-of-tables/mise.toml" <<'EOF'
[[tasks.check]]
run = "true"
EOF
out="$(run_case array-of-tables)"
rc=$?
assert_exit "an array-of-tables header fails closed" 1 "$rc"
assert_contains "names the array-of-tables reason" "array-of-tables header not modeled" "$out"

mk_case inline-tasks
cat >"$TMP/inline-tasks/mise.toml" <<'EOF'
[tasks]
check = "true"
EOF
out="$(run_case inline-tasks)"
rc=$?
assert_exit "a bare [tasks] table fails closed" 1 "$rc"
assert_contains "names the inline-table reason" "inline [tasks] table not modeled" "$out"

mk_case nested-table
cat >"$TMP/nested-table/mise.toml" <<'EOF'
[tasks.check]
run = "true"

[tasks.check.env]
FOO = "bar"
EOF
out="$(run_case nested-table)"
rc=$?
assert_exit "a nested task table fails closed" 1 "$rc"
assert_contains "names the nested-table reason" "nested task table not modeled" "$out"

mk_case unterminated-array
cat >"$TMP/unterminated-array/mise.toml" <<'EOF'
[tasks.check]
depends = [
  "build",
EOF
out="$(run_case unterminated-array)"
rc=$?
assert_exit "an unterminated array fails closed" 1 "$rc"
assert_contains "names the unterminated-array reason" "unterminated array" "$out"

mk_case bare-depends
cat >"$TMP/bare-depends/mise.toml" <<'EOF'
[tasks.check]
depends = build
run = "true"
EOF
out="$(run_case bare-depends)"
rc=$?
assert_exit "an unquoted depends value fails closed" 1 "$rc"
assert_contains "names the unrecognized value" "unrecognized depends value" "$out"

# ---- a mise.toml that parses to zero tasks fails closed ----
mk_case zero-tasks
cat >"$TMP/zero-tasks/mise.toml" <<'EOF'
[tools]
shellcheck = "0.11.0"
EOF
out="$(run_case zero-tasks)"
rc=$?
assert_exit "a zero-task mise.toml fails closed" 1 "$rc"
assert_contains "says the graph held no tasks" "parsed to zero tasks" "$out"

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
assert_contains "says no CI-invoked task was found" "no CI-invoked mise task found" "$out"
assert_contains "counts the workflow files it scanned" "1 workflow file(s) scanned" "$out"

# ---- a commented-out invocation must not manufacture a root ----
# Counting a comment as a root would mask the fail-closed above.
mkdir -p "$TMP/comment-root/workflows"
cat >"$TMP/comment-root/workflows/ci.yml" <<'EOF'
name: ci
"on": [push]
jobs:
  check:
    steps:
      # the single `mise run check` step is the gate
      - run: npm test
EOF
cat >"$TMP/comment-root/mise.toml" <<'EOF'
[tasks.check]
run = "true"
EOF
out="$(run_case comment-root)"
rc=$?
assert_exit "a comment naming a task does not count as a root" 1 "$rc"
assert_contains "still reports zero roots" "no CI-invoked mise task found" "$out"

# ---- the explicit no-graph argument runs the text pass alone ----
mk_case no-graph
cat >"$TMP/no-graph/mise.toml" <<'EOF'
[tasks.check]
depends = ["eval:skill"]
run = "true"
EOF
out="$("$GUARD" "$TMP/no-graph/workflows" - 2>&1)"
rc=$?
assert_exit "'-' skips the graph passes" 0 "$rc"
assert_contains "says there is no task graph" "no task graph to close over" "$out"

# ---- unreadable inputs fail closed rather than reading as empty ----
# `chmod 000` does not stop root, so under a root test runner these two would
# fail for a reason that says nothing about the guard.
if [ "$(id -u)" -eq 0 ]; then
  echo "ok: unreadable-input cases skipped (running as root)"
else
  mkdir -p "$TMP/unreadable/workflows"
  cp "$TMP/depends-chain/workflows/ci.yml" "$TMP/unreadable/workflows/"
  cp "$TMP/depends-chain/mise.toml" "$TMP/unreadable/"

  chmod 000 "$TMP/unreadable/workflows/ci.yml"
  out="$(run_case unreadable)"
  rc=$?
  chmod 644 "$TMP/unreadable/workflows/ci.yml"
  if [ "$rc" -eq 0 ]; then
    echo "FAIL: an unreadable workflow file passed vacuously" >&2
    failures=$((failures + 1))
  else
    assert_contains "an unreadable workflow file fails closed" "cannot be read" "$out"
  fi

  chmod 000 "$TMP/unreadable/workflows"
  out="$(run_case unreadable)"
  rc=$?
  chmod 755 "$TMP/unreadable/workflows"
  if [ "$rc" -eq 0 ]; then
    echo "FAIL: an unlistable workflow directory passed vacuously" >&2
    failures=$((failures + 1))
  else
    assert_contains "an unlistable workflow directory fails closed" "cannot be listed" "$out"
  fi
fi

# ---- usage errors are usage errors, not vacuous passes ----
"$GUARD" --halp >/dev/null 2>&1
assert_exit "an unknown flag is a usage error" 2 $?
"$GUARD" a b c >/dev/null 2>&1
assert_exit "too many arguments is a usage error" 2 $?
"$GUARD" "" >/dev/null 2>&1
assert_exit "an empty argument is a usage error" 2 $?
"$GUARD" "$TMP/benign" "$TMP/no-such-file.toml" >/dev/null 2>&1
assert_exit "an unresolvable explicit mise config is a usage error" 2 $?
"$GUARD" "$TMP/benign/ci.yml" - >/dev/null 2>&1
assert_exit "a file passed as the workflow directory is a usage error" 2 $?

# ---- verdicts go to stderr, clean summaries to stdout ----
run_split "$GUARD" "$TMP/depends-chain/workflows" "$TMP/depends-chain/mise.toml"
assert_exit "the violation case exits 1" 1 "$RC"
assert_contains "the verdict lands on stderr" "CI reaches eval task eval:skill" "$ERR"
assert_lacks "nothing leaks to stdout on a violation" "eval:skill" "$OUT"
run_split "$GUARD" "$TMP/unreachable-eval/workflows" "$TMP/unreachable-eval/mise.toml"
assert_exit "the clean case exits 0" 0 "$RC"
assert_contains "the clean summary lands on stdout" "reaches the eval: namespace" "$OUT"

# ---- --help documents the passes and the parse boundary ----
out="$("$GUARD" --help 2>&1)"
rc=$?
assert_exit "--help exits clean" 0 "$rc"
assert_contains "--help documents the workflow-text pass" "WORKFLOW-TEXT" "$out"
assert_contains "--help documents the task-graph closure pass" "TASK-GRAPH CLOSURE" "$out"
assert_contains "--help documents the run-body pass" "RUN-BODY" "$out"
assert_contains "--help documents the parse boundary" "PARSE BOUNDARY" "$out"
assert_contains "--help documents the fail-closed posture" "FAIL-CLOSED" "$out"
assert_contains "--help documents what the graph passes do not follow" "DO NOT FOLLOW" "$out"

# ---- the REAL repo workflow set and task graph pass ----
run_split "$GUARD" "$REPO_ROOT/.github/workflows" "$REPO_ROOT/mise.toml"
assert_exit "real repo workflow set and task graph pass" 0 "$RC"
assert_contains "the real repo runs all three passes" "reaches the eval: namespace" "$OUT"

# ---- defaults resolve to the repo's own workflows and mise config ----
# Asserting the success line, not just the exit code: the skip path also exits 0.
run_split "$GUARD"
assert_exit "defaults pass on the real repo" 0 "$RC"
assert_contains "defaults resolve the real mise config" "$REPO_ROOT/mise.toml" "$OUT"
assert_lacks "defaults do not silently skip the graph passes" "no task graph to close over" "$OUT"

if [ "$failures" -ne 0 ]; then
  echo "$failures test(s) failed" >&2
  exit 1
fi
echo "all check-no-ci-evals tests passed"
