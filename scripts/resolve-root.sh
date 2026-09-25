#!/bin/sh
# resolve-root.sh — print one of planwright's roots.
#
# Usage:
#   resolve-root.sh [--explain] install
#   resolve-root.sh [--explain] repo --primary | --checkout
#   (--explain may appear anywhere among the arguments)
#
# install   which planwright copy runs: the first content-bearing arm of the
#           core root chain, in order
#             PLANWRIGHT_ROOT      explicit override
#             CLAUDE_PLUGIN_ROOT   plugin delivery
#             writer-mode          $CLAUDE_DIR/planwright when CLAUDE_DIR is
#                                  set, otherwise $HOME/.claude/planwright
#             self-location        the tree this script ships in
#           An arm is content-bearing when it holds doctrine/ or scripts/. A
#           set arm that is not is skipped with a warning and never printed;
#           an absent writer-mode directory is skipped silently, since plugin
#           delivery never creates it.
# repo      which repository the session belongs to.
#   --primary   the primary working tree of the repository owning the common
#               git directory, so every linked worktree answers with the
#               primary checkout (a submodule answers with its own working
#               tree). PLANWRIGHT_REPO_ROOT, when set, is used instead, but
#               only if it is an absolute path naming a git toplevel; any
#               other value is refused, never ignored.
#   --checkout  the current toplevel; PLANWRIGHT_REPO_ROOT never affects it.
#   Both views discover from the working directory: an inherited GIT_DIR or
#   GIT_WORK_TREE (a git hook exports them) is ignored.
#
# --explain prints "<source>\t<path>": the arm (PLANWRIGHT_ROOT,
# CLAUDE_PLUGIN_ROOT, writer-mode, self-location) or the repo source
# (PLANWRIGHT_REPO_ROOT; git-common-dir when --primary derived the tree from
# the common git directory; show-toplevel when git named it directly).
# Printed paths are canonical (symlinks resolved).
#
# Exit: 0 printed · 1 no install root resolved · 2 usage · 3 no repository
#   root (git missing, not inside a working tree, a bare repository, or a
#   primary that cannot be named from here: a linked worktree of a separate
#   git dir, or a core.worktree that is gone) · 4 PLANWRIGHT_REPO_ROOT
#   refused. Callers treat 3 as "no repository" and degrade; they never
#   compose a path from an empty root.
#
# POSIX sh with no dependency beyond git and tr: guards and hooks exec it
# through /bin/sh, which is dash on Linux.
set -u
# Pin the C locale so tr's byte ranges below mean bytes.
LC_ALL=C
export LC_ALL
# A CDPATH-resolved cd would echo the destination into the command
# substitutions that capture directories.
unset CDPATH

# say <message>: one diagnostic line on stderr. Values in it come from the
# environment or from git, so control bytes are stripped and printf is used
# rather than echo, which dash lets expand backslash escapes. C0 and DEL
# only: under the C locale a C1 byte range would also delete UTF-8
# continuation bytes and mangle non-ASCII paths.
say() {
  printf 'planwright: %s\n' "$(printf '%s' "$1" | tr -d '\000-\037\177')" >&2
}

usage() {
  say "usage: resolve-root.sh [--explain] install | repo --primary|--checkout"
  exit 2
}

kind=""
view=""
explain=0
for arg in "$@"; do
  case $arg in
    --explain) explain=1 ;;
    --primary | --checkout)
      [ -z "$view" ] || usage
      view=${arg#--}
      ;;
    -* | "") usage ;;
    *)
      [ -z "$kind" ] || usage
      kind=$arg
      ;;
  esac
done

# emit <source> <path>: print the result and exit 0; never returns.
emit() {
  if [ "$explain" -eq 1 ]; then
    printf '%s\t%s\n' "$1" "$2"
  else
    printf '%s\n' "$2"
  fi
  exit 0
}

canon() {
  (cd -P -- "$1" 2>/dev/null && pwd -P)
}

# try_arm <arm> <dir>: emit on a content-bearing directory, else warn and
# return so the next arm is tried.
try_arm() {
  [ -n "$2" ] || return 0
  if [ "$1" = writer-mode ] && [ ! -e "$2" ] && [ ! -L "$2" ]; then
    return 0
  fi
  if [ ! -d "$2" ] || { [ ! -d "$2/doctrine" ] && [ ! -d "$2/scripts" ]; }; then
    say "WARNING skipping the $1 root '$2': not a directory holding doctrine/ or scripts/"
    return 0
  fi
  if ! ta_canon=$(canon "$2"); then
    say "WARNING skipping the $1 root '$2': the directory cannot be entered"
    return 0
  fi
  emit "$1" "$ta_canon"
}

