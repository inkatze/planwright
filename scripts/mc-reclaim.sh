#!/usr/bin/env bash
# mc-reclaim.sh — the worktree reclaim predicate, and the reclaim that backs
# a worktree's ignored audit files up into the program home before it goes.
#
# `mc-reclaim.sh --help` prints the contract: verbs, arms, outputs, exit codes.
set -u
set -f
LC_ALL=C
export LC_ALL
unset CDPATH

prog=mc-reclaim
script_dir=$(cd "$(dirname "$0")" && pwd) || exit 2
for lib in echo-safety.sh mc-lib.sh lock-lib.sh; do
  if [ ! -r "$script_dir/$lib" ]; then
    printf '%s\n' "$prog: $lib is missing or unreadable (broken install)" >&2
    exit 2
  fi
done
# shellcheck source=scripts/echo-safety.sh
. "$script_dir/echo-safety.sh" || exit 2
# shellcheck source=scripts/mc-lib.sh
. "$script_dir/mc-lib.sh" || exit 2
# shellcheck source=scripts/lock-lib.sh
. "$script_dir/lock-lib.sh" || exit 2

GH_BOUND=20
NL='
'

help_text() {
  cat <<'HELP'
mc-reclaim.sh — the worktree reclaim predicate, and the reclaim that backs a
worktree's ignored audit files up into the program home before it goes.

Usage:
  mc-reclaim.sh check --program <p> <worktree>
      evaluate the predicate; act on nothing.
  mc-reclaim.sh reclaim --program <p> <worktree>
      evaluate it, back the audit files up, verify the copies, then remove
      the worktree through scripts/fleet-cleanup.sh.

<worktree> is the absolute path of a linked worktree of one of the program's
repositories, proved from that repository's own git directory, never from
the worktree's .git file alone. This script's git calls name that git
directory, and every git call, the removal's included, runs with
core.fsmonitor and hooks off. The predicate's arms, each refusing on its
own:
  live-user      a process of this user has its working directory in the
                 worktree, or none of the process table's working
                 directories can be read (another user's processes are not
                 visible without privilege)
  uncommitted    git status lists a change or an untracked file, or the
                 worktree holds a submodule
  no-pr, pr-open the forge has no PR from this repository for the branch,
                 or one is still open; a merged or closed one passes
  unpushed       the branch is neither at parity with its upstream nor the
                 head of a PR merged at exactly the worktree's HEAD, the
                 evidence fleet-cleanup.sh's removal itself requires
and the shape checks: not-a-worktree, not-program-repo, main-checkout,
detached, bad-branch, pr-unreadable. A reclaim adds:
  backup         a copy failed, differs from its source, would replace a
                 different file already in the reclaim folder, a folder on
                 its way is a symbolic link, another reclaim of the folder
                 holds its lock, or a file name holds a newline
  interrupted    a signal stopped the backup
  removal        a process entered the worktree since the predicate ran, or
                 fleet-cleanup.sh refused the removal (its exit and last
                 line follow)

The backup copies every git-ignored file the mission_control_reclaim_files
knob matches (worktree-relative paths, `*` in the last component, a
directory taken whole, a symbolic link never followed) into
<program home>/reclaimed/<repository>/<branch>/, at the same relative path,
and compares each copy's size and SHA-256 with its source. A refusal before
the removal starts takes back every copy and folder it made; once the
removal starts the copies stay, whatever its outcome, since a removal that
fails partway may already have deleted their sources, and signals are held
off until it ends.

Output, tab separated:
  check <worktree> ok <merged|closed> #<n>
  reclaim <worktree> reclaimed <folder> <n> files
  <verb> <worktree> refused <arm> <detail>

Exit codes: 0 passed or reclaimed; 1 refused (a refused line on stdout),
or, with only a message on stderr, the program's home, repositories or the
file-set knob do not resolve; 2 usage, or a path that is not absolute;
3 the program is not configured.
HELP
}

usage() {
  mc_usage_fail "usage: mc-reclaim.sh check|reclaim --program <p> <worktree>"
}

# CREATED lists the copies this run made, MADE the directories it made
# (deepest last); a refusal before the removal takes both back.
CREATED=''
MADE=''
DEST_LOCK=''
rollback() {
  while IFS= read -r rb_f; do
    [ -z "$rb_f" ] || rm -f "$rb_f"
  done <<EOF
$CREATED
EOF
  printf '%s' "$MADE" | awk 'NF { l[++n] = $0 } END { for (i = n; i > 0; i--) print l[i] }' | while IFS= read -r rb_d; do
    rmdir "$rb_d" 2>/dev/null || :
  done
  CREATED='' MADE=''
}

