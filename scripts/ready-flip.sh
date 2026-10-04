#!/bin/bash
# ready-flip.sh — mark a unit's draft PR ready under `ready_flip_policy:
# unit-owner`, or park the pending flip when a precondition fails
# (doctrine/human-gates.md; the policy and its preconditions are the
# human-gates spec's REQ-C1.2 to REQ-C1.4).
#
# Usage:
#   ready-flip.sh reconcile --spec <dir> --task <id>... [--worktree <dir>]
#   ready-flip.sh evaluate  --spec <dir> --task <id>... [--pr <n>]
#       [--worktree <dir>] [--out <file>]
#   ready-flip.sh flip      --spec <dir> --task <id>... [--pr <n>]
#       [--worktree <dir>] [--expect-head <sha>] [--preconditions <file>]
#
#   --spec      the bundle directory, relative to the unit checkout
#               (specs/<spec>); its tasks.md must be format-version 2
#   --task      one task id of the unit; repeat it for a bundle
#   --worktree  the unit checkout; default the enclosing git top level. It
#               must sit on a planwright/<spec>/task-<ids> branch.
#
#   reconcile   remove this helper's own parking segment for the unit's tasks
#               from `## Awaiting input`, commit and push that in one commit
#               when anything changed, and print the resulting head. No host
#               call.
#   evaluate    reconcile, then evaluate every precondition on the head and
#               write the precondition record (below) to --out, else stdout.
#               Never flips, comments, or parks. The merge helper (human-gates
#               REQ-D1.4, not yet built) is to hand the record to `flip` so
#               the bounded CI wait runs once.
#   flip        read ready_flip_policy (anything but unit-owner refuses, with
#               no host call), reconcile, evaluate, then write the PR record
#               comment and only then call `gh pr ready`. A failed
#               precondition, a failed record write, or a failed flip call
#               parks instead; the flip call's failure also appends a
#               follow-up comment, since the record already claims the flip.
#               --expect-head refuses when reconciling left another head (the
#               head the pre-ready-flip point ended on). --preconditions
#               takes an all-pass record `evaluate` wrote for this same head
#               and skips only the CI wait: every predicate still runs, the
#               rollup as one read with no polling, so a hand-in never stands
#               in for a check. The PR's head on the host is re-read before the
#               record and again before the flip call; a moved head parks.
#
# The unit-PR flip, as /execute-task runs it after its post-pr point when
# ready_flip_policy resolves unit-owner: `reconcile`; then the pre-ready-flip
# point on the head it printed, its commit status posted per
# doctrine/custom-steps.md (*The flip points*), a halted or failed step or a
# failed post ending the attempt with no flip; then
# `flip --expect-head <the head the point ended on>`; the handoff reports the
# exit below. Under human it is never called, and a standalone review-skill
# run never calls it.
#
# Preconditions, all on the pinned head:
#   awaiting-input    no live segment in the unit's Awaiting-input bullets,
#                     read from the checkout and from the fetched base ref; a
#                     segment opening with `pending ready-flip:` is this
#                     helper's park and is ignored, any other segment (or an
#                     indented continuation line) is live
#   review-converged  the newest unit run with a `convergence` completion
#                     record (scripts/step-record.sh) has no halted or failed
#                     step at `convergence` or `post-pr`, and its last
#                     completion there names a head every later commit of
#                     which touches only the Awaiting-input section of tasks.md
#   ci-rollup         the PR head's check rollup is a positive green (at least
#                     one success, nothing failing or pending) within
#                     ready_flip_ci_wait, the planwright/pre-ready-flip and
#                     planwright/pre-spec-ready-flip statuses excluded; a host
#                     read that fails is retried within the same bound
#   ready-guard       scripts/ready-guard.sh defers `gh pr ready <n>`: the
#                     shipped currency and mergeability floor, called directly
#                     because the flip runs below any hook
# The local predicates run first; when one fails the host ones are skipped,
# so a known park costs no CI wait.
#
# The park: one bullet per task, `- **Task <id>** — <segments>`, segments
# joined by `; `, this helper's own segment last and reading
# `pending ready-flip: <predicates> failed on <head12>`. A re-run replaces its
# own segment; a bullet the base carries for the task and the checkout lacks
# is composed in first, so the branch never conflicts with it. One commit
# touching only tasks.md, stamped with the Planwright-Task trailers, pushed.
# A park that cannot be committed restores the file and is named instead; one
# committed but not pushed is named as such, and the next run pushes it
# before it pins a head. Reconciling also re-reads the fetched base and drops
# a segment the base once carried and has since cleared (one a park composed
# in); a segment the unit wrote itself stays. A bullet with neither is never
# rewritten.
#
# The precondition record (evaluate's output, flip's --preconditions input):
#   head<TAB><sha>
#   pred<TAB><name><TAB>pass|fail|skip<TAB><evidence>
#
# Exit: 0 reconciled / all preconditions hold / flipped; 2 usage; 3 skipped
# cleanly (no PR, no gh, PR not open or already ready, policy not unit-owner);
# 4 not flipped, park written and pushed (for evaluate, which never parks: a
# precondition failed); 5 not flipped and no park pushed (the park could not
# be written or pushed, the PR head moved off the checked head, reconcile
# failed, an unreadable policy, an unsupported bundle, a wrong branch or a
# fork PR). A head someone else moved gets no park, since one could not be
# pushed on top of it; the handoff says to sync and re-run.
#
# Environment: PLANWRIGHT_READY_FLIP_POLL_SECONDS (default 15) is the CI poll
# interval; at 0 the wait makes PLANWRIGHT_READY_FLIP_MAX_POLLS reads
# (default 1) instead of deriving the count from the bound.
#
# No model in the decision path: every predicate is a comparison.
set -u
unset CDPATH
LC_ALL=C
export LC_ALL

SCRIPTS=$(cd "$(dirname "$0")" && pwd) || exit 2
# shellcheck source=scripts/echo-safety.sh
. "$SCRIPTS/echo-safety.sh"
# shellcheck source=scripts/spec-parse.sh
. "$SCRIPTS/spec-parse.sh"

readonly LEAD='pending ready-flip:'
readonly DASH='—'
readonly EXCLUDED_CONTEXTS='["planwright/pre-ready-flip","planwright/pre-spec-ready-flip"]'

