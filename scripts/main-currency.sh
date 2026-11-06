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
#      the operation is chosen by what is checked out, AND by whether there is a
#      work tree at all: with `main` checked out in a real work tree it is
#      `git fetch origin main` + `git merge --ff-only FETCH_HEAD`; otherwise (a
#      worker branch, a detached HEAD, or a BARE checkout, which points HEAD at
#      `main` but has no tree to merge into) it is `git fetch origin main:main`, a
#      ref update that touches the `main` ref without a checkout and refuses a
#      non-fast-forward BY NATURE (git rejects a non-ff ref update on a local
#      branch ref unless forced, and nothing here forces).
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
#      Which of the three a failure IS gets decided on git's stated reason, never
#      on a word that several reasons share. A non-fast-forward is matched on the
#      reason git names (`(non-fast-forward)`), not on the bare "rejected" that
#      also appears in credential and transport failures — those never reached the
#      ref, so they are transient and retryable, and calling them divergence would
#      send the operator after local history that does not exist.
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
#   3  fail closed, transient: a fetch failure against a configured `origin`, or
#      a fast-forward refused for a reason that is not divergence (a locked index,
#      a full disk, a permission error) — `main` is unmoved and possibly stale; do
#      not proceed on it, retry next cycle. The unclassifiable case lands here
#      rather than on 4, since "retry" is the recovery an unknown refusal has
#      actually earned and "you have divergent history" is not.
#   4  divergence: the fast-forward was refused because local `main` is not an
#      ancestor of `origin/main`; surface for the operator, never force
#   5  `main` is checked out in a sibling worktree of this clone, so its ref
#      cannot be updated from here; permanent, not transient — run the sync in
#      that checkout instead (named in the message)
#   6  the fast-forward would overwrite local work — either uncommitted changes
#      to tracked files, or untracked files the incoming commits also add; NOT a
#      divergence — commit, stash, or move the files, then re-run
#
# Exits 3-6 are all fail-closed: `main` is left exactly where it was, and each
# names a recovery action that actually works for its case (D-10). Distinguishing
# them is the point — a dirty tree reported as "divergence", or a permanent
# structural refusal reported as "retry next cycle", sends the operator after a
# problem they do not have.
#
# FF-PRIMARY. The narrower verb a launched tower or worker session runs, in
# place of the raw `git merge --ff-only` its policy guard refuses, to bring a
# primary checkout's default branch up to origin with no operator. It moves
# only the primary checkout (named by --checkout, which must be that
# checkout's top level, or by default the primary of the repository holding
# the current directory, so a linked worktree reaches its own primary), only
# the branch origin's HEAD names as origin reports it now, only with no
# uncommitted tracked change and no operation in progress, and only by a pure
# fast-forward to the fetched commit. Every move is appended to
# <git-common-dir>/planwright/main-currency.log as one tab-separated line:
# UTC time, `ff-primary`, checkout, branch, old oid (empty when the branch
# was unborn), new oid, actor (PLANWRIGHT_WORKER_HANDLE, else
# PLANWRIGHT_TOWER_ID, else `unknown`); git's reflog carries it too. Output
# is sync's, its `main` line carrying the default branch's oid whatever that
# branch is called, plus:
#   checkout	<primary checkout>
#   branch	<origin's default branch>
#   record	<log path>|unwritten   (only after a move)
# Exits as sync does (3 also covers asking origin for its default branch and
# a git read error, 4 a local history origin lacks, 6 also an operation in
# progress), plus:
#   7  a shape it refuses: --checkout naming anything but a primary
#      checkout's top level, a bare repository, a checkout path holding a
#      control character, another branch or a detached HEAD checked out, no
#      resolvable default branch, or an unwritable record
#
# Usage:
#   main-currency.sh sync [--checkout <dir>] [--main-ref <branch>]
#   main-currency.sh ff-primary [--checkout <dir>]
set -eu
LC_ALL=C
export LC_ALL
unset CDPATH

script_dir=$(cd "$(dirname "$0")" && pwd)
if [ ! -f "$script_dir/echo-safety.sh" ] || [ ! -r "$script_dir/echo-safety.sh" ]; then
  printf '%s\n' "main-currency.sh: echo-safety.sh is missing or unreadable (broken install)" >&2
  exit 2
