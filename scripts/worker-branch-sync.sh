#!/bin/sh
# worker-branch-sync.sh - the acts on a dispatched worker's own unit branch
# that the worker profile's deny floor keeps from raw git.
#
# Usage (from the worker's own worktree, by the installed script's path):
#   worker-branch-sync.sh push --force-with-lease=<branch>:<sha> --force-if-includes
#   worker-branch-sync.sh reset <origin/branch>
#   worker-branch-sync.sh ff <sha>
#
# push publishes a rewrite while the branch's one same-repository PR is a
# draft, leased on the tip the rewrite started from (<sha>, which the branch's
# reflog records), only where the launch record names mission control and
# draft_rewrite=allow (doctrine/human-gates.md, the draft-branch rewrite row);
# it prints what it replaced and appends an audit line, and each refusal names
# its reason. reset refreshes origin/<branch>, then resets hard to it, naming
# each local commit it drops (which needs unpushed_rewrite); ff fast-forwards
# to a full commit id descending from HEAD.
#
# Every verb refuses unless it runs in a clean linked worktree whose launch
# record, at the worktree's own path (worker-session-record.sh path, never
# one the environment names), names it and the unit branch checked out
# there, outside the protected set, with no other worktree or session on it.
# Exit: 0 done; 1 refused; 2 usage; 3 a git failure.
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
  GIT_CONFIG GIT_CONFIG_PARAMETERS GIT_CONFIG_COUNT GIT_NAMESPACE GIT_PREFIX \
  PLANWRIGHT_WORKER_SESSION_RECORD
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
LEGACY_SUFFIX=' [pending-sign-off]'

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
target=''
lease_branch=''
lease=''
case $verb in
  push)
    [ "$#" = 2 ] \
      || refuse "push takes exactly --force-with-lease=<branch>:<sha> --force-if-includes, and no remote, refspec, + form, or other option"
    case $1 in
      --force-with-lease=?*:?*) ;;
      *) refuse "push takes --force-with-lease=<branch>:<sha> first, naming the branch and the full id of the tip the rewrite started from; '$(safe "$1")' is refused" ;;
    esac
    [ "$2" = --force-if-includes ] \
      || refuse "push takes --force-if-includes beside the lease, and nothing else; '$(safe "$2")' is refused"
    lease=${1##*:}
    lease_branch=${1#--force-with-lease=}
    lease_branch=${lease_branch%:*}
    full_sha "$lease" \
      || refuse "the lease names '$(safe "$lease")', which is not a full commit id (40 or 64 lowercase hex digits); lease on the full id of the tip the rewrite started from"
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

# Every override that could point the push's reads at another repository or
# another policy is refused rather than honored.
if [ "$verb" = push ]; then
  for v in GH_REPO GH_HOST PLANWRIGHT_CONFIG_DEFAULTS PLANWRIGHT_LOCAL_CONFIG PLANWRIGHT_REPO_ROOT PLANWRIGHT_CONFIG_STRICT_OVERLAYS; do
    eval "isset=\${$v+set}"
    [ -z "$isset" ] || refuse "$v is set in the environment, which could point this push's reads at another repository or policy; run it with no such override"
  done
fi

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

no_rec="the helper runs only for a dispatched worker whose launch wrote the worktree's own session record"
rec=$(/bin/sh "$script_dir/worker-session-record.sh" path "$top" 2>/dev/null </dev/null) \
  || refuse "the worktree's session record could not be located: $no_rec"
case $rec in /?*) ;; *) refuse "the worktree's session record path is not absolute: $no_rec" ;; esac
[ -e "$rec" ] || [ -L "$rec" ] || refuse "there is no session record at $(safe "$rec"): $no_rec"
[ -f "$rec" ] && [ ! -L "$rec" ] && [ -r "$rec" ] \
  && [ -n "$(find "$rec" -prune -user "$(id -u)" -print 2>/dev/null)" ] \
  || refuse "the session record is not this user's own readable regular file (or is a symlink): $no_rec"
[ -z "$(find "$rec" -prune \( -perm -020 -o -perm -002 \) -print 2>/dev/null)" ] \
  || refuse "the session record is writable by other users; refusing it"
