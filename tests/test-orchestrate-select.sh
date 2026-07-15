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
# anchored identifier grammar the engine validates (lowercase letters, digits,
# and dashes; first character a letter or digit), so all fixture spec ids below
# are well-formed.
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

# make_failing_gh_stub <dir> — drop a `gh` on PATH that always errors (mirrors
# the engine test). With a remote configured, this drives the engine's
# configured-but-failing-gh path, which emits a `degraded` record.
make_failing_gh_stub() {
  mkdir -p "$1"
  printf '#!/bin/sh\necho "gh: simulated failure" >&2\nexit 1\n' >"$1/gh"
  chmod +x "$1/gh"
}

# ---------------------------------------------------------------------------
# 1. Critical-path-first: a ready task heading a long dependent chain beats a
#    ready leaf. Task 1 is COMPLETED (trailer); 2 (deps 1, heads 2->3->4) and 5
#    (deps 1, leaf) are ready; 3 (deps 2) and 4 (deps 3) are not yet ready.
d1="$tmp/r1"
d1spec=$(new_spec "$d1" chain)
cat >"$d1spec/tasks.md" <<'EOF'
# tasks

**Format-version:** 1

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

**Format-version:** 1

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

**Format-version:** 1

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

**Format-version:** 1

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
printf '# tasks\n\n**Format-version:** 1\n\n## Forward plan\n\n(none)\n' >"$d6spec/tasks.md"
seal_base "$d6"
rc=0
/bin/bash "$SEL" "$d6spec" >/dev/null 2>&1 || rc=$?
[ "$rc" = 2 ] || fail "taskless tasks.md: exit $rc, expected 2"
# A tasks.md present but outside any git repo: the derivation cannot run → exit 2,
# and the fail-closed message must surface the engine's specific reason (not just
# a generic line), so an operator can see why selection refused.
d6n="$tmp/nongit"
mkdir -p "$d6n"
printf '# tasks\n\n**Format-version:** 1\n\n## Forward plan\n\n### Task 1 — x\n\n- **Dependencies:** none\n' >"$d6n/tasks.md"
rc=0
errout=$(/bin/bash "$SEL" "$d6n" 2>&1 >/dev/null) || rc=$?
[ "$rc" = 2 ] || fail "non-git tasks.md: exit $rc, expected 2 (live truth needs git)"
case "$errout" in
  *"orchestrate-state"*) : ;; # the engine's own diagnostic is forwarded
  *) fail "non-git tasks.md: fail-closed message did not surface the engine reason: [$errout]" ;;
esac
echo "ok: missing / taskless / non-git tasks.md fails closed with exit 2 (engine reason surfaced)"

# 6. A dotted task id (3.5) is a valid candidate and selectable.
d7="$tmp/r7"
d7spec=$(new_spec "$d7" dotted)
cat >"$d7spec/tasks.md" <<'EOF'
# tasks

**Format-version:** 1

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

**Format-version:** 1

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

**Format-version:** 1

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

**Format-version:** 1

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

**Format-version:** 1

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

**Format-version:** 1

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

**Format-version:** 1

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
printf '# tasks\n\n**Format-version:** 1\n\n## Forward plan\n\n(none)\n' >"$dcp/tasks.md"
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
    printf '# tasks\n\n**Format-version:** 1\n\n## Forward plan\n\n'
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
  # Completed helpers share ONE commit whose trailer block carries every
  # Planwright-Task trailer (the engine reads all reachable trailers, and
  # multiple trailers in a single message's trailer block all register), so N
  # completions cost one commit instead of N — keeping a 31-case suite from
  # racking up hundreds of commits. In-progress helpers get a marker (no
  # trailer) instead, so a dep on one blocks the candidate.
  pd_done=""
  for pd_i in 1 2 3 4 5 6 7 8 9; do
    case "$pd_inprog" in
      *" $pd_i "*) inflight_marker "$pd_dir" "$pd_i" ;;
      *) pd_done="$pd_done $pd_i" ;;
    esac
  done
  if [ -n "$pd_done" ]; then
    pd_trailers=$(for pd_i in $pd_done; do
      printf 'Planwright-Task: %s/%s\n' "$pd_spec" "$pd_i"
    done)
    gitc "$pd_repo" commit -q --allow-empty \
      -m "complete helper tasks" -m "$pd_trailers"
  fi

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

**Format-version:** 1

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

**Format-version:** 1

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

**Format-version:** 1

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

**Format-version:** 1

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

**Format-version:** 1

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

**Format-version:** 1

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

