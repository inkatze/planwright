#!/bin/bash
# Tests for scripts/converge-sync-main.sh's policy arms: the
# worker_merge_conflict_policy knob's halt and resolve paths, the
# worker_base_merge knob, the park and repair records each failure exit
# prints, and the refusal of a sync on a branch that is not the session's
# (human-gates Task 10; REQ-E1.1, REQ-E1.2, REQ-E1.3, REQ-B1.2, REQ-B1.3).
# tests/test-converge-sync-main.sh stays the deep suite for the sync's
# fetch-and-merge mechanics.
#
# Runs standalone under /bin/bash (the bash 3.2 floor).
set -eu
LC_ALL=C
export LC_ALL
unset CDPATH

here=$(cd "$(dirname "$0")" && pwd)
SYNC="$here/../scripts/converge-sync-main.sh"
SR="$here/../scripts/step-record.sh"
SKILL="$here/../skills/execute-task/SKILL.md"
TAB=$(printf '\t')

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

[ -x "$SYNC" ] || fail "scripts/converge-sync-main.sh missing or not executable"

SANDBOX=$(mktemp -d "${TMPDIR:-/tmp}/converge-sync-resolve.XXXXXX")
trap 'rm -rf "$SANDBOX"' EXIT

# The policy is read from the fixture alone: no adopter overlay, the
# machine-local layer a file each case writes, and no session project
# directory unless a case sets one.
PLANWRIGHT_ADOPTER_OVERLAY="$SANDBOX/no-adopter"
PLANWRIGHT_LOCAL_CONFIG="$SANDBOX/local.yml"
export PLANWRIGHT_ADOPTER_OVERLAY PLANWRIGHT_LOCAL_CONFIG
unset PLANWRIGHT_REPO_ROOT CLAUDE_PROJECT_DIR PLANWRIGHT_CONFIG_DEFAULTS

set_knobs() {
  printf '%s\n' "$@" >"$PLANWRIGHT_LOCAL_CONFIG"
}

gitc() {
  _gitc_dir="$1"
  shift
  git -C "$_gitc_dir" -c user.name=test -c user.email=test@example.invalid \
    -c commit.gpgsign=false -c init.defaultBranch=main "$@"
}

rec() { # <output> <tag> — the first record's second field
  printf '%s\n' "$1" | awk -F"$TAB" -v t="$2" '$1==t {print $2; exit}'
}
rec_text() { # <output> <tag> — the first record's last field
  printf '%s\n' "$1" | awk -F"$TAB" -v t="$2" '$1==t {print $NF; exit}'
}

# fixture <name> — a bare origin with `main`, a seed clone to push from, and a
# worker clone on a task branch with one commit editing shared.txt. Sets T.
fixture() {
  T="$SANDBOX/$1"
  mkdir -p "$T"
  git -c init.defaultBranch=main init -q --bare "$T/origin.git"
  git clone -q "$T/origin.git" "$T/seed" 2>/dev/null
  printf 'base\n' >"$T/seed/shared.txt"
  gitc "$T/seed" add -A
  gitc "$T/seed" commit -q -m "base"
  gitc "$T/seed" branch -M main
  gitc "$T/seed" push -q origin main
  git clone -q "$T/origin.git" "$T/worker" 2>/dev/null
  git -C "$T/worker" config user.name test
  git -C "$T/worker" config user.email test@example.invalid
  git -C "$T/worker" config commit.gpgsign false
  gitc "$T/worker" checkout -q -b planwright/demo/task-1
  printf 'worker side\n' >"$T/worker/shared.txt"
  gitc "$T/worker" commit -q -am "feat: worker edits shared.txt"
}

advance_main() { # <file> <content>
  printf '%s\n' "$2" >"$T/seed/$1"
  gitc "$T/seed" add -A
  gitc "$T/seed" commit -q -m "advance $1"
  gitc "$T/seed" push -q origin main
}

run_sync() { # [args...] — sets OUT, ERR, RC
  local e="$SANDBOX/err"
  RC=0
  OUT=$("$SYNC" "$@" 2>"$e") || RC=$?
  ERR=$(cat "$e")
}

