#!/bin/sh
# Unit test for scripts/spec-anchor.sh — the canonical content-anchor
# computation defined in doctrine/spec-format.md (REQ-F1.9).
#
# Verifies the four properties the canonical tasks.md definition-content
# extraction must deliver:
#   1. An orchestration state move (section change + Status / Last activity /
#      Dispatch annotations) does NOT change the anchor.
#   2. An edited Done-when DOES change the anchor.
#   3. Recomputation is deterministic (same input, same anchor).
#   4. Dotted task ids sort canonically (document order is irrelevant).
#
# Runs standalone: ./tests/spec-anchor-test.sh
# (Joins the Task 2 shell test runner's suite when that lands.)
set -eu

here=$(cd "$(dirname "$0")" && pwd)
anchor="$here/../scripts/spec-anchor.sh"

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

[ -x "$anchor" ] || fail "scripts/spec-anchor.sh missing or not executable"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
spec="$tmp/spec"
mkdir "$spec"

printf '%s\n' '# Fixture — Requirements' '' '**Status:** Active' > "$spec/requirements.md"
printf '%s\n' '# Fixture — Design' > "$spec/design.md"
printf '%s\n' '# Fixture — Test Spec' > "$spec/test-spec.md"

# Baseline: three tasks in Forward plan, one with a dotted id and a wrapped
# continuation line.
cat > "$spec/tasks.md" <<'EOF'
# Fixture — Tasks

**Status:** Active

Intro prose that is not task-definition content.

## Forward plan

### Task 1 — First thing

- **Deliverables:** A widget; plus a wrapped deliverable line that
  continues onto a second line.
- **Done when:** The widget exists.
- **Dependencies:** none
- **Citations:** D-1 · REQ-X1.1
- **Estimated effort:** half day

### Task 2 — Second thing

- **Deliverables:** A gadget.
- **Done when:** The gadget exists.
- **Dependencies:** 1
- **Citations:** D-2 · REQ-X1.2
- **Estimated effort:** 1 day

### Task 2.5 — Inserted thing

- **Deliverables:** A gizmo.
- **Done when:** The gizmo exists.
- **Dependencies:** 2
- **Citations:** D-3 · REQ-X1.3
- **Estimated effort:** half day

## In progress

(none yet)

## Completed

(none yet)
EOF

a_base=$("$anchor" "$spec") || fail "anchor computation failed on baseline"

# --- Property 3: determinism ---
a_again=$("$anchor" "$spec")
[ "$a_base" = "$a_again" ] || fail "non-deterministic: $a_base vs $a_again"

# --- Property 1: state move is anchor-invariant ---
# Task 2 moves Forward plan -> In progress, gains Status / Last activity /
# Dispatch annotations (with a continuation line), and the document order of
# the blocks changes (In progress section is written before Forward plan).
cat > "$spec/tasks.md" <<'EOF'
# Fixture — Tasks

**Status:** Active

Intro prose that is not task-definition content.

## In progress

### Task 2 — Second thing

- **Deliverables:** A gadget.
- **Done when:** The gadget exists.
- **Dependencies:** 1
- **Citations:** D-2 · REQ-X1.2
- **Estimated effort:** 1 day
- **Status:** implementing
- **Last activity:** 2026-06-11
- **Dispatch:** backend=tmux · window=`fixture-task-2` · dispatched 2026-06-11T00:00Z ·
  branch `planwright/fixture/task-2` · worktree `.claude/worktrees/task-2`

## Forward plan

### Task 1 — First thing

- **Deliverables:** A widget; plus a wrapped deliverable line that
  continues onto a second line.
- **Done when:** The widget exists.
- **Dependencies:** none
- **Citations:** D-1 · REQ-X1.1
- **Estimated effort:** half day

### Task 2.5 — Inserted thing

- **Deliverables:** A gizmo.
- **Done when:** The gizmo exists.
- **Dependencies:** 2
- **Citations:** D-3 · REQ-X1.3
- **Estimated effort:** half day

## Completed

(none yet)
EOF

a_moved=$("$anchor" "$spec") || fail "anchor computation failed after state move"
[ "$a_base" = "$a_moved" ] || fail "state move changed the anchor: $a_base vs $a_moved"

# --- Property 2: a meaning edit changes the anchor ---
sed 's/The gizmo exists./The gizmo exists and is documented./' "$spec/tasks.md" > "$spec/tasks.md.new"
mv "$spec/tasks.md.new" "$spec/tasks.md"
a_edited=$("$anchor" "$spec") || fail "anchor computation failed after Done-when edit"
[ "$a_base" != "$a_edited" ] || fail "Done-when edit did not change the anchor"

# --- Property 2b: an edit to a non-tasks file changes the anchor ---
printf '%s\n' '# Fixture — Design' 'New decision text.' > "$spec/design.md"
a_design=$("$anchor" "$spec")
[ "$a_edited" != "$a_design" ] || fail "design.md edit did not change the anchor"

# --- Duplicate task ids fail closed ---
# Two blocks claiming the same id would silently overwrite each other in the
# extraction, hashing an incomplete stream (REQ-F1.9 fail-closed mandate).
cp "$spec/tasks.md" "$spec/tasks.md.bak"
cat >> "$spec/tasks.md" <<'EOF'

### Task 2 — Second thing again

- **Deliverables:** A duplicate.
- **Done when:** Never; this input is invalid.
- **Dependencies:** none
- **Citations:** D-2
- **Estimated effort:** half day
EOF
if "$anchor" "$spec" >/dev/null 2>&1; then
  fail "duplicate task id did not fail"
fi
mv "$spec/tasks.md.bak" "$spec/tasks.md"

# --- Unreadable tasks.md fails closed ---
# An awk open failure inside the extraction pipeline must not degrade into a
# successful exit with an anchor over an empty task stream.
chmod 000 "$spec/tasks.md"
if "$anchor" "$spec" >/dev/null 2>&1; then
  chmod 644 "$spec/tasks.md"
  fail "unreadable tasks.md did not fail"
fi
chmod 644 "$spec/tasks.md"

# --- Missing file fails closed ---
rm "$spec/test-spec.md"
if "$anchor" "$spec" >/dev/null 2>&1; then
  fail "missing test-spec.md did not fail"
fi

echo "PASS: spec-anchor-test"
