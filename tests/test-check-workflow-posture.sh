#!/bin/bash
# Tests for scripts/check-workflow-posture.sh — the fork-PR posture guard
# (guard-coverage Task 4; D-6; REQ-C1.2, REQ-H1.3). D-6's working posture is
# that PR-authored code may execute under `pull_request`, but only ever with a
# read-only token and zero stored secrets. This guard pins that mechanically so
# a workflow edit that breaks it fails CI instead of relying on reviewer
# vigilance.
#
# The fixture set is the REQ-C1.2 verification path: each named violation gets
# a failing fixture, each deliberately-allowed shape gets a passing one (so the
# guard's scoping is pinned in BOTH directions), the vacuous-input cases fail
# closed per REQ-H1.3, and the repo's own workflows must pass.
#
# Workflow files are PR-controllable, so the guard treats their contents as
# untrusted data: the fixtures below include hostile-ish shapes (tabs, merge
# keys, a secret hidden behind the index spelling) and assert a loud failure
# rather than a silent pass.
set -u
unset CDPATH

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
GUARD="$REPO_ROOT/scripts/check-workflow-posture.sh"

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

# mkdir_case <name> — a fresh, empty fixture workflow directory.
mkdir_case() {
  d="$TMP/$1"
  mkdir -p "$d"
  printf '%s' "$d"
}

# ---------------------------------------------------------------------------
# Passing fixtures — the shapes D-6 deliberately allows.
# ---------------------------------------------------------------------------

# The canonical safe shape: pull_request-triggered, read-only top-level
# permissions, and the workflow's own GITHUB_TOKEN as the only secret
# reference (exempt: its privilege is governed by the permissions assertion).
d="$(mkdir_case pass-github-token)"
cat >"$d/ci.yml" <<'EOF'
---
name: ci
"on":
  pull_request:
  push:
    branches: [main]
permissions:
  contents: read
jobs:
  check:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v6
        with:
          token: ${{ secrets.GITHUB_TOKEN }}
      - run: mise run check
EOF
out="$("$GUARD" "$d" 2>&1)"
assert_exit "GITHUB_TOKEN under read-only permissions passes" 0 $?

# Reachability scoping, direction 1: a real stored secret is fine when no
# pull_request trigger can reach it.
d="$(mkdir_case pass-push-only-secret)"
cat >"$d/deploy.yml" <<'EOF'
---
name: deploy
"on":
  push:
    branches: [main]
permissions:
  contents: write
jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - run: ./deploy.sh
        env:
          KEY: ${{ secrets.DEPLOY_KEY }}
EOF
out="$("$GUARD" "$d" 2>&1)"
assert_exit "stored secret in a push-only workflow passes" 0 $?

# Reachability scoping, direction 2: a privileged workflow_run workflow is
# fine while it keeps its base-branch filter and consumes no PR artifact.
d="$(mkdir_case pass-workflow-run-filtered)"
cat >"$d/release.yml" <<'EOF'
---
name: release
"on":
  workflow_run:
    workflows: [ci]
    types: [completed]
    branches: [main]
permissions:
  contents: write
jobs:
  release:
    runs-on: ubuntu-latest
    steps:
      - run: ./release.sh
        env:
          KEY: ${{ secrets.RELEASE_KEY }}
EOF
out="$("$GUARD" "$d" 2>&1)"
assert_exit "filtered privileged workflow_run passes" 0 $?

# The two permission shorthands that are read-only-or-less.
d="$(mkdir_case pass-shorthands)"
cat >"$d/a.yml" <<'EOF'
---
name: a
"on": pull_request
permissions: read-all
jobs:
  a:
    runs-on: ubuntu-latest
    steps:
      - run: echo a
EOF
cat >"$d/b.yml" <<'EOF'
---
name: b
"on": [pull_request, push]
permissions:
  contents: read
jobs:
  b:
    permissions: {}
    runs-on: ubuntu-latest
    steps:
      - run: echo b
EOF
out="$("$GUARD" "$d" 2>&1)"
assert_exit "read-all and {} count as read-only" 0 $?

