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
# already there on the spec branch, recreates it from a surviving branch
# (local, else origin's, then tracking it), or creates both, the branch
# starting at the holder's default branch
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
# One holder may serve several projects, each with its own root, while the
# branch and worktree are named by the identifier alone: an existing spec
# branch that already carries another root's bundle of the same identifier,
# committed or still uncommitted in its worktree, belongs to that project and
# is refused, so spec identifiers stay unique per holder in practice.
#
# Exit: 0 ready; 2 usage or a refused identifier; 3 the root is not in a
# holder (same-repo and plain keep their own paths); 4 the root did not
# resolve, or the holder refused (a foreign directory at the worktree path,
# a symlinked .claude, another project's spec branch, a symlink on the
# bundle path inside the worktree or inside the bundle, no default branch, a
# git failure).
set -u
LC_ALL=C
export LC_ALL
unset CDPATH
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY \
  GIT_CONFIG_PARAMETERS GIT_CONFIG_COUNT \
  GIT_LITERAL_PATHSPECS GIT_GLOB_PATHSPECS GIT_NOGLOB_PATHSPECS GIT_ICASE_PATHSPECS

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
  # Refused up front: git would create the new branch before failing here.
  [ ! -e "$d" ] || [ -d "$d" ] || {
    say "refused: $d is not a directory"
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

# default_base — set base to the holder's default branch: origin/HEAD when
# it is recorded and still names a commit (it can outlive a renamed or
# pruned branch), else the holder's HEAD branch; empty when neither does.
default_base() {
  base=$(hg symbolic-ref -q refs/remotes/origin/HEAD 2>/dev/null) || base=''
  if [ -z "$base" ] || ! hg rev-parse -q --verify "$base^{commit}" >/dev/null 2>&1; then
    base=$(hg symbolic-ref -q HEAD 2>/dev/null) || base=''
  fi
  if [ -n "$base" ] && ! hg rev-parse -q --verify "$base^{commit}" >/dev/null 2>&1; then
    base=''
  fi
}
# Another root's bundle of this identifier: a bundle file in a directory
# named for it anywhere in the holder, outside this root's own bundle. Only
# bundle files count, so the root's other content (its observations, its
# marker) never reads as foreign, whatever directory names it passes through.
# foreign <git-command...> — run it limited to those files.
foreign() {
  g=":(top,glob)**/$id"
  "$@" -- ":(top,literal,exclude)${rel:+$rel/}$id/" "$g/requirements.md" "$g/design.md" \
    "$g/tasks.md" "$g/test-spec.md" "$g/kickoff-brief.md"
}
# refuse_foreign <listing> — refuse when the listing names a foreign path.
refuse_foreign() {
  [ -z "$1" ] && return 0
  p=$(printf '%s\n' "$1" | sed -n '1{s/^"//;s/"$//;p;}')
  say "refused: $branch carries another project's bundle at ${p%/*}; spec identifiers must be unique per holder"
  exit 4
}
# own_spec <ref> — refuse when <ref> changed, since leaving the default
# branch, another root's bundle of this identifier.
own_spec() {
  [ -n "$base" ] || {
    say "refused: the holder has no default branch to tell which project owns $branch"
    exit 4
  }
  changed=$(foreign hg -c core.quotePath=false diff --no-renames --name-only "$base...$1" 2>/dev/null) || {
    why=$(foreign hg diff --no-renames --name-only "$base...$1" 2>&1 >/dev/null)
    say "git could not compare $branch with the holder's default branch: $why"
    exit 4
  }
  refuse_foreign "$changed"
}
# own_wt — the same refusal over the worktree's uncommitted files, where a
# draft not yet committed (or never, under commit_on_draft: false) lives.
own_wt() {
  pending=$(foreign git -C "$wt" -c core.quotePath=false status --porcelain --untracked-files=all 2>/dev/null) || {
    say "git could not read the status of $wt"
    exit 4
  }
  refuse_foreign "$(printf '%s\n' "$pending" | cut -c4-)"
}

# tree_safe <ref> — the containment check below, run on <ref>'s tree before
# git opens anything from it, so a refusal leaves no branch or worktree
# behind: no component of the bundle path, and nothing inside the bundle,
# may be a symlink there. Entries are matched by exact name, never as a
# pattern.
tree_safe() {
  t_dir='' t_rest=${rel:+$rel/}$id
  while [ -n "$t_rest" ]; do
    t_name=${t_rest%%/*}
    case $t_rest in
      */*) t_rest=${t_rest#*/} ;;
      *) t_rest='' ;;
    esac
    t_modes=$(hg -c core.quotePath=false ls-tree "$1:$t_dir" 2>/dev/null \
      | N=$t_name awk -F '\t' '$2 == ENVIRON["N"] { split($1, f, " "); print f[1] }')
    case $t_modes in
      '') return 0 ;;
      *120000*)
        say "refused: $t_dir$t_name is a symlink on $1"
        exit 4
        ;;
      040000) ;;
      *)
        say "refused: $t_dir$t_name is not a directory on $1"
        exit 4
        ;;
    esac
    t_dir=$t_dir$t_name/
  done
  t_link=$(hg -c core.quotePath=false ls-tree -r "$1:$t_dir" 2>/dev/null | awk -F '\t' '$1 ~ /^120000 / { print $2; exit }')
  [ -z "$t_link" ] || {
    say "refused: $t_dir$t_link is a symlink on $1"
    exit 4
  }
}

default_base
if [ -e "$wt" ] || [ -L "$wt" ]; then
  is_spec_wt || {
    say "refused: $wt exists and is not the holder's worktree on $branch"
    exit 4
  }
  own_spec "refs/heads/$branch"
elif hg show-ref --verify --quiet "refs/heads/$branch"; then
  own_spec "refs/heads/$branch"
  tree_safe "refs/heads/$branch"
  add_wt "recreate $wt from $branch" "$wt" "$branch"
elif hg show-ref --verify --quiet "refs/remotes/origin/$branch"; then
  own_spec "refs/remotes/origin/$branch"
  tree_safe "refs/remotes/origin/$branch"
  # Pushed from elsewhere: starting afresh would diverge from the spec PR.
  add_wt "recreate $wt from origin/$branch" --track -b "$branch" "$wt" "refs/remotes/origin/$branch"
else
  [ -n "$base" ] || {
    say "the holder has no default branch to start $branch from"
    exit 4
  }
  tree_safe "$base"
  add_wt "create $wt on a new $branch" --no-track -b "$branch" "$wt" "$base"
fi
own_wt

# The skills write through the printed path, so no component of it below the
# worktree may be a symlink: one committed on the spec branch or the default
# branch would carry the writes outside the holder.
bundle=$wt
rest=${rel:+$rel/}$id
while [ -n "$rest" ]; do
  bundle=$bundle/${rest%%/*}
  case $rest in
    */*) rest=${rest#*/} ;;
    *) rest='' ;;
  esac
  [ ! -L "$bundle" ] || {
    say "refused: $bundle is a symlink"
    exit 4
  }
  [ ! -e "$bundle" ] || [ -d "$bundle" ] || {
    say "refused: $bundle is not a directory"
    exit 4
  }
done
# Nor may anything inside the bundle, committed or not: the skills write
# each bundle file in place.
if [ -d "$bundle" ]; then
  link=$(find "$bundle" -mindepth 1 -type l -print 2>/dev/null | sed -n 1p)
  [ -z "$link" ] || {
    say "refused: $link is a symlink"
    exit 4
  }
fi
printf 'worktree\t%s\nbundle\t%s\nbranch\t%s\n' "$wt" "$bundle" "$branch"
