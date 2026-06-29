#!/bin/bash
# Tests for scripts/orchestrate-select.sh — the critical-path-first ready-unit
# selector behind /orchestrate (selection: Task 13, REQ-F1.2, D-7, D-8;
# live-truth rewire: orchestration-concurrency Task 5, D-3, REQ-B1.2).
#
# Selection contract:
#   - completed / in-progress state is read from the LIVE DERIVATION
#     (scripts/orchestrate-state.sh), NOT from tasks.md section placement — so a
#     task that is in-flight or already completed (by git/marker evidence the
#     committed snapshot has not yet caught up to) is never re-dispatched
#     (Task 5, D-3, REQ-B1.2);
#   - a ready task is one in ## Forward plan that the derivation reports neither
#     completed nor in-progress, and whose every dependency the derivation
#     reports completed (the dependency GRAPH is still parsed from tasks.md, so
#     the prose-deps parser added in PR #78 is preserved);
#   - among ready tasks, the head of the effort-weighted longest dependent chain
#     wins (critical-path-first); FIFO (file order) breaks ties;
#   - no ready task → exit 1 (nothing to dispatch this step);
#   - a missing / taskless tasks.md, or a derivation that fails closed → exit 2.
#
# Because selection now reads live truth, the select-mode fixtures are real git
# repos with crafted evidence: a task is COMPLETED via a reachable
# `Planwright-Task: <spec>/<id>` trailer (the durable completion anchor, D-2),
# IN-PROGRESS via a fresh runtime dispatch marker (D-3) or an in-flight branch.
# Section placement in the fixture tasks.md is deliberately the un-reconciled
# snapshot (everything sits under ## Forward plan); the selector must ignore it
# and derive from evidence. The additive --critical-path mode stays structural
# (full DAG, completion-independent, git-free), so its tests are unchanged.
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

# git with a deterministic, signing-free identity (mirrors the engine's test:
# the framework never signs CI fixtures, and a stray global commit.gpgsign would
# otherwise break fixture commits).
gitc() {
  repo="$1"
  shift
  git -C "$repo" -c user.name=test -c user.email=test@example.invalid \
    -c commit.gpgsign=false -c init.defaultBranch=main "$@"
}

# new_spec <repo> <spec-id> — init a git repo with specs/<spec-id>/ and echo the
# spec dir. The bundle's tasks.md is then written by the caller and committed
# with seal_base. The spec id is the bundle dir basename and must satisfy the
# anchored identifier grammar the engine validates (lowercase, dashes), so all
# fixture spec ids below are well-formed.
new_spec() {
  nr_repo="$1"
  nr_spec="$2"
  mkdir -p "$nr_repo/specs/$nr_spec"
  git -C "$nr_repo" -c init.defaultBranch=main init -q
  printf '%s/specs/%s' "$nr_repo" "$nr_spec"
}

# seal_base <repo> — commit whatever is staged-or-not as the base commit on main.
seal_base() {
  gitc "$1" add -A
  gitc "$1" commit -q -m "base: spec bundle"
}

# done_trailer <repo> <spec-id> <id> — mark task <id> COMPLETED by adding a
# reachable completion trailer on main (no branch needed; the trailer is the
# durable anchor, D-2 / REQ-C1.4).
done_trailer() {
  gitc "$1" commit -q --allow-empty -m "task $3 done" -m "Planwright-Task: $2/$3"
}

# inflight_marker <spec-dir> <id> — mark task <id> IN-PROGRESS via a fresh
# runtime dispatch marker (D-3), the branch-create → first-commit window.
inflight_marker() {
  im_dir="$1/.orchestrate/markers"
  mkdir -p "$im_dir"
  date +%s >"$im_dir/$2"
}

# inflight_branch <repo> <spec-id> <id> — mark task <id> IN-PROGRESS via an
# in-flight task branch carrying a commit beyond base (not merged).
inflight_branch() {
  gitc "$1" branch "planwright/$2/task-$3" main
  gitc "$1" checkout -q "planwright/$2/task-$3"
  gitc "$1" commit -q --allow-empty -m "task $3 wip"
  gitc "$1" checkout -q main
}

# ---------------------------------------------------------------------------
# 1. Critical-path-first: a ready task heading a long dependent chain beats a
#    ready leaf. Task 1 is COMPLETED (trailer); 2 (deps 1, heads 2->3->4) and 5
#    (deps 1, leaf) are ready; 3 (deps 2) and 4 (deps 3) are not yet ready.
d1="$tmp/r1"
d1spec=$(new_spec "$d1" chain)
cat >"$d1spec/tasks.md" <<'EOF'
# tasks

## Forward plan

### Task 1 — root

