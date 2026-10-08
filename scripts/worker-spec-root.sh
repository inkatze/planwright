#!/bin/sh
# worker-spec-root.sh — the spec root a dispatched worker's command guard
# admits as its write zone (custom-spec-location D-15, REQ-E1.7): the resolved
# root's primary view when it lies in a different repository from the work
# repository or in none. A same-repo root prints nothing: the worker's own
# worktree already holds its copy, and its writes there ride the task branch.
#
# A dispatcher runs this once at launch and hands the result to the worker
# (fleet-dispatch-env.sh --spec-root, or PLANWRIGHT_WORKER_SPEC_ROOT in the
# launched environment), so the guard reads a fixed value instead of resolving
# config on every tool call.
#
# Usage: worker-spec-root.sh <work-repo-dir>
# Exit: 0 printed, or nothing to print · 1 the spec root did not resolve (the
#   caller hands no root; the store's posture never blocks a dispatch,
#   REQ-E1.4) · 2 usage, or a broken install (the script's own directory
#   cannot be entered).
set -u
LC_ALL=C
export LC_ALL
unset CDPATH

[ "$#" -eq 1 ] && [ -n "$1" ] || {
  echo "usage: worker-spec-root.sh <work-repo-dir>" >&2
  exit 2
}
case $0 in
  */*) script_dir=${0%/*} ;;
  *) script_dir=. ;;
esac
# Absolute, since the resolver runs from inside <work-repo-dir>.
script_dir=$(cd -- "$script_dir" && pwd -P) || exit 2
TAB=$(printf '\t')

line=$(cd -- "$1" 2>/dev/null && env -u PLANWRIGHT_REPO_ROOT /bin/sh "$script_dir/resolve-root.sh" spec --primary --explain 2>/dev/null) \
  || exit 1
# <source> TAB <path> TAB <posture> TAB <view>
rest=${line#*"$TAB"}
path=${rest%%"$TAB"*}
rest=${rest#*"$TAB"}
posture=${rest%%"$TAB"*}
case $posture in
  separate-repo | plain) printf '%s\n' "$path" ;;
  same-repo) ;;
  *) exit 1 ;;
esac
exit 0