rec_dir=$(cd "${rec%/*}/" 2>/dev/null && pwd -P) || refuse "the session record's directory could not be entered"
case "$rec_dir/" in "$top"/*) refuse "the session record's directory resolves inside the worktree, where the worker could write it; refusing it" ;; esac
size=$(wc -c <"$rec" 2>/dev/null | tr -d ' ') || size=''
[ -n "$size" ] && [ "$size" -le 4096 ] 2>/dev/null || refuse "the session record is unreadable or oversized; refusing it"
# Every line is key=value with a lowercase key, and no key appears twice.
awk '
  !/^[a-z_]+=/ { bad = 1 }
  { k = $0; sub(/=.*/, "", k); if (seen[k]++) bad = 1 }
  END { exit bad }' "$rec" 2>/dev/null \
  || refuse "the session record is unreadable or malformed (a line that is not key=value, or a key given twice); refusing it"
# field <key> — the value of the one <key>= line, or nothing when there is none.
field() {
  awk -v k="$1=" 'index($0, k) == 1 { print substr($0, length(k) + 1); exit }' "$rec"
}
rec_branch=$(field unit_branch)
rec_top=$(field worktree_root)
[ -n "$rec_branch" ] && [ -n "$rec_top" ] \
  || refuse "the session record does not name one unit_branch and one worktree_root; refusing it"
rec_top_p=$(cd "$rec_top" 2>/dev/null && pwd -P) || rec_top_p=$rec_top
[ "$rec_top_p" = "$top" ] \
  || refuse "this worktree's record names the worktree $(safe "$rec_top"), not $(safe "$top"); the helper works only in the session's own worktree"
[ "$rec_branch" = "$branch" ] \
  || refuse "this worktree's record names the unit branch $(safe "$rec_branch"), and $(safe "$branch") is checked out; check out your own unit branch"

# The push re-reads its authority here, as its own last line (REQ-G1.14).
if [ "$verb" = push ]; then
  [ "$(field launcher)" = mission-control ] \
    || refuse "the session record does not name mission control as this worker's launcher, so no draft-branch rewrite is published; add new commits instead"
  [ "$(field draft_rewrite)" = allow ] \
    || refuse "draft_rewrite is not allow in this session's launch record, so the rewrite of $(safe "$branch") is not published; add new commits instead"
fi

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

# legacy_lines <range> — `<sha>TAB<author ident and date>` per legacy checklist
# commit (a subject ending in the legacy suffix, with no sign-off trailer).
legacy_lines() {
  git log --no-show-signature --format="%H$TAB%s" "$1" -- 2>/dev/null | while IFS="$TAB" read -r ll_sha ll_subj; do
    case $ll_subj in
      *"$LEGACY_SUFFIX") ;;
      *) continue ;;
    esac
    [ -z "$(git log --no-show-signature -1 --format='%(trailers:key=Planwright-Sign-Off,valueonly)' "$ll_sha" | tr -d '[:space:]')" ] || continue
    printf '%s\t%s\n' "$ll_sha" "$(git log --no-show-signature -1 --format='%an <%ae> %ad' --date=raw "$ll_sha")"
  done
}

# legacy_changes <old tip> <new tip> — `PS-legacy-<old>TAB<PS-legacy-new or ->`
# per legacy commit the rewrite drops, paired with its replacement by author
# identity and date, in commit order, as scripts/tower-force-push.sh pairs them.
legacy_changes() {
  lc_old=$(legacy_lines "$2..$1")
  [ -n "$lc_old" ] || return 0
  lc_new=$(legacy_lines "$1..$2")
  FP_OLD=$lc_old FP_NEW=$lc_new awk '
    function id_of(line) { return substr(line, index(line, "\t") + 1) }
    BEGIN {
      n = split(ENVIRON["FP_NEW"], nl, "\n")
      for (i = 1; i <= n; i++) {
        if (nl[i] == "") continue
        id = id_of(nl[i])
        q[id, ++have[id]] = substr(nl[i], 1, 7)
      }
      m = split(ENVIRON["FP_OLD"], ol, "\n")
      for (i = 1; i <= m; i++) {
        if (ol[i] == "") continue
        id = id_of(ol[i])
        k = ++used[id]
        printf "PS-legacy-%s\t%s\n", substr(ol[i], 1, 7), (k <= have[id] ? "PS-legacy-" q[id, k] : "-")
      }
    }'
}

