#!/bin/sh
# worker-branch-sync.sh - a dispatched worker's routine sync of its own unit
# branch: the three acts the worker profile's deny floor keeps from raw git.
#
# Usage (from the worker's own worktree, by the installed script's path):
#   worker-branch-sync.sh push --force-with-lease=<branch:sha> --force-if-includes
#   worker-branch-sync.sh reset <origin/branch>
#   worker-branch-sync.sh ff <sha>
#
# The lease is written <branch>:<sha>, <sha> the full id of the tip the
# rewrite started from. push publishes the rewrite only while the branch heads
# one open draft PR of this repository; reset is git reset --hard to
# origin/<branch> as fetched; ff is git merge --ff-only to a full commit id
# descending from HEAD.
#
# Every verb refuses unless it runs in a linked worktree that the session
# record (PLANWRIGHT_WORKER_SESSION_RECORD, the user's own file outside the
# worktree) names, on the unit branch it names; that task or flight branch is
# outside the protected set; and no other worktree, nor any process outside
# this run's own ancestry, works on it. reset and ff need a clean tree. The
# lease must be a tip the branch's reflog records: git turns
# --force-if-includes off for an explicit lease, so this is that check. A push
# the remote refuses for a moved branch means someone else pushed: the branch
# is shared, and the push is never retried with another lease. Exit: 0 done;
# 1 refused; 2 usage; 3 a git or gh failure.
set -uf
# LC_ALL=C is for this script's own parsing only; git hooks run under the
# caller's locale (C.UTF-8 when it sets none).
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
# A headless worker has no one to answer a credential prompt.
GIT_TERMINAL_PROMPT=0
GH_PROMPT_DISABLED=1
export GIT_TERMINAL_PROMPT GH_PROMPT_DISABLED

me=worker-branch-sync
# Run through a link, the directory of $0 would be the link's, where a planted
# protected-branch.sh would stand in for the real one.
if [ -L "$0" ]; then
  printf '%s: %s\n' "$me" "run the installed script by its own path, not through a symbolic link" >&2
  exit 1
fi
script_dir=$(cd "$(dirname "$0")" && pwd -P) || {
  printf '%s: %s\n' "$me" "the script's own directory could not be entered" >&2
  exit 3
}
NL='
'
TAB=$(printf '\t')

safe() { printf '%s' "$1" | tr -d '\000-\037\177'; }
usage() {
  printf '%s: %s\n' "$me" "$1" >&2
  printf '%s\n' "usage: worker-branch-sync.sh push --force-with-lease=<branch>:<sha> --force-if-includes | reset origin/<branch> | ff <sha>" >&2
  exit 2
}
refuse() {
  printf '%s: %s\n' "$me" "$1" >&2
  exit 1
}
broken() {
  printf '%s: %s\n' "$me" "$1" >&2
  exit 3
}
hook_git() {
  if [ -n "$hook_lc_all" ]; then
    env LC_ALL="$hook_lc_all" git "$@"
  else
    env -u LC_ALL git "$@"
  fi
}
full_sha() {
  case $1 in *[!0-9a-f]*) return 1 ;; esac
  [ "${#1}" = 40 ] || [ "${#1}" = 64 ]
}

# --- arguments ---------------------------------------------------------------

[ "$#" -ge 1 ] || usage "a verb is required"
verb=$1
shift
lease_arg='' includes=0 target=''
case $verb in
  push)
    for a in "$@"; do
      case $a in
        --force-with-lease=*)
          [ -z "$lease_arg" ] || refuse "--force-with-lease is given twice"
          lease_arg=${a#--force-with-lease=}
          ;;
        --force-if-includes)
          [ "$includes" = 0 ] || refuse "--force-if-includes is given twice"
          includes=1
          ;;
        *) refuse "push takes --force-with-lease=<branch>:<sha> and --force-if-includes and nothing else; '$(safe "$a")' is refused (no remote, refspec, + form or other option)" ;;
      esac
    done
    [ -n "$lease_arg" ] || refuse "push needs --force-with-lease=<branch>:<sha>, the full id of the tip the rewrite started from; a force with no lease is refused"
    [ "$includes" = 1 ] || refuse "push needs --force-if-includes beside the lease, always paired"
    case $lease_arg in
      *:*) ;;
      *) refuse "the lease names no SHA; give --force-with-lease=<branch>:<sha>, the full id of the tip the rewrite started from" ;;
    esac
    lease_branch=${lease_arg%%:*}
    lease=${lease_arg#*:}
    full_sha "$lease" || refuse "the lease SHA must be the full commit id the rewrite started from (40 or 64 lowercase hex digits), not '$(safe "$lease")'"
    ;;
  reset | ff)
    [ "$#" = 1 ] || refuse "$verb takes exactly one argument (see the usage)"
    target=$1
    ;;
  -h | --help)
    sed -n '2,/^[^#]/p' "$0" | sed '$d' | sed 's/^# \{0,1\}//'
    exit 0
    ;;
  *) usage "unknown verb '$(safe "$verb")'" ;;
