#!/bin/sh
# observation-carry.sh — the sanctioned tower-observation-to-`main` carry path
# (fleet-hardening Task 9; D-9; REQ-D1.3, REQ-E1.3).
#
# A disposable tower records observations (scripts/obs-record.sh) as fragment
# files committed onto its disposable tower branch. Those commits are never
# pushed, so the learnings are STRANDED when the branch is torn down. This
# script is the sanctioned carry: it collects the observation fragments present
# on the current branch (HEAD) but absent from `origin/main`, pushes them onto
# ONE dedicated chore branch, and opens (or reuses) ONE draft chore PR against
# `main`, so the learnings reach the accumulator on `main` through a human
# merge. It is the belt the `/orchestrate --bookkeeping` drain pass runs; the
# tower may also run it directly.
#
# Invariants (D-9, REQ-D1.3, the carried floors):
#   - NEVER advances or touches shared local `main`: the carry is built with git
#     plumbing (a temp index + `commit-tree`) and pushed straight to the chore
#     branch ref; no checkout, no local branch, no local-`main` fast-forward.
#   - NEVER merges the PR and NEVER marks it ready — merge/ready stay the human's
#     (REQ-E1.4). The PR is always a DRAFT, matching planwright's "the draft→ready
#     flip is the human's" floor.
#   - NEVER force-pushes: the chore branch grows by NEW commits only. When it
#     already exists the new commit's parent is its tip (a fast-forward); when it
#     does not, the parent is `origin/main`.
#   - IDEMPOTENT: fragments already on `origin/main` OR already on the chore
#     branch are deduped, so a repeat run carries nothing new and opens no second
#     PR (one open chore PR is reused). A per-repo advisory lock serializes the
#     push+PR critical section so concurrent runs cannot both open a PR.
#   - Nothing is stranded SILENTLY: a degrade (no `origin` remote, no `gh`, or a
#     failed push/PR) names the stranded observations and exits non-zero so the
#     caller surfaces it (REQ-K1.6, REQ-K1.7).
#   - No model/API call anywhere in the decision path — deterministic git/gh
#     plumbing only (REQ-E1.3).
#
# Usage: observation-carry.sh [options] <repo-root>
#   <repo-root>          the checkout whose current branch (HEAD) carries the
#                        tower observation fragments to carry.
#   --branch <name>      chore branch name (default planwright/chore/observations).
#   --base <ref>         base ref the carry lands toward (default origin/main).
#   --source <ref>       ref whose fragments are carried (default HEAD).
#   --obs-dir <rel>      observations dir under the repo (default
#                        specs/_observations); its entries/ subdir holds fragments.
#   --dry-run            compute + report the stranded set; push nothing, open no PR.
#
# Output — a tagged TSV stream on stdout (consumers switch on column 1):
#   carry<TAB><created|updated|noop|degraded>
#   stranded<TAB><n>                     the count of fragments this run carried
#                                        (0 on a clean no-op; the stranded count
#                                        on a degrade, so it is never lost).
#   pr<TAB><number-or-url>               on created/updated, when known.
#
# Exit codes:
#   0  created | updated | noop (including a lock-contended clean no-op).
#   3  degraded — no `origin` remote, no `gh`, or a push/PR failure. The stranded
#      observations are named (stderr + the `stranded` record); the caller MUST
#      surface them rather than treat the carry as done.
#   2  usage / invalid input / internal failure (fail closed).
#
# Environment overrides (tests, worktree callers):
#   PLANWRIGHT_OBSERVATION_CARRY_STATE_DIR  dir holding the advisory lock
#       (default <repo>/.claude/orchestrate.local, gitignored by `.claude/*.local/`).
#   PLANWRIGHT_LOCAL_CONFIG                  passed through to config-get.sh.
#
# Portable POSIX sh + git + gh (bash 3.2 / BSD compatible, no eval; all external
# input is treated as data). Pathname expansion is disabled (set -f).
set -uf
LC_ALL=C
export LC_ALL
unset CDPATH

TAB=$(printf '\t')

script_dir=$(cd -- "$(dirname -- "$0")" && pwd) || exit 2
if [ -r "$script_dir/echo-safety.sh" ]; then
  # shellcheck source=scripts/echo-safety.sh
  . "$script_dir/echo-safety.sh"
