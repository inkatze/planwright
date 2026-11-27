#!/bin/bash
# request-reviewer.sh — request a review on a pull request without leaving a
# draft PR un-drafted as a side effect (doctrine/human-gates.md; the
# human-gates spec's REQ-C1.7, REQ-C1.8). The one sanctioned agent spelling
# of `gh pr ready --undo`: its re-draft runs only on a PR this run read as a
# draft before its own request. A ready flip someone else makes between that
# read and the check after the request is indistinguishable from the side
# effect, so that narrow window is re-drafted too.
#
# Usage:
#   request-reviewer.sh --repo <owner/repo> --pr <n> (--copilot | --reviewer <app>[bot])
#       [--spec <dir> --task <id>...]
#
#   --copilot   request Copilot through `gh pr edit --add-reviewer @copilot`
#   --reviewer  request a bot through the REST requested_reviewers endpoint,
#               by its App login in the `name[bot]` form
#   --repo      the repository this checkout's origin names, and no other
#   --spec, --task  the unit the PR belongs to, as scripts/ready-flip.sh takes
#               them; given, a failed re-draft parks it
#
# The sequence:
#   1. Read the PR's draft state and base, and the reviewer's newest
#      review_requested timeline event and whether it is a requested
#      reviewer. Any of these unreadable, or a PR that is not open, skips
#      with no request: the run could not tell afterwards whether a ready PR
#      was its own doing, or whether its request landed.
#   2. Request the review. A failed request still runs step 3, since the
#      host may have acted before failing.
#   3. On a PR that was a draft, read the draft state again at once. A PR
#      reported ready, or a read that fails, gets `gh pr ready --undo`.
#   4. A re-draft that fails parks the unit under `## Awaiting input`
#      (ready-flip.sh park, reason `redraft-pr-<n>`), naming the PR, in this
#      checkout, which must be on the PR's head branch; with no unit given, or
#      a checkout on another branch, it is named in the output alone.
#   5. A request the host accepted is not proof: GitHub has answered success
#      while adding no reviewer, and PR-Agent runs on review_requested, so a
#      request that never lands loses that run silently. Poll until the
#      reviewer has a review_requested event newer than step 1's, or is a
#      requested reviewer it was not in step 1, up to the bound below; a read
#      that fails is polled past. A reviewer already requested in step 1
#      with no newer event has not landed: no new event fired PR-Agent.
#
# The check stays wired whether or not the host un-drafts on request today,
# so a host change is caught.
#
# Exit: 0 requested and landed, the draft state held or restored; 1 the
# request failed, the draft state held or restored; 2 usage, a repository
# other than origin's or a reviewer that is not a bot, or a broken install;
# 3 skipped, no request made; 4 the re-draft failed and the unit is parked;
# 5 the re-draft failed and the park did not complete (the output names why);
# 6 the host accepted the request but none landed within the bound (or no
# read succeeded to show one), the draft state held or restored. The output
# names the fallback that fires PR-Agent: on a ready PR, converting it to
# draft and marking it ready again; on a draft, its ready flip. A re-draft
# failure (4, 5) outranks 1 and 6.
#
# Environment: PLANWRIGHT_REQUEST_REVIEWER_POLL_SECONDS (default 3) is the
# landing poll interval and PLANWRIGHT_REQUEST_REVIEWER_MAX_POLLS (default 10)
# the most reads after the request.
#
# No model in the decision path: every step is a comparison.
set -u
unset CDPATH
LC_ALL=C
export LC_ALL

SCRIPTS=$(cd "$(dirname "$0")" && pwd) || exit 2
if [ ! -f "$SCRIPTS/echo-safety.sh" ] || [ ! -r "$SCRIPTS/echo-safety.sh" ]; then
  printf '%s\n' "request-reviewer.sh: echo-safety.sh is missing or unreadable (broken install)" >&2
  exit 2
fi
# shellcheck source=scripts/echo-safety.sh
. "$SCRIPTS/echo-safety.sh" || exit 2

