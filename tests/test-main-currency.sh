#!/bin/bash
# Tests for scripts/main-currency.sh — the cross-checkout `main`-currency sync
# path (concurrent-orchestrator-coordination Task 3: D-3, D-10 · REQ-B1.2,
# REQ-B1.4).
#
# WHY THESE ASSERTIONS ARE COMMAND-LEVEL. A fast-forward merge and a rebase of a
# branch that has no divergent commits produce an IDENTICAL commit graph, so
# inspecting the resulting history cannot tell them apart — and the whole point
# of REQ-B1.4 is that the forbidden operation (rebase, reached through a bare
# `git pull` under `branch.autosetuprebase=always`) is the one that leaves no
# trace in the graph. The fixtures therefore interpose a `git` shim on PATH that
# records every argv the script invokes and then execs the real git, and assert
# against THAT log: the sync must invoke an explicit `fetch` followed by
# `merge --ff-only`, and must never invoke `pull`, `rebase`, `reset --hard`,
# a force-push, or `commit --amend`.
#
# What is covered:
#   - under `branch.autosetuprebase=always`, syncing a checked-out `main` is an
#     explicit `git fetch origin main` + `git merge --ff-only FETCH_HEAD` at the
#     command level — never a bare `git pull`, never a rebase (REQ-B1.4);
#   - with a worker branch checked out, the sync updates the `main` REF via
#     `git fetch origin main:main` and issues no `merge` at all, so no foreign
#     commit is ever dragged onto the worker branch (REQ-B1.4 — the path the
#     spec requires be exercised, not left untested);
#   - a fetch failure is CLASSIFIED before acting (D-10): no `origin` configured
#     degrades to the single-checkout solo flow and is NOT an error, while a
#     transient fetch failure against a configured `origin` fails closed —
#     surfaced, with `main` left unmoved rather than silently stale-and-accepted;
#   - a `--ff-only` refusal (simulated divergence) is surfaced for the operator
#     on both the checked-out and the ref-update path, with no force, rebase, or
#     reset attempted;
#   - across every path, no history-rewriting git operation is ever invoked
#     (REQ-B1.2: the never-rebase / never-force-push / never-amend /
#     never-`reset --hard` invariants are preserved, asserted rather than
#     asserted-by-prose);
#   - the sync never pushes to `main` (REQ-B1.4: currency flows origin→local
#     only; commits reach `origin` by PR).
#
# Runs standalone under /bin/bash (the bash 3.2 floor):
#   ./tests/test-main-currency.sh
set -eu
LC_ALL=C
export LC_ALL
unset CDPATH

# Isolate git fully from the host's global/system config: signing
# (commit.gpgsign + a 1Password/GPG signer that blocks non-interactively) and
# branch.autosetuprebase would otherwise hang or reshape the fixture commits.
export GIT_CONFIG_GLOBAL=/dev/null
export GIT_CONFIG_SYSTEM=/dev/null
export GIT_TERMINAL_PROMPT=0

here=$(cd "$(dirname "$0")" && pwd)
MC="$here/../scripts/main-currency.sh"

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

[ -x "$MC" ] || fail "scripts/main-currency.sh missing or not executable"

# Resolve the REAL git ONCE, before the shim is ever on PATH, so the shim can
# exec it without recursing into itself. The delimiter below is unquoted, so
# this value is expanded as the shim is WRITTEN — it has to land inside quotes
# there, or a git whose own path contains a space is word-split at shim run
# time and every scenario fails as though git were missing.
REAL_GIT=$(command -v git) || fail "git not on PATH"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

shim_dir="$tmp/shim"
mkdir -p "$shim_dir"
cat >"$shim_dir/git" <<EOF
#!/bin/sh
# Command-level recorder: log the argv, then behave exactly like git.
printf '%s\n' "\$*" >>"\$PW_GIT_LOG"
exec "$REAL_GIT" "\$@"
EOF
chmod +x "$shim_dir/git"

# Run the script with the recording shim first on PATH.
mc() {
  PATH="$shim_dir:$PATH" /bin/bash "$MC" "$@"
}

git_log_has() {
  grep -Eq "$1" "$PW_GIT_LOG"
}