say() { printf 'ready-flip: %s\n' "$*"; }
usage() {
  printf 'ready-flip: %s\n' "$1" >&2
  echo 'usage: ready-flip.sh reconcile|evaluate|flip --spec <dir> --task <id>... [options]' >&2
  exit 2
}

SCRATCH=$(mktemp -d "${TMPDIR:-/tmp}/ready-flip.XXXXXX") || exit 5
trap 'rm -rf "$SCRATCH"' EXIT

# --- arguments ---------------------------------------------------------------

MODE=${1:-}
case $MODE in
  reconcile | evaluate | flip) shift ;;
  *) usage 'the first argument must be reconcile, evaluate, or flip' ;;
esac
SPEC='' WT='' PR='' OUTF='' HANDIN='' EXPECT='' IDS=()
while [ "$#" -gt 0 ]; do
  case $1 in
    --spec | --task | --pr | --worktree | --out | --preconditions | --expect-head)
      [ "$#" -ge 2 ] || usage "$1 needs a value"
      case $1 in
        --spec) SPEC=$2 ;;
        --task) IDS[${#IDS[@]}]=$2 ;;
        --pr) PR=$2 ;;
        --worktree) WT=$2 ;;
        --out) OUTF=$2 ;;
        --preconditions) HANDIN=$2 ;;
        --expect-head) EXPECT=$2 ;;
      esac
      shift 2
      ;;
    *) usage "unknown argument '$(sanitize_printable "$1" '?')'" ;;
  esac
done
[ -n "$SPEC" ] || usage '--spec is required'
[ "${#IDS[@]}" -gt 0 ] || usage 'at least one --task is required'
[[ $SPEC =~ ^[A-Za-z0-9_][A-Za-z0-9._-]*(/[A-Za-z0-9_][A-Za-z0-9._-]*)*$ ]] \
  || usage '--spec must be a relative path inside the checkout'
case "/$SPEC/" in */../* | */./*) usage '--spec must not climb out of the checkout' ;; esac
for id in "${IDS[@]}"; do
  [[ $id =~ ^[0-9]+(\.[0-9]+)?$ ]] || usage "task id '$(sanitize_printable "$id" '?')' is malformed"
done
[ -z "$PR" ] || [[ $PR =~ ^[1-9][0-9]{0,9}$ ]] || usage '--pr must be a pull request number'
[ -z "$EXPECT" ] || [[ $EXPECT =~ ^[0-9a-f]{40}([0-9a-f]{24})?$ ]] || usage '--expect-head must be a full commit id'
[ "$MODE" = flip ] || [ -z "$EXPECT$HANDIN" ] || usage '--expect-head and --preconditions belong to flip'
[ "$MODE" = evaluate ] || [ -z "$OUTF" ] || usage '--out belongs to evaluate'
[ "$MODE" != reconcile ] || [ -z "$PR" ] || usage 'reconcile reads no PR'

refuse() { # <message> — not flipped, nothing parked
  say "not flipped: $1"
  exit 5
}

# File arguments name paths from the caller's directory, not the checkout's.
case $OUTF in '' | /*) ;; *) OUTF="$PWD/$OUTF" ;; esac
case $HANDIN in '' | /*) ;; *) HANDIN="$PWD/$HANDIN" ;; esac
[ -n "$WT" ] || WT=.
# A leading dash would read as cd's option (or `cd -`, the previous dir).
case $WT in -*) WT="./$WT" ;; esac
cd "$WT" 2>/dev/null || refuse 'the worktree cannot be entered'
# Git reports paths from the top level, so every path here is relative to it.
WT=$(git rev-parse --show-toplevel 2>/dev/null) || refuse 'not inside a git checkout'
cd "$WT" 2>/dev/null || refuse 'the worktree cannot be entered'
TASKS="$SPEC/tasks.md"
[ -f "$TASKS" ] && [ ! -L "$TASKS" ] || refuse "$(sanitize_printable "$TASKS") is not a regular file"
[ "$(spec_parse_header_value "$TASKS" Format-version 2>/dev/null)" = 2 ] \
  || refuse 'only a format-version 2 bundle can be parked by this helper; park the flip by hand'
SPEC_NAME=${SPEC##*/}
[[ $SPEC_NAME =~ ^[a-z0-9][a-z0-9-]*$ ]] || refuse 'the spec directory name is not a spec identifier'
BRANCH=$(git symbolic-ref --short -q HEAD 2>/dev/null) || BRANCH=''
[[ $BRANCH =~ ^planwright/[a-z0-9][a-z0-9-]*/task-[0-9]+(\.[0-9]+)?(-[0-9]+(\.[0-9]+)?)?$ ]] \
  || refuse 'the checkout is not on a planwright task branch'
