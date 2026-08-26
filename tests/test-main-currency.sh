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
# exec it without recursing into itself.
REAL_GIT=$(command -v git) || fail "git not on PATH"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

shim_dir="$tmp/shim"
mkdir -p "$shim_dir"
cat >"$shim_dir/git" <<EOF
#!/bin/sh
# Command-level recorder: log the argv, then behave exactly like git.
printf '%s\n' "\$*" >>"\$PW_GIT_LOG"
exec $REAL_GIT "\$@"
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

echo "PASS: test-main-currency.sh"