# make_dir <base> <rel>: create <base>/<rel> owner-only, refusing when any
# part of it below <base> is a symbolic link, and note what it made.
make_dir() {
  md_p=$1
  md_rest=$2
  while [ -n "$md_rest" ]; do
    md_part=${md_rest%%/*}
    if [ "$md_part" = "$md_rest" ]; then
      md_rest=''
    else
      md_rest=${md_rest#*/}
    fi
    [ -n "$md_part" ] || continue
    md_p="$md_p/$md_part"
    [ ! -L "$md_p" ] || refuse backup "${md_p#"$HOME_DIR"/} is a symbolic link"
    if [ ! -e "$md_p" ]; then
      (umask 077 && mkdir "$md_p") 2>/dev/null || refuse backup "cannot create ${md_p#"$HOME_DIR"/}"
      MADE="$MADE$md_p$NL"
    fi
    [ -d "$md_p" ] || refuse backup "${md_p#"$HOME_DIR"/} is not a directory"
  done
}
refuse() { # refuse <arm> <detail>
  rollback
  [ -z "$DEST_LOCK" ] || pw_lock_release "$DEST_LOCK" || :
  printf '%s\t%s\t%s\t%s\t%s\n' "$VERB" "$(sanitize_printable "$WT")" refused "$1" "$(sanitize_printable "$2")"
  exit 1
}

# g <args...>: git against the proved worktree, with the repository's git
# directory named and the worktree-steerable exec hooks off.
g() {
  git --git-dir="$GITDIR" --work-tree="$WT" -c core.fsmonitor=false -c core.hooksPath=/dev/null "$@"
}

# parse_paths <raw>: an inline list of worktree-relative paths, one per
# line; fails on an absolute path, a `..` component, a `*` outside the last
# component, or a control byte.
parse_paths() {
  RAW=$1 awk 'BEGIN {
    r = ENVIRON["RAW"]
    if (r ~ /[[:cntrl:]]/) exit 1
    sub(/^[ ]+/, "", r); sub(/[ ]+$/, "", r)
    if (r !~ /^\[.*\]$/) exit 1
    r = substr(r, 2, length(r) - 2)
    if (r ~ /^[ ]*$/) exit 0
    n = split(r, a, ",")
    for (i = 1; i <= n; i++) {
      p = a[i]; sub(/^[ ]+/, "", p); sub(/[ ]+$/, "", p)
      if (p ~ /^".*"$/ || p ~ /^\047.*\047$/) p = substr(p, 2, length(p) - 2)
      if (p == "" || p ~ /^\// || p ~ /(^|\/)\.\.?(\/|$)/ || p ~ /[][?{}\\\047"]/) exit 1
      d = p; sub(/[^\/]*$/, "", d)
      if (d ~ /\*/) exit 1
      print p
    }
  }'
}

# live_users <dir>: print the pid of every process of this user whose
# working directory is <dir> or below it; fails when no working directory
# can be read at all.
live_users() {
  if [ -L /proc/self/cwd ]; then
    # One find over procfs: a readlink per process costs seconds on a busy
    # host. The path is escaped so -lname matches it literally.
    lu_glob=$(printf '%s' "$1" | sed 's/[][*?\\]/\\&/g')
    find /proc -mindepth 2 -maxdepth 2 -name cwd \( -lname "$lu_glob" -o -lname "$lu_glob/*" \) 2>/dev/null \
      | awk -F / '$3 ~ /^[0-9]+$/ { print $3 }'
    return 0
  fi
  command -v lsof >/dev/null 2>&1 || return 1
  lu_out=$(lsof -a -d cwd -F pn 2>/dev/null)
  [ -n "$lu_out" ] || return 1
  printf '%s\n' "$lu_out" | D="$1/" awk '
    /^p/ { pid = substr($0, 2) }
    /^n/ { c = substr($0, 2) "/"; if (index(c, ENVIRON["D"]) == 1) print pid }'
}

file_size() { wc -c <"$1" | tr -d ' '; }

# ---------------------------------------------------------------------------

[ $# -ge 1 ] || usage
VERB=$1
shift
case $VERB in
  -h | --help)
    help_text
    exit 0
    ;;
  check | reclaim) ;;
  *) usage ;;
esac
PROGRAM='' WT=''
while [ $# -gt 0 ]; do
  case $1 in
    --program)
      [ $# -ge 2 ] || usage
      PROGRAM=$2
      shift 2
      ;;
    -*) usage ;;
    *)
      [ -z "$WT" ] || usage
      WT=$1
      shift
      ;;
  esac
