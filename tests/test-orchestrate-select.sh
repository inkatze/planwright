#!/bin/bash
# Tests for scripts/orchestrate-select.sh — the critical-path-first ready-unit
# selector behind /orchestrate (Task 13, REQ-F1.2, D-7, D-8).
#
# Selection contract (REQ-F1.2):
#   - a ready task is one in ## Forward plan whose every dependency sits in
#     ## Completed (In progress / Awaiting input / terminal tasks are not
#     candidates);
#   - among ready tasks, the head of the effort-weighted longest dependent
#     chain wins (critical-path-first); FIFO (file order) breaks ties;
#   - no ready task → exit 1 (nothing to dispatch this step);
#   - a missing / taskless tasks.md → exit 2 (fail closed).
#
# Runs standalone under /bin/bash (the bash 3.2 floor).
set -eu
LC_ALL=C
export LC_ALL
unset CDPATH

here=$(cd "$(dirname "$0")" && pwd)
SEL="$here/../scripts/orchestrate-select.sh"

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

[ -x "$SEL" ] || fail "scripts/orchestrate-select.sh missing or not executable"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# 1. Critical-path-first: a ready task heading a long dependent chain beats a
#    ready leaf, even when both have the same (smaller) per-task effort.
#    Completed: 1. Forward plan: 2 (deps 1, heads 2->3->4), 5 (deps 1, leaf),
#    3 (deps 2, not ready), 4 (deps 3, not ready).
d1="$tmp/chain"
mkdir -p "$d1"
cat >"$d1/tasks.md" <<'EOF'
# tasks

## Forward plan

### Task 2 — chain head

- **Dependencies:** 1
- **Estimated effort:** half day

### Task 5 — leaf

- **Dependencies:** 1
- **Estimated effort:** half day

### Task 3 — chain middle

- **Dependencies:** 2
- **Estimated effort:** 1 day

### Task 4 — chain tail

- **Dependencies:** 3
- **Estimated effort:** 1 day

## Completed

### Task 1 — root

- **Dependencies:** none
- **Estimated effort:** half day
EOF
got=$(/bin/bash "$SEL" "$d1") || fail "chain fixture: non-zero exit ($?)"
[ "$got" = 2 ] || fail "chain fixture: selected '$got', expected 2 (longest chain)"
echo "ok: critical-path-first selects the chain head over a leaf"

# 2. FIFO on ties: two ready leaves of equal weight → the earlier-in-file one.
d2="$tmp/tie"
mkdir -p "$d2"
cat >"$d2/tasks.md" <<'EOF'
# tasks

## Forward plan

### Task 7 — earlier-in-file leaf

- **Dependencies:** 1
- **Estimated effort:** 1 day

### Task 6 — later-in-file leaf

- **Dependencies:** 1
- **Estimated effort:** 1 day

## Completed

### Task 1 — root

- **Dependencies:** none
- **Estimated effort:** half day
EOF
got=$(/bin/bash "$SEL" "$d2") || fail "tie fixture: non-zero exit"
[ "$got" = 7 ] || fail "tie fixture: selected '$got', expected 7 (FIFO/file order)"
echo "ok: FIFO (file order) breaks weight ties"

# 3. A task whose dependency is not Completed is not ready; an In-progress
#    task is never a candidate. Here only 9's deps are met.
d3="$tmp/notready"
mkdir -p "$d3"
cat >"$d3/tasks.md" <<'EOF'
# tasks

## Forward plan

### Task 8 — blocked

- **Dependencies:** 5
- **Estimated effort:** 1 day

### Task 9 — ready

- **Dependencies:** 1
- **Estimated effort:** half day

## In progress

### Task 5 — running

- **Dependencies:** 1
- **Estimated effort:** 1 day

## Completed

### Task 1 — root

- **Dependencies:** none
- **Estimated effort:** half day
EOF
got=$(/bin/bash "$SEL" "$d3") || fail "notready fixture: non-zero exit"
[ "$got" = 9 ] || fail "notready fixture: selected '$got', expected 9"
echo "ok: a task with an uncompleted dep (and an In-progress task) is skipped"

