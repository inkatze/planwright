#!/bin/sh
# resolve-work-repo.sh — print the work repository for a spec bundle: the
# primary checkout of the repository whose task branches, pull requests, and
# commit trailers carry the bundle's execution state.
#
# Usage: resolve-work-repo.sh <spec-dir>
#
# The current repository (resolve-root.sh repo --primary, so a worktree
# answers with its primary checkout and PLANWRIGHT_REPO_ROOT, when set, names
# it) is the work repository when the bundle sits in it, or when its resolved
# spec root, in either view, is the bundle's parent: that root may lie in a
# holder repository or in no repository at all, and the bundle's execution
# state still lives here. Otherwise the bundle is taken to sit in its own work
# repository, the default layout, and that repository's primary checkout
# answers, so a bundle addressed from outside its repository still derives
# from its own branches. The bundle's own repository is never asked about
# PLANWRIGHT_REPO_ROOT, which names the current repository only.
#
# Exit: 0 printed · 2 usage, or no such directory · 3 no work repository (the
#   bundle is in no repository and the current repository, if any, does not
#   own it) · 4 PLANWRIGHT_REPO_ROOT refused
#
# POSIX sh; dash-safe.
set -u
LC_ALL=C
export LC_ALL
unset CDPATH

say() {
  printf 'resolve-work-repo: %s\n' "$(printf '%s' "$1" | tr -d '\000-\037\177')" >&2
}

[ "$#" -eq 1 ] && [ -n "$1" ] || {
  say "usage: resolve-work-repo.sh <spec-dir>"
  exit 2
}
bundle=$(cd -- "$1" 2>/dev/null && pwd -P) || {
  say "no such spec directory: $1"
  exit 2
}
parent=${bundle%/*}
[ -n "$parent" ] || parent=/

script_dir=$(cd -- "$(dirname -- "$0")" && pwd -P) || exit 2
root_helper=$script_dir/resolve-root.sh

cur=""
cur_rc=0
cur=$(/bin/sh "$root_helper" repo --primary 2>/dev/null) || cur_rc=$?
if [ "$cur_rc" -eq 4 ]; then
  /bin/sh "$root_helper" repo --primary >/dev/null
  exit 4
fi
[ "$cur_rc" -eq 0 ] || cur=""

own=$(cd -- "$bundle" && env -u PLANWRIGHT_REPO_ROOT /bin/sh "$root_helper" repo --primary 2>/dev/null) || own=""

if [ -n "$cur" ]; then
  if [ "$own" = "$cur" ]; then
    printf '%s\n' "$cur"
    exit 0
  fi
  # The spec root is resolved as the current repository sees it; a refused
  # or unreadable spec_root cannot vouch for the bundle, so it falls through.
  for view in "" --primary; do
    # shellcheck disable=SC2086 # an empty view is no argument
    root=$(/bin/sh "$root_helper" spec $view 2>/dev/null) || continue
    root=$(cd -- "$root" 2>/dev/null && pwd -P) || continue
    if [ "$root" = "$parent" ]; then
      printf '%s\n' "$cur"
      exit 0
    fi
  done
fi

if [ -n "$own" ]; then
  printf '%s\n' "$own"
  exit 0
fi
say "no work repository for $bundle: it is in no repository, and no repository here names it as its spec root"
exit 3