# ---------------------------------------------------------------------------
# REQ-E1.2: under halt (the shipped default) a conflict aborts, the tree is
# clean, and the park record names the class and the conflicting path.
# ---------------------------------------------------------------------------
r1() {
  fixture r1
  set_knobs
  advance_main shared.txt "main side"
  run_sync "$T/worker"
  [ "$RC" -eq 5 ] || fail "r1: expected exit 5 under halt, got $RC: $ERR"
  [ -z "$(gitc "$T/worker" status --porcelain --untracked-files=no)" ] \
    || fail "r1: the tree is not clean after a halt"
  [ "$(rec "$OUT" park)" = merge-conflict ] \
    || fail "r1: no merge-conflict park record: $OUT"
  case $(rec_text "$OUT" park) in
    *shared.txt*) ;;
    *) fail "r1: the park record does not name the conflicting path: $OUT" ;;
  esac
  echo "ok r1: halt aborts, leaves a clean tree, and parks naming the paths"
}

# ---------------------------------------------------------------------------
# REQ-E1.2, REQ-B1.2, REQ-B1.3: under resolve the conflict is left for the
# worker, whose resolution commit carries the sign-off trailer; the checklist
# flags it and names the halt re-run with the rejected trailer, never a
# revert.
# ---------------------------------------------------------------------------
r2() {
  fixture r2
  set_knobs 'worker_merge_conflict_policy: resolve'
  advance_main shared.txt "main side"
  run_sync "$T/worker"
  [ "$RC" -eq 8 ] || fail "r2: expected exit 8 (conflict left for resolution), got $RC: $ERR"
  [ -n "$(gitc "$T/worker" rev-parse -q --verify MERGE_HEAD)" ] \
    || fail "r2: the merge was not left in progress for the worker"
  case $(rec_text "$OUT" resolve) in
    *shared.txt*) ;;
    *) fail "r2: the resolve record does not name the conflicting path: $OUT" ;;
  esac
  [ -z "$(rec "$OUT" park)" ] || fail "r2: a resolve exit wrote a park record: $OUT"

  # Refused while a conflict stands, and nothing is committed.
  run_sync --commit-resolution demo/1 "$T/worker"
  [ "$RC" -eq 11 ] || fail "r2: committing with an unresolved path should exit 11, got $RC: $ERR"
  case $ERR in *shared.txt*) ;; *) fail "r2: the refusal does not name the unresolved path: $ERR" ;; esac

  # Refused when a staged file still carries conflict markers.
  gitc "$T/worker" add shared.txt
  run_sync --commit-resolution demo/1 "$T/worker"
  [ "$RC" -eq 11 ] || fail "r2: committing leftover conflict markers should exit 11, got $RC: $ERR"

  printf 'resolved\n' >"$T/worker/shared.txt"
  gitc "$T/worker" add shared.txt
  run_sync --commit-resolution demo/1 "$T/worker"
  [ "$RC" -eq 0 ] || fail "r2: the resolution commit failed ($RC): $ERR"
  [ "$(rec "$OUT" resolution)" = "$(gitc "$T/worker" rev-parse HEAD)" ] \
    || fail "r2: the resolution record does not name the new head: $OUT"
  [ "$(gitc "$T/worker" rev-list --parents -n 1 HEAD | wc -w | tr -d ' ')" -eq 3 ] \
    || fail "r2: the resolution is not a merge commit"
  [ "$(gitc "$T/worker" log -1 --format='%(trailers:key=Planwright-Sign-Off,valueonly)' | tr -d '\n')" = PS-1 ] \
    || fail "r2: the resolution commit does not carry Planwright-Sign-Off: PS-1"
  [ "$(gitc "$T/worker" log -1 --format='%(trailers:key=Planwright-Task,valueonly)' | tr -d '\n')" = demo/1 ] \
    || fail "r2: the resolution commit does not carry its task trailer"

  cl=$("$SR" --worktree "$T/worker" regenerate --base origin/main --head HEAD --checklist-only) \
    || fail "r2: the checklist did not regenerate"
  case $cl in *'**PS-1**'*) ;; *) fail "r2: the checklist does not list the resolution: $cl" ;; esac
  printf '%s\n' "$cl" | grep -q '^  - Base-merge resolution: .*shared.txt' \
    || fail "r2: the PR-body checklist does not flag the resolution with its paths: $cl"
  recipe=$(printf '%s\n' "$cl" | grep '^  - Reject with:') || fail "r2: no recipe: $cl"
  case $recipe in
    *'worker_merge_conflict_policy: halt'*'Planwright-Sign-Off-Rejected: PS-1'*) ;;
    *) fail "r2: the recipe does not name the halt re-run with the rejected trailer: $recipe" ;;
  esac
  case $recipe in *'`git revert'*) fail "r2: the recipe offers a revert: $recipe" ;; esac

  # A second commit attempt finds no resolve-mode merge in progress.
  run_sync --commit-resolution demo/1 "$T/worker"
  [ "$RC" -eq 11 ] || fail "r2: a resolution commit with no merge in progress should exit 11, got $RC"
  echo "ok r2: resolve leaves the conflict, commits a trailered resolution, and the checklist names the halt re-run"
}

