#!/bin/bash
# Tests for scripts/orchestrate-state.sh — the task-state derivation engine,
# the shared backbone the reconcile (T4), selection (T5), and the guards (T7)
# read through (orchestration-concurrency Task 1; D-1, D-2, D-3; REQ-C1.1,
# REQ-C1.2, REQ-A1.3, REQ-F1.1).
#
# Contract under test:
#   - state is DERIVED from observable evidence, never read from tasks.md
#     section placement: merged PR (gh), task-branch merge-reachability,
#     a Planwright-Task trailer reachable from base, and the timestamped
#     runtime dispatch marker (with a staleness check) — REQ-C1.1;
#   - git ground truth takes precedence; a genuine signal contradiction is
#     emitted as a tagged record on the output stream, not silently resolved
#     (REQ-C1.2);
#   - no remote is first-class: derivation runs from git + trailer + marker
#     with gh skipped; a configured-but-failing gh degrades to git-only and
#     surfaces the degradation rather than wedging (REQ-A1.3);
#   - parsed identifiers are validated against their grammar before use; a
#     malformed/hostile Planwright-Task value is refused and never used
#     (REQ-F1.1);
#   - the derivation is idempotent (read-only; two runs agree).
#
# Output stream is a tagged TSV on stdout, one record per line:
#   task<TAB><id><TAB><state><TAB><evidence>   state: completed|in-progress|ready|blocked
#   contradiction<TAB><id><TAB><message>
#   degraded<TAB>gh<TAB><message>
#   refused<TAB>Planwright-Task<TAB><value>
#
# Runs standalone under /bin/bash (the bash 3.2 floor).
set -eu
LC_ALL=C
export LC_ALL
unset CDPATH

here=$(cd "$(dirname "$0")" && pwd)
STATE="$here/../scripts/orchestrate-state.sh"
TAB=$(printf '\t')

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

[ -x "$STATE" ] || fail "scripts/orchestrate-state.sh missing or not executable"

# git with a deterministic, signing-free identity (the framework never signs
# in CI fixtures, and a stray global commit.gpgsign would otherwise break
# fixture commits).
gitc() {
  repo="$1"
  shift
  git -C "$repo" -c user.name=test -c user.email=test@example.invalid \
    -c commit.gpgsign=false -c init.defaultBranch=main "$@"
}

# Pull a single task's derived state out of the tagged output stream.
state_of() {
  printf '%s\n' "$1" | awk -F"$TAB" -v i="$2" '$1=="task" && $2==i {print $3; exit}'
}

# True when a tagged record for (tag,id) is present.
has_record() {
  printf '%s\n' "$1" | awk -F"$TAB" -v t="$2" -v i="$3" \
    'BEGIN{f=1} $1==t && $2==i {f=0} END{exit f}'
}

assert_state() {
  got=$(state_of "$1" "$2")
  [ "$got" = "$3" ] || fail "$4: task $2 derived '$got', expected '$3'"
}

# Write the fixture tasks.md. Section placement is deliberately WRONG for the
# real evidence (everything sits under Forward plan): the engine must ignore
# placement and derive from evidence alone.
write_tasks() {
  spec="$1"
  cat >"$spec/tasks.md" <<'EOF'
# Demo — Tasks

**Status:** Active

## Forward plan

### Task 1 — merged branch
- **Dependencies:** none

### Task 2 — trailer-only base commit
- **Dependencies:** none

### Task 3 — merged PR (squash, gh only)
- **Dependencies:** none

### Task 4 — in-flight branch + open PR
- **Dependencies:** none

### Task 5 — fresh marker only
- **Dependencies:** none

### Task 6 — stale marker only
- **Dependencies:** none

### Task 7 — no evidence, deps met
- **Dependencies:** 1

### Task 8 — no evidence, deps unmet
- **Dependencies:** 4

## Completed

(none)
EOF
}

# A gh stub printing canned `headRefName<TAB>state` lines. The engine calls
# `gh pr list ... --jq '... | @tsv'`; the stub ignores the args and prints the
# already-rendered TSV, so no system jq is needed.
make_gh_stub() {
  dir="$1"
  shift
  mkdir -p "$dir"
  {
    echo '#!/bin/sh'
    echo 'cat <<STUB'
    for line in "$@"; do printf '%s\n' "$line"; done
    echo 'STUB'
  } >"$dir/gh"
  chmod +x "$dir/gh"
}

make_failing_gh_stub() {
  dir="$1"
  mkdir -p "$dir"
  printf '#!/bin/sh\necho "gh: simulated failure" >&2\nexit 1\n' >"$dir/gh"
  chmod +x "$dir/gh"
}

