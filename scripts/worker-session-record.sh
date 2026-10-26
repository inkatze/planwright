#!/bin/sh
# worker-session-record.sh — write a dispatched worker's session record: the
# launch-time inputs its command guard trusts.
#
# Usage: worker-session-record.sh write <worktree> [<launch-id>]
#          [--scratch | --fresh-scratch]
#
# Resolves, once, from the worktree the worker will run in:
#   policy             worker_self_approval through the overlay layers,
#                      last value wins, read at the repository's primary
#                      checkout (as the policy guard reads its knobs), so an
#                      edit inside the worker's own worktree governs nothing;
#                      an unknown member, a malformed value, or a failed read
#                      resolves to the empty list
#   unit_branch        the branch checked out there, when it is a task or
#                      flight branch (otherwise omitted)
#   worktree_root      the worktree's canonical top level
#   pr_base            <remote>/<branch>: the unit branch's remote (origin
#                      when unset) and that remote's default branch as
#                      recorded locally, else main
#   worker_base_merge  the human-gates knob (omitted when it cannot be read)
#   scratch_root       with --scratch, the worktree's scratch root,
#                      <fleet-home>/scratch/<sha1-of-worktree-root>, whatever
#                      the launch id: created owner-only when absent and kept,
#                      contents and all, when present, so every plain stop,
#                      recover, and relaunch of the worker finds the same
#                      root. It must be this user's own directory, reached
#                      through no symlink; one that is not is omitted with a
#                      warning, which leaves the worker without the scratch
#                      arm. The launcher exports the recorded root as the
#                      worker's TMPDIR; the rung's final close (`stop
#                      --final`, which a reap makes) or `fleet-cleanup.sh
#                      worktree` removes it.
#                      --fresh-scratch empties a root left from an earlier
#                      worktree at the same path first, for a launcher that
#                      has just created the worktree
# and writes them as `key=value` lines to
# <fleet-home>/session-records/<sha1-of-worktree-root>.record, owner-only, by
# an atomic rename, printing the path. A <launch-id> (16 to 64 lowercase hex
# digits) names a record for that launch alone, <sha1>-<launch-id>.record, so
# a launch that loses a race to another never rewrites the winner's. The
# launcher exports that path to the worker as
# PLANWRIGHT_WORKER_SESSION_RECORD. The record lies outside the worktree (a
# fleet home inside it is refused), so nothing the worker writes there reaches
# it. A relaunch writes a fresh record from current config: the same file
# without a launch id, a new one with. `fleet-cleanup.sh worktree` removes
# every record for a worktree it reclaims.
#
# Exit: 0 written; 1 the record could not be resolved or written; 2 usage.
set -uf
LC_ALL=C
export LC_ALL
unset CDPATH

me=worker-session-record.sh
script_dir=$(cd "$(dirname "$0")" && pwd -P) || exit 1

die() {
  printf '%s: %s\n' "$me" "$1" >&2
  exit "${2:-1}"
}

usage="usage: $me write <worktree> [<launch-id>] [--scratch | --fresh-scratch]"
[ "$#" -ge 2 ] && [ "$1" = write ] || die "$usage" 2
wt_arg=$2
shift 2
launch_id=''
have_id=0
want_scratch=0
while [ "$#" -gt 0 ]; do
  case $1 in
    --scratch | --fresh-scratch)
      [ "$want_scratch" = 0 ] || die "$usage" 2
      want_scratch=1
      [ "$1" = --scratch ] || want_scratch=2
      shift
      ;;
    -*) die "$usage" 2 ;;
    *)
      [ "$have_id" = 0 ] || die "$usage" 2
      have_id=1
      launch_id=$1
      shift
      ;;
  esac
done
if [ "$have_id" = 1 ]; then
  case $launch_id in
    '' | *[!0-9a-f]*) die "the launch id must be 16 to 64 lowercase hex digits" 2 ;;
  esac
  [ "${#launch_id}" -ge 16 ] && [ "${#launch_id}" -le 64 ] || die "the launch id must be 16 to 64 lowercase hex digits" 2
fi

# The worktree is named by its argument alone: an inherited repository
# selector would point every git read below at another repository.
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY \
  GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_NAMESPACE GIT_CONFIG_PARAMETERS GIT_CONFIG_COUNT

gitq() {
  d=$1
  shift
  GIT_OPTIONAL_LOCKS=0 git -C "$d" "$@" 2>/dev/null </dev/null
}

wt=$(cd -P -- "$wt_arg" 2>/dev/null && pwd -P) || die "not a directory: the worktree"
top=$(gitq "$wt" rev-parse --show-toplevel) || die "not a git worktree"
wt=$(cd -P -- "$top" 2>/dev/null && pwd -P) || die "the worktree top level does not resolve"
# One record line per field: a control character in the path would split one.
case $wt in
  *[[:cntrl:]]*) die "the worktree path holds a control character" ;;
esac