else
  sanitize_printable() { printf '%s' "$1" | tr -d '\000-\037\177\200-\237'; }
fi
config_get="$script_dir/config-get.sh"

usage() {
  printf '%s\n' "usage: observation-carry.sh [--branch <name>] [--base <ref>] [--source <ref>] [--obs-dir <rel>] [--dry-run] <repo-root>" >&2
  exit 2
}

branch="planwright/chore/observations"
base_ref="origin/main"
source_ref="HEAD"
obs_dir="specs/_observations"
dry_run=0
repo_root=""

# A git ref / branch-name value is treated as data before it reaches a git
# command. Reject an empty value, a leading '-' (option-injection), whitespace,
# and anything outside a conservative ref charset; git's own ref rules are
# stricter still, but this closes the shell/option-injection surface first.
valid_ref() {
  case "$1" in
    '' | -*) return 1 ;;
    *[!A-Za-z0-9._/-]*) return 1 ;;
    *..* | */ | /*) return 1 ;;
  esac
  return 0
}

while [ $# -gt 0 ]; do
  case "$1" in
    --branch)
      [ $# -ge 2 ] || usage
      branch="$2"
      shift 2
      ;;
    --branch=*)
      branch="${1#--branch=}"
      shift
      ;;
    --base)
      [ $# -ge 2 ] || usage
      base_ref="$2"
      shift 2
      ;;
    --base=*)
      base_ref="${1#--base=}"
      shift
      ;;
    --source)
      [ $# -ge 2 ] || usage
      source_ref="$2"
      shift 2
      ;;
    --source=*)
      source_ref="${1#--source=}"
      shift
      ;;
    --obs-dir)
      [ $# -ge 2 ] || usage
      obs_dir="$2"
      shift 2
      ;;
    --obs-dir=*)
      obs_dir="${1#--obs-dir=}"
      shift
      ;;
    --dry-run)
      dry_run=1
      shift
      ;;
    --)
      shift
      break
      ;;
    -*)
      printf '%s\n' "observation-carry: unknown option '$(sanitize_printable "$1")'" >&2
      usage
      ;;
    *)
      [ -z "$repo_root" ] || usage
      repo_root="$1"
      shift
      ;;
  esac
done
if [ -z "$repo_root" ] && [ $# -gt 0 ]; then
  repo_root="$1"
  shift
fi
[ $# -eq 0 ] || usage
[ -n "$repo_root" ] || usage

# Validate the ref-shaped inputs before they touch git.
valid_ref "$branch" || {
  printf '%s\n' "observation-carry: invalid --branch '$(sanitize_printable "$branch")'" >&2
  exit 2
}
valid_ref "$base_ref" || {
  printf '%s\n' "observation-carry: invalid --base '$(sanitize_printable "$base_ref")'" >&2
  exit 2
}
valid_ref "$source_ref" || {
  printf '%s\n' "observation-carry: invalid --source '$(sanitize_printable "$source_ref")'" >&2
  exit 2
}
# The obs-dir must be a plain repo-relative path (no traversal / absolute).
case "$obs_dir" in
  '' | /* | *..*)
    printf '%s\n' "observation-carry: invalid --obs-dir '$(sanitize_printable "$obs_dir")'" >&2
    exit 2
    ;;
esac
entries_dir="$obs_dir/entries"

# Repo-root must be inside a git work tree; resolve its top so refs/paths are
# unambiguous regardless of the caller's cwd.
repo_top=$(cd -- "$repo_root" 2>/dev/null && git rev-parse --show-toplevel 2>/dev/null) || repo_top=""
if [ -z "$repo_top" ]; then
  printf '%s\n' "observation-carry: '$(sanitize_printable "$repo_root")' is not inside a git work tree" >&2
  exit 2
fi
repo_root=$repo_top

g() { git -C "$repo_root" "$@"; }

# List the entries-dir fragment PATHS (repo-relative) at a ref; empty if the ref
# or the dir is absent. Sorted for deterministic set math.
entries_at() {
  g ls-tree -r --name-only "$1" -- "$entries_dir" 2>/dev/null | LC_ALL=C sort
}
ref_exists() { g rev-parse --verify --quiet "$1^{commit}" >/dev/null 2>&1; }

# --- Compute the stranded set (deterministic, no network) ---------------------
# Fragments present at <source> but absent from BOTH origin/main AND the chore
# branch tip are the ones to carry. The chore-branch exclusion is what makes a
# repeat run a no-op and keeps the append commit non-empty.
ref_exists "$source_ref" || {
  printf '%s\n' "observation-carry: source ref '$(sanitize_printable "$source_ref")' does not resolve" >&2
  exit 2
}

# Refresh the remote-tracking refs so the dedupe reads a current origin/main and
# origin/<branch>. Refspec-isolated so a hostile remote.origin.fetch can never
# fast-forward local `main` (the read-only-local-`main` invariant holds by
# construction — mirrors dispatch-fetch.sh). Best-effort: a down remote degrades
# below rather than stranding the whole pass.
refresh_remote() {
  [ "$have_remote" -eq 1 ] || return 0
  g fetch origin --refmap='' '+refs/heads/*:refs/remotes/origin/*' --quiet >/dev/null 2>&1 || true
}

# Recompute the stranded set against the CURRENT refs, setting the globals
# `stranded`, `stranded_count`, `remote_branch`. It is called once before the
# lock (for the no-op / degrade decisions) and again AFTER the lock (authoritative
# — so a run that lost a concurrent race sees the winner's just-pushed branch and
# cleanly no-ops instead of building a doomed non-fast-forward push).
#   stranded = src_list − (main_list ∪ chore_list), matched on the full repo-
#   relative path (fragment filenames are globally unique, so path == identity).
# The set difference is POSIX `grep -Fxv -f <baseline>` (no bash process-subst):
# a fixed-string, whole-line, inverted match keeps only src paths absent from the
# carried baseline; an empty baseline matches nothing, so every src path passes —
# the correct "carry all" degenerate case.
remote_branch="origin/$branch"
compute_stranded() {
  # Dedup baselines. Offline, origin/main is unavailable; fall back to local
  # `main` READ-ONLY (only its tree is read, never advanced) so a fully offline
  # run still dedupes against what main already has.
  _base="$base_ref"
  ref_exists "$_base" || _base="main"
  _main_list=""
  ref_exists "$_base" && _main_list=$(entries_at "$_base")
  _chore_list=""
  ref_exists "$remote_branch" && _chore_list=$(entries_at "$remote_branch")

  _bf=$(mktemp "${TMPDIR:-/tmp}/observation-carry.base.XXXXXX") || {
    printf '%s\n' "observation-carry: could not create a temp file" >&2
    exit 2
  }
  printf '%s\n%s\n' "$_main_list" "$_chore_list" | grep -v '^$' | LC_ALL=C sort -u >"$_bf" || true
  stranded=$(printf '%s\n' "$src_list" | grep -v '^$' | grep -Fxv -f "$_bf" 2>/dev/null || true)
  rm -f -- "$_bf" 2>/dev/null || true
  stranded=$(printf '%s\n' "$stranded" | grep -v '^$' || true)
  stranded_count=$(printf '%s\n' "$stranded" | grep -c . || true)
  [ -n "$stranded_count" ] || stranded_count=0
}

src_list=$(entries_at "$source_ref")
have_remote=0
g remote get-url origin >/dev/null 2>&1 && have_remote=1
refresh_remote
compute_stranded

# --- Clean no-op: nothing stranded -------------------------------------------
if [ "$stranded_count" -eq 0 ]; then
  printf 'carry%snoop\n' "$TAB"
  printf 'stranded%s0\n' "$TAB"
  exit 0
fi

# --- Degrade paths (never silent) --------------------------------------------
# There ARE stranded observations but the carry cannot reach the remote / gh.
# Name them and exit 3 so the caller surfaces the pending carry, rather than
# dropping the learnings on a torn-down branch.
degrade() {
  _why="$1"
  printf '%s\n' "observation-carry: $stranded_count observation(s) stranded — $_why. Not carried:" >&2
  printf '%s\n' "$stranded" | sed 's#.*/##;s/^/  - /' >&2
  printf 'carry%sdegraded\n' "$TAB"
  printf 'stranded%s%s\n' "$TAB" "$stranded_count"
  exit 3
}