# ---------------------------------------------------------------------------
# 1. REQ-C1.1 — the mixed-evidence matrix derives the correct state per task.
# ---------------------------------------------------------------------------
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

repo="$tmp/matrix"
spec="$repo/specs/demo"
mkdir -p "$spec"
gitc_init() { git -C "$1" -c init.defaultBranch=main init -q; }
gitc_init "$repo"
write_tasks "$spec"
gitc "$repo" add -A
gitc "$repo" commit -q -m "base: spec bundle"
gitc "$repo" remote add origin https://example.invalid/demo.git

# Task 1: a branch merged into main (reachable) — completed by branch evidence.
gitc "$repo" checkout -q -b planwright/demo/task-1
gitc "$repo" commit -q --allow-empty -m "task 1 work"
gitc "$repo" checkout -q main
gitc "$repo" merge -q --no-ff -m "merge task 1" planwright/demo/task-1

# Task 2: a trailer reachable from main, no branch — completed by trailer.
gitc "$repo" commit -q --allow-empty -m "task 2 work" -m "Planwright-Task: demo/2"

# Task 4: an in-flight branch with commits beyond base, not merged.
gitc "$repo" checkout -q -b planwright/demo/task-4
gitc "$repo" commit -q --allow-empty -m "task 4 wip"
gitc "$repo" checkout -q main

# Tasks 5 & 6: markers in the default runtime-marker dir.
mdir="$spec/.orchestrate/markers"
mkdir -p "$mdir"
date +%s >"$mdir/5" # fresh
echo 100 >"$mdir/6" # epoch 1970 → far past the threshold

# Task 3 merged PR, Task 4 open PR.
stubdir="$tmp/binmatrix"
make_gh_stub "$stubdir" \
  "planwright/demo/task-3${TAB}MERGED" \
  "planwright/demo/task-4${TAB}OPEN"

out=$(PATH="$stubdir:$PATH" "$STATE" "$spec")

assert_state "$out" 1 completed "C1.1 merged-branch"
assert_state "$out" 2 completed "C1.1 trailer-only"
assert_state "$out" 3 completed "C1.1 merged-PR"
assert_state "$out" 4 in-progress "C1.1 in-flight branch + open PR"
assert_state "$out" 5 in-progress "C1.1 fresh marker"
assert_state "$out" 6 ready "C1.1 stale marker (no commits) reverts to ready"
assert_state "$out" 7 ready "C1.1 no evidence, deps met"
assert_state "$out" 8 blocked "C1.1 no evidence, deps unmet"
echo "ok: REQ-C1.1 mixed-evidence matrix derives correct states"

# ---------------------------------------------------------------------------
# 2. idempotence — a second run produces byte-identical output (read-only).
# ---------------------------------------------------------------------------
out2=$(PATH="$stubdir:$PATH" "$STATE" "$spec")
[ "$out" = "$out2" ] || fail "idempotence: second run differs from the first"
echo "ok: derivation is idempotent (two runs agree)"

# ---------------------------------------------------------------------------
# 3. REQ-C1.2 — git-truth precedence; contradictions flagged, not resolved.
# ---------------------------------------------------------------------------
crepo="$tmp/contra"
cspec="$crepo/specs/demo"
mkdir -p "$cspec"
gitc_init "$crepo"
cat >"$cspec/tasks.md" <<'EOF'
# Demo — Tasks
## Forward plan
### Task 1 — reachable, PR closed-unmerged
- **Dependencies:** none
### Task 2 — reachable trailer, PR still open
- **Dependencies:** none
EOF
gitc "$crepo" add -A
gitc "$crepo" commit -q -m "base"
gitc "$crepo" remote add origin https://example.invalid/demo.git
# Task 1: branch merged (reachable) but its PR is CLOSED — reality wins.
gitc "$crepo" checkout -q -b planwright/demo/task-1
gitc "$crepo" commit -q --allow-empty -m "task 1 work"
gitc "$crepo" checkout -q main
gitc "$crepo" merge -q --no-ff -m "merge task 1" planwright/demo/task-1
# Task 2: a completion trailer reachable on main, but the PR is still OPEN.
gitc "$crepo" commit -q --allow-empty -m "task 2 work" -m "Planwright-Task: demo/2"

cstub="$tmp/bincontra"
make_gh_stub "$cstub" \
  "planwright/demo/task-1${TAB}CLOSED" \
  "planwright/demo/task-2${TAB}OPEN"
cout=$(PATH="$cstub:$PATH" "$STATE" "$cspec")

