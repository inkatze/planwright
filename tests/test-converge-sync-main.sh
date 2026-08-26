#!/bin/bash
# Tests for scripts/converge-sync-main.sh — the convergence-loop `main`-sync
# `/execute-task` runs at the top of each `review_sequence` pass, plus the
# structural assertions over that wiring (merge-currency-guard Task 3; D-4;
# REQ-B1.1, REQ-B1.2, REQ-B1.3, REQ-B1.4, REQ-B1.5, REQ-B1.6, REQ-D1.3,
# REQ-K1.1).
#
# Contract under test:
#   - a clean `origin/main` advance lands on the branch, by fast-forward when
#     the branch has no commits of its own and by merge commit when it does
#     (REQ-B1.1); an already-current branch is a no-op success;
#   - the sync is an explicit fetch followed by a merge — never `git pull`
#     (which a global `branch.autosetuprebase=always` silently rewrites into a
#     forbidden rebase) and never a rebase, asserted both over the source and
#     behaviorally under that very config (REQ-B1.2, REQ-D1.3);
#   - an unresolvable conflict aborts the merge and exits non-zero, leaving a
#     clean tree (no MERGE_HEAD, no conflict markers) so re-invoking on resume
#     re-attempts the same fetch + merge rather than wedging (REQ-B1.3);
#   - the three non-zero causes stay distinct — unreachable-remote fetch
#     failure, unresolvable merge conflict, and a pre-existing dirty working
#     tree — each with its own reason and exit code, never collapsed into a
#     misreported "merge conflict" (REQ-B1.6, REQ-K1.1);
#   - `/execute-task` invokes the script once at the top of the convergence
#     sequence and still opens only a draft PR (REQ-B1.1, REQ-B1.4, REQ-B1.5).
#
# Output stream is a tagged TSV on stdout, one record per line:
#   sync<TAB><up-to-date|fast-forward|merged><TAB><head-sha>
# Failures print `converge-sync-main: <reason>: <message>` on stderr.
# Exit: 0 synced; 2 usage / not a git work tree; 3 dirty-tree; 4 fetch-failed;
#   5 merge-conflict (aborted, tree clean); 6 merge-failed (a non-conflict
#   merge refusal); 7 abort-failed (the one state that is NOT resume-clean).
#
# Runs standalone under /bin/bash (the bash 3.2 floor).
set -eu
LC_ALL=C
export LC_ALL
unset CDPATH

here=$(cd "$(dirname "$0")" && pwd)
SYNC="$here/../scripts/converge-sync-main.sh"
SKILL="$here/../skills/execute-task/SKILL.md"
TAB=$(printf '\t')

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

[ -x "$SYNC" ] || fail "scripts/converge-sync-main.sh missing or not executable"
[ -f "$SKILL" ] || fail "skills/execute-task/SKILL.md missing"

# git with a deterministic, signing-free identity for fixture bookkeeping. The
# script under test runs its own git, so the same identity is also written into
# each fixture clone's LOCAL config (see new_clone) — otherwise a merge commit
# made by the script would fail on a host with no global identity, or block on
# a signing key.
gitc() {
  repo="$1"
  shift
  git -C "$repo" -c user.name=test -c user.email=test@example.invalid \
    -c commit.gpgsign=false -c init.defaultBranch=main "$@"
}

# Pull the value of a tagged record (col 1 == tag) out of the sync output.
tag_val() {
  printf '%s\n' "$1" | awk -F"$TAB" -v t="$2" '$1==t {print $2; exit}'
}

# new_origin <dir> — a bare origin seeded with one commit on `main`, plus a
# `seed` clone to push from. The bare repo's default branch is pinned at
# creation so the fixtures do not depend on the host's `init.defaultBranch`.
new_origin() {
  root="$1"
  git -c init.defaultBranch=main init -q --bare "$root/origin.git"
  git clone -q "$root/origin.git" "$root/seed" 2>/dev/null
  printf 'base\n' >"$root/seed/shared.txt"
  gitc "$root/seed" add -A
  gitc "$root/seed" commit -q -m "base"
  gitc "$root/seed" branch -M main
  gitc "$root/seed" push -q origin main
}