- **Dependencies:** none
- **Estimated effort:** half day

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
EOF
seal_base "$d1"
done_trailer "$d1" chain 1
got=$(/bin/bash "$SEL" "$d1spec") || fail "chain fixture: non-zero exit ($?)"
[ "$got" = 2 ] || fail "chain fixture: selected '$got', expected 2 (longest chain)"
echo "ok: critical-path-first selects the chain head over a leaf"

# 2. FIFO on ties: two ready leaves of equal weight → the earlier-in-file one.
d2="$tmp/r2"
d2spec=$(new_spec "$d2" tie)
cat >"$d2spec/tasks.md" <<'EOF'
# tasks

## Forward plan

### Task 1 — root

- **Dependencies:** none
- **Estimated effort:** half day

### Task 7 — earlier-in-file leaf

- **Dependencies:** 1
- **Estimated effort:** 1 day

### Task 6 — later-in-file leaf

- **Dependencies:** 1
- **Estimated effort:** 1 day
EOF
seal_base "$d2"
done_trailer "$d2" tie 1
got=$(/bin/bash "$SEL" "$d2spec") || fail "tie fixture: non-zero exit"
[ "$got" = 7 ] || fail "tie fixture: selected '$got', expected 7 (FIFO/file order)"
echo "ok: FIFO (file order) breaks weight ties"

# ---------------------------------------------------------------------------
# 3. LIVE TRUTH — an in-flight task (fresh marker, snapshot not yet refreshed so
#    it still sits in Forward plan) is NOT re-dispatched; a genuinely-ready
#    sibling is picked instead. This is the core Task 5 case (D-3, REQ-B1.2):
#    the OLD section-based selector, seeing task 5 in Forward plan with its dep
#    completed, could re-dispatch it.
d3="$tmp/r3"
d3spec=$(new_spec "$d3" notready)
cat >"$d3spec/tasks.md" <<'EOF'
# tasks

## Forward plan

### Task 1 — root

- **Dependencies:** none
- **Estimated effort:** half day

### Task 8 — blocked on the in-flight task

- **Dependencies:** 5
- **Estimated effort:** 1 day

### Task 9 — ready

- **Dependencies:** 1
- **Estimated effort:** half day

### Task 5 — in flight (marker present, not yet reconciled)

- **Dependencies:** 1
- **Estimated effort:** 1 day
EOF
seal_base "$d3"
done_trailer "$d3" notready 1
inflight_marker "$d3spec" 5
got=$(/bin/bash "$SEL" "$d3spec") || fail "in-flight fixture: non-zero exit"
[ "$got" = 9 ] || fail "in-flight fixture: selected '$got', expected 9 (task 5 in flight, 8 blocked on it)"
echo "ok: an in-flight task (live truth) is not re-dispatched; its dependent stays blocked"

# 4. No ready task → exit 1. The only Forward task (3) depends on an in-flight
#    task (2, branch with commits); nothing is dispatchable this step.
d4="$tmp/r4"
d4spec=$(new_spec "$d4" none)
cat >"$d4spec/tasks.md" <<'EOF'
# tasks

## Forward plan

### Task 2 — in flight

- **Dependencies:** none
- **Estimated effort:** 1 day

### Task 3 — blocked on the in-flight task

- **Dependencies:** 2
- **Estimated effort:** 1 day
EOF
seal_base "$d4"
inflight_branch "$d4" none 2
rc=0
/bin/bash "$SEL" "$d4spec" >/dev/null 2>&1 || rc=$?
[ "$rc" = 1 ] || fail "no-ready fixture: exit $rc, expected 1"
echo "ok: no ready task exits 1 (dep is in-flight by branch evidence)"

# 5. Missing / taskless / non-git bundle fails closed (exit 2). A missing dir and
#    a taskless tasks.md both make the derivation fail closed; a tasks.md outside
#    any git work tree also fails closed (live truth needs git).
rc=0
/bin/bash "$SEL" "$tmp/does-not-exist" >/dev/null 2>&1 || rc=$?
[ "$rc" = 2 ] || fail "missing tasks.md: exit $rc, expected 2"
d6="$tmp/r6"
d6spec=$(new_spec "$d6" empty)
printf '# tasks\n\n## Forward plan\n\n(none)\n' >"$d6spec/tasks.md"
seal_base "$d6"
rc=0
/bin/bash "$SEL" "$d6spec" >/dev/null 2>&1 || rc=$?
[ "$rc" = 2 ] || fail "taskless tasks.md: exit $rc, expected 2"
# A tasks.md present but outside any git repo: the derivation cannot run → exit 2.
d6n="$tmp/nongit"
mkdir -p "$d6n"
printf '# tasks\n\n## Forward plan\n\n### Task 1 — x\n\n- **Dependencies:** none\n' >"$d6n/tasks.md"
rc=0
/bin/bash "$SEL" "$d6n" >/dev/null 2>&1 || rc=$?
[ "$rc" = 2 ] || fail "non-git tasks.md: exit $rc, expected 2 (live truth needs git)"
echo "ok: missing / taskless / non-git tasks.md fails closed with exit 2"

