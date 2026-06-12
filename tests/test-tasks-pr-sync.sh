#!/bin/bash
# Tests for scripts/tasks-pr-sync.sh — the PostToolUse hook that syncs
# tasks.md sections on `gh pr create` / `gh pr merge` (Task 6, REQ-K1.2,
# REQ-K1.4, D-36, D-44).
#
# Fixture map (test-spec.md REQ-K1.2 / REQ-K1.4):
#   - positive: single id, dotted id (task-3.5), bundle (task-3-4) move
#     their blocks; create → In progress, merge → Completed
#   - anchor invariance: a hook move never changes the spec content anchor
#     (scripts/spec-anchor.sh before == after)
#   - hostile: spec segment failing REQ-A1.8, id segment failing the D-36
#     grammar, `..`, extra path separators, metacharacters, the reserved
#     `planwright/<spec>/spec` namespace — each a clean no-op
#   - containment: a resolved tasks.md outside <primary>/specs/ (symlinked
#     spec dir) is rejected
#   - worker sessions: a hook run inside a linked worktree writes the
#     primary checkout's tasks.md (kickoff brief risk row 3)
#   - advisory lock: busy lock → clean no-op; stale lock → broken; local
#     config override of stale_lock_threshold is honored (D-33 wiring)
set -eu
LC_ALL=C
export LC_ALL
unset CDPATH

here=$(cd "$(dirname "$0")" && pwd)
HOOK="$here/../scripts/tasks-pr-sync.sh"
ANCHOR="$here/../scripts/spec-anchor.sh"

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

[ -x "$HOOK" ] || fail "scripts/tasks-pr-sync.sh missing or not executable"
[ -x "$ANCHOR" ] || fail "scripts/spec-anchor.sh missing (anchor invariance check needs it)"
command -v jq >/dev/null 2>&1 || fail "jq required to run this suite"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
today=$(date -u +%Y-%m-%d)

# --- gh stub: deterministic, no network. Honors GH_HEADREF when set
# (simulating `gh pr view <n> --json headRefName`); everything else fails,
# so the suite never falls through to a real gh binary.
stub=$tmp/bin
mkdir -p "$stub"
cat >"$stub/gh" <<'EOF'
#!/bin/sh
case "$*" in
  *headRefName*)
    if [ -n "${GH_HEADREF:-}" ]; then
      printf '%s\n' "$GH_HEADREF"
      exit 0
    fi
    exit 1
    ;;
  *) exit 1 ;;
esac
EOF
chmod +x "$stub/gh"

write_spec() { # $1 = spec dir
  mkdir -p "$1"
  printf '%s\n' '# Demo — Requirements' '' '**Status:** Active' >"$1/requirements.md"
  printf '%s\n' '# Demo — Design' >"$1/design.md"
  printf '%s\n' '# Demo — Test Spec' >"$1/test-spec.md"
  cat >"$1/tasks.md" <<'EOF'
# Demo — Tasks

**Status:** Active
**Last reviewed:** 2026-06-12
**Format-version:** 1

## Forward plan

### Task 3 — Widget parser

- **Deliverables:** A widget parser.
- **Done when:** Parses widgets.
- **Dependencies:** none
- **Citations:** REQ-X1.1
- **Estimated effort:** 1 day

### Task 3.5 — Widget polish

- **Deliverables:** Polish for widgets,
  wrapped onto a second line.
- **Done when:** Widgets shine.
- **Dependencies:** 3
- **Citations:** REQ-X1.2
- **Estimated effort:** half day

### Task 4 — Gadget integration

- **Deliverables:** Gadgets.
- **Done when:** Gadgets integrate.
- **Dependencies:** 3
- **Citations:** REQ-X1.3
- **Estimated effort:** 1 day
- **Status:** implementing
- **Last activity:** 2026-06-11
- **Dispatch:** backend=tmux · window=`pw-demo-task-4` · dispatched 2026-06-11T20:00Z ·
  branch `planwright/demo/task-4` · worktree `.claude/worktrees/task-4`

## In progress

(none yet)

## Awaiting input

(none yet)

## Completed

(none yet)
EOF
}

make_repo() { # $1 = repo dir
  mkdir -p "$1"
  git -C "$1" init -q -b main
  git -C "$1" config user.email test@example.com
  git -C "$1" config user.name test
  git -C "$1" config commit.gpgsign false
  write_spec "$1/specs/demo"
  git -C "$1" add -A
  git -C "$1" commit -qm "chore: fixture"
}

