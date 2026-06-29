#!/bin/bash
# Tests for scripts/orchestrate-marker.sh — the runtime dispatch-marker WRITER,
# the dispatch-path counterpart to orchestrate-state.sh's marker READER
# (orchestration-concurrency Task 3; D-1, D-3; REQ-A1.1, REQ-A1.2, REQ-F1.1).
#
# Contract under test:
#   - `write <spec-dir> <id>...` drops a timestamped marker (the current epoch
#     seconds) per task id, so the task derives In progress from branch + marker
#     alone — the branch-create → first-commit window the marker covers (D-3,
#     REQ-A1.1). The marker is a discardable runtime artifact: writing it makes
#     NO git-tracked change (it is gitignored), so main carries no dispatch
#     commit and a worker worktree cut from it inherits nothing foreign
#     (REQ-A1.2 contamination isolation by construction).
#   - the writer resolves the SAME marker path the reader does
#     (${PLANWRIGHT_ORCH_STATE_DIR:-<spec-dir>/.orchestrate/markers}/<id>), so a
#     marker the writer drops is the marker the engine reads (round-trip).
#   - `clear <spec-dir> <id>...` removes the marker idempotently, reverting the
#     task to Ready (a clean no-op when the marker is already gone).
#   - REQ-F1.1: every task id is validated against the per-task id grammar
#     `^[0-9]+(\.[0-9]+)?$` BEFORE it is used to build a path; a malformed or
#     hostile id (traversal, glob, bad charset, the bundle-range form) is a clean
#     refusal (exit 2, nothing written), never an out-of-tree path. A symlink at
#     the marker path is refused, not followed. The derived marker path is
#     containment-checked under its base dir before any write.
#   - the write is atomic (write-temp-then-rename), so a reader never sees a torn
#     marker; the marker content is exactly one integer.
#
# Runs standalone under /bin/bash (the bash 3.2 floor).
set -eu
LC_ALL=C
export LC_ALL
unset CDPATH

here=$(cd "$(dirname "$0")" && pwd)
MARKER="$here/../scripts/orchestrate-marker.sh"
STATE="$here/../scripts/orchestrate-state.sh"
TAB=$(printf '\t')

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

[ -x "$MARKER" ] || fail "scripts/orchestrate-marker.sh missing or not executable"
[ -x "$STATE" ] || fail "scripts/orchestrate-state.sh missing or not executable"

# git with a deterministic, signing-free identity (CI fixtures never sign).
gitc() {
  repo="$1"
  shift
  git -C "$repo" -c user.name=test -c user.email=test@example.invalid \
    -c commit.gpgsign=false -c init.defaultBranch=main "$@"
}
gitc_init() { git -C "$1" -c init.defaultBranch=main init -q; }

state_of() {
  printf '%s\n' "$1" | awk -F"$TAB" -v i="$2" '$1=="task" && $2==i {print $3; exit}'
}

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# A fixture spec bundle whose .gitignore mirrors the real repo's runtime-state
# ignores, so the no-tracked-change assertions below exercise the real contract.
make_fixture() {
  repo="$1"
  spec="$repo/specs/demo"
  mkdir -p "$spec"
  gitc_init "$repo"
  cat >"$repo/.gitignore" <<'EOF'
specs/*/.orchestrate.lock
specs/*/.orchestrate/
EOF
  cat >"$spec/tasks.md" <<'EOF'
# Demo — Tasks
## Forward plan
### Task 1 — dispatched (marker only)
- **Dependencies:** none
### Task 2 — dispatched alongside 1 (bundle)
- **Dependencies:** none
### Task 3 — never dispatched
- **Dependencies:** none
EOF
  gitc "$repo" add -A
  gitc "$repo" commit -q -m "base: spec bundle"
}

# ---------------------------------------------------------------------------
# 1. REQ-A1.1 — `write` drops a fresh timestamped marker that derives the task
#    In progress, AND leaves the git tree clean (no dispatch commit). This is
#    the dispatch record's core property: branch + marker, zero tasks.md write.
# ---------------------------------------------------------------------------
repo="$tmp/dispatch"
spec="$repo/specs/demo"
make_fixture "$repo"

# Dispatch task 1: the branch is the first durable act (created here, no
# commits yet — the window the marker covers), then the marker is written.
gitc "$repo" branch planwright/demo/task-1
"$MARKER" write "$spec" 1 || fail "A1.1: write exited non-zero"