# The history-rewriting operations REQ-B1.2 forbids. Checked after EVERY
# scenario, so no path can smuggle one in.
assert_no_rewrite() {
  ar_where=$1
  if git_log_has '(^| )rebase( |$)'; then
    fail "$ar_where: invoked git rebase"
  fi
  if git_log_has '(^| )pull( |$)'; then
    fail "$ar_where: invoked bare git pull (the autosetuprebase footgun)"
  fi
  if git_log_has 'reset .*--hard'; then
    fail "$ar_where: invoked git reset --hard"
  fi
  if git_log_has 'commit .*--amend'; then
    fail "$ar_where: invoked git commit --amend"
  fi
  if git_log_has 'push .*(--force|-f)( |$)'; then
    fail "$ar_where: invoked a force-push"
  fi
  if git_log_has 'push .*(main|HEAD:main)'; then
    fail "$ar_where: pushed to main (currency is origin->local only)"
  fi
}

# Build a bare `origin` plus a tower checkout of it. Echoes the checkout path.
# `$1` names the fixture so each scenario gets its own tree.
new_fixture() {
  nf_name=$1
  nf_root="$tmp/$nf_name"
  mkdir -p "$nf_root"
  "$REAL_GIT" init --quiet --bare --initial-branch=main "$nf_root/origin.git"

  # A seeding clone that publishes the initial commit to origin. Built with
  # init+remote rather than `clone`, which would warn about the empty repo.
  "$REAL_GIT" init --quiet --initial-branch=main "$nf_root/seed"
  "$REAL_GIT" -C "$nf_root/seed" remote add origin "$nf_root/origin.git"
  (
    cd "$nf_root/seed"
    "$REAL_GIT" config user.email t@example.invalid
    "$REAL_GIT" config user.name Tester
    "$REAL_GIT" config commit.gpgsign false
    echo one >file.txt
    "$REAL_GIT" add file.txt
    "$REAL_GIT" commit --quiet -m "seed"
    "$REAL_GIT" push --quiet origin main
  )

  # The tower checkout: a SEPARATE clone with its own private mutable main.
  "$REAL_GIT" clone --quiet "$nf_root/origin.git" "$nf_root/tower"
  (
    cd "$nf_root/tower"
    "$REAL_GIT" config user.email t@example.invalid
    "$REAL_GIT" config user.name Tester
    "$REAL_GIT" config commit.gpgsign false
    # THE PITFALL UNDER TEST: with this set, a bare `git pull` silently becomes
    # a rebase. Every scenario carries it, so the sync path has to be immune.
    "$REAL_GIT" config branch.autosetuprebase always
    "$REAL_GIT" config pull.rebase true
  )
  printf '%s\n' "$nf_root"
}

# Advance origin/main by one commit, from the seeding clone.
advance_origin() {
  (
    cd "$1/seed"
    echo more >>file.txt
    "$REAL_GIT" add file.txt
    "$REAL_GIT" commit --quiet -m "advance"
    "$REAL_GIT" push --quiet origin main
  )
}

# 1. `main` checked out, origin ahead: an explicit fetch-then-`--ff-only` merge,
#    asserted at the COMMAND level, under branch.autosetuprebase=always.
root=$(new_fixture ff)
advance_origin "$root"
PW_GIT_LOG="$tmp/log1"
export PW_GIT_LOG
: >"$PW_GIT_LOG"
before=$("$REAL_GIT" -C "$root/tower" rev-parse main)
out=$(mc sync --checkout "$root/tower") || fail "1: sync failed on a clean fast-forward: $out"
after=$("$REAL_GIT" -C "$root/tower" rev-parse main)
[ "$before" != "$after" ] || fail "1: main did not advance"
[ "$after" = "$("$REAL_GIT" -C "$root/origin.git" rev-parse main)" ] \
  || fail "1: main is not at origin/main after sync"
git_log_has '(^| )fetch .*origin main( |$)' \
  || fail "1: no explicit 'git fetch origin main' in the command log"
git_log_has '(^| )merge .*--ff-only' \
  || fail "1: the merge was not --ff-only at the command level"
printf '%s\n' "$out" | grep -q 'fast-forward' \
  || fail "1: sync did not report a fast-forward: $out"
assert_no_rewrite 1

# 2. A worker branch checked out: the `main` REF is updated via
#    `git fetch origin main:main`, with NO merge onto the worker branch.
#
#    The worker commit deliberately touches a DIFFERENT file than the one origin
#    advances, so a bare `git merge FETCH_HEAD` here would succeed cleanly rather
#    than conflicting. That matters: a conflicting fixture would "pass" this test
#    for the wrong reason (the forbidden merge erroring out), hiding the case the
#    assertion actually exists to catch — a silent, successful merge that drags
#    origin/main onto the worker branch.
root=$(new_fixture refupdate)
(
  cd "$root/tower"
  "$REAL_GIT" checkout --quiet -b planwright/demo/task-1
  echo worker >worker-only.txt
  "$REAL_GIT" add worker-only.txt
  "$REAL_GIT" commit --quiet -m "worker work"
)
advance_origin "$root"
PW_GIT_LOG="$tmp/log2"
export PW_GIT_LOG
: >"$PW_GIT_LOG"
worker_before=$("$REAL_GIT" -C "$root/tower" rev-parse HEAD)
out=$(mc sync --checkout "$root/tower") || fail "2: sync failed on the ref-update path: $out"
worker_after=$("$REAL_GIT" -C "$root/tower" rev-parse HEAD)
[ "$worker_before" = "$worker_after" ] \
  || fail "2: the worker branch moved — a foreign commit was dragged onto it"