run_hook() { # $1 = cwd, $2 = command, $3 = command stdout
  (
    cd "$1" \
      && printf '{"tool_name":"Bash","tool_input":{"command":"%s"},"tool_response":{"stdout":"%s","stderr":""}}' "$2" "$3" \
      | PATH="$stub:$PATH" "$HOOK"
  )
}

section_of() { # $1 = tasks.md, $2 = task id → section name (or empty)
  awk -v id="$2" '
    /^## / { sec = substr($0, 4) }
    index($0, "### Task " id " ") == 1 { print sec; exit }
  ' "$1"
}

block_of() { # $1 = tasks.md, $2 = task id → block lines
  awk -v id="$2" '
    found && (/^## / || /^### /) { exit }
    index($0, "### Task " id " ") == 1 { found = 1 }
    found { print }
  ' "$1"
}

assert_unchanged() { # $1 = label, $2 = tasks.md, $3 = pristine copy
  cmp -s "$2" "$3" || fail "$1: tasks.md changed but should be a clean no-op"
}

# ---------------------------------------------------------------------------
# 1. `gh pr create` on a single-id branch moves the block to In progress.
repo=$tmp/r1
make_repo "$repo"
anchor_before=$("$ANCHOR" "$repo/specs/demo")
git -C "$repo" checkout -qb planwright/demo/task-3
run_hook "$repo" "gh pr create --draft --title t --body b" "https://github.com/o/r/pull/12" \
  || fail "create: hook exited non-zero"
[ "$(section_of "$repo/specs/demo/tasks.md" 3)" = "In progress" ] \
  || fail "create: Task 3 not in In progress"
block_of "$repo/specs/demo/tasks.md" 3 | grep -q -- '- \*\*Status:\*\* PR #12 draft' \
  || fail "create: missing 'PR #12 draft' status annotation"
block_of "$repo/specs/demo/tasks.md" 3 | grep -q -- "- \*\*Last activity:\*\* $today" \
  || fail "create: missing Last activity annotation"
block_of "$repo/specs/demo/tasks.md" 3 | grep -q -- '- \*\*Done when:\*\* Parses widgets\.' \
  || fail "create: definition content lost in the move"
grep -A2 '^## In progress' "$repo/specs/demo/tasks.md" | grep -q '(none yet)' \
  && fail "create: '(none yet)' placeholder not removed from In progress"
anchor_after=$("$ANCHOR" "$repo/specs/demo")
[ "$anchor_before" = "$anchor_after" ] \
  || fail "create: hook move changed the content anchor (REQ-F1.9 breakage)"
echo "ok: create moves single-id block to In progress, anchor invariant"

# 1b. A second fire for the same PR event is idempotent (byte-identical).
cp "$repo/specs/demo/tasks.md" "$tmp/after-create.md"
run_hook "$repo" "gh pr create --draft --title t --body b" "https://github.com/o/r/pull/12" \
  || fail "idempotent create: hook exited non-zero"
cmp -s "$repo/specs/demo/tasks.md" "$tmp/after-create.md" \
  || fail "idempotent create: second fire changed tasks.md"
echo "ok: second fire for the same PR event is idempotent"

# 2. `gh pr merge` on the same branch moves the block to Completed.
run_hook "$repo" "gh pr merge 12 --squash" "Merged pull request #12" \
  || fail "merge: hook exited non-zero"
[ "$(section_of "$repo/specs/demo/tasks.md" 3)" = "Completed" ] \
  || fail "merge: Task 3 not in Completed"
block_of "$repo/specs/demo/tasks.md" 3 | grep -q -- "- \*\*Status:\*\* Completed · PR #12 merged $today" \
  || fail "merge: missing Completed status annotation"
block_of "$repo/specs/demo/tasks.md" 3 | grep -q -- '- \*\*Deliverables:\*\* A widget parser\.' \
  || fail "merge: definition content lost in the move"
grep -A2 '^## Completed' "$repo/specs/demo/tasks.md" | grep -q '(none yet)' \
  && fail "merge: '(none yet)' placeholder not removed from Completed"
[ "$("$ANCHOR" "$repo/specs/demo")" = "$anchor_before" ] \
  || fail "merge: hook move changed the content anchor"
echo "ok: merge moves block to Completed, anchor invariant"

# 3. Dotted id (D-36 blessed: task-3.5) is a positive fixture.
git -C "$repo" checkout -qb planwright/demo/task-3.5
run_hook "$repo" "gh pr create --draft" "https://github.com/o/r/pull/13" \
  || fail "dotted: hook exited non-zero"
[ "$(section_of "$repo/specs/demo/tasks.md" 3.5)" = "In progress" ] \
  || fail "dotted: Task 3.5 not in In progress"
block_of "$repo/specs/demo/tasks.md" 3.5 | grep -q 'wrapped onto a second line\.' \
  || fail "dotted: wrapped continuation line lost"
echo "ok: dotted id task-3.5 moves"

# 4. Bundle branch (task-3-4): merge moves both blocks; existing Status /
#    Last activity / Dispatch annotations are rewritten, Dispatch preserved.
repo=$tmp/r2
make_repo "$repo"
anchor_before=$("$ANCHOR" "$repo/specs/demo")
git -C "$repo" checkout -qb planwright/demo/task-3-4
run_hook "$repo" "gh pr merge --squash" "Merged pull request #9" \
  || fail "bundle: hook exited non-zero"
[ "$(section_of "$repo/specs/demo/tasks.md" 3)" = "Completed" ] \
  || fail "bundle: Task 3 not in Completed"
[ "$(section_of "$repo/specs/demo/tasks.md" 4)" = "Completed" ] \
  || fail "bundle: Task 4 not in Completed"
block_of "$repo/specs/demo/tasks.md" 4 | grep -q -- "- \*\*Status:\*\* Completed · PR #9 merged $today" \
  || fail "bundle: Task 4 status not rewritten"
block_of "$repo/specs/demo/tasks.md" 4 | grep -cq -- '- \*\*Status:\*\*' \
  || fail "bundle: Task 4 status annotation missing"
[ "$(block_of "$repo/specs/demo/tasks.md" 4 | grep -c -- '- \*\*Status:\*\*')" = 1 ] \
  || fail "bundle: duplicate Status annotations on Task 4"
block_of "$repo/specs/demo/tasks.md" 4 | grep -q -- '- \*\*Dispatch:\*\* backend=tmux' \
  || fail "bundle: Dispatch annotation dropped"
block_of "$repo/specs/demo/tasks.md" 4 | grep -qF "worktree \`.claude/worktrees/task-4\`" \
  || fail "bundle: Dispatch continuation line dropped"
[ "$("$ANCHOR" "$repo/specs/demo")" = "$anchor_before" ] \
  || fail "bundle: hook move changed the content anchor"
echo "ok: bundle task-3-4 merge moves both blocks"

# 5. Merge from a non-convention branch (e.g. main) resolves the head branch
#    via gh (graceful: without gh it is a no-op, REQ-K1.6). Empty stdout also
#    exercises the explicit-number-argument PR fallback (`gh pr merge 7`).
repo=$tmp/r3
make_repo "$repo"
GH_HEADREF=planwright/demo/task-4 run_hook "$repo" "gh pr merge 7 --squash" "" \
  || fail "headref: hook exited non-zero"
[ "$(section_of "$repo/specs/demo/tasks.md" 4)" = "Completed" ] \
  || fail "headref: Task 4 not in Completed via gh headRefName"
echo "ok: merge from main resolves branch via gh headRefName"

# 5b. tool_response delivered as a plain string (not an object) still works.
repo=$tmp/r3b
make_repo "$repo"
git -C "$repo" checkout -qb planwright/demo/task-3
(
  cd "$repo" \
    && printf '{"tool_name":"Bash","tool_input":{"command":"gh pr create --draft"},"tool_response":"https://github.com/o/r/pull/21"}' \
    | PATH="$stub:$PATH" "$HOOK"
) || fail "string tool_response: hook exited non-zero"
[ "$(section_of "$repo/specs/demo/tasks.md" 3)" = "In progress" ] \
  || fail "string tool_response: Task 3 not moved"
block_of "$repo/specs/demo/tasks.md" 3 | grep -q -- '- \*\*Status:\*\* PR #21 draft' \
  || fail "string tool_response: PR number not extracted from string response"
echo "ok: plain-string tool_response is handled"

# ---------------------------------------------------------------------------
# Hostile / no-op fixtures. Each must leave tasks.md byte-identical.
repo=$tmp/r4
make_repo "$repo"
pristine=$tmp/pristine.md
cp "$repo/specs/demo/tasks.md" "$pristine"
tasks=$repo/specs/demo/tasks.md

# 6. Non-Bash tool and empty input are no-ops.
(cd "$repo" && printf '{"tool_name":"Read","tool_input":{}}' | PATH="$stub:$PATH" "$HOOK") \
  || fail "non-Bash tool: hook exited non-zero"
assert_unchanged "non-Bash tool" "$tasks" "$pristine"
(cd "$repo" && printf '' | PATH="$stub:$PATH" "$HOOK") || fail "empty input: non-zero exit"
assert_unchanged "empty input" "$tasks" "$pristine"
echo "ok: non-Bash tool / empty input no-op"

# 7. A command merely mentioning gh pr create is a no-op.
git -C "$repo" checkout -qb planwright/demo/task-3
run_hook "$repo" "echo gh pr create" "gh pr create" || fail "mention: non-zero exit"
assert_unchanged "command mention" "$tasks" "$pristine"
echo "ok: non-invocation mention of gh pr create no-ops"

# 8. No derivable PR number is a clean no-op (gh stub fails).
run_hook "$repo" "gh pr create --draft" "" || fail "no-pr-num: non-zero exit"
assert_unchanged "no PR number" "$tasks" "$pristine"
echo "ok: missing PR number no-ops"

# 9. Reserved spec namespace planwright/<spec>/spec no-ops (D-44).
git -C "$repo" checkout -qb planwright/demo/spec
run_hook "$repo" "gh pr create --draft" "https://github.com/o/r/pull/12" \
  || fail "reserved: non-zero exit"
assert_unchanged "reserved spec namespace" "$tasks" "$pristine"
echo "ok: reserved spec namespace no-ops"

# 10. Hostile branch names reachable as real git refs: each a clean no-op.
for b in \
  main \
  planwright/Bad_Spec/task-3 \
  planwright/demo/task-.5 \
  planwright/demo/task-3- \
  planwright/demo/task-3.5.6 \
  "planwright/demo/task-3;x" \
  planwright/a/b/task-3 \
  planwright/demo/task-9 \
  planwright/nosuch/task-3; do
  git -C "$repo" checkout -q main
  git -C "$repo" branch -q "$b" 2>/dev/null || true
  git -C "$repo" checkout -q "$b" 2>/dev/null || fail "fixture branch not creatable: $b"
  run_hook "$repo" "gh pr create --draft" "https://github.com/o/r/pull/12" \
    || fail "hostile branch $b: non-zero exit"
  assert_unchanged "hostile branch $b" "$tasks" "$pristine"
done
echo "ok: hostile / non-matching real branches no-op"

# 11. Hostile head refs only reachable via gh (git refuses these refnames):
#     charset, dotted-escape, and metacharacter specs never reach a path.
git -C "$repo" checkout -q main
for ref in \
  "planwright/../task-3" \
  "planwright/demo/task-3..5" \
  "planwright/demo;rm -rf x/task-3" \
  "planwright/demo/extra/task-3" \
  "planwright/demo"; do
  GH_HEADREF=$ref run_hook "$repo" "gh pr merge 12 --squash" "" \
    || fail "hostile headref $ref: non-zero exit"
  assert_unchanged "hostile headref $ref" "$tasks" "$pristine"
done
echo "ok: hostile gh head refs no-op"

# 11b. A tasks.md missing the target section is a clean no-op.
nosec=$tmp/r4b
mkdir -p "$nosec"
git -C "$nosec" init -q -b main
git -C "$nosec" config user.email test@example.com
git -C "$nosec" config user.name test
git -C "$nosec" config commit.gpgsign false
mkdir -p "$nosec/specs/demo"
cat >"$nosec/specs/demo/tasks.md" <<'EOF'
# Demo — Tasks

## Forward plan

### Task 3 — Widget parser

- **Deliverables:** A widget parser.
- **Done when:** Parses widgets.

## Completed

(none yet)
EOF
git -C "$nosec" add -A
git -C "$nosec" commit -qm "chore: fixture"
git -C "$nosec" checkout -qb planwright/demo/task-3
cp "$nosec/specs/demo/tasks.md" "$tmp/nosec-pristine.md"
run_hook "$nosec" "gh pr create --draft" "https://github.com/o/r/pull/12" \
  || fail "missing section: non-zero exit"
cmp -s "$nosec/specs/demo/tasks.md" "$tmp/nosec-pristine.md" \
  || fail "missing section: tasks.md changed despite no '## In progress' section"
echo "ok: missing target section is a clean no-op"

# 12. Containment: a charset-clean spec whose directory symlinks outside
#     <primary>/specs/ is rejected (symlink-resolved prefix check).
outside=$tmp/outside
write_spec "$outside"
ln -s "$outside" "$repo/specs/evil"
cp "$outside/tasks.md" "$tmp/outside-pristine.md"
git -C "$repo" checkout -q main
git -C "$repo" checkout -qb planwright/evil/task-3
run_hook "$repo" "gh pr create --draft" "https://github.com/o/r/pull/12" \
  || fail "containment: non-zero exit"
cmp -s "$outside/tasks.md" "$tmp/outside-pristine.md" \
  || fail "containment: hook wrote through a symlinked spec dir"
echo "ok: symlinked spec dir is containment-rejected"

# ---------------------------------------------------------------------------
# 13. Worker sessions: a hook run inside a linked worktree writes the
#     primary checkout's tasks.md, not the worktree copy (risk row 3).
repo=$tmp/r5
make_repo "$repo"
wt=$repo/.claude/worktrees/task-3
git -C "$repo" worktree add -q "$wt" -b planwright/demo/task-3
cp "$wt/specs/demo/tasks.md" "$tmp/wt-pristine.md"
run_hook "$wt" "gh pr create --draft" "https://github.com/o/r/pull/12" \
  || fail "worktree: non-zero exit"
[ "$(section_of "$repo/specs/demo/tasks.md" 3)" = "In progress" ] \
  || fail "worktree: primary checkout tasks.md not updated"
cmp -s "$wt/specs/demo/tasks.md" "$tmp/wt-pristine.md" \
  || fail "worktree: hook wrote the worktree copy instead of the primary's"
echo "ok: worktree run writes the primary checkout"

# ---------------------------------------------------------------------------
# 14. Advisory lock: a fresh (busy) lock is a clean no-op; a stale lock is
#     broken; the local stale_lock_threshold override is honored (D-33).
repo=$tmp/r6
make_repo "$repo"
pristine6=$tmp/pristine6.md
cp "$repo/specs/demo/tasks.md" "$pristine6"
git -C "$repo" checkout -qb planwright/demo/task-3
mkdir "$repo/specs/demo/.orchestrate.lock"
run_hook "$repo" "gh pr create --draft" "https://github.com/o/r/pull/12" \
  || fail "busy lock: non-zero exit"
assert_unchanged "busy lock" "$repo/specs/demo/tasks.md" "$pristine6"

touch -t 202001010000 "$repo/specs/demo/.orchestrate.lock"
run_hook "$repo" "gh pr create --draft" "https://github.com/o/r/pull/12" \
  || fail "stale lock: non-zero exit"
[ "$(section_of "$repo/specs/demo/tasks.md" 3)" = "In progress" ] \
  || fail "stale lock: not broken at the default threshold"
[ ! -d "$repo/specs/demo/.orchestrate.lock" ] || fail "stale lock: lock not released"
echo "ok: busy lock no-ops, stale lock breaks"

repo=$tmp/r7
make_repo "$repo"
pristine7=$tmp/pristine7.md
cp "$repo/specs/demo/tasks.md" "$pristine7"
git -C "$repo" checkout -qb planwright/demo/task-3
mkdir -p "$repo/.claude"
printf 'stale_lock_threshold: 99999999m\n' >"$repo/.claude/planwright.local.yml"
mkdir "$repo/specs/demo/.orchestrate.lock"
touch -t 202001010000 "$repo/specs/demo/.orchestrate.lock"
run_hook "$repo" "gh pr create --draft" "https://github.com/o/r/pull/12" \
  || fail "override lock: non-zero exit"
assert_unchanged "stale_lock_threshold override" "$repo/specs/demo/tasks.md" "$pristine7"
echo "ok: local stale_lock_threshold override is honored"

# 15. A malformed stale_lock_threshold falls back to the tracked default
#     with a warning (config-model fallback rule): the 2020 lock is stale at
#     the default 15m, so the move proceeds.
printf 'stale_lock_threshold: banana\n' >"$repo/.claude/planwright.local.yml"
mkdir -p "$repo/specs/demo/.orchestrate.lock"
touch -t 202001010000 "$repo/specs/demo/.orchestrate.lock"
err=$( (run_hook "$repo" "gh pr create --draft" "https://github.com/o/r/pull/12") 2>&1 >/dev/null) \
  || fail "malformed threshold: non-zero exit"
[ "$(section_of "$repo/specs/demo/tasks.md" 3)" = "In progress" ] \
  || fail "malformed threshold: default fallback did not break the stale lock"
case $err in
  *"malformed stale_lock_threshold"*) ;;
  *) fail "malformed threshold: no fallback warning on stderr" ;;
esac
echo "ok: malformed stale_lock_threshold warns and falls back to the default"

echo "PASS: all tasks-pr-sync tests passed"