mfile="$spec/.orchestrate/markers/1"
[ -f "$mfile" ] || fail "A1.1: marker file not created at the default path"
[ ! -L "$mfile" ] || fail "A1.1: marker must be a regular file, not a symlink"
mval=$(cat "$mfile")
case "$mval" in
  '' | *[!0-9]*) fail "A1.1: marker content '$mval' is not a bare integer epoch" ;;
esac

# The engine reads the marker the writer dropped → in-progress (marker-fresh).
out=$("$STATE" "$spec") || fail "A1.1: state engine exited non-zero"
[ "$(state_of "$out" 1)" = in-progress ] \
  || fail "A1.1: task 1 did not derive in-progress from branch + marker"
[ "$(state_of "$out" 3)" = ready ] \
  || fail "A1.1: undispatched task 3 should be ready, not in-progress"

# The dispatch wrote NO git-tracked change: main carries no dispatch commit, so
# a worker worktree cut from it inherits nothing foreign (REQ-A1.2).
[ -z "$(gitc "$repo" status --porcelain)" ] \
  || fail "A1.1/A1.2: dispatch dirtied the git tree (marker must be gitignored)"
echo "ok: REQ-A1.1 write drops a fresh marker → in-progress, with zero tracked change"

# ---------------------------------------------------------------------------
# 2. REQ-A1.2 — a worktree branch cut from main after dispatch has an empty diff
#    against main: no sibling/foreign dispatch commit was inherited.
# ---------------------------------------------------------------------------
diff_out=$(gitc "$repo" diff main planwright/demo/task-1)
[ -z "$diff_out" ] \
  || fail "A1.2: the dispatch branch diverges from main (inherited a dispatch commit)"
echo "ok: REQ-A1.2 the dispatch branch carries no foreign commit (clean base)"

# ---------------------------------------------------------------------------
# 3. bundle dispatch — `write` accepts several ids and drops a marker per task,
#    each deriving in-progress (a cohesion bundle dispatches >1 task id).
# ---------------------------------------------------------------------------
gitc "$repo" branch planwright/demo/task-2
"$MARKER" write "$spec" 1 2 || fail "bundle: multi-id write exited non-zero"
[ -f "$spec/.orchestrate/markers/2" ] || fail "bundle: marker for task 2 not written"
bout=$("$STATE" "$spec") || fail "bundle: state engine exited non-zero"
[ "$(state_of "$bout" 2)" = in-progress ] || fail "bundle: task 2 not in-progress"
echo "ok: bundle write drops one marker per task id"

# ---------------------------------------------------------------------------
# 4. PLANWRIGHT_ORCH_STATE_DIR — the writer honors the override and writes where
#    the reader (with the same override) looks; nothing lands in the default dir.
# ---------------------------------------------------------------------------
orepo="$tmp/override"
ospec="$orepo/specs/demo"
make_fixture "$orepo"
altdir="$tmp/override-alt"
PLANWRIGHT_ORCH_STATE_DIR="$altdir" "$MARKER" write "$ospec" 1 \
  || fail "override: write exited non-zero"
[ -f "$altdir/1" ] || fail "override: marker not written to the override dir"
[ ! -e "$ospec/.orchestrate/markers/1" ] \
  || fail "override: a marker leaked into the default dir"
oout=$(PLANWRIGHT_ORCH_STATE_DIR="$altdir" "$STATE" "$ospec") \
  || fail "override: state engine exited non-zero"
[ "$(state_of "$oout" 1)" = in-progress ] \
  || fail "override: task 1 not in-progress from the override-dir marker"
echo "ok: PLANWRIGHT_ORCH_STATE_DIR is honored by the writer and reader together"

# ---------------------------------------------------------------------------
# 5. clear — removes the marker (reverting to ready) and is idempotent.
# ---------------------------------------------------------------------------
"$MARKER" clear "$spec" 1 || fail "clear: exited non-zero"
[ ! -e "$spec/.orchestrate/markers/1" ] || fail "clear: marker 1 not removed"
cout=$("$STATE" "$spec") || fail "clear: state engine exited non-zero"
[ "$(state_of "$cout" 1)" = ready ] \
  || fail "clear: task 1 should revert to ready after the marker is cleared"