# ---------------------------------------------------------------------------
# 17. Evidence-quality diagnostics surface on the success path (Task 5 review).
# The engine's `degraded` record (a configured gh query failed → selection ran
# git-only) is forwarded to STDERR so an operator sees the pick stood on
# degraded evidence, while STDOUT stays clean (just the selected id). Acting on
# the record stays the reconcile's (T4) and guards' (T7) concern; the selector
# only makes the safety-relevant subset visible (refused / malformed-deps are
# intentionally NOT forwarded, to keep the selection path quiet).
# ---------------------------------------------------------------------------
ddeg="$tmp/degraded"
ddegspec=$(new_spec "$ddeg" degradedspec)
cat >"$ddegspec/tasks.md" <<'EOF'
# tasks

**Format-version:** 1

## Forward plan

### Task 1 — root

- **Dependencies:** none
- **Estimated effort:** 1 day
EOF
seal_base "$ddeg"
# A remote + a failing gh stub on PATH makes the engine emit `degraded`.
gitc "$ddeg" remote add origin https://example.invalid/demo.git
degstub="$tmp/bindeg"
make_failing_gh_stub "$degstub"
deg_err="$tmp/degraded.err"
deg_rc=0
deg_out=$(PATH="$degstub:$PATH" /bin/bash "$SEL" "$ddegspec" 2>"$deg_err") || deg_rc=$?
[ "$deg_rc" = 0 ] \
  || fail "degraded-forward: selection must still succeed git-only (exit $deg_rc; stderr: $(cat "$deg_err"))"
[ "$deg_out" = 1 ] \
  || fail "degraded-forward: STDOUT must carry only the selected id (got '$deg_out')"
grep -Eq '^degraded[[:space:]]gh[[:space:]]' "$deg_err" \
  || fail "degraded-forward: the engine's degraded record must reach STDERR (got: $(cat "$deg_err"))"
echo "ok: degraded evidence is forwarded to stderr; stdout stays clean"

# ---------------------------------------------------------------------------
# 18. Engine success-path stderr warnings pass through (Task 5 review). The
# selector captures only the engine's STDOUT (records) and lets its STDERR flow
# through, so a warning the engine emits while still exiting 0 — here a malformed
# stale_marker_threshold that warns and falls back to the default — reaches the
# operator instead of being swallowed by the capture. stdout stays the id only.
# ---------------------------------------------------------------------------
dwarn="$tmp/warn"
dwarnspec=$(new_spec "$dwarn" warnspec)
cat >"$dwarnspec/tasks.md" <<'EOF'
# tasks

**Format-version:** 1

## Forward plan

### Task 1 — root

- **Dependencies:** none
- **Estimated effort:** 1 day
EOF
seal_base "$dwarn"
# A malformed repo-local stale_marker_threshold makes the engine warn on stderr
# while still exiting 0 (it falls back to the 15m default).
mkdir -p "$dwarn/.claude"
printf 'stale_marker_threshold: not-a-number\n' >"$dwarn/.claude/planwright.local.yml"
warn_err="$tmp/warn.err"
warn_rc=0
warn_out=$(/bin/bash "$SEL" "$dwarnspec" 2>"$warn_err") || warn_rc=$?
[ "$warn_rc" = 0 ] \
  || fail "stderr-passthrough: selection must still succeed (exit $warn_rc; stderr: $(cat "$warn_err"))"
[ "$warn_out" = 1 ] \
  || fail "stderr-passthrough: stdout must carry only the selected id (got '$warn_out')"
grep -q "ignoring malformed stale_marker_threshold" "$warn_err" \
  || fail "stderr-passthrough: the engine's success-path warning must reach stderr (got: $(cat "$warn_err"))"
echo "ok: engine success-path stderr warning passes through; stdout stays clean"

# ---------------------------------------------------------------------------
# Format-version 2 (invariant-tasks Task 5; D-8, D-3; REQ-C1.2, REQ-C1.8,
# REQ-C1.9, REQ-B1.5): v2 candidacy is computed without committed placement —
# completed / in-progress exclusion from the derivation engine, parked-ness
# from live reference bullets in the human-payload sections. v1 behavior above
# is unchanged.
# ---------------------------------------------------------------------------

# v2_tasks_md <path> — the shared v2 fixture skeleton: five tasks under a
# single ## Tasks section (no placement sections), the three human-payload
# sections empty. Task 1 is the root; 2/3/4/5 depend on it. Efforts make any
# parked-task leak visible: 2/3/4 (3 days each) outweigh 5 (half day), so if a
# bullet fails to exclude its task the selection flips away from 5.
v2_tasks_md() {
  cat >"$1" <<'EOF'
# tasks

**Format-version:** 2

## Tasks

### Task 1 — root

- **Dependencies:** none
- **Estimated effort:** 1 day

### Task 2 — parked awaiting input

- **Dependencies:** 1
- **Estimated effort:** 3 days

### Task 3 — parked deferred

- **Dependencies:** 1
- **Estimated effort:** 3 days

### Task 4 — parked out of scope

- **Dependencies:** 1
- **Estimated effort:** 3 days

### Task 5 — the only un-parked candidate

- **Dependencies:** 1
- **Estimated effort:** half day

## Awaiting input

- **Task 2** blocked on a human decision.

## Deferred

- **Task 3** deferred behind a gate.

## Out of scope

- **Task 4** excluded by decision.
EOF
}

