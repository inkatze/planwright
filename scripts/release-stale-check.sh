#!/usr/bin/env bash
# release-stale-check.sh — escalate a merged release PR that was never published.
#
# Merging the release PR approves a release; the signed tag and the GitHub
# Release come later from scripts/release-publish.sh, a local act. Until that
# runs, the merged PR keeps release-please's `autorelease: pending` label, and
# release-please suppresses every new proposal. Nothing else fails loudly in
# that state (the release-please job stays green with its proposal suppressed),
# so a forgotten or refused publish can sit unnoticed for hours. This check
# turns that silence into a red status once the merge is older than a bound.
#
# It reads only the label and the merge time. A pending label that outlives a
# tag that already exists (release-publish.sh's relabel is best-effort) is
# reported too: release-please deadlocks on that label just the same.
#
# Output (stdout): one line per stale PR, then the publish command.
# Exit: 0 nothing stale; 1 at least one stale release PR; 2 the state could not
# be read (gh failed, or its output did not parse), or a usage error. Exit 2 is
# distinct so a caller never folds "could not tell" into "nothing stale".
#
# Usage: release-stale-check.sh [--max-age-hours <n>] [--now <epoch-seconds>]
#   Run inside the repo with a signed-in gh (or GH_TOKEN plus GH_REPO in CI).
#   --max-age-hours: how long a merged release PR may stay pending (default 2).
#   --now: the evaluation time, for reproducible runs (default: the clock).

set -u
LC_ALL=C
export LC_ALL
unset CDPATH

PENDING_LABEL="autorelease: pending"
max_age_hours=2
now=""

usage() {
  echo "release-stale-check: usage: release-stale-check.sh [--max-age-hours <n>] [--now <epoch-seconds>]" >&2
  exit 2
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --max-age-hours)
      [ "$#" -ge 2 ] || usage
      max_age_hours="$2"
      shift 2
      ;;
    --now)
      [ "$#" -ge 2 ] || usage
      now="$2"
      shift 2
      ;;
    *) usage ;;
  esac
done

case "$max_age_hours" in
  '' | *[!0-9]*) usage ;;
esac
[ -n "$now" ] || now=$(date -u +%s)
case "$now" in
  '' | *[!0-9]*) usage ;;
esac

# Merged PRs only: an open release PR carries the same label and is not stale.
# The limit is generous because release-please leaves the label on every PR
# whose publish never relabelled it, and those are exactly what must surface.
prs=$(gh pr list --state merged --label "$PENDING_LABEL" --limit 50 \
  --json number,title,mergedAt 2>/dev/null) || {
  echo "release-stale-check: could not list merged '$PENDING_LABEL' pull requests (gh pr list failed); release state unknown" >&2
  exit 2
}

stale=$(printf '%s' "$prs" | jq -r --argjson now "$now" --argjson max "$max_age_hours" '
  map(select(.mergedAt != null)
      | . + {age: ($now - (.mergedAt | fromdateiso8601))}
      | select(.age > ($max * 3600)))
  | sort_by(.number)
  | .[]
  | "#\(.number) \(.title) merged \(.mergedAt), \((.age / 3600) | floor)h ago, still labelled autorelease: pending"
' 2>/dev/null) || {
  echo "release-stale-check: could not parse the pull request list from gh; release state unknown" >&2
  exit 2
}

if [ -z "$stale" ]; then
  exit 0
fi

printf '%s\n' "$stale"
echo "release-stale-check: a merged release was not published within ${max_age_hours}h; publish it with: scripts/release-publish.sh"
exit 1