# 6. A dotted task id (3.5) is a valid candidate and selectable.
d7="$tmp/r7"
d7spec=$(new_spec "$d7" dotted)
cat >"$d7spec/tasks.md" <<'EOF'
# tasks

## Forward plan

### Task 1 — root

- **Dependencies:** none
- **Estimated effort:** half day

### Task 3.5 — fractional, ready

- **Dependencies:** 1
- **Estimated effort:** 2 days
EOF
seal_base "$d7"
done_trailer "$d7" dotted 1
got=$(/bin/bash "$SEL" "$d7spec") || fail "dotted fixture: non-zero exit"
[ "$got" = 3.5 ] || fail "dotted fixture: selected '$got', expected 3.5"
echo "ok: dotted task ids parse and select"

# 7. A Forward-plan task with no effective dependencies ("Dependencies: none")
#    and no evidence is ready and selectable.
d8="$tmp/r8"
d8spec=$(new_spec "$d8" nodeps)
cat >"$d8spec/tasks.md" <<'EOF'
# tasks

## Forward plan

### Task 1 — depless root

- **Dependencies:** none
- **Estimated effort:** 1 day
EOF
seal_base "$d8"
got=$(/bin/bash "$SEL" "$d8spec") || fail "depless fixture: non-zero exit"
[ "$got" = 1 ] || fail "depless fixture: selected '$got', expected 1"
echo "ok: a task with 'Dependencies: none' is ready"

# 8. A task whose dependency does not exist as a task record is NOT ready (a
#    dangling id is never derived completed, so it fails closed to blocked) —
#    selection skips it and picks the genuinely-ready task instead.
d9="$tmp/r9"
d9spec=$(new_spec "$d9" dangling)
cat >"$d9spec/tasks.md" <<'EOF'
# tasks

## Forward plan

### Task 3 — depends on a non-existent task

- **Dependencies:** 99
- **Estimated effort:** 3 days

### Task 2 — genuinely ready

- **Dependencies:** none
- **Estimated effort:** half day
EOF
seal_base "$d9"
got=$(/bin/bash "$SEL" "$d9spec") || fail "dangling-dep fixture: non-zero exit"
[ "$got" = 2 ] || fail "dangling-dep fixture: selected '$got', expected 2 (task 3 is blocked)"
d9b="$tmp/r9b"
d9bspec=$(new_spec "$d9b" dangonly)
cat >"$d9bspec/tasks.md" <<'EOF'
# tasks

## Forward plan

### Task 3 — depends on a non-existent task

- **Dependencies:** 99
- **Estimated effort:** 3 days
EOF
seal_base "$d9b"
rc=0
/bin/bash "$SEL" "$d9bspec" >/dev/null 2>&1 || rc=$?
[ "$rc" = 1 ] || fail "dangling-only fixture: exit $rc, expected 1 (no ready task)"
echo "ok: a task with a non-existent dependency is treated as blocked"

# ---------------------------------------------------------------------------
# Live-truth-specific cases (Task 5, D-3, REQ-B1.2).
# ---------------------------------------------------------------------------

# L1. A dependency COMPLETED by reachable-but-snapshot-stale evidence (its block
#     still sits in Forward plan, never reconciled to ## Completed) is treated as
#     done: its dependent becomes ready, and the completed task itself is not
#     re-selected. The OLD section-based selector would have seen the dep still
#     in Forward plan (not ## Completed) and left the dependent blocked.
dl1="$tmp/l1"
dl1spec=$(new_spec "$dl1" stalecomplete)
cat >"$dl1spec/tasks.md" <<'EOF'
# tasks

## Forward plan

### Task 1 — done in git, snapshot not refreshed

- **Dependencies:** none
- **Estimated effort:** 1 day

### Task 2 — unblocked once task 1 is seen as done

- **Dependencies:** 1
- **Estimated effort:** 1 day
EOF
seal_base "$dl1"
done_trailer "$dl1" stalecomplete 1
got=$(/bin/bash "$SEL" "$dl1spec") || fail "stale-complete fixture: non-zero exit"
[ "$got" = 2 ] || fail "stale-complete: selected '$got', expected 2 (task 1 derived completed, not re-selected; 2 unblocked)"
echo "ok: a stale-completed dependency (live truth) unblocks its dependent and is not re-selected"