# ---------------------------------------------------------------------------
# REQ-E1.2: a hand-started merge is not a resolve-mode sync, so the helper
# will not stamp it.
# ---------------------------------------------------------------------------
r3() {
  fixture r3
  set_knobs 'worker_merge_conflict_policy: resolve'
  advance_main shared.txt "main side"
  gitc "$T/worker" fetch -q origin main
  gitc "$T/worker" merge -q FETCH_HEAD >/dev/null 2>&1 || true
  printf 'resolved\n' >"$T/worker/shared.txt"
  gitc "$T/worker" add shared.txt
  run_sync --commit-resolution demo/1 "$T/worker"
  [ "$RC" -eq 11 ] || fail "r3: a merge the sync did not leave should exit 11, got $RC: $ERR"
  [ -n "$(gitc "$T/worker" rev-parse -q --verify MERGE_HEAD)" ] \
    || fail "r3: the refusal disturbed the worker's merge"

  # A policy turned back to halt refuses the commit too.
  gitc "$T/worker" merge --abort
  run_sync "$T/worker"
  [ "$RC" -eq 8 ] || fail "r3: expected exit 8, got $RC: $ERR"
  printf 'resolved\n' >"$T/worker/shared.txt"
  gitc "$T/worker" add shared.txt
  set_knobs
  run_sync --commit-resolution demo/1 "$T/worker"
  [ "$RC" -eq 11 ] || fail "r3: a resolution under halt should exit 11, got $RC: $ERR"
  echo "ok r3: only a resolve-mode sync's own merge, under resolve, is committed"
}

# ---------------------------------------------------------------------------
# REQ-E1.2: the dirty-tree, failed-fetch, and failed-merge exits park naming
# the failure class; a failed abort writes no park and names hand repair.
# ---------------------------------------------------------------------------
r4() {
  fixture r4
  set_knobs
  printf 'uncommitted\n' >"$T/worker/shared.txt"
  run_sync "$T/worker"
  [ "$RC" -eq 3 ] && [ "$(rec "$OUT" park)" = dirty-tree ] \
    || fail "r4: a dirty tree should exit 3 with a dirty-tree park, got $RC: $OUT"
  gitc "$T/worker" checkout -q -- shared.txt

  gitc "$T/worker" remote set-url origin "$T/no-such-origin.git"
  run_sync "$T/worker"
  [ "$RC" -eq 4 ] && [ "$(rec "$OUT" park)" = fetch-failed ] \
    || fail "r4: a failed fetch should exit 4 with a fetch-failed park, got $RC: $OUT"
  gitc "$T/worker" remote set-url origin "$T/origin.git"

  advance_main blocker.txt "from main"
  printf 'untracked\n' >"$T/worker/blocker.txt"
  run_sync "$T/worker"
  [ "$RC" -eq 6 ] && [ "$(rec "$OUT" park)" = merge-failed ] \
    || fail "r4: a refused merge should exit 6 with a merge-failed park, got $RC: $OUT"
  rm -f "$T/worker/blocker.txt"

  advance_main shared.txt "main side"
  real_git=$(command -v git)
  mkdir -p "$T/bin"
  cat >"$T/bin/git" <<STUB
#!/bin/sh
case " \$* " in
  *" merge --abort "*) echo "stub: refusing to abort" >&2; exit 1 ;;
