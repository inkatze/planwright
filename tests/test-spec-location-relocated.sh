#!/bin/bash
# The migrated script callers with spec_root relocated, in each posture: an
# in-repo subdirectory, a directory in a second (holder) repository, and a
# plain directory in no repository. Every caller finds the bundle through the
# resolver, none asserts that the root's parent is named `specs`, and task
# state derives from the work repository whichever posture holds the bundle.
# A dispatch from inside a worktree places the new worktree under the work
# repository's primary checkout.
set -u
unset CDPATH
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY \
  GIT_CONFIG_PARAMETERS GIT_CONFIG_COUNT

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
S="$REPO_ROOT/scripts"

failures=0
ok() { echo "ok: $1"; }
fail() {
  printf 'FAIL: %s\n' "$1" | tr -d '\000-\010\013-\037\177' >&2
  failures=$((failures + 1))
}
# expect <label> <want-substring> <got>
expect() {
  case $3 in
    *"$2"*) ok "$1" ;;
    *) fail "$1 (expected to contain '$2', got '$3')" ;;
  esac
}

tmp=$(mktemp -d "${TMPDIR:-/tmp}/spec-location-relocated.XXXXXX") || exit 1
tmp=$(cd "$tmp" && pwd -P) || exit 1
trap 'rm -rf "$tmp"' EXIT

inherited_unsets=$(env | sed -n 's/^\(PLANWRIGHT_[A-Za-z0-9_]*\)=.*/-u \1/p')
mkdir -p "$tmp/home" "$tmp/fleet"
# A hermetic environment with the install root pinned to this tree.
hermetic() {
  # shellcheck disable=SC2086 # one `-u NAME` pair per word
  env $inherited_unsets -u CLAUDE_PLUGIN_ROOT -u CLAUDE_PLUGIN_DATA -u CLAUDE_DIR \
    -u TMUX -u TMUX_PANE TMUX_TMPDIR="$tmp/home" HOME="$tmp/home" \
    GIT_CEILING_DIRECTORIES="$tmp" GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 \
    GIT_AUTHOR_NAME=fixture GIT_AUTHOR_EMAIL=fixture@example.invalid \
    GIT_COMMITTER_NAME=fixture GIT_COMMITTER_EMAIL=fixture@example.invalid \
    PLANWRIGHT_ROOT="$REPO_ROOT" PLANWRIGHT_FLEET_STATE_DIR="$tmp/fleet" "$@"
}
# at <dir> <command...> — run from <dir>, capturing stdout+stderr and status.
at() {
  at_dir=$1
  shift
  out=$(cd "$at_dir" && hermetic "$@" 2>&1)
  rc=$?
}
gitq() { hermetic git "$@" >/dev/null 2>&1; }

