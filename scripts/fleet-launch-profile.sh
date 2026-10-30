#!/bin/sh
# fleet-launch-profile.sh — print the settings profile a fleet launch seam
# passes with `--settings` (fleet-messaging D-19): `worker` for the three
# worker dispatch seams, `tower` for the fleet tower launches, and
# `mission-control` for scripts/mission-control-launch.sh, which also
# resolves the other two for the session kinds it starts.
#
# The profile is `<root>/config/<kind>-settings.json`, the root being --root
# when the seam already holds the one it pins its session to, else the one the
# core root chain names (scripts/resolve-root.sh install), whose first arms are
# the PLANWRIGHT_ROOT and CLAUDE_PLUGIN_ROOT values fleet-dispatch-env.sh pins
# a session to, so the profile and the hooks it names come from one install.
# A launch without its profile would run under whatever the operator's own
# settings say, which is the silent-delivery failure obs:eea622de recorded, so
# a profile that is missing, unreadable, not a regular file, or reached through
# a symbolic link is refused with the path named, and the seam refuses its
# launch on that exit.
#
# Usage: fleet-launch-profile.sh worker|tower|mission-control [--root <abs-dir>]
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
  printf '%s\n' "usage: $me worker|tower|mission-control [--root <abs-dir>]" >&2
  exit 2
}

[ "$#" -ge 1 ] || usage
case $1 in
  worker | tower | mission-control) kind=$1 ;;
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
  script_dir=$(cd "$(dirname "$0")" && pwd) || exit 2
  root=$(/bin/sh "$script_dir/resolve-root.sh" install 2>/dev/null </dev/null) || root=''
  if [ -z "$root" ]; then
    printf '%s\n' "$me: no planwright root resolves, so the $kind settings profile cannot be found; refusing to launch without it" >&2
    exit 2
  fi
fi

profile="$root/config/$kind-settings.json"
# A link could load another install's policy while the session's hooks stay
# pinned to this root.
if [ -L "$root/config" ] || [ -L "$profile" ] || [ ! -f "$profile" ] || [ ! -r "$profile" ]; then
  printf '%s\n' "$me: cannot read the $kind settings profile $profile; refusing to launch without it" >&2
  exit 1
fi
printf '%s\n' "$profile"