[ "$("$REAL_GIT" -C "$root/tower" rev-parse main)" = "$("$REAL_GIT" -C "$root/origin.git" rev-parse main)" ] \
  || fail "2: the main ref was not updated to origin/main"
[ "$("$REAL_GIT" -C "$root/tower" symbolic-ref --short HEAD)" = "planwright/demo/task-1" ] \
  || fail "2: the checked-out branch changed"
git_log_has '(^| )fetch .*origin main:main( |$)' \
  || fail "2: no 'git fetch origin main:main' ref update in the command log"
if git_log_has '(^| )merge( |$)|(^| )merge '; then
  fail "2: a merge was invoked while a worker branch was checked out"
fi
printf '%s\n' "$out" | grep -q 'ref-update' \
  || fail "2: sync did not report a ref-update: $out"
assert_no_rewrite 2

# 3. No `origin` configured: the single-checkout SOLO flow, exit 0, not an error.
root=$(new_fixture solo)
"$REAL_GIT" -C "$root/tower" remote remove origin
PW_GIT_LOG="$tmp/log3"
export PW_GIT_LOG
: >"$PW_GIT_LOG"
out=$(mc sync --checkout "$root/tower") \
  || fail "3: a no-origin checkout must degrade to solo (exit 0), not error: $out"
printf '%s\n' "$out" | grep -q 'solo' \
  || fail "3: sync did not report the solo flow: $out"
if git_log_has '(^| )fetch( |$)|(^| )fetch '; then
  fail "3: fetched with no origin configured"
fi
assert_no_rewrite 3

# 4. A transient fetch failure against a CONFIGURED origin: fail closed.
root=$(new_fixture transient)
advance_origin "$root"
"$REAL_GIT" -C "$root/tower" remote set-url origin "$root/does-not-exist.git"
PW_GIT_LOG="$tmp/log4"
export PW_GIT_LOG
: >"$PW_GIT_LOG"
before=$("$REAL_GIT" -C "$root/tower" rev-parse main)
set +e
out=$(mc sync --checkout "$root/tower" 2>&1)
rc=$?
set -e
[ "$rc" -ne 0 ] || fail "4: a failed fetch against a configured origin must fail closed, got exit 0"
[ "$rc" -eq 3 ] || fail "4: expected the fail-closed exit code 3, got $rc"
[ "$before" = "$("$REAL_GIT" -C "$root/tower" rev-parse main)" ] \
  || fail "4: main moved despite a failed fetch"
printf '%s\n' "$out" | grep -qi 'fetch' \
  || fail "4: the failure was not surfaced with a fetch reason: $out"
assert_no_rewrite 4

# 5. A `--ff-only` refusal on the checked-out path: surfaced, never forced.
root=$(new_fixture diverged)
(
  cd "$root/tower"
  echo local >>file.txt
  "$REAL_GIT" add file.txt
  "$REAL_GIT" commit --quiet -m "unexpected local main commit"
)
advance_origin "$root"
PW_GIT_LOG="$tmp/log5"
export PW_GIT_LOG
: >"$PW_GIT_LOG"
before=$("$REAL_GIT" -C "$root/tower" rev-parse main)
set +e
out=$(mc sync --checkout "$root/tower" 2>&1)
rc=$?
set -e
[ "$rc" -ne 0 ] || fail "5: a non-fast-forward divergence must not report success"
[ "$rc" -eq 4 ] || fail "5: expected the divergence exit code 4, got $rc"
[ "$before" = "$("$REAL_GIT" -C "$root/tower" rev-parse main)" ] \
  || fail "5: main moved across a refused fast-forward"
# A GENUINE divergence must make the positive claim — this is the counterpart
# of test 10, which asserts a dirty tree never makes it.
printf '%s\n' "$out" | grep -qi 'has diverged' \
  || fail "5: a real divergence was not surfaced as one: $out"
assert_no_rewrite 5

