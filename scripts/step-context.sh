# shellcheck shell=sh
# step-context.sh — sourced, never run: fills the step-context variables git
# already knows when the caller left them unset, and refuses one a caller
# exported that disagrees with git. step-run.sh, step-record.sh, and
# resolve-steps.sh --preamble source it, so a worker runs each bare, with no
# PLANWRIGHT_STEP_* prefix; each maps the refusal to its own exit code.
#
#   step_context_derive <worktree> [<program name for messages>]
#     <worktree> is the unit's worktree, absolute and canonical.
#       PLANWRIGHT_STEP_WORKTREE    <worktree> itself; an exported path that
#                                   resolves to it is replaced by it
#       PLANWRIGHT_STEP_BRANCH      the branch HEAD names (none on a detached
#                                   HEAD, or when <worktree> is not the top of
#                                   its own work tree)
#       PLANWRIGHT_STEP_BASE_BRANCH main (not derived: a repository whose base
#                                   is another branch exports it)
#       PLANWRIGHT_STEP_UNIT_KIND   flight for planwright/flight/<id>, spec for
#                                   planwright/<spec>/spec, task for
#                                   planwright/<spec>/task-<ids>; none for any
#                                   other branch, planwright/flight/task-*
#                                   included
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
    if [ "$scd_canon" = "$scd_wt" ]; then
      PLANWRIGHT_STEP_WORKTREE=$scd_wt
      export PLANWRIGHT_STEP_WORKTREE
    else
      scd_bad="$scd_bad PLANWRIGHT_STEP_WORKTREE is '$scd_cur' but the worktree is '$scd_wt' (a literal absolute path);"
    fi
  fi

  # A directory inside another repository would answer with that repository's
  # branch, so only a worktree that is its own top is asked. The full ref is
  # read because --short turns ambiguous when a tag shares the branch's name.
  scd_ref=''
  if scd_top=$(step_context_top "$scd_wt") && [ "$scd_top" = "$scd_wt" ]; then
    scd_ref=$(step_context_git -C "$scd_wt" symbolic-ref -q HEAD 2>/dev/null) || scd_ref=''
  fi
  scd_branch=''
  case $scd_ref in refs/heads/?*) scd_branch=${scd_ref#refs/heads/} ;; esac
  if [ -n "$scd_branch" ]; then
    scd_cur=${PLANWRIGHT_STEP_BRANCH:-}
    if [ -z "$scd_cur" ]; then
      PLANWRIGHT_STEP_BRANCH=$scd_branch
      export PLANWRIGHT_STEP_BRANCH
    elif [ "$scd_cur" != "$scd_branch" ]; then
      scd_bad="$scd_bad PLANWRIGHT_STEP_BRANCH is '$scd_cur' but git's branch is '$scd_branch';"
    fi
    scd_kind=''
    # The guards' unit-branch shape, without their id charsets: one segment
    # after the spec or flight, and planwright/flight/task-* no unit at all.
    case $scd_branch in
      planwright/flight/task-* | planwright/*/*/*) ;;
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
  printf '%s\n' "$scd_me:$(printf '%s' "$scd_bad" | tr -d '\000-\037\177\200-\237') an exported value that disagrees with git is refused; unset or correct it, or the launch record it came from" >&2
  return 2
}

# step_context_git <args>: git with every inherited variable that would point
# it at another repository, object store, or config cleared, a guarded
# caller's driver settings excepted.
step_context_git() (
  unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY \
    GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_COMMON_DIR GIT_NAMESPACE \
    GIT_CONFIG_PARAMETERS GIT_CEILING_DIRECTORIES
  [ "${PW_UNTRUSTED_GIT:-}" = 1 ] || unset GIT_CONFIG_COUNT
  exec git "$@"
)

# step_context_top [<dir>]: prints the canonical top of the work tree <dir>
# (the working directory by default) lies in; fails outside one.
step_context_top() {
  sct_top=$(step_context_git -C "${1:-.}" rev-parse --show-toplevel 2>/dev/null) || return 1
  (cd -P -- "$sct_top" 2>/dev/null && pwd -P)
}