esac

# --- the worktree, the branch and the session record --------------------------

top=$(git rev-parse --show-toplevel 2>/dev/null) || refuse "not inside a git work tree"
top=$(cd "$top" 2>/dev/null && pwd -P) || broken "the work tree's top level could not be entered"
git_dir=$(git rev-parse --absolute-git-dir 2>/dev/null) || broken "the git directory could not be read"
common=$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || broken "the git common directory could not be read"
[ "$git_dir" != "$common" ] \
  || refuse "this is a primary checkout ($(safe "$top")); the helper works only in the worker's own linked worktree"
case $common in
  */.git) primary=${common%/.git} ;;
  *) refuse "the repository has no primary checkout (a bare repository); refusing" ;;
esac

branch=$(git symbolic-ref --quiet --short HEAD 2>/dev/null) || refuse "HEAD is detached; check out the unit branch first"
# policy-guard.sh's is_unit_branch grammar; keep the two in step.
re_task='^planwright/[a-z0-9][a-z0-9-]*/task-[0-9]+(\.[0-9]+)?(-[0-9]+(\.[0-9]+)?)?$'
re_flight='^planwright/flight/[a-z0-9]([a-z0-9-]*[a-z0-9])?$'
case $branch in planwright/flight/task-*) refuse "'$(safe "$branch")' is not a unit branch" ;; esac
printf '%s\n' "$branch" | grep -Eq "$re_task|$re_flight" \
  || refuse "'$(safe "$branch")' is not a unit branch (planwright/<spec>/task-<id> or planwright/flight/<name>); main, spec branches and other branches are never synced here"

rec=${PLANWRIGHT_WORKER_SESSION_RECORD:-}
no_rec="the helper runs only for a dispatched worker whose session record (PLANWRIGHT_WORKER_SESSION_RECORD, written by its launcher)"
[ -n "$rec" ] || refuse "there is no session record: $no_rec names this worktree and branch"
case $rec in /?*) ;; *) refuse "the session record path is not absolute: $no_rec must name this worktree and branch" ;; esac
[ -f "$rec" ] && [ ! -L "$rec" ] && [ -r "$rec" ] \
  && [ -n "$(find "$rec" -prune -user "$(id -u)" -print 2>/dev/null)" ] \
  || refuse "the session record is not this user's own readable regular file (or is a symlink): $no_rec names this worktree and branch"
[ -z "$(find "$rec" -prune \( -perm -020 -o -perm -002 \) -print 2>/dev/null)" ] \
  || refuse "the session record is writable by other users; refusing it"