# new_clone <root> <name> [branch] — a worker clone on its own task branch,
# with a local identity so the script's own `git merge` can commit.
new_clone() {
  root="$1"
  name="$2"
  branch="${3:-task}"
  git clone -q "$root/origin.git" "$root/$name" 2>/dev/null
  git -C "$root/$name" config user.name test
  git -C "$root/$name" config user.email test@example.invalid
  git -C "$root/$name" config commit.gpgsign false
  gitc "$root/$name" checkout -q -b "$branch"
}

# advance_main <root> <file> <content> — land a commit on origin/main.
advance_main() {
  root="$1"
  printf '%s\n' "$3" >"$root/seed/$2"
  gitc "$root/seed" add -A
  gitc "$root/seed" commit -q -m "advance $2"
  gitc "$root/seed" push -q origin main
}

# ---------------------------------------------------------------------------
# Case 1 — a clean origin/main advance fast-forwards a branch with no commits
# of its own; the advanced commit is in the branch's history afterward
# (REQ-B1.1).
# ---------------------------------------------------------------------------
c1() {
  tmp=$(mktemp -d "${TMPDIR:-/tmp}/converge-sync.c1.XXXXXX")
  trap 'rm -rf "$tmp"' RETURN
  new_origin "$tmp"
  new_clone "$tmp" worker
  advance_main "$tmp" newfile.txt "from main"
  adv=$(gitc "$tmp/seed" rev-parse HEAD)

  out=$("$SYNC" "$tmp/worker") || fail "c1: sync exited non-zero on a clean advance"

  [ "$(tag_val "$out" sync)" = fast-forward ] \
    || fail "c1: expected sync=fast-forward, got '$(tag_val "$out" sync)'"
  gitc "$tmp/worker" merge-base --is-ancestor "$adv" HEAD \
    || fail "c1: the advanced origin/main commit is not in the branch history"
  [ -f "$tmp/worker/newfile.txt" ] \
    || fail "c1: the advanced file did not land in the working tree"
  echo "ok c1: a clean origin/main advance fast-forwards the worker branch"
}

# ---------------------------------------------------------------------------
# Case 2 — a branch with its own commits takes a merge commit, keeping both
# sides' history (REQ-B1.1, REQ-B1.2: merge, never rebase).
# ---------------------------------------------------------------------------
c2() {
  tmp=$(mktemp -d "${TMPDIR:-/tmp}/converge-sync.c2.XXXXXX")
  trap 'rm -rf "$tmp"' RETURN
  new_origin "$tmp"
  new_clone "$tmp" worker
  printf 'worker work\n' >"$tmp/worker/worker.txt"
  gitc "$tmp/worker" add -A
  gitc "$tmp/worker" commit -q -m "worker commit"
  own=$(gitc "$tmp/worker" rev-parse HEAD)
  advance_main "$tmp" newfile.txt "from main"
  adv=$(gitc "$tmp/seed" rev-parse HEAD)

  out=$("$SYNC" "$tmp/worker") || fail "c2: sync exited non-zero on a clean merge"

  [ "$(tag_val "$out" sync)" = merged ] \
    || fail "c2: expected sync=merged, got '$(tag_val "$out" sync)'"
  gitc "$tmp/worker" merge-base --is-ancestor "$adv" HEAD \
    || fail "c2: the advanced origin/main commit is not in the branch history"
  gitc "$tmp/worker" merge-base --is-ancestor "$own" HEAD \
    || fail "c2: the worker's own commit was rewritten (a rebase, not a merge)"
  [ "$(gitc "$tmp/worker" rev-list --count --merges HEAD)" -eq 1 ] \
    || fail "c2: expected exactly one merge commit on the branch"
  echo "ok c2: a branch with its own commits takes a merge commit, both sides kept"
}