# 6. A non-fast-forward on the REF-UPDATE path is likewise refused, not forced.
root=$(new_fixture diverged-ref)
(
  cd "$root/tower"
  echo local >>file.txt
  "$REAL_GIT" add file.txt
  "$REAL_GIT" commit --quiet -m "unexpected local main commit"
  "$REAL_GIT" checkout --quiet -b planwright/demo/task-2
)
advance_origin "$root"
PW_GIT_LOG="$tmp/log6"
export PW_GIT_LOG
: >"$PW_GIT_LOG"
before=$("$REAL_GIT" -C "$root/tower" rev-parse main)
set +e
out=$(mc sync --checkout "$root/tower" 2>&1)
rc=$?
set -e
[ "$rc" -eq 4 ] || fail "6: expected the divergence exit code 4 on the ref-update path, got $rc"
[ "$before" = "$("$REAL_GIT" -C "$root/tower" rev-parse main)" ] \
  || fail "6: the main ref moved across a refused non-fast-forward ref update"
if git_log_has 'fetch .*\+.*main:main|fetch .*--force'; then
  fail "6: the ref update was forced"
fi
assert_no_rewrite 6

# 7. Already current: a no-op that still reports success and still never rebases.
root=$(new_fixture uptodate)
PW_GIT_LOG="$tmp/log7"
export PW_GIT_LOG
: >"$PW_GIT_LOG"
before=$("$REAL_GIT" -C "$root/tower" rev-parse main)
out=$(mc sync --checkout "$root/tower") || fail "7: sync failed when already current: $out"
[ "$before" = "$("$REAL_GIT" -C "$root/tower" rev-parse main)" ] \
  || fail "7: main moved when already current"
printf '%s\n' "$out" | grep -q 'up-to-date' \
  || fail "7: sync did not report up-to-date: $out"
assert_no_rewrite 7

# 8. `main` checked out in a SIBLING WORKTREE of the same clone — the ordinary
#    planwright shape, where the primary checkout sits on `main` and worker
#    worktrees are cut from it.
#
#    git refuses to update a branch ref that is checked out in any worktree, and
#    is right to: moving it would desynchronize that worktree's index. So the
#    refusal is correct and the ref update must NOT be forced. What matters is
#    the CLASSIFICATION: this is a permanent structural condition, not a
#    transient fetch failure, so it must not be reported as one — "retry next
#    cycle" is a dead end here, and a fail-closed refusal whose named recovery
#    action cannot work is exactly what D-10 exists to prevent.
root=$(new_fixture worktree)
"$REAL_GIT" -C "$root/tower" worktree add --quiet -b planwright/demo/task-3 "$root/tower-wt" main
advance_origin "$root"
PW_GIT_LOG="$tmp/log8"
export PW_GIT_LOG
: >"$PW_GIT_LOG"
before=$("$REAL_GIT" -C "$root/tower" rev-parse main)
set +e
out=$(mc sync --checkout "$root/tower-wt" 2>&1)
rc=$?
set -e
[ "$rc" -ne 0 ] || fail "8: syncing from a worktree while main is checked out elsewhere must not report success"
[ "$rc" -ne 3 ] \
  || fail "8: a sibling-worktree checkout is permanent, not a transient fetch failure — 'retry next cycle' can never succeed"
[ "$rc" -eq 5 ] || fail "8: expected the sibling-worktree exit code 5, got $rc"
[ "$before" = "$("$REAL_GIT" -C "$root/tower" rev-parse main)" ] \
  || fail "8: main moved despite being checked out in a sibling worktree"
# The message must name the checkout that owns main, since pointing the sync
# there is the whole remedy.
printf '%s\n' "$out" | grep -q "$root/tower" \
  || fail "8: the refusal did not name the checkout that owns main: $out"
# ...and must quote it, or the remedy it hands the operator is one they cannot
# paste for a checkout whose path contains whitespace.
printf '%s\n' "$out" | grep -qF -- "--checkout '$root/tower'" \
  || fail "8: the suggested recovery command left the checkout path unquoted: $out"
assert_no_rewrite 8

# 9. A malformed `--main-ref` is refused BEFORE it reaches any git command, so a
#    crafted value cannot smuggle an option or redirect the refspec.
root=$(new_fixture grammar)
PW_GIT_LOG="$tmp/log9"
export PW_GIT_LOG
for bad in \
  "--upload-pack=touch /tmp/pwned" \
  "main:refs/heads/hijacked" \
  "main