REMOTE=$(git config "branch.$BRANCH.remote" 2>/dev/null) || REMOTE=origin
[[ $REMOTE =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || refuse 'the branch remote is not a plain remote name'

# --- the Awaiting-input section ------------------------------------------------

# The unit's bullets are found through the shared parked-map parse
# (scripts/spec-parse.sh), never a private one; these programs only split a
# bullet's payload into segments and edit the lines that parse located.
# shellcheck disable=SC2016
LIVE_AWK='
function trim(s) { sub(/^[ \t]+/, "", s); sub(/[ \t]+$/, "", s); return s }
function body_of(r) {
  r = trim(r)
  if (index(r, DASH) == 1) r = substr(r, length(DASH) + 1)
  else if (substr(r, 1, 1) == ":" || substr(r, 1, 1) == "-") r = substr(r, 2)
  return r
}
function live_of(r,   n, parts, i, s, out) {
  n = split(body_of(r), parts, ";")
  out = ""
  for (i = 1; i <= n; i++) {
    s = trim(parts[i])
    if (s == "" || index(s, LEAD) == 1) continue
    out = (out == "" ? s : out "; " s)
  }
  return out
}
function own_of(r,   n, parts, i) {
  n = split(body_of(r), parts, ";")
  for (i = 1; i <= n; i++) if (index(trim(parts[i]), LEAD) == 1) return 1
  return 0
}
BEGIN { n = split(IDS, u, " "); for (i = 1; i <= n; i++) UNIT[u[i]] = 1 }
NR == FNR {
  if ($1 == "ref" && $3 == "awaiting-input" && ($2 in UNIT)) { ID[$4] = $2; P[$4] = $5 }
  next
}
(FNR - 1) in ID { C[FNR - 1] = ($0 ~ /^[ \t]+[^ \t]/) }
END { for (l in ID) printf "%s\t%d\t%s\t%d\t%d\n", ID[l], l, live_of(P[l]), C[l] + 0, own_of(P[l]) }
'

# unit_refs <tasks file> — `<id>\t<line>\t<live segments>\t<continued 0|1>\t
# <own segment 0|1>` for each unit bullet under `## Awaiting input`. Live
# segments are the bullet's `; `-joined segments minus this helper's own; an
# indented line under the bullet (continued) counts as live too.
unit_refs() {
  local map
  map=$(spec_parse_parked_map "$1" 2>/dev/null) || return 1
  printf '%s\n' "$map" | awk -F '\t' -v IDS="${IDS[*]}" -v LEAD="$LEAD" -v DASH="$DASH" \
    "$LIVE_AWK" - "$1"
}

# shellcheck disable=SC2016
EDIT_AWK='
BEGIN {
  DROP = "\001drop"
  n = split(IDS, U, " ")
  while ((getline l < REFS) > 0) {
    split(l, f, "\t")
    AT[f[2]] = f[1]; LIVE[f[2]] = f[3]; CONT[f[2]] = f[4]; OWN[f[2]] = f[5]; HAS[f[1]] = 1
  }
  if (DROPS != "") while ((getline l < DROPS) > 0) {
    t = index(l, "\t")
    if (t > 0) { STALE[substr(l, 1, t - 1), substr(l, t + 1)] = 1; DROPANY[substr(l, 1, t - 1)] = 1 }
  }
  if (BASEREFS != "") while ((getline l < BASEREFS) > 0) {
    split(l, f, "\t")
    if (f[3] != "") BLIVE[f[1]] = f[3]
  }
  nb = 0
  if (SEG != "") for (i = 1; i <= n; i++) if (!(U[i] in HAS)) {
    p = (U[i] in BLIVE) ? BLIVE[U[i]] "; " SEG : SEG
    NEWB[++nb] = "- **Task " U[i] "** " DASH " " p
  }
  remaining = BULLETS + nb
}
{
  h = $0
  sub(/\r$/, "", h)
  if (H && !E && h ~ /^## /) E = FNR
  if (!H && h ~ /^## Awaiting input[ \t]*$/) H = FNR
  if ((FNR in AT) && (SEG != "" || OWN[FNR] || (FNR in DROPANY))) {
    changed = 1
    p = LIVE[FNR]
    if (FNR in DROPANY) {
      ns = split(p, segs, "; ")
      p = ""
      for (s = 1; s <= ns; s++) if (!((FNR, segs[s]) in STALE)) p = (p == "" ? segs[s] : p "; " segs[s])
    }
    if (SEG != "") p = (p == "" ? SEG : p "; " SEG)
    if (p == "" && !CONT[FNR]) { remaining--; out[FNR] = DROP; next }
    out[FNR] = "- **Task " AT[FNR] "**" (p == "" ? "" : " " DASH " " p)
    next
  }
  out[FNR] = $0
}
END {
  m = FNR
  if (!H) exit (nb > 0 ? 3 : 4)
  if (!changed && nb == 0) exit 4
  if (!E) E = m + 1
  content = 0; ph = 0; last = 0; first = 0
  for (k = H + 1; k < E; k++) {
    t = out[k]
    if (t == DROP) { if (!first) first = k; continue }
    if (t ~ /^\(none yet\)[ \t\r]*$/) { ph = 1; last = k; continue }
    if (t !~ /^[ \t\r]*$/) { content = 1; last = k }
  }
  needph = (remaining == 0 && !content && !ph)
  pre = 0
  if (!last) { last = (H + 1 < E && out[H + 1] ~ /^[ \t\r]*$/) ? H + 1 : H; pre = (last == H) }
  for (k = 1; k <= m; k++) {
    t = out[k]
    if (t == DROP) { if (k == first && needph) print "(none yet)" }
    else if (k > H && k < E && remaining > 0 && t ~ /^\(none yet\)[ \t\r]*$/) { }
    else print t
    if (k == last && nb > 0) {
      if (pre) print ""
      for (j = 1; j <= nb; j++) print NEWB[j]
    }
  }
}
'

# edit_tasks <file> <segment> [<base refs>] — the file with each unit
# bullet's own segment dropped and <segment>, when non-empty, appended; a unit
# task with no bullet gains one, composed from the base's live segments first
# so the branch never conflicts with the base's bullet. The section's
# `(none yet)` placeholder goes once it holds a bullet and comes back when it
# holds nothing. Exit 4: nothing to change, so the file is left byte-for-byte
# alone; 3: a bullet is due but the section is missing.
edit_tasks() {
  local refs="$SCRATCH/refs.edit" bullets
  unit_refs "$1" >"$refs" || return 1
  bullets=$(spec_parse_parked_map "$1" 2>/dev/null | awk -F '\t' '$3 == "awaiting-input" { n++ } END { print n + 0 }') \
    || return 1
  awk -v IDS="${IDS[*]}" -v SEG="$2" -v DASH="$DASH" -v BULLETS="$bullets" \
    -v REFS="$refs" -v BASEREFS="${3:-}" -v DROPS="${4:-}" "$EDIT_AWK" "$1"
}

# stale_base_segments <base ref> <out> — write `<line>\t<segment>` for each
# live segment of a unit bullet in the checkout that the base once carried
# (a park composed it in) and its current tip no longer does: someone cleared
# it there. A segment the unit wrote itself never appears in the base's
# history and stays. Nothing is written when the base cannot be read.
stale_base_segments() {
  local ref=$1 out=$2 id line live seg
  : >"$out"
  git show "$ref:$TASKS" >"$SCRATCH/stale.base" 2>/dev/null || : >"$SCRATCH/stale.base"
  unit_refs "$SCRATCH/stale.base" >"$SCRATCH/stale.baserefs" 2>/dev/null || return 0
  unit_refs "$TASKS" >"$SCRATCH/stale.local" || return 0
  while IFS=$'\t' read -r id line live _; do
    [ -n "$live" ] || continue
    while IFS= read -r seg; do
      [ -n "$seg" ] || continue
      # Still on the base for this task: not stale.
      awk -F '\t' -v id="$id" -v s="$seg" '$1 == id { n = split($3, p, "; "); for (i = 1; i <= n; i++) if (p[i] == s) f = 1 } END { exit !f }' \
        "$SCRATCH/stale.baserefs" && continue
      base_carried "$ref" "$id" "$seg" || continue
      printf '%s\t%s\n' "$line" "$seg" >>"$out"
    done <<<"${live//; /$'\n'}"
  done <"$SCRATCH/stale.local"
}

# base_carried <base ref> <id> <segment> — 0 when some commit of the base's
# tasks.md history (or its parent) carried <segment> in task <id>'s own
# Awaiting-input bullet. The text search only nominates commits: matching the
# text anywhere in the file would take a segment the unit wrote itself for
# one the base once held under another task, and drop it.
base_carried() {
  local c v
  for c in $(git log --format=%H -S"$3" "$1" -- "$TASKS" 2>/dev/null); do
    for v in "$c" "$c^"; do
      git show "$v:$TASKS" >"$SCRATCH/carried.base" 2>/dev/null || continue
      unit_refs "$SCRATCH/carried.base" 2>/dev/null \
        | awk -F '\t' -v id="$2" -v s="$3" '$1 == id { n = split($3, p, "; "); for (i = 1; i <= n; i++) if (p[i] == s) f = 1 } END { exit !f }' \
        && return 0
    done
  done
  return 1
}

# base_ref — the fetched remote-tracking ref of the PR base (or, with no PR
# read yet, the remote's default branch); empty when none can be fetched.
base_ref() {
  local b=$PR_BASE
  if [ -z "$b" ]; then
    b=$(git symbolic-ref -q --short "refs/remotes/$REMOTE/HEAD" 2>/dev/null) || b=''
    b=${b#"$REMOTE"/}
  fi
  [[ $b =~ ^[A-Za-z0-9_][A-Za-z0-9._/-]*$ ]] || return 0
  git fetch -q "$REMOTE" "+refs/heads/$b:refs/remotes/$REMOTE/$b" >/dev/null 2>&1
  git rev-parse --verify -q "refs/remotes/$REMOTE/$b" >/dev/null && printf 'refs/remotes/%s/%s' "$REMOTE" "$b"
}

# strip_section <file> — the file without the Awaiting-input section's body.
strip_section() {
  awk '
    insec && /^## / { insec = 0 }
    !insec { print }
    /^## Awaiting input[ \t\r]*$/ { insec = 1 }
  ' "$1"
}

tasks_clean() {
  git diff --quiet HEAD -- "$TASKS" 2>/dev/null && git diff --cached --quiet -- "$TASKS" 2>/dev/null
}

# commit_tasks <subject> — commit the edited tasks.md alone and push it. On a
# failed commit the edit is reverted, so the tree is left as it was.
COMMIT_ERR=''
commit_tasks() {
  local msg="$SCRATCH/msg" refs=() id
  for id in "${IDS[@]}"; do refs[${#refs[@]}]="$SPEC_NAME/$id"; done
  if ! printf '%s\n' "$1" | /bin/sh "$SCRIPTS/planwright-commit-trailers.sh" "${refs[@]}" >"$msg" 2>/dev/null; then
    git checkout -q -- "$TASKS" 2>/dev/null
    COMMIT_ERR='the commit trailers could not be stamped'
    return 1
  fi
  if ! git commit -q -F "$msg" -- "$TASKS" >/dev/null 2>&1; then
    git checkout -q -- "$TASKS" 2>/dev/null
    COMMIT_ERR='the commit failed'
    return 1
  fi
  push_branch || {
    COMMIT_ERR="the commit was made but the push failed, so $(git rev-parse --short HEAD) is local only"
    return 1
  }
}

push_branch() { git push -q "$REMOTE" "$BRANCH" >/dev/null 2>&1; }

# unpushed — 0 when the branch holds commits its remote-tracking ref lacks,
# such as a park whose push failed last run. A branch the remote does not
# hold at all is left alone; its PR could not exist.
unpushed() {
  git rev-parse --verify -q "refs/remotes/$REMOTE/$BRANCH" >/dev/null || return 1
  [ "$(git rev-list --count "refs/remotes/$REMOTE/$BRANCH..HEAD" 2>/dev/null)" != 0 ]
}

# write_tasks — put the edited file in place; a failed or short write restores
# the committed file, so a truncated tasks.md is never committed.
write_tasks() {
  if ! cat "$SCRATCH/tasks.new" >"$TASKS" 2>/dev/null || ! cmp -s "$SCRATCH/tasks.new" "$TASKS"; then
    git checkout -q -- "$TASKS" 2>/dev/null
    COMMIT_ERR="$TASKS could not be written"
    return 1
  fi
}

unit_label() {
  if [ "${#IDS[@]}" = 1 ]; then printf 'task %s' "${IDS[0]}"; else printf 'tasks %s' "${IDS[*]}"; fi
}

# reconcile — drop this helper's own segment and push before any head is
# pinned. 0 when the section is clean of it and the branch is pushed.
reconcile() {
  local rc
  tasks_clean || {
    COMMIT_ERR="$TASKS has uncommitted changes"
    return 1
  }
  local ref drops=''
  ref=$(base_ref)
  if [ -n "$ref" ]; then
    drops="$SCRATCH/drops"
    stale_base_segments "$ref" "$drops"
  fi
  edit_tasks "$TASKS" '' '' "$drops" >"$SCRATCH/tasks.new"
  rc=$?
  case $rc in
    0)
      write_tasks || return 1
      commit_tasks "chore($SPEC_NAME): reconcile the Awaiting-input entry of $(unit_label)" || return 1
      ;;
    4) ;;
    *)
      COMMIT_ERR='tasks.md could not be parsed'
      return 1
      ;;
  esac
  # Refreshed by an explicit refspec, so a narrowed fetch config still leaves
  # a tracking ref to compare against; a failed fetch keeps the old one.
  git fetch -q "$REMOTE" "+refs/heads/$BRANCH:refs/remotes/$REMOTE/$BRANCH" >/dev/null 2>&1
  if unpushed && ! push_branch; then
    COMMIT_ERR='the branch has commits its remote lacks and the push failed'
    return 1
  fi
}

# --- the host ------------------------------------------------------------------

duration_seconds() { # <value> — a resolver-validated duration, rounded up
  awk -v v="$1" 'BEGIN {
    u = v; sub(/^[0-9.]+/, "", u); x = substr(v, 1, length(v) - length(u)) + 0
    m = (u == "ms") ? 0.001 : (u == "m") ? 60 : (u == "h") ? 3600 : (u == "d") ? 86400 : 1
    s = x * m; c = int(s); if (c < s) c++; if (c < 1) c = 1; print c
  }'
}

POLL=${PLANWRIGHT_READY_FLIP_POLL_SECONDS:-15}
[[ $POLL =~ ^[0-9]{1,4}$ ]] || POLL=15
ATTEMPTS=1
WAIT_TEXT=''
WAIT_SECS=0
read_wait() {
  local v s
  v=$(/bin/sh "$SCRIPTS/resolve-policy-knob.sh" ready_flip_ci_wait 2>/dev/null) || return 1
  WAIT_TEXT=$v
  s=$(duration_seconds "$v")
  WAIT_SECS=$s
  if [ "$POLL" = 0 ]; then
    ATTEMPTS=${PLANWRIGHT_READY_FLIP_MAX_POLLS:-1}
    [[ $ATTEMPTS =~ ^[1-9][0-9]{0,3}$ ]] || ATTEMPTS=1
  else
    # A read at 0s and then one per interval up to and including the deadline.
    ATTEMPTS=$((s / POLL + 1))
  fi
}

nap() { [ "$POLL" = 0 ] || sleep "$POLL"; }

PR_BASE=''
BASE_BULLETS=''
# The lookup retries a few times rather than for the whole CI wait: an
# unauthenticated or unauthorized gh fails the same way every time.
readonly LOOKUP_ATTEMPTS=3
# lookup_pr — 0 with PR and PR_BASE set; 3 a clean skip (message printed);
# 1 a host read that kept failing.
lookup_pr() {
  local i=0 raw err rc tries=$LOOKUP_ATTEMPTS
  [ "$ATTEMPTS" -ge "$tries" ] || tries=$ATTEMPTS
  while [ "$i" -lt "$tries" ]; do
    i=$((i + 1))
    raw=$(gh pr view "${PR:-$BRANCH}" --json number,isDraft,state,baseRefName,headRefName,isCrossRepository 2>"$SCRATCH/err")
    rc=$?
    err=$(cat "$SCRATCH/err")
    if [ "$rc" = 0 ] && [ -n "$raw" ]; then
      break
    fi
    case $err in
      *'no pull requests found'* | *'Could not resolve to a PullRequest'* | *'no open pull requests'*)
        say "skipped: no pull request for $BRANCH, so there is nothing to flip"
        return 3
        ;;
    esac
    raw=''
    [ "$i" -ge "$tries" ] || nap
  done
  [ -n "$raw" ] || return 1
  local num draft state base head fork
  num=$(printf '%s' "$raw" | jq -r '.number // empty' 2>/dev/null)
  draft=$(printf '%s' "$raw" | jq -r '.isDraft' 2>/dev/null)
  state=$(printf '%s' "$raw" | jq -r '.state // empty' 2>/dev/null)
  base=$(printf '%s' "$raw" | jq -r '.baseRefName // empty' 2>/dev/null)
  head=$(printf '%s' "$raw" | jq -r '.headRefName // empty' 2>/dev/null)
  fork=$(printf '%s' "$raw" | jq -r '.isCrossRepository' 2>/dev/null)
  [[ $num =~ ^[1-9][0-9]{0,9}$ ]] || return 1
  [ "$head" = "$BRANCH" ] || refuse "PR #$num is not this checkout's branch"
  [ "$fork" = false ] || refuse "PR #$num is not from this repository's own branch"
  # The host names the base; it reaches git as an argument, so no option shape.
  [[ $base =~ ^[A-Za-z0-9_][A-Za-z0-9._/-]*$ ]] || return 1
  git check-ref-format --branch "$base" >/dev/null 2>&1 || return 1
  PR=$num
  PR_BASE=$base
  if [ "$state" != OPEN ]; then
    say "skipped: PR #$PR is not open"
    return 3
  fi
  if [ "$draft" != true ]; then
    say "skipped: PR #$PR is already ready for review"
    return 3
  fi
}

# --- the preconditions ---------------------------------------------------------

declare -a P_NAME=() P_RES=() P_EVD=()
set_pred() { # <name> <pass|fail|skip> <evidence>
  local i=0
  while [ "$i" -lt "${#P_NAME[@]}" ]; do
    if [ "${P_NAME[$i]}" = "$1" ]; then
      P_RES[i]=$2
      P_EVD[i]=$3
      return
    fi
    i=$((i + 1))
  done
  P_NAME[i]=$1
  P_RES[i]=$2
  P_EVD[i]=$3
}
failed_preds() {
  local i=0 out=''
  while [ "$i" -lt "${#P_NAME[@]}" ]; do
    [ "${P_RES[$i]}" != fail ] || out="${out:+$out, }${P_NAME[$i]}"
    i=$((i + 1))
  done
  printf '%s' "$out"
}

pred_awaiting() {
  local where='' b
  unit_refs "$TASKS" >"$SCRATCH/live.local" || {
    set_pred awaiting-input fail 'the checkout tasks.md could not be read'
    return
  }
  BASE_BULLETS="$SCRATCH/live.base"
  : >"$BASE_BULLETS"
  # An explicit refspec, so a single-branch clone's narrowed fetch config
  # cannot leave a stale base ref behind.
  if ! git fetch -q "$REMOTE" "+refs/heads/$PR_BASE:refs/remotes/$REMOTE/$PR_BASE" >/dev/null 2>&1 \
    || ! git rev-parse --verify -q "refs/remotes/$REMOTE/$PR_BASE" >/dev/null; then
    set_pred awaiting-input fail "the base ref $REMOTE/$PR_BASE could not be fetched"
    return
  fi
  if git cat-file -e "refs/remotes/$REMOTE/$PR_BASE:$TASKS" 2>/dev/null; then
    git show "refs/remotes/$REMOTE/$PR_BASE:$TASKS" >"$SCRATCH/base.tasks" 2>/dev/null || {
      set_pred awaiting-input fail "tasks.md on $REMOTE/$PR_BASE could not be read"
      return
    }
    unit_refs "$SCRATCH/base.tasks" >"$BASE_BULLETS" || {
      : >"$BASE_BULLETS"
      set_pred awaiting-input fail "tasks.md on $REMOTE/$PR_BASE could not be parsed"
      return
    }
  fi
  for b in local base; do
    if awk -F '\t' '$3 != "" || $4 == 1 { found = 1 } END { exit !found }' "$SCRATCH/live.$b"; then
      where="${where:+$where and }$([ "$b" = local ] && echo 'the checkout' || echo "$REMOTE/$PR_BASE")"
    fi
  done
  if [ -n "$where" ]; then
    set_pred awaiting-input fail "a live Awaiting-input entry for $(unit_label) in $where"
  else
    set_pred awaiting-input pass "no live entry for $(unit_label) in the checkout or $REMOTE/$PR_BASE"
  fi
}

# park_only <commit> — 0 when the commit changes only the Awaiting-input
# section of this unit's tasks.md.
park_only() {
  local c=$1 parents files
  parents=$(git rev-list --parents -n 1 "$c" 2>/dev/null | wc -w | tr -d ' ')
  [ "$parents" = 2 ] || return 1
  files=$(git diff-tree --no-commit-id --name-only -r "$c" 2>/dev/null)
  [ "$files" = "$TASKS" ] || return 1
  git show "$c^:$TASKS" >"$SCRATCH/pa" 2>/dev/null || return 1
  git show "$c:$TASKS" >"$SCRATCH/pb" 2>/dev/null || return 1
  [ "$(strip_section "$SCRATCH/pa")" = "$(strip_section "$SCRATCH/pb")" ]
}

pred_review() {
  local rec rh bad run c n=0
  if ! /bin/sh "$SCRIPTS/step-record.sh" --worktree "$WT" list >"$SCRATCH/records" 2>/dev/null; then
    set_pred review-converged fail 'the step records could not be read'
    return
  fi
  rec=$(awk -F '\t' '
    function close_rec() {
      if (type != "") { N++; T[N] = type; R[N] = run; Q[N] = seq + 0; P[N] = point; H[N] = head; O[N] = outcome }
      type = run = seq = point = head = outcome = ""
    }
    /^record\t/ { close_rec(); next }
    /^$/ { close_rec(); next }
    $1 == "type" { type = $2 }
    $1 == "run" { run = $2 }
    $1 == "seq" { seq = $2 }
    $1 == "point" { point = $2 }
    $1 == "head" { head = $2 }
    $1 == "outcome" { outcome = $2 }
    END {
      close_rec()
      best = ""
      for (i = 1; i <= N; i++) if (T[i] == "completion" && P[i] == "convergence" && R[i] > best) best = R[i]
      if (best == "") exit
      bad = 0; hs = -1; hh = ""
      for (i = 1; i <= N; i++) {
        if (R[i] != best || (P[i] != "convergence" && P[i] != "post-pr")) continue
        if (T[i] == "step" && (O[i] == "halted" || O[i] == "failed")) bad = 1
        if (T[i] == "completion" && Q[i] > hs) { hs = Q[i]; hh = H[i] }
      }
      printf "%s\t%s\t%d\n", best, hh, bad
    }
  ' "$SCRATCH/records")
  if [ -z "$rec" ]; then
    set_pred review-converged fail 'no convergence record in this worktree names a reviewed head'
    return
  fi
  run=${rec%%$'\t'*}
  rh=${rec#*$'\t'}
  bad=${rh#*$'\t'}
  rh=${rh%%$'\t'*}
  if ! [[ $run =~ ^[0-9]{6}$ ]]; then
    set_pred review-converged fail 'the newest review record names no valid run'
    return
  fi
  if [ "$bad" != 0 ]; then
    set_pred review-converged fail "a review step halted or failed in run $run"
    return
  fi
  if ! [[ $rh =~ ^[0-9a-f]{40}([0-9a-f]{24})?$ ]] \
    || ! git merge-base --is-ancestor "$rh" "$HEAD_SHA" 2>/dev/null; then
    set_pred review-converged fail "the reviewed head of run $run is not in this branch's history"
    return
  fi
  for c in $(git rev-list "$rh..$HEAD_SHA" 2>/dev/null); do
    park_only "$c" || {
      set_pred review-converged fail "commits since the reviewed head ${rh:0:12} change more than the Awaiting-input section"
      return
    }
    n=$((n + 1))
  done
  set_pred review-converged pass "run $run converged on ${rh:0:12}; $n park-only commit(s) since"
}

# shellcheck disable=SC2016
ROLLUP_JQ='
  [ (.statusCheckRollup // [])[]
    | select(((.context // .name // "") as $n | any($ex[]; . == $n)) | not)
    | if .__typename == "StatusContext" then
        (if .state == "SUCCESS" then "green" elif (.state == "PENDING" or .state == "EXPECTED") then "pending" else "failing" end)
      else
        (if .status != "COMPLETED" then "pending" elif .conclusion == "SUCCESS" then "green"
         elif (.conclusion == "NEUTRAL" or .conclusion == "SKIPPED") then "neutral" else "failing" end)
      end ] as $v
  | if any($v[]; . == "failing") then "failing"
    elif any($v[]; . == "pending") then "pending"
    elif any($v[]; . == "green") then "green \([$v[] | select(. == "green")] | length)"
    else "none" end'

# Set when the host keeps reporting another head: someone else moved the
# branch, so a park could not be pushed on top of it and none is attempted.
HEAD_MOVED=0
pred_ci() {
  local i=0 raw oid verdict last='the check rollup could not be read' deadline=$((SECONDS + WAIT_SECS))
  # The read count bounds the wait, and so does the clock: no nap starts once
  # the deadline has passed, so a head re-read inside an attempt, which naps
  # too, overruns the bound by at most one interval.
  while [ "$i" -lt "$ATTEMPTS" ]; do
    i=$((i + 1))
    raw=$(gh pr view "$PR" --json headRefOid,statusCheckRollup 2>/dev/null) || raw=''
    if [ -n "$raw" ] && oid=$(printf '%s' "$raw" | jq -r '.headRefOid // empty' 2>/dev/null) && [ -n "$oid" ]; then
      # Another head goes through the lag-tolerant re-read; one that persists
      # is a branch someone else moved.
      if [ "$oid" != "$HEAD_SHA" ]; then
        pr_head_pinned
        case $? in
          0) raw=$(gh pr view "$PR" --json headRefOid,statusCheckRollup 2>/dev/null) || raw='' ;;
          1)
            HEAD_MOVED=1
            set_pred ci-rollup fail "the PR head is $(printf '%s' "${oid:0:12}" | tr -cd '0-9a-f'), not the pinned head ${HEAD_SHA:0:12}"
            return
            ;;
          *) ;; # unreadable: the stale read stands and the attempt counts as not settled
        esac
        oid=$(printf '%s' "$raw" | jq -r '.headRefOid // empty' 2>/dev/null) || oid=''
      fi
      if [ "$oid" != "$HEAD_SHA" ]; then
        verdict=moved
        last="the PR head did not settle on the pinned head ${HEAD_SHA:0:12}"
      else
        verdict=$(printf '%s' "$raw" | jq -r --argjson ex "$EXCLUDED_CONTEXTS" "$ROLLUP_JQ" 2>/dev/null) || verdict=''
      fi
      case $verdict in
        green\ *)
          set_pred ci-rollup pass "${verdict#green } check(s) green on ${HEAD_SHA:0:12}"
          return
          ;;
        failing)
          set_pred ci-rollup fail "a check failed on ${HEAD_SHA:0:12}"
          return
          ;;
        moved) ;;
        pending) last='checks still pending' ;;
        none) last='no check has reported a success' ;;
        *) last='the check rollup could not be read' ;;
      esac
    fi
    [ "$i" -lt "$ATTEMPTS" ] || break
    [ "$POLL" = 0 ] || [ "$SECONDS" -lt "$deadline" ] || break
    nap
  done
  set_pred ci-rollup fail "$last at the end of the ${WAIT_TEXT:-bounded} wait"
}