# A local reusable-workflow call from a pull_request-reachable job, with
# read-only permissions on both sides and no secrets passed.
d="$(mkdir_case pass-reusable-clean)"
cat >"$d/caller.yml" <<'EOF'
---
name: caller
"on":
  pull_request:
permissions:
  contents: read
jobs:
  call:
    uses: ./.github/workflows/reusable.yml
EOF
cat >"$d/reusable.yml" <<'EOF'
---
name: reusable
"on":
  workflow_call:
permissions:
  contents: read
jobs:
  work:
    runs-on: ubuntu-latest
    steps:
      - run: echo work
EOF
out="$("$GUARD" "$d" 2>&1)"
assert_exit "clean local reusable-workflow call passes" 0 $?

# ---------------------------------------------------------------------------
# Failing fixtures — one per REQ-C1.2 assertion.
# ---------------------------------------------------------------------------

# pull_request_target is banned outright, wherever it appears.
d="$(mkdir_case fail-pr-target)"
cat >"$d/x.yml" <<'EOF'
---
name: x
"on":
  pull_request_target:
    types: [opened]
permissions:
  contents: read
jobs:
  x:
    runs-on: ubuntu-latest
    steps:
      - run: echo x
EOF
out="$("$GUARD" "$d" 2>&1)"
assert_exit "pull_request_target fails" 1 $?
assert_contains "pull_request_target is named" "pull_request_target" "$out"

# A stored secret reachable from pull_request, dotted spelling.
d="$(mkdir_case fail-secret-dot)"
cat >"$d/x.yml" <<'EOF'
---
name: x
"on":
  pull_request:
permissions:
  contents: read
jobs:
  x:
    runs-on: ubuntu-latest
    steps:
      - run: ./publish.sh
        env:
          NPM_TOKEN: ${{ secrets.NPM_TOKEN }}
EOF
out="$("$GUARD" "$d" 2>&1)"
assert_exit "dotted stored secret reachable from pull_request fails" 1 $?
assert_contains "the secret name is named" "NPM_TOKEN" "$out"

# The same secret hidden behind the index spelling, which a naive
# `secrets\.` grep would miss.
d="$(mkdir_case fail-secret-index)"
cat >"$d/x.yml" <<'EOF'
---
name: x
"on":
  pull_request:
permissions:
  contents: read
jobs:
  x:
    runs-on: ubuntu-latest
    steps:
      - run: ./publish.sh
        env:
          NPM_TOKEN: ${{ secrets['NPM_TOKEN'] }}
EOF
out="$("$GUARD" "$d" 2>&1)"
assert_exit "index-spelled stored secret fails" 1 $?
assert_contains "the index-spelled secret is named" "NPM_TOKEN" "$out"

# secrets: inherit on a pull_request-reachable reusable-workflow call.
d="$(mkdir_case fail-secrets-inherit)"
cat >"$d/caller.yml" <<'EOF'
---
name: caller
"on":
  pull_request:
permissions:
  contents: read
jobs:
  call:
    uses: ./.github/workflows/reusable.yml
    secrets: inherit
EOF
cat >"$d/reusable.yml" <<'EOF'
---
name: reusable
"on":
  workflow_call:
permissions:
  contents: read
jobs:
  work:
    runs-on: ubuntu-latest
    steps:
      - run: echo work
EOF
out="$("$GUARD" "$d" 2>&1)"
assert_exit "secrets: inherit reachable from pull_request fails" 1 $?
assert_contains "inherit is named" "inherit" "$out"

# A secret referenced only inside the CALLEE, reached through a local
# reusable-workflow call: the guard must follow the uses: edge.
d="$(mkdir_case fail-secret-through-uses)"
cat >"$d/caller.yml" <<'EOF'
---
name: caller
"on":
  pull_request:
permissions:
  contents: read
jobs:
  call:
    uses: ./.github/workflows/reusable.yml
EOF
cat >"$d/reusable.yml" <<'EOF'
---
name: reusable
"on":
  workflow_call:
permissions:
  contents: read
jobs:
  work:
    runs-on: ubuntu-latest
    steps:
      - run: ./publish.sh
        env:
          KEY: ${{ secrets.DEPLOY_KEY }}