# 4. No ready task → exit 1.
d4="$tmp/none"
mkdir -p "$d4"
cat >"$d4/tasks.md" <<'EOF'
# tasks

## Forward plan

### Task 3 — blocked on an unfinished dep

- **Dependencies:** 2
- **Estimated effort:** 1 day

## In progress

### Task 2 — running

- **Dependencies:** none
- **Estimated effort:** 1 day
EOF
rc=0
/bin/bash "$SEL" "$d4" >/dev/null 2>&1 || rc=$?
[ "$rc" = 1 ] || fail "no-ready fixture: exit $rc, expected 1"
echo "ok: no ready task exits 1"

# 5. Missing tasks.md → exit 2 (fail closed).
rc=0
/bin/bash "$SEL" "$tmp/does-not-exist" >/dev/null 2>&1 || rc=$?
[ "$rc" = 2 ] || fail "missing tasks.md: exit $rc, expected 2"
# A taskless tasks.md is malformed for selection → exit 2.
d6="$tmp/empty"
mkdir -p "$d6"
printf '# tasks\n\n## Forward plan\n\n(none)\n' >"$d6/tasks.md"
rc=0
/bin/bash "$SEL" "$d6" >/dev/null 2>&1 || rc=$?
[ "$rc" = 2 ] || fail "taskless tasks.md: exit $rc, expected 2"
echo "ok: missing / taskless tasks.md fails closed with exit 2"

# 6. A dotted task id (3.5) is a valid candidate and selectable.
d7="$tmp/dotted"
mkdir -p "$d7"
cat >"$d7/tasks.md" <<'EOF'
# tasks

## Forward plan

### Task 3.5 — fractional, ready

- **Dependencies:** 1
- **Estimated effort:** 2 days

## Completed

### Task 1 — root

- **Dependencies:** none
- **Estimated effort:** half day
EOF
got=$(/bin/bash "$SEL" "$d7") || fail "dotted fixture: non-zero exit"
[ "$got" = 3.5 ] || fail "dotted fixture: selected '$got', expected 3.5"
echo "ok: dotted task ids parse and select"

# 7. A Forward-plan task with no effective dependencies ("Dependencies: none",
#    the canonical depless form per spec-format's required task fields) is ready
#    and selectable.
d8="$tmp/nodeps"
mkdir -p "$d8"
cat >"$d8/tasks.md" <<'EOF'
# tasks

## Forward plan

### Task 1 — depless root

- **Dependencies:** none
- **Estimated effort:** 1 day
EOF
got=$(/bin/bash "$SEL" "$d8") || fail "depless fixture: non-zero exit"
[ "$got" = 1 ] || fail "depless fixture: selected '$got', expected 1"
echo "ok: a task with 'Dependencies: none' is ready"

# 8. A task whose dependency does not exist as a task record is NOT ready
#    (a dangling id is never in ## Completed, so it fails closed to blocked) —
#    selection must skip it and pick the genuinely-ready task instead.
d9="$tmp/dangling"
mkdir -p "$d9"
cat >"$d9/tasks.md" <<'EOF'
# tasks

## Forward plan

### Task 3 — depends on a non-existent task

- **Dependencies:** 99
- **Estimated effort:** 3 days

### Task 2 — genuinely ready

- **Dependencies:** none
- **Estimated effort:** half day
EOF
got=$(/bin/bash "$SEL" "$d9") || fail "dangling-dep fixture: non-zero exit"
[ "$got" = 2 ] || fail "dangling-dep fixture: selected '$got', expected 2 (task 3 is blocked)"
# And when the dangling-dep task is the only candidate, nothing is ready.
d9b="$tmp/dangling-only"
mkdir -p "$d9b"
cat >"$d9b/tasks.md" <<'EOF'
# tasks

## Forward plan

### Task 3 — depends on a non-existent task

- **Dependencies:** 99
- **Estimated effort:** 3 days
EOF
rc=0
/bin/bash "$SEL" "$d9b" >/dev/null 2>&1 || rc=$?
[ "$rc" = 1 ] || fail "dangling-only fixture: exit $rc, expected 1 (no ready task)"
echo "ok: a task with a non-existent dependency is treated as blocked"

echo "PASS: orchestrate-select"