# ---------------------------------------------------------------------------
# Case 3 — an already-current branch is a clean no-op: exit 0, no new commit.
# ---------------------------------------------------------------------------
c3() {
  tmp=$(mktemp -d "${TMPDIR:-/tmp}/converge-sync.c3.XXXXXX")
  trap 'rm -rf "$tmp"' RETURN
  new_origin "$tmp"
  new_clone "$tmp" worker
  before=$(gitc "$tmp/worker" rev-parse HEAD)

  out=$("$SYNC" "$tmp/worker") || fail "c3: sync exited non-zero on an up-to-date branch"

  [ "$(tag_val "$out" sync)" = up-to-date ] \
    || fail "c3: expected sync=up-to-date, got '$(tag_val "$out" sync)'"
  [ "$(gitc "$tmp/worker" rev-parse HEAD)" = "$before" ] \
    || fail "c3: an up-to-date sync moved the branch head"
  echo "ok c3: an already-current branch is a clean no-op"
}

# ---------------------------------------------------------------------------
# Case 4 — an unresolvable conflict aborts the merge, exits non-zero with the
# conflict reason, and leaves a CLEAN tree: no MERGE_HEAD, no conflict markers,
# head unmoved (REQ-B1.3, REQ-B1.6, REQ-K1.1).
# ---------------------------------------------------------------------------
c4() {
  tmp=$(mktemp -d "${TMPDIR:-/tmp}/converge-sync.c4.XXXXXX")
  trap 'rm -rf "$tmp"' RETURN
  new_origin "$tmp"
  new_clone "$tmp" worker
  printf 'worker side\n' >"$tmp/worker/shared.txt"
  gitc "$tmp/worker" add -A
  gitc "$tmp/worker" commit -q -m "worker edits shared.txt"
  before=$(gitc "$tmp/worker" rev-parse HEAD)
  advance_main "$tmp" shared.txt "main side"

  rc=0
  err=$("$SYNC" "$tmp/worker" 2>&1 >/dev/null) || rc=$?

  [ "$rc" -eq 5 ] || fail "c4: expected exit 5 (merge-conflict), got $rc"
  case "$err" in
    *merge-conflict*) ;;
    *) fail "c4: conflict stderr did not name the merge-conflict reason: $err" ;;
  esac
  case "$err" in
    *shared.txt*) ;;
    *) fail "c4: conflict message did not name the conflicting path: $err" ;;
  esac
  [ ! -f "$tmp/worker/.git/MERGE_HEAD" ] \
    || fail "c4: MERGE_HEAD survived — the merge was not aborted"
  [ -z "$(gitc "$tmp/worker" status --porcelain)" ] \
    || fail "c4: the working tree was left dirty after the abort"
  grep -q '<<<<<<<' "$tmp/worker/shared.txt" \
    && fail "c4: conflict markers were left in the working tree"
  [ "$(gitc "$tmp/worker" rev-parse HEAD)" = "$before" ] \
    || fail "c4: the branch head moved despite the aborted merge"
  echo "ok c4: an unresolvable conflict aborts, exits 5, and leaves a clean tree"
}

# ---------------------------------------------------------------------------
# Case 5 — re-invoking after an aborted conflict is idempotent: the same
# non-zero exit and reason, never a "merge already in progress" wedge
# (REQ-B1.3).
# ---------------------------------------------------------------------------
c5() {
  tmp=$(mktemp -d "${TMPDIR:-/tmp}/converge-sync.c5.XXXXXX")
  trap 'rm -rf "$tmp"' RETURN
  new_origin "$tmp"
  new_clone "$tmp" worker
  printf 'worker side\n' >"$tmp/worker/shared.txt"
  gitc "$tmp/worker" add -A
  gitc "$tmp/worker" commit -q -m "worker edits shared.txt"
  advance_main "$tmp" shared.txt "main side"

  rc1=0
  "$SYNC" "$tmp/worker" >/dev/null 2>&1 || rc1=$?
  rc2=0
  err2=$("$SYNC" "$tmp/worker" 2>&1 >/dev/null) || rc2=$?

  [ "$rc1" -eq 5 ] || fail "c5: first run expected exit 5, got $rc1"
  [ "$rc2" -eq 5 ] || fail "c5: re-invoke expected the same exit 5, got $rc2"
  case "$err2" in
    *merge-conflict*) ;;
    *) fail "c5: re-invoke reported a different reason than the conflict: $err2" ;;
  esac
  echo "ok c5: re-invoking after an aborted conflict re-attempts, exit and reason unchanged"
}

