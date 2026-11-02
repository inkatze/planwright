#!/bin/sh
# resolve-work-repo.sh — print the work repository for a spec bundle: the
# primary checkout whose task branches, pull requests, and commit trailers
# carry the bundle's execution state.
#
# Usage: resolve-work-repo.sh <spec-dir> [--repository <alias> | --task <id>]
# --repository: the registry's (work-repo-registry.sh) checkout for <alias>.
# --task: where task <id> dispatches: its version 3 Repository: alias as
#   --repository resolves it, else the bundle's work repository.
#
# The current repository (resolve-root.sh repo --primary, so
# PLANWRIGHT_REPO_ROOT applies) answers when the bundle sits in it or its
# spec root, in either view, is the bundle's parent; otherwise the bundle's
# own repository does. A holder is the exception: a bundle in the current
# repository under a marked root other than its own spec root resolves to the
# one work repository registered against that root, never to the holder.
#
# Exit: 0 printed · 2 usage, no such directory, or unreadable Repository:
#   fields · 3 the bundle is in no repository and nothing here owns it ·
#   4 PLANWRIGHT_REPO_ROOT refused · 5 the alias, the task, or a holder's
#   bundle resolves to nothing (unregistered, stale, ambiguous, unmarked
#   root, a malformed field, or not exactly one registered work repository)
#
# POSIX sh; dash-safe.
set -u
LC_ALL=C
export LC_ALL
unset CDPATH

say() {
  printf 'resolve-work-repo: %s\n' "$(printf '%s' "$1" | tr -d '\000-\037\177')" >&2
}

usage() {
  say "usage: resolve-work-repo.sh <spec-dir> [--repository <alias> | --task <id>]"
  exit 2
}
spec_arg=""
alias=""
have_alias=0
task=""
have_task=0
while [ "$#" -gt 0 ]; do
  case $1 in
    --repository)
      [ "$#" -ge 2 ] && [ "$have_alias" -eq 0 ] && [ "$have_task" -eq 0 ] || usage
      alias=$2
      have_alias=1
      shift 2
      ;;
    --task)
      [ "$#" -ge 2 ] && [ "$have_task" -eq 0 ] && [ "$have_alias" -eq 0 ] || usage
      task=$2
      have_task=1
      shift 2
      ;;
    "") usage ;;
    *)
      [ -z "$spec_arg" ] || usage
      spec_arg=$1
      shift
      ;;
  esac
done
[ -n "$spec_arg" ] || usage
valid_alias() {
  case $1 in
    "" | [!a-z0-9]* | *[!a-z0-9-]*) return 1 ;;
  esac
  [ "${#1}" -le 64 ]
}
if [ "$have_alias" -eq 1 ] && ! valid_alias "$alias"; then
  say "refusing the alias '$alias': it must match ^[a-z0-9][a-z0-9-]*\$, at most 64 characters"
  exit 2
fi
# The byte screen first: grep matches line by line, so an id carrying a
# newline would otherwise pass on its first line alone.
if [ "$have_task" -eq 1 ]; then
  case $task in
    "" | *[!0-9.]*) task_ok=0 ;;
    *) task_ok=1 ;;
  esac
  if [ "$task_ok" -eq 0 ] || ! printf '%s' "$task" | grep -Eq '^[0-9]+(\.[0-9]+)?$'; then
    say "refusing the task id '$task': it must match ^[0-9]+(\\.[0-9]+)?\$"
    exit 2
  fi
