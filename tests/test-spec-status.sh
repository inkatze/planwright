#!/bin/bash
# Tests for scripts/spec-status.sh — the derived status render (invariant-tasks
# Task 3; D-3, D-4, D-6, D-12; REQ-B1.1–REQ-B1.6, REQ-C1.8, REQ-C1.9).
#
# Contract under test:
#   - the render surfaces the derivation engine (orchestrate-state.sh) as the
#     canonical human status read surface: per-task execution status plus the
#     bundle's effective status (Active/Done), derived from evidence, never
#     committed (REQ-B1.1); the merged-PR case renders the PR number and merge
#     date; the render writes no file;
#   - no remote is first-class: the render degrades per the engine's evidence
#     fallback and exits 0 (REQ-B1.2), while a configured-but-FAILING remote is
#     a distinct fail-closed mode (pinned exit 3): the failure is reported, no
#     partial evidence is presented as status, and only the locally-determinable
#     facts (stored header, reference-bullet parked state) are reported, marked
#     as the only facts available (REQ-B1.5);
#   - a live reference bullet (v2) is authoritative for its task over git
#     evidence — awaiting-input / deferred / out-of-scope — and a bullet on a
#     task whose evidence derives completed is flagged as a stale-bullet
#     anomaly (REQ-B1.4);
#   - derived bundle status is computed only for stored-Ready bundles; Draft /
#     Retired / Superseded render their stored state with no execution claim; a
#     zero-task bundle reports it has no tasks and never derives Done; a live
#     Awaiting-input bullet blocks Done; Deferred / Out-of-scope-parked tasks
#     are excluded from the Done universe rather than blocking it (REQ-B1.6);
#   - a missing or unparseable Format-version: fails closed (exit 2, error
#     reported, no v1 fallback) (REQ-C1.8);
#   - every echoed untrusted value (bullet text, header values, engine-stream
#     fields, remote error text) is sanitized; a reference bullet whose task id
#     violates the task-id grammar is rejected, not used (REQ-C1.9).
#
# Runs standalone under /bin/bash (the bash 3.2 floor).
set -eu
LC_ALL=C
export LC_ALL
unset CDPATH

here=$(cd "$(dirname "$0")" && pwd)
RENDER="$here/../scripts/spec-status.sh"
TAB=$(printf '\t')
ESC=$(printf '\033')

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

[ -x "$RENDER" ] || fail "scripts/spec-status.sh missing or not executable"

# git with a deterministic, signing-free identity.
gitc() {
  repo="$1"
  shift
  git -C "$repo" -c user.name=test -c user.email=test@example.invalid \
    -c commit.gpgsign=false -c init.defaultBranch=main "$@"
}
gitc_init() { git -C "$1" -c init.defaultBranch=main init -q; }

# assert_has <output> <substring> <label>
assert_has() {
  case "$1" in
    *"$2"*) ;;
    *) fail "$3: output lacks '$2'" ;;
  esac
}

# assert_not <output> <substring> <label>
assert_not() {
  case "$1" in
    *"$2"*) fail "$3: output unexpectedly contains '$2'" ;;
  esac
}

# task_line <output> <id> — the render's per-task line for one id (the line
# beginning "task <id> "), so state assertions cannot match another task's.
task_line() {
  printf '%s\n' "$1" | awk -v id="$2" '$1 == "task" && $2 == id { print; exit }'
}

# A gh stub printing canned 4-column TSV rows (headRefName, state, number,
# mergedAt), mirroring the engine's --jq render so no system jq is needed.
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
  printf '#!/bin/sh\necho "gh: simulated outage" >&2\nexit 1\n' >"$dir/gh"
  chmod +x "$dir/gh"
}

