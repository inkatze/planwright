#!/bin/bash
# merge-admitted.sh — merge a unit PR its policy class admits, under
# `merge_policy: policy-class`: the one sanctioned agent merge path
# (doctrine/human-gates.md; the human-gates spec's REQ-D1.4, REQ-D1.5).
#
# Usage:
#   merge-admitted.sh --spec <dir> --task <id>... [--pr <n>] [--worktree <dir>]
#       [--expect-head <sha>]
#
# Arguments as scripts/ready-flip.sh takes them; --expect-head refuses to
# flip a draft whose evaluated head is not <sha>. Run in the worker tier by the
# skill owning the unit branch (/execute-task), as its terminal step; the
# policy guard refuses it to the tower and under any other merge_policy value.
#
# As /execute-task runs it, when merge_policy resolves policy-class: after the
# unit-owner flip sequence (scripts/ready-flip.sh) exits 0 or 3, or straight
# away under ready_flip_policy: human. While the PR is still a draft, first
# `scripts/ready-flip.sh reconcile` and the pre-ready-flip point on the head
# it printed (its commit status posted as for the unit-owner flip; a halted or
# failed step ends the attempt with no flip or merge), then this helper with
# `--expect-head <that head>`, since its flip is an agent-issued flip too. The
# handoff reports the exit below.
#
# The sequence:
#   1. Re-resolve merge_policy here: anything but policy-class skips with no
#      host call, and a read that fails refuses.
#   2. scripts/merge-class.sh evaluate: the class predicates and the flip
#      preconditions, once. A PR outside the class gets a PR comment naming
#      each failed predicate and the human act that approves it under
#      on-approval (merge-class.sh identity), and nothing else.
#   3. An admitted PR still in draft is flipped through
#      `scripts/ready-flip.sh flip --for-merge`, the class record handed in so
#      the CI wait runs once, whatever ready_flip_policy says: the class holds
#      every flip precondition and the flip approves nothing.
#      A flip that does not go through gets a PR comment saying so; one that
#      went through leaves the PR ready even if a later step stops the merge,
#      which approves nothing.
#   4. The merge record comment: the policy value, the head, the base, the
#      method, and each predicate's evidence, every evidence cell a code span
#      so host text stays inert. A record that cannot be written ends the run
#      with no merge.
#   5. Immediately before the merge call, merge_policy, the PR head, the
#      Awaiting-input predicate, and the base ref's OID are read again; any of
#      them changed since evaluation refuses the merge with a PR comment
#      saying which.
#   6. `gh pr merge --<method> --match-head-commit <head>`, so the host
#      refuses a head that moves after the re-read too. The branch is never
#      deleted. The outcome is read back from the host: a merge a queue or
#      auto-merge holds is reported as not merged yet. A failed call whose
#      merge landed anyway is reported merged (or, merged at another head,
#      corrected on the PR as not this run's merge); otherwise it gets a follow-up
#      comment, since the record already claims the merge, and parks the unit
#      under `## Awaiting input` (ready-flip.sh park), unless the head moved,
#      where a park could not be pushed on top.
#
# Exit: 0 merged, or handed to the host's queue; 2 usage; 3 skipped
# (merge_policy not policy-class, no gh, no open PR); 4 not merged, and the PR
# says why (a fall-through, a changed state, a failed flip, a failed merge
# call); 5 not merged and the PR could not be told (an unreadable policy, a
# failed record or comment write, an evaluation that refused).
#
# No model in the decision path: every step is a comparison.
set -u
unset CDPATH
LC_ALL=C
export LC_ALL

SCRIPTS=$(cd "$(dirname "$0")" && pwd) || exit 2
if [ ! -f "$SCRIPTS/echo-safety.sh" ] || [ ! -r "$SCRIPTS/echo-safety.sh" ]; then
  printf '%s\n' "merge-admitted.sh: echo-safety.sh is missing or unreadable (broken install)" >&2
  exit 2
fi
# shellcheck source=scripts/echo-safety.sh
. "$SCRIPTS/echo-safety.sh" || exit 2

say() { printf 'merge-admitted: %s\n' "$*"; }
usage() {
  printf 'merge-admitted: %s\n' "$1" >&2
  echo 'usage: merge-admitted.sh --spec <dir> --task <id>... [--pr <n>] [--worktree <dir>] [--expect-head <sha>]' >&2
  exit 2
}
refuse() {
  say "not merged: $1"
  exit 5
}

SCRATCH=$(mktemp -d "${TMPDIR:-/tmp}/merge-admitted.XXXXXX") || exit 5
trap 'rm -rf "$SCRATCH"' EXIT