# ---------------------------------------------------------------------------
# Case 6 — an unreachable remote exits non-zero with the FETCH reason, distinct
# from the conflict reason and code (REQ-B1.6, REQ-K1.1).
# ---------------------------------------------------------------------------
c6() {
  tmp=$(mktemp -d "${TMPDIR:-/tmp}/converge-sync.c6.XXXXXX")
  trap 'rm -rf "$tmp"' RETURN
  new_origin "$tmp"
  new_clone "$tmp" worker
  git -C "$tmp/worker" remote set-url origin "$tmp/nonexistent.git"

  rc=0
  err=$(GIT_TERMINAL_PROMPT=0 "$SYNC" "$tmp/worker" 2>&1 >/dev/null) || rc=$?

  [ "$rc" -eq 4 ] || fail "c6: expected exit 4 (fetch-failed), got $rc"
  case "$err" in
    *fetch-failed*) ;;
    *) fail "c6: unreachable-remote stderr did not name the fetch reason: $err" ;;
  esac
  case "$err" in
    *merge-conflict*) fail "c6: a fetch failure was misreported as a merge conflict: $err" ;;
    *) ;;
  esac
  echo "ok c6: an unreachable remote exits 4 with its own fetch reason"
}

# ---------------------------------------------------------------------------
# Case 7 — a pre-existing dirty tree exits non-zero with the DIRTY reason,
# before any fetch runs. The remote is broken in this fixture too, so a reason
# of `dirty-tree` (not `fetch-failed`) is what proves the ordering: the sync
# never touched the network (REQ-B1.6, REQ-K1.1).
# ---------------------------------------------------------------------------
c7() {
  tmp=$(mktemp -d "${TMPDIR:-/tmp}/converge-sync.c7.XXXXXX")
  trap 'rm -rf "$tmp"' RETURN
  new_origin "$tmp"
  new_clone "$tmp" worker
  git -C "$tmp/worker" remote set-url origin "$tmp/nonexistent.git"
  printf 'uncommitted\n' >>"$tmp/worker/shared.txt"

  rc=0
  err=$("$SYNC" "$tmp/worker" 2>&1 >/dev/null) || rc=$?

  [ "$rc" -eq 3 ] || fail "c7: expected exit 3 (dirty-tree), got $rc"
  case "$err" in
    *dirty-tree*) ;;
    *) fail "c7: dirty-tree stderr did not name its own reason: $err" ;;
  esac
  case "$err" in
    *fetch-failed* | *merge-conflict*)
      fail "c7: a dirty tree was collapsed into a fetch/conflict reason: $err"
      ;;
    *) ;;
  esac
  echo "ok c7: a pre-existing dirty tree exits 3 with its own reason, before any fetch"
}

# ---------------------------------------------------------------------------
# Case 8 — untracked files alone do not block the sync. They cannot be
# rewritten by a merge that does not touch their paths, and a worker's scratch
# files are not a reason to halt a unit (REQ-B1.6 scopes the dirty-tree halt to
# a tree that actually blocks the merge).
# ---------------------------------------------------------------------------
c8() {
  tmp=$(mktemp -d "${TMPDIR:-/tmp}/converge-sync.c8.XXXXXX")
  trap 'rm -rf "$tmp"' RETURN
  new_origin "$tmp"
  new_clone "$tmp" worker
  printf 'scratch\n' >"$tmp/worker/scratch.log"
  advance_main "$tmp" newfile.txt "from main"

  out=$("$SYNC" "$tmp/worker") || fail "c8: an untracked scratch file blocked a clean sync"

  [ "$(tag_val "$out" sync)" = fast-forward ] \
    || fail "c8: expected sync=fast-forward, got '$(tag_val "$out" sync)'"
  [ -f "$tmp/worker/scratch.log" ] || fail "c8: the untracked file was destroyed"
  echo "ok c8: an untracked scratch file does not block the sync"
}

