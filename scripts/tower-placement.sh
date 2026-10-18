#!/bin/sh
# tower-placement.sh — classify the checkout a tower runs in and report the
# `tower_placement` knob beside it, for the bring-up of /tower and
# /orchestrate.
#
# Prints one line, `<placement><TAB><tower_placement>`, the placement being:
#   main     the working tree of a checkout's own git directory: the primary
#            checkout or a separate clone, which git cannot tell apart
#   linked   a linked worktree (its git directory differs from the common one)
#   none     not in a working tree: a bare repository, the inside of a git
#            directory, or no repository at all
#
# Only git's directory queries decide the placement, never the path's shape:
# a plain `git worktree add` may put a tower anywhere. The skill renders the
# result and applies the knob; this script makes no judgment of its own.
#
# The knob resolves through scripts/resolve-config-knob.sh with its by-layer
# malformed policy. A linked worktree reads the primary checkout's layers, so
# a dedicated clone declares `allow` in its own machine-local layer.
#
# Usage: tower-placement.sh   (no arguments; classifies the working directory)
#
# Exit: 0 for every placement; 2 usage error; otherwise the knob resolver's
# own exit (4 a malformed repo-tracked value, 5 a broken install), with
# nothing printed on stdout.
set -u

LC_ALL=C
export LC_ALL
unset CDPATH
# Classify the working directory, as resolve-root.sh does for the knob's
# layers: a git hook exports these, and honoring them would classify the
# repository the hook runs for instead.
unset GIT_DIR GIT_WORK_TREE GIT_COMMON_DIR GIT_INDEX_FILE GIT_OBJECT_DIRECTORY \
  GIT_CONFIG_PARAMETERS GIT_CONFIG_COUNT

if [ "$#" -ne 0 ]; then
  echo "usage: tower-placement.sh   (no arguments; classifies the working directory)" >&2
  exit 2
fi

script_dir=$(cd "$(dirname "$0")" && pwd) || exit 2
resolver="$script_dir/resolve-config-knob.sh"
if [ ! -r "$resolver" ]; then
  printf '%s\n' "tower-placement: knob resolver '$resolver' is missing — broken install" >&2
  exit 5
fi

# abs_dir <path>: <path> canonicalized, a relative one read from the working
# directory (git before 2.31 has no --path-format and prints one).
abs_dir() {
  case $1 in
    /*) (cd -P -- "$1" 2>/dev/null && pwd -P) ;;
    *) (cd -P -- "./$1" 2>/dev/null && pwd -P) ;;
  esac
}

placement=none
if [ "$(git rev-parse --is-inside-work-tree 2>/dev/null)" = true ]; then
  own=$(git rev-parse --absolute-git-dir 2>/dev/null) || own=""
  common=$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || common=""
  case $common in
    /*) ;;
    *) common=$(git rev-parse --git-common-dir 2>/dev/null) || common="" ;;
  esac
  own=${own:+$(abs_dir "$own")}
  common=${common:+$(abs_dir "$common")}
  if [ -n "$own" ] && [ -n "$common" ]; then
    if [ "$own" = "$common" ]; then
      placement=main
    else
      placement=linked
    fi
  fi
fi

value=$(/bin/sh "$resolver" --key tower_placement --type enum \
  --values 'warn refuse allow' --fallback warn) || exit $?

printf '%s\t%s\n' "$placement" "$value"
