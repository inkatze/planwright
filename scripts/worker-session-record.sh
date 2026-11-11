#!/bin/sh
# worker-session-record.sh — write a dispatched worker's session record: the
# launch-time inputs its command guard trusts.
#
# Usage: worker-session-record.sh write <worktree> [<launch-id> | --session <handle>] [--base <branch> | --base-from-pr]
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
#   stack_base         <remote>/<branch>: the base of a stacked pull request
#                      (one whose base is another feature branch), from
#                      --base <branch> or, with --base-from-pr, the PR's
#                      baseRefName read once from gh (the one network call,
#                      made only on request); omitted when it is the default base,
#                      outside the branch grammar, or unknown. It is the one
#                      branch besides the default base a worker's base merge
#                      may take (scripts/policy-guard.sh,
#                      scripts/converge-sync-main.sh --base)
#   worker_base_merge  the human-gates knob (omitted when it cannot be read)
#   scratch_root       with --scratch, the worktree's scratch root, a short
#                      directory outside the fleet home that
#                      scripts/fleet-scratch.sh places and records, whatever
#                      the launch id: created owner-only when absent and kept,
#                      contents and all, when present, so every plain stop,
#                      recover, and relaunch of the worker finds the same
#                      root. It must be this user's own directory, reached
#                      through no symlink; one that is not is omitted with a
#                      warning, which leaves the worker without the scratch
#                      arm. The launcher exports the recorded root as the
#                      worker's TMPDIR; the rung's final close (`stop
#                      --final`, which a reap makes) removes it (an
#                      earlier-layout worktree root still in use beside the
#                      worker is left: scripts/fleet-stop-lib.sh), and
#                      `fleet-cleanup.sh worktree` removes it whatever its use.
#                      --fresh-scratch replaces a root left from an earlier
#                      worktree at the same path first, for a launcher that
#                      has just created the worktree.
#                      --session <handle> gives one session of several
#                      sharing a worktree a root of its own, keyed by
#                      <hash-of-worktree-root>-<hash-of-handle>, so a
#                      session's final close removes its files alone, never
#                      another session's
#   hook_exclude       worker_hook_exclude as a comma-joined list, omitted
#                      when unset or when any member falls outside
#                      [A-Za-z0-9_-]; the launcher exports it as
#                      LEFTHOOK_EXCLUDE (scripts/fleet-dispatch-env.sh)
#   audit_log_home     <fleet-home>/allow-audit, owner-only, where the guard
#                      appends a line per approval to <record-name>.log. Every
#                      write first prunes the logs there older than
#                      worker_audit_log_retention_days days (read like the
#                      policy; its default when it cannot be read). An
#                      unusable home is omitted with a warning, which leaves
#                      the worker without either write arm
# and writes them as `key=value` lines to
# <fleet-home>/session-records/<hash-of-worktree-root>.record, owner-only, by
# an atomic rename, printing the path. Each <hash> is `git hash-object`'s, in
# the repository's object format. A <launch-id> (16 to 64 lowercase hex
# digits) names a record for that launch alone, <hash>-<launch-id>.record, so
# a launch that loses a race to another never rewrites the winner's. The
# launcher exports that path to the worker as
# PLANWRIGHT_WORKER_SESSION_RECORD. With --session <handle> (the field
# grammar, never with a <launch-id>) the record is
# <hash-of-worktree-root>-<hash-of-handle>.record, that session's alone, and
# names that session's own scratch root. The record lies outside the worktree (a
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

branch_grammar_ok() {
  case $1 in
    '' | -* | /* | */ | *//* | *..* | *[!A-Za-z0-9._/+@-]* | *.lock | *.lock/* | */.* | .* | *.) return 1 ;;
  esac
  return 0
}