EOF
out="$("$GUARD" "$d" 2>&1)"
assert_exit "secret in a called reusable workflow fails" 1 $?
assert_contains "the callee secret is named" "DEPLOY_KEY" "$out"

# Job-level write escalation under a read-only top level: the exact shape a
# top-level-only check would wave through.
d="$(mkdir_case fail-job-escalation)"
cat >"$d/x.yml" <<'EOF'
---
name: x
"on":
  pull_request:
permissions:
  contents: read
jobs:
  safe:
    runs-on: ubuntu-latest
    steps:
      - run: echo safe
  risky:
    runs-on: ubuntu-latest
    permissions:
      contents: read
      pull-requests: write
    steps:
      - run: echo risky
EOF
out="$("$GUARD" "$d" 2>&1)"
assert_exit "job-level write escalation fails" 1 $?
assert_contains "the escalating job is named" "risky" "$out"

# write-all at the top level is the same violation in shorthand.
d="$(mkdir_case fail-write-all)"
cat >"$d/x.yml" <<'EOF'
---
name: x
"on":
  pull_request:
permissions: write-all
jobs:
  x:
    runs-on: ubuntu-latest
    steps:
      - run: echo x
EOF
out="$("$GUARD" "$d" 2>&1)"
assert_exit "write-all with a pull_request trigger fails" 1 $?

# No permissions declared at all: the effective token comes from repo/org
# settings, which the file cannot prove read-only. Fail closed (REQ-H1.3).
d="$(mkdir_case fail-perms-absent)"
cat >"$d/x.yml" <<'EOF'
---
name: x
"on":
  pull_request:
jobs:
  x:
    runs-on: ubuntu-latest
    steps:
      - run: echo x
EOF
out="$("$GUARD" "$d" 2>&1)"
assert_exit "undeclared permissions on a pull_request job fails closed" 1 $?
assert_contains "the undeclared-permissions reason is stated" "no permissions" "$out"

# A privileged workflow_run workflow that dropped its base-branch filter: a
# fork PR's workflow can then trigger it with the base repo's write token.
d="$(mkdir_case fail-workflow-run-unfiltered)"
cat >"$d/x.yml" <<'EOF'
---
name: x
"on":
  workflow_run:
    workflows: [ci]
    types: [completed]
permissions:
  contents: write
jobs:
  x:
    runs-on: ubuntu-latest
    steps:
      - run: echo x
EOF
out="$("$GUARD" "$d" 2>&1)"
assert_exit "privileged workflow_run without a base-branch filter fails" 1 $?
assert_contains "the missing filter is named" "branches" "$out"

# A privileged workflow_run workflow consuming a PR-produced artifact: the
# artifact-poisoning path GitHub's own docs warn about.
d="$(mkdir_case fail-workflow-run-artifact)"
cat >"$d/x.yml" <<'EOF'
---
name: x
"on":
  workflow_run:
    workflows: [ci]
    types: [completed]
    branches: [main]
permissions:
  contents: write
jobs:
  x:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/download-artifact@v4
        with:
          name: pr-report
EOF
out="$("$GUARD" "$d" 2>&1)"
assert_exit "privileged workflow_run consuming a PR artifact fails" 1 $?
assert_contains "the artifact consumption is named" "artifact" "$out"

# ---------------------------------------------------------------------------
# Fail-closed on input the guard cannot read (REQ-H1.3).
# ---------------------------------------------------------------------------

# Tab indentation: outside the parsed subset, so the structure is unknown.
d="$(mkdir_case fail-unparseable-tab)"
printf 'name: x\n"on":\n\tpull_request:\njobs:\n  x:\n    runs-on: ubuntu-latest\n' \
  >"$d/x.yml"
out="$("$GUARD" "$d" 2>&1)"
assert_exit "tab-indented workflow fails closed" 1 $?
assert_contains "the parse failure is stated" "parse" "$out"

# A YAML merge key: structure the parser does not model, so it must not
# silently read the visible half and pass.
d="$(mkdir_case fail-unparseable-merge)"
cat >"$d/x.yml" <<'EOF'
---
name: x
"on":
  pull_request:
permissions:
  contents: read
defaults: &d
  run:
    shell: bash