if [ "$have_remote" -ne 1 ]; then
  degrade "no 'origin' remote to carry to"
fi
if ! command -v gh >/dev/null 2>&1; then
  degrade "the 'gh' CLI is unavailable, so no PR can be opened"
fi

if [ "$dry_run" -eq 1 ]; then
  printf 'carry%snoop\n' "$TAB"
  printf 'stranded%s%s\n' "$TAB" "$stranded_count"
  printf '%s\n' "observation-carry: --dry-run: $stranded_count observation(s) would be carried" >&2
  exit 0
fi

# --- Advisory lock: serialize the push+PR critical section --------------------
# A per-repo mkdir lock (atomic, process-surviving) so two concurrent carries
# cannot both push+open a PR. A live holder → clean no-op (the other run is
# carrying). A stale holder (older than stale_lock_threshold) is broken and
# re-acquired.
state_dir="${PLANWRIGHT_OBSERVATION_CARRY_STATE_DIR:-$repo_root/.claude/orchestrate.local}"
lock_dir="$state_dir/observation-carry.lock"
mkdir -p -- "$state_dir" 2>/dev/null || true

stale_min=15
if [ -x "$config_get" ]; then
  cv=$("$config_get" stale_lock_threshold 2>/dev/null) || cv=""
  cv=${cv%m}
  case "$cv" in
    '' | *[!0-9]* | 0?*) ;;
    *) stale_min=$cv ;;
  esac