fi
# shellcheck source=scripts/echo-safety.sh
. "$script_dir/echo-safety.sh"

err() {
  printf 'main-currency: %s\n' "$1" >&2
}

# Fold git's multi-line stderr onto one line BEFORE it reaches
# sanitize_printable, which deletes control bytes outright — newlines included.
# Deleting them runs the last word of each line into the first of the next
# ("...before you merge.AbortingUpdating abc..def"), and these diagnostics are
# the whole operator-facing product of the classification work below.
fold_lines() {
  printf '%s' "$1" | tr '\n\t' '  ' | tr -s ' '
}

# Every failure path surfaces git's own words under this prefix, so the folding
# and the sanitizing stay in one place rather than being paired correctly at
# four separate call sites.
err_git_said() {
  err "git said: $(sanitize_printable "$(fold_lines "$1")")"
}

# Quote a value for a command line we are handing an operator to paste.
# sanitize_printable answers a different question — it strips control bytes so
# the value cannot drive the terminal — and says nothing about the shell's own
# metacharacters. Single quotes cover whitespace and the rest of them; the one
# character they cannot cover is a single quote, legal in a POSIX path, which is
# closed, escaped, and reopened in the standard way. Apply this to the sanitized
# value, so the two concerns compose rather than one undoing the other.
# Done with parameter expansion rather than a sed substitution on purpose: the
# replacement text would itself be a backslash-and-quote thicket read through
# two levels of quoting, which is the very kind of construct this function
# exists to stop getting wrong.
shell_quote() {
  _sq_rest=$1
  _sq_done=''
  while :; do
    case $_sq_rest in
      *\'*)
        _sq_done="$_sq_done${_sq_rest%%\'*}'\\''"
        _sq_rest=${_sq_rest#*\'}
        ;;
      *) break ;;
    esac
  done
  printf "'%s'" "$_sq_done$_sq_rest"
}

usage() {
  cat >&2 <<'USAGE'
usage: main-currency.sh sync [--checkout <dir>] [--main-ref <branch>]
       main-currency.sh ff-primary [--checkout <primary checkout>]
  --checkout  sync: the tower checkout to sync (default: the current directory)
              ff-primary: the primary checkout (default: the primary checkout
              of the repository holding the current directory)
  --main-ref  the branch carrying trunk (default: main); sync only
USAGE
}