GUARD_REASON=''
pred_guard() {
  local payload out
  payload=$(jq -nc --arg c "gh pr ready $PR" --arg w "$WT" \
    '{tool_name:"Bash", tool_input:{command:$c}, cwd:$w}' 2>/dev/null) || payload=''
  if [ -z "$payload" ] || ! out=$(printf '%s' "$payload" | /bin/bash "$SCRIPTS/ready-guard.sh" bash 2>/dev/null); then
    set_pred ready-guard fail 'the ready-guard could not run'
    return
  fi
  if [ -z "$(printf '%s' "$out" | tr -d '[:space:]')" ]; then
    set_pred ready-guard pass 'currency and mergeability check passed'
  else
    GUARD_REASON=$(printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecisionReason // ""' 2>/dev/null)
    set_pred ready-guard fail 'the currency and mergeability check refused'
  fi
}

# read_handin — 0 when the handed-in record is for HEAD_SHA and passes all.
read_handin() {
  [ -f "$HANDIN" ] && [ ! -L "$HANDIN" ] || return 1
  awk -F '\t' -v h="$HEAD_SHA" '
    $1 == "head" { head = ($2 == h) ; seen = 1; next }
    $1 == "pred" && NF >= 3 { if ($3 != "pass") bad = 1; n[$2] = 1; next }
    { bad = 1 }
    END {
      if (!seen || !head || bad) exit 1
      if (!("ci-rollup" in n) || !("review-converged" in n) || !("ready-guard" in n) || !("awaiting-input" in n)) exit 1
    }
  ' "$HANDIN" || return 1
}

# A valid hand-in skips only the CI *wait*: every predicate is still checked
# on the current head, the rollup by one read with no polling, so a forged or
# stale hand-in can never stand in for host-side evidence.
evaluate_all() {
  local reuse=0 attempts=$ATTEMPTS poll=$POLL
  if [ -n "$HANDIN" ]; then
    if read_handin; then
      reuse=1
    else
      say "the handed-in preconditions are not for head ${HEAD_SHA:0:12}; evaluating afresh"
    fi
  fi
  pred_awaiting
  pred_review
  if [ -n "$(failed_preds)" ]; then
    set_pred ci-rollup skip 'not read: a local precondition failed'
    set_pred ready-guard skip 'not run: a local precondition failed'
    return
  fi
  if [ "$reuse" = 1 ]; then
    ATTEMPTS=1 POLL=0
    pred_ci
    ATTEMPTS=$attempts POLL=$poll
  else
    pred_ci
  fi
  if [ -n "$(failed_preds)" ]; then
    set_pred ready-guard skip 'not run: the check rollup is not green'
    return
  fi
  pred_guard
}

# park <predicates> — write the parking segment; 0 written, 1 not.
park() {
  local seg="$LEAD $1 failed on ${HEAD_SHA:0:12}"
  tasks_clean || {
    COMMIT_ERR="$TASKS has uncommitted changes"
    return 1
  }
  edit_tasks "$TASKS" "$seg" "${BASE_BULLETS:-}" >"$SCRATCH/tasks.new"
  case $? in
    0) ;;
    3)
      COMMIT_ERR="$TASKS has no ## Awaiting input section"
      return 1
      ;;
    4) return 0 ;;
    *)
      COMMIT_ERR='tasks.md could not be parsed'
      return 1
      ;;
  esac
  write_tasks || return 1
  commit_tasks "chore($SPEC_NAME): park the ready-flip of $(unit_label)"
}

