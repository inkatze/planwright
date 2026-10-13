#!/bin/bash
# merge-class.sh — evaluate whether a unit PR is inside the declared policy
# class, so it may merge under `merge_policy: policy-class` with no per-PR
# human act (doctrine/human-gates.md; the class is the human-gates spec's
# REQ-D1.3, REQ-D1.8, and REQ-D1.9).
#
# Usage:
#   merge-class.sh evaluate --spec <dir> --task <id>... [--pr <n>]
#       [--worktree <dir>] [--out <file>]
#   merge-class.sh identity [--pr <n>] [--worktree <dir>]
#
#   --spec, --task, --worktree   as scripts/ready-flip.sh takes them; the
#               checkout must sit on a planwright/<spec>/task-<ids> branch
#
#   evaluate    every predicate below, written as the evidence record to
#               --out, else stdout. Never merges, flips, comments, or parks;
#               scripts/merge-admitted.sh acts on the record. It reads no
#               merge_policy: the helper does.
#   identity    which human act approves the PR under on-approval: always
#               `act<TAB>enable-auto-merge`, plus
#               `act<TAB>approving-review-with-auto-merge` when the session's
#               GitHub login differs from the PR author's (a server-verified
#               approval then exists). A shared identity is never refused.
#
# Predicates, in order. The cheap ones run first, and when one fails the
# ready-flip preconditions are skipped, so a known fall-through costs no CI
# wait:
#   branch           the PR head is a task branch (planwright/<spec>/task-<ids>,
#                    <spec> one segment) from the base repository. Fixed: no
#                    layer widens it, so a release, bot, flight, or human PR
#                    always falls to on-approval.
#   sign-off         no commit in base..head carries a Planwright-Sign-Off
#                    trailer or a legacy ` [pending-sign-off]` subject: a raw
#                    scan, so a reverted or rejected item still refuses.
#   core-zone        no changed path matches the core zone below, which no
#                    layer can shrink.
#   excluded-paths   no changed path matches merge_class_exclude_paths.
#   max-lines        the change's added plus deleted lines are at most
#                    merge_class_max_lines (0 admits nothing; a binary change
#                    has no line count and refuses).
#   strategy         merge_class_strategy resolves to one method the host
#                    allows: sole-allowed needs exactly one allowed method, a
#                    named one must be allowed, and a failed host query fails.
#   awaiting-input, review-converged, ci-rollup, ready-guard
#                    scripts/ready-flip.sh evaluate --for-merge on the head,
#                    once: its record is the one the merge helper hands to the
#                    flip, so the bounded CI wait never runs twice.
# Changed paths and lines are taken from the merge base with the fetched base
# ref, renames split into their two paths. Globs match the whole path and `*`
# spans `/`.
#
# The record:
#   head<TAB><sha>
#   base<TAB><branch><TAB><oid>
#   pr<TAB><n>
#   strategy<TAB><method, or - when none resolved>
#   pred<TAB><name><TAB>pass|fail|skip<TAB><evidence>
#
# Exit: 0 admitted; 2 usage; 3 skipped (no gh, no open PR); 4 not admitted,
# the record names why; 5 refused before a record (a checkout off the unit's
# own branch, spec, or tasks; an unreadable PR or base; a reconcile, push, or
# flip-precondition evaluation that could not run). A head outside the branch
# set records the PR's own head and skips every other predicate.
#
# No model in the decision path: every predicate is a comparison.
set -u
unset CDPATH
LC_ALL=C
export LC_ALL

SCRIPTS=$(cd "$(dirname "$0")" && pwd) || exit 2
if [ ! -f "$SCRIPTS/echo-safety.sh" ] || [ ! -r "$SCRIPTS/echo-safety.sh" ]; then
  printf '%s\n' "merge-class.sh: echo-safety.sh is missing or unreadable (broken install)" >&2
  exit 2
fi
# shellcheck source=scripts/echo-safety.sh
. "$SCRIPTS/echo-safety.sh" || exit 2