# write_v2_spec <spec-dir> <stored-status> — a minimal v2 bundle: the
# requirements.md header (the authoritative Status home) plus a v2 tasks.md
# (single ## Tasks section, pointer line, human-payload sections).
write_v2_spec() {
  dir="$1"
  status="$2"
  mkdir -p "$dir"
  cat >"$dir/requirements.md" <<EOF
# Demo — Requirements

**Status:** $status
**Last reviewed:** 2026-07-15
**Format-version:** 2
**Execution:** derived — see the status render

## Goal

Fixture.
EOF
  cat >"$dir/tasks.md" <<EOF
# Demo — Tasks

**Status:** $status
**Last reviewed:** 2026-07-15
**Format-version:** 2
**Execution:** derived — see the status render

## Tasks

### Task 1 — merged branch
- **Dependencies:** none

### Task 2 — trailer completion
- **Dependencies:** none

### Task 3 — merged PR
- **Dependencies:** none

### Task 4 — in-flight branch + open PR
- **Dependencies:** none

### Task 5 — fresh marker only
- **Dependencies:** none

### Task 6 — no evidence, deps met
- **Dependencies:** 1

### Task 7 — no evidence, deps unmet
- **Dependencies:** 4

### Task 8 — open PR only (no local branch)
- **Dependencies:** none

## Awaiting input

(none yet)

## Deferred

(none yet)

## Out of scope

(none yet)
EOF
}

# Seed the evidence matrix into a repo holding specs/demo: task 1 merged
# branch, task 2 trailer, task 4 in-flight branch, task 5 fresh marker.
seed_evidence() {
  repo="$1"
  spec="$repo/specs/demo"
  gitc "$repo" add -A
  gitc "$repo" commit -q -m "base: spec bundle"
  gitc "$repo" checkout -q -b planwright/demo/task-1
  gitc "$repo" commit -q --allow-empty -m "task 1 work"
  gitc "$repo" checkout -q main
  gitc "$repo" merge -q --no-ff -m "merge task 1" planwright/demo/task-1
  gitc "$repo" commit -q --allow-empty -m "task 2 work" -m "Planwright-Task: demo/2"
  gitc "$repo" checkout -q -b planwright/demo/task-4
  gitc "$repo" commit -q --allow-empty -m "task 4 wip"
  gitc "$repo" checkout -q main
  mkdir -p "$spec/.orchestrate/markers"
  date +%s >"$spec/.orchestrate/markers/5"
}

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# ---------------------------------------------------------------------------
# 1. REQ-B1.1 — the evidence matrix renders per-task states, the merged-PR
#    task carries its PR number and merge date, and the bundle derives Active.
# ---------------------------------------------------------------------------
repo="$tmp/matrix"
spec="$repo/specs/demo"
mkdir -p "$repo"
gitc_init "$repo"
write_v2_spec "$spec" Ready
seed_evidence "$repo"
gitc "$repo" remote add origin https://example.invalid/demo.git
stub="$tmp/binmatrix"
make_gh_stub "$stub" \
  "planwright/demo/task-1${TAB}OPEN${TAB}41${TAB}" \
  "planwright/demo/task-3${TAB}MERGED${TAB}42${TAB}2026-07-01T10:00:00Z" \
  "planwright/demo/task-4${TAB}OPEN${TAB}43${TAB}" \
  "planwright/demo/task-8${TAB}OPEN${TAB}44${TAB}"

out=$(PATH="$stub:$PATH" "$RENDER" "$spec") || fail "B1.1: render exited non-zero"
assert_has "$(task_line "$out" 1)" completed "B1.1 merged-branch"
assert_has "$(task_line "$out" 2)" completed "B1.1 trailer"
assert_has "$(task_line "$out" 3)" completed "B1.1 merged-PR"
assert_has "$(task_line "$out" 3)" "PR #42" "B1.1 merged-PR renders the PR number"
assert_has "$(task_line "$out" 3)" 2026-07-01 "B1.1 merged-PR renders the merge date"
assert_has "$(task_line "$out" 4)" in-progress "B1.1 in-flight branch"
assert_has "$(task_line "$out" 5)" in-progress "B1.1 fresh marker"
assert_has "$(task_line "$out" 6)" ready "B1.1 deps met"
assert_has "$(task_line "$out" 7)" blocked "B1.1 deps unmet"
# Task 8's ONLY evidence is the gh OPEN row (no local branch, no marker), so
# this pins the pr-open engine arm rather than riding the branch-commits one.
assert_has "$(task_line "$out" 8)" in-progress "B1.1 open-PR-only task derives in-progress"
assert_has "$(task_line "$out" 8)" pr-open "B1.1 open-PR-only evidence is the PR itself"
# Task 1 is branch-merged while its stubbed PR still reads OPEN: the engine's
# contradiction record must surface as a rendered note, not vanish.
assert_has "$out" "note: task 1" "B1.1 contradiction record renders as a note"
assert_has "$out" "bundle status: Active (derived)" "B1.1 bundle derives Active"
echo "ok: REQ-B1.1 evidence matrix renders per-task and bundle status"