# pr_head_pinned — 0 when the host reports the pinned head for the PR, 1 when
# every read reports another (a host lagging a push settles within a few
# reads), 2 when none could be read.
pr_head_pinned() {
  local i=0 oid seen=0
  while [ "$i" -lt "$LOOKUP_ATTEMPTS" ]; do
    i=$((i + 1))
    oid=$(gh pr view "$PR" --json headRefOid --jq .headRefOid 2>/dev/null) || oid=''
    if [ -n "$oid" ]; then
      [ "$oid" != "$HEAD_SHA" ] || return 0
      seen=1
    fi
    [ "$i" -ge "$LOOKUP_ATTEMPTS" ] || nap
  done
  [ "$seen" = 1 ] && return 1
  return 2
}

# not_pinned_text <pr_head_pinned status> — the handoff and comment wording.
not_pinned_text() {
  if [ "$1" = 1 ]; then echo 'the PR head moved off the checked head'; else echo 'the PR head could not be re-read'; fi
}

park_and_exit() { # <predicates>
  if [ "$HEAD_MOVED" = 1 ]; then
    say "not flipped: $1 failed on ${HEAD_SHA:0:12} because someone else moved the branch; no park was written, since it could not be pushed on top. Sync the branch and re-run."
    exit 5
  fi
  if park "$1"; then
    say "not flipped: $1 failed on ${HEAD_SHA:0:12}; parked under ## Awaiting input in $TASKS"
    [ -z "$GUARD_REASON" ] || say "ready-guard: $(sanitize_printable "$GUARD_REASON")"
    exit 4
  fi
  say "not flipped: $1 failed on ${HEAD_SHA:0:12}, and the park was not written: $COMMIT_ERR"
  [ -z "$GUARD_REASON" ] || say "ready-guard: $(sanitize_printable "$GUARD_REASON")"
  exit 5
}