# L2. In-flight by BRANCH evidence (commits beyond base) is excluded too, even
#     when the snapshot still shows the task in Forward plan.
dl2="$tmp/l2"
dl2spec=$(new_spec "$dl2" inflightbranch)
cat >"$dl2spec/tasks.md" <<'EOF'
# tasks

## Forward plan

### Task 1 — root

- **Dependencies:** none
- **Estimated effort:** half day

### Task 2 — in flight by branch commits

- **Dependencies:** 1
- **Estimated effort:** 2 days

### Task 3 — genuinely ready

- **Dependencies:** 1
- **Estimated effort:** half day
EOF
seal_base "$dl2"
done_trailer "$dl2" inflightbranch 1
inflight_branch "$dl2" inflightbranch 2
got=$(/bin/bash "$SEL" "$dl2spec") || fail "in-flight-branch fixture: non-zero exit"
[ "$got" = 3 ] || fail "in-flight-branch: selected '$got', expected 3 (task 2 in flight by branch, despite higher weight)"
echo "ok: an in-flight task by branch evidence is excluded even at higher critical-path weight"

# L3. Clean steady state — when the snapshot and live truth agree (completed work
#     carries evidence), selection output is exactly what the structural
#     critical-path computation yields. Here 1 completed; 2 heads 2->3, 4 is a
#     leaf; the head of the longest chain (2) is selected.
dl3="$tmp/l3"
dl3spec=$(new_spec "$dl3" clean)
cat >"$dl3spec/tasks.md" <<'EOF'
# tasks

## Forward plan

### Task 1 — root

- **Dependencies:** none
- **Estimated effort:** 1 day

### Task 2 — chain head

- **Dependencies:** 1
- **Estimated effort:** 1 day

### Task 4 — leaf

- **Dependencies:** 1
- **Estimated effort:** 1 day

### Task 3 — chain tail

- **Dependencies:** 2
- **Estimated effort:** 1 day
EOF
seal_base "$dl3"
done_trailer "$dl3" clean 1
got=$(/bin/bash "$SEL" "$dl3spec") || fail "clean-steady fixture: non-zero exit"
[ "$got" = 2 ] || fail "clean-steady: selected '$got', expected 2 (longest chain head)"
echo "ok: clean steady state — selection matches the structural critical-path head"

# ---------------------------------------------------------------------------
# --critical-path mode (Task 7 of specs/spec-comprehension, D-6, REQ-C1.3):
# an additive, STRUCTURAL mode — the effort-weighted longest-dependent chain over
# the FULL task DAG, completion-independent and git-free (it does NOT consult the
# live derivation). The dependency-graph view highlights exactly this output.
# ---------------------------------------------------------------------------

# 9. --critical-path emits the full-graph longest effort-weighted chain. On the
#    chain fixture (d1) the longest chain is 1 -> 2 -> 3 -> 4 (1 + 0.5 + 1 + 1);
#    task 5 is a short leaf off 1, so it is not on the path. The path spans the
#    full DAG regardless of task 1 being completed.
cp_out=$(/bin/bash "$SEL" --critical-path "$d1spec") || fail "--critical-path d1: non-zero exit"
cp_expected=$(printf '1\n2\n3\n4')
[ "$cp_out" = "$cp_expected" ] \
  || fail "--critical-path d1: got [$cp_out], expected [1 2 3 4]"
echo "ok: --critical-path emits the full-graph effort-weighted longest chain"

# 10. The mode is additive: default selection on d1 is unchanged (still task 2).
got=$(/bin/bash "$SEL" "$d1spec") || fail "default mode regressed under --critical-path addition"
[ "$got" = 2 ] || fail "default selection changed: got '$got', expected 2"
echo "ok: --critical-path is additive — default selection is unchanged"

# 11. Over the real spec-comprehension bundle the emitted path matches the
#     documented structural critical path (1 -> 2 -> 3 -> 5 -> 6 -> 7 -> 11). The
#     path is section-independent (full DAG, git-free), so it is stable.
real="$here/../specs/spec-comprehension"
if [ -d "$real" ]; then
  cp_real=$(/bin/bash "$SEL" --critical-path "$real") \
    || fail "--critical-path real bundle: non-zero exit"
  cp_real_expected=$(printf '1\n2\n3\n5\n6\n7\n11')
  [ "$cp_real" = "$cp_real_expected" ] \
    || fail "--critical-path real bundle: got [$cp_real], expected [1 2 3 5 6 7 11]"
  echo "ok: --critical-path matches the documented critical path on the real bundle"
fi