# The branch-name grammar, validated BEFORE the value can reach any ref-mutating
# or network operation (REQ-D1.5 discipline): a crafted `--main-ref` must not be
# able to smuggle an option or a refspec separator into the fetch. Validation
# does end in one git command, `check-ref-format` below, but it is purely
# syntactic — no repository, no ref touched, no remote contacted.
is_branch_name() {
  case "$1" in
    # A leading dash would be read as an option by the git commands below, and a
    # leading PLUS is read by git as the refspec's force modifier rather than as
    # part of the ref name: `+main:+main` fetches `main` onto a ref literally
    # named `+main`, forcing it, and leaves the real `main` untouched while every
    # success signal here still fires. Note that `refs/heads/+main` is a legal
    # ref name, so `git check-ref-format` does not catch this — the hazard is the
    # `+`'s POSITION in a refspec, which only this grammar can rule out.
    "" | -* | +*) return 1 ;;
    # A refspec separator, a glob, or revision metacharacters would change
    # which ref the fetch names.
    *:* | *'?'* | *'*'* | *'['* | *'~'* | *'^'*) return 1 ;;
    # Path traversal and malformed ref shapes. A LEADING slash is refused for
    # the same reason as a trailing one, and matching the sibling grammar in
    # scripts/ready-guard.sh: git rejects `/main:/main` as an invalid refspec,
    # and a fetch that fails for a malformed argument would otherwise be
    # classified as a transient failure and retried forever.
    #
    # Revision syntax (`@{...}`, a bare `@` for HEAD) and the shapes git's own
    # ref grammar forbids (a trailing dot, a `.lock` suffix) are refused here for
    # exactly that reason: each one makes the fetch fail on a PERMANENT input
    # error, which the classifier downstream would otherwise surface as
    # "retry next cycle" — a recovery that can never succeed.
    *..* | /* | */ | */*/* | *.lock | *'@{'* | @ | *.) return 1 ;;
    *\\* | *' '*) return 1 ;;
  esac
  # Catches every C0 control character (tab and newline included) plus DEL.
  [ "$(printf '%s' "$1" | tr -d '\000-\037\177')" = "$1" ] || return 1
  # Then git's OWN ref grammar, as the backstop for everything above that this
  # list does not try to encode: dot-led path components, `.lock` segments, and
  # whatever a later git tightens. Hand-maintaining that against git's
  # per-component rules is a losing game — a value git rejects fails the fetch as
  # a PERMANENT error, which the classifier downstream would then surface as
  # "retry next cycle", a recovery that can never succeed. Purely syntactic, so
  # it needs no repository and runs before this script has entered one.
  #
  # It cannot REPLACE the checks above, only extend them: `refs/heads/+main` and
  # `refs/heads/@` are both perfectly legal ref names. The checks above are about
  # what the value does in ARGUMENT and REFSPEC position, which git's validator
  # has no way to know; this call is about whether it names a ref at all.
  git check-ref-format "refs/heads/$1" 2>/dev/null || return 1
  return 0
}

# --- ff-primary --------------------------------------------------------------
# The contract is the FF-PRIMARY paragraph of the header.
ff_refuse() {
  err "$1"
  exit 7
}

ff_primary() {
  ffp_checkout=''
  while [ $# -gt 0 ]; do
    case "$1" in
      --checkout)
        [ $# -ge 2 ] && [ -n "$2" ] || {
          err "--checkout needs a value"
          exit 2
        }
        ffp_checkout=$2
        shift 2
        ;;
      *)
        err "unexpected argument '$(sanitize_printable "$1")'"
        usage
        exit 2
        ;;
    esac
  done
  command -v git >/dev/null 2>&1 || {
    err "git not found on PATH; this fast-forward is a git operation and cannot run without it"
    exit 2
  }
  # An inherited repository pointer (a caller running inside a git hook)
  # would keep every command below on that repository whatever directory
  # this enters.
  unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY
  if [ -n "$ffp_checkout" ]; then
    if ! [ -d "$ffp_checkout" ] || ! cd -- "$ffp_checkout"; then
      err "cannot enter checkout directory '$(sanitize_printable "$ffp_checkout")'"
      exit 2
    fi
  fi
  [ "$(git rev-parse --is-bare-repository 2>/dev/null)" != true ] \
    || ff_refuse "$(sanitize_printable "$(pwd)") is a bare repository, which has no checkout to fast-forward"
  if ! common=$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null) \
    || ! gitdir=$(git rev-parse --path-format=absolute --git-dir 2>/dev/null); then
    err "not a git checkout: $(sanitize_printable "$(pwd)")"
    exit 2
  fi
  # Checked on the git directory's path, before any $(...) strips a trailing
  # newline that would turn the path into a sibling's: the checkout's path is
  # printed and recorded as a tab-separated field. The byte range is
  # sanitize_printable's.
  [ "$(printf '%s' "$common" | tr -d '\000-\037\177\200-\237')" = "$common" ] \
    || ff_refuse "the repository's path holds a control character, which this verb's output and record lines cannot carry"
  case $common in
    */.git) primary=${common%/.git} ;;
    *) ff_refuse "the repository's git directory ($(sanitize_printable "$common")) is not a checkout's .git, so there is no primary checkout to fast-forward" ;;
  esac
  primary=$(cd -P -- "$primary" 2>/dev/null && pwd -P) \
    || ff_refuse "the primary checkout of this repository could not be entered"
  if [ -n "$ffp_checkout" ]; then
    # git walks up from a directory that is not a top level, so a named
    # directory inside some other repository would reach that repository;
    # inside a .git directory there is no top level at all.
    ffp_top=$(git rev-parse --show-toplevel 2>/dev/null) || ffp_top=''
    if [ -n "$ffp_top" ]; then
      ffp_top=$(cd -P -- "$ffp_top" 2>/dev/null && pwd -P) || ffp_top=''
    fi
    if [ -z "$ffp_top" ] || [ "$gitdir" != "$common" ] || [ "$ffp_top" != "$(pwd -P)" ]; then
      ff_refuse "$(sanitize_printable "$ffp_checkout") is not a primary checkout's top level, and this verb moves only a primary checkout's default branch; name the primary checkout itself (for this repository: main-currency.sh ff-primary --checkout $(shell_quote "$(sanitize_printable "$primary")"))"
    fi
  fi
  cd -- "$primary" || ff_refuse "the primary checkout $(sanitize_printable "$primary") could not be entered"
  [ "$(git rev-parse --is-inside-work-tree 2>/dev/null)" = true ] \
    || ff_refuse "the primary checkout $(sanitize_printable "$primary") has no work tree to fast-forward"

  if ! git remote get-url origin >/dev/null 2>&1; then
    printf 'origin\tabsent\n'
    printf 'checkout\t%s\n' "$primary"
    printf 'sync\tsolo\n'
    exit 0
  fi
  printf 'origin\tconfigured\n'
  printf 'checkout\t%s\n' "$primary"

  # Asked of origin every run: the local refs/remotes/origin/HEAD goes stale
  # when origin renames its default branch, and any worktree of the clone
  # can rewrite it.
  if ! lsr=$(GIT_TERMINAL_PROMPT=0 git ls-remote --symref origin HEAD 2>&1); then
    err "could not ask origin for its default branch; every branch is unmoved — retry next cycle"
    err_git_said "$lsr"
    exit 3
  fi
  default=$(printf '%s\n' "$lsr" | awk -F '\t' '$2 == "HEAD" && index($1, "ref: refs/heads/") == 1 { print substr($1, 17); exit }')
  is_branch_name "$default" \
    || ff_refuse "origin's default branch could not be resolved (got '$(sanitize_printable "$default")'), so there is no branch this verb may move"
  printf 'branch\t%s\n' "$default"

  rec_dir="$common/planwright"
  rec="$rec_dir/main-currency.log"
  { mkdir -p -- "$rec_dir" 2>/dev/null && [ -w "$rec_dir" ] && { [ ! -e "$rec" ] || [ -w "$rec" ]; }; } \
    || ff_refuse "the act record $(sanitize_printable "$rec") is not writable, so the fast-forward is refused rather than left unrecorded"

  if ! fetch_err=$(GIT_TERMINAL_PROMPT=0 git fetch --no-write-fetch-head origin "+refs/heads/$default:refs/remotes/origin/$default" 2>&1); then
    err "fetch of origin/$default failed; $default is unmoved — retry next cycle"
    err_git_said "$fetch_err"
    exit 3
  fi
  target=$(git rev-parse --verify --quiet "refs/remotes/origin/$default^{commit}") || {
    err "origin/$default does not resolve to a commit after the fetch; $default is unmoved — retry next cycle"
    exit 3
  }

  # The checkout checks run after the fetch, the slow step, so they describe
  # the checkout the merge below meets. Operations come first: a rebase or a
  # bisect detaches HEAD, and its remedy is to finish it, not to switch.
  for op in MERGE_HEAD CHERRY_PICK_HEAD REVERT_HEAD sequencer rebase-merge rebase-apply BISECT_LOG; do
    if [ -e "$common/$op" ]; then
      err "an operation is in progress in the primary checkout ($op), so $default is not clean — refusing"
      err "finish or abort it there, then re-run; nothing here discards your work"
      exit 6
    fi
  done
  ffp_rc=0
  cur=$(git symbolic-ref --quiet --short HEAD 2>/dev/null) || ffp_rc=$?
  case $ffp_rc in
    0) ;;
    1) ff_refuse "the primary checkout is on a detached HEAD, not origin's default branch $default; this verb moves only the default branch, so everything stays where it is" ;;
    *)
      err "git could not read the primary checkout's HEAD (exit $ffp_rc); $default is unmoved — retry next cycle"
      exit 3
      ;;
  esac
  [ "$cur" = "$default" ] \
    || ff_refuse "the primary checkout has $(sanitize_printable "$cur" 'another branch') checked out, not origin's default branch $default; this verb moves only the default branch, so everything stays where it is"
  for ffp_scope in '' --cached; do
    ffp_rc=0
    # shellcheck disable=SC2086 # an empty scope is no argument at all
    git diff --quiet $ffp_scope >/dev/null 2>&1 || ffp_rc=$?
    case $ffp_rc in
      0) ;;
      1)
        err "the primary checkout has uncommitted changes on $default — refusing to fast-forward under them"
        err "commit, stash, or discard them yourself, then re-run; nothing here discards your work"
        exit 6
        ;;
      *)
        err "git could not read the primary checkout's changes (git diff exit $ffp_rc); $default is unmoved — retry next cycle"
        exit 3
        ;;
    esac
  done

  before=$(git rev-parse --verify --quiet "refs/heads/$default") || before=''
  if [ "$before" = "$target" ]; then
    printf 'sync\tup-to-date\n'
    printf 'main\t%s\n' "$before"
    exit 0
  fi
  if [ -n "$before" ]; then
    ffp_rc=0
    git merge-base --is-ancestor "$before" "$target" || ffp_rc=$?
    case $ffp_rc in
      0) ;;
      1)
        err "$default has history origin/$default lacks, so this is not a pure fast-forward — refusing"
        err "resolve it yourself; this path never merges, forces, rebases, or resets"
        exit 4
        ;;
      *)
        err "git could not compare $default with origin/$default (exit $ffp_rc); $default is unmoved — retry next cycle"
        exit 3
        ;;
    esac
  fi
  # The fetched commit, not the ref, so a concurrent fetch cannot change what
  # was checked above. The reflog message carries this run's own tag, so the
  # move is attributed from the reflog rather than from merge output a hook
  # or a file name could imitate.
  ffp_tag="planwright main-currency ff-primary $$.$(date +%s)"
  if ! merge_out=$(GIT_REFLOG_ACTION=$ffp_tag git merge --ff-only --no-edit --no-stat "$target" 2>&1); then
    case "$merge_out" in
      *'ot possible to fast-forward'* | *'divergent'*)
        err "$default has history origin/$default lacks, so this is not a pure fast-forward — refusing"
        err_git_said "$merge_out"
        exit 4
        ;;
      *'would be overwritten'*)
        err "the fast-forward would overwrite files in the primary checkout — refusing; nothing here discards your work"
        err_git_said "$merge_out"
        exit 6
        ;;
      *)
        err "the fast-forward of $default was refused; $default is unmoved — retry next cycle"
        err_git_said "$merge_out"
        exit 3
        ;;
    esac
  fi
  after=$(git rev-parse --verify --quiet "refs/heads/$default") || after=''
  if [ "$after" != "$target" ]; then
    err "after the fast-forward, $default is not at origin/$default's commit (another session may have switched the primary checkout); check it by hand"
    err_git_said "$merge_out"
    exit 3
  fi
  # A merge onto an unborn branch writes git's own `initial pull` entry, not
  # the tag, so that first move stands as this run's.
  ffp_last=''
  if [ -n "$before" ]; then
    ffp_last=$(git reflog -1 --format=%gs "refs/heads/$default" -- 2>/dev/null) || ffp_last=''
  fi
  case $ffp_last in
    "$ffp_tag:"*)
      # This run's move; the entry before it holds the true old commit, even
      # when another run moved the branch after the read above.
      before=$(git rev-parse --verify --quiet "refs/heads/$default@{1}") || before=''
      ;;
    '')
      # An unborn branch, or no reflog to read (core.logAllRefUpdates off):
      # the read above stands.
      ;;
    *)
      # Another run moved it between the read above and this merge.
      printf 'sync\tup-to-date\n'
      printf 'main\t%s\n' "$after"
      exit 0
      ;;
  esac
  actor=$(sanitize_printable "${PLANWRIGHT_WORKER_HANDLE:-${PLANWRIGHT_TOWER_ID:-}}" unknown)
  printf 'sync\tfast-forward\n'
  printf 'main\t%s\n' "$after"
  if printf '%s\tff-primary\t%s\t%s\t%s\t%s\t%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$primary" "$default" "$before" "$after" "$actor" >>"$rec" 2>/dev/null; then
    printf 'record\t%s\n' "$rec"
  else
    printf 'record\tunwritten\n'
    err "fast-forwarded $default but could not append the act to $(sanitize_printable "$rec"); git's reflog still carries it"
  fi
  exit 0
}