# planwright's own enforcement surface (its profiles, hooks, guards, skills, the
# scripts the class and its records are computed by, its policy defaults),
# plus the files a repository keeps its policy, CI definition, and dependency
# pins in.
readonly CORE_ZONE='hooks/* githooks/* skills/* config/*-settings.json config/defaults.yml config/steps.yaml .claude/settings.json .claude/settings.local.json .claude/planwright.yml .claude-plugin/* scripts/*guard*.sh scripts/resolve-*.sh scripts/inception-secret-screen.sh scripts/config-get.sh scripts/protected-branch.sh scripts/ready-flip.sh scripts/merge-class.sh scripts/merge-admitted.sh scripts/step-record.sh scripts/spec-parse.sh scripts/echo-safety.sh scripts/planwright-commit-trailers.sh scripts/lock-lib.sh .github/* mise.toml .mise.toml .config/mise.toml .config/mise/* mise/* .mise/* mise-tasks/* lefthook.yml .lefthook.yml doctrine/human-gates.md tests/fixtures/reserved-control-spellings *package-lock.json *npm-shrinkwrap.json *pnpm-lock.yaml *.lock *go.sum'
readonly TASK_BRANCH_RE='^planwright/[a-z0-9][a-z0-9-]*/task-[0-9]+(\.[0-9]+)?(-[0-9]+(\.[0-9]+)?)?$'

say() { printf 'merge-class: %s\n' "$*"; }
usage() {
  printf 'merge-class: %s\n' "$1" >&2
  echo 'usage: merge-class.sh evaluate --spec <dir> --task <id>... [--pr <n>] [--worktree <dir>] [--out <file>] | identity [--pr <n>] [--worktree <dir>]' >&2
  exit 2
}
refuse() {
  say "not evaluated: $1"
  exit 5
}

SCRATCH=$(mktemp -d "${TMPDIR:-/tmp}/merge-class.XXXXXX") || exit 5
trap 'rm -rf "$SCRATCH"' EXIT

MODE=${1:-}
case $MODE in
  evaluate | identity) shift ;;
  *) usage 'the first argument must be evaluate or identity' ;;
esac
SPEC='' WT='' PR='' OUTF='' IDS=()
while [ "$#" -gt 0 ]; do
  case $1 in
    --spec | --task | --pr | --worktree | --out)
      [ "$#" -ge 2 ] || usage "$1 needs a value"
      case $1 in
        --spec) SPEC=$2 ;;
        --task) IDS[${#IDS[@]}]=$2 ;;
        --pr) PR=$2 ;;
        --worktree) WT=$2 ;;
        --out) OUTF=$2 ;;
      esac
      shift 2
      ;;
    *) usage "unknown argument '$(sanitize_printable "$1" '?')'" ;;
  esac
done
[ -z "$PR" ] || [[ $PR =~ ^[1-9][0-9]{0,9}$ ]] || usage '--pr must be a pull request number'
if [ "$MODE" = evaluate ]; then
  [ -n "$SPEC" ] || usage '--spec is required'
  [ "${#IDS[@]}" -gt 0 ] || usage 'at least one --task is required'
  [[ $SPEC =~ ^[A-Za-z0-9_][A-Za-z0-9._-]*(/[A-Za-z0-9_][A-Za-z0-9._-]*)*$ ]] \
    || usage '--spec must be a relative path inside the checkout'
  case "/$SPEC/" in */../* | */./*) usage '--spec must not climb out of the checkout' ;; esac
  for id in "${IDS[@]}"; do
    [[ $id =~ ^[0-9]+(\.[0-9]+)?$ ]] || usage "task id '$(sanitize_printable "$id" '?')' is malformed"
  done
else
  [ -z "$SPEC$OUTF" ] && [ "${#IDS[@]}" = 0 ] || usage 'identity takes only --pr and --worktree'
fi
case $OUTF in '' | /*) ;; *) OUTF="$PWD/$OUTF" ;; esac
[ -n "$WT" ] || WT=.
case $WT in -*) WT="./$WT" ;; esac
cd "$WT" 2>/dev/null || refuse 'the worktree cannot be entered'
WT=$(git rev-parse --show-toplevel 2>/dev/null) || refuse 'not inside a git checkout'
cd "$WT" 2>/dev/null || refuse 'the worktree cannot be entered'
BRANCH=$(git symbolic-ref --short -q HEAD 2>/dev/null) || BRANCH=''

if ! command -v gh >/dev/null 2>&1; then
  say 'skipped: gh is not installed, so no pull request can be read'
  exit 3
fi
command -v jq >/dev/null 2>&1 || refuse 'jq is required to read the host answers'

# --- identity ------------------------------------------------------------------

if [ "$MODE" = identity ]; then
  agent=$(gh api user --jq .login 2>/dev/null) || agent=''
  author=$(gh pr view ${PR:+"$PR"} --json author --jq '.author.login // empty' 2>/dev/null) || author=''
  printf 'act\tenable-auto-merge\n'
  login_re='^[A-Za-z0-9][A-Za-z0-9_.-]{0,63}(\[bot\])?$'
  if [[ $agent =~ $login_re ]] && [[ $author =~ $login_re ]] \
    && [ "$agent" != "$author" ]; then
    printf 'act\tapproving-review-with-auto-merge\n'
  fi
  exit 0
fi

# --- evaluate ------------------------------------------------------------------

[[ $BRANCH =~ $TASK_BRANCH_RE ]] || refuse 'the checkout is not on a planwright task branch'
# The unit is the branch's: its spec, and its task id or id range.
B_SEG=${BRANCH#planwright/}
B_SPEC=${B_SEG%%/*}
B_IDS=${B_SEG##*/task-}
[ "${SPEC##*/}" = "$B_SPEC" ] || refuse "--spec names ${SPEC##*/}, but the checkout is on $B_SPEC's task branch"
TASK_ARGS=()
for id in "${IDS[@]}"; do
  case $B_IDS in
    # Ids compare by major then minor as integers: 3.10 follows 3.9.
    *-*) awk -v i="$id" -v lo="${B_IDS%-*}" -v hi="${B_IDS#*-}" '
      function key(v, p) { split(v, p, "."); return p[1] * 1000000000 + p[2] }
      BEGIN { exit !(key(i) >= key(lo) && key(i) <= key(hi)) }' ;;
    *) [ "$id" = "$B_IDS" ] ;;
  esac || refuse "task $id is not the unit the branch names (task-$B_IDS)"
  TASK_ARGS+=(--task "$id")