# 12. --critical-path fails closed on a missing / taskless tasks.md (exit 2). It
#     is git-free, so a taskless bundle need not be a git repo.
rc=0
/bin/bash "$SEL" --critical-path "$tmp/does-not-exist" >/dev/null 2>&1 || rc=$?
[ "$rc" = 2 ] || fail "--critical-path missing tasks.md: exit $rc, expected 2"
dcp="$tmp/cpempty"
mkdir -p "$dcp"
printf '# tasks\n\n## Forward plan\n\n(none)\n' >"$dcp/tasks.md"
rc=0
/bin/bash "$SEL" --critical-path "$dcp" >/dev/null 2>&1 || rc=$?
[ "$rc" = 2 ] || fail "--critical-path taskless tasks.md: exit $rc, expected 2"
echo "ok: --critical-path fails closed on a missing/taskless bundle"

# 13. A single depless task is its own critical path.
cp_solo=$(/bin/bash "$SEL" --critical-path "$d8spec") || fail "--critical-path solo: non-zero exit"
[ "$cp_solo" = 1 ] || fail "--critical-path solo: got [$cp_solo], expected [1]"
echo "ok: --critical-path of a single depless task is that task"

# ---------------------------------------------------------------------------
# Prose-style dependency lines (specs/kickoff-lifecycle uses these). The
# dependency GRAPH is still parsed from tasks.md by the selector (NOT delegated
# to the derivation engine, whose parser is stricter), so PR #78's prose-deps
# handling is preserved: a trailing period ("Task 1." is dep 1), a parenthetical
# qualifier whose own text holds id-shaped tokens, and a trailing cross-spec
# clause naming another bundle's tasks must all parse to only the LOCAL deps.
# Completion is now LIVE TRUTH: a helper task is COMPLETED via a reachable
# trailer; an id passed as in-progress gets a fresh marker (and no trailer)
# instead, so a dep on it blocks the candidate.
# ---------------------------------------------------------------------------

pd_n=0
# parse_deps_assert <label> <deps-line> <ready|blocked> [in_progress_ids...]
# Builds a git fixture with a single Forward-plan candidate task 50 whose
# Dependencies bullet is exactly <deps-line>. Helper tasks 1..9 are COMPLETED
# (trailer) by default; any id passed after the expected outcome is IN-PROGRESS
# (marker, no trailer) instead, so a dep on it (if parsed) would block task 50.
parse_deps_assert() {
  pd_label=$1
  pd_line=$2
  pd_expect=$3
  shift 3
  pd_inprog=" $* "
  pd_n=$((pd_n + 1))
  pd_repo="$tmp/pd$pd_n"
  pd_spec="pd$pd_n"
  pd_dir=$(new_spec "$pd_repo" "$pd_spec")
  {
    printf '# tasks\n\n## Forward plan\n\n'
    printf '### Task 50 — candidate under test\n\n'
    printf -- '- **Dependencies:** %s\n' "$pd_line"
    printf -- '- **Estimated effort:** 1 day\n\n'
    for pd_i in 1 2 3 4 5 6 7 8 9; do
      printf '### Task %s — helper\n\n' "$pd_i"
      printf -- '- **Dependencies:** none\n'
      printf -- '- **Estimated effort:** 1 day\n\n'
    done
  } >"$pd_dir/tasks.md"
  seal_base "$pd_repo"
  # Completed helpers get a trailer; in-progress helpers get a marker instead.
  for pd_i in 1 2 3 4 5 6 7 8 9; do
    case "$pd_inprog" in
      *" $pd_i "*) inflight_marker "$pd_dir" "$pd_i" ;;
      *) done_trailer "$pd_repo" "$pd_spec" "$pd_i" ;;
    esac
  done

  pd_rc=0
  pd_got=$(/bin/bash "$SEL" "$pd_dir" 2>/dev/null) || pd_rc=$?
  if [ "$pd_expect" = ready ]; then
    [ "$pd_rc" = 0 ] && [ "$pd_got" = 50 ] \
      || fail "deps-parse [$pd_label]: line '$pd_line' should leave task 50 READY (got '$pd_got', rc $pd_rc)"
  else
    # blocked: task 50 must NOT be selected. Assert BOTH (AND, not OR): rc must
    # be 1 AND 50 must not be emitted — an OR would mask a regression (exiting 0
    # while printing nothing, or selecting some other id).
    { [ "$pd_rc" = 1 ] && [ "$pd_got" != 50 ]; } \
      || fail "deps-parse [$pd_label]: line '$pd_line' should leave task 50 BLOCKED (got '$pd_got', rc $pd_rc)"
  fi
  echo "ok: deps-parse [$pd_label] -> $pd_expect"
}