done
[ -n "$PROGRAM" ] && [ -n "$WT" ] || usage
case $WT in
  /*) ;;
  *) mc_usage_fail "the worktree must be an absolute path" ;;
esac
[ "$WT" = "$(sanitize_printable "$WT")" ] || mc_usage_fail "refusing a worktree path with a control byte"
mc_require_program "$PROGRAM"
REPOS=$(/bin/bash "$script_dir/mc-program.sh" get "$PROGRAM" repositories) || mc_fail "the repositories of program $PROGRAM do not resolve"

# --- shape: a linked worktree of a program repository ------------------------

[ -d "$WT" ] || refuse not-a-worktree "no such directory"
WT=$(cd "$WT" && pwd -P) || refuse not-a-worktree "not a traversable directory"
[ "$WT" = "$(sanitize_printable "$WT")" ] || mc_usage_fail "refusing a worktree whose resolved path holds a control byte"
# The worktree's .git file is the worker's to write, so it only names a
# candidate: the repository's own worktrees/<id>/gitdir must point back.
MAIN='' GITDIR=''
gd_raw=''
if [ -f "$WT/.git" ] && [ ! -L "$WT/.git" ]; then
  gd_raw=$(sed -n '1s/^gitdir: //p' "$WT/.git" 2>/dev/null)
fi
case $gd_raw in
  '') ;;
  /*) gd_abs=$gd_raw ;;
  *) gd_abs="$WT/$gd_raw" ;;
esac
gd=''
[ -z "$gd_raw" ] || gd=$(cd "$gd_abs" 2>/dev/null && pwd -P) || gd=''
while IFS= read -r repo; do
  [ -n "$repo" ] || continue
  r_top=$(cd "$repo" 2>/dev/null && pwd -P) || continue
  [ "$r_top" != "$WT" ] || refuse main-checkout "the repository's main checkout is never reclaimed"
  [ -n "$gd" ] || continue
  r_common=$(git -C "$r_top" rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || continue
  r_common=$(cd "$r_common" 2>/dev/null && pwd -P) || continue
  case ${gd#"$r_common"/worktrees/} in
    "$gd" | '' | */*) continue ;;
  esac
  back=$(head -n 1 "$gd/gitdir" 2>/dev/null) || continue
  case $back in
    /*) ;;
    *) back="$gd/$back" ;;
  esac
  back_dir=$(cd "${back%/.git}" 2>/dev/null && pwd -P) || continue
  [ "$back_dir" = "$WT" ] && [ "${back##*/}" = .git ] || continue
  MAIN=$r_top GITDIR=$gd
  break
done <<EOF
$REPOS
EOF
[ -n "$MAIN" ] || refuse not-program-repo "not a linked worktree of a repository program $PROGRAM lists"
REPO_NAME=${MAIN##*/}
while IFS= read -r repo; do
  [ -n "$repo" ] || continue
  o_top=$(cd "$repo" 2>/dev/null && pwd -P) || continue
  [ "$o_top" = "$MAIN" ] || [ "${o_top##*/}" != "$REPO_NAME" ] \
    || refuse not-program-repo "two of the program's repositories are named $REPO_NAME, so the reclaim folder would be shared"
done <<EOF
$REPOS
EOF
case $REPO_NAME in
  '' | . | .. | -*) refuse not-a-worktree "the main checkout's directory name cannot name a folder" ;;
esac
BRANCH=$(g symbolic-ref --quiet --short HEAD 2>/dev/null) || refuse detached "HEAD names no branch"
git check-ref-format --branch "$BRANCH" >/dev/null 2>&1 || refuse bad-branch "the branch name is not a valid ref"
HEAD_OID=$(g rev-parse HEAD 2>/dev/null) || refuse not-a-worktree "HEAD is unreadable"

# --- the predicate -------------------------------------------------------------

users=$(live_users "$WT") || refuse live-user "the process table's working directories cannot be read"
[ -z "$users" ] || refuse live-user "in use by pid $(printf '%s' "$users" | tr '\n' ' ' | sed 's/ $//')"

