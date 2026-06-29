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

# ---------------------------------------------------------------------------
# --critical-path mode (Task 7 of specs/spec-comprehension, D-6, REQ-C1.3):
# an additive mode that emits the effort-weighted longest-dependent chain — the
# structural critical path — as ordered task ids, one per line, reusing the SAME
# weight()/crit() longest-chain logic the selector uses. The dependency-graph
# view highlights exactly this output, so "the highlighted path matches the
# reused computation" holds by construction. Unlike selection, the path is over
# the FULL task DAG (all sections): the terminal-task exclusion is a remaining-
# work filter for *dispatch*, not for the *visualization*.
# ---------------------------------------------------------------------------

# 9. --critical-path emits the full-graph longest effort-weighted chain. On the
#    chain fixture (d1) the longest chain is 1 -> 2 -> 3 -> 4 (1 + 0.5 + 1 + 1);
#    task 5 is a short leaf off 1, so it is not on the path.
cp_out=$(/bin/bash "$SEL" --critical-path "$d1") || fail "--critical-path d1: non-zero exit"
cp_expected=$(printf '1\n2\n3\n4')
[ "$cp_out" = "$cp_expected" ] \
  || fail "--critical-path d1: got [$cp_out], expected [1 2 3 4]"
echo "ok: --critical-path emits the full-graph effort-weighted longest chain"

# 10. The mode is additive: the default selection output is unchanged.
got=$(/bin/bash "$SEL" "$d1") || fail "default mode regressed under --critical-path addition"
[ "$got" = 2 ] || fail "default selection changed: got '$got', expected 2"
echo "ok: --critical-path is additive — default selection is unchanged"

# 11. Over the real spec-comprehension bundle the emitted path matches the
#     documented structural critical path (tasks.md build-order note:
#     1 -> 2 -> 3 -> 5 -> 6 -> 7 -> 11). This anchors REQ-C1.3's "matches the
#     reused computation for the same bundle". The path is section-independent
#     (full DAG), so it is stable as tasks complete.
real="$here/../specs/spec-comprehension"
if [ -d "$real" ]; then
  cp_real=$(/bin/bash "$SEL" --critical-path "$real") \
    || fail "--critical-path real bundle: non-zero exit"
  cp_real_expected=$(printf '1\n2\n3\n5\n6\n7\n11')
  [ "$cp_real" = "$cp_real_expected" ] \
    || fail "--critical-path real bundle: got [$cp_real], expected [1 2 3 5 6 7 11]"
  echo "ok: --critical-path matches the documented critical path on the real bundle"
fi

# 12. --critical-path fails closed on a missing / taskless tasks.md (exit 2),
#     same as selection.
rc=0
/bin/bash "$SEL" --critical-path "$tmp/does-not-exist" >/dev/null 2>&1 || rc=$?
[ "$rc" = 2 ] || fail "--critical-path missing tasks.md: exit $rc, expected 2"
rc=0
/bin/bash "$SEL" --critical-path "$d6" >/dev/null 2>&1 || rc=$?
[ "$rc" = 2 ] || fail "--critical-path taskless tasks.md: exit $rc, expected 2"
echo "ok: --critical-path fails closed on a missing/taskless bundle"

# 13. A single depless task is its own critical path.
cp_solo=$(/bin/bash "$SEL" --critical-path "$d8") || fail "--critical-path solo: non-zero exit"
[ "$cp_solo" = 1 ] || fail "--critical-path solo: got [$cp_solo], expected [1]"
echo "ok: --critical-path of a single depless task is that task"

# ---------------------------------------------------------------------------
# Prose-style dependency lines (specs/kickoff-lifecycle uses these): the
# Dependencies bullet may read "Task 1." (with a trailing period), carry a
# parenthetical qualifier whose own text contains id-shaped tokens
# ("Task 6 (REQ-A1.8 / D-9 — ...)"), or trail a cross-spec clause naming
# ANOTHER spec's tasks ("plus cross-spec (hard): ... Task 1 ... Task 4").
# The selector must parse only the LOCAL dependency ids:
#   - a trailing period must not break the id (so "Task 1." is dep 1);
#   - tokens inside a parenthetical qualifier must NOT become phantom deps
#     ("REQ-A1.8 / D-9" must not yield deps 1.8 or 9);
#   - a cross-spec clause (introduced after a paren / "plus") names another
#     bundle's tasks and must NOT be read as local deps.
# ---------------------------------------------------------------------------

