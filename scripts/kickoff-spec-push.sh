#!/bin/sh
# kickoff-spec-push.sh - push a spec's sign-off branch, and nothing else.
#
# Usage: kickoff-spec-push.sh <spec>
#
# The one push a kickoff session may make. The policy guard admits it only to
# the worker launched as that spec's kickoff, on that spec's branch; this
# script checks the branch and runs one plain `git push -u origin`. It never
# forces, deletes, or pushes another ref, and git refuses a non-fast-forward.
#
# Exit: 0 pushed; 1 refused here; otherwise git's own push status.
set -u
LC_ALL=C
export LC_ALL
unset CDPATH

die() {
  printf '%s\n' "kickoff-spec-push: $1" >&2
  exit 1
}

[ "$#" = 1 ] || die "usage: kickoff-spec-push.sh <spec>"
spec=$1
case $spec in
  [a-z0-9]*) ;;
  *) die "'$spec' is not a spec name (lowercase letters, digits and hyphens)" ;;
esac
case $spec in
  *[!a-z0-9-]*) die "'$spec' is not a spec name (lowercase letters, digits and hyphens)" ;;
esac

branch=planwright/$spec/spec
current=$(git symbolic-ref --quiet --short HEAD) \
  || die "HEAD is detached; check out $branch first"
[ "$current" = "$branch" ] \
  || die "this checkout is on '$current', not $branch; run it from the spec branch"

exec git push -u origin "$branch"