evil" \
  "main~1" \
  "../../etc/main" \
  "main*" \
  "/main" \
  "/" \
  "+main" \
  "+" \
  "main@{1}" \
  "@" \
  "main." \
  "feat/.main" \
  "foo.lock/bar" \
  "main/.x" \
  ""; do
  : >"$PW_GIT_LOG"
  set +e
  out=$(mc sync --checkout "$root/tower" --main-ref "$bad" 2>&1)
  rc=$?
  set -e
  [ "$rc" -eq 2 ] \
    || fail "9: a malformed --main-ref must be a usage refusal (exit 2), got $rc for '$bad'"
  # The refusal has to land before git is invoked at all, not merely be caught
  # by git after the value was already handed to it.
  if [ -s "$PW_GIT_LOG" ] && grep -Eq '(^| )(fetch|merge|push)( |$)' "$PW_GIT_LOG"; then
    fail "9: a git ref operation ran despite a malformed --main-ref '$bad'"
  fi
  printf '%s\n' "$out" | grep -qi 'malformed\|usage' \
    || fail "9: the refusal was not surfaced for '$bad': $out"
  # No crafted value may leave a ref behind. A leading `+` used to slip the
  # grammar and be consumed by git as the refspec's FORCE modifier, fetching onto
  # a ref literally named `+main` — while every success signal fired and the real
  # `main` was never synced. A false success is worse than a refusal, so the
  # branch list is pinned, not just the exit code.
  refs_now=$("$REAL_GIT" -C "$root/tower" for-each-ref --format='%(refname)' refs/heads/ | tr '\n' ' ')
  [ "$refs_now" = "refs/heads/main " ] \
    || fail "9: '$bad' left a stray ref behind: $refs_now"
done
assert_no_rewrite 9

# 10. A DIRTY WORKING TREE on `main` is not divergence. git aborts the merge to
#     protect uncommitted changes, but `main` is still a clean fast-forward
#     behind origin — so reporting "diverged / unexpected local history" would
#     send the operator hunting a divergence that does not exist, when the fix is
#     simply to commit or stash. Same D-10 contract as the sibling-worktree case:
#     the named recovery action has to be one that works.
root=$(new_fixture dirty)
advance_origin "$root"
echo "uncommitted" >>"$root/tower/file.txt"
PW_GIT_LOG="$tmp/log10"
export PW_GIT_LOG
: >"$PW_GIT_LOG"
before=$("$REAL_GIT" -C "$root/tower" rev-parse main)
set +e
out=$(mc sync --checkout "$root/tower" 2>&1)
rc=$?
set -e
[ "$rc" -ne 0 ] || fail "10: a dirty working tree must not report a successful sync"
[ "$rc" -ne 4 ] || fail "10: a dirty working tree is not divergence — main is still a clean fast-forward behind origin"
[ "$rc" -eq 6 ] || fail "10: expected the dirty-tree exit code 6, got $rc"
[ "$before" = "$("$REAL_GIT" -C "$root/tower" rev-parse main)" ] \
  || fail "10: main moved despite the refusal"
printf '%s\n' "$out" | grep -qi 'commit\|stash' \
  || fail "10: the refusal did not name the actual remedy (commit or stash): $out"
# Match the CLAIM, not the word: the message legitimately contains "not a
# divergence", so grepping for the bare stem would flag its own disclaimer.
printf '%s\n' "$out" | grep -qi 'has diverged' \
  && fail "10: a dirty tree was misreported as a divergence: $out"
# The uncommitted change must still be there — the sync never discards work.
grep -q uncommitted "$root/tower/file.txt" \
  || fail "10: the uncommitted change was lost"
assert_no_rewrite 10

# 11. An UNTRACKED file the fast-forward would overwrite is the same class as
#     test 10, not a divergence: git aborts the merge to protect the file, but
#     `main` is still a clean fast-forward behind origin. `git diff` and
#     `git diff --cached` do not see untracked files, so the up-front dirty
#     check cannot catch this one — it has to be classified from the merge's own
#     refusal, or it lands in the divergence bucket and sends the operator after
#     history that does not exist.
#
#     The fixture deliberately does NOT pre-detect untracked files up front: a
#     blanket up-front check would refuse the sync over any unrelated build
#     artifact sitting in the tree, so only the file the fast-forward actually
#     collides with may block it.
root=$(new_fixture untracked)
(
  cd "$root/seed"
  echo brand-new >brand-new.txt
  "$REAL_GIT" add brand-new.txt
  "$REAL_GIT" commit --quiet -m "origin adds brand-new.txt"
  "$REAL_GIT" push --quiet origin main
)
echo "untracked local content" >"$root/tower/brand-new.txt"
PW_GIT_LOG="$tmp/log11"
export PW_GIT_LOG
: >"$PW_GIT_LOG"
before=$("$REAL_GIT" -C "$root/tower" rev-parse main)
set +e
out=$(mc sync --checkout "$root/tower" 2>&1)
rc=$?
set -e
[ "$rc" -ne 0 ] || fail "11: an untracked-file collision must not report a successful sync"
[ "$rc" -ne 4 ] \
  || fail "11: an untracked-file collision is not divergence — main is still a clean fast-forward behind origin"