# parse_deps_assert <label> <deps-line> <ready|blocked> [in_progress_ids...]
# Builds a single Forward-plan candidate task 50 whose Dependencies bullet is
# exactly <deps-line>. Helper tasks 1..9 are Completed by default; any id passed
# after the expected outcome is placed In progress instead, so a dep on it (if
# parsed) would block task 50. This lets a case assert both that a genuine dep
# is honored (put it In progress, expect blocked) and that a phantom/cross-spec
# id is NOT parsed (put it In progress, expect ready — a wrong parse would block).
parse_deps_assert() {
  pd_label=$1
  pd_line=$2
  pd_expect=$3
  shift 3
  pd_inprog=" $* "
  pd_dir="$tmp/parse-$(echo "$pd_label" | tr -c 'A-Za-z0-9' _)"
  mkdir -p "$pd_dir"
  {
    printf '# tasks\n\n## Forward plan\n\n'
    printf '### Task 50 — candidate under test\n\n'
    printf -- '- **Dependencies:** %s\n' "$pd_line"
    printf -- '- **Estimated effort:** 1 day\n\n'
    printf '## In progress\n\n'
    for pd_i in 1 2 3 4 5 6 7 8 9; do
      case "$pd_inprog" in
        *" $pd_i "*)
          printf '### Task %s — in flight\n\n' "$pd_i"
          printf -- '- **Dependencies:** none\n'
          printf -- '- **Estimated effort:** 1 day\n\n'
          ;;
      esac
    done
    printf '## Completed\n\n'
    for pd_i in 1 2 3 4 5 6 7 8 9; do
      case "$pd_inprog" in
        *" $pd_i "*) : ;;
        *)
          printf '### Task %s — done\n\n' "$pd_i"
          printf -- '- **Dependencies:** none\n'
          printf -- '- **Estimated effort:** 1 day\n\n'
          ;;
      esac
    done
  } >"$pd_dir/tasks.md"

  pd_rc=0
  pd_got=$(/bin/bash "$SEL" "$pd_dir" 2>/dev/null) || pd_rc=$?
  if [ "$pd_expect" = ready ]; then
    [ "$pd_rc" = 0 ] && [ "$pd_got" = 50 ] \
      || fail "deps-parse [$pd_label]: line '$pd_line' should leave task 50 READY (got '$pd_got', rc $pd_rc)"
  else
    # blocked: task 50 must NOT be selected. With every other task non-Forward,
    # the only possible Forward candidate is 50, so a correct block → exit 1.
    { [ "$pd_rc" = 1 ] || [ "$pd_got" != 50 ]; } \
      || fail "deps-parse [$pd_label]: line '$pd_line' should leave task 50 BLOCKED (got '$pd_got', rc $pd_rc)"
  fi
  echo "ok: deps-parse [$pd_label] -> $pd_expect"
}

# Baseline OC-style bare-number deps still parse (regression guard for the fix).
parse_deps_assert "none" "none" ready
parse_deps_assert "none-dot" "none." ready
parse_deps_assert "bare-1-6" "1, 6" ready         # both Completed -> ready
parse_deps_assert "bare-1-6-blk" "1, 6" blocked 6 # dep 6 In progress -> blocked
parse_deps_assert "bare-1-3-4" "1, 3, 4" ready
parse_deps_assert "bare-1-3-4-blk" "1, 3, 4" blocked 3 # dep 3 In progress -> blocked

