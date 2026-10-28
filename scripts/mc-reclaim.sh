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
for lib in echo-safety.sh mc-lib.sh; do
  if [ ! -r "$script_dir/$lib" ]; then
    printf '%s\n' "$prog: $lib is missing or unreadable (broken install)" >&2
    exit 2
  fi
done
# shellcheck source=scripts/echo-safety.sh
. "$script_dir/echo-safety.sh" || exit 2
# shellcheck source=scripts/mc-lib.sh
. "$script_dir/mc-lib.sh" || exit 2

GH_BOUND=20
NL='
'
OLD_IFS=$IFS

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
repositories. The predicate's arms, each refusing on its own:
  live-user      a process has its working directory in the worktree, or
                 the process table's working directories cannot be read
  uncommitted    git status lists a change or an untracked file
  no-pr, pr-open the forge has no PR for the branch, or one is still open;
                 a merged or closed one passes
  unpushed       a commit is on no remote-tracking ref, unless the PR merged
                 at exactly the worktree's HEAD
and the shape checks: not-a-worktree, main-checkout, detached, pr-unreadable.

The backup copies every git-ignored file the mission_control_reclaim_files
knob matches (worktree-relative paths, `*` in the last component, a
directory taken whole, a symbolic link never followed) into
<program home>/reclaimed/<repository>/<branch>/, at the same relative path,
and compares each copy's size and SHA-256 with its source. A copy that
fails, differs, or would replace a different file already there refuses the
reclaim with the worktree untouched. The removal is fleet-cleanup.sh's
guarded `worktree` arm, run from the repository's main checkout.

Output, tab separated:
  <verb> <worktree> ok <merged|closed> #<n>              check passed
  reclaim <worktree> reclaimed <folder> <n> files
  <verb> <worktree> refused <arm> <detail>

Exit codes: 0 passed or reclaimed; 1 refused; 2 usage, or a path that is
not absolute; 3 the program is not configured.
HELP
}

usage() {
  mc_usage_fail "usage: mc-reclaim.sh check|reclaim --program <p> <worktree>"
}

CREATED=''
refuse() { # refuse <arm> <detail>
  # A refused backup takes back the copies it made, so a bad copy never
  # blocks the next attempt as "a different file already there".
  if [ -n "$CREATED" ]; then
    while IFS= read -r rf_f; do
      [ -z "$rf_f" ] || rm -f "$rf_f"
    done <<EOF
$CREATED
EOF
  fi
  printf '%s\t%s\t%s\t%s\t%s\n' "$VERB" "$(sanitize_printable "$WT")" refused "$1" "$(sanitize_printable "$2")"
  exit 1
}

# mc_parse_paths <raw>: an inline list of worktree-relative paths, one per
# line; fails on an absolute path, a `..` component, a `*` outside the last
# component, or a control byte.
mc_parse_paths() {
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
      if (p ~ /^".*"$/) p = substr(p, 2, length(p) - 2)
      if (p == "" || p ~ /^\// || p ~ /(^|\/)\.\.?(\/|$)/ || p ~ /[][?{}\\]/) exit 1
      d = p; sub(/[^\/]*$/, "", d)
      if (d ~ /\*/) exit 1
      print p
    }
  }'
}

# live_users <dir>: print the pid of every process whose working directory is
# <dir> or below it; fails when the working directories cannot be read.
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
HOME_DIR=$(/bin/bash "$script_dir/mc-program.sh" get "$PROGRAM" home) || mc_fail "the home of program $PROGRAM does not resolve"
FILES=$(mc_knob mission_control_reclaim_files mc_parse_paths) || exit 1

# --- shape ------------------------------------------------------------------

[ -d "$WT" ] || refuse not-a-worktree "no such directory"
WT=$(cd "$WT" && pwd -P) || refuse not-a-worktree "not a traversable directory"
top=$(git -C "$WT" rev-parse --show-toplevel 2>/dev/null) || top=''
top=$(cd "$top" 2>/dev/null && pwd -P) || top=''
[ "$top" = "$WT" ] || refuse not-a-worktree "not the root of a git worktree"
MAIN=$(git -C "$WT" worktree list --porcelain 2>/dev/null | awk '/^worktree / { print substr($0, 10); exit }')
MAIN=$(cd "$MAIN" 2>/dev/null && pwd -P) || refuse not-a-worktree "its main checkout cannot be found"
[ "$MAIN" != "$WT" ] || refuse main-checkout "the repository's main checkout is never reclaimed"
BRANCH=$(git -C "$WT" symbolic-ref --quiet --short HEAD 2>/dev/null) || refuse detached "HEAD names no branch"
git check-ref-format --branch "$BRANCH" >/dev/null 2>&1 || refuse detached "the branch name is not a valid ref"
REPO_NAME=${MAIN##*/}
case $REPO_NAME in
  '' | . | .. | -*) refuse not-a-worktree "the main checkout's directory name cannot name a folder" ;;
esac
HEAD_OID=$(git -C "$WT" rev-parse HEAD 2>/dev/null) || refuse not-a-worktree "HEAD is unreadable"

# --- the predicate ------------------------------------------------------------

users=$(live_users "$WT") || refuse live-user "the process table's working directories cannot be read"
[ -z "$users" ] || refuse live-user "in use by pid $(printf '%s' "$users" | tr '\n' ' ' | sed 's/ $//')"