# ---------------------------------------------------------------------------
# 2. REQ-B1.1 — the render writes nothing: the spec dir is byte-identical
#    before and after, and the git working tree stays clean.
# ---------------------------------------------------------------------------
before=$(find "$spec" -type f -exec cat {} + | cksum)
dirty_before=$(gitc "$repo" status --porcelain -- specs/)
out=$(PATH="$stub:$PATH" "$RENDER" "$spec") || fail "read-only: render exited non-zero"
after=$(find "$spec" -type f -exec cat {} + | cksum)
[ "$before" = "$after" ] || fail "read-only: render modified the spec dir"
dirty_after=$(gitc "$repo" status --porcelain -- specs/)
[ "$dirty_before" = "$dirty_after" ] \
  || fail "read-only: render changed the working tree: $dirty_after"
echo "ok: REQ-B1.1 render writes no file"

# ---------------------------------------------------------------------------
# 3. REQ-B1.2 — no remote configured is first-class: full render, exit 0,
#    no failure report.
# ---------------------------------------------------------------------------
repo2="$tmp/noremote"
spec2="$repo2/specs/demo"
mkdir -p "$repo2"
gitc_init "$repo2"
write_v2_spec "$spec2" Ready
seed_evidence "$repo2"

out=$("$RENDER" "$spec2") || fail "B1.2: no-remote render exited non-zero"
assert_has "$(task_line "$out" 1)" completed "B1.2 branch evidence derives with no remote"
assert_has "$(task_line "$out" 2)" completed "B1.2 trailer evidence derives with no remote"
assert_has "$out" "bundle status: Active (derived)" "B1.2 bundle derives with no remote"
assert_not "$out" "evidence failure" "B1.2 no-remote is not a failure mode"
echo "ok: REQ-B1.2 no-remote mode renders full status, exit 0"

# ---------------------------------------------------------------------------
# 4. REQ-B1.5 — a configured-but-failing remote fails closed: pinned exit 3,
#    the failure is reported, per-task evidence is NOT presented as status,
#    and locally-determinable facts (stored header, parked bullets) are still
#    reported, marked as the only facts available.
# ---------------------------------------------------------------------------
repo3="$tmp/outage"
spec3="$repo3/specs/demo"
mkdir -p "$repo3"
gitc_init "$repo3"
write_v2_spec "$spec3" Ready
awk '/^\(none yet\)$/ && !done { sub(/.*/, "- **Task 7** why is this blocked?"); done=1 } { print }' \
  "$spec3/tasks.md" >"$spec3/tasks.md.new" && mv "$spec3/tasks.md.new" "$spec3/tasks.md"
seed_evidence "$repo3"
gitc "$repo3" add -A
gitc "$repo3" commit -q -m "park task 7"
gitc "$repo3" remote add origin https://example.invalid/demo.git
failstub="$tmp/binfail"
make_failing_gh_stub "$failstub"

set +e
out=$(PATH="$failstub:$PATH" "$RENDER" "$spec3" 2>&1)
rc=$?
set -e
[ "$rc" -eq 3 ] || fail "B1.5: expected pinned exit 3 on transient failure, got $rc"
assert_has "$out" "evidence failure" "B1.5 failure is reported"
assert_not "$(task_line "$out" 1)" completed "B1.5 no partial evidence presented as status"
assert_has "$out" "stored status: Ready" "B1.5 stored header still reported"
assert_has "$out" "awaiting-input" "B1.5 bullet-parked state still reported"
assert_has "$out" "only facts available" "B1.5 local facts marked as the only ones"
echo "ok: REQ-B1.5 transient evidence failure fails closed (exit 3, local facts only)"