jobs:
  x:
    <<: *d
    runs-on: ubuntu-latest
    steps:
      - run: echo x
EOF
out="$("$GUARD" "$d" 2>&1)"
assert_exit "merge-key workflow fails closed" 1 $?
assert_contains "the merge-key parse failure is stated" "parse" "$out"

# A workflow with no jobs at all is degenerate, not vacuously clean.
d="$(mkdir_case fail-zero-jobs)"
cat >"$d/x.yml" <<'EOF'
---
name: x
"on":
  pull_request:
permissions:
  contents: read
EOF
out="$("$GUARD" "$d" 2>&1)"
assert_exit "workflow with zero jobs fails closed" 1 $?

# An empty workflow directory: nothing to assert means nothing was proven.
d="$(mkdir_case fail-empty-dir)"
out="$("$GUARD" "$d" 2>&1)"
assert_exit "empty workflow directory fails closed" 1 $?
assert_contains "the zero-file reason is stated" "no workflow files" "$out"

# An absent directory, same reasoning.
out="$("$GUARD" "$TMP/does-not-exist" 2>&1)"
assert_exit "absent workflow directory fails closed" 1 $?

# A local reusable-workflow target that is not in the scanned set: the edge
# cannot be followed, so the reachable surface is unknown.
d="$(mkdir_case fail-dangling-uses)"
cat >"$d/caller.yml" <<'EOF'
---
name: caller
"on":
  pull_request:
permissions:
  contents: read
jobs:
  call:
    uses: ./.github/workflows/missing.yml
EOF
out="$("$GUARD" "$d" 2>&1)"
assert_exit "dangling local reusable-workflow call fails closed" 1 $?
assert_contains "the missing callee is named" "missing.yml" "$out"

# ---------------------------------------------------------------------------
# Matching discipline — the shapes a naive matcher lets through or trips on.
# ---------------------------------------------------------------------------

# GitHub expression contexts and secret names are case-insensitive
# (`${{ SECRETS.foo }}`, `${{ SeCRetS.Baz }}` all resolve), so a
# case-SENSITIVE scan is evadable by casing alone.
d="$(mkdir_case fail-secret-casing)"
cat >"$d/x.yml" <<'EOF'
---
name: x
"on":
  pull_request:
permissions:
  contents: read
jobs:
  x:
    runs-on: ubuntu-latest
    steps:
      - run: ./publish.sh
        env:
          A: ${{ SECRETS.NPM_TOKEN }}
          B: ${{ SeCRetS['OTHER_KEY'] }}
EOF
out="$("$GUARD" "$d" 2>&1)"
assert_exit "case-varied SECRETS spellings fail" 1 $?
assert_contains "the upper-cased spelling is caught" "NPM_TOKEN" "$out"
assert_contains "the mixed-case index spelling is caught" "OTHER_KEY" "$out"

# The exemption is case-insensitive in the same way, so a lower-cased
# GITHUB_TOKEN reference is not mistaken for a stored secret. GitHub reserves
# the `GITHUB_` prefix for secret names, so no stored secret can claim it.
d="$(mkdir_case pass-github-token-casing)"
cat >"$d/x.yml" <<'EOF'
---
name: x
"on":
  pull_request:
permissions:
  contents: read
jobs:
  x:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v6
        with:
          token: ${{ secrets.github_token }}
EOF
out="$("$GUARD" "$d" 2>&1)"
assert_exit "lower-cased github_token stays exempt" 0 $?

# A step script is text, not YAML structure: a `- run: |` body that happens to
# contain `key: &word` must not be read as a YAML anchor. The mapping form
# (`run: |`) already skipped its body; the sequence form must too.
d="$(mkdir_case pass-seq-block-scalar)"
cat >"$d/x.yml" <<'EOF'
---
name: x
"on":
  pull_request:
permissions:
  contents: read
jobs:
  x:
    runs-on: ubuntu-latest
    steps:
      - run: |
          grep 'name: &anchor' file.txt
          printf 'ref: *glob\n'
          echo '<<: merge'
EOF
out="$("$GUARD" "$d" 2>&1)"
assert_exit "a step script containing YAML-ish text is not a parse failure" 0 $?