assert_state "$cout" 1 completed "C1.2 closed PR but reachable → completed (reality wins)"
has_record "$cout" contradiction 1 && fail "C1.2: task 1 (closed PR, consistent) must NOT be flagged"
assert_state "$cout" 2 completed "C1.2 reachable trailer → completed"
has_record "$cout" contradiction 2 || fail "C1.2: task 2 (done in git, PR open) must be flagged contradiction"
echo "ok: REQ-C1.2 git-truth precedence; genuine contradiction flagged on the stream"

# ---------------------------------------------------------------------------
# 4. REQ-A1.3 — no remote is first-class (gh skipped, no degradation noise).
# ---------------------------------------------------------------------------
nrepo="$tmp/noremote"
nspec="$nrepo/specs/demo"
mkdir -p "$nspec"
gitc_init "$nrepo"
cat >"$nspec/tasks.md" <<'EOF'
# Demo — Tasks
## Forward plan
### Task 1 — trailer-completed, no remote
- **Dependencies:** none
### Task 2 — fresh marker, no remote
- **Dependencies:** none
EOF
gitc "$nrepo" add -A
gitc "$nrepo" commit -q -m "base" -m "Planwright-Task: demo/1"
nmdir="$nspec/.orchestrate/markers"
mkdir -p "$nmdir"
date +%s >"$nmdir/2"
# A gh stub is on PATH, but with NO remote configured the engine must not call
# it — and must not emit a degradation record.
nstub="$tmp/binnoremote"
make_failing_gh_stub "$nstub"
nout=$(PATH="$nstub:$PATH" "$STATE" "$nspec") \
  || fail "A1.3 no-remote: engine exited non-zero"
assert_state "$nout" 1 completed "A1.3 no-remote trailer completion"
assert_state "$nout" 2 in-progress "A1.3 no-remote fresh marker"
printf '%s\n' "$nout" | grep -q "^degraded" \
  && fail "A1.3 no-remote: a degradation record was wrongly emitted"
echo "ok: REQ-A1.3 no-remote derivation is first-class (gh skipped, no noise)"

# ---------------------------------------------------------------------------
# 5. REQ-A1.3 — a configured-but-failing gh degrades to git-only and surfaces.
# ---------------------------------------------------------------------------
frepo="$tmp/ghfail"
fspec="$frepo/specs/demo"
mkdir -p "$fspec"
gitc_init "$frepo"
cat >"$fspec/tasks.md" <<'EOF'
# Demo — Tasks
## Forward plan
### Task 1 — merged branch, gh broken
- **Dependencies:** none
EOF
gitc "$frepo" add -A
gitc "$frepo" commit -q -m "base"
gitc "$frepo" remote add origin https://example.invalid/demo.git
gitc "$frepo" checkout -q -b planwright/demo/task-1
gitc "$frepo" commit -q --allow-empty -m "task 1 work"
gitc "$frepo" checkout -q main
gitc "$frepo" merge -q --no-ff -m "merge task 1" planwright/demo/task-1
fstub="$tmp/binghfail"
make_failing_gh_stub "$fstub"
fout=$(PATH="$fstub:$PATH" "$STATE" "$fspec") \
  || fail "A1.3 gh-failure: engine exited non-zero (must degrade, not wedge)"
printf '%s\n' "$fout" | grep -q "^degraded${TAB}gh" \
  || fail "A1.3 gh-failure: no degradation record surfaced"
assert_state "$fout" 1 completed "A1.3 gh-failure: git-only derivation still correct"
echo "ok: REQ-A1.3 configured-but-failing gh degrades to git-only and surfaces"

# ---------------------------------------------------------------------------
# 6. REQ-F1.1 — a malformed/hostile trailer value is refused, never used.
# ---------------------------------------------------------------------------
hrepo="$tmp/hostile"
hspec="$hrepo/specs/demo"
mkdir -p "$hspec"
gitc_init "$hrepo"
cat >"$hspec/tasks.md" <<'EOF'
# Demo — Tasks
## Forward plan
### Task 1 — legitimate trailer completion
- **Dependencies:** none
EOF
gitc "$hrepo" add -A
gitc "$hrepo" commit -q -m "base"
# A hostile trailer (path traversal) reachable on main alongside a valid one.
gitc "$hrepo" commit -q --allow-empty -m "valid" -m "Planwright-Task: demo/1"
gitc "$hrepo" commit -q --allow-empty -m "hostile" -m "Planwright-Task: ../../etc/passwd"
hout=$("$STATE" "$hspec") || fail "F1.1: engine exited non-zero on a hostile trailer"
assert_state "$hout" 1 completed "F1.1: the well-formed trailer still completes its task"
printf '%s\n' "$hout" | grep -q "^refused${TAB}Planwright-Task" \
  || fail "F1.1: the hostile trailer was not refused/flagged"