# Trailing period must not erase the dependency: "Task 1." is a real dep 1.
parse_deps_assert "task-1-dot" "Task 1." blocked 1   # dep 1 In progress -> blocked
parse_deps_assert "task-1-dot-ready" "Task 1." ready # dep 1 Completed   -> ready
parse_deps_assert "task-3-dot" "Task 3." blocked 3
parse_deps_assert "task-3-dot-ready" "Task 3." ready

# Parenthetical qualifier: deps are "Task 1" and "Task 6"; the ids INSIDE the
# paren (REQ-A1.8 -> 1.8, D-9 -> 9) must NOT become phantom deps. Put 9 (the
# phantom) In progress: a correct parse ignores it, so 50 stays ready (deps 1,6
# Completed). A buggy parse would read phantom 9 and block.
parse_deps_assert "paren-phantom-ignored" \
  "Task 1; Task 6 (REQ-A1.8 / D-9 — the Draft→Ready producer is" ready 9
# And the genuine deps from that same line are honored: put 6 In progress.
parse_deps_assert "paren-real-dep-6" \
  "Task 1; Task 6 (REQ-A1.8 / D-9 — the Draft→Ready producer is" blocked 6
parse_deps_assert "paren-real-dep-1" \
  "Task 1; Task 6 (REQ-A1.8 / D-9 — the Draft→Ready producer is" blocked 1

# DOCUMENTED LIMITATION — a local dep written AFTER a mid-line parenthetical is
# dropped. The greedy paren-strip (sub(/\(.*/, ...)) removes the parenthetical
# AND everything after it, because in the real bundles that trailing text is a
# qualifier or a cross-spec clause whose own id-shaped tokens must NOT become
# local deps (see the cross-spec cases below). Every real bundle places its
# local deps BEFORE any parenthetical, so this is safe; pinned here so a future
# move to a non-greedy strip updates this test on purpose rather than tripping
# it by accident. Here dep "Task 2" trails the paren: with Task 2 In progress a
# correct (greedy) parse drops it, so task 50 sees only dep 1 (Completed) and
# stays READY. Honoring the after-paren dep would (wrongly) block on Task 2.
parse_deps_assert "paren-trailing-dep-dropped" \
  "Task 1 (the foundational one), Task 2" ready 2

# Cross-spec clause: the only LOCAL dep is Task 5; the "orchestration-concurrency
# Task 1 ... Task 4" names ANOTHER bundle's tasks and must NOT be parsed local.
# Put local-ids 1 and 4 In progress: a correct parse ignores the cross-spec
# mention, so with dep 5 Completed task 50 stays ready. A buggy parse reads
# 1/4 as local deps and blocks.
parse_deps_assert "cross-spec-ignored" \
  "Task 5; plus cross-spec (hard): \`orchestration-concurrency\`" ready 1 4
parse_deps_assert "cross-spec-real-dep-5" \
  "Task 5; plus cross-spec (hard): \`orchestration-concurrency\`" blocked 5

# Multiple comma-joined "Task N" deps with a trailing period on the last id.
parse_deps_assert "multi-task-trailing" "Task 2, Task 4, Task 6." ready
parse_deps_assert "multi-task-trailing-blk2" "Task 2, Task 4, Task 6." blocked 2
parse_deps_assert "multi-task-trailing-blk4" "Task 2, Task 4, Task 6." blocked 4
parse_deps_assert "multi-task-trailing-blk6" "Task 2, Task 4, Task 6." blocked 6

# Empty / whitespace-only Dependencies value: no ids parse, so task 50 has no
# effective deps and is ready. Pins robustness (the awk pipeline must not choke
# on an empty value) — both naive and fixed parsers agree an empty value is depless.
parse_deps_assert "empty" "" ready
parse_deps_assert "whitespace-only" "   " ready

# Malformed value with no id-shaped tokens at all -> treated as depless -> ready.
# DOCUMENTED LIMITATION: an unparseable Dependencies value (e.g. "see design
# doc", "TBD") yields NO numeric ids, so the task is considered ready, not
# blocked — the selector understands only numeric ids and cannot distinguish
# prose-without-ids from "Dependencies: none". Current behavior, pinned on purpose.
parse_deps_assert "no-ids-prose" "see the design doc; to be determined" ready