print_record() {
  local i=0
  printf 'head\t%s\n' "$HEAD_SHA"
  while [ "$i" -lt "${#P_NAME[@]}" ]; do
    printf 'pred\t%s\t%s\t%s\n' "${P_NAME[$i]}" "${P_RES[$i]}" "${P_EVD[$i]}"
    i=$((i + 1))
  done
}

# The backticks below are markdown for the PR comment, never expansions.
# shellcheck disable=SC2016
record_body() { # <policy>
  local i=0
  printf '<!-- planwright:ready-flip -->\n'
  printf '**Ready-flip record.** `ready_flip_policy` is `%s`; flipping head `%s` once every precondition below held on it.\n\n' "$1" "$HEAD_SHA"
  printf '| Precondition | Result | Evidence |\n| --- | --- | --- |\n'
  while [ "$i" -lt "${#P_NAME[@]}" ]; do
    printf '| %s | %s | %s |\n' "${P_NAME[$i]}" "${P_RES[$i]}" "$(printf '%s' "${P_EVD[$i]}" | tr '|' '/')"
    i=$((i + 1))
  done
}

# --- the modes -----------------------------------------------------------------

if [ "$MODE" = reconcile ]; then
  reconcile || refuse "the Awaiting-input section could not be reconciled: $COMMIT_ERR"
  say "reconciled; head $(git rev-parse HEAD)"
  exit 0