[ "$rc" -eq 6 ] || fail "11: expected the dirty-tree exit code 6, got $rc"
[ "$before" = "$("$REAL_GIT" -C "$root/tower" rev-parse main)" ] \
  || fail "11: main moved despite the refusal"
printf '%s\n' "$out" | grep -qi 'has diverged' \
  && fail "11: an untracked-file collision was misreported as a divergence: $out"
printf '%s\n' "$out" | grep -qi 'move or remove\|untracked' \
  || fail "11: the refusal did not name the actual remedy: $out"
grep -q "untracked local content" "$root/tower/brand-new.txt" \
  || fail "11: the untracked file was overwritten"
# The surfaced git diagnostic must stay READABLE. sanitize_printable deletes
# control bytes, newlines included, so git's multi-line stderr has to be folded
# to spaces first or the last word of each line runs into the first of the next
# ("merge.AbortingUpdating"). Asserting the space is what pins the fold.
printf '%s\n' "$out" | grep -q 'merge\. Aborting' \
  || fail "11: git's multi-line stderr was not folded readably: $out"
assert_no_rewrite 11

# 12. A transport/permission failure whose stderr happens to contain the word
#     "rejected" is a TRANSIENT failure, not a divergence. Classifying it by a
#     bare "rejected" match reports unexpected local history that does not
#     exist, and tells the operator to resolve it — the dead end D-10 exists to
#     prevent. requirements.md pins the same split for the mirror fence-push
#     path: a permission error with no per-ref rejection is the transient,
#     retry-next-cycle path.
root=$(new_fixture authrejected)
(
  cd "$root/tower"
  "$REAL_GIT" checkout --quiet -b planwright/demo/task-4
)
"$REAL_GIT" -C "$root/tower" remote set-url origin "ssh://git@localhost/repo.git"
cat >"$tmp/fake-ssh" <<'EOF'
#!/bin/sh
echo "ERROR: The key you are authenticating with has been rejected by the server." >&2
exit 255
EOF
chmod +x "$tmp/fake-ssh"
PW_GIT_LOG="$tmp/log12"
export PW_GIT_LOG
: >"$PW_GIT_LOG"
before=$("$REAL_GIT" -C "$root/tower" rev-parse main)
set +e
out=$(GIT_SSH_COMMAND="$tmp/fake-ssh" mc sync --checkout "$root/tower" 2>&1)
rc=$?
set -e
[ "$rc" -ne 0 ] || fail "12: an unreachable origin must not report a successful sync"
[ "$rc" -ne 4 ] \
  || fail "12: an auth failure is not a divergence — 'resolve the unexpected history yourself' is unactionable here"
[ "$rc" -eq 3 ] || fail "12: expected the transient fail-closed exit code 3, got $rc"
[ "$before" = "$("$REAL_GIT" -C "$root/tower" rev-parse main)" ] \
  || fail "12: main moved despite a failed fetch"
printf '%s\n' "$out" | grep -qi 'has diverged' \
  && fail "12: a transport failure was misreported as a divergence: $out"
assert_no_rewrite 12

# 13. A BARE checkout has no work tree, so `git diff` cannot answer the
#     dirty-tree question at all — it exits non-zero because the operation is
#     invalid there, not because anything is uncommitted. Reading that as "you
#     have uncommitted changes, commit or stash" names a remedy that is
#     impossible in a repository with no working tree. With no index to
#     desynchronize, the ref-update path is both available and correct.
#     Reachability is low (a tower checkout is not normally bare), but the
#     misclassification is the same shape as tests 10 and 11.
root=$(new_fixture bare)
"$REAL_GIT" clone --quiet --bare "$root/origin.git" "$root/tower.git"
"$REAL_GIT" -C "$root/tower.git" remote set-url origin "$root/origin.git"
advance_origin "$root"
PW_GIT_LOG="$tmp/log13"
export PW_GIT_LOG
: >"$PW_GIT_LOG"
before=$("$REAL_GIT" -C "$root/tower.git" rev-parse main)
set +e
out=$(mc sync --checkout "$root/tower.git" 2>&1)
rc=$?
set -e
printf '%s\n' "$out" | grep -qi 'uncommitted changes' \
  && fail "13: a bare repository was reported as having uncommitted changes: $out"
[ "$rc" -eq 0 ] || fail "13: a bare checkout should sync via the ref-update path, got exit $rc: $out"
[ "$before" != "$("$REAL_GIT" -C "$root/tower.git" rev-parse main)" ] \
  || fail "13: main did not advance in the bare checkout"