cmd=${1-}
[ -n "$cmd" ] || {
  usage
  exit 2
}
shift

case "$cmd" in
  sync) ;;
  ff-primary) ff_primary "$@" ;;
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
      # An EMPTY value is refused rather than falling back to the current
      # directory: the operator named a checkout, and quietly syncing a
      # different one than the one they named is the substitution `--main-ref ""`
      # is already refused for. Omitting the option entirely is still the
      # documented way to mean "here".
      [ $# -ge 2 ] && [ -n "$2" ] || {
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

# Establish the dependency BEFORE the grammar check, because that check now asks
# git itself whether the ref name is legal. Without this, a missing git makes
# `check-ref-format` return 127, which reads as "the value is malformed" and
# reports a perfectly well-formed `--main-ref` as the problem — blaming the
# operator's argument for an absent dependency.
command -v git >/dev/null 2>&1 || {
  err "git not found on PATH; this sync is a git operation and cannot run without it"
  exit 2
}

is_branch_name "$main_ref" || {
  err "refusing a malformed --main-ref '$(sanitize_printable "$main_ref")'"
  exit 2
}

if [ -n "$checkout" ]; then
  [ -d "$checkout" ] || {
    err "no such checkout directory '$(sanitize_printable "$checkout")'"
    exit 2
  }
  # `--` so a directory named like an option (`-`, `-L`) is treated as a path.
  cd -- "$checkout" || {
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

# A BARE checkout points HEAD at `main` without having a work tree, so the merge
# path cannot serve it: `git diff` there fails because the operation is invalid
# rather than because anything is uncommitted (reading that as "you have
# uncommitted changes, commit or stash" names a remedy that is impossible in a
# repository with no working tree), and `git merge` cannot run at all. With no
# index to desynchronize, the ref update below is both available and correct — so
# the operation is chosen by whether a work tree EXISTS as well as by what is
# checked out. A bare repo also reports `bare` rather than a branch line to
# `git worktree list`, so it cannot trip the sibling-worktree refusal below.
in_work_tree=false
if [ "$(git rev-parse --is-inside-work-tree 2>/dev/null)" = "true" ]; then
  in_work_tree=true
fi

if [ "$current_branch" = "$main_ref" ] && [ "$in_work_tree" = true ]; then
  # Uncommitted work aborts a merge that would otherwise fast-forward cleanly.
  # That is NOT divergence, so it must not be reported as one: `main` is still a
  # plain fast-forward behind `origin`, and the remedy is to commit or stash, not
  # to go hunting for unexpected history. Checked up front so the operator gets
  # that remedy instead of git's overwrite warning wrapped in the wrong story.
  if ! git diff --quiet 2>/dev/null || ! git diff --cached --quiet 2>/dev/null; then
    err "$main_ref has uncommitted changes, so the fast-forward would overwrite them — refusing"
    err "this is not a divergence: $main_ref is still a clean fast-forward behind origin/$main_ref"
    err "commit or stash the changes, then re-run; nothing here discards your work"
    exit 6
  fi
  # The explicit fetch-then-fast-forward-merge form. NEVER `git pull`, whose
  # rebase-on-pull configs would rewrite history here.
  if ! fetch_err=$(git fetch origin "$main_ref" 2>&1); then
    err "fetch of origin/$main_ref failed against a configured origin; leaving $main_ref unmoved rather than proceeding on a possibly-stale main — retry next cycle"
    err_git_said "$fetch_err"
    exit 3
  fi
  if ! merge_err=$(git merge --ff-only FETCH_HEAD 2>&1); then
    # Only claim divergence when git actually reports a non-fast-forward; any
    # other refusal gets git's own reason rather than a story invented for it.
    case "$merge_err" in
      *'untracked working tree files would be overwritten'* | *'local changes'*'would be overwritten'*)
        # The same class as the up-front dirty-tree check, but invisible to it:
        # untracked files are not in the index, so `git diff` and
        # `git diff --cached` both report clean and only the merge's own refusal
        # can surface the collision. Still NOT a divergence — $main_ref remains a
        # plain fast-forward behind origin — so it must not be reported as one.
        # Only the colliding file blocks the sync; unrelated untracked files (a
        # build artifact, a scratch note) are none of this path's business, which
        # is why this is classified from the refusal rather than pre-empted by a
        # blanket untracked-file check.
        err "$main_ref has untracked files the fast-forward would overwrite — refusing"
        err "this is not a divergence: $main_ref is still a clean fast-forward behind origin/$main_ref"
        err "move or remove the files git names below, then re-run; nothing here discards your work"
        err_git_said "$merge_err"
        exit 6
        ;;
      *'Not possible to fast-forward'* | *'not possible to fast-forward'* | *'divergent'*)
        err "$main_ref has diverged from origin/$main_ref — the fast-forward was refused"
        err "a per-tower $main_ref should only ever fast-forward, so this is unexpected local history; resolve it yourself — this path will never force, rebase, or reset"
        err_git_said "$merge_err"
        exit 4
        ;;
      *)
        # An unrecognized refusal is NOT reported as divergence. A locked index
        # (another git process in this checkout), a full disk, or a permission
        # error all land here, and every one of them is retryable — while
        # "your history has diverged, go resolve it" is a diagnosis this path has
        # not earned and cannot support. So the unknown case says only what is
        # certain: the fast-forward did not happen, $main_ref is untouched, try
        # again next cycle. This also matches the ref-update path below, which
        # already treats an unclassified failure as transient.
        err "the fast-forward of $main_ref was refused for a reason that is not divergence; $main_ref is unmoved — retry next cycle"
        err_git_said "$merge_err"
        exit 3
        ;;
    esac
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
  # Quoted so the suggestion stays pasteable for any checkout path `cd --
  # "$checkout"` already accepts, whitespace and apostrophes included.
  err "run the sync in that checkout instead, where it fast-forwards $main_ref directly: main-currency.sh sync --checkout $(shell_quote "$(sanitize_printable "$main_worktree")")"
  exit 5