# The primary checkout, where policy is read (scripts/policy-guard.sh,
# policy_root).
primary=''
common=$(gitq "$wt" rev-parse --path-format=absolute --git-common-dir) || common=''
case $common in
  /*/.git) primary=${common%/.git} ;;
esac
[ -n "$primary" ] && [ -d "$primary" ] || primary=''

policy=''
if [ -n "$primary" ]; then
  raw=$(cd -- "$primary" && PLANWRIGHT_REPO_ROOT=$primary /bin/sh "$script_dir/resolve-config-knob.sh" \
    --key worker_self_approval --type globlist --fallback '' --degrade '' 2>/dev/null </dev/null) || raw=''
  for m in $raw; do
    case $m in
      own-branch | scratch)
        case " $policy " in
          *" $m "*) ;;
          *) policy="${policy:+$policy }$m" ;;
        esac
        ;;
      *)
        policy=''
        break
        ;;
    esac
  done
fi

unit=$(gitq "$wt" symbolic-ref --quiet --short HEAD) || unit=''
case $unit in
  planwright/flight/task-*) unit='' ;;
  planwright/flight/*) printf '%s\n' "$unit" | grep -Eq '^planwright/flight/[a-z0-9][a-z0-9-]*-[0-9a-f]{8}$' || unit='' ;;
  planwright/*/task-*) printf '%s\n' "$unit" | grep -Eq '^planwright/[a-z0-9][a-z0-9-]*/task-[0-9]+(\.[0-9]+)?(-[0-9]+(\.[0-9]+)?)?$' || unit='' ;;
  *) unit='' ;;
esac

pr_base=''
if [ -n "$unit" ]; then
  remote=$(gitq "$wt" config --get "branch.$unit.remote") || remote=''
  case $remote in
    '' | .) remote=origin ;;
  esac
  case $remote in
    [A-Za-z0-9]*) ;;
    *) remote='' ;;
  esac
  case $remote in
    *[!A-Za-z0-9._-]*) remote='' ;;
  esac
  if [ -n "$remote" ]; then
    head=$(gitq "$wt" symbolic-ref --quiet --short "refs/remotes/$remote/HEAD") || head=''
    base=${head#"$remote"/}
    [ -n "$head" ] && [ "$base" != "$head" ] || base=main
    pr_base=$remote/$base
  fi
fi

base_merge=''
if [ -n "$primary" ]; then
  base_merge=$(cd -- "$primary" && PLANWRIGHT_REPO_ROOT=$primary /bin/sh "$script_dir/resolve-policy-knob.sh" \
    worker_base_merge 2>/dev/null </dev/null) || base_merge=''
  case $base_merge in
    allow | deny) ;;
    *) base_merge='' ;;
  esac
fi

home=$(/bin/sh "$script_dir/fleet-state.sh" root 2>/dev/null </dev/null) || die "cannot resolve the fleet home"
case $home in
  /*) ;;
  *) die "the fleet home is not an absolute path" ;;
esac
dir=$home/session-records
umask 077
mkdir -p -- "$dir" 2>/dev/null || die "cannot create the record directory"
dir=$(cd -P -- "$dir" && pwd -P) || die "the record directory does not resolve"
case $dir/ in
  "$wt"/*) die "the fleet home lies inside the worktree, where the worker could rewrite its record" ;;
esac

wt_key=$(printf '%s' "$wt" | git hash-object --stdin 2>/dev/null) || die "cannot name the record"
key=$wt_key
[ -z "$launch_id" ] || key=$key-$launch_id
rec=$dir/$key.record

# scratch_make <dir>: create the scratch root when absent, then print its
# canonical path when it is one the guard can trust.
scratch_make() {
  sm=$1
  case $sm in
    *[[:cntrl:]]*) return 1 ;;
  esac
  # An existing root is kept; the checks below decide either way.
  mkdir -- "$sm" 2>/dev/null || : # not-a-lock: creating the scratch root, whose checks follow
  [ -d "$sm" ] && [ ! -L "$sm" ] || return 1
  [ "$(find "$sm" -maxdepth 0 -user "$(id -u)" 2>/dev/null)" = "$sm" ] || return 1
  chmod 700 -- "$sm" 2>/dev/null || return 1
  sm=$(cd -P -- "$sm" 2>/dev/null && pwd -P) || return 1
  case $sm/ in
    "$wt"/* | "$dir"/*) return 1 ;;
  esac
  case $wt/ in
    "$sm"/*) return 1 ;;
  esac
  case $dir/ in
    "$sm"/*) return 1 ;;
  esac
  printf '%s\n' "$sm"
}

scratch=''
sroot=$home/scratch/$wt_key
if [ "$want_scratch" = 2 ] && [ -d "$sroot" ] && [ ! -L "$sroot" ]; then
  find "$sroot" -type d ! -perm -700 -exec chmod u+rwx {} \; 2>/dev/null || :
  rm -rf -- "$sroot" 2>/dev/null || :
  # A root that would not empty keeps an earlier worker's files: no root.
  [ ! -e "$sroot" ] || want_scratch=3
fi
if { [ "$want_scratch" = 1 ] || [ "$want_scratch" = 2 ]; } && mkdir -p -- "$home/scratch" 2>/dev/null; then
  scratch=$(scratch_make "$sroot") || scratch=''
fi
[ "$want_scratch" = 0 ] || [ -n "$scratch" ] \
  || printf '%s: the scratch root is unusable; the worker gets no scratch arm\n' "$me" >&2
tmp=$(mktemp "$dir/.$key.XXXXXX") || die "cannot write the record"
if ! {
  printf 'policy=%s\n' "$policy"
  [ -z "$unit" ] || printf 'unit_branch=%s\n' "$unit"
  printf 'worktree_root=%s\n' "$wt"
  [ -z "$pr_base" ] || printf 'pr_base=%s\n' "$pr_base"
  [ -z "$base_merge" ] || printf 'worker_base_merge=%s\n' "$base_merge"
  [ -z "$scratch" ] || printf 'scratch_root=%s\n' "$scratch"
} >"$tmp" || ! mv -f -- "$tmp" "$rec"; then
  rm -f -- "$tmp"
  die "cannot write the record"
fi
printf '%s\n' "$rec"
