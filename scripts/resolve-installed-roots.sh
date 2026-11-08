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
# $HOME/.claude; with neither set nothing is printed (--fresh prints <path>).
#
# Usage:
#   resolve-installed-roots.sh
#     <claude-dir> comes from the environment as described above.
#   resolve-installed-roots.sh --unlinked <path>
#     Prints nothing; the exit status is the rule's verdict.
#   resolve-installed-roots.sh --refused
#     The listing's dropped candidates, one per line.
#   resolve-installed-roots.sh --current
#     The record's roots that apply here, no cached copy: an entry of a
#     project or local scope whose projectPath holds the project
#     ($CLAUDE_PROJECT_DIR, else the working directory), then the user-scope
#     ones. A long-running session runs the root resolver from the first,
#     rather than from a path it remembers.
#   resolve-installed-roots.sh --check <path>
#     Warns on stderr, and exits 1, when <path> is a copy under the plugin
#     cache that no --current root names: an older version a session kept
#     using after an upgrade or reload. Silent, and 0, for a current copy,
#     a path outside the cache (a checkout), or a record it cannot read.
#   resolve-installed-roots.sh --fresh <path>
#     The root to hand a session launched from <path>: the first --current
#     root present on disk where --check would warn about <path>, else <path>
#     as given. A launch seam runs it over every root it passes on, so a
#     session never inherits the older copy its launcher kept using.
#
# Exit codes: 0 always for the listing. An unset home, an absent or
#   unreadable record, an absent jq, and an empty cache are each empty
#   output, never a failure: callers read empty as "no installed roots" and
#   the arm it feeds does not fire; the same holds for --refused. With
#   --unlinked: 0 when the path passes the rule, 1 when it does not (or is
#   empty). --current prints nothing, exit 0, where the listing would print
#   no record entry. With --check: 1 for a stale copy, else 0. --fresh: 0.
#   2 on a usage error.
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

usage() {
  echo "usage: resolve-installed-roots.sh [--unlinked <path> | --refused | --current | --check <path> | --fresh <path>]" >&2
  exit 2
}

want=kept
check=''
fresh=0
case ${1-} in
  --fresh)
    [ "$#" -eq 2 ] && [ -n "$2" ] || usage
    check=$2
    fresh=1
    ;;
  --refused | --current)
    [ "$#" -eq 1 ] || usage
    want=${1#--}
    ;;
  --unlinked)
    [ "$#" -eq 2 ] || usage
    unlinked "$2"
    exit
    ;;
  --check)
    [ "$#" -eq 2 ] && [ -n "$2" ] || usage
    check=$2
    ;;
  '') ;;
  *) usage ;;
esac

claude_dir=''
if [ -n "${CLAUDE_DIR:-}" ]; then
  claude_dir=$CLAUDE_DIR
elif [ -n "${HOME:-}" ]; then
  claude_dir="$HOME/.claude"
fi
if [ -z "$claude_dir" ]; then
  [ "$fresh" -eq 0 ] || printf '%s\n' "$check"
  exit 0
fi

# emit <root>: print the root when it falls on the side of the rule asked for.
emit() {
  if unlinked "$1"; then
    case $want in kept | current) printf '%s\n' "$1" ;; esac
  else
    [ "$want" = refused ] && printf '%s\n' "$1"
  fi
  return 0
}

# recorded_roots all|here: the record's planwright roots, every entry or
# only those that apply in the working directory (most specific first),
# each through emit.
recorded_roots() {
  f="$claude_dir/plugins/installed_plugins.json"
  if [ -r "$f" ] && command -v jq >/dev/null 2>&1; then
    rr_cwd=${CLAUDE_PROJECT_DIR:-$(pwd -P 2>/dev/null)}
    jq -r --arg which "$1" --arg cwd "$rr_cwd" '[(.plugins // {}) | to_entries[]
      | select((.key | type) == "string" and (.key | startswith("planwright@")))
      | (.value | if type == "array" then .[] else . end)
      | select(type == "object" and (.installPath | type) == "string" and (.installPath | startswith("/")))
      | . as $e
      | if $which == "all" then [0, 0, $e.installPath]
        elif (($e.scope // "user") == "user") then [1, 0, $e.installPath]
        elif (($e.projectPath | type) == "string" and ($e.projectPath | startswith("/")) and $cwd != ""
          and ($cwd == $e.projectPath or ($cwd | startswith(($e.projectPath | rtrimstr("/")) + "/"))))
          then [0, -($e.projectPath | rtrimstr("/") | length), $e.installPath]
        else empty end]
      | sort_by(.[0], .[1]) | .[] | .[2]' "$f" 2>/dev/null \
      | while IFS= read -r p; do
        emit "$p"
      done
  fi
}

# physical <dir>: the directory's canonical path, or nothing.
physical() { (cd -P -- "$1" 2>/dev/null && pwd -P); }

# stale <path>: true when <path> is a cached copy no --current root names,
# with ck_path its canonical form and ck_first the root to use instead. Only a
# current root present on disk with its scripts/ stands in: a record naming a
# copy that is not there yet (or was pruned) would hand on a root whose hooks
# never run, so the path stands instead.
stale() {
  ck_cache=$(physical "$claude_dir/plugins/cache") || return 1
  ck_path=$(physical "$1") || return 1
  case $ck_path/ in
    "$ck_cache"/*) ;;
    *) return 1 ;;
  esac
  want=current
  ck_current=$(recorded_roots here)
  [ -n "$ck_current" ] || return 1
  ck_first=''
  while IFS= read -r ck_root; do
    [ -n "$ck_root" ] || continue
    [ "$(physical "$ck_root")" != "$ck_path" ] || return 1
    [ -n "$ck_first" ] || [ ! -d "$ck_root/scripts" ] || ck_first=$ck_root
  done <<EOF
$ck_current
EOF
  [ -n "$ck_first" ]
}

if [ "$fresh" -eq 1 ]; then
  if stale "$check"; then
    printf '%s\n' "$ck_first"
  else
    printf '%s\n' "$check"
  fi
  exit 0
fi

if [ -n "$check" ]; then
  stale "$check" || exit 0
  printf 'planwright: WARNING running from %s, which is not the installed planwright (%s); run every script and doc from the installed copy instead\n' \
    "$(printf '%s' "$ck_path" | tr -d '\000-\037\177')" "$(printf '%s' "$ck_first" | tr -d '\000-\037\177')" >&2
  exit 1
fi

if [ "$want" = current ]; then
  recorded_roots here
  exit 0
fi
recorded_roots all

for d in "$claude_dir"/plugins/cache/*/planwright/*/; do
  [ -d "$d" ] || continue
  emit "${d%/}"
done
exit 0