fi

lock_held=0
# acquire_lock exit codes (mirrors orchestrate-lock.sh's real-error-vs-contention
# split): 0 held; 1 live contention (another carry holds it — a clean no-op);
# 2 real error (mkdir failed AND the lock dir does not exist — an unwritable
# state dir or filesystem fault). A real error must NOT be misread as contention:
# reporting a clean no-op while observations are still stranded would be a silent
# drop, so the caller degrades on 2.
acquire_lock() {
  if mkdir -- "$lock_dir" 2>/dev/null; then
    lock_held=1
    return 0
  fi
  # mkdir failed. If the lock dir does not exist, this is a real error (the state
  # dir is unwritable or the filesystem faulted), never contention.
  [ -d "$lock_dir" ] || return 2
  # Contention: break a stale holder (older than the threshold), then retry.
  if find "$lock_dir" -maxdepth 0 -mmin +"$stale_min" 2>/dev/null | grep -q .; then
    rmdir -- "$lock_dir" 2>/dev/null || true
    if mkdir -- "$lock_dir" 2>/dev/null; then
      lock_held=1
      return 0
    fi
    # Post-break: same distinction — an absent lock dir is a real error, a
    # present one means another holder won the race.
    [ -d "$lock_dir" ] || return 2
  fi
  return 1
}
release_lock() {
  [ "$lock_held" -eq 1 ] && rmdir -- "$lock_dir" 2>/dev/null || true
  lock_held=0
}
# Temp artifacts, declared before the trap so `cleanup` can reference them under
# `set -u` even if a signal arrives before they are assigned.
tmp_index=""
msg_file=""
# Invoked indirectly through the traps below (SC2329 cannot see trap-string uses).
# shellcheck disable=SC2329
cleanup() {
  release_lock
  [ -n "$tmp_index" ] && rm -f -- "$tmp_index" 2>/dev/null
  [ -n "$msg_file" ] && rm -f -- "$msg_file" 2>/dev/null
  return 0
}
# A signal trap MUST exit: a handler that only cleans up and returns lets the
# shell RESUME the interrupted command, which would carry on the push/PR after
# the lock was already released. So INT/TERM clean up and exit with the
# conventional 128+signo code; the EXIT trap then re-runs cleanup idempotently.
trap 'cleanup' EXIT
trap 'cleanup; exit 130' INT
trap 'cleanup; exit 143' TERM

acquire_lock
lock_rc=$?
if [ "$lock_rc" -eq 2 ]; then
  # Real error creating the lock (unwritable state dir / filesystem fault): the
  # observations are still stranded, so degrade non-silently rather than report a
  # clean no-op that would drop them.
  degrade "the carry lock could not be created (state dir unwritable or filesystem error)"