fi

POLICY=''
if [ "$MODE" = flip ]; then
  POLICY=$(/bin/sh "$SCRIPTS/resolve-policy-knob.sh" ready_flip_policy 2>/dev/null) \
    || refuse 'ready_flip_policy could not be resolved, so the flip is refused'
  if [ "$POLICY" != unit-owner ]; then
    say "skipped: ready_flip_policy is $(sanitize_printable "$POLICY" '?'), so a person marks this PR ready"
    exit 3
  fi
fi

if ! command -v gh >/dev/null 2>&1; then
  say 'skipped: gh is not installed, so no pull request can be read'
  exit 3
fi
command -v jq >/dev/null 2>&1 || refuse 'jq is required to read the host answers'
read_wait || refuse 'ready_flip_ci_wait could not be resolved'

lookup_pr
case $? in
  0) ;;
  3) exit 3 ;;
  *)
    HEAD_SHA=$(git rev-parse HEAD)
    [ "$MODE" = flip ] || refuse 'the pull request could not be read'
    park_and_exit pr-lookup
    ;;
esac

reconcile || refuse "the Awaiting-input section could not be reconciled: $COMMIT_ERR"
HEAD_SHA=$(git rev-parse HEAD)
if [ -n "$EXPECT" ] && [ "$EXPECT" != "$HEAD_SHA" ]; then
  refuse "reconciling left head ${HEAD_SHA:0:12}, not the expected ${EXPECT:0:12}"