# make_bundle <dir> — a Ready format-version 2 bundle: task 1, and task 2
# depending on it. Its brief carries the recorded anchor form existing briefs
# use.
make_bundle() {
  mkdir -p "$1"
  mb_head='**Status:** Ready
**Format-version:** 2
**Execution:** derived — see the status render'
  printf '# Demo — Requirements\n\n%s\n\n## Goal\n\nA fixture.\n\n## REQ-A — Things\n\n- **REQ-A1.1** A thing SHALL exist.\n  *(Cites: D-1.)*\n' "$mb_head" >"$1/requirements.md"
  printf '# Demo — Design\n\n%s\n\n### D-1: The thing  (N)\n\n**Decision:** make it.\n\n**Alternatives considered:**\n- None. Rejected because: nothing else.\n\n**Chosen because:** it is the thing.\n' "$mb_head" >"$1/design.md"
  printf '# Demo — Test spec\n\n%s\n\n## REQ-A — Things\n\n### REQ-A1.1 — The thing [test]\n\nA fixture test.\n' "$mb_head" >"$1/test-spec.md"
  cat >"$1/tasks.md" <<'EOF'
# Demo — Tasks

**Status:** Ready
**Format-version:** 2
**Execution:** derived — see the status render

## Tasks

### Task 1 — the first unit

- **Deliverables:** a thing
- **Done when:** the thing exists
- **Dependencies:** none
- **Citations:** D-1 · REQ-A1.1
- **Estimated effort:** 1 day

### Task 2 — the second unit

- **Deliverables:** another thing
- **Done when:** it exists
- **Dependencies:** 1
- **Citations:** D-1 · REQ-A1.1
- **Estimated effort:** 1 day
EOF
  mb_anchor=$(hermetic "$S/spec-anchor.sh" "$1") || return 1
  cat >"$1/kickoff-brief.md" <<EOF
# Demo — Kickoff brief

## Amendment log

Class: expression-only
Anchor: \`$mb_anchor\` — computed as
\`scripts/spec-anchor.sh specs/demo\`
EOF
}

# make_work <dir> — the work repository: task 1 completed on main by its
# trailer, and a linked worktree.
make_work() {
  gitq -c init.defaultBranch=main init -q "$1" || return 1
  printf 'x\n' >"$1/file"
  gitq -C "$1" add -A && gitq -C "$1" commit -q -m init || return 1
  printf 'feat: the first unit\n\nPlanwright-Task: demo/1\n' | hermetic git -C "$1" commit -q --allow-empty -F - || return 1
  gitq -C "$1" worktree add -q "$1/.claude/worktrees/wt" -b wt
}

# set_root <work> <value> — spec_root in the work repository's machine-local
# layer, as an operator relocating the root would set it.
set_root() { printf 'spec_root: %s\n' "$2" >"$1/.claude/planwright.local.yml"; }

# Three postures, each in its own work repository.
for posture in in-repo holder plain; do
  w=$tmp/$posture/work
  make_work "$w" || {
    fail "$posture: the work repository fixture could not be built"
    continue
  }
  case $posture in
    in-repo)
      root=$w/docs/spec-home
      value=docs/spec-home
      ;;
    holder)
      gitq -c init.defaultBranch=main init -q "$tmp/$posture/holder"
      root=$tmp/$posture/holder/work-specs
      value=$root
      ;;
    plain)
      root=$tmp/$posture/plain-specs
      value=$root
      ;;
  esac
  mkdir -p "$root"
  printf 'project: fixture\nlayout: 1\n' >"$root/planwright-spec-root.yml"
  make_bundle "$root/demo" || {
    fail "$posture: the bundle fixture could not be built"
    continue
  }
  set_root "$w" "$value"
  wt=$w/.claude/worktrees/wt

  at "$w" "$S/resolve-root.sh" spec --posture
  case $posture in
    holder) want=separate-repo ;;
    plain) want=plain ;;
    *) want=same-repo ;;
  esac
  expect "$posture: the fixture resolves the relocated root in its posture" "$want" "$out"

  # Task state derives from the work repository, not the store (REQ-E1.4).
  at "$w" "$S/orchestrate-state.sh" "$root/demo"
  expect "$posture: state derives task 1 from the work repository's trailer" "task	1	completed	trailer" "$out"
  expect "$posture: state derives task 2 ready" "task	2	ready	deps-met" "$out"

  at "$w" "$S/spec-status.sh" "$root/demo"
  expect "$posture: the status render derives from the work repository" "task 1 completed" "$out"

  at "$w" "$S/orchestrate-meta-select.sh" "$root/demo"
  expect "$posture: meta-select selects the next unit" "$root/demo	2" "$out"

  # The sync hook (REQ-E1.6) locates the bundle through the resolver: with
  # its lock held, it reports the busy lock of the bundle it found.
  mkdir "$root/demo/.orchestrate.lock"
  gitq -C "$w" branch planwright/demo/task-1
  gitq -C "$w" checkout -q planwright/demo/task-1
  # shellcheck disable=SC2016 # the child shell expands its own arguments
  at "$w" sh -c 'printf "%s" "$1" | "$2"' sh \
    '{"tool_name":"Bash","tool_input":{"command":"gh pr create --draft"},"tool_response":{"stdout":"https://github.com/o/r/pull/12","stderr":""}}' \
    "$S/tasks-pr-sync.sh"
  expect "$posture: the sync hook finds the bundle in the relocated root" "lock unavailable (acquire exit 1)" "$out"
  gitq -C "$w" checkout -q main
  rmdir "$root/demo/.orchestrate.lock"

  # The lock needs no `specs` parent (REQ-A1.7), from the checkout or a
  # worktree of it.
  for from in "$w" "$wt"; do
    at "$from" "$S/orchestrate-lock.sh" acquire "$root/demo"
    if [ "$rc" -eq 0 ] && [ -d "$root/demo/.orchestrate.lock" ]; then
      ok "$posture: the lock is taken in the relocated root (from ${from#"$tmp/"})"
    else
      fail "$posture: the lock was refused from ${from#"$tmp/"} (rc=$rc): $out"
    fi
    at "$from" "$S/orchestrate-lock.sh" release "$root/demo"
  done
  mkdir -p "$tmp/$posture/elsewhere/specs/demo"
  at "$w" "$S/orchestrate-lock.sh" acquire "$tmp/$posture/elsewhere/specs/demo"
  expect "$posture: a dir under no resolved spec root is still refused" "not contained under a resolved spec root" "$out"

  at "$w" "$S/fleet-tower-watchdog.sh" "$root/demo"
  expect "$posture: the watchdog takes a bundle whose parent is not named specs" "no-marker" "$out"

  at "$w" "$S/fleet-dispatch-headless.sh" status demo 1
  if [ "$rc" -eq 5 ] && [ "$out" = absent ]; then
    ok "$posture: the headless dispatcher finds the bundle in the relocated root"
  else
    fail "$posture: headless status (rc=$rc): $out"
  fi

  at "$w" "$S/spec-walkthrough.sh" --scope tasks demo
  expect "$posture: the walkthrough loads the relocated bundle" "loaded bundle 'demo'" "$out"

  at "$w" "$S/check-ledger.sh"
  if [ "$rc" -eq 0 ]; then
    ok "$posture: the ledger check scans the relocated root"
  else
    fail "$posture: the ledger check (rc=$rc): $out"
  fi
  at "$w" "$S/check-memory-links.sh"
  expect "$posture: the memory-links check scans the relocated root" "4 scanned spec file(s)" "$out"
  at "$w" "$S/check-anchor-freshness.sh"
  expect "$posture: anchor freshness recomputes the relocated bundle" "ok     demo" "$out"
  at "$w" "$S/migrate-status-lifecycle.sh"
  expect "$posture: the lifecycle migration sweeps the relocated root" "1 unchanged" "$out"
  at "$w" "$S/migrate-format-version.sh"
  expect "$posture: the format migration sweeps the relocated root" "1 unchanged" "$out"

  # A dispatch from inside the worktree places the new worktree under the
  # work repository's primary checkout (REQ-B1.3) and writes the dispatch
  # marker into the relocated bundle (REQ-E1.6).
  at "$wt" "$S/fleet-dispatch-worktree.sh" dispatch demo 2 --no-attach
  expect "$posture: dispatch places the worktree under the primary checkout" \
    "dispatch	worktree	$w/.claude/worktrees/demo-task-2" "$out"
  if [ -f "$root/demo/.orchestrate/markers/2" ]; then
    ok "$posture: dispatch writes its marker into the relocated bundle"
  else
    fail "$posture: no dispatch marker in the relocated bundle: $out"
  fi
  # A commit on the dispatched task branch, in the work repository, is what
  # the state then derives from, wherever the bundle lives (REQ-E1.4).
  gitq -C "$w/.claude/worktrees/demo-task-2" commit -q --allow-empty -m "wip"
  at "$w" "$S/orchestrate-state.sh" "$root/demo"
  expect "$posture: state derives task 2 from the work repository's task branch" "task	2	in-progress	branch-commits" "$out"
done

# The spec checks in mise.toml read the resolved root (REQ-G1.2): the
# validator and the bundle lint run over a relocated root, and the lint
# relaxation is the one found under that root.
task_body() {
  awk -v t="[tasks.\"$1\"]" '
    $0 == t { intask = 1; next }
    intask && /^\[/ { exit }
    intask && /^run = '"'''"'$/ { inbody = 1; next }
    inbody && /^'"'''"'$/ { exit }
    inbody { print }
  ' "$REPO_ROOT/mise.toml"
}
w=$tmp/in-repo/work
root=$w/docs/spec-home
specs_body=$(task_body check:specs)
lint_body=$(task_body lint:md)
[ -n "$specs_body" ] && [ -n "$lint_body" ] || fail "mise.toml: could not read the check:specs and lint:md task bodies"
ln -s "$S" "$w/scripts"
at "$w" sh -c "$specs_body"
if [ "$rc" -eq 0 ]; then ok "check:specs passes a valid relocated root"; else fail "check:specs over the relocated root (rc=$rc): $out"; fi
mkdir -p "$root/broken"
printf '# Broken — Tasks\n' >"$root/broken/tasks.md"
at "$w" sh -c "$specs_body"
if [ "$rc" -ne 0 ]; then ok "check:specs validates the bundles under the relocated root"; else fail "check:specs passed a broken bundle under the relocated root: $out"; fi
rm -rf "$root/broken"

printf '# Long\n\n%s\n' "$(printf 'word %.0s' $(seq 1 40))" >"$root/demo/long.md"
# The linter runs with the operator's own HOME, which a mise-managed install
# needs; the adopter overlay is blanked instead so the root still resolves
# from the fixture alone.
lint() {
  # shellcheck disable=SC2086 # one `-u NAME` pair per word
  out=$(cd "$w" && env $inherited_unsets -u CLAUDE_PLUGIN_ROOT -u CLAUDE_PLUGIN_DATA -u CLAUDE_DIR \
    PLANWRIGHT_ROOT="$REPO_ROOT" PLANWRIGHT_ADOPTER_OVERLAY="$tmp/no-adopter" \
    GIT_CEILING_DIRECTORIES="$tmp" GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 \
    sh -c "$lint_body" 2>&1)
  rc=$?
}
# A mise shim resolves its tool from the working directory's mise config,
# which the fixture has none of, so the tool and its node runtime are put on
# PATH directly where mise can name them.
ml_path=""
if command -v mise >/dev/null 2>&1; then
  for ml_tool in markdownlint-cli2 node; do
    ml_bin=$(cd "$REPO_ROOT" && mise which "$ml_tool" 2>/dev/null) && ml_path="$ml_path${ml_bin%/*}:"
  done
fi
PATH="$ml_path$PATH"
if command -v markdownlint-cli2 >/dev/null 2>&1; then
  lint
  expect "lint:md lints the relocated root" "long.md" "$out"
  expect "lint:md applies the base line-length rule with no relaxation" "MD013" "$out"
  printf '{ "MD013": false }\n' >"$root/.markdownlint.jsonc"
  lint
  case $out in
    *MD013*) fail "lint:md ignored the relocated root's relaxation: $out" ;;
    *) ok "lint:md applies the relaxation found under the relocated root" ;;
  esac
elif [ -n "${GITHUB_ACTIONS:-}" ]; then
  fail "markdownlint-cli2 is not on PATH on the CI runner"
else
  echo "note: markdownlint-cli2 is not on PATH; the lint:md cases were not run"
fi

echo
if [ "$failures" -eq 0 ]; then
  echo "all spec-location relocated-root tests passed"
  exit 0
fi
echo "$failures spec-location relocated-root test(s) failed" >&2
exit 1