usage="usage: $me write <worktree> [<launch-id> | --session <handle>] [--base <branch> | --base-from-pr] [--scratch | --fresh-scratch]"
[ "$#" -ge 2 ] && [ "$1" = write ] || die "$usage" 2
wt_arg=$2
shift 2
launch_id=''
have_id=0
session=''
stack_arg=''
have_base=0
want_scratch=0
while [ "$#" -gt 0 ]; do
  case $1 in
    --scratch | --fresh-scratch)
      [ "$want_scratch" = 0 ] || die "$usage" 2
      want_scratch=1
      [ "$1" = --scratch ] || want_scratch=2
      shift
      ;;
    --base-from-pr)
      [ "$have_base" = 0 ] || die "$usage" 2
      have_base=2
      shift
      ;;
    --base)
      [ "$#" -ge 2 ] && [ "$have_base" = 0 ] || die "$usage" 2
      branch_grammar_ok "$2" || die "--base is outside the branch grammar" 2
      stack_arg=$2
      have_base=1
      shift 2
      ;;
    --session)
      [ "$#" -ge 2 ] && [ -z "$session" ] && [ "$have_id" = 0 ] || die "$usage" 2
      case $2 in
        '' | -* | . | .. | *[!A-Za-z0-9._=@:-]*) die "the session handle is outside the handle grammar (no leading dash, letters, digits and . _ = @ : - only)" 2 ;;
      esac
      session=$2
      shift 2
      ;;
    -*) die "$usage" 2 ;;
    *)
      [ "$have_id" = 0 ] && [ -z "$session" ] || die "$usage" 2
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

hook_exclude=''
if [ -n "$primary" ]; then
  raw=$(cd -- "$primary" && PLANWRIGHT_REPO_ROOT=$primary /bin/sh "$script_dir/resolve-config-knob.sh" \
    --key worker_hook_exclude --type globlist --fallback '' --degrade '' 2>/dev/null </dev/null) || raw=''
  for m in $raw; do
    case $m in
      '' | *[!A-Za-z0-9_-]*)
        hook_exclude=''
        break
        ;;
      *) hook_exclude="${hook_exclude:+$hook_exclude,}$m" ;;
    esac
  done
fi

unit=$(gitq "$wt" symbolic-ref --quiet --short HEAD) || unit=''
case $unit in
  planwright/flight/task-*) unit='' ;;
  planwright/flight/*) printf '%s\n' "$unit" | grep -Eq '^planwright/flight/[a-z0-9][a-z0-9-]*-[0-9a-f]{8}$' || unit='' ;;
  planwright/*/task-*) printf '%s\n' "$unit" | grep -Eq '^planwright/[a-z0-9][a-z0-9-]*/task-[0-9]+[a-z]?(\.[0-9]+[a-z]?)?(-[0-9]+[a-z]?(\.[0-9]+[a-z]?)?)?$' || unit='' ;;
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