# ---------------------------------------------------------------------------
# 5. REQ-B1.4 — reference-bullet authority: a completed-evidence task parked
#    by an Awaiting-input bullet derives awaiting-input (flagged as a
#    stale-bullet anomaly); Deferred and Out-of-scope bullets park the same
#    way; removing the bullet restores evidence-derived status.
# ---------------------------------------------------------------------------
repo4="$tmp/bullets"
spec4="$repo4/specs/demo"
mkdir -p "$repo4"
gitc_init "$repo4"
write_v2_spec "$spec4" Ready
awk '
  /^\(none yet\)$/ && aw == 0 { print "- **Task 1** confirm the rollout order"; aw = 1; next }
  /^\(none yet\)$/ && aw == 1 && df == 0 { print "- **Task 6** gated on the Q3 window"; df = 1; next }
  /^\(none yet\)$/ && df == 1 && os == 0 { print "- **Task 7** cut from this phase"; os = 1; next }
  { print }
' "$spec4/tasks.md" >"$spec4/tasks.md.new" && mv "$spec4/tasks.md.new" "$spec4/tasks.md"
seed_evidence "$repo4"
gitc "$repo4" add -A
gitc "$repo4" commit -q -m "park tasks"

out=$("$RENDER" "$spec4") || fail "B1.4: render exited non-zero"
assert_has "$(task_line "$out" 1)" awaiting-input "B1.4 bullet overrides completed evidence"
assert_not "$(task_line "$out" 1)" completed "B1.4 parked task does not read completed"
assert_has "$out" "anomaly" "B1.4 stale bullet on a completed task is flagged"
assert_has "$(task_line "$out" 6)" deferred "B1.4 Deferred bullet parks its task"
assert_has "$(task_line "$out" 7)" out-of-scope "B1.4 Out-of-scope bullet parks its task"

# Unpark task 1: evidence-derived status returns, the anomaly clears.
awk '!/^- \*\*Task 1\*\*/' "$spec4/tasks.md" >"$spec4/tasks.md.new" \
  && mv "$spec4/tasks.md.new" "$spec4/tasks.md"
out=$("$RENDER" "$spec4") || fail "B1.4: render exited non-zero after unpark"
assert_has "$(task_line "$out" 1)" completed "B1.4 unparking restores evidence-derived status"
assert_not "$out" "anomaly" "B1.4 anomaly clears with the bullet"
echo "ok: REQ-B1.4 reference bullets are authoritative; stale bullet flagged"

# ---------------------------------------------------------------------------
# 6. REQ-B1.6 — bundle determination rules: a live Awaiting-input bullet
#    blocks Done; a Deferred-parked task is excluded from the Done universe
#    rather than blocking it.
# ---------------------------------------------------------------------------
repo5="$tmp/done"
spec5="$repo5/specs/demo"
mkdir -p "$repo5"
gitc_init "$repo5"
mkdir -p "$spec5"
cat >"$spec5/requirements.md" <<'EOF'
# Demo — Requirements

**Status:** Ready
**Last reviewed:** 2026-07-15
**Format-version:** 2
**Execution:** derived — see the status render
EOF
cat >"$spec5/tasks.md" <<'EOF'
# Demo — Tasks

**Status:** Ready
**Last reviewed:** 2026-07-15
**Format-version:** 2
**Execution:** derived — see the status render

## Tasks

### Task 1 — done work
- **Dependencies:** none

### Task 2 — parked question
- **Dependencies:** none

## Awaiting input

- **Task 2** confirm the contract shape

## Deferred

(none yet)

## Out of scope

(none yet)
EOF
gitc "$repo5" add -A
gitc "$repo5" commit -q -m "base"
gitc "$repo5" commit -q --allow-empty -m "task 1 work" -m "Planwright-Task: demo/1"
gitc "$repo5" commit -q --allow-empty -m "task 2 work" -m "Planwright-Task: demo/2"

out=$("$RENDER" "$spec5") || fail "B1.6: render exited non-zero"
assert_not "$out" "bundle status: Done" "B1.6 live Awaiting-input bullet blocks Done"