# Baseline bare-number deps.
parse_deps_assert "none" "none" ready
parse_deps_assert "none-dot" "none." ready
parse_deps_assert "bare-1-6" "1, 6" ready         # both completed -> ready
parse_deps_assert "bare-1-6-blk" "1, 6" blocked 6 # dep 6 in-progress -> blocked
parse_deps_assert "bare-1-3-4" "1, 3, 4" ready
parse_deps_assert "bare-1-3-4-blk" "1, 3, 4" blocked 3 # dep 3 in-progress -> blocked

# Trailing period must not erase the dependency: "Task 1." is a real dep 1.
parse_deps_assert "task-1-dot" "Task 1." blocked 1   # dep 1 in-progress -> blocked
parse_deps_assert "task-1-dot-ready" "Task 1." ready # dep 1 completed -> ready
parse_deps_assert "task-3-dot" "Task 3." blocked 3
parse_deps_assert "task-3-dot-ready" "Task 3." ready

# Parenthetical qualifier: deps are "Task 1" and "Task 6"; the ids INSIDE the
# paren (REQ-A1.8 -> 1.8, D-9 -> 9) must NOT become phantom deps. Put 9 (the
# phantom) in-progress: a correct parse ignores it, so 50 stays ready (deps 1,6
# completed). A buggy parse would read phantom 9 and block.
parse_deps_assert "paren-phantom-ignored" \
  "Task 1; Task 6 (REQ-A1.8 / D-9 — the Draft→Ready producer is" ready 9
parse_deps_assert "paren-real-dep-6" \
  "Task 1; Task 6 (REQ-A1.8 / D-9 — the Draft→Ready producer is" blocked 6
parse_deps_assert "paren-real-dep-1" \
  "Task 1; Task 6 (REQ-A1.8 / D-9 — the Draft→Ready producer is" blocked 1

# DOCUMENTED LIMITATION — a local dep written AFTER a mid-line parenthetical is
# dropped (the greedy paren-strip removes the parenthetical and everything after
# it). Here dep "Task 2" trails the paren: with Task 2 in-progress a correct
# (greedy) parse drops it, so task 50 sees only dep 1 (completed) and stays READY.
parse_deps_assert "paren-trailing-dep-dropped" \
  "Task 1 (the foundational one), Task 2" ready 2

# Cross-spec clause: the only LOCAL dep is Task 5; the cross-spec mention names
# ANOTHER bundle's tasks and must NOT be parsed local. Put local-ids 1 and 4
# in-progress: a correct parse ignores the cross-spec mention, so with dep 5
# completed task 50 stays ready.
parse_deps_assert "cross-spec-ignored" \
  "Task 5; plus cross-spec (hard): \`orchestration-concurrency\`" ready 1 4
parse_deps_assert "cross-spec-real-dep-5" \
  "Task 5; plus cross-spec (hard): \`orchestration-concurrency\`" blocked 5

# Multiple comma-joined "Task N" deps with a trailing period on the last id.
parse_deps_assert "multi-task-trailing" "Task 2, Task 4, Task 6." ready
parse_deps_assert "multi-task-trailing-blk2" "Task 2, Task 4, Task 6." blocked 2
parse_deps_assert "multi-task-trailing-blk4" "Task 2, Task 4, Task 6." blocked 4
parse_deps_assert "multi-task-trailing-blk6" "Task 2, Task 4, Task 6." blocked 6

# Empty / whitespace-only Dependencies value: no ids parse, so task 50 is depless
# and ready.
parse_deps_assert "empty" "" ready
parse_deps_assert "whitespace-only" "   " ready

# Malformed value with no id-shaped tokens -> treated as depless -> ready
# (DOCUMENTED LIMITATION: the selector understands only numeric ids).
parse_deps_assert "no-ids-prose" "see the design doc; to be determined" ready

# Trailing-semicolon variant ("Task 1;"): the ";" is a separator, so dep 1 is
# honored.
parse_deps_assert "task-1-semicolon" "Task 1;" blocked 1
parse_deps_assert "task-1-semicolon-ready" "Task 1;" ready
parse_deps_assert "task-2-dot" "Task 2." blocked 2
parse_deps_assert "task-2-dot-ready" "Task 2." ready

# Mixed ";" and "," separators in a single line, the last id carrying a trailing
# period. All three ids must parse.
parse_deps_assert "mixed-sep" "Task 1; Task 2, Task 3." ready
parse_deps_assert "mixed-sep-blk1" "Task 1; Task 2, Task 3." blocked 1
parse_deps_assert "mixed-sep-blk2" "Task 1; Task 2, Task 3." blocked 2
parse_deps_assert "mixed-sep-blk3" "Task 1; Task 2, Task 3." blocked 3