# ---------------------------------------------------------------------------
# Case 9 — source-level negative assertions: no `git pull`, no rebase in any
# form (REQ-B1.2, REQ-D1.3). Comments are stripped first so the script may
# still EXPLAIN why it avoids them.
# ---------------------------------------------------------------------------
c9() {
  code=$(sed 's/#.*$//' "$SYNC")

  printf '%s\n' "$code" | grep -Eq '(^|[^[:alnum:]_-])git[[:space:]]+([^|;&]*[[:space:]])?pull([^[:alnum:]_-]|$)' \
    && fail "c9: the script contains a 'git pull' (REQ-B1.2 forbids it)"
  printf '%s\n' "$code" | grep -Eq '(^|[^[:alnum:]_-])git[[:space:]]+([^|;&]*[[:space:]])?rebase([^[:alnum:]_-]|$)' \
    && fail "c9: the script runs 'git rebase' (REQ-B1.2 forbids it)"
  printf '%s\n' "$code" | grep -Eq -- '--rebase|rebase[[:space:]]*=[[:space:]]*(true|1|interactive|merges)' \
    && fail "c9: the script enables a rebase via flag or config (REQ-B1.2 forbids it)"
  printf '%s\n' "$code" | grep -Eq 'push[[:space:]]+--force|--force-with-lease|commit[[:space:]]+[^|;&]*--amend' \
    && fail "c9: the script contains a force-push or amend (bootstrap REQ-J1.4 forbids them)"

  printf '%s\n' "$code" | grep -Eq 'git[^|;&]*fetch[[:space:]]+([^|;&]*[[:space:]])?origin[[:space:]]+main' \
    || fail "c9: the script does not run 'git fetch origin main'"
  printf '%s\n' "$code" | grep -Eq 'merge[^|;&]*FETCH_HEAD' \
    || fail "c9: the script does not merge FETCH_HEAD"
  printf '%s\n' "$code" | grep -Eq 'merge[[:space:]]+--abort' \
    || fail "c9: the script never runs 'git merge --abort' (REQ-B1.3)"

  # Headless-hang guards. GIT_TERMINAL_PROMPT covers git's own credential
  # prompt; ssh's host-key and passphrase prompts are a separate channel that
  # would block the fetch just as hard, so both must be pinned.
  printf '%s\n' "$code" | grep -Eq 'export[[:space:]]+GIT_TERMINAL_PROMPT|GIT_TERMINAL_PROMPT=0' \
    || fail "c9: the script does not disable git's interactive terminal prompt"
  printf '%s\n' "$code" | grep -Eq 'GIT_SSH_COMMAND=.*BatchMode=yes' \
    || fail "c9: the script does not force ssh BatchMode, so an unknown host key can hang a headless fetch"
  echo "ok c9: source assertions — fetch + merge FETCH_HEAD, no pull/rebase/force/amend, no interactive prompt"
}

# ---------------------------------------------------------------------------
# Case 10 — behavioral no-rebase: under `branch.autosetuprebase=always` (the
# very config that silently turns a `git pull` into a forbidden rebase), the
# sync still produces a merge and rewrites no history (REQ-B1.2).
# ---------------------------------------------------------------------------
c10() {
  tmp=$(mktemp -d "${TMPDIR:-/tmp}/converge-sync.c10.XXXXXX")
  trap 'rm -rf "$tmp"' RETURN
  new_origin "$tmp"
  new_clone "$tmp" worker
  git -C "$tmp/worker" config branch.autosetuprebase always
  git -C "$tmp/worker" config pull.rebase true
  printf 'worker work\n' >"$tmp/worker/worker.txt"
  gitc "$tmp/worker" add -A
  gitc "$tmp/worker" commit -q -m "worker commit"
  own=$(gitc "$tmp/worker" rev-parse HEAD)
  advance_main "$tmp" newfile.txt "from main"

  out=$("$SYNC" "$tmp/worker") || fail "c10: sync exited non-zero under autosetuprebase=always"

  [ "$(tag_val "$out" sync)" = merged ] \
    || fail "c10: expected sync=merged under autosetuprebase, got '$(tag_val "$out" sync)'"
  gitc "$tmp/worker" merge-base --is-ancestor "$own" HEAD \
    || fail "c10: the worker's own commit was rewritten — a rebase happened"
  echo "ok c10: autosetuprebase=always still yields a merge, no rewritten history"
}

