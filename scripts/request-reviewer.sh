#!/bin/bash
# request-reviewer.sh — request a review on a pull request without leaving a
# draft PR un-drafted as a side effect (doctrine/human-gates.md; the
# human-gates spec's REQ-C1.7, REQ-C1.8). The one sanctioned agent spelling
# of `gh pr ready --undo`: its re-draft runs only on a PR this run read as a
# draft before its own request, so it can never send a ready PR back.
#
# Usage:
#   request-reviewer.sh --repo <owner/repo> --pr <n> (--copilot | --reviewer <login>)
#       [--spec <dir> --task <id>...]
#
#   --copilot   request Copilot through `gh pr edit --add-reviewer @copilot`
#   --reviewer  request <login> through the REST requested_reviewers endpoint
#               (an App's login in its `name[bot]` form)
#   --spec, --task  the unit the PR belongs to, as scripts/ready-flip.sh takes
#               them; given, a failed re-draft parks it
#
# The sequence:
#   1. Read the PR's draft state and base. An unreadable state, or a PR that
#      is not open, skips with no request: the run could not tell afterwards
#      whether a ready PR was its own doing.
#   2. Request the review. A failed request still runs step 3, since the
#      host may have acted before failing.
#   3. On a PR that was a draft, read the draft state again. A PR reported
#      ready, or a read that fails, gets `gh pr ready --undo`.
#   4. A re-draft that fails parks the unit under `## Awaiting input`
#      (ready-flip.sh park, reason `redraft-pr-<n>`), naming the PR, in this
#      checkout, which must be on the PR's head branch; with no unit given, or
#      a checkout on another branch, it is named in the output alone.
#
# The live probe behind this (kickoff brief, risk register) found no
# un-draft on request; the check stays wired so a host change is caught.
#
# Exit: 0 requested, the draft state held or restored; 1 the request failed,
# the draft state held or restored; 2 usage; 3 skipped, no request made; 4 the
# re-draft failed and the unit is parked; 5 the re-draft failed and nothing
# was parked.
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
  echo 'usage: request-reviewer.sh --repo <owner/repo> --pr <n> (--copilot | --reviewer <login>) [--spec <dir> --task <id>...]' >&2
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
  [[ $REVIEWER =~ ^[A-Za-z0-9][A-Za-z0-9-]{0,38}(\[bot\])?$ ]] || usage 'name the reviewer: --copilot, or --reviewer <login>'
fi
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

# 2. The request.
if [ "$COPILOT" = 1 ]; then
  who='Copilot'
  gh pr edit "$PR" --repo "$REPO" --add-reviewer @copilot >/dev/null 2>&1
else
  who=$REVIEWER
  gh api -X POST "repos/$REPO/pulls/$PR/requested_reviewers" -f "reviewers[]=$REVIEWER" >/dev/null 2>&1
fi
req_rc=$?
if [ "$req_rc" = 0 ]; then
  say "requested a review from $who on PR #$PR"
  outcome=0
else
  say "the review request to $who on PR #$PR failed (gh exit $req_rc)"
  outcome=1
fi
if [ "$was_draft" != true ]; then
  exit "$outcome"
fi

# 3. A draft must still be one.
if after=$(state); then
  case $after in
    'true '*) exit "$outcome" ;;
  esac
  why='came back ready after the request'
else
  why='could not be read after the request, so it is treated as un-drafted'
fi
say "the draft state of PR #$PR $why"
if gh pr ready "$PR" --repo "$REPO" --undo >/dev/null 2>&1; then
  say "re-drafted PR #$PR"
  exit "$outcome"
fi

# 4. The re-draft failed: the PR may be ready with no one having flipped it.
say "the re-draft failed: PR #$PR is no longer a draft, and no one marked it ready"
if [ "${#UNIT[@]}" = 0 ]; then
  say 'no unit was named, so nothing was parked; put the PR back to draft by hand'
  exit 5
fi
# The park writes to this checkout's branch, so it must be the PR's own.
here=$(git symbolic-ref --short -q HEAD 2>/dev/null) || here=''
if [ "$here" != "$HEAD_REF" ]; then
  say "nothing was parked: this checkout is not on PR #$PR's branch; put the PR back to draft by hand"
  exit 5
fi
/bin/bash "$SCRIPTS/ready-flip.sh" park --spec "$SPEC" "${UNIT[@]}" --reason "redraft-pr-$PR" --base "$BASE" >/dev/null 2>&1
if [ "$?" = 4 ]; then
  say 'the unit is parked under ## Awaiting input'
  exit 4
fi
say 'the park could not be written either; put the PR back to draft by hand'
exit 5