# ---------------------------------------------------------------------------
# 14. End-to-end prose-deps fixture mirroring specs/kickoff-lifecycle's shape:
# Task 1 completed (trailer); Tasks 2/5/7 depend on "Task 1."; Task 3 on
# "Task 1; Task 6 (...)"; Task 6 on "Task 5; plus cross-spec ..."; Task 4 on
# Task 3; Task 8 on "Task 2, Task 4, Task 6.". Genuinely ready = {2,5,7} (their
# only dep, Task 1, is completed). 3/4/6/8 are blocked on a not-yet-completed dep.
# ---------------------------------------------------------------------------
dkl="$tmp/kl"
dklspec=$(new_spec "$dkl" kickoffprose)
cat >"$dklspec/tasks.md" <<'EOF'
# tasks

## Forward plan

### Task 1 — meta-spec root

- **Dependencies:** none.
- **Estimated effort:** half day

### Task 2 — validator

- **Dependencies:** Task 1.
- **Estimated effort:** half day

### Task 3 — kickoff flip

- **Dependencies:** Task 1; Task 6 (REQ-A1.8 / D-9 — the Draft→Ready producer is
  gated behind the derived reconcile so the lifecycle is never half-wired).
- **Estimated effort:** half day

### Task 4 — kickoff readies PR

- **Dependencies:** Task 3.
- **Estimated effort:** 1 day

### Task 5 — orchestrate gate

- **Dependencies:** Task 1.
- **Estimated effort:** half day

### Task 6 — derived reconcile

- **Dependencies:** Task 5; plus cross-spec (hard): `orchestration-concurrency`
  Task 1 (derivation engine) and Task 4 (single reconcile writer).
- **Estimated effort:** 1 day

### Task 7 — downstream surfaces

- **Dependencies:** Task 1.
- **Estimated effort:** half day

### Task 8 — migration sweep

- **Dependencies:** Task 2, Task 4, Task 6.
- **Estimated effort:** half day
EOF
seal_base "$dkl"
done_trailer "$dkl" kickoffprose 1
got=$(/bin/bash "$SEL" "$dklspec") || fail "kickoff-prose fixture: non-zero exit ($?)"
case "$got" in
  2 | 5 | 7) : ;;
  *) fail "kickoff-prose fixture: selected '$got', expected one of {2,5,7}" ;;
esac
echo "ok: prose-deps end-to-end selects a genuinely-ready task ($got in {2,5,7})"

# With 2,5,7 moved in-flight (markers), only 3/4/6/8 remain as Forward candidates;
# each depends on a non-completed task → nothing ready.
inflight_marker "$dklspec" 2
inflight_marker "$dklspec" 5
inflight_marker "$dklspec" 7
rc=0
/bin/bash "$SEL" "$dklspec" >/dev/null 2>&1 || rc=$?
[ "$rc" = 1 ] || fail "kickoff-prose-blocked: tasks 3/4/6/8 must all be blocked (exit $rc, expected 1)"
echo "ok: prose-deps end-to-end leaves 3/4/6/8 blocked (each on a non-completed dep)"

# ---------------------------------------------------------------------------
# 15. Genuine dotted task ids (1.2, 3.5) are preserved verbatim: the trailing-
# period strip removes ONLY a trailing dot, never the internal dot of a
# fractional id.
# ---------------------------------------------------------------------------
ddot="$tmp/dot"
ddotspec=$(new_spec "$ddot" dottedprose)
cat >"$ddotspec/tasks.md" <<'EOF'
# tasks

## Forward plan

### Task 1.2 — fractional root a

- **Dependencies:** none
- **Estimated effort:** 1 day

### Task 3.5 — fractional root b

- **Dependencies:** none
- **Estimated effort:** 1 day

### Task 60 — depends on two fractional ids, last with a trailing period

- **Dependencies:** Task 1.2, Task 3.5.
- **Estimated effort:** 1 day
EOF
seal_base "$ddot"
done_trailer "$ddot" dottedprose 1.2
done_trailer "$ddot" dottedprose 3.5
got=$(/bin/bash "$SEL" "$ddotspec") || fail "dotted-prose: non-zero exit ($?)"
[ "$got" = 60 ] || fail "dotted-prose: selected '$got', expected 60 (both fractional deps completed)"
echo "ok: fractional deps 'Task 1.2, Task 3.5.' parse (internal dot kept, trailing dot stripped)"

# The trailing-period fractional dep is genuinely honored: 3.5 in-progress blocks 60.
ddotb="$tmp/dotb"
ddotbspec=$(new_spec "$ddotb" dottedblk)
cat >"$ddotbspec/tasks.md" <<'EOF'
# tasks

## Forward plan

### Task 1.2 — fractional root a

- **Dependencies:** none
- **Estimated effort:** 1 day

### Task 3.5 — fractional dep, in flight