SPEC='' WT='' PR='' EXPECT='' IDS=()
while [ "$#" -gt 0 ]; do
  case $1 in
    --spec | --task | --pr | --worktree | --expect-head)
      [ "$#" -ge 2 ] || usage "$1 needs a value"
      case $1 in
        --spec) SPEC=$2 ;;
        --task) IDS[${#IDS[@]}]=$2 ;;
        --pr) PR=$2 ;;
        --worktree) WT=$2 ;;
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
UNIT=()
for id in "${IDS[@]}"; do
  [[ $id =~ ^[0-9]+(\.[0-9]+)?$ ]] || usage "task id '$(sanitize_printable "$id" '?')' is malformed"
  UNIT+=(--task "$id")
done
[ -z "$PR" ] || [[ $PR =~ ^[1-9][0-9]{0,9}$ ]] || usage '--pr must be a pull request number'
[ -z "$EXPECT" ] || [[ $EXPECT =~ ^[0-9a-f]{40}([0-9a-f]{24})?$ ]] || usage '--expect-head must be a full commit id'
[ -n "$WT" ] || WT=.
case $WT in -*) WT="./$WT" ;; esac
cd "$WT" 2>/dev/null || refuse 'the worktree cannot be entered'
WT=$(git rev-parse --show-toplevel 2>/dev/null) || refuse 'not inside a git checkout'
cd "$WT" 2>/dev/null || refuse 'the worktree cannot be entered'

# 1. The policy, re-read here whatever the caller resolved.
POLICY=$(/bin/sh "$SCRIPTS/resolve-policy-knob.sh" merge_policy 2>/dev/null) \
  || refuse 'merge_policy could not be resolved, so the merge is refused'
if [ "$POLICY" != policy-class ]; then
  say "skipped: merge_policy is $(sanitize_printable "$POLICY" '?'), so the operator's approval act merges this PR"
  exit 3
fi
if ! command -v gh >/dev/null 2>&1; then
  say 'skipped: gh is not installed, so no pull request can be read'
  exit 3
fi
command -v jq >/dev/null 2>&1 || refuse 'jq is required to read the host answers'

comment() { # <body file> — 0 when the comment was written
  gh pr comment "$PR" --body-file "$1" >/dev/null 2>&1
}

# A table row per record line; each evidence cell a code span, its own
# backticks and pipes replaced, so a path or branch name cannot mention a
# person, link, or open an HTML comment.
# shellcheck disable=SC2016 # awk program; the backticks are markdown
ROW_AWK='function cell(e) { gsub(/\|/, "/", e); gsub(/`/, "\047", e); return "`" e "`" }'

hex() { printf '%s' "$1" | tr -cd '0-9a-f'; }

# 2. The class.
REC="$SCRATCH/record"
/bin/bash "$SCRIPTS/merge-class.sh" evaluate --spec "$SPEC" "${UNIT[@]}" ${PR:+--pr "$PR"} \
  --out "$REC" >"$SCRATCH/class.out" 2>&1
rc=$?
why=$(sanitize_printable "$(tail -1 "$SCRATCH/class.out" 2>/dev/null)" '?')
case $rc in
  0 | 4) ;;
  3)
    say "skipped: ${why#merge-class: }"
    exit 3
    ;;
  *) refuse "the class could not be evaluated (${why#merge-class: })" ;;
esac
field() { awk -F '\t' -v k="$1" -v n="$2" '$1 == k { print $n; exit }' "$REC"; }
HEAD_SHA=$(field head 2) BASE=$(field base 2) BASE_OID=$(field base 3) PR=$(field pr 2) METHOD=$(field strategy 2)
[[ $HEAD_SHA =~ ^[0-9a-f]{40}([0-9a-f]{24})?$ ]] && [[ $BASE_OID =~ ^[0-9a-f]{40}([0-9a-f]{24})?$ ]] \
  && [[ $PR =~ ^[1-9][0-9]{0,9}$ ]] && [[ $BASE =~ ^[A-Za-z0-9_][A-Za-z0-9._/-]*$ ]] \
  || refuse 'the class record is malformed'