# ---------------------------------------------------------------------------
# Case 11 — a non-git directory fails closed with the usage code, never a
# silent success (REQ-K1.1).
# ---------------------------------------------------------------------------
c11() {
  tmp=$(mktemp -d "${TMPDIR:-/tmp}/converge-sync.c11.XXXXXX")
  trap 'rm -rf "$tmp"' RETURN

  rc=0
  err=$("$SYNC" "$tmp" 2>&1 >/dev/null) || rc=$?
  [ "$rc" -eq 2 ] || fail "c11: expected exit 2 on a non-git directory, got $rc"
  [ -n "$err" ] || fail "c11: non-git directory produced no reason"

  rc=0
  "$SYNC" "$tmp/does-not-exist" >/dev/null 2>&1 || rc=$?
  [ "$rc" -eq 2 ] || fail "c11: expected exit 2 on a missing directory, got $rc"

  rc=0
  err=$("$SYNC" a b 2>&1 >/dev/null) || rc=$?
  [ "$rc" -eq 2 ] || fail "c11: expected exit 2 on too many arguments, got $rc"
  # The arity refusal is a failure like any other, so it carries the same
  # tagged prefix and reason token the caller greps for. Asserting only the
  # exit code here is what let an untagged raw `usage:` line survive.
  case "$err" in
    'converge-sync-main: '*': '*) ;;
    *) fail "c11: the arity refusal is not in the tagged 'converge-sync-main: <reason>: <message>' form: $err" ;;
  esac
  echo "ok c11: a non-git, missing, or over-argumented target fails closed with a tagged usage reason"
}

# ---------------------------------------------------------------------------
# Case 12 — a missing binary is named for what it is. Without this probe the
# `git` absence surfaces through the work-tree check as "not a git work tree",
# sending the human to inspect a directory that is fine, and `scrub`'s own
# missing `tr` empties the path out of the message on top of it (REQ-K1.1: the
# reason names what could not be confirmed).
# ---------------------------------------------------------------------------
c12() {
  tmp=$(mktemp -d "${TMPDIR:-/tmp}/converge-sync.c12.XXXXXX")
  trap 'rm -rf "$tmp"' RETURN

  rc=0
  err=$(env -i PATH=/nonexistent-for-this-test /bin/bash "$SYNC" "$tmp" 2>&1 >/dev/null) || rc=$?

  [ "$rc" -eq 2 ] || fail "c12: expected exit 2 on a missing git, got $rc"
  case "$err" in
    *git*) ;;
    *) fail "c12: the missing-binary message never names git: $err" ;;
  esac
  case "$err" in
    *"not a git work tree"*)
      fail "c12: a missing git was misreported as a bad work tree: $err"
      ;;
    *) ;;
  esac
  echo "ok c12: a missing git is named as such, not misreported as a bad work tree"
}

# ---------------------------------------------------------------------------
# Case 13 — a merge refused for a NON-conflict reason gets its own exit and
# reason. c8 lets untracked files through on purpose, so the case they do block
# a merge — an incoming path colliding with an untracked file — is the one that
# has to stay distinguishable from a real conflict (REQ-B1.6, REQ-K1.1).
# ---------------------------------------------------------------------------
c13() {
  tmp=$(mktemp -d "${TMPDIR:-/tmp}/converge-sync.c13.XXXXXX")
  trap 'rm -rf "$tmp"' RETURN
  new_origin "$tmp"
  new_clone "$tmp" worker
  advance_main "$tmp" newfile.txt "from main"
  printf 'squatting\n' >"$tmp/worker/newfile.txt"
  before=$(gitc "$tmp/worker" rev-parse HEAD)

  rc=0
  err=$("$SYNC" "$tmp/worker" 2>&1 >/dev/null) || rc=$?

  [ "$rc" -eq 6 ] || fail "c13: expected exit 6 (merge-failed), got $rc"
  case "$err" in
    *merge-failed*) ;;
    *) fail "c13: the non-conflict refusal did not name the merge-failed reason: $err" ;;
  esac
  case "$err" in
    *merge-conflict*)
      fail "c13: a blocking untracked file was misreported as a merge conflict: $err"
      ;;
    *) ;;
  esac
  [ "$(gitc "$tmp/worker" rev-parse HEAD)" = "$before" ] \
    || fail "c13: the branch head moved despite the refused merge"
  [ ! -f "$tmp/worker/.git/MERGE_HEAD" ] \
    || fail "c13: MERGE_HEAD survived a refused merge"
  echo "ok c13: an untracked file blocking the merge exits 6, not as a conflict"
}