# F1. REQ-C1.8 — a missing Format-version: line fails closed (exit 2) in both
#     modes, before any derivation runs (a plain non-git dir suffices).
dfv="$tmp/fvmissing"
mkdir -p "$dfv"
printf '# tasks\n\n## Forward plan\n\n### Task 1 — x\n\n- **Dependencies:** none\n' >"$dfv/tasks.md"
rc=0
fv_err=$(/bin/bash "$SEL" "$dfv" 2>&1 >/dev/null) || rc=$?
[ "$rc" = 2 ] || fail "fv-missing select: exit $rc, expected 2 (fail closed)"
case "$fv_err" in
  *Format-version*) : ;;
  *) fail "fv-missing select: diagnostic must name Format-version (got: $fv_err)" ;;
esac
rc=0
/bin/bash "$SEL" --critical-path "$dfv" >/dev/null 2>&1 || rc=$?
[ "$rc" = 2 ] || fail "fv-missing --critical-path: exit $rc, expected 2 (fail closed)"
echo "ok: a missing Format-version: fails closed in both modes (REQ-C1.8)"

# F2. REQ-C1.8 — an unparseable Format-version: value fails closed too; the
#     selector never falls open to either version's rules.
dfv2="$tmp/fvbogus"
mkdir -p "$dfv2"
printf '# tasks\n\n**Format-version:** 3beta\n\n## Forward plan\n\n### Task 1 — x\n\n- **Dependencies:** none\n' >"$dfv2/tasks.md"
rc=0
/bin/bash "$SEL" "$dfv2" >/dev/null 2>&1 || rc=$?
[ "$rc" = 2 ] || fail "fv-bogus select: exit $rc, expected 2 (fail closed)"
rc=0
/bin/bash "$SEL" --critical-path "$dfv2" >/dev/null 2>&1 || rc=$?
[ "$rc" = 2 ] || fail "fv-bogus --critical-path: exit $rc, expected 2 (fail closed)"
echo "ok: an unparseable Format-version: fails closed in both modes (REQ-C1.8)"

# V1. REQ-C1.2 — parked-task exclusion, all three sections: with task 1
#     completed, tasks 2/3/4 are ready by evidence but each is parked by a live
#     reference bullet; only task 5 is dispatchable, despite its lower weight.
dv1="$tmp/v2park"
dv1spec=$(new_spec "$dv1" vtwo)
v2_tasks_md "$dv1spec/tasks.md"
seal_base "$dv1"
done_trailer "$dv1" vtwo 1
got=$(/bin/bash "$SEL" "$dv1spec") || fail "v2-parked fixture: non-zero exit ($?)"
[ "$got" = 5 ] || fail "v2-parked: selected '$got', expected 5 (2/3/4 parked by bullets)"
echo "ok: v2 reference bullets park their tasks in all three sections (REQ-C1.2)"

# V2. REQ-C1.2 — equivalence with the v1 section model: the same states
#     expressed as v1 section placement (task 2 in ## Awaiting input, 3 in
#     ## Deferred, 4 in ## Out of scope) pick the same candidate.
dv2="$tmp/v1twin"
dv2spec=$(new_spec "$dv2" vonetwin)
cat >"$dv2spec/tasks.md" <<'EOF'
# tasks

**Format-version:** 1

## Forward plan

### Task 1 — root

- **Dependencies:** none
- **Estimated effort:** 1 day

### Task 5 — the only un-parked candidate

- **Dependencies:** 1
- **Estimated effort:** half day

## Awaiting input

### Task 2 — parked awaiting input

- **Dependencies:** 1
- **Estimated effort:** 3 days

## Deferred

### Task 3 — parked deferred

- **Dependencies:** 1
- **Estimated effort:** 3 days

## Out of scope

### Task 4 — parked out of scope

- **Dependencies:** 1
- **Estimated effort:** 3 days
EOF
seal_base "$dv2"
done_trailer "$dv2" vonetwin 1
got_v1=$(/bin/bash "$SEL" "$dv2spec") || fail "v1-twin fixture: non-zero exit ($?)"
[ "$got_v1" = "5" ] || fail "v1-twin: selected '$got_v1', expected 5"
[ "$got_v1" = "$got" ] || fail "v2/v1 equivalence: v2 picked '$got', v1 twin picked '$got_v1'"
echo "ok: v2 selection matches the v1 section model in equivalent states (REQ-C1.2)"