fi
if [ "$lock_rc" -ne 0 ]; then
  # Another carry holds the lock — a clean no-op (it will carry this set).
  printf 'carry%snoop\n' "$TAB"
  printf 'stranded%s0\n' "$TAB"
  exit 0
fi

# Authoritative recompute inside the lock: re-fetch and re-derive the stranded
# set so a run that lost a concurrent race sees the winner's just-pushed chore
# branch and cleanly no-ops, rather than building a doomed non-fast-forward push.
refresh_remote
compute_stranded
if [ "$stranded_count" -eq 0 ]; then
  release_lock
  printf 'carry%snoop\n' "$TAB"
  printf 'stranded%s0\n' "$TAB"
  exit 0
fi

# --- Build the carry commit with plumbing (never touches local main) ----------
# Parent: the chore branch tip if it exists (append, fast-forward), else the
# base ref. Base tree = the parent's tree; add each stranded fragment's EXISTING
# blob (no re-hash) into a temp index; write the tree; commit-tree.
if ref_exists "$remote_branch"; then
  parent="$remote_branch"
else
  parent="$base_ref"
fi
if ! ref_exists "$parent"; then
  release_lock
  printf '%s\n' "observation-carry: carry parent '$(sanitize_printable "$parent")' does not resolve" >&2
  degrade "the carry base ref is unresolvable"
fi

tmp_index=$(mktemp "${TMPDIR:-/tmp}/observation-carry.idx.XXXXXX") || {
  release_lock
  degrade "could not create a temp index"
}
# read-tree wants no pre-existing index file content; mktemp made an empty file,
# which read-tree treats as an empty index before it reads the parent tree.
rm -f -- "$tmp_index"
cleanup_index() { rm -f -- "$tmp_index" 2>/dev/null || true; }

if ! GIT_INDEX_FILE="$tmp_index" g read-tree "$parent" 2>/dev/null; then
  cleanup_index
  release_lock
  degrade "could not read the carry base tree"
fi

add_ok=1
printf '%s\n' "$stranded" | while IFS= read -r path; do
  [ -n "$path" ] || continue
  blob=$(g rev-parse "$source_ref:$path" 2>/dev/null) || blob=""
  if [ -z "$blob" ]; then
    printf 'ADDFAIL\n'
    break
  fi
  if ! GIT_INDEX_FILE="$tmp_index" g update-index --add --cacheinfo 100644 "$blob" "$path" 2>/dev/null; then
    printf 'ADDFAIL\n'
    break
  fi
done | grep -q ADDFAIL && add_ok=0

if [ "$add_ok" -ne 1 ]; then
  cleanup_index
  release_lock
  degrade "could not stage a stranded fragment"
fi

new_tree=$(GIT_INDEX_FILE="$tmp_index" g write-tree 2>/dev/null) || new_tree=""
cleanup_index
if [ -z "$new_tree" ]; then
  release_lock
  degrade "could not write the carry tree"
fi

parent_tree=$(g rev-parse "$parent^{tree}" 2>/dev/null) || parent_tree=""
if [ -n "$parent_tree" ] && [ "$new_tree" = "$parent_tree" ]; then
  # Nothing actually changed (every stranded fragment was already in the parent
  # tree) — a safety net against an empty commit. Treat as a clean no-op.
  release_lock
  printf 'carry%snoop\n' "$TAB"
  printf 'stranded%s0\n' "$TAB"
  exit 0
fi

# Commit message: a conventional chore subject + the carried UIDs in the body.
msg_file=$(mktemp "${TMPDIR:-/tmp}/observation-carry.msg.XXXXXX") || {
  release_lock
  degrade "could not create a commit-message temp file"
}
{
  printf 'chore(observations): carry %s tower observation(s) toward main\n\n' "$stranded_count"
  printf 'Sanctioned tower-observation carry (fleet-hardening Task 9, D-9,\n'
  printf 'REQ-D1.3). Fragments stranded on a disposable tower branch, carried\n'
  printf 'toward the accumulator on main for a human merge. Carried:\n\n'
  printf '%s\n' "$stranded" | sed 's#.*/##;s/^/- /'
} >"$msg_file"