# Trailing-semicolon variant ("Task 1;"): the ";" is a separator collapsed by the
# id-extraction pass, not part of the id, so dep 1 is honored (In progress -> blocked).
parse_deps_assert "task-1-semicolon" "Task 1;" blocked 1
parse_deps_assert "task-1-semicolon-ready" "Task 1;" ready
# Trailing-period variant on task 2 (completes the "Task 1." / "Task 2." pair the
# brief calls out; discriminates the fix — a naive parser drops "2." entirely).
parse_deps_assert "task-2-dot" "Task 2." blocked 2
parse_deps_assert "task-2-dot-ready" "Task 2." ready

# Mixed ";" and "," separators in a single line, the last id carrying a trailing
# period. All three ids must parse; the trailing "." on "Task 3." discriminates
# the fix (a naive parser drops it). Assert each id is individually honored.
parse_deps_assert "mixed-sep" "Task 1; Task 2, Task 3." ready
parse_deps_assert "mixed-sep-blk1" "Task 1; Task 2, Task 3." blocked 1
parse_deps_assert "mixed-sep-blk2" "Task 1; Task 2, Task 3." blocked 2
parse_deps_assert "mixed-sep-blk3" "Task 1; Task 2, Task 3." blocked 3

# ---------------------------------------------------------------------------
# 14. End-to-end prose-deps fixture mirroring specs/kickoff-lifecycle's shape:
# Task 1 Completed; Tasks 2/5/7 depend on "Task 1."; Task 3 depends on
# "Task 1; Task 6 (...)"; Task 6 depends on "Task 5; plus cross-spec ...";
# Task 4 depends on Task 3; Task 8 depends on "Task 2, Task 4, Task 6.".
# Genuinely ready = {2,5,7} (their only dep, Task 1, is Completed). 3 is blocked
# on Task 6 (Forward, not done), 4 on Task 3, 6 on Task 5 (Forward, not done),
# 8 on 2/4/6 (Forward, not done). The selector must pick one of {2,5,7} and
# never 3/4/6/8.
# ---------------------------------------------------------------------------
d_kl="$tmp/kickoff-prose"
mkdir -p "$d_kl"
cat >"$d_kl/tasks.md" <<'EOF'
# tasks

## Forward plan

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

## Completed

### Task 1 — meta-spec root

- **Dependencies:** none.
- **Estimated effort:** half day
EOF
got=$(/bin/bash "$SEL" "$d_kl") || fail "kickoff-prose fixture: non-zero exit ($?)"
case "$got" in
  2 | 5 | 7) : ;;
  *) fail "kickoff-prose fixture: selected '$got', expected one of {2,5,7}" ;;
esac
echo "ok: prose-deps end-to-end selects a genuinely-ready task ($got in {2,5,7})"

# Exhaustively confirm 3/4/6/8 are never selectable here: each is blocked by a
# Forward-plan (not Completed) dependency, so even after completing {2,5,7} they
# would still depend on each other. We assert directly that the parsed ready set
# excludes them by completing 2,5,7 and checking the next pick is never 3 alone-
# blocked path. Simpler: assert the FIRST pick is in {2,5,7} (above) and that
# removing 2,5,7 from contention (mark them In progress) yields no ready task,
# proving 3/4/6/8 are all blocked on un-Completed Forward deps.
d_klb="$tmp/kickoff-prose-blocked"
mkdir -p "$d_klb"
# Same bundle but with 2,5,7 moved to In progress so only 3,4,6,8 remain in
# Forward plan; each depends on a non-Completed task → nothing ready.
cat >"$d_klb/tasks.md" <<'EOF'
# tasks

## Forward plan

### Task 3 — kickoff flip

- **Dependencies:** Task 1; Task 6 (REQ-A1.8 / D-9 — the Draft→Ready producer is
  gated behind the derived reconcile so the lifecycle is never half-wired).
- **Estimated effort:** half day

### Task 4 — kickoff readies PR

- **Dependencies:** Task 3.
- **Estimated effort:** 1 day