# ---------------------------------------------------------------------------
# Case 14 — an operation already in progress is refused BEFORE the merge, and
# says which one. c7 covers the other exit-3 message (uncommitted tracked
# changes); this covers the branch REQ-B1.3's no-wedging clause rests on: a
# lingering MERGE_HEAD (or CHERRY_PICK_HEAD) must halt on its own reason rather
# than be trampled by a second merge.
# ---------------------------------------------------------------------------
c14() {
  tmp=$(mktemp -d "${TMPDIR:-/tmp}/converge-sync.c14.XXXXXX")
  trap 'rm -rf "$tmp"' RETURN
  new_origin "$tmp"
  new_clone "$tmp" worker

  # A real conflicted merge, left unaborted — the exact state a crashed or
  # interrupted earlier sync would leave behind.
  printf 'worker side\n' >"$tmp/worker/shared.txt"
  gitc "$tmp/worker" add -A
  gitc "$tmp/worker" commit -q -m "worker edits shared.txt"
  advance_main "$tmp" shared.txt "main side"
  gitc "$tmp/worker" fetch -q origin main
  gitc "$tmp/worker" merge --no-edit FETCH_HEAD >/dev/null 2>&1 \
    && fail "c14: the fixture merge was expected to conflict"
  [ -f "$tmp/worker/.git/MERGE_HEAD" ] \
    || fail "c14: the fixture did not leave a MERGE_HEAD to detect"

  rc=0
  err=$("$SYNC" "$tmp/worker" 2>&1 >/dev/null) || rc=$?

  [ "$rc" -eq 3 ] || fail "c14: expected exit 3 on an in-progress merge, got $rc"
  case "$err" in
    *dirty-tree*) ;;
    *) fail "c14: an in-progress merge did not report the dirty-tree reason: $err" ;;
  esac
  case "$err" in
    *MERGE_HEAD*) ;;
    *) fail "c14: the refusal does not name which operation is in progress: $err" ;;
  esac
  case "$err" in
    *"uncommitted tracked change"*)
      fail "c14: an in-progress merge was reported as plain uncommitted changes: $err"
      ;;
    *) ;;
  esac
  # The pre-flight must refuse before the merge, so the interrupted state is
  # left exactly as found for the human to finish or abort.
  [ -f "$tmp/worker/.git/MERGE_HEAD" ] \
    || fail "c14: the sync disturbed the in-progress merge it was supposed to refuse"

  # The same branch, reached through a different state token.
  new_clone "$tmp" worker2
  printf 'w2 side\n' >"$tmp/worker2/shared.txt"
  gitc "$tmp/worker2" add -A
  gitc "$tmp/worker2" commit -q -m "worker2 edits shared.txt"
  gitc "$tmp/worker2" fetch -q origin main
  head_main=$(gitc "$tmp/worker2" rev-parse FETCH_HEAD)
  gitc "$tmp/worker2" cherry-pick "$head_main" >/dev/null 2>&1 \
    && fail "c14: the fixture cherry-pick was expected to conflict"

  rc=0
  err=$("$SYNC" "$tmp/worker2" 2>&1 >/dev/null) || rc=$?
  [ "$rc" -eq 3 ] || fail "c14: expected exit 3 on an in-progress cherry-pick, got $rc"
  case "$err" in
    *CHERRY_PICK_HEAD*) ;;
    *) fail "c14: an in-progress cherry-pick is not named in the refusal: $err" ;;
  esac
  echo "ok c14: an operation already in progress halts on its own reason, naming which one"
}