fi

evaluate_all
FAILED=$(failed_preds)

if [ "$MODE" = evaluate ]; then
  if [ -n "$OUTF" ]; then
    print_record >"$OUTF" || refuse 'the precondition record could not be written'
  else
    print_record
  fi
  [ -z "$FAILED" ] || exit 4
  exit 0
fi

[ -z "$FAILED" ] || park_and_exit "$FAILED"

pr_head_pinned
pin=$?
if [ "$pin" != 0 ]; then
  [ "$pin" != 1 ] || HEAD_MOVED=1
  park_and_exit head-check
fi
record_body "$POLICY" >"$SCRATCH/record.md"
gh pr comment "$PR" --body-file "$SCRATCH/record.md" >/dev/null 2>&1 || park_and_exit record-write
pr_head_pinned
pin=$?
if [ "$pin" = 0 ]; then
  gh pr ready "$PR" >/dev/null 2>&1
  rc=$?
  why="gh exit $rc"
else
  rc=1
  why=$(not_pinned_text "$pin")
  [ "$pin" != 1 ] || HEAD_MOVED=1
fi
if [ "$rc" = 0 ]; then
  say "flipped PR #$PR ready at $HEAD_SHA"
  exit 0
fi
# The record already claims the flip, so the follow-up says what became of it.
outcome=5
if [ "$HEAD_MOVED" = 1 ]; then
  parked='no park was written, since the branch moved under it; sync the branch and re-run'
elif park flip-call; then
  outcome=4
  # shellcheck disable=SC2016 # markdown backticks for the comment
  parked='the flip is parked under `## Awaiting input`'
else
  parked="the park could not be written either ($COMMIT_ERR)"
fi
printf '**Ready-flip follow-up.** The flip was not made after the record above (%s), so PR #%s stays draft; %s.\n' \
  "$why" "$PR" "$parked" >"$SCRATCH/follow.md"
gh pr comment "$PR" --body-file "$SCRATCH/follow.md" >/dev/null 2>&1 \
  || say 'the follow-up comment could not be written either'
say "not flipped after the record ($why); $parked"
exit "$outcome"