### Task 6 — derived reconcile

- **Dependencies:** Task 5; plus cross-spec (hard): `orchestration-concurrency`
  Task 1 (derivation engine) and Task 4 (single reconcile writer).
- **Estimated effort:** 1 day

### Task 8 — migration sweep

- **Dependencies:** Task 2, Task 4, Task 6.
- **Estimated effort:** half day

## In progress

### Task 2 — validator

- **Dependencies:** Task 1.
- **Estimated effort:** half day

### Task 5 — orchestrate gate

- **Dependencies:** Task 1.
- **Estimated effort:** half day

### Task 7 — downstream surfaces

- **Dependencies:** Task 1.
- **Estimated effort:** half day

## Completed

### Task 1 — meta-spec root

- **Dependencies:** none.
- **Estimated effort:** half day
EOF
rc=0
/bin/bash "$SEL" "$d_klb" >/dev/null 2>&1 || rc=$?
[ "$rc" = 1 ] || fail "kickoff-prose-blocked: tasks 3/4/6/8 must all be blocked (exit $rc, expected 1)"
echo "ok: prose-deps end-to-end leaves 3/4/6/8 blocked (each on a non-Completed Forward dep)"

# ---------------------------------------------------------------------------
# 15. Genuine dotted task ids (e.g. 1.2, 3.5) are preserved verbatim: the
# trailing-period strip removes ONLY a trailing dot, never the internal dot of a
# fractional id. The dotted helper tasks can't be expressed through
# parse_deps_assert (which seeds integer tasks 1..9), so use standalone fixtures.
# ---------------------------------------------------------------------------
# Both fractional deps Completed (last with a trailing period) -> ready. A naive
# parser would drop "Task 3.5." (trailing period); the fix keeps it as dep 3.5.
d_dot="$tmp/dotted-prose"
mkdir -p "$d_dot"
cat >"$d_dot/tasks.md" <<'EOF'
# tasks

## Forward plan

### Task 60 — depends on two fractional ids, last with a trailing period

- **Dependencies:** Task 1.2, Task 3.5.
- **Estimated effort:** 1 day

## Completed

### Task 1.2 — fractional root a

- **Dependencies:** none
- **Estimated effort:** 1 day

### Task 3.5 — fractional root b

- **Dependencies:** none
- **Estimated effort:** 1 day
EOF
got=$(/bin/bash "$SEL" "$d_dot") || fail "dotted-prose: non-zero exit ($?)"
[ "$got" = 60 ] || fail "dotted-prose: selected '$got', expected 60 (both fractional deps Completed)"
echo "ok: fractional deps 'Task 1.2, Task 3.5.' parse (internal dot kept, trailing dot stripped)"

# The trailing-period fractional dep is genuinely honored: move 3.5 to In
# progress and task 60 must block. Discriminates the fix — a naive parser drops
# "3.5." and would wrongly leave 60 ready.
d_dotb="$tmp/dotted-prose-blocked"
mkdir -p "$d_dotb"
cat >"$d_dotb/tasks.md" <<'EOF'
# tasks

## Forward plan

### Task 60 — depends on a fractional id with a trailing period

- **Dependencies:** Task 1.2, Task 3.5.
- **Estimated effort:** 1 day

## In progress

### Task 3.5 — fractional dep in flight

- **Dependencies:** none
- **Estimated effort:** 1 day

## Completed

### Task 1.2 — fractional root a

- **Dependencies:** none
- **Estimated effort:** 1 day
EOF
rc=0
/bin/bash "$SEL" "$d_dotb" >/dev/null 2>&1 || rc=$?
[ "$rc" = 1 ] || fail "dotted-prose-blocked: 'Task 3.5.' In progress must block task 60 (exit $rc, expected 1)"
echo "ok: trailing-period fractional dep '3.5.' is honored (blocks when not Completed)"

