#!/bin/sh
# orchestrate-marker-home.sh — the directories a spec's runtime dispatch markers
# live in, resolved once here for the writer (orchestrate-marker.sh) and every
# reader (orchestrate-state.sh, fleet-dispatch-worktree.sh's liveness probe).
#
# A marker dropped from one checkout must count as in flight from every
# worktree of the same repository, so its home sits under the common git dir
# of the repository holding the bundle, keyed by spec id:
#   <git-common-dir>/planwright/orchestrate/<spec>/markers
# A bundle in no repository keys under its work repository's common dir
# (resolve-work-repo.sh). Another clone has its own common dir and sees none
# of it.
#
# The checkout-local <spec-dir>/.orchestrate/markers stays in both lists while
# planwright versions that know only that location may still run beside this
# one: the writer drops each marker there too, so an older reader in the same
# checkout still counts it, and a reader also consults the primary checkout's
# copy of the bundle, where an older writer running there left its marker. An
# older writer in another linked worktree stays invisible from here, as does
# a primary checkout whose .git is not its git dir (made with
# --separate-git-dir, or a .git symlinked elsewhere), which git itself cannot
# name from a linked worktree.
#
# Usage: orchestrate-marker-home.sh write|read <spec-dir>
#   write  the dirs a dispatch drops its marker in: the shared home, then the
#          checkout-local dir, always last
#   read   the write dirs, plus the primary checkout's checkout-local dir when
#          the bundle sits in a linked worktree
# One canonical absolute dir per line, no repeats, so a consumer can refuse a
# dir reached through a symlink by comparing it with its own `pwd -P`.
# PLANWRIGHT_ORCH_STATE_DIR, when non-empty, is the only dir for both (a
# trusted operator and test knob, printed as given). A spec id outside the
# identifier grammar, or a derived path carrying a control byte, loses the
# dirs it cannot place safely; the checkout-local dir is always printed.
#
# Exit: 0 printed; 2 usage, no such spec dir, or a spec dir or override
#   carrying a newline (a list of lines cannot carry it).
#
# Portable POSIX sh; dash-safe. No eval; paths are data.
set -u
LC_ALL=C
export LC_ALL
unset CDPATH
# An inherited git environment (a hook exports it) would point every git call
# below at that repository instead of the bundle's, or stop discovery short.
unset GIT_DIR GIT_WORK_TREE GIT_COMMON_DIR GIT_INDEX_FILE GIT_OBJECT_DIRECTORY \
  GIT_CEILING_DIRECTORIES GIT_DISCOVERY_ACROSS_FILESYSTEM GIT_CONFIG_PARAMETERS GIT_CONFIG_COUNT

nl='
'

say() {
  printf 'orchestrate-marker-home: %s\n' "$(printf '%s' "$1" | tr -d '\000-\037\177')" >&2
}

usage() {
  say "usage: orchestrate-marker-home.sh write|read <spec-dir>"
  exit 2
}

[ "$#" -eq 2 ] || usage
cmd=$1
spec=$2
case "$cmd" in
  write | read) ;;
  *) usage ;;
esac
[ -n "$spec" ] || usage

if [ -n "${PLANWRIGHT_ORCH_STATE_DIR:-}" ]; then
  case "$PLANWRIGHT_ORCH_STATE_DIR" in
    *"$nl"*)
      say "refusing a PLANWRIGHT_ORCH_STATE_DIR carrying a newline"
      exit 2
      ;;
  esac
  [ -d "$spec" ] || {
    say "no such spec dir: $spec"
    exit 2
  }
  printf '%s\n' "$PLANWRIGHT_ORCH_STATE_DIR"
  exit 0
fi

