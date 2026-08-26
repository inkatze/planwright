#!/bin/sh
# main-currency.sh — keep a per-tower checkout's private `main` current with
# `origin`, by fetch-then-fast-forward only
# (concurrent-orchestrator-coordination Task 3: D-3, D-10 · REQ-B1.2, REQ-B1.4).
#
# WHAT THIS IS. Under the per-tower-checkout topology (docs/per-tower-checkouts.md)
# each tower owns a SEPARATE clone with its own private mutable local `main`, and
# the towers coordinate through `origin` rather than through a shared local
# `main`. That removes the clobbering race at its root, but it leaves each tower
# responsible for keeping its own `main` current. This script is that one path,
# so the discipline lives in a single tested place instead of being re-derived at
# every call site.
#
# THE THREE HARDENINGS (REQ-B1.4). Each exists because of a specific way the
# obvious implementation goes wrong:
#
#   1. FAST-FORWARD ONLY, AND NEVER A BARE `git pull`. A private `main` is never
#      directly committed to — commits ride task branches and reach `origin` by
#      PR — so currency is ALWAYS a fast-forward, and `--ff-only` costs nothing
#      on the happy path while turning any unexpected divergence into an explicit
#      refusal instead of a silent merge commit. The explicit `fetch` + `merge
#      --ff-only` form is also what neutralizes `branch.autosetuprebase=always`
#      (and `pull.rebase`), under which a bare `git pull` silently becomes a
#      REBASE — a history rewrite the never-rewrite floor forbids. Note that a
#      fast-forward merge and such a rebase leave an IDENTICAL graph, so this
#      hardening is only ever verifiable at the command level; that is exactly
#      how tests/test-main-currency.sh asserts it.
#
#   2. NEVER A BARE MERGE ONTO A WORKER BRANCH. `git merge FETCH_HEAD` merges
#      into whatever is currently checked out, so running the sync from a worker
#      branch would drag `origin/main` onto that branch — the "foreign commits on
#      a worker branch" hazard `orchestration-concurrency` already fenced off. So
#      the operation is chosen by what is checked out: with `main` checked out it
#      is `git fetch origin main` + `git merge --ff-only FETCH_HEAD`; otherwise it
#      is `git fetch origin main:main`, a ref update that touches the `main` ref
#      without a checkout and refuses a non-fast-forward BY NATURE (git rejects a
#      non-ff ref update on a local branch ref unless forced, and nothing here
#      forces).
#
#   3. A FETCH FAILURE IS CLASSIFIED BEFORE ACTING (D-10). A blanket "a failed
#      fetch fails closed" would mis-treat the legitimate no-remote case as an
#      error, so the two are split:
#        * NO `origin` CONFIGURED — a configuration state, not a failure. There
#          is no cross-clone currency to maintain and no multi-tower posture to
#          hold, so the tower runs the single-checkout SOLO flow and this script
#          reports `solo` and exits 0.
#        * A TRANSIENT FETCH FAILURE AGAINST A CONFIGURED `origin` — fail closed.
#          Surface it and leave `main` where it is; proceeding would run the
#          tower on a silently-stale `main`. Retry on the next cycle.
#      A `--ff-only` refusal is its own third outcome: surfaced for the operator,
#      never resolved by force, rebase, or reset.
#
# WHAT IT NEVER DOES. No `git pull`, no rebase, no `reset --hard`, no `--amend`,
# no force-push, and no push to `main` at all: currency flows origin→local only,
# because a per-tower `main` never originates commits. Those absences are
# asserted at the command level by the fixture, not merely stated here.
#
# OUTPUT. Tab-separated verdict lines on stdout, machine-readable by a caller:
#   origin	absent|configured
#   sync	solo|up-to-date|fast-forward|ref-update
#   main	<oid>                (omitted on the solo path when no main ref exists)
# Failures are surfaced on stderr.
#
# EXIT CODES:
#   0  synced (or already current), or the legitimate no-origin solo flow
#   2  usage error
#   3  fail closed: a fetch failure against a configured `origin` — `main` is
#      unmoved and possibly stale; do not proceed on it, retry next cycle
#   4  divergence: the fast-forward was refused because local `main` is not an
#      ancestor of `origin/main`; surface for the operator, never force
#   5  `main` is checked out in a sibling worktree of this clone, so its ref
#      cannot be updated from here; permanent, not transient — run the sync in
#      that checkout instead (named in the message)
#
# USAGE:
#   main-currency.sh sync [--checkout <dir>] [--main-ref <branch>]
set -eu
LC_ALL=C
export LC_ALL
unset CDPATH