# Internal dot must NOT be stripped: a dep on Completed Task 3.5 leaves task 60
# ready. Were the dot collapsed (3.5 -> 35), id 35 would dangle and block — so a
# ready result proves the internal dot survives.
d_dotc="$tmp/dotted-internal"
mkdir -p "$d_dotc"
cat >"$d_dotc/tasks.md" <<'EOF'
# tasks

## Forward plan

### Task 60 — depends on fractional 3.5

- **Dependencies:** Task 3.5
- **Estimated effort:** 1 day

## Completed

### Task 3.5 — fractional root

- **Dependencies:** none
- **Estimated effort:** 1 day
EOF
got=$(/bin/bash "$SEL" "$d_dotc") || fail "dotted-internal: non-zero exit ($?)"
[ "$got" = 60 ] || fail "dotted-internal: selected '$got', expected 60 (3.5 must resolve to Completed 3.5, not dangling 35)"
echo "ok: internal dot preserved — dep 'Task 3.5' resolves to Completed 3.5 (not 35)"

# ---------------------------------------------------------------------------
# 16. KNOWN LIMITATION — first-line-only dependency parsing. The parser reads ids
# ONLY from the single line carrying the `**Dependencies:**` marker; a local dep
# id that WRAPS onto a continuation line is not seen. This is safe for the real
# bundles — every local dep fits on the first line, and the only text that wraps
# is a parenthetical or cross-spec clause we deliberately ignore (see
# specs/kickoff-lifecycle/tasks.md, Tasks 3 and 6). It IS a limitation, pinned
# here so a future move to multi-line parsing updates this test on purpose rather
# than tripping it by accident.
#
# Fixture: deps "Task 1, Task 2," with "Task 3." on the continuation line. Tasks
# 1,2 Completed; Task 3 In progress. The second line is not parsed, so task 70
# sees only deps {1,2} (both Completed) and is READY. If the wrap WERE parsed,
# the In-progress Task 3 would block it.
# ---------------------------------------------------------------------------
d_wrap="$tmp/wrap-secondline"
mkdir -p "$d_wrap"
cat >"$d_wrap/tasks.md" <<'EOF'
# tasks

## Forward plan

### Task 70 — deps wrap onto a second line

- **Dependencies:** Task 1, Task 2,
  Task 3.
- **Estimated effort:** 1 day

## In progress

### Task 3 — second-line dep, in flight (NOT seen by the parser)

- **Dependencies:** none
- **Estimated effort:** 1 day

## Completed

### Task 1 — first-line dep a

- **Dependencies:** none
- **Estimated effort:** 1 day

### Task 2 — first-line dep b

- **Dependencies:** none
- **Estimated effort:** 1 day
EOF
got=$(/bin/bash "$SEL" "$d_wrap") || fail "wrap-secondline: non-zero exit ($?)"
[ "$got" = 70 ] \
  || fail "wrap-secondline: selected '$got', expected 70 (second-line dep 3 is NOT parsed — first-line-only limitation)"
echo "ok: first-line-only limitation pinned — a wrapped second-line dep is not parsed"

# Conversely, the FIRST-line deps on that same wrapped bullet ARE honored: move
# Task 2 (first line) to In progress and task 70 must block.
d_wrapb="$tmp/wrap-firstline"
mkdir -p "$d_wrapb"
cat >"$d_wrapb/tasks.md" <<'EOF'
# tasks

## Forward plan

### Task 70 — deps wrap onto a second line

- **Dependencies:** Task 1, Task 2,
  Task 3.
- **Estimated effort:** 1 day

## In progress

### Task 2 — first-line dep, in flight

- **Dependencies:** none
- **Estimated effort:** 1 day

## Completed

### Task 1 — first-line dep a

- **Dependencies:** none
- **Estimated effort:** 1 day
EOF
rc=0
/bin/bash "$SEL" "$d_wrapb" >/dev/null 2>&1 || rc=$?
[ "$rc" = 1 ] || fail "wrap-firstline: first-line dep Task 2 In progress must block task 70 (exit $rc, expected 1)"
echo "ok: first-line deps on a wrapped bullet are honored (Task 2 blocks)"

echo "PASS: orchestrate-select"