fi

# Update the `main` REF without a checkout. This refspec has no leading `+` and
# no --force, so git refuses a non-fast-forward by nature — the ff-only guarantee
# comes from the refspec's own shape here, not from a separate flag. That shape is
# only guaranteed because `is_branch_name` refuses a `--main-ref` beginning with
# `+`; without that refusal the value would supply the force modifier itself, so
# the two are one mechanism and not two independent safeguards.
if ! fetch_err=$(git fetch origin "$main_ref:$main_ref" 2>&1); then
  # Two failures share this exit path, so classify them by whether origin was
  # reachable at all: a non-fast-forward rejection means the fetch itself worked.
  #
  # The match is on the non-fast-forward REASON, never on the bare word
  # "rejected". git's own rejection always names the reason
  # (`! [rejected] main -> main (non-fast-forward)`), while "rejected" on its own
  # appears in transport and credential failures that never reached the ref at
  # all — an ssh key "rejected by the server" is the common one. Classifying
  # those as divergence tells the operator to go resolve unexpected local
  # history that does not exist, which is the dead end D-10 exists to prevent;
  # they are transient and belong on the retry path below. This mirrors the split
  # REQ-C1.6 pins for the fence push: a permission error with no per-ref
  # rejection is the transient case, not the taken/diverged case.
  case "$fetch_err" in
    *'non-fast-forward'* | *'non-fast forward'*)
      err "the $main_ref ref update was rejected as a non-fast-forward — $main_ref has diverged from origin/$main_ref"
      err_git_said "$fetch_err"
      err "a per-tower $main_ref should only ever fast-forward, so this is unexpected local history; resolve it yourself — this path will never force, rebase, or reset"
      exit 4
      ;;
  esac
  err "fetch of origin/$main_ref failed against a configured origin; leaving $main_ref unmoved rather than proceeding on a possibly-stale main — retry next cycle"
  err_git_said "$fetch_err"
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