[ "$("$REAL_GIT" -C "$root/tower.git" rev-parse main)" = "$("$REAL_GIT" -C "$root/origin.git" rev-parse main)" ] \
  || fail "13: main is not at origin/main after the bare-checkout sync"
assert_no_rewrite 13

# 14. An explicitly EMPTY `--checkout` is a usage error, not a silent fallback
#     to the current directory. The operator named a checkout; syncing a
#     different one than the one they named is the kind of quiet substitution
#     `--main-ref ""` is already refused for (test 9), so the two options hold
#     the same line.
root=$(new_fixture emptyarg)
PW_GIT_LOG="$tmp/log14"
export PW_GIT_LOG
: >"$PW_GIT_LOG"
set +e
out=$(cd "$root/tower" && mc sync --checkout "" 2>&1)
rc=$?
set -e
[ "$rc" -eq 2 ] || fail "14: an empty --checkout must be a usage refusal (exit 2), got $rc: $out"
if [ -s "$PW_GIT_LOG" ] && grep -Eq '(^| )(fetch|merge|push)( |$)' "$PW_GIT_LOG"; then
  fail "14: a git ref operation ran despite an empty --checkout"
fi
assert_no_rewrite 14

# 15. The solo path with NO local `main` ref at all — a fresh `git init` that
#     has never committed. The output contract says the `main` line is omitted
#     in exactly this case, so the omission needs a test or the contract's only
#     conditional branch goes unexercised.
mkdir -p "$tmp/solo-empty"
"$REAL_GIT" init --quiet --initial-branch=main "$tmp/solo-empty/tower"
PW_GIT_LOG="$tmp/log15"
export PW_GIT_LOG
: >"$PW_GIT_LOG"
out=$(mc sync --checkout "$tmp/solo-empty/tower") \
  || fail "15: an empty no-origin checkout must degrade to solo (exit 0): $out"
printf '%s\n' "$out" | grep -q 'solo' \
  || fail "15: sync did not report the solo flow: $out"
printf '%s\n' "$out" | grep -q '^main	' \
  && fail "15: the main line must be omitted when no main ref exists: $out"
assert_no_rewrite 15

# 16. An unrecognized merge refusal is TRANSIENT, not a divergence. A locked
#     index — another git process working in this checkout — is the everyday
#     instance: retrying next cycle is exactly the right recovery, while
#     "your history has diverged, go resolve it" is a diagnosis this path cannot
#     support and sends the operator after nothing. The check that matters is
#     that the unknown case is not filed under divergence.
root=$(new_fixture lockedindex)
advance_origin "$root"
: >"$root/tower/.git/index.lock"
PW_GIT_LOG="$tmp/log16"
export PW_GIT_LOG
: >"$PW_GIT_LOG"
before=$("$REAL_GIT" -C "$root/tower" rev-parse main)
set +e
out=$(mc sync --checkout "$root/tower" 2>&1)
rc=$?
set -e
[ "$rc" -ne 0 ] || fail "16: a refused fast-forward must not report success"
[ "$rc" -ne 4 ] \
  || fail "16: a locked index is not a divergence — it is retryable, and claiming divergent history sends the operator nowhere"
[ "$rc" -eq 3 ] || fail "16: expected the transient exit code 3, got $rc"
[ "$before" = "$("$REAL_GIT" -C "$root/tower" rev-parse main)" ] \
  || fail "16: main moved despite the refusal"
printf '%s\n' "$out" | grep -qi 'has diverged' \
  && fail "16: a locked index was misreported as a divergence: $out"
printf '%s\n' "$out" | grep -qi 'retry' \
  || fail "16: the refusal did not name the actual remedy (retry): $out"
rm -f "$root/tower/.git/index.lock"
assert_no_rewrite 16

# 17. A missing `git` is reported as a missing dependency, not as a malformed
#     `--main-ref`. The grammar check asks git itself whether a ref name is
#     legal, so without an up-front dependency check a `git` that is absent
#     returns 127, reads as "the value is malformed", and blames a perfectly
#     well-formed argument for the real problem.
#
#     The fixture builds a PATH carrying the shell utilities the script uses and
#     deliberately no git, rather than an empty one — an empty PATH would fail to
#     find the shell itself and prove nothing about this path.
nogit_bin="$tmp/nogit-bin"
mkdir -p "$nogit_bin"
for u in sh bash printf tr cat dirname pwd; do
  u_path=$(command -v "$u" 2>/dev/null) \
    || fail "17: cannot build the fixture PATH — '$u' is not on this PATH"
  ln -sf "$u_path" "$nogit_bin/$u"