# A submodule's own git directory is the worker's to configure, and status
# would run its filters; the removal refuses a worktree holding one anyway.
gitlinks=$(g ls-files --stage 2>/dev/null | awk '$1 == "160000"' | head -n 1) || refuse uncommitted "git ls-files failed"
[ -z "$gitlinks" ] || refuse uncommitted "the worktree holds a submodule"
status=$(g status --porcelain --untracked-files=all --ignore-submodules=all 2>/dev/null) || refuse uncommitted "git status failed"
[ -z "$status" ] || refuse uncommitted "$(printf '%s\n' "$status" | wc -l | tr -d ' ') path(s) changed or untracked"

prs=$(cd "$MAIN" && /bin/sh "$script_dir/bounded-run.sh" "$GH_BOUND" gh pr list --head "$BRANCH" --state all \
  --json number,state,headRefOid,isCrossRepository \
  --template '{{range .}}{{.number}} {{.state}} {{.headRefOid}} {{.isCrossRepository}}{{"\n"}}{{end}}' 2>/dev/null </dev/null) \
  || refuse pr-unreadable "the forge query failed or did not finish within ${GH_BOUND}s"
PR_STATE='' PR_NUM='' MERGED_PR=''
while read -r p_num p_state p_oid p_cross p_extra; do
  [ -n "$p_num" ] || continue
  if [ -n "$p_extra" ] || ! mc_valid_uint "$p_num"; then
    refuse pr-unreadable "the forge returned a line outside the asked shape"
  fi
  case $p_oid in
    *[!0-9a-f]* | '') refuse pr-unreadable "the forge returned no usable head oid" ;;
  esac
  case $p_cross in
    true) continue ;;
    false) ;;
    *) refuse pr-unreadable "the forge did not say whether PR #$p_num comes from a fork" ;;
  esac
  case $p_state in
    OPEN) refuse pr-open "PR #$p_num is open" ;;
    MERGED)
      if [ "$p_oid" = "$HEAD_OID" ]; then
        PR_STATE=merged PR_NUM=$p_num MERGED_PR=$p_num
      elif [ "$PR_STATE" != merged ]; then
        PR_STATE=merged PR_NUM=$p_num
      fi
      ;;
    CLOSED) [ -n "$PR_STATE" ] || PR_STATE=closed PR_NUM=$p_num ;;
    *) refuse pr-unreadable "PR #$p_num has an unknown state" ;;
  esac
done <<EOF
$prs
EOF
[ -n "$PR_STATE" ] || refuse no-pr "the forge has no PR from this repository for branch $BRANCH"

if [ -z "$MERGED_PR" ]; then
  g rev-parse --verify --quiet '@{upstream}' >/dev/null 2>&1 \
    || refuse unpushed "no upstream and no PR merged at HEAD, so nothing proves the commits are pushed"
  ahead=$(g rev-list --count '@{upstream}..HEAD' 2>/dev/null) || refuse unpushed "the unpushed count is unreadable"
  [ "$ahead" = 0 ] || refuse unpushed "$ahead commit(s) ahead of the upstream"
fi

if [ "$VERB" = check ]; then
  printf 'check\t%s\tok\t%s\t#%s\n' "$(sanitize_printable "$WT")" "$PR_STATE" "$PR_NUM"
  exit 0
fi

# --- the backup ----------------------------------------------------------------

HOME_DIR=$(/bin/bash "$script_dir/mc-program.sh" get "$PROGRAM" home) || mc_fail "the home of program $PROGRAM does not resolve"
FILES=$(mc_knob mission_control_reclaim_files parse_paths) || exit 1
(umask 077 && mkdir -p "$HOME_DIR") 2>/dev/null || mc_fail "cannot create the home of program $PROGRAM"
on_signal() {
  rollback
  printf '%s\t%s\t%s\t%s\t%s\n' "$VERB" "$(sanitize_printable "$WT")" refused interrupted "a signal stopped the backup; its copies were taken back"
  exit 1
}
pw_lock_trap_install
trap on_signal HUP INT TERM
make_dir "$HOME_DIR" reclaimed
RECLAIMED="$HOME_DIR/reclaimed"
DEST_LOCK="$RECLAIMED/.lock.$(printf '%s/%s' "$REPO_NAME" "$BRANCH" | mc_sha256)"
pw_lock_acquire "$DEST_LOCK"
case $? in
  0) ;;
  1)
    DEST_LOCK=''
    refuse backup "another reclaim of this folder is running"
    ;;
  *)
    DEST_LOCK=''
    refuse backup "cannot take the reclaim folder's lock"
    ;;
esac
make_dir "$RECLAIMED" "$REPO_NAME/$BRANCH"
DEST="$RECLAIMED/$REPO_NAME/$BRANCH"