commit=$(g commit-tree "$new_tree" -p "$parent" -F "$msg_file" 2>/dev/null) || commit=""
rm -f -- "$msg_file" 2>/dev/null || true
if [ -z "$commit" ]; then
  release_lock
  degrade "could not create the carry commit"
fi

# --- Push the carry commit straight to the chore branch ref -------------------
# New commit only, fast-forward (parent is the branch tip or origin/main). No
# local branch is created and local `main` is never touched.
if ! g push origin "$commit:refs/heads/$branch" --quiet >/dev/null 2>&1; then
  release_lock
  degrade "the chore branch push was rejected"
fi

# --- Open or reuse ONE draft chore PR -----------------------------------------
# Run gh from the repo so it resolves the GitHub repo from the checkout (no
# fragile `-R <url>` parsing of the origin URL). An open PR for this head means
# the push above already updated it; reuse it rather than opening a second.
# `.[0].number // empty` is load-bearing: a bare `.[0].number` prints the literal
# string "null" for an empty result set (no open PR), which `[ -n ]` reads as
# truthy and would wrongly skip PR creation forever. `// empty` yields no output
# when there is no PR, so `existing` is empty exactly when no PR exists.
existing=$(cd -- "$repo_root" && gh pr list --head "$branch" --state open --json number --jq '.[0].number // empty' 2>/dev/null) || existing=""

if [ -n "$existing" ]; then
  # The push already updated the open PR with the new commit — reuse it.
  release_lock
  printf 'carry%supdated\n' "$TAB"
  printf 'stranded%s%s\n' "$TAB" "$stranded_count"
  printf 'pr%s%s\n' "$TAB" "$existing"
  exit 0
fi

pr_title="chore(observations): carry tower observations toward main"
# The body carries literal markdown backticks (around `main`, `/spec-draft`);
# they are prose, not command substitution — SC2016 is a false positive here.
# shellcheck disable=SC2016
pr_body=$(
  printf 'Sanctioned carry of tower-recorded observation fragments stranded on a\n'
  printf 'disposable tower branch, landing them toward the accumulator on `main`\n'
  printf '(fleet-hardening Task 9, D-9, REQ-D1.3).\n\n'
  printf 'This PR is a **draft**: the ready-flip and the merge stay the human'\''s.\n'
  printf 'Merging carries the observations to `main` for `/spec-draft` to mine.\n\n'
  printf 'Carried this run:\n\n'
  printf '%s\n' "$stranded" | sed 's#.*/##;s/^/- /'
)
# The PR base is the branch name behind `base_ref`, not a hardcoded `main`. Strip
# the leading segment ONLY when it is an actual configured remote (`origin/main`
# → `main`), so a local base branch that legitimately contains a slash
# (`release/1.2`) or a `refs/...` form is used verbatim rather than corrupted to
# its tail.
pr_base="$base_ref"
_base_first="${base_ref%%/*}"
if [ "$_base_first" != "$base_ref" ] && g remote get-url "$_base_first" >/dev/null 2>&1; then
  pr_base="${base_ref#*/}"
fi
pr_url=$(cd -- "$repo_root" && gh pr create --draft --base "$pr_base" --head "$branch" \
  --title "$pr_title" --body "$pr_body" 2>/dev/null) || pr_url=""
if [ -z "$pr_url" ]; then
  # The branch is pushed (un-stranded), but the PR could not be opened. Surface
  # it — and NAME the fragments now sitting on the chore branch awaiting a manual
  # PR — rather than claim success (the non-silent contract, matching degrade()).
  release_lock
  printf '%s\n' "observation-carry: chore branch '$branch' pushed but 'gh pr create' failed; open the PR manually. On the chore branch:" >&2
  printf '%s\n' "$stranded" | sed 's#.*/##;s/^/  - /' >&2
  printf 'carry%sdegraded\n' "$TAB"
  printf 'stranded%s%s\n' "$TAB" "$stranded_count"
  exit 3
fi

release_lock
printf 'carry%screated\n' "$TAB"
printf 'stranded%s%s\n' "$TAB" "$stranded_count"
printf 'pr%s%s\n' "$TAB" "$pr_url"
exit 0