case $rec in "$top"/*) refuse "the session record's path lies inside the worktree, where the worker could write it; refusing it" ;; esac
rec_dir=$(cd "${rec%/*}/" 2>/dev/null && pwd -P) || refuse "the session record's directory could not be entered"
case "$rec_dir/" in "$top"/*) refuse "the session record's directory resolves inside the worktree, where the worker could write it; refusing it" ;; esac
size=$(wc -c <"$rec" 2>/dev/null | tr -d ' ') || size=''
[ -n "$size" ] && [ "$size" -le 4096 ] 2>/dev/null || refuse "the session record is unreadable or oversized; refusing it"
# field <key> — the value of the one <key>= line, or nothing when there is
# none or more than one.
field() {
  awk -v k="$1=" 'index($0, k) == 1 { n++; v = substr($0, length(k) + 1) } END { if (n == 1) print v }' "$rec"
}
rec_branch=$(field unit_branch)
rec_top=$(field worktree_root)
[ -n "$rec_branch" ] && [ -n "$rec_top" ] \
  || refuse "the session record does not name one unit_branch and one worktree_root; refusing it"
rec_top_p=$(cd "$rec_top" 2>/dev/null && pwd -P) || rec_top_p=$rec_top
[ "$rec_top_p" = "$top" ] \
  || refuse "this session's record names the worktree $(safe "$rec_top"), not $(safe "$top"); the helper works only in the session's own worktree"
[ "$rec_branch" = "$branch" ] \
  || refuse "this session's record names the unit branch $(safe "$rec_branch"), and $(safe "$branch") is checked out; check out your own unit branch"

rc=0
(cd "$primary" && PLANWRIGHT_REPO_ROOT=$primary /bin/sh "$script_dir/protected-branch.sh" "$branch") >/dev/null 2>&1 </dev/null || rc=$?
case $rc in
  0) ;;
  1) refuse "'$(safe "$branch")' is in the protected set; no agent session rewrites or resets it" ;;
  *) refuse "the protected set could not be read (protected-branch.sh exit $rc); refusing (fail closed)" ;;
esac

# --- shared: another worktree, or another session working in this one ---------

wt_list=$(git worktree list --porcelain 2>/dev/null) || refuse "the worktree list could not be read, so whether another worktree holds $(safe "$branch") is unknown; refusing"
holders=$(printf '%s\n' "$wt_list" | WANT="branch refs/heads/$branch" awk '
  index($0, "worktree ") == 1 { p = substr($0, 10) }
  $0 == ENVIRON["WANT"] { print p }')
old_ifs=$IFS
IFS=$NL
for h in $holders; do
  hp=$(cd "$h" 2>/dev/null && pwd -P) || hp=$h
  [ "$hp" = "$top" ] || {
    IFS=$old_ifs
    refuse "another worktree ($(safe "$h")) holds $(safe "$branch") too, so the branch is shared; refusing"
  }
done
IFS=$old_ifs

# cwd_of <pid> — the process's working directory, or a failure.
cwd_of() {
  if [ -d /proc/self ]; then
    readlink "/proc/$1/cwd" 2>/dev/null
  else
    lsof -a -p "$1" -d cwd -Fn 2>/dev/null </dev/null | sed -n 's/^n//p'
  fi
}
# ppid_of <pid> — the parent's id, or nothing.
ppid_of() {
  if [ -r "/proc/$1/stat" ]; then
    sed 's/.*) //' "/proc/$1/stat" 2>/dev/null | cut -d' ' -f2
  else
    ps -o ppid= -p "$1" 2>/dev/null | tr -d ' '
  fi
}
in_top() {
  case "$1/" in "$top"/*) return 0 ;; esac
  return 1
}
# dir_users — every process id working in the worktree, or a failure when
# this host's process table cannot be read.
dir_users() {
  cd / || return 1
  if [ -L /proc/self/cwd ]; then
    readlink "/proc/$$/cwd" >/dev/null 2>&1 || return 1
    du_glob=$(printf '%s' "$top" | sed 's/[][*?\\]/\\&/g')
    du_out=$(find /proc -mindepth 2 -maxdepth 2 -name cwd \( -lname "$du_glob" -o -lname "$du_glob/*" \) 2>/dev/null)
    case $du_out in
      */proc/$$/cwd*) ;;
      *)
        # busybox find has no -lname: read each process's directory instead.
        du_out=''
        set +f
        for du_c in /proc/[0-9]*/cwd; do
          du_t=$(readlink "$du_c" 2>/dev/null) || continue
          in_top "$du_t" && du_out="$du_out$NL$du_c"
        done
        set -f
        ;;
    esac
    printf '%s\n' "$du_out" | awk -F / '$3 ~ /^[0-9]+$/ { print $3 }'
    return 0
  fi
  command -v lsof >/dev/null 2>&1 || return 1
  du_out=$(lsof -a -d cwd -F pn 2>/dev/null </dev/null)
  [ -n "$du_out" ] || return 1
  printf '%s\n' "$du_out" | D="$top/" awk '
    /^p/ { pid = substr($0, 2) }
    /^n/ { c = substr($0, 2) "/"; if (index(c, ENVIRON["D"]) == 1) print pid }'
}