# repo_of_url <url> — `<host>/<owner>/<name>` for a GitHub-shaped remote URL.
repo_of_url() {
  ru=$1
  case $ru in
    https://*) ru=${ru#https://} ;;
    ssh://*)
      ru=${ru#ssh://}
      ru=${ru#*@}
      ;;
    *@*:*)
      ru=${ru#*@}
      ru=$(printf '%s' "$ru" | sed 's/:/\//')
      ;;
    *) return 1 ;;
  esac
  ru=${ru%/}
  ru=${ru%.git}
  printf '%s\n' "$ru" | grep -Eq '^[A-Za-z0-9.-]+(:[0-9]+)?/[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$' || return 1
  printf '%s\n' "$ru" | sed 's/:[0-9]*\//\//'
}

head=$(git rev-parse --verify --quiet 'HEAD^{commit}') || broken "HEAD does not resolve"

case $verb in
  push)
    [ "$lease_branch" = "$branch" ] \
      || refuse "the lease names $(safe "$lease_branch"), and $(safe "$branch") is checked out; the helper pushes only the checked-out unit branch, so name it exactly"
    clean_or_refuse
    git cat-file -e "$lease^{commit}" 2>/dev/null \
      || refuse "the lease $lease is not a commit in this repository; lease on the tip the rewrite started from"
    [ "$lease" != "$head" ] || refuse "the lease is HEAD itself, so there is nothing to rewrite; a plain push suffices"
    if git merge-base --is-ancestor "$lease" "$head" 2>/dev/null; then
      refuse "HEAD contains the lease, so this is a fast-forward and a plain push suffices"
    fi
    git reflog exists "refs/heads/$branch" 2>/dev/null \
      || refuse "$(safe "$branch") has no reflog, so the lease cannot be proven to be a tip it held; refusing"
    git reflog show --format=%H "refs/heads/$branch" -- 2>/dev/null | grep -qxF "$lease" \
      || refuse "the lease $lease is a tip $(safe "$branch") never held (its reflog does not record it), so it was read from elsewhere, such as the remote-tracking ref at push time; lease on the tip the rewrite started from"

    pr_base=$(field pr_base)
    remote=${pr_base%%/*}
    base_branch=${pr_base#*/}
    [ -n "$pr_base" ] && [ "$base_branch" != "$pr_base" ] && [ -n "$remote" ] && [ -n "$base_branch" ] \
      || refuse "the session record names no PR base (<remote>/<branch>), so the commits this push replaces cannot be bounded; refusing"
    case $remote in [A-Za-z0-9]*) ;; *) refuse "the record's PR base names an unreadable remote; refusing" ;; esac
    case $remote in *[!A-Za-z0-9._-]*) refuse "the record's PR base names an unreadable remote; refusing" ;; esac
    base_ref="refs/remotes/$remote/$base_branch"
    git rev-parse --verify --quiet "$base_ref^{commit}" >/dev/null \
      || refuse "the PR base $(safe "$pr_base") does not resolve here; fetch it first (git fetch $(safe "$remote") $(safe "$base_branch"))"

    me_name=$(git config --get user.name 2>/dev/null) || me_name=''
    me_mail=$(git config --get user.email 2>/dev/null) || me_mail=''
    [ -n "$me_name" ] && [ -n "$me_mail" ] \
      || refuse "this repository has no configured author identity (user.name and user.email), so whose commits the push replaces cannot be told; refusing"
    # The replaced commits: on the lease, and on neither the PR base nor the
    # new head (a commit the rewrite keeps as it is replaces nothing).
    authors=$(git log --no-show-signature --format="%H$TAB%an$TAB%ae" "$lease" "^$base_ref" "^$head" -- 2>/dev/null) \
      || broken "the commits the push replaces could not be listed; nothing was pushed"
    old_ifs=$IFS
    IFS=$NL
    for line in $authors; do
      a_sha=${line%%"$TAB"*}
      rest=${line#*"$TAB"}
      a_name=${rest%%"$TAB"*}
      a_mail=${rest#*"$TAB"}
      if [ "$a_name" != "$me_name" ] || [ "$a_mail" != "$me_mail" ]; then
        IFS=$old_ifs
        refuse "commit $a_sha, which this push would replace, is by $(safe "$a_name") <$(safe "$a_mail")>, not this repository's configured author; a rewrite never replaces someone else's commit. Add new commits instead"
      fi
    done
    IFS=$old_ifs

    url=$(git config --get "remote.$remote.pushurl" 2>/dev/null) || url=$(git config --get "remote.$remote.url" 2>/dev/null) || url=''
    [ -n "$url" ] || refuse "the remote $(safe "$remote") has no URL; refusing"
    repo=$(repo_of_url "$url") || refuse "the push remote's URL ($(safe "$url")) names no repository gh can read; refusing"

    # The audit log the session's command guard writes to, checked before the
    # push so a published rewrite always leaves its line.
    audit_home=$(field audit_log_home)
    case $audit_home in /?*) ;; *) refuse "the session record names no audit-log home, so the push would leave no audit line; refusing" ;; esac
    [ -d "$audit_home" ] && [ ! -L "$audit_home" ] && [ -w "$audit_home" ] \
      && [ -n "$(find "$audit_home" -prune -user "$(id -u)" -print 2>/dev/null)" ] \
      || refuse "the session's audit-log home is not this user's own writable directory, so the push would leave no audit line; refusing"
    case "$(cd "$audit_home" 2>/dev/null && pwd -P)/" in "$top"/*) refuse "the audit-log home lies inside the worktree; refusing" ;; esac
    audit_key=${rec##*/}
    audit_key=${audit_key%.record}
    audit_log=$audit_home/$audit_key.log
    if [ -e "$audit_log" ] || [ -L "$audit_log" ]; then
      [ -f "$audit_log" ] && [ ! -L "$audit_log" ] && [ -n "$(find "$audit_log" -prune -user "$(id -u)" -print 2>/dev/null)" ] \
        || refuse "the session's audit log is not this user's own regular file; refusing"
    fi

    command -v gh >/dev/null 2>&1 || refuse "gh is required to read the pull request; nothing was pushed"
    command -v jq >/dev/null 2>&1 || refuse "jq is required to read the pull request; nothing was pushed"
    heads=$(gh pr list --repo "$repo" --head "$branch" --state open --json number,isDraft,headRefName,isCrossRepository 2>/dev/null </dev/null) \
      || refuse "gh could not list the open pull requests of $(safe "$repo") for $(safe "$branch"), so whether its PR is a draft is unknown; nothing was pushed"
    state=$(printf '%s' "$heads" | jq -r --arg b "$branch" '
      if type != "array" then "unreadable" else
      [.[] | select(.headRefName == $b)] |
      if length == 0 then "none"
      elif length > 1 then "several"
      elif .[0].isCrossRepository != false then "cross"
      elif .[0].isDraft == true then "draft"
      elif .[0].isDraft == false then "ready"
      else "unreadable" end end' 2>/dev/null) || state=unreadable
    case $state in
      draft) ;;
      ready) refuse "the pull request for $(safe "$branch") is ready for review, not a draft; a rewrite publishes only while the PR is a draft. Add new commits instead" ;;
      none) refuse "$(safe "$branch") heads no open pull request in $(safe "$repo"); a rewrite publishes only while its PR is a draft" ;;
      several) refuse "$(safe "$branch") heads more than one open pull request; refusing" ;;
      cross) refuse "the open pull request for $(safe "$branch") comes from another repository; refusing" ;;
      *) refuse "gh's answer for $(safe "$branch") could not be read; nothing was pushed" ;;
    esac
    bases=$(gh pr list --repo "$repo" --base "$branch" --state open --json number 2>/dev/null </dev/null) \
      || refuse "gh could not list the open pull requests based on $(safe "$branch"), so whether another PR stacks on it is unknown; nothing was pushed"
    nb=$(printf '%s' "$bases" | jq -r 'if type == "array" then length else "x" end' 2>/dev/null) || nb=x
    case $nb in
      0) ;;
      '' | *[!0-9]*) refuse "gh's answer for the pull requests based on $(safe "$branch") could not be read; nothing was pushed" ;;
      *) refuse "an open pull request takes $(safe "$branch") as its base, so rewriting it would rewrite that PR's base; refusing" ;;
    esac

    out=$(hook_git push --porcelain --force-with-lease="refs/heads/$branch:$lease" --force-if-includes \
      "$remote" "refs/heads/$branch:refs/heads/$branch" 2>&1 </dev/null)
    prc=$?
    if [ "$prc" != 0 ]; then
      printf '%s\n' "$out" | tr -d '\000-\010\013-\037\177' >&2
      # Read only git's own porcelain status line for the ref, never hook text.
      if printf '%s\n' "$out" | grep -q "^!${TAB}refs/heads/$branch:refs/heads/$branch${TAB}\\[rejected\\]"; then
        refuse "$(safe "$remote")/$(safe "$branch") moved past the lease $lease, so someone else pushed to it: treat the branch as shared from now on, and never retry with another lease or a broader force"
      fi
      broken "git push failed (exit $prc)"
    fi
    printf 'pushed\t%s\t%s\t%s\n' "$(safe "$branch")" "$lease" "$head"
    git log --no-show-signature --format="%H$TAB%s" "$head..$lease" -- 2>/dev/null | while IFS="$TAB" read -r sha subj; do
      [ -z "$sha" ] || printf 'replaced\t%s\t%s\n' "$sha" "$(safe "$subj")"
    done
    legacy=$(legacy_changes "$lease" "$head")
    if [ -n "$legacy" ]; then
      printf '%s\n' "$legacy" | while IFS="$TAB" read -r from to; do
        printf 'legacy\t%s\t%s\n' "$from" "$to"
      done
      printf 'note\t%s\n' "re-stamp any Planwright-Sign-Off-Rejected trailer naming an old legacy id with its new id, in a new commit"
    fi
    now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    printf '%s\tdraft-rewrite-push\t%s\t%s\t%s\n' "$now" "$(safe "$branch")" "$lease" "$head" >>"$audit_log" \
      || broken "the push landed, but its audit line could not be written to $(safe "$audit_log")"
    ;;
  reset)
    [ "$target" = "origin/$branch" ] \
      || refuse "reset takes origin/$(safe "$branch"), this branch's own remote-tracking ref, and nothing else; '$(safe "$target")' is refused"
    # Refreshed first, so the commits it drops are the ones no remote holds.
    git fetch --quiet --no-tags origin "+refs/heads/$branch:refs/remotes/origin/$branch" </dev/null \
      || refuse "origin/$(safe "$branch") could not be refreshed, so which local commits the reset would drop is unknown; refusing (fail closed)"
    to=$(git rev-parse --verify --quiet "refs/remotes/origin/$branch^{commit}") \
      || refuse "origin/$(safe "$branch") does not resolve; fetch it first (git fetch origin $(safe "$branch"))"
    clean_or_refuse
    drops=$(git log --no-show-signature --format="%H$TAB%s" "$to..$head" -- 2>/dev/null) \
      || broken "the commits the reset would drop could not be listed; nothing was reset"
    if [ -n "$drops" ]; then
      # Dropping a local commit reshapes never-pushed history, which the
      # policy allows only under unpushed_rewrite, read at the primary checkout.
      rk=$(cd "$primary" && PLANWRIGHT_REPO_ROOT=$primary /bin/sh "$script_dir/resolve-policy-knob.sh" unpushed_rewrite 2>/dev/null </dev/null) \
        || refuse "unpushed_rewrite could not be read, and this reset would drop local commits; refusing (fail closed)"
      [ "$rk" = allow ] \
        || refuse "unpushed_rewrite is $(safe "$rk"), and this reset would drop local commits; leave them, or ask the operator"
    fi
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