- **Dependencies:** none
- **Estimated effort:** 1 day

### Task 60 — depends on a fractional id with a trailing period

- **Dependencies:** Task 1.2, Task 3.5.
- **Estimated effort:** 1 day
EOF
seal_base "$ddotb"
done_trailer "$ddotb" dottedblk 1.2
inflight_marker "$ddotbspec" 3.5
rc=0
/bin/bash "$SEL" "$ddotbspec" >/dev/null 2>&1 || rc=$?
[ "$rc" = 1 ] || fail "dotted-prose-blocked: 'Task 3.5.' in flight must block task 60 (exit $rc, expected 1)"
echo "ok: trailing-period fractional dep '3.5.' is honored (blocks when not completed)"

# Internal dot must NOT be stripped: a dep on completed Task 3.5 leaves 60 ready.
ddotc="$tmp/dotc"
ddotcspec=$(new_spec "$ddotc" dottedint)
cat >"$ddotcspec/tasks.md" <<'EOF'
# tasks

## Forward plan

### Task 3.5 — fractional root

- **Dependencies:** none
- **Estimated effort:** 1 day

### Task 60 — depends on fractional 3.5

- **Dependencies:** Task 3.5
- **Estimated effort:** 1 day
EOF
seal_base "$ddotc"
done_trailer "$ddotc" dottedint 3.5
got=$(/bin/bash "$SEL" "$ddotcspec") || fail "dotted-internal: non-zero exit ($?)"
[ "$got" = 60 ] || fail "dotted-internal: selected '$got', expected 60 (3.5 must resolve to completed 3.5, not dangling 35)"
echo "ok: internal dot preserved — dep 'Task 3.5' resolves to completed 3.5 (not 35)"

# ---------------------------------------------------------------------------
# 16. KNOWN LIMITATION — first-line-only dependency parsing. The parser reads ids
# ONLY from the line carrying the `**Dependencies:**` marker; a dep id that WRAPS
# onto a continuation line is not seen. Fixture: deps "Task 1, Task 2," with
# "Task 3." on the continuation line. Tasks 1,2 completed; Task 3 in-progress.
# The second line is not parsed, so task 70 sees only {1,2} and is READY.
# ---------------------------------------------------------------------------
dwrap="$tmp/wrap"
dwrapspec=$(new_spec "$dwrap" wrapsecond)
cat >"$dwrapspec/tasks.md" <<'EOF'
# tasks

## Forward plan

### Task 1 — first-line dep a

- **Dependencies:** none
- **Estimated effort:** 1 day

### Task 2 — first-line dep b

- **Dependencies:** none
- **Estimated effort:** 1 day

### Task 3 — second-line dep, in flight (NOT seen by the parser)

- **Dependencies:** none
- **Estimated effort:** 1 day

### Task 70 — deps wrap onto a second line

- **Dependencies:** Task 1, Task 2,
  Task 3.
- **Estimated effort:** 1 day
EOF
seal_base "$dwrap"
done_trailer "$dwrap" wrapsecond 1
done_trailer "$dwrap" wrapsecond 2
inflight_marker "$dwrapspec" 3
got=$(/bin/bash "$SEL" "$dwrapspec") || fail "wrap-secondline: non-zero exit ($?)"
[ "$got" = 70 ] \
  || fail "wrap-secondline: selected '$got', expected 70 (second-line dep 3 is NOT parsed — first-line-only limitation)"
echo "ok: first-line-only limitation pinned — a wrapped second-line dep is not parsed"

# Conversely, the FIRST-line deps on that same wrapped bullet ARE honored: Task 2
# in-progress must block task 70.
dwrapb="$tmp/wrapb"
dwrapbspec=$(new_spec "$dwrapb" wrapfirst)
cat >"$dwrapbspec/tasks.md" <<'EOF'
# tasks

## Forward plan

### Task 1 — first-line dep a

- **Dependencies:** none
- **Estimated effort:** 1 day

### Task 2 — first-line dep, in flight

- **Dependencies:** none
- **Estimated effort:** 1 day

### Task 70 — deps wrap onto a second line

- **Dependencies:** Task 1, Task 2,
  Task 3.
- **Estimated effort:** 1 day
EOF
seal_base "$dwrapb"
done_trailer "$dwrapb" wrapfirst 1
inflight_marker "$dwrapbspec" 2
rc=0
/bin/bash "$SEL" "$dwrapbspec" >/dev/null 2>&1 || rc=$?
[ "$rc" = 1 ] || fail "wrap-firstline: first-line dep Task 2 in flight must block task 70 (exit $rc, expected 1)"
echo "ok: first-line deps on a wrapped bullet are honored (Task 2 blocks)"

echo "PASS: orchestrate-select"