# Re-park task 2 under Deferred instead: excluded from the Done universe, so
# the bundle now derives Done.
awk '
  /^- \*\*Task 2\*\* confirm/ { next }
  /^## Awaiting input$/ { print; print ""; print "(none yet)"; skip = 1; next }
  skip && /^$/ { skip = 0; next }
  /^\(none yet\)$/ && deferred == 0 && seen_def { print "- **Task 2** gated on the contract decision"; deferred = 1; next }
  /^## Deferred$/ { seen_def = 1 }
  { print }
' "$spec5/tasks.md" >"$spec5/tasks.md.new" && mv "$spec5/tasks.md.new" "$spec5/tasks.md"
out=$("$RENDER" "$spec5") || fail "B1.6: render exited non-zero (deferred variant)"
assert_has "$out" "bundle status: Done (derived)" "B1.6 Deferred-parked task excluded, not blocking"
echo "ok: REQ-B1.6 Awaiting-input blocks Done; Deferred-parked is excluded"

# ---------------------------------------------------------------------------
# 7. REQ-B1.6 — stored-status gating: Draft / Retired / Superseded render the
#    stored state with no execution claim; a zero-task bundle reports it has
#    no tasks and never derives Done.
# ---------------------------------------------------------------------------
for st in Draft Retired Superseded; do
  repo6="$tmp/gate$st"
  spec6="$repo6/specs/demo"
  mkdir -p "$repo6"
  gitc_init "$repo6"
  write_v2_spec "$spec6" "$st"
  seed_evidence "$repo6"
  out=$("$RENDER" "$spec6") || fail "B1.6: stored-$st render exited non-zero"
  assert_has "$out" "stored status: $st" "B1.6 stored $st is rendered"
  assert_has "$out" "no execution claim" "B1.6 stored $st makes no execution claim"
  [ -z "$(task_line "$out" 1)" ] || fail "B1.6 stored $st: unexpected per-task status"
  assert_not "$out" "bundle status:" "B1.6 stored $st derives no bundle status"
done
echo "ok: REQ-B1.6 stored Draft/Retired/Superseded render stored state only"

repo7="$tmp/zerotask"
spec7="$repo7/specs/demo"
mkdir -p "$repo7"
gitc_init "$repo7"
write_v2_spec "$spec7" Ready
awk '/^## Tasks$/ { print; print ""; skip = 1; next }
     /^## Awaiting input$/ { skip = 0 }
     skip { next }
     { print }' "$spec7/tasks.md" >"$spec7/tasks.md.new" \
  && mv "$spec7/tasks.md.new" "$spec7/tasks.md"
gitc "$repo7" add -A
gitc "$repo7" commit -q -m "base"
out=$("$RENDER" "$spec7") || fail "B1.6: zero-task render exited non-zero"
assert_has "$out" "no tasks" "B1.6 zero-task bundle reports no tasks"
assert_not "$out" "bundle status: Done" "B1.6 zero-task bundle never derives Done"
echo "ok: REQ-B1.6 zero-task bundle reports no tasks, never Done"

# ---------------------------------------------------------------------------
# 8. REQ-C1.8 — a missing or unparseable Format-version: fails closed: exit 2,
#    an error naming the line, no render output.
# ---------------------------------------------------------------------------
repo8="$tmp/nover"
spec8="$repo8/specs/demo"
mkdir -p "$repo8"
gitc_init "$repo8"
write_v2_spec "$spec8" Ready
grep -v '^\*\*Format-version:\*\*' "$spec8/tasks.md" >"$spec8/tasks.md.new" \
  && mv "$spec8/tasks.md.new" "$spec8/tasks.md"
gitc "$repo8" add -A
gitc "$repo8" commit -q -m "base"
set +e
out=$("$RENDER" "$spec8" 2>&1)
rc=$?
set -e
[ "$rc" -eq 2 ] || fail "C1.8: missing Format-version should exit 2, got $rc"
assert_has "$out" "Format-version" "C1.8 missing version names the line"
assert_not "$out" "stored status:" "C1.8 missing version renders nothing"
assert_not "$out" "bundle status:" "C1.8 missing version derives nothing"

write_v2_spec "$spec8" Ready
sed 's/^\*\*Format-version:\*\* 2$/**Format-version:** banana/' "$spec8/tasks.md" \
  >"$spec8/tasks.md.new" && mv "$spec8/tasks.md.new" "$spec8/tasks.md"