# V3. REQ-C1.2 — completed / in-progress exclusion comes from derivation
#     evidence, not sections: on a v2 bundle (everything under ## Tasks, no
#     bullets) a trailer-completed task is not re-selected and a marker-held
#     task is not double-dispatched; the remaining ready task is picked.
dv3="$tmp/v2live"
dv3spec=$(new_spec "$dv3" vtwolive)
cat >"$dv3spec/tasks.md" <<'EOF'
# tasks

**Format-version:** 2

## Tasks

### Task 1 — completed by trailer

- **Dependencies:** none
- **Estimated effort:** 1 day

### Task 2 — in flight by marker

- **Dependencies:** 1
- **Estimated effort:** 3 days

### Task 3 — genuinely ready

- **Dependencies:** 1
- **Estimated effort:** half day

## Awaiting input

(none yet)

## Deferred

(none yet)

## Out of scope

(none yet)
EOF
seal_base "$dv3"
done_trailer "$dv3" vtwolive 1
inflight_marker "$dv3spec" 2
got=$(/bin/bash "$SEL" "$dv3spec") || fail "v2-live fixture: non-zero exit ($?)"
[ "$got" = 3 ] || fail "v2-live: selected '$got', expected 3 (1 completed, 2 in flight — derivation, no sections)"
echo "ok: v2 completed/in-progress exclusion derives from evidence, not sections (REQ-C1.2)"

# V4. Chain-weight terminality on v2: an out-of-scope-parked dependent never
#     lengthens the remaining critical path (it is not future work), while a
#     deferred-parked dependent still does — mirroring the v1 section
#     semantics (only Out of scope and completed are terminal).
v4_tasks_md() {
  # $1 = file, $2 = the section parking task 3 (Deferred | Out of scope)
  cat >"$1" <<EOF
# tasks

**Format-version:** 2

## Tasks

### Task 1 — root

- **Dependencies:** none
- **Estimated effort:** 1 day

### Task 2 — chain head (its weight rides on task 3)

- **Dependencies:** 1
- **Estimated effort:** half day

### Task 3 — heavy dependent, parked

- **Dependencies:** 2
- **Estimated effort:** 3 days

### Task 4 — leaf

- **Dependencies:** 1
- **Estimated effort:** 1 day

## Awaiting input

(none yet)

## Deferred

$([ "$2" = Deferred ] && printf -- '- **Task 3** deferred behind a gate.' || printf '(none yet)')

## Out of scope

$([ "$2" = "Out of scope" ] && printf -- '- **Task 3** excluded by decision.' || printf '(none yet)')
EOF
}
dv4a="$tmp/v2oosweight"
dv4aspec=$(new_spec "$dv4a" vtwooos)
v4_tasks_md "$dv4aspec/tasks.md" "Out of scope"
seal_base "$dv4a"
done_trailer "$dv4a" vtwooos 1
got=$(/bin/bash "$SEL" "$dv4aspec") || fail "v2-oos-weight fixture: non-zero exit ($?)"
[ "$got" = 4 ] || fail "v2-oos-weight: selected '$got', expected 4 (task 3 out-of-scope-parked must not extend 2's chain)"
dv4b="$tmp/v2defweight"
dv4bspec=$(new_spec "$dv4b" vtwodef)
v4_tasks_md "$dv4bspec/tasks.md" Deferred
seal_base "$dv4b"
done_trailer "$dv4b" vtwodef 1
got=$(/bin/bash "$SEL" "$dv4bspec") || fail "v2-def-weight fixture: non-zero exit ($?)"
[ "$got" = 2 ] || fail "v2-def-weight: selected '$got', expected 2 (a deferred-parked dependent still extends the chain)"
echo "ok: v2 out-of-scope bullets are chain-terminal; deferred bullets are not (v1 parity)"

# V5. REQ-B1.5 — transient evidence failure on a v2 bundle dispatches nothing:
#     with a remote configured and gh failing, the selector exits 3 (distinct
#     from 1 no-ready-unit and 2 malformed-input) with an empty stdout. The v1
#     degraded path above (check 17) still selects git-only — v1 unchanged.
dv5="$tmp/v2degraded"
dv5spec=$(new_spec "$dv5" vtwodeg)
cat >"$dv5spec/tasks.md" <<'EOF'
# tasks

**Format-version:** 2

## Tasks

### Task 1 — root

- **Dependencies:** none
- **Estimated effort:** 1 day

## Awaiting input

(none yet)

## Deferred

(none yet)

## Out of scope

