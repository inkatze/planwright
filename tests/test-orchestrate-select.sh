#!/bin/bash
# Tests for scripts/orchestrate-select.sh — v1 SELECTION, live-truth exclusion,
# and --critical-path mode (selection: Task 13, REQ-F1.2, D-7, D-8; live-truth
# rewire: orchestration-concurrency Task 5, D-3, REQ-B1.2; --critical-path:
# spec-comprehension Task 7, D-6, REQ-C1.3).
#
# Split into four files (guard-coverage Task 6, REQ-E1.2, D-9): this file was a
# wall-clock straggler, so its four cohesive concern groups now run as four
# files the runner's tests/*.sh discovery picks up in parallel. The siblings are
#   tests/test-orchestrate-select-deps.sh        dependency-line parsing and
#                                                evidence-quality diagnostics
#   tests/test-orchestrate-select-v2.sh          format-version 2 candidacy
#   tests/test-orchestrate-select-v2-hygiene.sh  v2 header/parse hygiene and
#                                                untrusted-content discipline
# No assertion changed in the split; each file rebuilds the fixtures it needs so
# it still runs standalone.
#
# Selection contract:
#   - completed / in-progress state is read from the LIVE DERIVATION
#     (scripts/orchestrate-state.sh), NOT from tasks.md section placement — so a
#     task that is in-flight or already completed (by git/marker evidence the
#     committed snapshot has not yet caught up to) is never re-dispatched
#     (Task 5, D-3, REQ-B1.2);
#   - a ready task is one the derivation reports neither completed nor
#     in-progress, whose every dependency the derivation reports completed
#     (the dependency GRAPH is still parsed from tasks.md, so the prose-deps
#     parser added in PR #78 is preserved), and that is a candidate under the
#     bundle's declared format version (invariant-tasks Task 5, D-8,
#     REQ-C1.2): v1 = sits in ## Forward plan; v2 = not parked by a live
#     reference bullet under Awaiting input / Deferred / Out of scope;
#   - among ready tasks, the head of the effort-weighted longest dependent chain
#     wins (critical-path-first); FIFO (file order) breaks ties;
#   - no ready task → exit 1 (nothing to dispatch this step);
#   - a missing / taskless / NUL-laden tasks.md, a missing or unparseable
#     Format-version: line (REQ-C1.8), a missing echo-safety.sh helper, or a
#     derivation that fails closed → exit 2;
#   - a v2 transient evidence failure (remote configured, evidence fetch
#     failed) → exit 3, dispatch nothing (REQ-B1.5); v1 keeps its documented
#     degraded-but-proceed behavior.
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

echo "PASS: orchestrate-select (v1 selection, live truth, --critical-path)"