"$MARKER" clear "$spec" 1 || fail "clear: not idempotent (clearing a gone marker must be a no-op)"
echo "ok: clear removes the marker (→ ready) and is idempotent"

# ---------------------------------------------------------------------------
# 6. REQ-F1.1 — a malformed/hostile id is refused (exit 2), nothing written.
# ---------------------------------------------------------------------------
hrepo="$tmp/hostile"
hspec="$hrepo/specs/demo"
make_fixture "$hrepo"
for bad in "../../etc/passwd" "*" "1; rm -rf /" "abc" "1.2.3" "5-6" "-1" "1/2" ".." ""; do
  rc=0
  "$MARKER" write "$hspec" "$bad" >/dev/null 2>&1 || rc=$?
  [ "$rc" = 2 ] || fail "F1.1: id '$bad' returned $rc, expected a clean refusal (exit 2)"
done
# No marker dir should have been created by any refused write.
[ ! -e "$hspec/.orchestrate/markers" ] \
  || fail "F1.1: a refused write created marker state (should write nothing)"
# A refusal in a multi-id batch refuses the whole batch before writing anything.
rc=0
"$MARKER" write "$hspec" 1 "../escape" >/dev/null 2>&1 || rc=$?
[ "$rc" = 2 ] || fail "F1.1: a batch with one hostile id must be refused (exit 2)"
[ ! -e "$hspec/.orchestrate/markers/1" ] \
  || fail "F1.1: a batch refusal still wrote the valid id (must be all-or-nothing)"
# A traversal id must never escape the marker base dir.
[ ! -e "$hrepo/passwd" ] && [ ! -e "$hrepo/etc/passwd" ] \
  || fail "F1.1: a traversal id escaped the marker base dir"
echo "ok: REQ-F1.1 malformed/hostile ids refused (exit 2), nothing written, batch all-or-nothing"

# ---------------------------------------------------------------------------
# 7. REQ-F1.1 — a symlink sitting at the marker path is refused, not followed
#    (the read-time symlink-swap guard has a write-time counterpart).
# ---------------------------------------------------------------------------
srepo="$tmp/symlink"
sspec="$srepo/specs/demo"
make_fixture "$srepo"
mkdir -p "$sspec/.orchestrate/markers"
target="$tmp/symlink-target"
: >"$target"
ln -s "$target" "$sspec/.orchestrate/markers/1"
rc=0
"$MARKER" write "$sspec" 1 >/dev/null 2>&1 || rc=$?
[ "$rc" = 2 ] || fail "F1.1: a symlink at the marker path returned $rc, expected refusal (exit 2)"
[ ! -s "$target" ] || fail "F1.1: the write followed the symlink and wrote through it"
echo "ok: REQ-F1.1 a symlink at the marker path is refused, never followed"

# ---------------------------------------------------------------------------
# 8. atomicity — no temp/partial file is left behind in the marker dir; the only
#    entry per dispatched id is the final, complete marker.
# ---------------------------------------------------------------------------
arepo="$tmp/atomic"
aspec="$arepo/specs/demo"
make_fixture "$arepo"
"$MARKER" write "$aspec" 1 || fail "atomic: write exited non-zero"
entries=$(find "$aspec/.orchestrate/markers" -type f | wc -l | tr -d ' ')
[ "$entries" = 1 ] || fail "atomic: expected exactly one marker file, found $entries (temp left behind?)"
echo "ok: write leaves no temp/partial file (atomic write-temp-then-rename)"

# ---------------------------------------------------------------------------
# 9. usage / fail-closed — missing args and an unknown subcommand exit 2.
# ---------------------------------------------------------------------------
rc=0
"$MARKER" >/dev/null 2>&1 || rc=$?
[ "$rc" = 2 ] || fail "usage: no args returned $rc, expected 2"
rc=0
"$MARKER" write "$tmp/does-not-exist" 1 >/dev/null 2>&1 || rc=$?
[ "$rc" = 2 ] || fail "usage: a missing spec dir returned $rc, expected 2"
rc=0
"$MARKER" frobnicate "$spec" 1 >/dev/null 2>&1 || rc=$?
[ "$rc" = 2 ] || fail "usage: an unknown subcommand returned $rc, expected 2"
echo "ok: usage errors and an unknown subcommand fail closed (exit 2)"

echo "PASS: test-orchestrate-marker.sh"
