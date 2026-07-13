#!/bin/bash
# Tests for scripts/check-no-ci-evals.sh — the standing CI-exclusion guard
# (prompt-hygiene Task 4; REQ-C1.6). The kept prompt-eval suite must never run
# in GitHub CI (cost, nondeterministic gating, and an API-key requirement in a
# public repo — D-8). This guard enforces that invariant structurally: it fails
# if any eval task (the `eval:` mise namespace) is wired into a workflow file,
# rather than relying on the eval task's mere absence from the `check`
# aggregate. Workflow files are PR-controllable, so the guard treats their
# contents as untrusted data (grep over text; no eval, no path expansion).
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
out="$("$GUARD" "$TMP/benign" 2>&1)"
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
out="$("$GUARD" "$TMP/wired1" 2>&1)"
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
out="$("$GUARD" "$TMP/wired2" 2>&1)"
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
out="$("$GUARD" "$TMP/wired3" 2>&1)"
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
out="$("$GUARD" "$TMP/alias" 2>&1)"
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
out="$("$GUARD" "$TMP/flag" 2>&1)"
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
out="$("$GUARD" "$TMP/quoted" 2>&1)"
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
out="$("$GUARD" "$TMP/direct" 2>&1)"
rc=$?
assert_exit "direct sh scripts/prompt-eval.sh is caught" 1 "$rc"
assert_contains "names the direct-runner offender" "direct/ci.yml" "$out"

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
out="$("$GUARD" "$TMP/falsepos" 2>&1)"
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
out="$("$GUARD" "$TMP/retrieval" 2>&1)"
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
out="$("$GUARD" "$TMP/premise" 2>&1)"
rc=$?
assert_exit "a word ending in 'mise' (premise) is not flagged" 0 "$rc"

# ---- no workflow directory: vacuously clean ----
out="$("$GUARD" "$TMP/does-not-exist" 2>&1)"
assert_exit "absent workflow dir passes vacuously" 0 $?

# ---- the REAL repo workflow set passes ----
out="$("$GUARD" "$REPO_ROOT/.github/workflows" 2>&1)"
assert_exit "real repo workflow set passes" 0 $?

# ---- default arg resolves to .github/workflows and passes ----
out="$(cd "$REPO_ROOT" && "$GUARD" 2>&1)"
assert_exit "default (.github/workflows) passes on the real repo" 0 $?

if [ "$failures" -ne 0 ]; then
  echo "$failures test(s) failed" >&2
  exit 1
fi
echo "all check-no-ci-evals tests passed"
