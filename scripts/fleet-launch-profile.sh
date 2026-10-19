#!/bin/sh
# fleet-launch-profile.sh — print the settings profile a fleet launch seam
# passes with `--settings` (fleet-messaging D-19): `worker` for the three
# worker dispatch seams, `tower` for the fleet tower launches.
#
# The profile is `<root>/config/<kind>-settings.json`, the root being --root
# when the seam already holds the one it pins its session to, else the one
# fleet-dispatch-env.sh pins a session to when given none: PLANWRIGHT_ROOT,
# else the install this script runs from. The profile and the hooks it names
# then come from one install. A launch without its profile would run under
# whatever the operator's own settings say, which is the silent-delivery
# failure obs:eea622de recorded, so a profile that is missing, unreadable, or
# not a regular file is refused with the path named, and the seam refuses its
# launch on that exit.
#
# Usage: fleet-launch-profile.sh worker|tower [--root <abs-dir>]
# Exit: 0 the absolute path printed; 1 the profile cannot be read (named on
#   stderr); 2 usage, or no root resolves.
#
# POSIX sh; no eval. Pathname expansion is disabled.
set -uf

LC_ALL=C
export LC_ALL
unset CDPATH

me=fleet-launch-profile

usage() {
  printf '%s\n' "usage: $me worker|tower [--root <abs-dir>]" >&2
  exit 2
}

[ "$#" -ge 1 ] || usage
case $1 in
  worker | tower) kind=$1 ;;
  *) usage ;;
esac
shift
root=''
case $# in
  0) ;;
  2)
    [ "$1" = --root ] || usage
    case $2 in
      /*) root=$2 ;;
      *) usage ;;
    esac
    ;;
  *) usage ;;
esac

if [ -z "$root" ]; then
  root=${PLANWRIGHT_ROOT:-}
  [ -n "$root" ] || root=$(cd "$(dirname "$0")/.." 2>/dev/null && pwd -P) || {
    printf '%s\n' "$me: no planwright root resolves, so the $kind settings profile cannot be found; refusing to launch without it" >&2
    exit 2
  }
fi

profile="$root/config/$kind-settings.json"
if [ ! -f "$profile" ] || [ ! -r "$profile" ]; then
  printf '%s\n' "$me: cannot read the $kind settings profile $profile; refusing to launch without it" >&2
  exit 1
fi
printf '%s\n' "$profile"