(none yet)
EOF
seal_base "$dv5"
gitc "$dv5" remote add origin https://example.invalid/demo.git
v5_err="$tmp/v2degraded.err"
rc=0
v5_out=$(PATH="$degstub:$PATH" /bin/bash "$SEL" "$dv5spec" 2>"$v5_err") || rc=$?
[ "$rc" = 3 ] || fail "v2-degraded: exit $rc, expected 3 (transient evidence failure, dispatch nothing)"
[ -z "$v5_out" ] || fail "v2-degraded: stdout must be empty (got '$v5_out')"
grep -q 'transient evidence failure' "$v5_err" \
  || fail "v2-degraded: stderr must name the transient failure (got: $(cat "$v5_err"))"
echo "ok: v2 transient evidence failure exits 3 and dispatches nothing (REQ-B1.5)"

# V6. REQ-C1.9 — a reference bullet whose task id violates the task-id grammar
#     is rejected with a sanitized stderr warning and never used; a well-formed
#     bullet naming a non-existent task matches nothing here (asserting only
#     that it causes no crash or spurious warning — the unknown-id error itself
#     is the validator's, and is unobservable at this surface); selection
#     proceeds on the valid state either way.
dv6="$tmp/v2badbullet"
dv6spec=$(new_spec "$dv6" vtwobad)
{
  printf '# tasks\n\n**Format-version:** 2\n\n## Tasks\n\n'
  printf '### Task 1 — the only task\n\n'
  printf -- '- **Dependencies:** none\n'
  printf -- '- **Estimated effort:** 1 day\n\n'
  printf '## Awaiting input\n\n'
  # A grammar-violating bullet id carrying a raw ESC byte: rejected, sanitized.
  printf -- '- **Task 9\033[31mx** hostile id, must be rejected.\n'
  # A well-formed id naming a task that does not exist: parks nothing.
  printf -- '- **Task 99** names no existing task.\n\n'
  printf '## Deferred\n\n(none yet)\n\n## Out of scope\n\n(none yet)\n'
} >"$dv6spec/tasks.md"
seal_base "$dv6"
v6_err="$tmp/v2badbullet.err"
rc=0
v6_out=$(/bin/bash "$SEL" "$dv6spec" 2>"$v6_err") || rc=$?
[ "$rc" = 0 ] || fail "v2-bad-bullet: exit $rc, expected 0 (stderr: $(cat "$v6_err"))"
[ "$v6_out" = 1 ] || fail "v2-bad-bullet: selected '$v6_out', expected 1"
grep -q 'violates the task-id grammar' "$v6_err" \
  || fail "v2-bad-bullet: rejected bullet id must be surfaced on stderr (got: $(cat "$v6_err"))"
LC_ALL=C grep '[^ -~]' "$v6_err" >/dev/null \
  && fail "v2-bad-bullet: stderr carries non-printable bytes (unsanitized bullet id)"
echo "ok: v2 grammar-violating bullet ids are rejected with a sanitized warning (REQ-C1.9)"

# V7. Fenced code blocks are illustration in the v2 parked map: a fenced
#     example bullet must not park its task, and a fenced section heading must
#     not end the real section around it (a real bullet after the fence still
#     parks). Mirrors the drain-gates parked-map fence guard.
dv7="$tmp/v2fence"
dv7spec=$(new_spec "$dv7" vtwofence)
cat >"$dv7spec/tasks.md" <<'EOF'
# tasks

**Format-version:** 2

## Tasks

### Task 1 — ready, illustrated as parked in a fence

- **Dependencies:** none
- **Estimated effort:** 1 day

### Task 2 — genuinely parked after an embedded fence (heavier, so a
suppressed park flips the pick and fails the assertion)

- **Dependencies:** none
- **Estimated effort:** 3 days

## Awaiting input

(none yet)

## Deferred

```markdown
## Deferred

- **Task 1** an illustrative parking bullet, not a real one.
```

- **Task 2** genuinely parked; the fence above must not have ended the section.

## Out of scope

(none yet)
EOF
seal_base "$dv7"
got=$(/bin/bash "$SEL" "$dv7spec") || fail "v2-fence fixture: non-zero exit ($?)"
[ "$got" = 1 ] || fail "v2-fence: selected '$got', expected 1 (fenced bullet must not park 1; real bullet after the fence must park 2)"
echo "ok: v2 parked-map parse treats fenced content as illustration"

# V8. A fenced Format-version example must not shadow the real header line: the
#     bundle below is v2 (real header) with a fenced v1 example above the real
#     line's consumers; v2 semantics (bullet parking) must apply.
dv8="$tmp/v2fvfence"
dv8spec=$(new_spec "$dv8" vtwofvfence)
cat >"$dv8spec/tasks.md" <<'EOF'
# tasks

```markdown
**Format-version:** 1
```

**Format-version:** 2

