#!/bin/sh
# orchestrate-marker-home.sh — the directories a spec's runtime dispatch markers
# live in, resolved once here for the writer (orchestrate-marker.sh) and every
# reader (orchestrate-state.sh, fleet-dispatch-worktree.sh's liveness probe).
#
# A marker dropped from one checkout must count as in flight from every
# worktree of the same repository, so its home sits under the repository's
# common git dir, keyed by spec id:
#   <git-common-dir>/planwright/orchestrate/<spec>/markers
# Another clone has its own common dir and sees none of it.
#
# The checkout-local <spec-dir>/.orchestrate/markers stays in both lists while
# planwright versions that know only that location may still run beside this
# one: the writer drops each marker there too, so an older reader in the same
# checkout still counts it, and a reader also consults the primary checkout's
# copy of the bundle, where an older writer running there left its marker.
#
# Usage: orchestrate-marker-home.sh write|read <spec-dir>
#   write  the dirs a dispatch drops its marker in: the shared home, then the
#          checkout-local dir
#   read   the write dirs, plus the primary checkout's checkout-local dir when
#          the bundle sits in a linked worktree
# One dir per line, no repeats. PLANWRIGHT_ORCH_STATE_DIR, when non-empty, is
# the only dir for both (a trusted operator and test knob). A bundle with no
# work repository, a spec id outside the identifier grammar, or a derived path
# carrying a control byte loses the dirs it cannot place safely, never the
# checkout-local one, so a marker is never refused for want of a shared home.
#
# Exit: 0 printed; 2 usage, or no such spec dir.
#
# Portable POSIX sh; dash-safe. No eval; paths are data.
set -u
LC_ALL=C
export LC_ALL
unset CDPATH
# An inherited git environment (a hook exports it) would point every git call
# below at that repository instead of the bundle's.
unset GIT_DIR GIT_WORK_TREE GIT_COMMON_DIR GIT_INDEX_FILE GIT_OBJECT_DIRECTORY

usage() {
  printf '%s\n' "usage: orchestrate-marker-home.sh write|read <spec-dir>" >&2
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
spec_real=$(cd -- "$spec" 2>/dev/null && pwd -P) || {
  printf 'orchestrate-marker-home: no such spec dir: %s\n' "$(printf '%s' "$spec" | tr -d '\000-\037\177')" >&2
  exit 2
}

if [ -n "${PLANWRIGHT_ORCH_STATE_DIR:-}" ]; then
  printf '%s\n' "$PLANWRIGHT_ORCH_STATE_DIR"
  exit 0
fi

script_dir=$(cd -- "$(dirname -- "$0")" && pwd -P) || exit 2

emit() {
  case "$1" in
    *[[:cntrl:]]*) return 0 ;;
  esac
  printf '%s\n' "$1"
}

spec_id=${spec_real##*/}
id_ok=1
case "$spec_id" in
  '' | -* | *[!a-z0-9-]* | flight) id_ok=0 ;;
esac
[ "${#spec_id}" -le 64 ] || id_ok=0

if [ "$id_ok" -eq 1 ] \
  && work=$(/bin/sh "$script_dir/resolve-work-repo.sh" "$spec_real" 2>/dev/null) \
  && common=$(git -C "$work" rev-parse --git-common-dir 2>/dev/null) \
  && common=$(cd -- "$work" 2>/dev/null && cd -- "$common" 2>/dev/null && pwd -P); then
  emit "$common/planwright/orchestrate/$spec_id/markers"
fi

emit "$spec/.orchestrate/markers"

[ "$cmd" = read ] || exit 0

# The bundle's own path inside the primary checkout, when it sits in a linked
# worktree of its repository.
top=$(git -C "$spec_real" rev-parse --show-toplevel 2>/dev/null) || exit 0
top=$(cd -- "$top" 2>/dev/null && pwd -P) || exit 0
primary=$(cd -- "$spec_real" && env -u PLANWRIGHT_REPO_ROOT /bin/sh "$script_dir/resolve-root.sh" repo --primary 2>/dev/null) || exit 0
[ -n "$primary" ] && [ "$primary" != "$top" ] || exit 0
case "$spec_real" in
  "$top"/*) emit "$primary/${spec_real#"$top"/}/.orchestrate/markers" ;;
esac
exit 0
