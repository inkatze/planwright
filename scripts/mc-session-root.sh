#!/bin/sh
# mc-session-root.sh — judge the plugin root a session loaded at launch
# against the installed version. A session keeps the hooks of the root it
# started under, so one launched before an upgrade runs an older planwright;
# the launcher records that root in the session's registry row and list,
# doctor, the stall scan and the panel read one verdict from here.
#
# Usage:
#   mc-session-root.sh current-root    this install's canonical root
#   mc-session-root.sh verdict <root | ->
#     one tab-separated line: `current`; `stale <recorded> <installed>`;
#     or `unknown <why>` for no recorded root ("-" or empty, a row from
#     before the field) or a version that cannot be read, never `current`.
#
# A root's version is that of its .claude-plugin/plugin.json, else its
# directory name under the plugin cache; the installed version is that of
# the first root resolve-installed-roots.sh --current names.
# Exit: 0 for verdict; 2 usage.
set -u
LC_ALL=C
export LC_ALL
unset CDPATH

script_dir=$(cd "$(dirname "$0")" && pwd) || exit 2

usage() {
  printf '%s\n' "usage: mc-session-root.sh current-root | verdict <root | ->" >&2
  exit 2
}

# version_of <root>: print the root's version, or nothing.
version_of() {
  if [ -r "$1/.claude-plugin/plugin.json" ]; then
    vo_v=$(sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' \
      "$1/.claude-plugin/plugin.json" | head -n 1)
    [ -z "$vo_v" ] || {
      printf '%s\n' "$vo_v"
      return 0
    }
  fi
  vo_base=${1##*/}
  case $1 in
    */plugins/cache/*/planwright/*)
      case $vo_base in
        [0-9]*.[0-9]*) printf '%s\n' "$vo_base" ;;
      esac
      ;;
  esac
}

# older <a> <b>: 0 when version a is strictly older than version b, comparing
# the dotted numeric core (a pre-release or build suffix is dropped).
older() {
  awk -v a="$1" -v b="$2" 'BEGIN {
    sub(/[-+].*/, "", a); sub(/[-+].*/, "", b)
    na = split(a, x, "."); nb = split(b, y, ".")
    n = na > nb ? na : nb
    for (i = 1; i <= n; i++) {
      if ((x[i] + 0) < (y[i] + 0)) exit 0
      if ((x[i] + 0) > (y[i] + 0)) exit 1
    }
    exit 1
  }'
}

valid_version() {
  case $1 in
    "" | *[!0-9A-Za-z.+-]*) return 1 ;;
    [0-9]*) return 0 ;;
  esac
  return 1
}

[ $# -ge 1 ] || usage
case $1 in
  current-root)
    [ $# -eq 1 ] || usage
    cd "$script_dir/.." && pwd -P
    ;;
  verdict)
    [ $# -eq 2 ] || usage
    root=$2
    if [ -z "$root" ] || [ "$root" = - ]; then
      printf 'unknown\tno plugin root recorded at launch\n'
      exit 0
    fi
    rec=$(version_of "$root")
    if ! valid_version "$rec"; then
      printf 'unknown\tthe recorded root names no readable version\n'
      exit 0
    fi
    inst_root=$(/bin/sh "$script_dir/resolve-installed-roots.sh" --current </dev/null 2>/dev/null | head -n 1)
    inst=''
    [ -z "$inst_root" ] || inst=$(version_of "$inst_root")
    if ! valid_version "$inst"; then
      printf 'unknown\tthe installed version could not be read\n'
      exit 0
    fi
    if older "$rec" "$inst"; then
      printf 'stale\t%s\t%s\n' "$rec" "$inst"
    else
      printf 'current\n'
    fi
    ;;
  *) usage ;;
esac