# The backticks below are markdown for the PR comments, never expansions.
# shellcheck disable=SC2016
if [ "$rc" = 4 ]; then
  acts=$(/bin/bash "$SCRIPTS/merge-class.sh" identity --pr "$PR" 2>/dev/null)
  act='a person enables auto-merge on it'
  case $acts in
    *approving-review-with-auto-merge*)
      act="$act, or approves it with an approving review while auto-merge is enabled (the agent's GitHub login differs from the PR author's, so the host verifies that review)"
      ;;
  esac
  {
    printf '<!-- planwright:merge-class -->\n'
    printf '**Merge-class fall-through.** `merge_policy` is `policy-class`, and head `%s` is outside the declared class, so this PR falls to `on-approval`: it merges once %s. No agent merges it.\n\n' "$HEAD_SHA" "$act"
    printf '| Predicate | Evidence |\n| --- | --- |\n'
    awk -F '\t' "$ROW_AWK"' $1 == "pred" && $3 == "fail" { printf "| %s | %s |\n", $2, cell($4) }' "$REC"
  } >"$SCRATCH/fall.md"
  failed=$(awk -F '\t' '$1 == "pred" && $3 == "fail" { o = o (o == "" ? "" : ", ") $2 } END { print o }' "$REC")
  if comment "$SCRATCH/fall.md"; then
    say "not merged: outside the class ($failed); the reason is on PR #$PR, which falls to on-approval"
    exit 4
  fi
  say "not merged: outside the class ($failed), and the fall-through comment could not be written"
  exit 5
fi

pr_state() { # sets S_HEAD, S_DRAFT, S_STATE; 1 when unreadable
  local raw
  raw=$(gh pr view "$PR" --json headRefOid,isDraft,state 2>/dev/null) || return 1
  S_HEAD=$(printf '%s' "$raw" | jq -r '.headRefOid // empty' 2>/dev/null)
  S_DRAFT=$(printf '%s' "$raw" | jq -r '.isDraft' 2>/dev/null)
  S_STATE=$(printf '%s' "$raw" | jq -r '.state // empty' 2>/dev/null)
  [ -n "$S_HEAD" ]
}

# 3. The flip of an admitted draft.
pr_state || refuse "PR #$PR could not be read after evaluation"
if [ "$S_DRAFT" = true ]; then
  if [ -n "$EXPECT" ] && [ "$EXPECT" != "$HEAD_SHA" ]; then
    # shellcheck disable=SC2016 # markdown backticks for the comment
    printf '**Merge not attempted.** The class evaluated head `%s`, not the head the pre-ready-flip point ran on, so PR #%s stays a draft and was not merged; re-run the sequence.\n' \
      "$HEAD_SHA" "$PR" >"$SCRATCH/expect.md"
    comment "$SCRATCH/expect.md" \
      || refuse "the evaluated head ${HEAD_SHA:0:12} is not the head the pre-ready-flip point ran on, and the PR comment could not be written"
    say "not merged: the evaluated head ${HEAD_SHA:0:12} is not the head the pre-ready-flip point ran on (${EXPECT:0:12})"
    exit 4
  fi
  grep -E '^(head|pred)	' "$REC" >"$SCRATCH/handin"
  /bin/bash "$SCRIPTS/ready-flip.sh" flip --for-merge --spec "$SPEC" "${UNIT[@]}" --pr "$PR" \
    --preconditions "$SCRATCH/handin" --expect-head "$HEAD_SHA" >"$SCRATCH/flip.out" 2>&1
  frc=$?
  # Skipped as already ready: someone flipped it meanwhile, which the re-pin
  # below accepts like any ready PR.
  if [ "$frc" = 3 ] && pr_state && [ "$S_DRAFT" = false ]; then
    frc=0
  fi
  if [ "$frc" != 0 ]; then
    fwhy=$(sanitize_printable "$(tail -1 "$SCRATCH/flip.out")" '?')
    # shellcheck disable=SC2016 # markdown backticks for the comment
    printf '**Merge not attempted.** The class admitted head `%s`, but its flip ready did not go through, so PR #%s stays a draft and was not merged; the unit'"'"'s handoff says why.\n' \
      "$HEAD_SHA" "$PR" >"$SCRATCH/flipfail.md"
    if comment "$SCRATCH/flipfail.md"; then
      say "not merged: the flip of the admitted PR did not go through ($fwhy)"
      exit 4
    fi
    say "not merged: the flip of the admitted PR did not go through ($fwhy), and the PR comment could not be written"
    exit 5
  fi
fi

# 4. The record.
# shellcheck disable=SC2016
{
  printf '<!-- planwright:merge-admitted -->\n'
  printf '**Merge record.** `merge_policy` is `policy-class`; merging head `%s` into `%s` at `%s` by `%s`, once every predicate below held on it.\n\n' \
    "$HEAD_SHA" "$BASE" "$BASE_OID" "$METHOD"
  printf '| Predicate | Result | Evidence |\n| --- | --- | --- |\n'
  awk -F '\t' "$ROW_AWK"' $1 == "pred" { printf "| %s | %s | %s |\n", $2, $3, cell($4) }' "$REC"
} >"$SCRATCH/record.md"
comment "$SCRATCH/record.md" || refuse "the merge record could not be written to PR #$PR, so no merge was made"