# A stacked PR's base is another feature branch: the one the launcher names
# with --base, else the PR's own baseRefName read once from gh. It is kept
# only when it differs from the default base the record already names, and
# only inside the branch grammar the guards re-check.
stack_base=''
if [ -n "$pr_base" ]; then
  if [ "$have_base" = 2 ] && command -v gh >/dev/null 2>&1; then
    stack_arg=$(cd -- "$wt" 2>/dev/null && /bin/sh "$script_dir/bounded-run.sh" 15 gh pr view "$unit" --json baseRefName --jq .baseRefName 2>/dev/null </dev/null | head -n 1) || stack_arg=''
  fi
  if [ -n "$stack_arg" ] && [ "$stack_arg" != "${pr_base#*/}" ] && branch_grammar_ok "$stack_arg"; then
    stack_base=${pr_base%%/*}/$stack_arg
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
days=''
if [ -n "$primary" ]; then
  days=$(cd -- "$primary" && PLANWRIGHT_REPO_ROOT=$primary /bin/sh "$script_dir/resolve-config-knob.sh" \
    --key worker_audit_log_retention_days --type posint --fallback 30 2>/dev/null </dev/null) || days=''
fi
case $days in
  '' | *[!0-9]*) days=30 ;;
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
sess_key=''
if [ -n "$session" ]; then
  sess_key=$(printf '%s' "$session" | git hash-object --stdin 2>/dev/null) || die "cannot name the session's record"
  key=$key-$sess_key
fi
rec=$dir/$key.record

# scratch_trusted <dir>: succeed when the scratch root is canonical and one
# the guard can trust: apart from the worktree and the record directory in
# both directions.
scratch_trusted() {
  sm=$(cd -P -- "$1" 2>/dev/null && pwd -P) || return 1
  [ "$sm" = "$1" ] || return 1
  case $sm/ in
    "$wt"/* | "$dir"/*) return 1 ;;
  esac
  case $wt/ in
    "$sm"/*) return 1 ;;
  esac
  case $dir/ in
    "$sm"/*) return 1 ;;
  esac
}

scratch=''
why=''
nl='
'
skey=$wt_key
[ -z "$sess_key" ] || skey=$wt_key-$sess_key
if [ "$want_scratch" != 0 ]; then
  set --
  [ "$want_scratch" != 2 ] || set -- --fresh
  # Its last line is the root, or on failure the reason, whatever stray line
  # a shell prints ahead of either.
  if scratch=$(/bin/sh "$script_dir/fleet-scratch.sh" make "$home" "$skey" "$@" 2>&1 </dev/null); then
    scratch=${scratch##*"$nl"}
  else
    why=${scratch##*"$nl"}
    scratch=''
  fi
  if [ -n "$scratch" ] && ! scratch_trusted "$scratch"; then
    /bin/sh "$script_dir/fleet-scratch.sh" release "$home" "$scratch" >/dev/null 2>&1 </dev/null || :
    why="the root $scratch lies inside the worktree or the record directory"
    scratch=''
  fi
fi
[ "$want_scratch" = 0 ] || [ -n "$scratch" ] \
  || printf '%s: the scratch root is unusable; the worker gets no scratch arm%s\n' "$me" "${why:+ ($why)}" >&2

# audit_make <dir>: create the audit-log home when absent, prune its logs
# past the retention bound, then print its canonical path when the guard can
# trust it. The guard only appends, so pruning is the launch's job.
audit_make() {
  am=$1
  mkdir -- "$am" 2>/dev/null || : # not-a-lock: creating the audit-log home, whose checks follow
  [ -d "$am" ] && [ ! -L "$am" ] || return 1
  [ "$(find "$am" -maxdepth 0 -user "$(id -u)" 2>/dev/null)" = "$am" ] || return 1
  chmod 700 "$am" 2>/dev/null || return 1
  am=$(cd -P -- "$am" 2>/dev/null && pwd -P) || return 1
  case $am/ in
    "$wt"/*) return 1 ;;
  esac
  if [ -n "$scratch" ]; then
    case $am/ in
      "$scratch"/*) return 1 ;;
    esac
  fi
  find "$am" -maxdepth 1 -type f -name '*.log' -mtime +"$days" -exec rm -f -- {} + 2>/dev/null || :
  printf '%s\n' "$am"
}
audit=$(audit_make "$home/allow-audit") || audit=''
[ -n "$audit" ] \
  || printf '%s: the audit-log home is unusable; the worker gets no write arm\n' "$me" >&2
tmp=$(mktemp "$dir/.$key.XXXXXX") || die "cannot write the record"
if ! {
  printf 'policy=%s\n' "$policy"
  [ -z "$unit" ] || printf 'unit_branch=%s\n' "$unit"
  printf 'worktree_root=%s\n' "$wt"
  [ -z "$pr_base" ] || printf 'pr_base=%s\n' "$pr_base"
  [ -z "$stack_base" ] || printf 'stack_base=%s\n' "$stack_base"
  [ -z "$base_merge" ] || printf 'worker_base_merge=%s\n' "$base_merge"
  [ -z "$scratch" ] || printf 'scratch_root=%s\n' "$scratch"
  [ -z "$audit" ] || printf 'audit_log_home=%s\n' "$audit"
  [ -z "$hook_exclude" ] || printf 'hook_exclude=%s\n' "$hook_exclude"
} >"$tmp" || ! mv -f -- "$tmp" "$rec"; then
  rm -f -- "$tmp"
  die "cannot write the record"
fi
printf '%s\n' "$rec"