set +e
out=$("$RENDER" "$spec8" 2>&1)
rc=$?
set -e
[ "$rc" -eq 2 ] || fail "C1.8: unparseable Format-version should exit 2, got $rc"
assert_has "$out" "Format-version" "C1.8 unparseable version names the line"
assert_not "$out" "stored status:" "C1.8 unparseable version renders nothing"
assert_not "$out" "bundle status:" "C1.8 unparseable version derives nothing"
echo "ok: REQ-C1.8 missing/unparseable Format-version fails closed (exit 2)"

# ---------------------------------------------------------------------------
# 9. REQ-C1.9 — echo sanitization: terminal-escape bytes embedded in bullet
#    text, header values, and engine-stream fields (a hostile trailer value, a
#    malformed Dependencies line) never reach the output; a reference bullet
#    whose task id violates the task-id grammar is rejected, not used.
# ---------------------------------------------------------------------------
repo9="$tmp/hostile"
spec9="$repo9/specs/demo"
mkdir -p "$repo9"
gitc_init "$repo9"
write_v2_spec "$spec9" Ready
awk -v esc="$ESC" '
  /^\(none yet\)$/ && aw == 0 { print "- **Task 1** " esc "[31mhostile bullet" esc "[0m text"; aw = 1; next }
  { print }
' "$spec9/tasks.md" >"$spec9/tasks.md.new" && mv "$spec9/tasks.md.new" "$spec9/tasks.md"
# A malformed Dependencies token and a hostile trailer value ride the engine
# stream into the render.
sed 's/^- \*\*Dependencies:\*\* 4$/- **Dependencies:** 4 see-note/' "$spec9/tasks.md" \
  >"$spec9/tasks.md.new" && mv "$spec9/tasks.md.new" "$spec9/tasks.md"
gitc "$repo9" add -A
gitc "$repo9" commit -q -m "base"
gitc "$repo9" commit -q --allow-empty -m "hostile" -m "Planwright-Task: demo/${ESC}[31mevil"

out=$("$RENDER" "$spec9" 2>&1) || fail "C1.9: render exited non-zero"
case "$out" in
  *"$ESC"*) fail "C1.9: an escape byte reached the render output" ;;
esac
# The anomaly records must render positively, not merely sanitized away.
assert_has "$out" "malformed Dependencies" "C1.9 malformed-deps record renders as a note"
assert_has "$out" "note: refused" "C1.9 refused-trailer record renders as a note"
echo "ok: REQ-C1.9 escape bytes in bullet text and stream fields are stripped"

repo10="$tmp/hostilehdr"
spec10="$repo10/specs/demo"
mkdir -p "$repo10"
gitc_init "$repo10"
write_v2_spec "$spec10" Ready
sed "s/^\*\*Status:\*\* Ready\$/**Status:** Re${ESC}[31mady/" "$spec10/requirements.md" \
  >"$spec10/requirements.md.new" && mv "$spec10/requirements.md.new" "$spec10/requirements.md"
gitc "$repo10" add -A
gitc "$repo10" commit -q -m "base"
set +e
out=$("$RENDER" "$spec10" 2>&1)
rc=$?
set -e
[ "$rc" -eq 0 ] && fail "C1.9: an unrecognized stored status should not render cleanly"
case "$out" in
  *"$ESC"*) fail "C1.9: an escape byte in the header value reached the output" ;;
esac
echo "ok: REQ-C1.9 escape bytes in header values are stripped"

repo11="$tmp/badid"
spec11="$repo11/specs/demo"
mkdir -p "$repo11"
gitc_init "$repo11"
write_v2_spec "$spec11" Ready
awk '
  /^\(none yet\)$/ && aw == 0 { print "- **Task 1x** grammar-violating id"; aw = 1; next }
  /^\(none yet\)$/ && aw == 1 && df == 0 { print "- **Task 42** names no task block"; df = 1; next }
  { print }
