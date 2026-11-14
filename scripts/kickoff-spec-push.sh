#!/bin/sh
# kickoff-spec-push.sh - push a spec's sign-off branch, and nothing else.
#
# Usage: kickoff-spec-push.sh <spec>
#
# The one push a kickoff session may make. The policy guard admits it only to
# the worker launched as that spec's kickoff: on that spec's branch or one of
# its amendment branches (planwright/<spec>/amendment-<n>, digits only), or,
# for an amendment kickoff, on its own amendment branch alone. This script
# checks the branch and runs one plain `git push -u origin` of that branch to
# the same name. It never forces, deletes, or pushes another ref, and git
# refuses a non-fast-forward.
#
# Exit: 0 pushed; 1 refused here; otherwise git's own push status.
set -u
# LC_ALL=C is for this script's own parsing only. The adopter's pre-push hooks
# run under the caller's locale (C.UTF-8 when the caller sets none): a C locale
# there breaks UTF-8 file names in the hooked tools.
if [ -n "${LC_ALL:-}" ]; then
  hook_lc_all=$LC_ALL
elif [ -n "${LC_CTYPE:-}${LANG:-}" ]; then
  hook_lc_all=
else
  hook_lc_all=C.UTF-8
fi
LC_ALL=C
export LC_ALL
unset CDPATH
unset GIT_DIR GIT_WORK_TREE GIT_COMMON_DIR GIT_INDEX_FILE GIT_OBJECT_DIRECTORY \
  GIT_CONFIG GIT_CONFIG_PARAMETERS GIT_CONFIG_COUNT GIT_NAMESPACE GIT_PREFIX

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
[ "${#spec}" -le 64 ] || die "'$spec' is longer than 64 characters"
[ "$spec" != flight ] || die "'flight' is the flight namespace, not a spec"

form="\${CLAUDE_PLUGIN_ROOT}/scripts/kickoff-spec-push.sh <spec>"
current=$(git symbolic-ref --quiet --short HEAD) \
  || die "HEAD is detached; check out planwright/$spec/spec or one of its amendment branches first (run as $form)"
case $current in
  "planwright/$spec/spec") ;;
  "planwright/$spec/amendment-"*)
    case ${current#"planwright/$spec/amendment-"} in
      '' | *[!0-9]*) die "this checkout is on '$current', not planwright/$spec/spec or planwright/$spec/amendment-<n> (digits only); run as $form" ;;
    esac
    ;;
  *) die "this checkout is on '$current', not planwright/$spec/spec or planwright/$spec/amendment-<n>; run as $form from one of them" ;;
esac

# A session's launch scope binds the push here, at run time, since the guard
# reads the branch before a command runs and anything may move HEAD after it
# or run this script where the guard never sees it. No scope is an attended
# run, which the branch checks above govern alone.
scope=${PLANWRIGHT_WORKER_SCOPE:-}
not_kickoff="this session is not the kickoff for $spec (launch scope '$scope'), so it may not push; only a session launched with scope kickoff-$spec, or kickoff-$spec-a<n> on planwright/$spec/amendment-<n>, runs $form"
if [ -n "$scope" ] && [ "$scope" != "kickoff-$spec" ]; then
  case $scope in
    "kickoff-$spec-a"[0-9]*) ;;
    *) die "$not_kickoff" ;;
  esac
  rest=${scope#"kickoff-$spec-a"}
  n=${rest%%[!0-9]*}
  rest=${rest#"$n"}
  case $rest in
    '' | [a-z]) ;;
    -*)
      case ${rest#-} in '' | *[!a-z0-9]*) die "$not_kickoff" ;; esac
      ;;
    *) die "$not_kickoff" ;;
  esac
  [ "$current" = "planwright/$spec/amendment-$n" ] \
    || die "amendment $n's kickoff for $spec pushes only planwright/$spec/amendment-$n, and this checkout is on '$current'; check that branch out and run $form"
fi

# A full refspec: a short name is mapped through remote.origin.push, which can
# carry an amendment branch onto the spec branch.
refspec="refs/heads/$current:refs/heads/$current"
if [ -n "$hook_lc_all" ]; then
  exec env LC_ALL="$hook_lc_all" git push -u origin "$refspec"
fi
exec env -u LC_ALL git push -u origin "$refspec"
