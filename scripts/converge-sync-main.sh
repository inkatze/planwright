#!/usr/bin/env bash
# converge-sync-main.sh — merge `origin/main` into the current worker branch,
# once at the top of each `/execute-task` convergence pass, so the head the
# review sequence verifies is `main`-current
# (merge-currency-guard Task 3; D-4; REQ-B1.1, REQ-B1.2, REQ-B1.3, REQ-B1.6,
# REQ-D1.3, REQ-K1.1).
#
# NOT the head `/execute-task`'s own full-CI step ran on: that step runs before
# the Convergence section this sync opens, and the skill has no loop that
# re-runs it afterwards. The merged head is covered by whatever wider-suite runs
# the review sequence performs, so a pass that applies no fix can leave it with
# no suite run at all. That gap is a known contract drift against D-4's premise,
# recorded for the spec owner in the 2026-08-26 `converge-sync-ci-ordering`
# observation rather than decided here.
#
# Why this exists as a script and not as skill prose: REQ-B1.5. `/execute-task`
# invokes it in one line, its instruction body does not grow a paragraph, and
# the mechanism stays testable in isolation.
#
# WHAT IT MAY NOT DO. `git pull` is forbidden outright (REQ-B1.2): a global
# `branch.autosetuprebase=always` silently rewrites it into a rebase, and
# rebase — like amend, squash, and force-push — rewrites published history and
# breaks the content anchor (bootstrap REQ-J1.4). So the sync is always an
# explicit fetch followed by an explicit merge, and `merge.ff` is pinned to its
# default at the call site so an ambient `merge.ff=only` cannot turn a routine
# non-fast-forward sync into a failure that looks like a conflict.
#
# WHAT IT LEAVES BEHIND ON FAILURE. Every non-zero path leaves a tree the next
# invocation can retry from unchanged (REQ-B1.3): the dirty-tree and
# fetch-failure paths never start a merge, and the conflict path aborts the one
# it started. That is what makes the caller's halt-and-resume idempotent rather
# than wedged on a lingering MERGE_HEAD. The single exception is an abort that
# itself fails, which gets its own reason precisely because it is the one state
# a resume cannot assume is clean.
#
# WHY EACH FAILURE GETS ITS OWN REASON (REQ-B1.6, REQ-K1.1). The caller halts
# the unit to `Awaiting input` with whatever this prints, and the three causes
# need three different human actions: an unreachable remote is retried, a
# conflict is resolved by landing `origin/main`, a dirty tree is committed or
# discarded first. Collapsing any of them into a misreported "merge conflict"
# sends the human after the wrong thing.
#
# Usage: converge-sync-main.sh [<repo-dir>]      (default: the current directory)
#
# Output: one tagged TSV record on stdout, on success only:
#   sync<TAB><up-to-date|fast-forward|merged><TAB><head-sha>
# Failures print `converge-sync-main: <reason>: <message>` on stderr.
#
# Exit codes:
#   0  synced (already current, fast-forwarded, or merged)
#   2  usage — bad argument count, a target that is not a git work tree, or a
#      missing `git`/`tr` (reason `environment`)
#   3  dirty-tree — tracked-file changes, or a merge/rebase/cherry-pick already
#      in progress; no fetch is attempted
#   4  fetch-failed — `git fetch origin main` failed (unreachable remote, no
#      `origin`, no `main` on the remote, auth failure)
#   5  merge-conflict — an unresolvable merge, aborted; the tree is clean
#   6  merge-failed — a merge refused for a non-conflict reason (an untracked
#      file in the way, a config refusal); aborted if it had started
#   7  abort-failed — the merge failed AND `git merge --abort` failed; the tree
#      is NOT clean and a resume must not assume it is
#
# Portable bash 3.2 / BSD tooling; no fish/mise/tmux dependency (REQ-K1.5).
# No LLM and no model/API call anywhere in the decision path (REQ-D1.4): the
# logic is deterministic shell over local git state and one fetch.
set -u

LC_ALL=C
export LC_ALL
unset CDPATH

