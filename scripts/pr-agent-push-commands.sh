#!/usr/bin/env bash
# pr-agent-push-commands.sh — choose the review PR-Agent runs on a push:
# incremental (/review -i), or full (/review) when a merge commit is among the
# commits the incremental review would take in.
#
# An incremental review diffs every file the commits newer than PR-Agent's
# newest review comment touched, so a merge from the base among them carries
# all of the base's changes since the last sync and can outrun the time bound.
# PR-Agent skips only a "Merge branch '<default>'" merge; here any commit with
# more than one parent counts. A full review reads the PR's own diff against
# its base, which a merge adds nothing to.
#
# The range mirrors PR-Agent 0.49.0's github_provider.get_commit_range: from
# the head back, the commits whose committer date (author date when it has
# none) is later than the newest review comment's creation, stopping at the
# first that is not. With no review comment PR-Agent reviews in full itself,
# so the incremental command stands. A full review edits that comment in
# place without moving its creation time, so once a merge is in range every
# later push on the PR gets the full review too.
#
# Usage: pr-agent-push-commands.sh --pr <n> --output <file>
#   Needs gh signed in and GITHUB_REPOSITORY; appends commands=<JSON list> to
#   <file> (the step's GITHUB_OUTPUT).
# Exit: 0 a choice was written (a failed or unreadable read picks the full
#   review and warns); 1 the output could not be written; 2 usage.

set -u
LC_ALL=C
export LC_ALL
unset CDPATH

READ_BOUND=60
INCREMENTAL='["/review -i"]'
FULL='["/review"]'
# shellcheck disable=SC2016 # a jq program; $b is jq's
REVIEW_FILTER='.[] | select(.user.login == "github-actions[bot]") | (.body // "") as $b
  | select(([$b | split("\n") | .[:5][] | gsub("^\\s+|\\s+$"; "")]
      | any(. == "<!-- pr-agent:review:full -->" or . == "<!-- pr-agent:review:incremental -->"
        or . == "[pr-agent:review:full]: https://github.com/The-PR-Agent/pr-agent"
        or . == "[pr-agent:review:incremental]: https://github.com/The-PR-Agent/pr-agent"))
    or ($b | startswith("## PR Reviewer Guide") or startswith("## Incremental PR Reviewer Guide")))
  | .created_at'
DATE_RE='[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z'

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

# finish <commands>: write the choice and exit.
finish() {
  printf 'commands=%s\n' "$1" >>"$output" || {
    printf '::error title=PR-Agent push review::could not write the choice to %s\n' "$output"
    exit 1
  }
  exit 0
}

# finish_full <reason>: a failed or unreadable lookup; choose the full review
# and exit. Its cost is bounded by the PR's own diff; an incremental one over a
# merge is not.
finish_full() {
  printf '::warning title=PR-Agent full review::%s, so this push gets a full review.\n' "$1"
  finish "$FULL"
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
review_times=$(read_api "issues/$pr/comments?per_page=100" "$REVIEW_FILTER") \
  || finish_full "Could not read the PR's comments"
if [ -n "$review_times" ] && printf '%s\n' "$review_times" | grep -Evq "^$DATE_RE\$"; then
  finish_full "The PR's comment list came back in a shape this script cannot read"
fi
last_review=$(printf '%s\n' "$review_times" | tail -n 1)
[ -n "$last_review" ] || finish "$INCREMENTAL"

# One "<parent count> <date>" row per commit, oldest first.
commit_rows=$(read_api "pulls/$pr/commits?per_page=100" '.[] | "\(.parents | length) \(.commit.committer.date // .commit.author.date)"') \
  || finish_full "Could not read the PR's commits"
if printf '%s\n' "$commit_rows" | grep -Evq "^[0-9]+ $DATE_RE\$"; then
  finish_full "The PR's commit list came back in a shape this script cannot read"
fi

# The date test ends the walk rather than filtering it, as in PR-Agent's range;
# same-shaped UTC timestamps order as strings.
if printf '%s\n' "$commit_rows" | awk -v since="$last_review" '
  { parents[NR] = $1; date[NR] = $2 }
  END {
    for (i = NR; i >= 1 && date[i] > since; i--)
      if (parents[i] > 1) exit 0
    exit 1
  }'; then
  printf '::notice title=PR-Agent full review::A merge commit is among the commits since the last review, so this push gets a full review of the PR diff instead of an incremental one.\n'
  finish "$FULL"
fi
finish "$INCREMENTAL"
