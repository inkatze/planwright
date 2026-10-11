#!/bin/sh
# spec-store-worktree.sh — open the spec worktree in a holder repository.
#
# Usage: spec-store-worktree.sh <spec>
#
# When the spec root lies in a holder (the separate-repo posture,
# doctrine/storage-classes.md), the spec branch planwright/<spec>/spec and
# its worktree <holder>/.claude/worktrees/<spec>-spec belong to the holder,
# never to the work repository the session runs in. Claude Code's native
# worktree mechanism only reaches the session's own repository, so this
# script is the holder's equivalent: it reuses the worktree when it is
# already there on the spec branch, recreates it from a surviving branch,
# or creates both, the branch starting at the holder's default branch
# (origin/HEAD when recorded, else the holder's HEAD branch) with no
# upstream until the first push. It fetches nothing, commits nothing, and
# never touches the work repository.
#
# <spec> is the identifier, or its alias specs/<spec>, either with one
# trailing slash. Prints three tab-separated lines:
#   worktree<TAB><holder>/.claude/worktrees/<spec>-spec
#   bundle<TAB><the bundle directory inside that worktree>
#   branch<TAB>planwright/<spec>/spec
#
# Exit: 0 ready; 2 usage or a refused identifier; 3 the root is not in a
# holder (same-repo and plain keep their own paths); 4 the root did not
# resolve, or the holder refused (a foreign directory at the worktree path,
# a symlinked .claude, no default branch, a git failure).
set -u
LC_ALL=C
export LC_ALL
unset CDPATH
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY \
  GIT_CONFIG_PARAMETERS GIT_CONFIG_COUNT

script_dir=$(cd -- "$(dirname -- "$0")" && pwd -P) || exit 4
# shellcheck source=scripts/spec-id-lib.sh
. "$script_dir/spec-id-lib.sh"

say() { printf 'spec-store-worktree: %s\n' "$1" | tr -d '\000-\010\013-\037\177' >&2; }

[ "$#" -eq 1 ] || {
  say "usage: spec-store-worktree.sh <spec>"
  exit 2
}
spec_id_canon "$1"
id=$SPEC_ID
case $id in
  '' | flight | *[!a-z0-9-]* | [!a-z0-9]*)
    say "refused: the spec must be an identifier matching ^[a-z0-9][a-z0-9-]*\$, not flight"
    exit 2
    ;;
esac
[ "${#id}" -le 64 ] || {
  say "refused: the identifier is longer than 64 characters"
  exit 2
}

posture=$("$script_dir/resolve-root.sh" spec --posture) || {
  say "the spec root did not resolve"
  exit 4
}
[ "$posture" = separate-repo ] || {
  say "the spec root's posture is $posture, not separate-repo: no holder worktree to open"
  exit 3
}
root=$("$script_dir/resolve-root.sh" spec --primary) || {
  say "the spec root did not resolve"
  exit 4
}
# The holder's own primary checkout, discovered from the root, never from the
# work repository's override.
holder=$(cd -- "$root" && unset PLANWRIGHT_REPO_ROOT PLANWRIGHT_REPO_ROOT_CHECKED \
  && "$script_dir/resolve-root.sh" repo --primary) || {
  say "the holder repository holding the spec root did not resolve"
  exit 4
}
case $root in
  "$holder") rel='' ;;
  "$holder"/*) rel=${root#"$holder"/} ;;
  *)
    say "the spec root does not lie in its holder's primary checkout"
    exit 4
    ;;
esac

for d in "$holder/.claude" "$holder/.claude/worktrees"; do
  [ ! -L "$d" ] || {
    say "refused: $d is a symlink"
    exit 4
  }
done

branch="planwright/$id/spec"
wt="$holder/.claude/worktrees/$id-spec"
hg() { git -C "$holder" "$@"; }

# is_spec_wt — true when $wt is the holder's own worktree on $branch.
is_spec_wt() {
  [ ! -L "$wt" ] || return 1
  wt_common=$(git -C "$wt" rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || wt_common=''
  h_common=$(hg rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || h_common=''
  wt_top=$(git -C "$wt" rev-parse --show-toplevel 2>/dev/null) || wt_top=''
  wt_branch=$(git -C "$wt" symbolic-ref -q --short HEAD 2>/dev/null) || wt_branch=''
  [ -n "$h_common" ] && [ "$wt_common" = "$h_common" ] && [ "$wt_top" = "$wt" ] && [ "$wt_branch" = "$branch" ]
}
# add_wt <what> <worktree-add args...> — git's own reason reaches the caller.
# A failure that still left the spec worktree in place (a holder hook failing
# after checkout, a concurrent run winning the race) is a warning, not a refusal.
add_wt() {
  what=$1
  shift
  add_err=$(hg worktree add -q "$@" 2>&1 >/dev/null) && return 0
  if is_spec_wt; then
    say "warning: git reported a failure after opening $wt: $add_err"
    return 0
  fi
  say "git could not $what: $add_err"
  exit 4
}

if [ -e "$wt" ] || [ -L "$wt" ]; then
  is_spec_wt || {
    say "refused: $wt exists and is not the holder's worktree on $branch"
    exit 4
  }
elif hg show-ref --verify --quiet "refs/heads/$branch"; then
  add_wt "recreate $wt from $branch" "$wt" "$branch"
else
  base=$(hg symbolic-ref -q refs/remotes/origin/HEAD 2>/dev/null) || base=''
  # A recorded origin/HEAD can outlive the branch it names (renamed, pruned).
  if [ -z "$base" ] || ! hg rev-parse -q --verify "$base^{commit}" >/dev/null 2>&1; then
    base=$(hg symbolic-ref -q HEAD 2>/dev/null) || base=''
  fi
  if [ -z "$base" ] || ! hg rev-parse -q --verify "$base^{commit}" >/dev/null 2>&1; then
    say "the holder has no default branch to start $branch from"
    exit 4
  fi
  add_wt "create $wt on a new $branch" --no-track -b "$branch" "$wt" "$base"
fi

if [ -n "$rel" ]; then
  bundle="$wt/$rel/$id"
else
  bundle="$wt/$id"
fi
printf 'worktree\t%s\nbundle\t%s\nbranch\t%s\n' "$wt" "$bundle" "$branch"