# 5. The re-pin.
moved=''
now=$(/bin/sh "$SCRIPTS/resolve-policy-knob.sh" merge_policy 2>/dev/null) || now='unresolvable'
if [ "$now" != policy-class ]; then
  moved="merge_policy changed to $(sanitize_printable "$now" '?')"
elif ! pr_state; then
  moved='the PR head could not be re-read'
elif [ "$S_HEAD" != "$HEAD_SHA" ]; then
  moved="the PR head moved to $(hex "${S_HEAD:0:12}")"
elif [ "$S_STATE" != OPEN ] || [ "$S_DRAFT" != false ]; then
  moved='the PR is no longer open and ready'
fi
if [ -z "$moved" ]; then
  REMOTE=$(git config "branch.$(git symbolic-ref --short -q HEAD).remote" 2>/dev/null) || REMOTE=origin
  [[ $REMOTE =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || REMOTE=origin
  # The Awaiting-input re-read fetches the base itself, so it goes first and
  # a park landing there is named as a park rather than as a base move.
  if ! /bin/bash "$SCRIPTS/ready-flip.sh" awaiting --spec "$SPEC" "${UNIT[@]}" --base "$BASE" >/dev/null 2>&1; then
    moved="a live Awaiting-input entry for the unit appeared, or could not be read,"
  elif ! git fetch -q "$REMOTE" "+refs/heads/$BASE:refs/remotes/$REMOTE/$BASE" >/dev/null 2>&1; then
    moved="the base $BASE could not be re-read"
  elif [ "$(git rev-parse --verify -q "refs/remotes/$REMOTE/$BASE^{commit}")" != "$BASE_OID" ]; then
    moved="the base $BASE moved from ${BASE_OID:0:12}"
  fi
fi
if [ -n "$moved" ]; then
  printf '**Merge refused.** %s since the predicates were evaluated, so the merge the record above claims was not made; PR #%s is left for a re-run or the operator.\n' \
    "$moved" "$PR" >"$SCRATCH/moved.md"
  if comment "$SCRATCH/moved.md"; then
    say "not merged: $moved since evaluation"
    exit 4
  fi
  say "not merged: $moved since evaluation, and the refusal comment could not be written"
  exit 5
fi

# 6. The merge.
case $METHOD in squash | merge | rebase) ;; *) refuse 'the class record names no merge method' ;; esac
gh pr merge "$PR" "--$METHOD" --match-head-commit "$HEAD_SHA" >/dev/null 2>&1
mrc=$?
# What the host did, not what the call returned.
S_STATE='' S_HEAD=''
pr_state || S_STATE=''
if [ "$S_STATE" = MERGED ]; then
  if [ "$S_HEAD" = "$HEAD_SHA" ]; then
    say "merged PR #$PR at $HEAD_SHA by $METHOD under merge_policy: policy-class"
    exit 0
  fi
  # shellcheck disable=SC2016 # markdown backticks for the comment
  printf '**Merge follow-up.** PR #%s merged at another head (`%s`) than the recorded `%s`, so the record above does not describe that merge; this run did not make it.\n' \
    "$PR" "$(hex "$S_HEAD")" "$HEAD_SHA" >"$SCRATCH/other.md"
  say "not merged by this run: PR #$PR merged at another head ($(hex "${S_HEAD:0:12}")) than the recorded ${HEAD_SHA:0:12}"
  comment "$SCRATCH/other.md" && exit 4
  say 'the follow-up comment could not be written'
  exit 5
fi
if [ "$mrc" = 0 ]; then
  say "PR #$PR at $HEAD_SHA was handed to the host by $METHOD and is not merged yet (a merge queue or auto-merge holds it, or its state could not be read)"
  exit 0
fi
outcome=5
if [ -n "$S_HEAD" ] && [ "$S_HEAD" != "$HEAD_SHA" ]; then
  parked="the PR head moved to $(hex "${S_HEAD:0:12}") during the call, so no park was written on top of it; sync the branch and re-run"
  outcome=4
else
  /bin/bash "$SCRIPTS/ready-flip.sh" park --spec "$SPEC" "${UNIT[@]}" --reason merge-call --base "$BASE" >/dev/null 2>&1
  if [ "$?" = 4 ]; then
    outcome=4
    # shellcheck disable=SC2016 # markdown backticks for the comment
    parked='the unit is parked under `## Awaiting input`'
  else
    parked='the park could not be written either'
  fi
fi
printf '**Merge follow-up.** The merge was not made after the record above (gh exit %s), so PR #%s stays open; %s.\n' \
  "$mrc" "$PR" "$parked" >"$SCRATCH/follow.md"
if ! comment "$SCRATCH/follow.md"; then
  say 'the follow-up comment could not be written either'
  outcome=5
fi
say "not merged after the record (gh exit $mrc); $parked"
exit "$outcome"