esac
exec "$real_git" "\$@"
STUB
  chmod +x "$T/bin/git"
  RC=0
  OUT=$(PATH="$T/bin:$PATH" "$SYNC" "$T/worker" 2>/dev/null) || RC=$?
  [ "$RC" -eq 7 ] || fail "r4: a failed abort should exit 7, got $RC"
  [ -z "$(rec "$OUT" park)" ] || fail "r4: a failed abort wrote a park record: $OUT"
  [ "$(rec "$OUT" repair)" = abort-failed ] || fail "r4: a failed abort printed no repair record: $OUT"
  case $(rec_text "$OUT" repair) in
    *"by hand"*) ;;
    *) fail "r4: the repair record does not name hand repair: $OUT" ;;
  esac
  echo "ok r4: each failure exit parks naming its class, and a failed abort names hand repair instead"
}

# ---------------------------------------------------------------------------
# REQ-E1.1: worker_base_merge: deny skips the merge; a malformed repo-tracked
# value refuses it and parks.
# ---------------------------------------------------------------------------
r5() {
  fixture r5
  set_knobs 'worker_base_merge: deny'
  advance_main other.txt "from main"
  before=$(gitc "$T/worker" rev-parse HEAD)
  run_sync "$T/worker"
  [ "$RC" -eq 0 ] && [ "$(rec "$OUT" sync)" = denied ] \
    || fail "r5: worker_base_merge: deny should skip with sync=denied, got $RC: $OUT $ERR"
  [ "$(gitc "$T/worker" rev-parse HEAD)" = "$before" ] || fail "r5: a denied sync moved the head"

  set_knobs
  mkdir -p "$T/worker/.claude"
  printf 'worker_merge_conflict_policy: maybe\n' >"$T/worker/.claude/planwright.yml"
  run_sync "$T/worker"
  [ "$RC" -eq 9 ] && [ "$(rec "$OUT" park)" = policy-unreadable ] \
    || fail "r5: a malformed tracked value should exit 9 with a policy-unreadable park, got $RC: $OUT"
  [ "$(gitc "$T/worker" rev-parse HEAD)" = "$before" ] || fail "r5: an unreadable policy still merged"
  echo "ok r5: worker_base_merge: deny skips the merge, and an unreadable policy refuses it"
}

# ---------------------------------------------------------------------------
# REQ-E1.1, REQ-E1.3: a sync on a protected branch, or in a worktree whose
# branch is not the session's unit branch, is refused before any fetch.
# ---------------------------------------------------------------------------
r6() {
  fixture r6
  set_knobs
  advance_main other.txt "from main"
  gitc "$T/worker" checkout -q main
  before=$(gitc "$T/worker" rev-parse HEAD)
  run_sync "$T/worker"
  [ "$RC" -eq 10 ] || fail "r6: a sync on main should exit 10, got $RC: $ERR"
  [ "$(gitc "$T/worker" rev-parse HEAD)" = "$before" ] || fail "r6: a refused sync moved main"
  gitc "$T/worker" checkout -q planwright/demo/task-1

  gitc "$T/worker" worktree add -q -b planwright/demo/task-2 "$T/sibling" origin/main 2>/dev/null
  before=$(gitc "$T/sibling" rev-parse HEAD)
  RC=0
  ERR=$(CLAUDE_PROJECT_DIR="$T/worker" "$SYNC" "$T/sibling" 2>&1 >/dev/null) || RC=$?
  [ "$RC" -eq 10 ] || fail "r6: a sync into another unit's worktree should exit 10, got $RC: $ERR"
  [ "$(gitc "$T/sibling" rev-parse HEAD)" = "$before" ] || fail "r6: a refused sync moved the sibling"

  RC=0
  CLAUDE_PROJECT_DIR="$T/worker" "$SYNC" "$T/worker" >/dev/null 2>&1 || RC=$?
  [ "$RC" -eq 0 ] || fail "r6: a sync in the session's own worktree should succeed, got $RC"
  echo "ok r6: a sync off the session's unit branch is refused"
}

# ---------------------------------------------------------------------------
# Wiring: /execute-task routes the park, repair, and resolve records.
# ---------------------------------------------------------------------------
w1() {
  flat=$(tr '\n' ' ' <"$SKILL")
  # shellcheck disable=SC2016 # literal backticks of the skill's markdown
  for want in '`park`' '`repair`' '`resolve`'; do
    case $flat in *"$want"*) ;; *) fail "w1: SKILL.md does not route the sync's $want record" ;; esac
  done
  echo "ok w1: /execute-task routes the sync's park, repair, and resolve outcomes"
}

r1
r2
r3
r4
r5
r6
w1

echo "PASS: test-converge-sync-resolve.sh"
