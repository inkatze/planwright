#!/bin/sh
# resolve-installed-roots.sh — print, one per line, every root Claude Code has
# a planwright plugin installed at: the installPath values its own
# <claude-dir>/plugins/installed_plugins.json records for a `planwright@...`
# plugin, plus every version directory under its marketplace cache
# (<claude-dir>/plugins/cache/<marketplace>/planwright/<version>), except a
# root that fails the symlink rule below. Raw candidates otherwise — callers
# canonicalize and existence-check.
#
# Why this is one script and not a helper in each caller: the worker-command-
# guard trusts `scripts/*.sh` under these roots, and the stream-json launch
# proves the guard approves a script call under them before it spawns a
# worker. The class this closes was the two disagreeing about which roots a
# worker runs scripts from (the launcher's own checkout versus the plugin
# Claude Code actually loads the skill from), so the answer is computed in
# exactly one place.
#
# The symlink rule: callers canonicalize a root, so a root reached through a
# symlink would make wherever the link points trusted. A root that is itself
# a symlink is dropped, and so is a relative one, one with a `.` or `..`
# component (which hides a symlink from the test), or one under a
# `plugins/cache/` tree with a symlink anywhere from `plugins` down. `--unlinked <path>` applies the same
# rule to one path, for the command guards' plugin-root arm; `--refused`
# prints the candidates the rule dropped instead, for the launch preflight,
# which must prove those too (the guard will not trust them).
#
# The JSON read goes through jq and yields nothing without it; the cache walk
# needs no jq. Neither half ever guesses. <claude-dir> is $CLAUDE_DIR, else
# $HOME/.claude; with neither set nothing is printed.
#
# Usage:
#   resolve-installed-roots.sh
#     <claude-dir> comes from the environment as described above.
#   resolve-installed-roots.sh --unlinked <path>
#     Prints nothing; the exit status is the rule's verdict.
#   resolve-installed-roots.sh --refused
#     The listing's dropped candidates, one per line.
#
# Exit codes: 0 always for the listing. An unset home, an absent or
#   unreadable record, an absent jq, and an empty cache are each empty
#   output, never a failure: callers read empty as "no installed roots" and
#   the arm it feeds does not fire; the same holds for --refused. With
#   --unlinked: 0 when the path passes the rule, 1 when it does not (or is
#   empty). 2 on a usage error.
#
# POSIX sh; pathname expansion is used for the cache walk only.
set -u
unset CDPATH
LC_ALL=C
export LC_ALL

# unlinked <path>: the symlink rule above.
unlinked() {
  ul_p=$1
  while :; do
    case $ul_p in
      */) ul_p=${ul_p%/} ;;
      *) break ;;
    esac
  done
  # A doubled slash is one separator to the kernel but would hide the
  # `/plugins/cache/` match below.
  while :; do
    case $ul_p in
      *//*) ul_p=${ul_p%%//*}/${ul_p#*//} ;;
      *) break ;;
    esac
  done
  # A relative path resolves against whatever directory a caller runs in, and
  # the cache walk below can only anchor an absolute one.
  case $ul_p in
    /?*) ;;
    *) return 1 ;;
  esac
  # `[ -L ]` follows a link named before a `.` or `..` component, so a path
  # carrying one would hide the symlink it walks through.
  case /$ul_p/ in
    */./* | */../*) return 1 ;;
  esac
  [ ! -L "$ul_p" ] || return 1
  case $ul_p in
    */plugins/cache/*) ;;
    *) return 0 ;;
  esac
  ul_cur=${ul_p%%/plugins/cache/*}
  ul_rest=${ul_p#"$ul_cur"/}
  while [ -n "$ul_rest" ]; do
    ul_c=${ul_rest%%/*}
    case $ul_rest in
      */*) ul_rest=${ul_rest#*/} ;;
      *) ul_rest='' ;;
    esac
    [ -n "$ul_c" ] || continue
    ul_cur=$ul_cur/$ul_c
    [ ! -L "$ul_cur" ] || return 1
  done
  return 0
}

want=kept
case ${1-} in
  --refused)
    [ "$#" -eq 1 ] || {
      echo "usage: resolve-installed-roots.sh [--unlinked <path> | --refused]" >&2
      exit 2
    }
    want=refused
    ;;
  --unlinked)
    [ "$#" -eq 2 ] || {
      echo "usage: resolve-installed-roots.sh [--unlinked <path> | --refused]" >&2
      exit 2
    }
    unlinked "$2"
    exit
    ;;
  '') ;;
  *)
    echo "usage: resolve-installed-roots.sh [--unlinked <path> | --refused]" >&2
    exit 2
    ;;
esac

claude_dir=''
if [ -n "${CLAUDE_DIR:-}" ]; then
  claude_dir=$CLAUDE_DIR
elif [ -n "${HOME:-}" ]; then
  claude_dir="$HOME/.claude"
fi
[ -n "$claude_dir" ] || exit 0

# emit <root>: print the root when it falls on the side of the rule asked for.
emit() {
  if unlinked "$1"; then
    [ "$want" = kept ] && printf '%s\n' "$1"
  else
    [ "$want" = refused ] && printf '%s\n' "$1"
  fi
  return 0
}

f="$claude_dir/plugins/installed_plugins.json"
if [ -r "$f" ] && command -v jq >/dev/null 2>&1; then
  jq -r '(.plugins // {}) | to_entries[]
    | select((.key | type) == "string" and (.key | startswith("planwright@")))
    | (.value | if type == "array" then .[] else . end)
    | (.installPath? // empty)
    | select(type == "string" and startswith("/"))' "$f" 2>/dev/null \
    | while IFS= read -r p; do
      emit "$p"
    done
fi

for d in "$claude_dir"/plugins/cache/*/planwright/*/; do
  [ -d "$d" ] || continue
  emit "${d%/}"
done
exit 0
