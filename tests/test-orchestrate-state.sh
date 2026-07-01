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
#   malformed-deps<TAB><id><TAB><raw>
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

# Pull a single task's derived EVIDENCE (column 4) out of the tagged stream, so
# a test can assert the derivation PATH, not just the resulting state (a state
# that is right via the wrong evidence would otherwise pass).
evidence_of() {
  printf '%s\n' "$1" | awk -F"$TAB" -v i="$2" '$1=="task" && $2==i {print $4; exit}'
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

assert_evidence() {
  got=$(evidence_of "$1" "$2")
  [ "$got" = "$3" ] || fail "$4: task $2 evidence '$got', expected '$3'"
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
# 6e. stale_marker_threshold config override — a repo-local override widens the
#     freshness window; a malformed value warns and falls back to the default.
#     Mirrors the advisory lock's stale_lock_threshold coverage.
# ---------------------------------------------------------------------------
trepo="$tmp/threshold"
tspec="$trepo/specs/demo"
mkdir -p "$tspec"
gitc_init "$trepo"
cat >"$tspec/tasks.md" <<'EOF'
# Demo — Tasks
## Forward plan
### Task 1 — marker 20 minutes old
- **Dependencies:** none
EOF
gitc "$trepo" add -A
gitc "$trepo" commit -q -m "base"
tmdir="$tspec/.orchestrate/markers"
mkdir -p "$tmdir"
echo $(($(date +%s) - 1200)) >"$tmdir/1" # 20m old: stale at the 15m default

# Default threshold (15m): the 20m marker is stale → the task reverts to ready.
tout=$("$STATE" "$tspec") || fail "threshold: engine exited non-zero (default)"
assert_state "$tout" 1 ready "threshold default 15m: 20m marker is stale → ready"

# Repo-local override to 30m: the same 20m marker is now fresh → in-progress.
mkdir -p "$trepo/.claude"
printf 'stale_marker_threshold: 30m\n' >"$trepo/.claude/planwright.local.yml"
tout=$("$STATE" "$tspec") || fail "threshold: engine exited non-zero (override)"
assert_state "$tout" 1 in-progress "threshold override 30m: 20m marker is fresh → in-progress"

# Malformed override: warn on stderr and fall back to the 15m default → ready.
printf 'stale_marker_threshold: not-a-number\n' >"$trepo/.claude/planwright.local.yml"
terr="$tmp/threshold.err"
tout=$("$STATE" "$tspec" 2>"$terr") || fail "threshold: engine exited non-zero (malformed)"
grep -q "ignoring malformed stale_marker_threshold" "$terr" \
  || fail "threshold malformed: no fallback warning surfaced"
assert_state "$tout" 1 ready "threshold malformed: falls back to 15m default → ready"
echo "ok: stale_marker_threshold override widens the window; malformed warns and falls back"

# ---------------------------------------------------------------------------
# 6f. PLANWRIGHT_ORCH_STATE_DIR override — markers are read from the overridden
#     base dir, not the default <spec-dir>/.orchestrate/markers.
# ---------------------------------------------------------------------------
orepo="$tmp/statedir"
ospec="$orepo/specs/demo"
mkdir -p "$ospec"
gitc_init "$orepo"
cat >"$ospec/tasks.md" <<'EOF'
# Demo — Tasks
## Forward plan
### Task 1 — fresh marker only in the overridden state dir
- **Dependencies:** none
EOF
gitc "$orepo" add -A
gitc "$orepo" commit -q -m "base"
# No marker in the DEFAULT dir; a fresh one only in the override dir.
altdir="$tmp/statedir-alt"
mkdir -p "$altdir"
date +%s >"$altdir/1"
# Without the override the task is ready (no marker found in the default dir).
oout=$("$STATE" "$ospec") || fail "statedir: engine exited non-zero (default dir)"
assert_state "$oout" 1 ready "statedir default: no marker in the default dir → ready"
# With the override the fresh marker is found → in-progress.
oout=$(PLANWRIGHT_ORCH_STATE_DIR="$altdir" "$STATE" "$ospec") \
  || fail "statedir: engine exited non-zero (override)"
assert_state "$oout" 1 in-progress "statedir override: fresh marker in the override dir → in-progress"
echo "ok: PLANWRIGHT_ORCH_STATE_DIR override redirects the marker read"

# ---------------------------------------------------------------------------
# 6g. REQ-F1.1 — an invalid spec id (the bundle dir name fails its grammar) is
#     refused with a fail-closed exit, never deriving against a bad identifier.
# ---------------------------------------------------------------------------
irepo="$tmp/invalidspec"
ispec="$irepo/specs/BadSpec" # uppercase is outside the spec-id grammar
mkdir -p "$ispec"
gitc_init "$irepo"
cat >"$ispec/tasks.md" <<'EOF'
# Bad — Tasks
## Forward plan
### Task 1 — never reached
- **Dependencies:** none
EOF
gitc "$irepo" add -A
gitc "$irepo" commit -q -m "base"
rc=0
"$STATE" "$ispec" >/dev/null 2>&1 || rc=$?
[ "$rc" = 2 ] || fail "F1.1 spec id: exit $rc, expected 2 for an invalid spec id"
echo "ok: REQ-F1.1 invalid spec id refused (fail closed)"

# ---------------------------------------------------------------------------
# 6h. dependency-grammar hardening — a Dependencies line carrying tokens outside
#     the task-id grammar keeps only the conforming ids (so a phantom number
#     grepped out of prose is NOT treated as a dependency) and surfaces the
#     non-conforming line as a tagged `malformed-deps` record (REQ-F1.1 — parsed
#     identifiers are validated against their grammar before use).
# ---------------------------------------------------------------------------
drepo="$tmp/depgrammar"
dspec="$drepo/specs/demo"
mkdir -p "$dspec"
gitc_init "$drepo"
cat >"$dspec/tasks.md" <<'EOF'
# Demo — Tasks
## Forward plan
### Task 1 — completed via trailer
- **Dependencies:** none
### Task 2 — real dep is 1, but the line carries stray prose
- **Dependencies:** 1 (see issue #2)
EOF
gitc "$drepo" add -A
gitc "$drepo" commit -q -m "base" -m "Planwright-Task: demo/1"
dout=$("$STATE" "$dspec") || fail "dep-grammar: engine exited non-zero"
assert_state "$dout" 1 completed "dep-grammar: trailer completes task 1"
# Task 2's only real dependency is 1 (completed); the '2' grepped from '#2' must
# NOT become a phantom dependency, so task 2 is ready, not blocked.
assert_state "$dout" 2 ready "dep-grammar: phantom prose number is not a dependency → ready"
has_record "$dout" malformed-deps 2 \
  || fail "dep-grammar: non-conforming Dependencies line not surfaced on the stream"
echo "ok: dependency-grammar hardening keeps real ids and surfaces malformed lines"

# ---------------------------------------------------------------------------
# 6i. dependency tokenization must not pathname-expand — a Dependencies line
#     containing a glob metacharacter is literal text (surfaced as malformed),
#     never expanded against the run directory into a phantom numeric dependency.
# ---------------------------------------------------------------------------
grepo="$tmp/depglob"
gspec="$grepo/specs/demo"
mkdir -p "$gspec"
gitc_init "$grepo"
cat >"$gspec/tasks.md" <<'EOF'
# Demo — Tasks
## Forward plan
### Task 1 — completed via trailer
- **Dependencies:** none
### Task 2 — a glob metacharacter where the id list belongs
- **Dependencies:** *
EOF
gitc "$grepo" add -A
gitc "$grepo" commit -q -m "base" -m "Planwright-Task: demo/1"
# Run from a directory holding a single numerically-named file: if the '*' were
# pathname-expanded it would glob to '9' and fabricate a dependency on a
# (non-existent, non-completed) task 9, leaving task 2 blocked with no malformed
# record. With expansion disabled the '*' stays literal → refused → task 2 ready.
gcwd="$tmp/depglob-cwd"
mkdir -p "$gcwd"
: >"$gcwd/9"
gout=$(cd "$gcwd" && "$STATE" "$gspec") || fail "dep-glob: engine exited non-zero"
assert_state "$gout" 2 ready "dep-glob: '*' is literal (no pathname expansion) → no phantom dep → ready"
has_record "$gout" malformed-deps 2 \
  || fail "dep-glob: a literal glob metacharacter was not surfaced as malformed"
echo "ok: dependency tokenization does not pathname-expand glob metacharacters"

# ---------------------------------------------------------------------------
# 6j. decimal task ids — the task-id grammar is `^[0-9]+(\.[0-9]+)?$`, so a
#     subtask id like 1.1 must parse, derive, and resolve dependencies exactly
#     as an integer id does (decimal/subtask ids are a first-class dispatch
#     convention this shared engine must not silently regress). Also asserts the
#     evidence column, not just the state.
# ---------------------------------------------------------------------------
xrepo="$tmp/decimal"
xspec="$xrepo/specs/demo"
mkdir -p "$xspec"
gitc_init "$xrepo"
cat >"$xspec/tasks.md" <<'EOF'
# Demo — Tasks
## Forward plan
### Task 1.1 — completed via trailer
- **Dependencies:** none
### Task 1.2 — depends on the decimal id 1.1
- **Dependencies:** 1.1
EOF
gitc "$xrepo" add -A
gitc "$xrepo" commit -q -m "base" -m "Planwright-Task: demo/1.1"
xout=$("$STATE" "$xspec") || fail "decimal-id: engine exited non-zero"
assert_state "$xout" 1.1 completed "decimal-id: 1.1 completes via its trailer"
assert_evidence "$xout" 1.1 trailer "decimal-id: 1.1 completion evidence is the trailer"
assert_state "$xout" 1.2 ready "decimal-id: 1.2's decimal dependency 1.1 is met → ready"
assert_evidence "$xout" 1.2 deps-met "decimal-id: 1.2 evidence is deps-met"
echo "ok: decimal task ids parse, derive, and resolve decimal dependencies"

# ---------------------------------------------------------------------------
# 6k. contradiction via BRANCH-MERGED evidence (not only the trailer arm) — a
#     task branch merge-reachable into base while gh still reports its PR OPEN
#     derives completed (git wins) AND surfaces the contradiction. Test 3 covers
#     the trailer arm; this covers the other half of the
#     `{ br_merged || trailer_done } && pr_open` condition.
# ---------------------------------------------------------------------------
brepo="$tmp/branchcontra"
bspec="$brepo/specs/demo"
mkdir -p "$bspec"
gitc_init "$brepo"
cat >"$bspec/tasks.md" <<'EOF'
# Demo — Tasks
## Forward plan
### Task 1 — merged branch, PR still open
- **Dependencies:** none
EOF
gitc "$brepo" add -A
gitc "$brepo" commit -q -m "base"
gitc "$brepo" remote add origin https://example.invalid/demo.git
gitc "$brepo" checkout -q -b planwright/demo/task-1
gitc "$brepo" commit -q --allow-empty -m "task 1 work"
gitc "$brepo" checkout -q main
gitc "$brepo" merge -q --no-ff -m "merge task 1" planwright/demo/task-1
bstub="$tmp/binbranchcontra"
make_gh_stub "$bstub" "planwright/demo/task-1${TAB}OPEN"
bout=$(PATH="$bstub:$PATH" "$STATE" "$bspec")
assert_state "$bout" 1 completed "branch-contra: merged branch → completed (git wins)"
assert_evidence "$bout" 1 branch-merged "branch-contra: completion evidence is branch-merged"
has_record "$bout" contradiction 1 \
  || fail "branch-contra: merged-branch-vs-open-PR contradiction not surfaced"
echo "ok: branch-merged completion vs open PR surfaces a contradiction"

# ---------------------------------------------------------------------------
# 6n. a zero-commit dispatch branch that fell BEHIND base is not completion
#     evidence. Section 6b covers a zero-commit branch whose tip sits exactly at
#     base; this covers the case the br_merged heuristic missed — the branch was
#     forked at an older base and never advanced, then base moved forward, so its
#     tip became "strictly behind base" (an ancestor of base, != base) and looked
#     like merged work even though nothing was ever committed or merged. It must
#     derive ready (no marker) / in-progress (fresh marker), never completed.
# ---------------------------------------------------------------------------
yrepo="$tmp/zerobehind"
yspec="$yrepo/specs/demo"
mkdir -p "$yspec"
gitc_init "$yrepo"
cat >"$yspec/tasks.md" <<'EOF'
# Demo — Tasks
## Forward plan
### Task 1 — zero-commit branch forked at an older base, no marker
- **Dependencies:** none
### Task 2 — zero-commit branch forked at an older base, fresh marker
- **Dependencies:** none
EOF
gitc "$yrepo" add -A
gitc "$yrepo" commit -q -m "B0 base"
gitc "$yrepo" branch planwright/demo/task-1 # forked at B0, zero commits
gitc "$yrepo" branch planwright/demo/task-2
gitc "$yrepo" commit -q --allow-empty -m "B1 — base advances past the forks"
ymdir="$yspec/.orchestrate/markers"
mkdir -p "$ymdir"
date +%s >"$ymdir/2" # a fresh marker on task 2 only
yout=$("$STATE" "$yspec") || fail "zero-behind: engine exited non-zero"
assert_state "$yout" 1 ready "zero-behind: forked-at-older-base + no marker → ready (not completed)"
assert_state "$yout" 2 in-progress "zero-behind: forked-at-older-base + fresh marker → in-progress (not completed)"
echo "ok: a zero-commit dispatch branch that fell behind base is not completion evidence"

# ---------------------------------------------------------------------------
# 6l. fail-closed on a non-resolving base ref — a PLANWRIGHT_BASE_REF that passes
#     the charset gate (a typo'd ref, a deleted branch) but does NOT resolve to a
#     commit must exit 2, not continue. Otherwise every later rev-list/rev-parse
#     degrades silently to ahead=0/empty and a genuinely merged task mis-derives
#     as ready instead of completed. Section 6d covers the option-injection arm of
#     base-ref validation; this covers the non-existent-ref arm.
rc=0
berr="$tmp/baseref.err"
PLANWRIGHT_BASE_REF="no-such-ref-xyz" "$STATE" "$mspec" >/dev/null 2>"$berr" || rc=$?
[ "$rc" = 2 ] || fail "base ref resolve: exit $rc, expected 2 for a non-resolving base ref"
grep -q "does not resolve to a commit" "$berr" \
  || fail "base ref resolve: exit 2 surfaced without the resolution-failure reason"
echo "ok: a non-resolving PLANWRIGHT_BASE_REF fails closed (exit 2)"

# ---------------------------------------------------------------------------
# 6m. the gh PR probe must not silently truncate — `gh pr list` defaults to a
#     single page (30). On a repo with more PRs than the page size, a task whose
#     PR sits beyond the page would have its OPEN/MERGED evidence invisible and
#     its state mis-derived. The engine must pass an explicit high --limit; assert
#     the flag actually reaches gh (a recording stub logs its argv).
arepo="$tmp/ghlimit"
aspec="$arepo/specs/demo"
mkdir -p "$aspec"
gitc_init "$arepo"
cat >"$aspec/tasks.md" <<'EOF'
# Demo — Tasks
## Forward plan
### Task 1 — evidence comes only from gh (merged PR)
- **Dependencies:** none
EOF
gitc "$arepo" add -A
gitc "$arepo" commit -q -m "base"
gitc "$arepo" remote add origin https://example.invalid/demo.git
# A recording gh stub: append its args to a log, then emit the canned TSV line.
astub="$tmp/binghlimit"
mkdir -p "$astub"
alog="$tmp/ghlimit.args"
{
  echo '#!/bin/sh'
  printf 'printf "%%s\\n" "$*" >>"%s"\n' "$alog"
  echo 'cat <<STUB'
  printf 'planwright/demo/task-1%sMERGED\n' "$TAB"
  echo 'STUB'
} >"$astub/gh"
chmod +x "$astub/gh"
aout=$(PATH="$astub:$PATH" "$STATE" "$aspec") || fail "gh-limit: engine exited non-zero"
assert_state "$aout" 1 completed "gh-limit: gh MERGED evidence still derives completed"
grep -q -- '--limit' "$alog" \
  || fail "gh-limit: engine called gh pr list without an explicit --limit (default-page truncation risk)"
echo "ok: the gh PR probe passes an explicit --limit (no default-page truncation)"

# ---------------------------------------------------------------------------
# 6o. squash/rebase-merge RELOCATED trailer — a squash merge concatenates the
#     constituent commits' messages, so a Planwright-Task trailer that was a
#     proper footer on its original commit lands MID-BODY in the squashed
#     message (content follows it). git's %(trailers) parses only the last
#     paragraph, so it misses a relocated trailer; the engine must scan the
#     whole message (%B) and still derive completion — regardless of how the PR
#     was merged or what the branch was named. Regression guard for the
#     footer-only read that failed grammar-backed-explain Task 1 in paycalc-
#     services (PR squash-merged from a non-convention branch: the gh head-ref
#     mapping found no match AND the trailer was mid-body → task mis-derived).
# ---------------------------------------------------------------------------
srepo="$tmp/squashtrailer"
sspec="$srepo/specs/demo"
mkdir -p "$sspec"
gitc_init "$srepo"
cat >"$sspec/tasks.md" <<'EOF'
# Demo — Tasks
## Forward plan
### Task 1 — completed via a trailer the squash pushed mid-body
- **Dependencies:** none
### Task 2 — depends on task 1
- **Dependencies:** 1
EOF
gitc "$srepo" add -A
gitc "$srepo" commit -q -m "base"
# A squash-style message: subject, then the trailer, then MORE body after it, so
# the trailer is no longer in the last paragraph (where %(trailers) looks). No
# task branch and no remote — the trailer is the only completion anchor, exactly
# the paycalc-services shape.
gitc "$srepo" commit -q --allow-empty \
  -m "squashed: task 1 work (STEAI-834)" \
  -m "Planwright-Task: demo/1" \
  -m "trailing body paragraph the squash appended after the trailer"
# Sanity-check the fixture actually reproduces the bug: footer-only parsing must
# NOT see the relocated trailer (otherwise the test would pass on the old code).
footer_only=$(gitc "$srepo" log HEAD --format='%(trailers:key=Planwright-Task,valueonly)')
[ -z "$footer_only" ] \
  || fail "squash-trailer: fixture invalid — %(trailers) already sees the relocated trailer"
sout=$("$STATE" "$sspec") || fail "squash-trailer: engine exited non-zero"
assert_state "$sout" 1 completed "squash-trailer: relocated mid-body trailer still derives completed"
assert_evidence "$sout" 1 trailer "squash-trailer: completion evidence is the trailer"
assert_state "$sout" 2 ready "squash-trailer: dependent task 1 is met → task 2 ready (not re-dispatched)"
echo "ok: a squash-relocated mid-body trailer is recognized (whole-message scan)"

# ---------------------------------------------------------------------------
# 6p. case-insensitive trailer key — git's own trailer parser treats keys
#     case-insensitively, so %(trailers:key=Planwright-Task) matched a
#     lowercased `planwright-task:` footer. The whole-message scan must preserve
#     that (an awk tolower() match, not a case-sensitive `sed '^Planwright-Task:'`)
#     so switching the reader does not silently narrow what completes. Guards the
#     case-sensitivity regression the panel review reproduced.
# ---------------------------------------------------------------------------
crepo2="$tmp/casekey"
cspec2="$crepo2/specs/demo"
mkdir -p "$cspec2"
gitc_init "$crepo2"
cat >"$cspec2/tasks.md" <<'EOF'
# Demo — Tasks
## Forward plan
### Task 1 — completed via a lowercased trailer key
- **Dependencies:** none
EOF
gitc "$crepo2" add -A
gitc "$crepo2" commit -q -m "base"
# A lowercased key in footer position — git's %(trailers) would have matched it.
gitc "$crepo2" commit -q --allow-empty -m "task 1 work" -m "planwright-task: demo/1"
cout2=$("$STATE" "$cspec2") || fail "case-key: engine exited non-zero"
assert_state "$cout2" 1 completed "case-key: lowercased planwright-task: still completes (git parity)"
assert_evidence "$cout2" 1 trailer "case-key: completion evidence is the trailer"
echo "ok: a case-variant trailer key is recognized (git-parity, no regression)"

# ---------------------------------------------------------------------------
# 6q. dependency trailing-period tolerance — a prose dependency list commonly
#     ends its final entry with a period ("...Task 13."). On a MULTI-dependency
#     line an earlier token still yields a valid id, so the task keeps a real
#     dependency; but on a SINGLE-dependency line the only id carries the period,
#     fails the id grammar, is dropped, and the line silently parses to zero deps
#     — so the task resolves ready and is dispatched BEFORE its prerequisite is
#     complete. The engine must strip a trailing period so the id is recognized.
#     A dotted id (n.m) ends in a digit, so the strip only ever removes sentence
#     punctuation. Regression guard for the single-dependency fail-open reported
#     against grammar-backed-explain (Task 14 dep "Task 13.", Task 15 dep "Task 3.").
# ---------------------------------------------------------------------------
prepo="$tmp/depperiod"
pspec="$prepo/specs/demo"
mkdir -p "$pspec"
gitc_init "$prepo"
cat >"$pspec/tasks.md" <<'EOF'
# Demo — Tasks
## Forward plan
### Task 1 — prerequisite, not complete
- **Dependencies:** none
### Task 14 — single prose dependency ending in a period
- **Dependencies:** Task 1.
### Task 15 — single bare id ending in a period
- **Dependencies:** 1.
### Task 19 — dotted id ending in a period (the period must not eat the id)
- **Dependencies:** 1.2.
EOF
gitc "$prepo" add -A
gitc "$prepo" commit -q -m "base"
pout=$("$STATE" "$pspec") || fail "dep-period: engine exited non-zero"
# Task 1 is not complete, so anything depending on it must be blocked, never ready.
assert_state "$pout" 1 ready "dep-period: prerequisite with no deps is ready"
assert_state "$pout" 14 blocked "dep-period: single prose dep 'Task 1.' → dep 1 recognized → blocked (not ready)"
assert_evidence "$pout" 14 deps-unmet "dep-period: task 14 is blocked on its real, unmet dependency"
assert_state "$pout" 15 blocked "dep-period: single bare id '1.' → dep 1 recognized → blocked (not ready)"
# The bare-id-with-period case is now clean (no stray prose), so it must NOT be
# flagged as malformed — the period alone is not a grammar violation.
has_record "$pout" malformed-deps 15 \
  && fail "dep-period: a bare id with a trailing period was wrongly flagged malformed"
assert_state "$pout" 19 blocked "dep-period: dotted id '1.2.' keeps id 1.2 (period stripped, digit preserved) → blocked on unmet 1.2"
echo "ok: a trailing period on a single-dependency line no longer fails open (id recognized)"

# ---------------------------------------------------------------------------
# 7. fail-closed on a missing / taskless bundle (matches the sibling scripts).
# ---------------------------------------------------------------------------
rc=0
"$STATE" "$tmp/does-not-exist" >/dev/null 2>&1 || rc=$?
[ "$rc" = 2 ] || fail "missing spec dir: exit $rc, expected 2"
echo "ok: fails closed (exit 2) on a missing spec dir"

echo "PASS: test-orchestrate-state.sh"