# A headless worker that hits a credential prompt would hang the whole
# convergence loop with no output. Failing the fetch fast, with a reason the
# caller can act on, is the better of the two. Credential helpers still work;
# only interactive terminal prompting is disabled.
GIT_TERMINAL_PROMPT=0
export GIT_TERMINAL_PROMPT

# ssh prompts on its own channel, which `GIT_TERMINAL_PROMPT` does not reach:
# an unverified host key or a passphrase-protected key would block the fetch
# just as hard as a credential prompt. `BatchMode=yes` turns both into a
# fetch-failed exit the caller can act on. The cost is deliberate and worth
# naming: first contact with a host absent from `known_hosts` now fails instead
# of asking, making that a setup step rather than something the sync completes.
# An agent-held key is unaffected, which is the fleet's normal case.
GIT_SSH_COMMAND="${GIT_SSH_COMMAND:-ssh} -o BatchMode=yes"
export GIT_SSH_COMMAND

# die <exit-code> <reason> <message> — the single failure surface. The reason
# token is what the caller greps for and what keeps the causes distinct
# (REQ-B1.6); the message is what a human reads (REQ-K1.1).
# printf, not echo: git's own stderr rides these messages and can carry
# backslashes, which some echo implementations would interpret.
die() {
  printf 'converge-sync-main: %s: %s\n' "$2" "$3" >&2
  exit "$1"
}

# scrub — strip control bytes from anything git or the filesystem hands back
# before it reaches a terminal, so a hostile branch name or path cannot smuggle
# escape sequences into the caller's output. TAB and LF are the only C0 bytes
# kept, because the output format is built from them; every other one goes,
# carriage return included — it needs no escape byte to overwrite the rendered
# line and forge a different message on top of a real one.
scrub() {
  tr -d '\000-\010\013-\037\177'
}

if [ "$#" -gt 1 ]; then
  die 2 usage "too many arguments; usage: converge-sync-main.sh [<repo-dir>]"
fi

# Probe the binaries before anything reads git state. Without this an absent
# `git` surfaces through the work-tree check below as "not a git work tree",
# which sends the human to inspect a directory that is fine; and an absent `tr`
# empties `scrub`'s output, dropping the path out of the very message meant to
# identify the problem. `die` is safe to use even here: it is printf and exit,
# and reaches for neither of the binaries being probed.
for bin in git tr; do
  command -v "$bin" >/dev/null 2>&1 \
    || die 2 environment "$bin is not on PATH; the sync cannot run"
done

# The target is echoed back in two failure messages, so it gets the same
# newline collapse the git-stderr paths below use: a message a human reads on a
# halt is one line, whatever the path it names contains.
repo="${1:-.}"
repo_shown=$(printf '%s' "$repo" | tr '\n' ' ' | scrub)
[ -d "$repo" ] || die 2 usage "target directory not found: $repo_shown"

# `--is-inside-work-tree` prints `false` inside a bare repo's git dir, where
# there is nothing to merge into, so the value is checked rather than just the
# exit status.
inside=$(git -C "$repo" rev-parse --is-inside-work-tree 2>/dev/null || true)
[ "$inside" = true ] \
  || die 2 usage "not a git work tree: $repo_shown"

# --- pre-flight: the tree must be clean BEFORE the network -------------------
#
# Ordering is deliberate. A dirty tree is a dirty tree whether or not the remote
# answers, and checking it first means the sync never spends a fetch to
# rediscover that, and never reports a fetch failure for a run it was going to
# refuse anyway.

for state in MERGE_HEAD REBASE_HEAD CHERRY_PICK_HEAD REVERT_HEAD; do
  if git -C "$repo" rev-parse -q --verify "$state" >/dev/null 2>&1; then
    die 3 dirty-tree "an operation is already in progress ($state exists) — finish or abort it before the sync can merge origin/main"
  fi
done