## Tasks

### Task 1 — parked by bullet

- **Dependencies:** none
- **Estimated effort:** 3 days

### Task 2 — ready

- **Dependencies:** none
- **Estimated effort:** half day

## Awaiting input

- **Task 1** parked; only v2 semantics read this bullet.

## Deferred

(none yet)

## Out of scope

(none yet)
EOF
seal_base "$dv8"
got=$(/bin/bash "$SEL" "$dv8spec") || fail "v2-fv-fence fixture: non-zero exit ($?)"
[ "$got" = 2 ] || fail "v2-fv-fence: selected '$got', expected 2 (fenced FV example must not select v1 rules; bullet must park 1)"
echo "ok: a fenced Format-version example does not shadow the real header line"

# V9. Prose-bullet tolerance (validator parity): a plain prose bullet whose
#     bold lead happens to start with "Task " plus inner whitespace ("**Task
#     force assembled.**") is a plain bullet the format allows in Deferred /
#     Out of scope — silently skipped, never warned about as a grammar
#     violation, and parking nothing.
dv9="$tmp/v2prose"
dv9spec=$(new_spec "$dv9" vtwoprose)
cat >"$dv9spec/tasks.md" <<'EOF'
# tasks

**Format-version:** 2

## Tasks

### Task 1 — ready

- **Dependencies:** none
- **Estimated effort:** 1 day

## Awaiting input

(none yet)

## Deferred

- **Task force assembled.** A plain prose bullet, not a task reference.

## Out of scope

(none yet)
EOF
seal_base "$dv9"
v9_err="$tmp/v2prose.err"
rc=0
v9_out=$(/bin/bash "$SEL" "$dv9spec" 2>"$v9_err") || rc=$?
[ "$rc" = 0 ] || fail "v2-prose: exit $rc, expected 0 (stderr: $(cat "$v9_err"))"
[ "$v9_out" = 1 ] || fail "v2-prose: selected '$v9_out', expected 1 (a prose bullet parks nothing)"
grep -q 'violates the task-id grammar' "$v9_err" \
  && fail "v2-prose: a plain prose bullet must not be warned about as a rejected reference (got: $(cat "$v9_err"))"
echo "ok: prose bullets with inner whitespace are tolerated silently (validator parity)"

# V10. No-PR-found is evidence, not failure (REQ-B1.5): a working gh that
#      returns an EMPTY PR list is a definitive negative result — the v2
#      selector must select normally (exit 0), never exit 3.
dv10="$tmp/v2emptygh"
dv10spec=$(new_spec "$dv10" vtwoemptygh)
cat >"$dv10spec/tasks.md" <<'EOF'
# tasks

**Format-version:** 2

## Tasks

### Task 1 — ready

- **Dependencies:** none
- **Estimated effort:** 1 day

## Awaiting input

(none yet)

## Deferred

(none yet)

## Out of scope

(none yet)
EOF
seal_base "$dv10"
gitc "$dv10" remote add origin https://example.invalid/demo.git
okstub="$tmp/binokgh"
mkdir -p "$okstub"
printf '#!/bin/sh\nexit 0\n' >"$okstub/gh"
chmod +x "$okstub/gh"
rc=0
v10_out=$(PATH="$okstub:$PATH" /bin/bash "$SEL" "$dv10spec" 2>/dev/null) || rc=$?
[ "$rc" = 0 ] || fail "v2-empty-gh: exit $rc, expected 0 (an empty PR list is evidence, not failure)"
[ "$v10_out" = 1 ] || fail "v2-empty-gh: selected '$v10_out', expected 1"
echo "ok: an empty gh PR list is evidence, not a transient failure (REQ-B1.5)"

# V11. Format-version trailing-trim: a CRLF header line and a Markdown
#      hard-break (trailing spaces) both parse.
dv11="$tmp/v2fvtrim"
dv11spec=$(new_spec "$dv11" vtwofvtrim)
{
  printf '# tasks\r\n\r\n'
  printf '**Format-version:** 2  \r\n\r\n'
  printf '## Tasks\r\n\r\n'
  printf '### Task 1 — ready\r\n\r\n'
  printf -- '- **Dependencies:** none\r\n'
  printf -- '- **Estimated effort:** 1 day\r\n\r\n'
  printf '## Awaiting input\r\n\r\n(none yet)\r\n\r\n'
  printf '## Deferred\r\n\r\n(none yet)\r\n\r\n'
  printf '## Out of scope\r\n\r\n(none yet)\r\n'
} >"$dv11spec/tasks.md"
seal_base "$dv11"
got=$(/bin/bash "$SEL" "$dv11spec") || fail "v2-fv-trim fixture: non-zero exit ($?)"
[ "$got" = 1 ] || fail "v2-fv-trim: selected '$got', expected 1 (CRLF/hard-break FV line must parse)"
echo "ok: Format-version trailing trim handles CRLF and hard-break lines"

