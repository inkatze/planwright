#!/usr/bin/env bash
# pr-agent-push-commands.sh — choose the review PR-Agent runs on a push:
# incremental (/review -i), or full (/review) when a merge commit is among the
# commits the incremental review would take in.
#
# An incremental review takes every file each commit newer than PR-Agent's
# newest review comment touched, diffed against the last commit before them.
# A merge from the base among those commits carries all of the base's changes
# since the branch last synced, so the review can run past its time bound.
# PR-Agent skips only a merge whose message starts "Merge branch '<default>'";
# a "Merge remote-tracking branch 'origin/main'" goes in whole. A full review
# reads the PR's own diff against its base, so a merge adds nothing to it.
#
# The range mirrors PR-Agent 0.49.0's (github_provider.get_commit_range):
# walking back from the head, the commits whose committer date is later than
# the newest review comment's creation, stopping at the first that is not.
# With no review comment PR-Agent reviews in full itself, so the incremental
# command stands.
#
# Usage: pr-agent-push-commands.sh --pr <n> --output <file>
#   Needs gh signed in and GITHUB_REPOSITORY. Appends one line,
#   commands=<JSON list>, to <file> (the step's GITHUB_OUTPUT).
# Exit: 0 a choice was written (a read that fails, or comes back in a shape
#   this script cannot read, picks the full review and warns); 1 the output
#   could not be written; 2 usage.

set -u
LC_ALL=C
export LC_ALL
unset CDPATH

READ_BOUND=60
INCREMENTAL='["/review -i"]'
FULL='["/review"]'
REVIEW_FILTER='.[] | select(.user.login == "github-actions[bot]") | (.body // "") as $b
  | select(([$b | split("\n") | .[:5][] | gsub("^\\s+|\\s+$"; "")]
      | any(. == "<!-- pr-agent:review:full -->" or . == "<!-- pr-agent:review:incremental -->"
        or . == "[pr-agent:review:full]: https://github.com/The-PR-Agent/pr-agent"
        or . == "[pr-agent:review:incremental]: https://github.com/The-PR-Agent/pr-agent"))
    or ($b | startswith("## PR Reviewer Guide") or startswith("## Incremental PR Reviewer Guide")))
  | .created_at'
DATE='[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z'

die_usage() {
  printf 'pr-agent-push-commands: %s\n' "$1" >&2
  printf '%s\n' 'usage: pr-agent-push-commands.sh --pr <n> --output <file>' >&2
  exit 2
}

pr="" output=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --pr | --output)
      [ "$#" -ge 2 ] || die_usage "$1 needs a value"
      case "$1" in
        --pr) pr=$2 ;;
        --output) output=$2 ;;
      esac
      shift 2
      ;;
    *) die_usage "unknown argument: $1" ;;
  esac
done
case "$pr" in '' | *[!0-9]* | 0*) die_usage "--pr must be a pull request number" ;; esac
[ "${#pr}" -le 9 ] || die_usage "--pr must be a pull request number"
[ -n "$output" ] || die_usage "--output is required"
[ -n "${GITHUB_REPOSITORY:-}" ] || die_usage "GITHUB_REPOSITORY is not set"

script_dir=$(cd "$(dirname "$0")" && pwd) || {
  printf '::error title=PR-Agent push review::could not resolve the script directory\n'
  exit 1
}

choose() {
  printf 'commands=%s\n' "$1" >>"$output" || {
    printf '::error title=PR-Agent push review::could not write the choice to %s\n' "$output"
    exit 1
  }
  exit 0
}

# full_on <reason>: a failed or unreadable lookup. The full review's cost is
# bounded by the PR's own diff; an incremental one over a merge is not.
full_on() {
  printf '::warning title=PR-Agent full review::%s, so this push gets a full review.\n' "$1"
  choose "$FULL"
}

# read_api <path> <jq program>: gh api's paginated output, bounded; fails on
# an API error.
read_api() {
  /bin/sh "$script_dir/bounded-run.sh" -k 5 "$READ_BOUND" \
    gh api --paginate "repos/$GITHUB_REPOSITORY/$1" --jq "$2"
}

# The comment list comes in creation order, so its last review comment is the
# newest, as PR-Agent's get_previous_review finds it. A comment is a review as
# comment_identity.comment_matches_identity decides: a marker, in either of
# its stored forms, as a whole line among the first five, or a legacy header
# the body starts with.
reviews=$(read_api "issues/$pr/comments?per_page=100" "$REVIEW_FILTER") \
  || full_on "Could not read the PR's comments"
if [ -n "$reviews" ] && printf '%s\n' "$reviews" | grep -Evq "^$DATE\$"; then
  full_on "The PR's comment list came back in a shape this script cannot read"
fi
last_review=$(printf '%s\n' "$reviews" | tail -n 1)
[ -n "$last_review" ] || choose "$INCREMENTAL"

commits=$(read_api "pulls/$pr/commits?per_page=100" '.[] | "\(.parents | length) \(.commit.committer.date)"') \
  || full_on "Could not read the PR's commits"
if [ -z "$commits" ] || printf '%s\n' "$commits" | grep -Evq "^[0-9]+ $DATE\$"; then
  full_on "The PR's commit list came back in a shape this script cannot read"
fi

# Same-shaped UTC timestamps order as strings.
if printf '%s\n' "$commits" | awk -v since="$last_review" '
  { parents[NR] = $1; date[NR] = $2 }
  END {
    for (i = NR; i >= 1 && date[i] > since; i--)
      if (parents[i] > 1) exit 0
    exit 1
  }'; then
  printf '::notice title=PR-Agent full review::A merge commit is among the commits since the last review, so this push gets a full review of the PR diff instead of an incremental one.\n'
  choose "$FULL"
fi
choose "$INCREMENTAL"