# Untracked files are deliberately excluded: they cannot make a merge ambiguous
# on paths the merge does not touch, and a worker's scratch output is not a
# reason to halt a unit. An untracked file that IS in the merge's way surfaces
# on the merge itself, as `merge-failed` — its own reason, not this one.
dirty=$(git -C "$repo" status --porcelain --untracked-files=no 2>/dev/null || true)
if [ -n "$dirty" ]; then
  count=$(printf '%s\n' "$dirty" | grep -c '' || true)
  die 3 dirty-tree "the working tree has $count uncommitted tracked change(s) — commit or discard them before the sync can merge origin/main"
fi

# --- fetch -------------------------------------------------------------------
#
# The remote and branch are literal: D-4 targets `origin/main` specifically, the
# worker-convergence base by planwright convention. A PR on some other base is
# the ready-guard's job, which reads each PR's real base server-side and needs
# no per-base handling here.

fetch_err=$(git -C "$repo" fetch origin main 2>&1 >/dev/null) || {
  die 4 fetch-failed "git fetch origin main failed — the remote is unreachable, absent, or refused the read: $(printf '%s' "$fetch_err" | tr '\n' ' ' | scrub)"
}

target=$(git -C "$repo" rev-parse --verify FETCH_HEAD 2>/dev/null || true)
[ -n "$target" ] \
  || die 4 fetch-failed "git fetch origin main left no FETCH_HEAD to merge"

# --- merge -------------------------------------------------------------------

# Already current: FETCH_HEAD is in the branch's history, so there is nothing to
# merge. This is the modal outcome on a quiet `main` and must stay a clean
# no-op — it neither moves the head nor makes an empty commit.
if git -C "$repo" merge-base --is-ancestor "$target" HEAD 2>/dev/null; then
  head=$(git -C "$repo" rev-parse HEAD)
  printf 'sync\tup-to-date\t%s\n' "$head"
  exit 0
fi

# Classified before the merge runs, because afterwards the two are
# indistinguishable from the resulting history alone.
kind=merged
if git -C "$repo" merge-base --is-ancestor HEAD "$target" 2>/dev/null; then
  kind=fast-forward
fi

# `--no-edit` so a tty-attached run never blocks on an editor (D-4).
# `-c merge.ff=true` pins the default at the call site: an ambient
# `merge.ff=only` would otherwise refuse every real merge, and `merge.ff=false`
# would manufacture a merge commit for a fast-forward that needs none.
merge_err=$(git -C "$repo" -c merge.ff=true merge --no-edit FETCH_HEAD 2>&1 >/dev/null) || {
  # `diff --diff-filter=U`, not `ls-files --unmerged`: it prints one path per
  # line already deduplicated across the three stages, so a path containing a
  # space survives into the message intact instead of being cut at the first
  # field.
  unmerged=$(git -C "$repo" diff --name-only --diff-filter=U 2>/dev/null)

  # Abort whatever the merge left behind, before reporting. A conflict that is
  # not aborted leaves MERGE_HEAD in place and the NEXT sync fails on the stale
  # merge instead of the real cause (REQ-B1.3).
  if git -C "$repo" rev-parse -q --verify MERGE_HEAD >/dev/null 2>&1; then
    git -C "$repo" merge --abort >/dev/null 2>&1 \
      || die 7 abort-failed "the origin/main merge failed AND git merge --abort could not undo it — the working tree is NOT clean and must be repaired by hand before this unit resumes"
  fi

  if [ -n "$unmerged" ]; then
    paths=$(printf '%s\n' "$unmerged" | head -10 | tr '\n' ' ' | scrub)
    more=$(printf '%s\n' "$unmerged" | grep -c '' || true)
    if [ "$more" -gt 10 ]; then
      paths="$paths(and $((more - 10)) more) "
    fi
    die 5 merge-conflict "origin/main conflicts with this branch on: ${paths}— the merge was aborted and the tree is clean; land origin/main's changes here (or resolve upstream) before convergence resumes"
  fi

  die 6 merge-failed "the origin/main merge was refused for a non-conflict reason: $(printf '%s' "$merge_err" | tr '\n' ' ' | scrub)"
}

head=$(git -C "$repo" rev-parse HEAD)
printf 'sync\t%s\t%s\n' "$kind" "$head"
exit 0