resolve_install() {
  writer_root=""
  if [ -n "${CLAUDE_DIR:-}" ]; then
    writer_root="$CLAUDE_DIR/planwright"
  elif [ -n "${HOME:-}" ]; then
    writer_root="$HOME/.claude/planwright"
  fi

  try_arm PLANWRIGHT_ROOT "${PLANWRIGHT_ROOT:-}"
  try_arm CLAUDE_PLUGIN_ROOT "${CLAUDE_PLUGIN_ROOT:-}"
  try_arm writer-mode "$writer_root"
  case $0 in
    */*) script_dir=${0%/*} ;;
    *) script_dir=. ;;
  esac
  try_arm self-location "$script_dir/.."
  say "no install root resolved (every arm of the core root chain was unset or skipped)"
  exit 1
}

# toplevel_of <dir>: the canonical toplevel of the working tree at <dir>.
toplevel_of() {
  to_top=$(cd -P -- "$1" 2>/dev/null && git rev-parse --show-toplevel 2>/dev/null) || return 1
  [ -n "$to_top" ] || return 1
  canon "$to_top"
}

no_repo() {
  if [ "$(git rev-parse --is-bare-repository 2>/dev/null)" = true ]; then
    say "no repository root: inside a bare repository, which has no working tree"
  elif [ "$(git rev-parse --is-inside-git-dir 2>/dev/null)" = true ]; then
    say "no repository root: inside a git directory, which has no working tree ($(pwd))"
  else
    say "no repository root: not inside a git repository ($(pwd))"
  fi
  exit 3
}

no_primary() {
  say "no repository root: this repository has no primary working tree${1:+ ($1)}"
  exit 3
}

resolve_primary() {
  if [ -n "${PLANWRIGHT_REPO_ROOT:-}" ]; then
    case $PLANWRIGHT_REPO_ROOT in
      /*) ;;
      *)
        say "refusing PLANWRIGHT_REPO_ROOT='$PLANWRIGHT_REPO_ROOT': it must be an absolute path"
        exit 4
        ;;
    esac
    rp_want=$(canon "$PLANWRIGHT_REPO_ROOT") || rp_want=""
    rp_top=""
    [ -z "$rp_want" ] || rp_top=$(toplevel_of "$rp_want") || rp_top=""
    if [ -z "$rp_top" ] || [ "$rp_top" != "$rp_want" ]; then
      say "refusing PLANWRIGHT_REPO_ROOT='$PLANWRIGHT_REPO_ROOT': it does not name the toplevel of a git working tree"
      exit 4
    fi
    emit PLANWRIGHT_REPO_ROOT "$rp_top"
  fi

  rp_common=$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || no_repo
  [ "$(git rev-parse --is-bare-repository 2>/dev/null)" != true ] || no_repo
  case $rp_common in
    /*) ;;
    *)
      # git before 2.31 has no --path-format and prints a relative path.
      rp_common=$(git rev-parse --git-common-dir 2>/dev/null) || no_repo
      case $rp_common in
        /*) ;;
        *) rp_common=$(pwd -P)/$rp_common ;;
      esac
      ;;
  esac
  rp_common=$(canon "$rp_common") || no_primary "'$rp_common' is not reachable"
  [ "$(git --git-dir="$rp_common" config --bool core.bare 2>/dev/null)" != true ] || no_primary

  # The primary, in order: the configured core.worktree; the tree we are in,
  # when our own git directory is the common one (the only way to name the
  # tree of a separate git dir); the directory holding a .git. A linked
  # worktree of a separate git dir has none of these to go on. A separate
  # git dir that is itself named .git is indistinguishable from an ordinary
  # one when run from inside it, and answers with the directory holding it.
  rp_src=git-common-dir
  rp_cand=$(git --git-dir="$rp_common" config core.worktree 2>/dev/null) || rp_cand=""
  case $rp_cand in
    "" | /*) ;;
    *) rp_cand=$rp_common/$rp_cand ;;
  esac
  if [ -z "$rp_cand" ] && [ "$(git rev-parse --is-inside-work-tree 2>/dev/null)" = true ]; then
    rp_own=$(git rev-parse --absolute-git-dir 2>/dev/null) || rp_own=""
    if [ -n "$rp_own" ] && [ "$(canon "$rp_own")" = "$rp_common" ]; then
      rp_cand=$(git rev-parse --show-toplevel 2>/dev/null) || rp_cand=""
      rp_src=show-toplevel
    fi
  fi
  if [ -z "$rp_cand" ]; then
    case $rp_common in
      */.git) rp_cand=${rp_common%/.git} ;;
      *) no_primary "the git directory '$rp_common' is separate from its working tree and records no primary path" ;;
    esac
  fi
  rp_path=$(toplevel_of "$rp_cand") || no_primary "'$rp_cand' is not reachable"
  [ "$rp_path" = "$(canon "$rp_cand")" ] || no_primary "'$rp_cand' is not a working tree toplevel"
  emit "$rp_src" "$rp_path"
}

resolve_checkout() {
  rc_top=$(git rev-parse --show-toplevel 2>/dev/null) || no_repo
  [ -n "$rc_top" ] || no_repo
  rc_top=$(canon "$rc_top") || no_repo
  emit show-toplevel "$rc_top"
}

case $kind in
  install)
    [ -z "$view" ] || usage
    resolve_install
    ;;
  repo)
    unset GIT_DIR GIT_WORK_TREE GIT_COMMON_DIR GIT_INDEX_FILE GIT_OBJECT_DIRECTORY
    command -v git >/dev/null 2>&1 || {
      say "no repository root: git is not installed (not on PATH)"
      exit 3
    }
    case $view in
      primary) resolve_primary ;;
      checkout) resolve_checkout ;;
      *) usage ;;
    esac
    ;;
  *) usage ;;
esac
