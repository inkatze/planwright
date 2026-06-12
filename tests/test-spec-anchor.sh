#!/bin/sh
# Unit test for scripts/spec-anchor.sh — the canonical content-anchor
# computation defined in doctrine/spec-format.md (REQ-F1.9).
#
# Properties verified:
#   1. An orchestration state move (section change across In progress /
#      Awaiting input / Completed, plus Status / Last activity / Dispatch and
#      unknown annotation bullets) does NOT change the anchor.
#   2. An edited Done-when (or any non-tasks spec file edit) DOES change it.
#   3. Recomputation is deterministic and emits a 40-hex digest.
#   4. Records sort numerically by task id (1 < 2 < 2.5 < 10), pinned by an
#      independently computed golden manifest.
#   5. A non-task H3 section never leaks into the preceding task's record.
#   6. Failure modes fail closed with a clear stderr message: missing or
#      unreadable file, duplicate task ids, unemittable output.
#
# Runs standalone: ./tests/test-spec-anchor.sh
# (Joins the Task 2 shell test runner's suite when that lands.)
set -eu

# Pin the C locale: the [!0-9a-f] case glob below is collation-dependent for
# the letter range under UTF-8 locales.
LC_ALL=C
export LC_ALL

# A CDPATH-resolved cd echoes the destination into the command substitution
# below, corrupting the derived script path (house pattern, see sibling tests).
unset CDPATH

here=$(cd "$(dirname "$0")" && pwd)
anchor="$here/../scripts/spec-anchor.sh"

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

is_hex40() {
  case $1 in
    *[!0-9a-f]*) return 1 ;;
  esac
  [ ${#1} -eq 40 ]
}

[ -x "$anchor" ] || fail "scripts/spec-anchor.sh missing or not executable"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
spec="$tmp/spec"
mkdir "$spec"

printf '%s\n' '# Fixture — Requirements' '' '**Status:** Active' >"$spec/requirements.md"
printf '%s\n' '# Fixture — Design' >"$spec/design.md"
printf '%s\n' '# Fixture — Test Spec' >"$spec/test-spec.md"

# Baseline: four tasks in Forward plan, with a dotted id, an id >= 10, and a
# wrapped continuation line.
cat >"$spec/tasks.md" <<'EOF'
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

### Task 10 — Tenth thing

- **Deliverables:** A doohickey.
- **Done when:** The doohickey exists.
- **Dependencies:** 2.5
- **Citations:** D-4 · REQ-X1.4
- **Estimated effort:** 1 day

## In progress

(none yet)

## Completed

(none yet)
EOF

a_base=$("$anchor" "$spec") || fail "anchor computation failed on baseline"
is_hex40 "$a_base" || fail "anchor is not a 40-hex digest: $a_base"

# --- Property 3: determinism ---
a_again=$("$anchor" "$spec")
[ "$a_base" = "$a_again" ] || fail "non-deterministic: $a_base vs $a_again"

# --- Property 4: golden manifest pins the normative record order ---
# Computed independently of the script: extraction bytes written by hand in
# numeric id order (a lexicographic sort would place Task 10 between Task 1
# and Task 2), hashed and folded into the manifest per the meta-spec.
cat >"$tmp/expected-extraction" <<'EOF'
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
### Task 10 — Tenth thing
- **Deliverables:** A doohickey.
- **Done when:** The doohickey exists.
- **Dependencies:** 2.5
- **Citations:** D-4 · REQ-X1.4
- **Estimated effort:** 1 day
EOF
exp_anchor=$(printf '%s\n%s\n%s\n%s\n' \
  "$(git hash-object "$spec/requirements.md")" \
  "$(git hash-object "$spec/design.md")" \
  "$(git hash-object "$tmp/expected-extraction")" \
  "$(git hash-object "$spec/test-spec.md")" | git hash-object --stdin)
[ "$a_base" = "$exp_anchor" ] \
  || fail "anchor deviates from the independently computed golden manifest: $a_base vs $exp_anchor"

# --- Property 1: state moves are anchor-invariant ---
# Task 1 completes, Task 2 dispatches, Task 2.5 awaits input; document order
# shuffles; annotations appear, including an unknown future annotation bullet.
cat >"$spec/tasks.md" <<'EOF'
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
- **Reviewed-by:** an annotation kind this version does not know
- **Dispatch:** backend=tmux · window=`fixture-task-2` · dispatched 2026-06-11T00:00Z ·
  branch `planwright/fixture/task-2` · worktree `.claude/worktrees/task-2`

## Awaiting input

### Task 2.5 — Inserted thing

- **Deliverables:** A gizmo.
- **Done when:** The gizmo exists.
- **Dependencies:** 2
- **Citations:** D-3 · REQ-X1.3
- **Estimated effort:** half day
- **Status:** awaiting input — which color should the gizmo be?

## Forward plan

### Task 10 — Tenth thing

- **Deliverables:** A doohickey.
- **Done when:** The doohickey exists.
- **Dependencies:** 2.5
- **Citations:** D-4 · REQ-X1.4
- **Estimated effort:** 1 day

## Completed

### Task 1 — First thing

- **Deliverables:** A widget; plus a wrapped deliverable line that
  continues onto a second line.
- **Done when:** The widget exists.
- **Dependencies:** none
- **Citations:** D-1 · REQ-X1.1
- **Estimated effort:** half day
- **Status:** merged in PR #7
- **Last activity:** 2026-06-11
EOF

a_moved=$("$anchor" "$spec") || fail "anchor computation failed after state moves"
[ "$a_base" = "$a_moved" ] || fail "state moves changed the anchor: $a_base vs $a_moved"

# --- Property 2: a meaning edit changes the anchor ---
sed 's/The gizmo exists./The gizmo exists and is documented./' "$spec/tasks.md" >"$spec/tasks.md.new"
mv "$spec/tasks.md.new" "$spec/tasks.md"
a_edited=$("$anchor" "$spec") || fail "anchor computation failed after Done-when edit"
[ "$a_base" != "$a_edited" ] || fail "Done-when edit did not change the anchor"

# --- Property 2b: an edit to a non-tasks file changes the anchor ---
printf '%s\n' '# Fixture — Design' 'New decision text.' >"$spec/design.md"
a_design=$("$anchor" "$spec")
[ "$a_edited" != "$a_design" ] || fail "design.md edit did not change the anchor"

# --- Property 5: a non-task H3 section is excluded from the extraction ---
# A task block ends at the next H2/H3 heading (doctrine/spec-format.md);
# definition-like bullets under a non-task H3 directly following a task block
# must not leak into that task's record.
cp "$spec/tasks.md" "$spec/tasks.md.bak"
cat >>"$spec/tasks.md" <<'EOF'

### Task 9 — Tail thing

- **Done when:** the tail task exists.
EOF
a_tail=$("$anchor" "$spec") || fail "anchor computation failed with tail task"
cat >>"$spec/tasks.md" <<'EOF'

### Notes

- **Done when:** sneaky bullet that must not join the preceding task block
EOF
a_notes=$("$anchor" "$spec") || fail "anchor computation failed with non-task H3 section"
mv "$spec/tasks.md.bak" "$spec/tasks.md"
[ "$a_tail" = "$a_notes" ] || fail "non-task H3 section content leaked into the anchor: $a_tail vs $a_notes"

# --- Zero task blocks: succeeds, deterministic, well-formed ---
cat >"$spec/tasks.md" <<'EOF'
# Fixture — Tasks

**Status:** Active

## Forward plan

(none yet)

## Completed

(none yet)
EOF
a_zero=$("$anchor" "$spec") || fail "anchor computation failed on zero-task fixture"
is_hex40 "$a_zero" || fail "zero-task anchor is not a 40-hex digest: $a_zero"
a_zero2=$("$anchor" "$spec")
[ "$a_zero" = "$a_zero2" ] || fail "zero-task anchor non-deterministic"

# --- Duplicate task ids fail closed, with a clear message ---
cat >"$spec/tasks.md" <<'EOF'
## Forward plan

### Task 2 — Second thing

- **Done when:** The gadget exists.

### Task 2 — Second thing again

- **Done when:** Never; this input is invalid.
EOF
if err=$("$anchor" "$spec" 2>&1 >/dev/null); then
  fail "duplicate task id did not fail"
fi
case $err in
  *"duplicate task id"*) ;;
  *) fail "duplicate-id failure lacks a clear message: $err" ;;
