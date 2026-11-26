#!/usr/bin/env bash
# pr-agent-reviewed.sh — the PR-Agent workflow's once-per-head check: say
# whether this workflow's own run marker already records a successful review
# of the head, so a second event on an unchanged head (the ready flip after a
# draft's review, a repeated request) pays for no second run.
#
# Usage: pr-agent-reviewed.sh --pr <n> --head <sha>
#   Needs gh signed in and GITHUB_REPOSITORY. Writes `reviewed=true` or
#   `reviewed=false` to $GITHUB_OUTPUT when set, else to stdout.
#   The marker is the newest `<!-- pr-agent-run: ... -->` comment that
#   github-actions[bot] posted (the workflow edits one in place); only its
#   head equal to --head with status success reads true. A failed read reads
#   false, with a warning: an unread marker reviews rather than skips.
# Exit: 0 answered; 2 usage.
set -u
LC_ALL=C
export LC_ALL
unset CDPATH

die_usage() {
  printf 'pr-agent-reviewed: %s\n' "$1" >&2
  printf '%s\n' 'usage: pr-agent-reviewed.sh --pr <n> --head <sha>' >&2
  exit 2
}

pr='' head=''
while [ "$#" -gt 0 ]; do
  case $1 in
    --pr | --head)
      [ "$#" -ge 2 ] || die_usage "$1 needs a value"
      case $1 in
        --pr) pr=$2 ;;
        --head) head=$2 ;;
      esac
      shift 2
      ;;
    *) die_usage "unknown argument" ;;
  esac
done
[[ $pr =~ ^[1-9][0-9]{0,9}$ ]] || die_usage '--pr must be a pull request number'
[[ $head =~ ^[0-9a-f]{40}$ ]] || die_usage '--head must be a full commit'
[[ ${GITHUB_REPOSITORY:-} =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || die_usage 'GITHUB_REPOSITORY must be <owner>/<repo>'

answer() {
  if [ -n "${GITHUB_OUTPUT:-}" ]; then
    printf 'reviewed=%s\n' "$1" >>"$GITHUB_OUTPUT"
  else
    printf 'reviewed=%s\n' "$1"
  fi
}

# The marker line is the one .github/workflows/pr-agent.yml writes.
# shellcheck disable=SC2016 # a jq program
if ! marks=$(gh api --paginate "repos/$GITHUB_REPOSITORY/issues/$pr/comments?per_page=100" --jq '
  .[] | select(.user.login == "github-actions[bot]")
  | (.body // "") | split("\n")[0]
  | capture("^<!-- pr-agent-run: id=[0-9]+\\.[0-9]+ head=(?<head>[0-9a-f]*) status=(?<status>[a-z_]+) -->$")?
  | .head + " " + .status' 2>&1); then
  printf '::warning title=PR-Agent run marker unread::The run markers of PR #%s could not be read, so this head is reviewed.\n' "$pr"
  answer false
  exit 0
fi
last=$(printf '%s\n' "$marks" | grep -E '^[0-9a-f]* [a-z_]+$' | tail -n 1)
if [ "$last" = "$head success" ]; then
  printf '::notice title=PR-Agent already reviewed this head::Run marker on PR #%s records a successful review of %s, so no second run.\n' "$pr" "${head:0:12}"
  answer true
else
  answer false
fi