say() { printf 'request-reviewer: %s\n' "$*"; }
usage() {
  printf 'request-reviewer: %s\n' "$1" >&2
  echo 'usage: request-reviewer.sh --repo <owner/repo> --pr <n> (--copilot | --reviewer <app>[bot]) [--spec <dir> --task <id>...]' >&2
  exit 2
}

REPO='' PR='' REVIEWER='' COPILOT=0 SPEC='' IDS=()
while [ "$#" -gt 0 ]; do
  case $1 in
    --repo | --pr | --reviewer | --spec | --task)
      [ "$#" -ge 2 ] || usage "$1 needs a value"
      case $1 in
        --repo) REPO=$2 ;;
        --pr) PR=$2 ;;
        --reviewer) REVIEWER=$2 ;;
        --spec) SPEC=$2 ;;
        --task) IDS[${#IDS[@]}]=$2 ;;
      esac
      shift 2
      ;;
    --copilot)
      COPILOT=1
      shift
      ;;
    *) usage "unknown argument '$(sanitize_printable "$1" '?')'" ;;
  esac
done
[[ $REPO =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || usage '--repo must be <owner>/<repo>'
[[ $PR =~ ^[1-9][0-9]{0,9}$ ]] || usage '--pr must be a pull request number'
if [ "$COPILOT" = 1 ]; then
  [ -z "$REVIEWER" ] || usage '--copilot and --reviewer are exclusive'
else
  [[ $REVIEWER =~ ^[A-Za-z0-9][A-Za-z0-9-]{0,38}\[bot\]$ ]] \
    || usage 'name a bot reviewer: --copilot, or --reviewer <app>[bot]; a person is requested by hand'
fi
# The command guards run this helper unprompted, so it reaches only the
# repository this checkout's origin names; any other is requested by hand.
origin=$(git config --get remote.origin.url 2>/dev/null) || origin=''
origin=${origin%/}
origin=${origin%.git}
# Folded by expansion, not tr: a tr that failed would fold both names to empty,
# and they would compare equal.
fold_lower() {
  local up=ABCDEFGHIJKLMNOPQRSTUVWXYZ low=abcdefghijklmnopqrstuvwxyz i=0
  FOLD=$1
  while [ "$i" -lt 26 ]; do
    FOLD=${FOLD//${up:$i:1}/${low:$i:1}}
    i=$((i + 1))
  done
}
own=''
[[ $origin =~ [/:]([^/:]+/[^/:]+)$ ]] && own=${BASH_REMATCH[1]}
fold_lower "$own"
own=$FOLD
fold_lower "$REPO"
[ -n "$own" ] && [ "$own" = "$FOLD" ] \
  || usage "--repo must be the repository this checkout's origin names"
UNIT=()
for id in "${IDS[@]+"${IDS[@]}"}"; do
  [[ $id =~ ^[0-9]+(\.[0-9]+)?$ ]] || usage "task id '$(sanitize_printable "$id" '?')' is malformed"
  UNIT+=(--task "$id")
done
if [ -n "$SPEC" ] || [ "${#UNIT[@]}" -gt 0 ]; then
  [ -n "$SPEC" ] && [ "${#UNIT[@]}" -gt 0 ] || usage '--spec and --task go together'
  [[ $SPEC =~ ^[A-Za-z0-9_][A-Za-z0-9._-]*(/[A-Za-z0-9_][A-Za-z0-9._-]*)*$ ]] \
    || usage '--spec must be a relative path inside the checkout'
  case "/$SPEC/" in */../* | */./*) usage '--spec must not climb out of the checkout' ;; esac
fi
POLL=${PLANWRIGHT_REQUEST_REVIEWER_POLL_SECONDS:-3}
[[ $POLL =~ ^[0-9]{1,4}$ ]] || POLL=3
# Base 10 explicitly: bash arithmetic reads a leading zero as octal.
POLL=$((10#$POLL))
ATTEMPTS=${PLANWRIGHT_REQUEST_REVIEWER_MAX_POLLS:-10}
[[ $ATTEMPTS =~ ^[0-9]{1,3}$ ]] || ATTEMPTS=10
ATTEMPTS=$((10#$ATTEMPTS))
[ "$ATTEMPTS" -ge 1 ] || ATTEMPTS=10
# The logins the reviewer shows under: GraphQL drops the `[bot]` suffix REST
# carries, and Copilot's request lands as its reviewer App.
if [ "$COPILOT" = 1 ]; then
  LOGINS='copilot-pull-request-reviewer copilot'
else
  LOGINS=$(printf '%s' "${REVIEWER%\[bot\]}" | tr '[:upper:]' '[:lower:]')
fi

if ! command -v gh >/dev/null 2>&1; then
  say 'skipped: gh is not installed, so no review was requested'
  exit 3
fi
command -v jq >/dev/null 2>&1 || {
  say 'skipped: jq is required to read the draft state, so no review was requested'
  exit 3
}

# state — print `<isDraft> <state> <base> <head branch>`; non-zero when
# unreadable, which includes an answer missing any of the four (a null draft
# flag is not "ready").
state() {
  local j
  j=$(gh pr view "$PR" --repo "$REPO" --json isDraft,state,baseRefName,headRefName 2>/dev/null) || return 1
  printf '%s' "$j" | jq -er 'select((.isDraft | type) == "boolean"
    and (.state | type) == "string" and (.state | test("^[A-Z_]+$"))
    and (.baseRefName | type) == "string" and (.baseRefName | length) > 0
    and (.headRefName | type) == "string" and (.headRefName | length) > 0)
    | "\(.isDraft) \(.state) \(.baseRefName) \(.headRefName)"' 2>/dev/null
}

# requested — print `<pending> <event id>`: whether the reviewer is among the
# requested reviewers, and the id of its newest review_requested timeline
# event (`none` without one); non-zero when unreadable.
# shellcheck disable=SC2016 # GraphQL variables, not shell expansions
RQ='query($owner:String!,$name:String!,$number:Int!){ repository(owner:$owner,name:$name){ pullRequest(number:$number){ reviewRequests(first:100){ nodes{ requestedReviewer{ ... on Bot{ login } } } } timelineItems(itemTypes:[REVIEW_REQUESTED_EVENT],last:100){ nodes{ ... on ReviewRequestedEvent{ id requestedReviewer{ ... on Bot{ login } } } } } } } }'
requested() {
  local j
  # -f for owner and name: -F would send a repository named 2048 or null as
  # a number or a null, which the String! variables refuse.
  j=$(gh api graphql -f query="$RQ" -f owner="${REPO%%/*}" -f name="${REPO#*/}" -F number="$PR" 2>/dev/null) || return 1
  printf '%s' "$j" | jq -er --arg who "$LOGINS" '
    def mine: ((.requestedReviewer.login // "") | ascii_downcase | sub("\\[bot\\]$"; "")) as $l
      | $l != "" and ($who | split(" ") | any(. == $l));
    .data.repository.pullRequest
    | select(type == "object" and (.reviewRequests.nodes | type) == "array"
      and (.timelineItems.nodes | type) == "array")
    | "\([.reviewRequests.nodes[] | select(mine)] | length > 0) \(([.timelineItems.nodes[] | select(mine) | .id | strings | gsub("[^A-Za-z0-9_=-]"; "") | select(. != "")] | last) // "none")"' 2>/dev/null
}

# 1. Where the PR stands before the request.
if ! before=$(state); then
  say "skipped: the draft state of PR #$PR could not be read, so no review was requested"
  exit 3
fi
read -r was_draft pr_state BASE HEAD_REF <<EOF
$before
EOF
if [ "$pr_state" != OPEN ]; then
  say "skipped: PR #$PR is $(sanitize_printable "$pr_state" '?'), not open, so no review was requested"
  exit 3
fi
if ! seen=$(requested); then
  say "skipped: the review requests on PR #$PR could not be read, so no review was requested"
  exit 3
fi
read -r pending_before event_before <<EOF
$seen
EOF

# 2. The request.
if [ "$COPILOT" = 1 ]; then
  who='Copilot'
  gh pr edit "$PR" --repo "$REPO" --add-reviewer @copilot >/dev/null 2>&1
else
  who=$REVIEWER
  gh api -X POST "repos/$REPO/pulls/$PR/requested_reviewers" -f "reviewers[]=$REVIEWER" >/dev/null 2>&1
fi
req_rc=$?

# redraft_check — steps 3 and 4: returns 0 when the draft state held or was
# restored, else the exit code (4, 5).
redraft_check() {
  local after why now here park_out park_rc park_why
  # 3. A draft must still be one.
  if after=$(state); then
    case $after in
      'true '*) return 0 ;;
    esac
    why='came back ready after the request'
    now='is no longer a draft'
  else
    why='could not be read after the request, so it is treated as un-drafted'
    now='may no longer be a draft'
  fi
  say "the draft state of PR #$PR $why"
  if gh pr ready "$PR" --repo "$REPO" --undo >/dev/null 2>&1; then
    say "re-drafted PR #$PR"
    return 0
  fi

  # 4. The re-draft failed: the PR may be ready with no one having flipped it.
  say "the re-draft failed: PR #$PR $now, and no one marked it ready"
  if [ "${#UNIT[@]}" = 0 ]; then
    say 'no unit was named, so nothing was parked; put the PR back to draft by hand'
    return 5
  fi
  # The park writes to this checkout's branch, so it must be the PR's own.
  here=$(git symbolic-ref --short -q HEAD 2>/dev/null) || here=''
  if [ "$here" != "$HEAD_REF" ]; then
    say "nothing was parked: this checkout is not on PR #$PR's branch; put the PR back to draft by hand"
    return 5
  fi
  park_out=$(/bin/bash "$SCRIPTS/ready-flip.sh" park --spec "$SPEC" "${UNIT[@]}" --reason "redraft-pr-$PR" --base "$BASE" 2>&1)
  park_rc=$?
  if [ "$park_rc" = 4 ]; then
    say 'the unit is parked under ## Awaiting input'
    return 4
  fi
  # ready-flip's last line names why: a refusal, or a park committed locally
  # whose push failed, which is not the same as nothing written.
  park_why=$(printf '%s\n' "$park_out" | tail -n 1)
  say "the park did not complete ($(sanitize_printable "${park_why:-ready-flip exit $park_rc}" '?')); put the PR back to draft by hand"
  return 5
}

# Checked before the landing wait, so a caller that stops the wait never
# leaves behind a PR the request un-drafted.
redraft=0
if [ "$was_draft" = true ]; then
  redraft_check
  redraft=$?
fi

# 5. An accepted request must land.
nap() { [ "$POLL" = 0 ] || sleep "$POLL"; }
landed=0 reads=0 n=0
while [ "$req_rc" = 0 ] && [ "$n" -lt "$ATTEMPTS" ]; do
  n=$((n + 1))
  if seen=$(requested); then
    reads=$((reads + 1))
    read -r pending_now event_now <<EOF
$seen
EOF
    if { [ "$event_now" != none ] && [ "$event_now" != "$event_before" ]; } \
      || { [ "$pending_now" = true ] && [ "$pending_before" != true ]; }; then
      landed=1
      break
    fi
  fi
  [ "$n" -ge "$ATTEMPTS" ] || nap
done
if [ "$was_draft" = true ]; then
  fallback="marking PR #$PR ready fires PR-Agent"
else
  fallback="to fire PR-Agent, convert PR #$PR to draft and mark it ready again (the operator's act: the policy guard denies agents the re-draft)"
fi
if [ "$req_rc" != 0 ]; then
  say "the review request to $who on PR #$PR failed (gh exit $req_rc)"
  outcome=1
elif [ "$landed" = 1 ]; then
  say "requested a review from $who on PR #$PR"
  outcome=0
elif [ "$reads" = 0 ]; then
  say "the review request to $who on PR #$PR is unconfirmed: every read of its review requests failed after the host accepted it; check for a new PR-Agent run before falling back: $fallback"
  outcome=6
elif [ "$pending_before" = true ]; then
  say "the review request to $who on PR #$PR did not land: $who was already a requested reviewer and no new review_requested event followed; $fallback"
  outcome=6
else
  say "the review request to $who on PR #$PR did not land: no review_requested event and no pending request after the host accepted it; $fallback"
  outcome=6
fi
[ "$redraft" = 0 ] || exit "$redraft"
exit "$outcome"