# ---------------------------------------------------------------------------
# Case 15 — failure messages stay one scrubbed line. The reason a human reads
# is the whole interface on a halt, so a hostile path must not be able to
# rewrite it: a carriage return overwrites the rendered line on a terminal, and
# an embedded newline splits one message into two.
# ---------------------------------------------------------------------------
c15() {
  cr=$(printf '\r')

  rc=0
  err=$("$SYNC" "$(printf 'evil\rconverge-sync-main: sync ok')" 2>&1 >/dev/null) || rc=$?
  [ "$rc" -eq 2 ] || fail "c15: expected exit 2 on a missing directory, got $rc"
  case "$err" in
    *"$cr"*) fail "c15: a carriage return survived into the failure message" ;;
    *) ;;
  esac

  rc=0
  err=$("$SYNC" "$(printf 'foo\nbar')" 2>&1 >/dev/null) || rc=$?
  [ "$rc" -eq 2 ] || fail "c15: expected exit 2 on a missing directory, got $rc"
  [ "$(printf '%s\n' "$err" | grep -c '')" -eq 1 ] \
    || fail "c15: a newline in the target split the failure into more than one line: $err"
  echo "ok c15: failure messages survive a hostile path as a single scrubbed line"
}

# ---------------------------------------------------------------------------
# Wiring 1 — `/execute-task` invokes the sync ONCE, at the top of the
# convergence sequence: before the line that runs the review skills, so the
# final iteration's CI + review verification lands on the post-sync head
# (REQ-B1.1). One occurrence is also what keeps the edit a single line
# (REQ-B1.5).
# ---------------------------------------------------------------------------
w1() {
  n=$(grep -c 'converge-sync-main\.sh' "$SKILL" || true)
  [ "$n" -eq 1 ] \
    || fail "w1: expected exactly 1 converge-sync-main.sh invocation in SKILL.md, found $n"

  sync_line=$(grep -n 'converge-sync-main\.sh' "$SKILL" | cut -d: -f1 || true)
  run_line=$(grep -n '^\*\*Run each named skill in order' "$SKILL" | cut -d: -f1 || true)
  conv_line=$(grep -n '^## Convergence' "$SKILL" | cut -d: -f1 || true)
  [ -n "$run_line" ] || fail "w1: could not locate the review-sequence run instruction in SKILL.md"
  [ -n "$conv_line" ] || fail "w1: could not locate the Convergence section heading in SKILL.md"
  [ "$sync_line" -gt "$conv_line" ] \
    || fail "w1: the sync call sits outside the Convergence section"
  [ "$sync_line" -lt "$run_line" ] \
    || fail "w1: the sync call does not sit at the TOP of the sequence (it follows the run instruction)"
  echo "ok w1: SKILL.md invokes the sync exactly once, at the top of the convergence sequence"
}

# ---------------------------------------------------------------------------
# Wiring 2 — the sync edit did not smuggle a ready-flip into `/execute-task`:
# the draft-only contract stands and no `gh pr ready` / MCP ready call appears
# in the skill body (REQ-B1.4).
# ---------------------------------------------------------------------------
w2() {
  grep -Eq 'gh pr ready|mcp__github__update_pull_request' "$SKILL" \
    && fail "w2: SKILL.md gained a ready-flip call — /execute-task must never flip ready"
  grep -q 'gh pr create --draft' "$SKILL" \
    || fail "w2: SKILL.md lost its draft-only PR creation instruction"
  grep -q 'The PR is always a draft. Never mark it ready and never merge.' "$SKILL" \
    || fail "w2: SKILL.md lost the PR-creation never-mark-ready contract"
  grep -Eq '^- \*\*Never\*\* create a non-draft PR, mark a PR ready, or merge' "$SKILL" \
    || fail "w2: SKILL.md lost the never-mark-ready invariant"
  echo "ok w2: /execute-task still opens only a draft PR and never flips ready"
}

c1
c2
c3
c4
c5
c6
c7
c8
c9
c10
c11
c12
c13
c14
c15
w1
w2

echo "PASS: test-converge-sync-main.sh"