echo "ok: REQ-F1.1 hostile trailer value refused and never used"

# ---------------------------------------------------------------------------
# 6b. REQ-A1.1 / D-3 — a zero-commit dispatch branch is NOT completion evidence.
#     The branch is created as the first durable act of dispatch; until it
#     carries a commit it is the branch-create → first-commit window the marker
#     covers. A tip sitting exactly at base is trivially an ancestor of base, so
#     it must NOT derive completed — the marker (fresh → in-progress) or deps
#     (no marker → ready) decide.
# ---------------------------------------------------------------------------
zrepo="$tmp/zerocommit"
zspec="$zrepo/specs/demo"
mkdir -p "$zspec"
gitc_init "$zrepo"
cat >"$zspec/tasks.md" <<'EOF'
# Demo — Tasks
## Forward plan
### Task 1 — zero-commit branch, no marker
- **Dependencies:** none
### Task 2 — zero-commit branch, fresh marker
- **Dependencies:** none
EOF
gitc "$zrepo" add -A
gitc "$zrepo" commit -q -m "base"
gitc "$zrepo" branch planwright/demo/task-1 # created, no commits yet
gitc "$zrepo" branch planwright/demo/task-2
zmdir="$zspec/.orchestrate/markers"
mkdir -p "$zmdir"
date +%s >"$zmdir/2" # fresh marker covers the window
zout=$("$STATE" "$zspec") || fail "A1.1: engine exited non-zero on a zero-commit branch"
assert_state "$zout" 1 ready "A1.1: zero-commit branch + no marker → ready (not completed)"
assert_state "$zout" 2 in-progress "A1.1: zero-commit branch + fresh marker → in-progress"
echo "ok: REQ-A1.1/D-3 zero-commit dispatch branch is not completion evidence"

# ---------------------------------------------------------------------------
# 6c. marker robustness — a far-future marker (clock skew anomaly) does NOT
#     hold the task (fail-safe), and a symlink at the marker path is refused.
# ---------------------------------------------------------------------------
mrepo="$tmp/markerrobust"
mspec="$mrepo/specs/demo"
mkdir -p "$mspec"
gitc_init "$mrepo"
cat >"$mspec/tasks.md" <<'EOF'
# Demo — Tasks
## Forward plan
### Task 1 — far-future marker (anomalous)
- **Dependencies:** none
### Task 2 — symlink at the marker path
- **Dependencies:** none
### Task 3 — small-skew future marker (still fresh)
- **Dependencies:** none
EOF
gitc "$mrepo" add -A
gitc "$mrepo" commit -q -m "base"
mrdir="$mspec/.orchestrate/markers"
mkdir -p "$mrdir"
echo $(($(date +%s) + 999999999)) >"$mrdir/1" # far in the future → not a hold
ln -s /etc/hostname "$mrdir/2"                # a symlink is never a marker
echo $(($(date +%s) + 30)) >"$mrdir/3"        # 30s skew, within threshold
mout=$("$STATE" "$mspec") || fail "marker-robust: engine exited non-zero"
assert_state "$mout" 1 ready "far-future marker is anomalous → not held (ready)"
assert_state "$mout" 2 ready "symlink marker refused → not held (ready)"
assert_state "$mout" 3 in-progress "small forward clock skew still reads fresh"
echo "ok: marker robustness (future-skew + symlink) holds the fail-safe"

# ---------------------------------------------------------------------------
# 6d. REQ-F1.1 — an unsafe PLANWRIGHT_BASE_REF (option-injection) is refused.
# ---------------------------------------------------------------------------
rc=0
PLANWRIGHT_BASE_REF="--output=/tmp/x" "$STATE" "$mspec" >/dev/null 2>&1 || rc=$?
[ "$rc" = 2 ] || fail "F1.1 base ref: exit $rc, expected 2 for an option-like base"
echo "ok: REQ-F1.1 unsafe base ref refused (fail closed)"

# ---------------------------------------------------------------------------
# 7. fail-closed on a missing / taskless bundle (matches the sibling scripts).
# ---------------------------------------------------------------------------
rc=0
"$STATE" "$tmp/does-not-exist" >/dev/null 2>&1 || rc=$?
[ "$rc" = 2 ] || fail "missing spec dir: exit $rc, expected 2"
echo "ok: fails closed (exit 2) on a missing spec dir"

echo "PASS: test-orchestrate-state.sh"
