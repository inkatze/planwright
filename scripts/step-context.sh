# shellcheck shell=sh
# step-context.sh — sourced, never run: fills the step-context variables git
# already knows when the caller left them unset, and refuses one a caller
# exported that disagrees with git. step-run.sh and step-record.sh source it,
# so a worker runs either bare, with no PLANWRIGHT_STEP_* prefix.
#
#   step_context_derive <worktree> [<program name for messages>]
#     <worktree> is the unit's worktree, absolute and canonical.
#       PLANWRIGHT_STEP_WORKTREE    <worktree> itself
#       PLANWRIGHT_STEP_BRANCH      `git symbolic-ref --short HEAD` (none on a
#                                   detached HEAD)
#       PLANWRIGHT_STEP_BASE_BRANCH main
#       PLANWRIGHT_STEP_UNIT_KIND   flight for planwright/flight/<id>, spec for
#                                   planwright/<spec>/spec, task for
#                                   planwright/<spec>/task-<ids>; none for any
#                                   other branch
#     A variable set non-empty is kept when it equals what git says, and
#     refused (return 2, both values on stderr) when it differs. The base
#     branch has nothing to disagree with, and the spec, task ids, and PR
#     number are never derived. Sets and exports only the variables it can
#     derive; returns 0 otherwise.
#
# POSIX sh; the caller owns `die` handling of the return.
unset CDPATH

step_context_derive() {
  scd_wt=$1
  scd_me=${2:-step-context}
  scd_bad=''

  scd_cur=${PLANWRIGHT_STEP_WORKTREE:-}
  if [ -z "$scd_cur" ]; then
    PLANWRIGHT_STEP_WORKTREE=$scd_wt
    export PLANWRIGHT_STEP_WORKTREE
  elif [ "$scd_cur" != "$scd_wt" ]; then
    case $scd_cur in
      /*) scd_canon=$(cd -P -- "$scd_cur" 2>/dev/null && pwd -P) || scd_canon='' ;;
      *) scd_canon='' ;;
    esac
    [ "$scd_canon" = "$scd_wt" ] \
      || scd_bad="$scd_bad PLANWRIGHT_STEP_WORKTREE is '$scd_cur' but the worktree is '$scd_wt' (a literal absolute path);"
  fi

  scd_branch=$(
    unset GIT_DIR GIT_WORK_TREE GIT_COMMON_DIR GIT_INDEX_FILE
    git -C "$scd_wt" symbolic-ref --short HEAD 2>/dev/null
  ) || scd_branch=''
  if [ -n "$scd_branch" ]; then
    scd_cur=${PLANWRIGHT_STEP_BRANCH:-}
    if [ -z "$scd_cur" ]; then
      PLANWRIGHT_STEP_BRANCH=$scd_branch
      export PLANWRIGHT_STEP_BRANCH
    elif [ "$scd_cur" != "$scd_branch" ]; then
      scd_bad="$scd_bad PLANWRIGHT_STEP_BRANCH is '$scd_cur' but git's branch is '$scd_branch';"
    fi
    scd_kind=''
    case $scd_branch in
      planwright/flight/?*) scd_kind=flight ;;
      planwright/?*/spec) scd_kind=spec ;;
      planwright/?*/task-?*) scd_kind=task ;;
    esac
    if [ -n "$scd_kind" ]; then
      scd_cur=${PLANWRIGHT_STEP_UNIT_KIND:-}
      if [ -z "$scd_cur" ]; then
        PLANWRIGHT_STEP_UNIT_KIND=$scd_kind
        export PLANWRIGHT_STEP_UNIT_KIND
      elif [ "$scd_cur" != "$scd_kind" ]; then
        scd_bad="$scd_bad PLANWRIGHT_STEP_UNIT_KIND is '$scd_cur' but branch '$scd_branch' is a $scd_kind;"
      fi
    fi
  fi

  if [ -z "${PLANWRIGHT_STEP_BASE_BRANCH:-}" ]; then
    PLANWRIGHT_STEP_BASE_BRANCH=main
    export PLANWRIGHT_STEP_BASE_BRANCH
  fi

  [ -z "$scd_bad" ] && return 0
  printf '%s\n' "$scd_me:$(printf '%s' "$scd_bad" | tr -d '\000-\037\177') an exported value that disagrees with git is refused; unset it or fix it" >&2
  return 2
}
