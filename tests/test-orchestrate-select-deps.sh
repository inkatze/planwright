#!/bin/bash
# Tests for scripts/orchestrate-select.sh — DEPENDENCY-LINE PARSING and
# evidence-quality diagnostics (selection: Task 13, REQ-F1.2, D-7; prose-deps
# handling from PR #78; live-truth rewire: orchestration-concurrency Task 5,
# D-3, REQ-B1.2).
#
# Split out of tests/test-orchestrate-select.sh (guard-coverage Task 6,
# REQ-E1.2, D-9); the base file's header carries the full selection contract and
# names the other three siblings. No assertion changed in the split.
#
# What this file covers:
#   - the prose-style `**Dependencies:**` grammar (trailing periods, mixed
#     separators, parenthetical qualifiers holding id-shaped tokens, trailing
#     cross-spec clauses) parsing to only the LOCAL deps. The dependency GRAPH
#     is parsed from tasks.md by the selector itself, NOT delegated to the
#     derivation engine (whose parser is stricter), so this grammar is the
#     selector's own contract;
#   - genuine dotted task ids (1.2, 3.5) surviving the trailing-period strip;
#   - the pinned first-line-only parsing limitation (§16);
#   - evidence-quality diagnostics on the success path: the engine's `degraded`
#     record and its success-path stderr warnings reach the operator while
#     stdout stays the selected id alone (§§17–18).
#
# Completion is LIVE TRUTH throughout: a helper task is COMPLETED via a
# reachable `Planwright-Task: <spec>/<id>` trailer (D-2), IN-PROGRESS via a
# fresh runtime dispatch marker (D-3).
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

# make_failing_gh_stub <dir> — drop a `gh` on PATH that always errors (mirrors
# the engine test). With a remote configured, this drives the engine's
# configured-but-failing-gh path, which emits a `degraded` record.
make_failing_gh_stub() {
  mkdir -p "$1"
  printf '#!/bin/sh\necho "gh: simulated failure" >&2\nexit 1\n' >"$1/gh"
  chmod +x "$1/gh"
}

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

echo "PASS: orchestrate-select (dependency-line parsing, evidence diagnostics)"