esac

# Restore a valid tasks.md for the remaining cases.
cat >"$spec/tasks.md" <<'EOF'
## Forward plan

### Task 1 — First thing

- **Done when:** The widget exists.
EOF

# --- Unreadable tasks.md fails closed ---
# An awk open failure inside the extraction must not degrade into a
# successful exit with an anchor over an empty task stream. Skipped under
# uid 0: the kernel lets root read mode-000 files, so the case cannot be
# exercised there.
if [ "$(id -u)" -ne 0 ]; then
  chmod 000 "$spec/tasks.md"
  if err=$("$anchor" "$spec" 2>&1 >/dev/null); then
    chmod 644 "$spec/tasks.md"
    fail "unreadable tasks.md did not fail"
  fi
  chmod 644 "$spec/tasks.md"
  case $err in
    *"missing or unreadable"*) ;;
    *) fail "unreadable-file failure lacks a clear message: $err" ;;
  esac
fi

# --- Unwritable stdout fails closed ---
# git hash-object ignores a failed write to a closed stdout and still exits 0;
# the script must not report success when it could not emit the anchor.
if "$anchor" "$spec" >&- 2>/dev/null; then
  fail "closed stdout did not fail"
fi

# --- Missing file fails closed, with a clear message ---
rm "$spec/test-spec.md"
if err=$("$anchor" "$spec" 2>&1 >/dev/null); then
  fail "missing test-spec.md did not fail"
fi
case $err in
  *"missing or unreadable"*) ;;
  *) fail "missing-file failure lacks a clear message: $err" ;;
esac

echo "PASS: test-spec-anchor"