status=$(git -C "$WT" status --porcelain 2>/dev/null) || refuse uncommitted "git status failed"
[ -z "$status" ] || refuse uncommitted "$(printf '%s\n' "$status" | wc -l | tr -d ' ') path(s) changed or untracked"

prs=$(cd "$WT" && /bin/sh "$script_dir/bounded-run.sh" "$GH_BOUND" gh pr list --head "$BRANCH" --state all \
  --json number,state,headRefOid --template '{{range .}}{{.number}} {{.state}} {{.headRefOid}}{{"\n"}}{{end}}' 2>/dev/null </dev/null) \
  || refuse pr-unreadable "the forge query failed or did not finish within ${GH_BOUND}s"
PR_STATE='' PR_NUM='' MERGED_PR=''
while read -r p_num p_state p_oid p_extra; do
  [ -n "$p_num" ] || continue
  if [ -n "$p_extra" ] || ! mc_valid_uint "$p_num"; then
    refuse pr-unreadable "the forge returned a line outside the asked shape"
  fi
  case $p_oid in
    *[!0-9a-f]* | '') refuse pr-unreadable "the forge returned no usable head oid" ;;
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
[ -n "$PR_STATE" ] || refuse no-pr "the forge has no PR for branch $BRANCH"

ahead=$(git -C "$WT" rev-list --count HEAD --not --remotes 2>/dev/null) || refuse unpushed "the unpushed count is unreadable"
if [ "$ahead" != 0 ] && [ -z "$MERGED_PR" ]; then
  refuse unpushed "$ahead commit(s) on no remote-tracking ref"
fi

if [ "$VERB" = check ]; then
  printf 'check\t%s\tok\t%s\t#%s\n' "$(sanitize_printable "$WT")" "$PR_STATE" "$PR_NUM"
  exit 0
fi

# --- the backup ---------------------------------------------------------------

DEST="$HOME_DIR/reclaimed/$REPO_NAME/$BRANCH"
list=''
while IFS= read -r pat; do
  [ -n "$pat" ] || continue
  # The pattern's `*` expands here, and only here; a space is no separator.
  set +f
  IFS=$NL
  # shellcheck disable=SC2086
  set -- "$WT"/$pat
  IFS=$OLD_IFS
  set -f
  for m in "$@"; do
    [ -e "$m" ] && [ ! -L "$m" ] || continue
    if [ -d "$m" ]; then
      found=$(find "$m" -type f 2>/dev/null) || refuse backup "cannot list $(sanitize_printable "${m#"$WT"/}")"
      list="$list$found
"
    elif [ -f "$m" ]; then
      list="$list$m
"
    fi
  done
done <<EOF
$FILES
EOF

n=0
while IFS= read -r src; do
  [ -n "$src" ] || continue
  rel=${src#"$WT"/}
  src_dir=$(cd "${src%/*}" 2>/dev/null && pwd -P) || refuse backup "cannot resolve the directory of $rel"
  case "$src_dir/" in
    "$WT"/*) ;;
    *) refuse backup "$rel resolves outside the worktree" ;;
  esac
  git -C "$WT" check-ignore -q -- "$rel" 2>/dev/null || continue
  dst="$DEST/$rel"
  src_sum=$(mc_sha256 <"$src") || refuse backup "cannot hash $rel"
  if [ -e "$dst" ] || [ -L "$dst" ]; then
    [ -f "$dst" ] && [ ! -L "$dst" ] && [ "$(mc_sha256 <"$dst")" = "$src_sum" ] \
      || refuse backup "the reclaim folder already holds a different $rel"
  else
    (umask 077 && mkdir -p "${dst%/*}") 2>/dev/null || refuse backup "cannot create the folder for $rel"
    CREATED="$CREATED$dst
"
    cp "$src" "$dst" 2>/dev/null || refuse backup "the copy of $rel failed"
  fi
  [ -f "$dst" ] || refuse backup "the copy of $rel is missing"
  [ "$(file_size "$dst")" = "$(file_size "$src")" ] || refuse backup "the copy of $rel: size mismatch"
  [ "$(mc_sha256 <"$dst")" = "$src_sum" ] || refuse backup "the copy of $rel: hash mismatch"
  n=$((n + 1))
done <<EOF
$list
EOF

# --- the removal ----------------------------------------------------------------

# Verified copies stay even if the removal is refused.
CREATED=''

set -- worktree "$WT" "mission-control reclaim" "program $PROGRAM: $PR_STATE PR #$PR_NUM, $n audit file(s) backed up"
[ -z "$MERGED_PR" ] || set -- "$@" --merged-pr "$MERGED_PR"
fc_err=$(cd "$MAIN" && /bin/sh "$script_dir/fleet-cleanup.sh" "$@" 2>&1 >/dev/null </dev/null)
fc_rc=$?
if [ "$fc_rc" != 0 ] && [ "$fc_rc" != 6 ]; then
  refuse removal "fleet-cleanup exit $fc_rc: $(printf '%s' "$fc_err" | tail -n 1)"
fi
[ "$fc_rc" = 0 ] || printf '%s\n' "$prog: the worktree was removed but its audit-trail record failed" >&2
printf 'reclaim\t%s\treclaimed\t%s\t%s files\n' "$(sanitize_printable "$WT")" "$(sanitize_printable "$DEST")" "$n"
