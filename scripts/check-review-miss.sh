#!/bin/sh
# check-review-miss.sh — the miss-ledger grammar guard (review-effectiveness
# REQ-E1.5, D-8). A miss is an observation fragment with the review-miss slug
# whose entry text follows the grammar doctrine/review-independence.md states;
# the backtest refresh and the cost metric read it by PR number and path, so a
# malformed miss would silently drop out of both. This guard fails it instead.
#
# Two modes:
#   check-review-miss.sh [--obs-dir <dir>]   every fragment under entries/ and
#       archive/ that is a miss by slug or by its entry text; a passing mention
#       of the grammar in another fragment is not a miss. The default store is
#       `_observations` under the resolved spec root. An absent directory is a
#       clean pass.
#   check-review-miss.sh --text <text>       one entry text, for a writer to
#       check before it calls scripts/obs-record.sh.
#
# The doctrine states the grammar; scripts/review-backtest-lib.sh implements it
# once (rbt_miss_fragment, rbt_miss_row), shared with the readers.
#
# Exit codes: 0 clean, 1 one or more malformed misses, 2 usage or internal
# error, a store directory or fragment that cannot be read safely (unreadable,
# a symlink, or not a regular file) included.
set -u
LC_ALL=C
export LC_ALL
unset CDPATH

prog=check-review-miss
here=$(cd "$(dirname "$0")" && pwd) || exit 2

if [ -r "$here/echo-safety.sh" ]; then
  # shellcheck source=scripts/echo-safety.sh
  . "$here/echo-safety.sh"
else
  sanitize_printable() { printf '%s' "$1" | tr -d '\000-\037\177\200-\237'; }
fi
[ -r "$here/review-backtest-lib.sh" ] || {
  printf '%s\n' "$prog: cannot read review-backtest-lib.sh" >&2
  exit 2
}
# shellcheck source=scripts/review-backtest-lib.sh
. "$here/review-backtest-lib.sh"

usage() {
  printf '%s\n' "usage: $prog [--obs-dir <dir>] | --text <text>" >&2
}

obsdir=
obsdir_set=0
text=
text_mode=0
while [ $# -gt 0 ]; do
  case $1 in
    --obs-dir | --text)
      [ $# -ge 2 ] || {
        usage
        exit 2
      }
      if [ "$1" = --text ]; then
        text=$2
        text_mode=1
      else
        obsdir=$2
        obsdir_set=1
      fi
      shift 2
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      usage
      exit 2
      ;;
  esac
done

if [ "$text_mode" -eq 1 ]; then
  if rbt_miss_row "$text" >/dev/null; then
    exit 0
  fi
  printf '%s\n' "$prog: $(sanitize_printable "$RBT_MISS_WHY")" >&2
  exit 1
fi

if [ "$obsdir_set" -eq 0 ]; then
  spec_root=$("$here/resolve-root.sh" spec) || {
    printf '%s\n' "$prog: cannot resolve the spec root; pass --obs-dir" >&2
    exit 2
  }
  obsdir=$spec_root/_observations
fi
case $obsdir in
  '' | -*)
    printf '%s\n' "$prog: the observations directory must be a non-empty path not beginning with a hyphen" >&2
    exit 2
    ;;
esac

if [ -e "$obsdir" ] && { [ ! -d "$obsdir" ] || [ ! -x "$obsdir" ]; }; then
  printf '%s\n' "$prog: cannot search the observations directory" >&2
  exit 2
fi

status=0
for dir in "$obsdir/entries" "$obsdir/archive"; do
  [ -e "$dir" ] || [ -L "$dir" ] || continue
  if [ -L "$dir" ] || [ ! -d "$dir" ] || [ ! -r "$dir" ] || [ ! -x "$dir" ]; then
    printf '%s\n' "$prog: ${dir##*/}: cannot read the directory safely" >&2
    status=2
    continue
  fi
  rbt_miss_prefilter "$dir"
  for f in "$dir"/*.md; do
    [ -e "$f" ] || [ -L "$f" ] || continue
    rc=0
    rbt_miss_fragment "$f" || rc=$?
    case $rc in
      1 | 4) continue ;;
      0) rbt_miss_row "$RBT_MISS_TEXT" >/dev/null && continue ;;
      2 | 3) ;;
    esac
    printf '%s\n' "$prog: ${dir##*/}/$(sanitize_printable "${f##*/}"): $(sanitize_printable "$RBT_MISS_WHY")" >&2
    if [ "$rc" -eq 3 ]; then
      status=2
    elif [ "$status" -eq 0 ]; then
      status=1
    fi
  done
  RBT_MISS_PREFILTER=0
done
exit "$status"
