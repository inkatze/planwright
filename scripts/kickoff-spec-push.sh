#!/bin/sh
# kickoff-spec-push.sh - push a spec's sign-off branch, and nothing else.
#
# Usage: kickoff-spec-push.sh <spec>
#
# A kickoff session pushes planwright/<spec>/spec with this script, never with
# a raw `git push`: the worker profiles deny the raw spelling for every spec
# branch. The policy guard decides which session may run it (only the worker
# launched as the kickoff of <spec>, on that spec's branch); this script
# enforces the rest. It runs one plain `git push -u origin` of the current
# branch, which must be planwright/<spec>/spec, and never forces, deletes, or
# pushes any other ref. A non-fast-forward push is refused by git and left
# refused.
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