list=''
while IFS= read -r pat; do
  [ -n "$pat" ] || continue
  # The pattern's `*` expands here, and only here; a space is no separator.
  set +f
  old_ifs=$IFS
  IFS=$NL
  # shellcheck disable=SC2086
  set -- "$WT"/$pat
  IFS=$old_ifs
  set -f
  for m in "$@"; do
    case $m in
      *"$NL"*) refuse backup "a file name matching $pat holds a newline" ;;
    esac
    [ -e "$m" ] && [ ! -L "$m" ] || continue
    if [ -d "$m" ]; then
      [ -z "$(find "$m" -name "*$NL*" 2>/dev/null | head -n 1)" ] || refuse backup "a file name under ${m#"$WT"/} holds a newline"
      found=$(find "$m" -type f 2>/dev/null) || refuse backup "cannot list ${m#"$WT"/}"
      list="$list$found$NL"
    elif [ -f "$m" ]; then
      list="$list$m$NL"
    fi
  done
done <<EOF
$FILES
EOF
list=$(printf '%s' "$list" | awk 'NF && !seen[$0]++')

n=0
while IFS= read -r src; do
  [ -n "$src" ] || continue
  rel=${src#"$WT"/}
  src_dir=$(cd "${src%/*}" 2>/dev/null && pwd -P) || refuse backup "cannot resolve the directory of $rel"
  case "$src_dir/" in
    "$WT"/*) ;;
    *) refuse backup "$rel resolves outside the worktree" ;;
  esac
  g check-ignore -q -- "$rel" 2>/dev/null
  case $? in
    0) ;;
    1) continue ;;
    *) refuse backup "git cannot say whether $rel is ignored" ;;
  esac
  [ -f "$src" ] && [ ! -L "$src" ] || refuse backup "$rel is no longer a regular file"
  case $rel in
    */*) make_dir "$DEST" "${rel%/*}" ;;
  esac
  dst="$DEST/$rel"
  src_sum=$(mc_sha256 <"$src") || refuse backup "cannot hash $rel"
  if [ -e "$dst" ] || [ -L "$dst" ]; then
    [ -f "$dst" ] && [ ! -L "$dst" ] && [ "$(mc_sha256 <"$dst")" = "$src_sum" ] \
      || refuse backup "the reclaim folder already holds a different $rel"
  else
    CREATED="$CREATED$dst$NL"
    cp "$src" "$dst" 2>/dev/null || refuse backup "the copy of $rel failed"
  fi
  [ -f "$dst" ] || refuse backup "the copy of $rel is missing"
  [ "$(file_size "$dst")" = "$(file_size "$src")" ] || refuse backup "the copy of $rel: size mismatch"
  [ "$(mc_sha256 <"$dst")" = "$src_sum" ] || refuse backup "the copy of $rel: hash mismatch"
  n=$((n + 1))
done <<EOF
$list
EOF

# --- the removal ---------------------------------------------------------------

users=$(live_users "$WT") || refuse removal "the process table's working directories cannot be read"
[ -z "$users" ] || refuse removal "a process entered the worktree: pid $(printf '%s' "$users" | tr '\n' ' ' | sed 's/ $//')"
# From here the copies stay whatever happens: a removal that fails partway
# may already have deleted their sources.
CREATED='' MADE=''
trap '' HUP INT TERM
set -- worktree "$WT" "mission-control reclaim" "program $PROGRAM: $PR_STATE PR #$PR_NUM, $n audit file(s) backed up"
[ -z "$MERGED_PR" ] || set -- "$@" --merged-pr "$MERGED_PR"
fc_err=$(cd "$MAIN" && GIT_CONFIG_COUNT=2 GIT_CONFIG_KEY_0=core.fsmonitor GIT_CONFIG_VALUE_0=false \
  GIT_CONFIG_KEY_1=core.hooksPath GIT_CONFIG_VALUE_1=/dev/null \
  /bin/sh "$script_dir/fleet-cleanup.sh" "$@" 2>&1 >/dev/null </dev/null)
fc_rc=$?
if [ "$fc_rc" != 0 ] && [ "$fc_rc" != 6 ]; then
  refuse removal "fleet-cleanup exit $fc_rc, copies kept: $(printf '%s' "$fc_err" | tail -n 1)"
fi
pw_lock_release "$DEST_LOCK" || :
[ "$fc_rc" = 0 ] || printf '%s\n' "$prog: the worktree was removed but its audit-trail record failed" >&2
printf 'reclaim\t%s\treclaimed\t%s\t%s files\n' "$(sanitize_printable "$WT")" "$(sanitize_printable "$DEST")" "$n"