# This run's own ancestry is its parent chain for as long as each process works
# in the worktree (a session's runner and its claude both do), with their
# descendants; any other process there is another session.
own=" $$ "
p=$(ppid_of $$)
n=0
while [ -n "$p" ] && [ "$p" -gt 1 ] 2>/dev/null && [ "$n" -lt 64 ]; do
  c=$(cwd_of "$p") || break
  in_top "$c" || break
  own="$own$p "
  p=$(ppid_of "$p")
  n=$((n + 1))
done
users=$(dir_users) || users=''
# This script works in the worktree itself, so a scan that misses it read
# nothing (a find or lsof that failed or lacks a flag).
case " $(printf '%s' "$users" | tr '\n' ' ') " in
  *" $$ "*) ;;
  *) refuse "this host's process table cannot be read, so whether another session works in $(safe "$top") is unknown; refusing" ;;
esac
for u in $users; do
  case $own in *" $u "*) continue ;; esac
  q=$u
  n=0
  mine=0
  while [ -n "$q" ] && [ "$q" -gt 1 ] 2>/dev/null && [ "$n" -lt 64 ]; do
    case $own in *" $q "*)
      mine=1
      break
      ;;
    esac
    q=$(ppid_of "$q")
    n=$((n + 1))
  done
  [ "$mine" = 0 ] || continue
  # Skipped only when gone since the scan, or the tmux server that hosts panes
  # (not a session); a process ps cannot name still counts.
  if ! comm=$(ps -o comm= -p "$u" 2>/dev/null); then
    kill -0 "$u" 2>/dev/null || [ -d "/proc/$u" ] || continue
    comm=unknown
  fi
  case ${comm##*/} in tmux*) continue ;; esac
  refuse "process $u ($(safe "${comm##*/}")) works in $(safe "$top") and is no part of this session, so another session may be on $(safe "$branch"); refusing as shared"
done

# --- the acts ------------------------------------------------------------------

clean_or_refuse() {
  st=$(git status --porcelain=v1 --untracked-files=all 2>/dev/null) || broken "git status failed"
  [ -z "$st" ] || refuse "the worktree is not clean (staged, changed or untracked files); commit or remove them first"
  for f in MERGE_HEAD CHERRY_PICK_HEAD REVERT_HEAD BISECT_LOG rebase-merge rebase-apply; do
    fp=$(git rev-parse --git-path "$f" 2>/dev/null) || broken "the git directory could not be read"
    [ ! -e "$fp" ] || refuse "a merge, rebase, cherry-pick, revert or bisect is in progress ($f); finish or abort it first"
  done
}

head=$(git rev-parse --verify --quiet 'HEAD^{commit}') || broken "HEAD does not resolve"

case $verb in
  push)
    [ "$lease_branch" = "$branch" ] \
      || refuse "the lease names $(safe "$lease_branch"), and $(safe "$branch") is checked out; the helper pushes only the checked-out unit branch, so name it exactly"
    git cat-file -e "$lease^{commit}" 2>/dev/null \
      || refuse "the lease $lease is not a commit in this repository; give the tip the rewrite started from"
    [ "$lease" != "$head" ] || refuse "the lease is HEAD itself, so there is nothing to rewrite; a plain push suffices"
    if git merge-base --is-ancestor "$lease" "$head" 2>/dev/null; then
      refuse "HEAD contains the lease, so this is a fast-forward and a plain push suffices"
    fi
    git reflog show --format=%H "refs/heads/$branch" -- 2>/dev/null | grep -qxF "$lease" \
      || refuse "the lease $lease is a tip $(safe "$branch") never held (its reflog does not record it), so it was read from elsewhere, such as the remote-tracking ref at push time; lease on the tip the rewrite started from"
    git remote get-url origin >/dev/null 2>&1 || refuse "there is no remote named origin"
    command -v jq >/dev/null 2>&1 || broken "jq is required to read the pull request"
    prs=$(gh pr list --head "$branch" --state open --json number,isDraft,headRefName,isCrossRepository 2>&1 </dev/null) \
      || broken "gh could not list the open pull requests for $(safe "$branch") ($(safe "$prs" | cut -c1-200)), so whether its PR is a draft is unknown; nothing was pushed"
    drafts=$(printf '%s' "$prs" | jq -r --arg b "$branch" \
      '[.[] | select(.headRefName == $b and .isCrossRepository == false)] | if length == 1 then (.[0].isDraft | tostring) else "count:\(length)" end' 2>/dev/null) \
      || broken "gh's answer for $(safe "$branch") could not be read; nothing was pushed"
    case $drafts in
      true) ;;
      false) refuse "the pull request for $(safe "$branch") is ready for review, not a draft; a rewrite publishes only while the PR is a draft. Add new commits instead" ;;
      count:0) refuse "$(safe "$branch") heads no open pull request from this repository; a rewrite publishes only while its PR is a draft, so open the draft PR first" ;;
      count:*) refuse "$(safe "$branch") heads more than one open pull request; refusing" ;;
      *) broken "gh reported no draft state for the pull request of $(safe "$branch"); nothing was pushed" ;;
    esac
    out=$(hook_git push --porcelain --force-with-lease="refs/heads/$branch:$lease" --force-if-includes \
      origin "refs/heads/$branch:refs/heads/$branch" 2>&1 </dev/null)
    prc=$?
    if [ "$prc" != 0 ]; then
      printf '%s\n' "$out" | tr -d '\000-\010\013-\037\177' >&2
      # Read only git's own porcelain status line for the ref, never hook text.
      if printf '%s\n' "$out" | grep -q "^!${TAB}refs/heads/$branch:refs/heads/$branch${TAB}\\[rejected\\]"; then
        now=$(git ls-remote origin "refs/heads/$branch" 2>/dev/null </dev/null | awk -v r="refs/heads/$branch" '$2 == r { print $1; exit }')
        if [ "$now" = "$head" ]; then
          # An earlier run of this same push landed; only its report was lost.
          printf 'pushed\t%s\t%s\t%s\n' "$(safe "$branch")" "$lease" "$head"
          exit 0
        fi
        refuse "origin/$(safe "$branch") moved past the lease $lease, so someone else pushed to it: treat the branch as shared from now on and never retry with another lease"
      fi
      broken "git push failed (exit $prc)"
    fi
    printf 'pushed\t%s\t%s\t%s\n' "$(safe "$branch")" "$lease" "$head"
    ;;
  reset)
    [ "$target" = "origin/$branch" ] \
      || refuse "reset takes origin/$(safe "$branch"), this branch's own remote-tracking ref, and nothing else; '$(safe "$target")' is refused"
    to=$(git rev-parse --verify --quiet "refs/remotes/origin/$branch^{commit}") \
      || refuse "origin/$(safe "$branch") does not resolve; fetch it first (git fetch origin $(safe "$branch"))"
    clean_or_refuse
    drops=$(git log --no-show-signature --format="%H$TAB%s" "$to..$head" -- 2>/dev/null) \
      || broken "the commits the reset would drop could not be listed; nothing was reset"
    hook_git reset --hard --quiet "$to" </dev/null || broken "git reset failed"
    printf 'reset\t%s\t%s\t%s\n' "$(safe "$branch")" "$head" "$to"
    printf '%s\n' "$drops" | while IFS="$TAB" read -r sha subj; do
      [ -z "$sha" ] || printf 'dropped\t%s\t%s\n' "$sha" "$(safe "$subj")"
    done
    ;;
  ff)
    full_sha "$target" || refuse "ff takes the full id (40 or 64 lowercase hex digits) of a commit descending from HEAD, not '$(safe "$target")'"
    git cat-file -e "$target^{commit}" 2>/dev/null || refuse "$target is not a commit in this repository; fetch it first"
    [ "$target" != "$head" ] || refuse "$target is HEAD already; nothing to fast-forward"
    git merge-base --is-ancestor "$head" "$target" 2>/dev/null \
      || refuse "$target is not a descendant of HEAD, so this is no fast-forward; refusing"
    clean_or_refuse
    hook_git merge --ff-only --quiet "$target" </dev/null || broken "git merge --ff-only failed"
    printf 'fast-forwarded\t%s\t%s\t%s\n' "$(safe "$branch")" "$head" "$target"
    ;;
esac