# V12. REQ-C1.9 — a hostile unparseable Format-version value (raw ESC byte) is
#      refused (exit 2) with a sanitized diagnostic: no non-printable bytes on
#      stderr.
dv12="$tmp/v2fvhostile"
mkdir -p "$dv12"
printf '# tasks\n\n**Format-version:** 3\033[31mx\n\n## Tasks\n\n### Task 1 — x\n\n- **Dependencies:** none\n' >"$dv12/tasks.md"
v12_err="$tmp/v2fvhostile.err"
rc=0
/bin/bash "$SEL" "$dv12" >/dev/null 2>"$v12_err" || rc=$?
[ "$rc" = 2 ] || fail "v2-fv-hostile: exit $rc, expected 2"
grep -q 'Format-version' "$v12_err" \
  || fail "v2-fv-hostile: diagnostic must name Format-version (got: $(cat "$v12_err"))"
LC_ALL=C grep '[^ -~]' "$v12_err" >/dev/null \
  && fail "v2-fv-hostile: stderr carries non-printable bytes (unsanitized header value)"
echo "ok: a hostile Format-version value is refused with a sanitized diagnostic (REQ-C1.9)"

# V13. The rejected-bullet warning is emitted before the evidence probe, so it
#      still reaches stderr when the run then fails closed on transient
#      evidence (REQ-B1.5's locally-determinable-facts clause at this surface).
dv13="$tmp/v2rejdeg"
dv13spec=$(new_spec "$dv13" vtworejdeg)
{
  printf '# tasks\n\n**Format-version:** 2\n\n## Tasks\n\n'
  printf '### Task 1 — ready\n\n'
  printf -- '- **Dependencies:** none\n'
  printf -- '- **Estimated effort:** 1 day\n\n'
  printf '## Awaiting input\n\n'
  printf -- '- **Task 9x** grammar-violating id.\n\n'
  printf '## Deferred\n\n(none yet)\n\n## Out of scope\n\n(none yet)\n'
} >"$dv13spec/tasks.md"
seal_base "$dv13"
gitc "$dv13" remote add origin https://example.invalid/demo.git
v13_err="$tmp/v2rejdeg.err"
rc=0
v13_out=$(PATH="$degstub:$PATH" /bin/bash "$SEL" "$dv13spec" 2>"$v13_err") || rc=$?
[ "$rc" = 3 ] || fail "v2-rej-deg: exit $rc, expected 3 (transient failure)"
[ -z "$v13_out" ] || fail "v2-rej-deg: stdout must be empty (got '$v13_out')"
grep -q 'violates the task-id grammar' "$v13_err" \
  || fail "v2-rej-deg: the rejected-bullet warning must still surface during a transient failure"
echo "ok: rejected-bullet warnings survive a transient evidence failure (REQ-B1.5)"

# V14. Fenced code blocks are illustration in the selection GRAPH too: a
#      fenced example task heading is never a graph node, so it can be neither
#      selected nor part of the critical path (its example effort must not
#      outweigh real work).
dv14="$tmp/v2graphfence"
dv14spec=$(new_spec "$dv14" vtwographfence)
cat >"$dv14spec/tasks.md" <<'EOF'
# tasks

**Format-version:** 2

## Tasks

### Task 1 — the only real task

- **Dependencies:** none
- **Estimated effort:** half day

```markdown
### Task 9 — an illustration, heavier than any real work

- **Dependencies:** none
- **Estimated effort:** 5 days
```

## Awaiting input

(none yet)

## Deferred

(none yet)

## Out of scope

(none yet)
EOF
seal_base "$dv14"
got=$(/bin/bash "$SEL" "$dv14spec") || fail "v2-graph-fence fixture: non-zero exit ($?)"
[ "$got" = 1 ] || fail "v2-graph-fence: selected '$got', expected 1 (a fenced task heading is not a graph node)"
cp14=$(/bin/bash "$SEL" --critical-path "$dv14spec") || fail "v2-graph-fence --critical-path: non-zero exit ($?)"
case "$cp14" in
  *9*) fail "v2-graph-fence --critical-path: fenced task 9 appeared on the path [$cp14]" ;;
esac
echo "ok: fenced task headings are illustration in selection and --critical-path"