script_dir=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=scripts/echo-safety.sh
. "$script_dir/echo-safety.sh"

err() {
  echo "main-currency: $1" >&2
}

usage() {
  cat >&2 <<'USAGE'
usage: main-currency.sh sync [--checkout <dir>] [--main-ref <branch>]
  --checkout  the tower checkout to sync (default: the current directory)
  --main-ref  the branch carrying trunk (default: main)
USAGE
}

# The branch-name grammar, validated BEFORE the value reaches any git command
# (REQ-D1.5 discipline): a crafted `--main-ref` must not be able to smuggle an
# option or a refspec separator into the fetch.
is_branch_name() {
  case "$1" in
    # A leading dash would be read as an option by the git commands below.
    "" | -*) return 1 ;;
    # A refspec separator, a glob, or revision metacharacters would change
    # which ref the fetch names.
    *:* | *'?'* | *'*'* | *'['* | *'~'* | *'^'*) return 1 ;;
    # Path traversal and malformed ref shapes.
    *..* | */ | */*/* | *.lock) return 1 ;;
    *\\* | *' '*) return 1 ;;
  esac
  # Catches every C0 control character (tab and newline included) plus DEL.
  [ "$(printf '%s' "$1" | tr -d '\000-\037\177')" = "$1" ] || return 1
  return 0
}

cmd=${1-}
[ -n "$cmd" ] || {
  usage
  exit 2
}
shift

case "$cmd" in
  sync) ;;
  -h | --help)
    usage
    exit 0
    ;;
  *)
    err "unknown subcommand '$(sanitize_printable "$cmd")'"
    usage
    exit 2
    ;;
esac

checkout=""
main_ref="main"
while [ $# -gt 0 ]; do
  case "$1" in
    --checkout)
      [ $# -ge 2 ] || {
        err "--checkout needs a value"
        exit 2
      }
      checkout=$2
      shift 2
      ;;
    --main-ref)
      [ $# -ge 2 ] || {
        err "--main-ref needs a value"
        exit 2
      }
      main_ref=$2
      shift 2
      ;;
    *)
      err "unexpected argument '$(sanitize_printable "$1")'"
      usage
      exit 2
      ;;
  esac
done

is_branch_name "$main_ref" || {
  err "refusing a malformed --main-ref '$(sanitize_printable "$main_ref")'"
  exit 2
}

if [ -n "$checkout" ]; then
  [ -d "$checkout" ] || {
    err "no such checkout directory '$(sanitize_printable "$checkout")'"
    exit 2
  }
  cd "$checkout" || {
    err "cannot enter '$(sanitize_printable "$checkout")'"
    exit 2
  }
fi

git rev-parse --git-dir >/dev/null 2>&1 || {
  err "not a git checkout: $(sanitize_printable "$(pwd)")"
  exit 2
}

# --- Classify origin reachability BEFORE any fetch (D-10) -------------------

if ! git remote get-url origin >/dev/null 2>&1; then
  # The genuine no-remote posture: a single-checkout solo tower. There is no
  # cross-clone currency to maintain, so this is a healthy state, not an error.
  # Nothing is fetched — a fetch here would fail for a reason that means nothing.
  printf 'origin\tabsent\n'
  printf 'sync\tsolo\n'
  if solo_oid=$(git rev-parse --verify --quiet "refs/heads/$main_ref" 2>/dev/null); then
    printf 'main\t%s\n' "$solo_oid"
  fi
  exit 0
fi
printf 'origin\tconfigured\n'

before=$(git rev-parse --verify --quiet "refs/heads/$main_ref" 2>/dev/null) || before=""

current_branch=$(git symbolic-ref --quiet --short HEAD 2>/dev/null) || current_branch=""

if [ "$current_branch" = "$main_ref" ]; then
  # `main` is checked out: the explicit fetch-then-fast-forward-merge form.
  # NEVER `git pull`, whose rebase-on-pull configs would rewrite history here.
  if ! fetch_err=$(git fetch origin "$main_ref" 2>&1); then
    err "fetch of origin/$main_ref failed against a configured origin; leaving $main_ref unmoved rather than proceeding on a possibly-stale main — retry next cycle"
    err "git said: $(sanitize_printable "$fetch_err")"
    exit 3
  fi
  if ! merge_err=$(git merge --ff-only FETCH_HEAD 2>&1); then
    err "$main_ref has diverged from origin/$main_ref — the fast-forward was refused"
    err "git said: $(sanitize_printable "$merge_err")"
    err "a per-tower $main_ref should only ever fast-forward, so this is unexpected local history; resolve it yourself — this path will never force, rebase, or reset"
    exit 4
  fi
  after=$(git rev-parse --verify "refs/heads/$main_ref")
  if [ "$before" = "$after" ]; then
    printf 'sync\tup-to-date\n'
  else
    printf 'sync\tfast-forward\n'
  fi
  printf 'main\t%s\n' "$after"
  exit 0
fi

# A worker branch (or a detached HEAD) is checked out here. Before reaching for
# the ref update, rule out the one case where it can never work: `main` checked
# out in a SIBLING WORKTREE of this same clone. git refuses to update a branch
# ref that is checked out anywhere, and is right to — moving it would
# desynchronize that worktree's index. That refusal is permanent and structural,
# so it must not be reported as a transient fetch failure: telling the operator
# to retry names a recovery action that cannot succeed, which is the dead end
# D-10 exists to prevent. The action that does work is running the sync in the
# checkout that owns `main`, where it takes the fast-forward merge path — so
# name that checkout.
main_worktree=$(git worktree list --porcelain 2>/dev/null | awk -v want="branch refs/heads/$main_ref" '
  /^worktree /{ path = substr($0, 10) }
  $0 == want { print path; exit }
')
if [ -n "$main_worktree" ]; then
  err "$main_ref is checked out in another worktree of this clone ($(sanitize_printable "$main_worktree")), so its ref cannot be updated from here — this is permanent, not a transient failure, and retrying will not change it"
  err "run the sync in that checkout instead, where it fast-forwards $main_ref directly: main-currency.sh sync --checkout $(sanitize_printable "$main_worktree")"
  exit 5
fi

# Update the `main` REF without a checkout. This refspec has no leading `+` and
# no --force, so git refuses a non-fast-forward by nature — the ff-only guarantee
# comes from the refspec's own shape here, not from a separate flag.
if ! fetch_err=$(git fetch origin "$main_ref:$main_ref" 2>&1); then
  # Two failures share this exit path, so classify them by whether origin was
  # reachable at all: a non-fast-forward rejection means the fetch itself worked.
  case "$fetch_err" in
    *'non-fast-forward'* | *'non-fast forward'* | *'rejected'*)
      err "the $main_ref ref update was rejected as a non-fast-forward — $main_ref has diverged from origin/$main_ref"
      err "git said: $(sanitize_printable "$fetch_err")"
      err "a per-tower $main_ref should only ever fast-forward, so this is unexpected local history; resolve it yourself — this path will never force, rebase, or reset"
      exit 4
      ;;
  esac
  err "fetch of origin/$main_ref failed against a configured origin; leaving $main_ref unmoved rather than proceeding on a possibly-stale main — retry next cycle"
  err "git said: $(sanitize_printable "$fetch_err")"
  exit 3
fi

after=$(git rev-parse --verify "refs/heads/$main_ref")
if [ "$before" = "$after" ]; then
  printf 'sync\tup-to-date\n'
else
  printf 'sync\tref-update\n'
fi
printf 'main\t%s\n' "$after"
exit 0