# …but the text scans still see block-scalar bodies: a secret referenced
# inside a `- run: |` script is as reachable as one in a structured value.
d="$(mkdir_case fail-secret-in-seq-block)"
cat >"$d/x.yml" <<'EOF'
---
name: x
"on":
  pull_request:
permissions:
  contents: read
jobs:
  x:
    runs-on: ubuntu-latest
    steps:
      - run: |
          echo "publishing"
          ./publish.sh --token '${{ secrets.NPM_TOKEN }}'
EOF
out="$("$GUARD" "$d" 2>&1)"
assert_exit "a secret inside a step script is still caught" 1 $?
assert_contains "the in-script secret is named" "NPM_TOKEN" "$out"

# `branches-ignore` is not a positive base-branch filter — it allows every
# branch it does not name — so it does not satisfy assertion 4.
d="$(mkdir_case fail-workflow-run-branches-ignore)"
cat >"$d/x.yml" <<'EOF'
---
name: x
"on":
  workflow_run:
    workflows: [ci]
    branches-ignore: [dependabot/**]
permissions:
  contents: write
jobs:
  x:
    runs-on: ubuntu-latest
    steps:
      - run: echo x
EOF
out="$("$GUARD" "$d" 2>&1)"
assert_exit "branches-ignore does not satisfy the base-branch filter" 1 $?

# Artifact consumption via the gh CLI, not just the action.
d="$(mkdir_case fail-workflow-run-gh-download)"
cat >"$d/x.yml" <<'EOF'
---
name: x
"on":
  workflow_run:
    workflows: [ci]
    branches: [main]
permissions:
  contents: write
jobs:
  x:
    runs-on: ubuntu-latest
    steps:
      - run: gh run download "$RUN_ID" --name pr-report
EOF
out="$("$GUARD" "$d" 2>&1)"
assert_exit "gh run download counts as consuming a PR artifact" 1 $?

# An unrecognized permission level proves nothing about the token, so it is
# treated exactly like write (REQ-H1.3).
d="$(mkdir_case fail-perms-unrecognized)"
cat >"$d/x.yml" <<'EOF'
---
name: x
"on":
  pull_request:
permissions:
  contents: read
jobs:
  x:
    runs-on: ubuntu-latest
    permissions:
      contents: reed
    steps:
      - run: echo x
EOF
out="$("$GUARD" "$d" 2>&1)"
assert_exit "an unrecognized permission level fails closed" 1 $?
assert_contains "the unrecognized level is described" "unrecognized" "$out"

# A dangling local `uses:` reached only through a multi-hop closure must be
# reported once, not once per closure iteration.
d="$(mkdir_case fail-dangling-uses-multihop)"
cat >"$d/a.yml" <<'EOF'
---
name: a
"on":
  pull_request:
permissions:
  contents: read
jobs:
  j:
    uses: ./.github/workflows/b.yml
EOF
cat >"$d/b.yml" <<'EOF'
---
name: b
"on":
  workflow_call:
permissions:
  contents: read
jobs:
  j:
    uses: ./.github/workflows/nope.yml
EOF
out="$("$GUARD" "$d" 2>&1)"
assert_exit "a multi-hop dangling uses fails closed" 1 $?
n="$(printf '%s\n' "$out" | grep -c "nope.yml" || true)"
assert_exit "the dangling edge is reported exactly once" 1 "$n"

# ---------------------------------------------------------------------------
# Usage and the real tree.
# ---------------------------------------------------------------------------

out="$("$GUARD" too many args 2>&1)"
assert_exit "too many arguments is a usage error" 2 $?

out="$("$GUARD" "$REPO_ROOT/.github/workflows" 2>&1)"
assert_exit "the repo's own workflows pass" 0 $?

# The default argument resolves to the repo's workflow directory, so a bare
# invocation from anywhere gives the same verdict as the explicit one.
out="$(cd "$TMP" && "$GUARD" 2>&1)"
assert_exit "the default workflows dir resolves to the repo's" 0 $?

if [ "$failures" -ne 0 ]; then
  echo "$failures test(s) failed" >&2
  exit 1
fi
echo "all check-workflow-posture tests passed"
