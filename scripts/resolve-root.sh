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
#             writer-mode          $CLAUDE_DIR/planwright, else
#                                  $HOME/.claude/planwright
#             self-location        the tree this script ships in
#           An arm is content-bearing when it holds doctrine/ or scripts/. A
#           set arm that is not is skipped with a warning and never printed;
#           an absent writer-mode directory is skipped silently, since plugin
#           delivery never creates it.
# repo      which repository the session belongs to.
#   --primary   the worktree owning the common git directory, so every linked
#               worktree answers with the primary checkout. PLANWRIGHT_REPO_ROOT,
#               when set, is used instead, but only if it names a git
#               toplevel; any other value is refused, never ignored.
#   --checkout  the current toplevel; PLANWRIGHT_REPO_ROOT never affects it.
#
# --explain prints "<source>\t<path>": the arm (PLANWRIGHT_ROOT,
# CLAUDE_PLUGIN_ROOT, writer-mode, self-location) or the repo source
# (PLANWRIGHT_REPO_ROOT, git-common-dir, show-toplevel). Printed paths are
# canonical (symlinks resolved).
#
# Exit: 0 printed · 1 no install root resolved · 2 usage · 3 no repository
#   root (not inside a git repository, or a bare repository with no primary
#   working tree) · 4 PLANWRIGHT_REPO_ROOT does not name a git toplevel.
#   Callers treat 3 as "no repository" and degrade; they never compose a path
#   from an empty root.
set -u
LC_ALL=C
export LC_ALL
unset CDPATH

usage() {
  echo "usage: resolve-root.sh [--explain] install | repo --primary|--checkout" >&2
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
    -*) usage ;;
    *)
      [ -z "$kind" ] || usage
      kind=$arg
      ;;
  esac
done

emit() {
  # emit <source> <path>
  if [ "$explain" -eq 1 ]; then
    printf '%s\t%s\n' "$1" "$2"
  else
    printf '%s\n' "$2"
  fi
  exit 0
}

canon() {
  (cd "$1" 2>/dev/null && pwd -P)
}

resolve_install() {
  script_dir=$(cd "$(dirname "$0")" && pwd -P) || exit 1
  writer_root=""
  if [ -n "${CLAUDE_DIR:-}" ]; then
    writer_root="$CLAUDE_DIR/planwright"
  elif [ -n "${HOME:-}" ]; then
    writer_root="$HOME/.claude/planwright"
  fi

  # try_arm <arm> <dir>: emit on a content-bearing directory, else return.
  try_arm() {
    [ -n "$2" ] || return 0
    if [ "$1" = writer-mode ] && [ ! -e "$2" ]; then
      return 0
    fi
    if [ -d "$2" ] && { [ -d "$2/doctrine" ] || [ -d "$2/scripts" ]; }; then
      ta_canon=$(canon "$2") && emit "$1" "$ta_canon"
    fi
    echo "planwright: WARNING skipping the $1 root '$2': not a directory holding doctrine/ or scripts/" >&2
  }

  try_arm PLANWRIGHT_ROOT "${PLANWRIGHT_ROOT:-}"
  try_arm CLAUDE_PLUGIN_ROOT "${CLAUDE_PLUGIN_ROOT:-}"
  try_arm writer-mode "$writer_root"
  try_arm self-location "$script_dir/.."
  echo "planwright: no install root resolved (every arm of the core root chain was unset or skipped)" >&2
  exit 1
}

# toplevel_of <dir>: the canonical toplevel of the working tree at <dir>.
toplevel_of() {
  to_top=$(cd "$1" 2>/dev/null && git rev-parse --show-toplevel 2>/dev/null) || return 1
  [ -n "$to_top" ] || return 1
  canon "$to_top"
}

no_repo() {
  if [ "$(git rev-parse --is-bare-repository 2>/dev/null)" = true ]; then
    echo "planwright: no repository root: inside a bare repository, which has no working tree" >&2
  else
    echo "planwright: no repository root: not inside a git repository ($(pwd))" >&2
  fi
  exit 3
}

resolve_primary() {
  if [ -n "${PLANWRIGHT_REPO_ROOT:-}" ]; then
    rp_want=$(canon "$PLANWRIGHT_REPO_ROOT") || rp_want=""
    rp_top=""
    [ -z "$rp_want" ] || rp_top=$(toplevel_of "$rp_want") || rp_top=""
    if [ -z "$rp_top" ] || [ "$rp_top" != "$rp_want" ]; then
      echo "planwright: refusing PLANWRIGHT_REPO_ROOT='$PLANWRIGHT_REPO_ROOT': it does not name the toplevel of a git working tree" >&2
      exit 4
    fi
    emit PLANWRIGHT_REPO_ROOT "$rp_top"
  fi

  git rev-parse --git-dir >/dev/null 2>&1 || no_repo
  [ "$(git rev-parse --is-bare-repository 2>/dev/null)" != true ] || no_repo

  # The first entry of the worktree list is the one owning the common git
  # directory; git marks it "bare" when there is no primary working tree.
  rp_first=$(git worktree list --porcelain 2>/dev/null | awk '
    NR == 1 && /^worktree / { sub(/^worktree /, ""); path = $0; next }
    /^$/ { exit }
    /^bare$/ { bare = 1 }
    END { if (path != "" && !bare) print path }
  ')
  if [ -z "$rp_first" ]; then
    echo "planwright: no repository root: this worktree belongs to a bare repository, which has no primary working tree" >&2
    exit 3
  fi
  rp_path=$(canon "$rp_first") || {
    echo "planwright: no repository root: the primary working tree '$rp_first' is not reachable" >&2
    exit 3
  }
  emit git-common-dir "$rp_path"
}

resolve_checkout() {
  rc_top=$(toplevel_of .) || no_repo
  emit show-toplevel "$rc_top"
}

case $kind in
  install)
    [ -z "$view" ] || usage
    resolve_install
    ;;
  repo)
    case $view in
      primary) resolve_primary ;;
      checkout) resolve_checkout ;;
      *) usage ;;
    esac
    ;;
  *) usage ;;
esac