done
REMOTE=$(git config "branch.$BRANCH.remote" 2>/dev/null) || REMOTE=origin
[[ $REMOTE =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || refuse 'the branch remote is not a plain remote name'

declare -a P_NAME=() P_RES=() P_EVD=()
set_pred() { # <name> <pass|fail|skip> <evidence>
  P_NAME[${#P_NAME[@]}]=$1
  P_RES[${#P_RES[@]}]=$2
  P_EVD[${#P_EVD[@]}]=$(sanitize_printable "$3" '?')
}
any_failed() {
  local r
  for r in ${P_RES[@]+"${P_RES[@]}"}; do [ "$r" != fail ] || return 0; done
  return 1
}
knob() { /bin/sh "$SCRIPTS/resolve-policy-knob.sh" "$1" 2>/dev/null; }

# The PR, from the host. A failed read is retried twice before it refuses.
raw='' i=0
while [ "$i" -lt 3 ]; do
  i=$((i + 1))
  raw=$(gh pr view "${PR:-$BRANCH}" --json number,state,baseRefName,headRefName,headRefOid,isCrossRepository 2>"$SCRATCH/err") && [ -n "$raw" ] && break
  case $(cat "$SCRATCH/err") in
    *'no pull requests found'* | *'Could not resolve to a PullRequest'* | *'no open pull requests'*)
      say "skipped: no pull request for ${PR:+PR #}${PR:-$BRANCH}"
      exit 3
      ;;
  esac
  raw=''
done
[ -n "$raw" ] || refuse 'the pull request could not be read'
PR=$(printf '%s' "$raw" | jq -r '.number // empty' 2>/dev/null)
state=$(printf '%s' "$raw" | jq -r '.state // empty' 2>/dev/null)
BASE=$(printf '%s' "$raw" | jq -r '.baseRefName // empty' 2>/dev/null)
HEAD_NAME=$(printf '%s' "$raw" | jq -r '.headRefName // empty' 2>/dev/null)
HOST_HEAD=$(printf '%s' "$raw" | jq -r '.headRefOid // empty' 2>/dev/null)
fork=$(printf '%s' "$raw" | jq -r '.isCrossRepository' 2>/dev/null)
[[ $PR =~ ^[1-9][0-9]{0,9}$ ]] || refuse 'the pull request number could not be read'
if ! [[ $BASE =~ ^[A-Za-z0-9_][A-Za-z0-9._/-]*$ ]] || ! git check-ref-format --branch "$BASE" >/dev/null 2>&1; then
  refuse 'the pull request base is not a branch name'
fi
if [ "$state" != OPEN ]; then
  say "skipped: PR #$PR is not open"
  exit 3
fi

if [ "$fork" != false ]; then
  set_pred branch fail 'the head is from another repository, not the base repository'
elif ! [[ $HEAD_NAME =~ $TASK_BRANCH_RE ]]; then
  set_pred branch fail "the head $(sanitize_printable "$HEAD_NAME" '?') is not a task branch; only task branches are in the class"
elif [ "$HEAD_NAME" != "$BRANCH" ]; then
  refuse "PR #$PR is not this checkout's branch"
else
  set_pred branch pass "$HEAD_NAME from the base repository"
fi

print_record() {
  local i=0
  printf 'head\t%s\nbase\t%s\t%s\npr\t%s\nstrategy\t%s\n' "$HEAD_SHA" "$BASE" "$BASE_OID" "$PR" "$METHOD"
  while [ "$i" -lt "${#P_NAME[@]}" ]; do
    printf 'pred\t%s\t%s\t%s\n' "${P_NAME[$i]}" "${P_RES[$i]}" "${P_EVD[$i]}"
    i=$((i + 1))
  done
}
emit_record() {
  if [ -n "$OUTF" ]; then
    print_record >"$OUTF" || refuse 'the record could not be written'
  else
    print_record
  fi
}

METHOD=-
git fetch -q "$REMOTE" "+refs/heads/$BASE:refs/remotes/$REMOTE/$BASE" >/dev/null 2>&1 \
  || refuse "the base $REMOTE/$BASE could not be fetched"
BASE_OID=$(git rev-parse --verify -q "refs/remotes/$REMOTE/$BASE^{commit}") || refuse "the base $REMOTE/$BASE could not be fetched"

# A head outside the branch set is the PR's own, not this checkout's: the
# record names the host's head and judges nothing else.
if any_failed; then
  [[ $HOST_HEAD =~ ^[0-9a-f]{40}([0-9a-f]{24})?$ ]] || refuse "PR #$PR's head could not be read"
  HEAD_SHA=$HOST_HEAD
  for p in sign-off core-zone excluded-paths max-lines strategy awaiting-input review-converged ci-rollup ready-guard; do
    set_pred "$p" skip 'not evaluated: the head is outside the branch set'
  done
  emit_record
  exit 4
fi

# Settle the Awaiting-input section first, so every predicate reads the head
# the flip would read.
/bin/bash "$SCRIPTS/ready-flip.sh" reconcile --spec "$SPEC" "${TASK_ARGS[@]}" >/dev/null 2>&1 \
  || refuse 'the Awaiting-input section could not be reconciled and pushed'
HEAD_SHA=$(git rev-parse HEAD) || refuse 'HEAD does not resolve'
MB=$(git merge-base "$BASE_OID" "$HEAD_SHA" 2>/dev/null) || refuse "the head shares no history with $REMOTE/$BASE"

# sign-off: a raw scan of the range.
if ! git log --format='%H%x09%(trailers:key=Planwright-Sign-Off,valueonly,separator=%x2C)%x09%s' \
  "$BASE_OID..$HEAD_SHA" >"$SCRATCH/log" 2>/dev/null; then
  set_pred sign-off fail "the commits of $REMOTE/$BASE..head could not be listed"
else
  hits=$(awk -F '\t' '
    { subj = $0; sub(/^[^\t]*\t[^\t]*\t/, "", subj) }
    $2 != "" || subj ~ / \[pending-sign-off\]$/ { out = out (out == "" ? "" : ", ") substr($1, 1, 7) }
    END { print out }' "$SCRATCH/log")
  if [ -n "$hits" ]; then
    set_pred sign-off fail "sign-off items in the range, reverted or not: $hits"
  else
    set_pred sign-off pass "no Planwright-Sign-Off trailer or legacy suffix in $(wc -l <"$SCRATCH/log" | tr -d ' ') commit(s)"
  fi
fi

# The changed paths.
match_any() { # <path> <globs> — print the first glob the whole path matches
  local p=$1 g
  set -f
  for g in $2; do
    # shellcheck disable=SC2053 # the glob is the pattern
    if [[ $p == $g ]]; then
      set +f
      printf '%s' "$g"
      return 0
    fi
  done
  set +f
  return 1
}
PATHS_OK=1
git diff --name-only --no-renames -z "$MB" "$HEAD_SHA" >"$SCRATCH/paths" 2>/dev/null || PATHS_OK=0
EXCLUDE_OK=0
EXCLUDE=$(knob merge_class_exclude_paths) || EXCLUDE_OK=1
zone_hit='' excl_hit='' n=0
if [ "$PATHS_OK" = 1 ]; then
  while IFS= read -r -d '' p; do
    n=$((n + 1))
    [ -n "$zone_hit" ] || { g=$(match_any "$p" "$CORE_ZONE") && zone_hit="$p (core glob $g)"; }
    [ -n "$excl_hit" ] || { g=$(match_any "$p" "$EXCLUDE") && excl_hit="$p (glob $g)"; }
  done <"$SCRATCH/paths"
  if [ -n "$zone_hit" ]; then
    set_pred core-zone fail "a changed path is in the hard-disqualifier zone: $zone_hit"
  else
    set_pred core-zone pass "none of $n changed path(s) is in the core zone"
  fi
  if [ "$EXCLUDE_OK" != 0 ]; then
    set_pred excluded-paths fail 'merge_class_exclude_paths could not be resolved'
  elif [ -n "$excl_hit" ]; then
    set_pred excluded-paths fail "a changed path is excluded by merge_class_exclude_paths: $excl_hit"
  else
    set_pred excluded-paths pass "no changed path matches merge_class_exclude_paths"
  fi
else
  set_pred core-zone fail 'the changed paths could not be listed'
  set_pred excluded-paths fail 'the changed paths could not be listed'
fi

# max-lines.
if ! MAXL=$(knob merge_class_max_lines) || ! [[ $MAXL =~ ^[0-9]{1,9}$ ]]; then
  set_pred max-lines fail 'merge_class_max_lines could not be resolved'
elif ! git diff --numstat --no-renames "$MB" "$HEAD_SHA" >"$SCRATCH/numstat" 2>/dev/null; then
  set_pred max-lines fail 'the changed lines could not be counted'
elif grep -q '^-' "$SCRATCH/numstat"; then
  set_pred max-lines fail 'a binary change has no line count'
else
  lines=$(awk '{ s += $1 + $2 } END { print s + 0 }' "$SCRATCH/numstat")
  if [ "$MAXL" = 0 ]; then
    set_pred max-lines fail "merge_class_max_lines is 0, so the class admits nothing ($lines changed line(s))"
  elif [ "$lines" -gt "$MAXL" ]; then
    set_pred max-lines fail "$lines changed line(s), over merge_class_max_lines $MAXL"
  else
    set_pred max-lines pass "$lines changed line(s), within merge_class_max_lines $MAXL"
  fi
fi

# strategy.
if ! want=$(knob merge_class_strategy); then
  set_pred strategy fail 'merge_class_strategy could not be resolved'
elif ! methods=$(gh repo view --json mergeCommitAllowed,squashMergeAllowed,rebaseMergeAllowed 2>/dev/null \
  | jq -r '[(if .mergeCommitAllowed == true then "merge" else empty end), (if .squashMergeAllowed == true then "squash" else empty end), (if .rebaseMergeAllowed == true then "rebase" else empty end)] | join(" ")' 2>/dev/null) \
  || [ -z "$methods" ]; then
  set_pred strategy fail 'the merge methods the host allows could not be read'
elif [ "$want" = sole-allowed ]; then
  case $methods in
    *' '*) set_pred strategy fail "the host allows several methods ($methods) and merge_class_strategy is sole-allowed; name one" ;;
    *)
      METHOD=$methods
      set_pred strategy pass "$methods, the one method the host allows"
      ;;
  esac
else
  case " $methods " in
    *" $want "*)
      METHOD=$want
      set_pred strategy pass "$want, which the host allows"
      ;;
    *) set_pred strategy fail "merge_class_strategy is $want, which the host does not allow ($methods)" ;;
  esac
fi

# The ready-flip preconditions, once.
FLIP_PREDS='awaiting-input review-converged ci-rollup ready-guard'
if any_failed; then
  for p in $FLIP_PREDS; do set_pred "$p" skip 'not evaluated: a cheaper predicate failed'; done
else
  /bin/bash "$SCRIPTS/ready-flip.sh" evaluate --for-merge --spec "$SPEC" "${TASK_ARGS[@]}" --pr "$PR" \
    --out "$SCRATCH/flip" >"$SCRATCH/flip.out" 2>&1
  rc=$?
  if [ "$rc" = 3 ]; then
    say "skipped: $(sanitize_printable "$(tail -1 "$SCRATCH/flip.out")" '?')"
    exit 3
  fi
  if { [ "$rc" = 0 ] || [ "$rc" = 4 ]; } && grep -qx "head	$HEAD_SHA" "$SCRATCH/flip" 2>/dev/null; then
    for p in $FLIP_PREDS; do
      line=$(awk -F '\t' -v p="$p" '$1 == "pred" && $2 == p { print; exit }' "$SCRATCH/flip")
      res=$(printf '%s' "$line" | cut -f3)
      case $res in
        pass | fail | skip) set_pred "$p" "$res" "$(printf '%s' "$line" | cut -f4-)" ;;
        *) set_pred "$p" fail 'missing from the ready-flip record' ;;
      esac
    done
  else
    # Not a predicate verdict (an unreadable PR, a failed reconcile or push):
    # this run cannot say, so it refuses rather than report a fall-through.
    refuse "the ready-flip preconditions could not be evaluated on ${HEAD_SHA:0:12}: $(sanitize_printable "$(tail -1 "$SCRATCH/flip.out" 2>/dev/null)" "exit $rc")"
  fi
fi

emit_record
any_failed && exit 4
exit 0