# A relative operand is anchored with ./ so `cd` never reads `-` as OLDPWD or
# a leading dash as an option.
case "$spec" in
  /*) spec_cd=$spec ;;
  *) spec_cd=./$spec ;;
esac
spec_real=$(cd -P -- "$spec_cd" 2>/dev/null && pwd -P) || {
  say "no such spec dir: $spec"
  exit 2
}
case "$spec_real" in
  *"$nl"*)
    say "refusing a spec dir carrying a newline"
    exit 2
    ;;
esac

emit() {
  case "$1" in
    *[[:cntrl:]]*) return 0 ;;
  esac
  printf '%s\n' "$1"
}

# The id the branches and trailers use: the bundle's name as addressed, not
# the target of a symlinked bundle dir, with `.` and repeated slashes resolved.
spec_id=$(cd -L -- "$spec_cd" 2>/dev/null && pwd -L) || spec_id=''
spec_id=${spec_id##*/}
id_ok=1
case "$spec_id" in
  '' | -* | *[!a-z0-9-]* | flight) id_ok=0 ;;
esac
[ "${#spec_id}" -le 64 ] || id_ok=0

# One git call answers both the common dir and the bundle's own worktree.
common=''
top=''
if rp=$(git -C "$spec_real" rev-parse --git-common-dir --show-toplevel 2>/dev/null); then
  common=${rp%%"$nl"*}
  top=${rp#*"$nl"}
  [ "$top" != "$rp" ] || top=''
  # Anything but exactly two lines means a path carried a newline (or an older
  # git printed no worktree): no safe split. Current git exits non-zero instead
  # of printing one line, so the empty arm is defensive.
  case "$top" in
    '' | *"$nl"*) common='' top='' ;;
  esac
  if [ -n "$common" ]; then
    common=$(cd -P -- "$spec_real" 2>/dev/null && cd -P -- "$common" 2>/dev/null && pwd -P) || common=''
  fi
  if [ -n "$top" ]; then
    top=$(cd -P -- "$top" 2>/dev/null && pwd -P) || top=''
  fi
elif work=$(/bin/sh "$(dirname -- "$0")/resolve-work-repo.sh" "$spec_real" 2>/dev/null); then
  wc=$(git -C "$work" rev-parse --git-common-dir 2>/dev/null) \
    && common=$(cd -P -- "$work" 2>/dev/null && cd -P -- "$wc" 2>/dev/null && pwd -P) || common=''
fi

if [ "$id_ok" -eq 1 ] && [ -n "$common" ]; then
  emit "$common/planwright/orchestrate/$spec_id/markers"
fi
printf '%s\n' "$spec_real/.orchestrate/markers"

[ "$cmd" = read ] || exit 0

# The primary checkout is the first entry git lists for the repository (a
# bare repository's first entry is the bare dir, which holds no bundle copy);
# a bundle in a linked worktree has its copy at the same path relative to it.
[ -n "$top" ] || exit 0
wl=$(git -C "$spec_real" worktree list --porcelain 2>/dev/null) || exit 0
block=${wl%%"$nl$nl"*}
case "$nl$block$nl" in
  *"${nl}bare$nl"*) exit 0 ;;
esac
first=${block%%"$nl"*}
case "$first" in
  'worktree '*) primary=${first#worktree } ;;
  *) exit 0 ;;
esac
primary=$(cd -P -- "$primary" 2>/dev/null && pwd -P) || exit 0
# A primary whose .git is not its git dir (made with --separate-git-dir, or a
# .git symlinked elsewhere) is unknown to git from a linked worktree, which
# lists the git dir in its place: only a checkout whose own .git resolves to
# the common dir is taken for the primary. (A git dir itself
# named .git makes git treat its parent as the main worktree, and so does this.)
[ -n "$common" ] && [ "$primary" != "$top" ] || exit 0
[ "$(cd -P -- "$primary/.git" 2>/dev/null && pwd -P)" = "$common" ] || exit 0
case "$spec_real" in
  "$top"/*) emit "$primary/${spec_real#"$top"/}/.orchestrate/markers" ;;
esac
exit 0