# V15. NUL bytes in tasks.md fail closed (mirrors drain-gates): the snapshot
#      read strips NULs, which would splice flanking bytes and could silently
#      un-park a task; corruption is refused, never reinterpreted.
dv15="$tmp/v2nul"
dv15spec=$(new_spec "$dv15" vtwonul)
{
  printf '# tasks\n\n**Format-version:** 2\n\n## Tasks\n\n'
  printf '### Task 1 — ready\n\n'
  printf -- '- **Dependencies:** none\n'
  printf -- '- **Estimated effort:** 1 day\n\n'
  printf '## Awaiting input\n\n'
  printf -- 'corrupt\000- **Task 1** parked, NUL-spliced.\n\n'
  printf '## Deferred\n\n(none yet)\n\n## Out of scope\n\n(none yet)\n'
} >"$dv15spec/tasks.md"
seal_base "$dv15"
rc=0
/bin/bash "$SEL" "$dv15spec" >/dev/null 2>&1 || rc=$?
[ "$rc" = 2 ] || fail "v2-nul: exit $rc, expected 2 (NUL-laden tasks.md fails closed)"
echo "ok: NUL bytes in tasks.md fail closed (no snapshot splice)"

# V16. A NEAR-MISS reference bullet — whitespace-trimmed lead is a valid id
#      ("Task 1 ", stray space), or the lead is only digits/dots/whitespace
#      ("Task 1 2") — is a failed park a human meant: rejected LOUDLY, never
#      silently skipped as prose (REQ-C1.9's never-silent posture). Genuine
#      prose (V9) stays silent.
dv16="$tmp/v2nearmiss"
dv16spec=$(new_spec "$dv16" vtwonearmiss)
{
  printf '# tasks\n\n**Format-version:** 2\n\n## Tasks\n\n'
  printf '### Task 1 — ready\n\n'
  printf -- '- **Dependencies:** none\n'
  printf -- '- **Estimated effort:** 1 day\n\n'
  printf '## Awaiting input\n\n'
  printf -- '- **Task 1 ** near-miss: stray space inside the bold lead.\n\n'
  printf '## Deferred\n\n(none yet)\n\n## Out of scope\n\n(none yet)\n'
} >"$dv16spec/tasks.md"
seal_base "$dv16"
v16_err="$tmp/v2nearmiss.err"
rc=0
v16_out=$(/bin/bash "$SEL" "$dv16spec" 2>"$v16_err") || rc=$?
[ "$rc" = 0 ] || fail "v2-near-miss: exit $rc, expected 0"
[ "$v16_out" = 1 ] || fail "v2-near-miss: selected '$v16_out', expected 1 (a rejected near-miss parks nothing)"
grep -q 'violates the task-id grammar' "$v16_err" \
  || fail "v2-near-miss: a stray-space reference bullet must be rejected loudly, not silently skipped as prose"
echo "ok: near-miss reference bullets warn; the failed park is never silent (REQ-C1.9)"

# V17. Echo discipline: untrusted content carrying a LITERAL backslash escape
#      (the four printable bytes \033) must not be re-synthesized into a live
#      ESC by the diagnostic path — sanitize_printable strips formed control
#      bytes, and the emitter must not manufacture new ones. Exercised under
#      /bin/sh (macOS xpg echo) and dash (the CI shell) where echo interprets
#      backslash sequences.
dv17="$tmp/v2echoesc"
dv17spec=$(new_spec "$dv17" vtwoechoesc)
{
  printf '# tasks\n\n**Format-version:** 2\n\n## Tasks\n\n'
  printf '### Task 1 — ready\n\n'
  printf -- '- **Dependencies:** none\n'
  printf -- '- **Estimated effort:** 1 day\n\n'
  printf '## Awaiting input\n\n'
  printf -- '- **Task 9\\033[31mX** literal backslash sequence in the id.\n\n'
  printf '## Deferred\n\n(none yet)\n\n## Out of scope\n\n(none yet)\n'
} >"$dv17spec/tasks.md"
seal_base "$dv17"
for v17_sh in /bin/sh dash; do
  command -v "$v17_sh" >/dev/null 2>&1 || continue
  v17_err="$tmp/v2echoesc.${v17_sh##*/}.err"
  rc=0
  v17_out=$("$v17_sh" "$SEL" "$dv17spec" 2>"$v17_err") || rc=$?
  [ "$rc" = 0 ] || fail "v2-echo-esc ($v17_sh): exit $rc, expected 0"
  [ "$v17_out" = 1 ] || fail "v2-echo-esc ($v17_sh): selected '$v17_out', expected 1"
  grep -q 'violates the task-id grammar' "$v17_err" \
    || fail "v2-echo-esc ($v17_sh): the rejection warning must still be emitted"
  LC_ALL=C grep '[^ -~]' "$v17_err" >/dev/null \
    && fail "v2-echo-esc ($v17_sh): a literal backslash sequence was re-synthesized into a control byte on stderr"
done
echo "ok: literal backslash sequences are never re-synthesized into terminal escapes"

echo "PASS: orchestrate-select"