' "$spec11/tasks.md" >"$spec11/tasks.md.new" && mv "$spec11/tasks.md.new" "$spec11/tasks.md"
seed_evidence "$repo11"
gitc "$repo11" add -A
gitc "$repo11" commit -q -m "park with bad id"
out=$("$RENDER" "$spec11" 2>&1) || fail "C1.9: render exited non-zero on a bad bullet id"
assert_has "$out" "rejected" "C1.9 grammar-violating bullet id is rejected"
assert_has "$(task_line "$out" 1)" completed "C1.9 rejected bullet parks nothing"
assert_has "$out" "does not exist" "C1.9 unknown-id bullet is surfaced, not silently inert"
echo "ok: REQ-C1.9 grammar-violating bullet id is rejected, not used"

# ---------------------------------------------------------------------------
# 9b. Header-value robustness — a trailing Markdown hard-break (two spaces)
#     on the Status line and a CR-terminated Format-version line (a CRLF
#     checkout) are valid values, not parse failures.
# ---------------------------------------------------------------------------
repo11b="$tmp/trailing"
spec11b="$repo11b/specs/demo"
mkdir -p "$repo11b"
gitc_init "$repo11b"
write_v2_spec "$spec11b" Ready
sed 's/^\*\*Status:\*\* Ready$/**Status:** Ready  /' "$spec11b/requirements.md" \
  >"$spec11b/requirements.md.new" && mv "$spec11b/requirements.md.new" "$spec11b/requirements.md"
awk '{ if ($0 == "**Format-version:** 2") print $0 "\r"; else print }' "$spec11b/tasks.md" \
  >"$spec11b/tasks.md.new" && mv "$spec11b/tasks.md.new" "$spec11b/tasks.md"
gitc "$repo11b" add -A
gitc "$repo11b" commit -q -m "base"
out=$("$RENDER" "$spec11b") || fail "header robustness: trailing whitespace/CR rejected a valid bundle"
assert_has "$out" "stored status: Ready" "header robustness: trailing-space Status parses"
assert_has "$out" "format-version: 2" "header robustness: CR-terminated Format-version parses"
echo "ok: header values tolerate trailing whitespace and CR"

# ---------------------------------------------------------------------------
# 10. v1 coexistence — a v1 bundle still renders: stored Ready derives; a
#     stored Active (v1-only value) renders as stored, never as a derived
#     claim, with the per-task table still shown.
# ---------------------------------------------------------------------------
repo12="$tmp/v1"
spec12="$repo12/specs/demo"
mkdir -p "$spec12"
gitc_init "$repo12"
cat >"$spec12/requirements.md" <<'EOF'
# Demo — Requirements

**Status:** Active
**Last reviewed:** 2026-07-15
**Format-version:** 1
EOF
cat >"$spec12/tasks.md" <<'EOF'
# Demo — Tasks

**Status:** Active
**Last reviewed:** 2026-07-15
**Format-version:** 1

## Forward plan

### Task 2 — pending work
- **Dependencies:** 1

## In progress

(none yet)

## Awaiting input

(none yet)

## Completed

### Task 1 — done work
- **Dependencies:** none
- **Status:** Completed · merged 2026-07-14

## Deferred

(none yet)

## Out of scope

(none yet)
EOF
gitc "$repo12" add -A
gitc "$repo12" commit -q -m "base"
gitc "$repo12" commit -q --allow-empty -m "task 1 work" -m "Planwright-Task: demo/1"

out=$("$RENDER" "$spec12") || fail "v1: render exited non-zero"
assert_has "$out" "stored status: Active" "v1 stored Active is rendered as stored"
assert_not "$out" "bundle status:" "v1 stored Active derives no bundle status"
assert_has "$(task_line "$out" 1)" completed "v1 per-task derivation still renders"
assert_has "$(task_line "$out" 2)" ready "v1 pending task renders"
echo "ok: v1 bundle renders per-task status; stored Active stays stored"

# ---------------------------------------------------------------------------
# 11. The render is wired as a mise task.
# ---------------------------------------------------------------------------
grep -q '^\[tasks.status\]' "$here/../mise.toml" \
  || fail "mise wiring: no [tasks.status] task in mise.toml"
grep -q 'spec-status.sh' "$here/../mise.toml" \
  || fail "mise wiring: [tasks.status] does not invoke spec-status.sh"
echo "ok: render is wired as the mise status task"

echo "PASS: test-spec-status.sh"