fi
bundle=$(cd -- "$spec_arg" 2>/dev/null && pwd -P) || {
  say "no such spec directory: $spec_arg"
  exit 2
}
parent=${bundle%/*}
[ -n "$parent" ] || parent=/

script_dir=$(cd -- "$(dirname -- "$0")" && pwd -P) || exit 2
root_helper=$script_dir/resolve-root.sh
registry=$script_dir/work-repo-registry.sh
TAB=$(printf '\t')

own=$(cd -- "$bundle" && env -u PLANWRIGHT_REPO_ROOT /bin/sh "$root_helper" repo --primary 2>/dev/null) || own=""
# The registry keys a root by its primary checkout's path: a copy in a linked
# worktree of the bundle's repository maps onto it.
reg_root=$parent
btop=$(cd -- "$bundle" && /bin/sh "$root_helper" repo --checkout 2>/dev/null) || btop=""
if [ -n "$own" ] && [ -n "$btop" ] && [ "$btop" != "$own" ]; then
  case $parent in
    "$btop") reg_root=$own ;;
    "$btop"/*) reg_root=$(cd -- "$own/${parent#"$btop"/}" 2>/dev/null && pwd -P) || reg_root=$parent ;;
  esac
fi

# registry_entries: set entries to the live work repositories registered
# against the root, `<alias><TAB><checkout>` per line (holder entries never
# dispatch); fails when the registry cannot answer at all.
entries=""
registry_entries() {
  re_out=$(/bin/sh "$registry" lookup --root "$reg_root" 2>/dev/null) || {
    entries=""
    return 1
  }
  entries=$(printf '%s\n' "$re_out" | awk -F"$TAB" '$1 == "entry" && $3 == "work" { print $2 "\t" $4 }')
}
# candidates: the entries as `alias (checkout)`, comma-separated, or none.
candidates() {
  cd_list=$(printf '%s\n' "$entries" | awk -F"$TAB" 'NF { printf "%s%s (%s)", sep, $1, $2; sep = ", " }')
  printf '%s' "${cd_list:-none}"
}

by_alias() {
  /bin/sh "$root_helper" marker "$reg_root" >/dev/null || {
    say "the alias '$1' resolves to nothing: the spec root $parent has no valid planwright-spec-root.yml marker, and only a marked root has registered repositories"
    exit 5
  }
  # The registry names its own reason on stderr; any failure to answer is
  # the alias resolving to nothing, never a fallback to the current repository.
  if ! ba_out=$(/bin/sh "$registry" lookup --root "$reg_root" "$1"); then
    registry_entries || :
    say "the work repositories registered against $reg_root: $(candidates)"
    exit 5
  fi
  registry_entries || :
  if ! printf '%s\n' "$entries" | BA_OUT=$ba_out awk -F"$TAB" '$2 == ENVIRON["BA_OUT"] { f = 1 } END { exit !f }'; then
    say "the alias '$1' resolves to nothing: it names a holder checkout, which never receives a dispatch; the work repositories registered against $reg_root: $(candidates)"
    exit 5
  fi
  printf '%s\n' "$ba_out"
  exit 0
}

if [ "$have_alias" -eq 1 ]; then
  by_alias "$alias"
fi

if [ "$have_task" -eq 1 ]; then
  spec_parse_sh="$script_dir/spec-parse.sh"
  [ -r "$spec_parse_sh" ] || {
    say "spec-parse.sh missing or unreadable: $spec_parse_sh"
    exit 2
  }
  # shellcheck source=scripts/spec-parse.sh
  . "$spec_parse_sh" || exit 2
  tasks_md=$bundle/tasks.md
  # Only version 3 defines the field; a field under a declaration that cannot
  # say whether one is meant fails closed, as the derivation does.
  fv=$(spec_parse_header_value "$tasks_md" Format-version 2>/dev/null) || fv=""
  map=""
  case $fv in
    1 | 2) ;;
    *)
      map=$(spec_parse_repository_map "$tasks_md") || {
        say "could not read the Repository: fields of $tasks_md"
        exit 2
      }
      if [ "$fv" != 3 ] && [ -n "$map" ]; then
        say "$tasks_md carries Repository: fields under a missing, unparseable, or undefined Format-version: (fail closed)"
        exit 2
      fi
      ;;
  esac
  field=$(printf '%s\n' "$map" | awk -F"$TAB" -v i="$task" '$1 == i { print $2 "\t" $3; exit }')
  case ${field%%"$TAB"*} in
    "") ;;
    alias) by_alias "${field#*"$TAB"}" ;;
    duplicate)
      say "task $task resolves to nothing: it carries more than one Repository: field"
      exit 5
      ;;
    *)
      say "task $task resolves to nothing: its Repository: value is not a single alias in the identifier grammar"
      exit 5
      ;;
  esac
fi

cur=""
cur_rc=0
cur=$(/bin/sh "$root_helper" repo --primary 2>/dev/null) || cur_rc=$?
if [ "$cur_rc" -eq 4 ]; then
  /bin/sh "$root_helper" repo --primary >/dev/null
  exit 4
fi
[ "$cur_rc" -eq 0 ] || cur=""

# names_parent: the current repository's resolved spec root, in either view,
# is the bundle's parent. A refused or unreadable spec_root cannot vouch for
# the bundle.
names_parent() {
  for view in "" --primary; do
    # shellcheck disable=SC2086 # an empty view is no argument
    root=$(/bin/sh "$root_helper" spec $view 2>/dev/null) || continue
    root=$(cd -- "$root" 2>/dev/null && pwd -P) || continue
    [ "$root" != "$parent" ] || return 0
  done
  return 1
}

if [ -n "$cur" ]; then
  if [ "$own" = "$cur" ]; then
    if ! names_parent && /bin/sh "$root_helper" marker "$reg_root" >/dev/null 2>&1; then
      if ! registry_entries; then
        say "no work repository for $bundle: it sits in the holder $cur, and the work-repository registry could not be read for $reg_root (work-repo-registry.sh lookup --explain says why)"
        exit 5
      fi
      case $(printf '%s' "$entries" | awk 'END { print NR }') in
        1)
          printf '%s\n' "${entries#*"$TAB"}"
          exit 0
          ;;
        0) say "no work repository for $bundle: it sits in the holder $cur, and no work repository is registered against $reg_root (run work-repo-registry.sh register in one)" ;;
        *) say "no work repository for $bundle: several are registered against $reg_root ($(candidates)), so a task naming none has no single home; give each such task a Repository: field" ;;
      esac
      exit 5
    fi
    printf '%s\n' "$cur"
    exit 0
  fi
  if names_parent; then
    printf '%s\n' "$cur"
    exit 0
  fi
fi

if [ -n "$own" ]; then
  printf '%s\n' "$own"
  exit 0
fi
say "no work repository for $bundle: it is in no repository, and no repository here names it as its spec root"
exit 3