done
if PATH="$nogit_bin" command -v git >/dev/null 2>&1; then
  fail "17: the fixture PATH still resolves git, so this scenario proves nothing"
fi
root=$(new_fixture nogit)
PW_GIT_LOG="$tmp/log17"
export PW_GIT_LOG
: >"$PW_GIT_LOG"
set +e
out=$(PATH="$nogit_bin" /bin/bash "$MC" sync --checkout "$root/tower" --main-ref main 2>&1)
rc=$?
set -e
[ "$rc" -eq 2 ] || fail "17: a missing git must be a usage refusal (exit 2), got $rc: $out"
printf '%s\n' "$out" | grep -qi 'git not found' \
  || fail "17: a missing git was not named as the cause: $out"
printf '%s\n' "$out" | grep -qi 'malformed' \
  && fail "17: a missing git was blamed on the --main-ref value: $out"

# 18. The REF-UPDATE path creates a local `main` that does not exist yet: with
#     HEAD detached, `current_branch` is empty, so the sync updates the ref
#     without a checkout — from nothing to origin's tip — and the output
#     contract reports the new oid.
root=$(new_fixture createmain)
"$REAL_GIT" -C "$root/tower" checkout --quiet --detach
"$REAL_GIT" -C "$root/tower" branch --quiet -D main
PW_GIT_LOG="$tmp/log18"
export PW_GIT_LOG
: >"$PW_GIT_LOG"
"$REAL_GIT" -C "$root/tower" rev-parse --verify --quiet refs/heads/main >/dev/null \
  && fail "18: the fixture still has a local main, so this scenario proves nothing"
out=$(mc sync --checkout "$root/tower") \
  || fail "18: sync failed when the local main did not exist yet: $out"
printf '%s\n' "$out" | grep -q '^sync	ref-update$' \
  || fail "18: a detached checkout must take the ref-update path: $out"
[ "$("$REAL_GIT" -C "$root/tower" rev-parse main)" = "$("$REAL_GIT" -C "$root/origin.git" rev-parse main)" ] \
  || fail "18: main was not created at origin/main"
printf '%s\n' "$out" | grep -q '^main	' \
  || fail "18: the main line must carry the newly created oid: $out"
assert_no_rewrite 18

# 19. The MERGE path creates a local `main` that does not exist yet: an unborn
#     `main` (HEAD -> refs/heads/main with no commit) is checked out, so the
#     sync merges — from nothing to origin's tip, still a fast-forward — and
#     the output contract reports the new oid.
root_dir="$tmp/unbornmain"
mkdir -p "$root_dir"
"$REAL_GIT" init --quiet --bare --initial-branch=main "$root_dir/origin.git"
"$REAL_GIT" init --quiet --initial-branch=main "$root_dir/seed"
"$REAL_GIT" -C "$root_dir/seed" remote add origin "$root_dir/origin.git"
(
  cd "$root_dir/seed"
  "$REAL_GIT" config user.email t@example.invalid
  "$REAL_GIT" config user.name Tester
  "$REAL_GIT" config commit.gpgsign false
  echo one >file.txt
  "$REAL_GIT" add file.txt
  "$REAL_GIT" commit --quiet -m "seed"
  "$REAL_GIT" push --quiet origin main
)
"$REAL_GIT" init --quiet --initial-branch=main "$root_dir/tower"
"$REAL_GIT" -C "$root_dir/tower" remote add origin "$root_dir/origin.git"
"$REAL_GIT" -C "$root_dir/tower" config user.email t@example.invalid
"$REAL_GIT" -C "$root_dir/tower" config user.name Tester
"$REAL_GIT" -C "$root_dir/tower" config commit.gpgsign false
PW_GIT_LOG="$tmp/log19"
export PW_GIT_LOG
: >"$PW_GIT_LOG"
[ "$("$REAL_GIT" -C "$root_dir/tower" symbolic-ref --short HEAD)" = "main" ] \
  || fail "19: the fixture HEAD must point at the unborn main"
out=$(mc sync --checkout "$root_dir/tower") \
  || fail "19: sync failed on an unborn main: $out"
printf '%s\n' "$out" | grep -q '^sync	fast-forward$' \
  || fail "19: an unborn checked-out main must take the merge path: $out"
[ "$("$REAL_GIT" -C "$root_dir/tower" rev-parse main)" = "$("$REAL_GIT" -C "$root_dir/origin.git" rev-parse main)" ] \
  || fail "19: main was not created at origin/main"
assert_no_rewrite 19

echo "PASS: test-main-currency.sh"
