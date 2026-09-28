#!/bin/sh
# protected-branch.sh — decide whether a branch is outside the protected set
# (the core floor plus the protected_branches additions, read locally through
# resolve-policy-knob.sh; the host is never queried).
#
# Usage: protected-branch.sh <branch>
#
# The branch may carry a `refs/heads/` prefix, which is stripped, as it is from
# each entry of the set. An entry is a name or a glob matched segment by
# segment, so `*` and `?` never span a `/`: `planwright/*/spec` protects
# `planwright/x/spec` and not `planwright/a/b/spec`.
#
# Exit 0 ONLY when the branch is outside the set; every other exit refuses the
# act: 1 protected, 2 usage or an invalid branch name, and the resolver's own
# exit when the set cannot be read (4 malformed, 5 broken install). The clear
# answer is the zero exit so a caller that tests only for success fails closed.
set -uf

LC_ALL=C
export LC_ALL
unset CDPATH

script_dir=$(cd "$(dirname "$0")" && pwd) || exit 2
# shellcheck source=scripts/echo-safety.sh
. "$script_dir/echo-safety.sh"

[ "$#" -eq 1 ] || {
  echo "usage: protected-branch.sh <branch>" >&2
  exit 2
}

name=${1#refs/heads/}
refuse_name() {
  printf '%s\n' "protected-branch: invalid branch name '$(sanitize_printable "$1" "(unprintable name)")'" >&2
  exit 2
}
case "$name" in
  "" | -* | /* | */ | *//* | *..* | *[!A-Za-z0-9._/-]*) refuse_name "$1" ;;
esac
[ "${#name}" -le 255 ] || refuse_name "$1"

set_out=$(/bin/sh "$script_dir/resolve-policy-knob.sh" protected_branches) || {
  rc=$?
  echo "protected-branch: the protected set could not be read; refusing" >&2
  exit "$rc"
}

# seg_match <pattern> <name>: 0 when every `/`-separated segment of the name
# matches the pattern's segment at the same position and the counts agree.
seg_match() {
  _p=$1
  _n=$2
  while :; do
    case "$_p" in
      */*)
        _ph=${_p%%/*}
        _p=${_p#*/}
        _pm=1
        ;;
      *)
        _ph=$_p
        _pm=0
        ;;
    esac
    case "$_n" in
      */*)
        _nh=${_n%%/*}
        _n=${_n#*/}
        _nm=1
        ;;
      *)
        _nh=$_n
        _nm=0
        ;;
    esac
    # shellcheck disable=SC2254 # the entry is a pattern on purpose
    case "$_nh" in
      $_ph) ;;
      *) return 1 ;;
    esac
    [ "$_pm" = "$_nm" ] || return 1
    [ "$_pm" = 1 ] || return 0
  done
}

for entry in $set_out; do
  if seg_match "${entry#refs/heads/}" "$name"; then
    printf '%s\n' "protected-branch: '$name' is protected (matches '$entry')" >&2
    exit 1
  fi
done
exit 0
