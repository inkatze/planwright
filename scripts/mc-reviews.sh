#!/usr/bin/env bash
# mc-reviews.sh — the reviews-at-a-glance snapshot the panel mod draws: the
# gh account's open pull requests and the ones waiting on its review, in a
# program's repositories. Read-only: it only reads from the forge.
#
# `mc-reviews.sh --help` prints the contract: verbs, outputs, exit codes.
set -u
set -f
LC_ALL=C
export LC_ALL
unset CDPATH

prog=mc-reviews
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

# How many pull requests each search returns.
SEARCH_FIRST=30
REASON_MAX=160

usage() { mc_usage_fail "usage: mc-reviews.sh refresh --program <p> [--now <epoch>]"; }

help_text() {
  cat <<'HELP'
mc-reviews.sh — the reviews-at-a-glance snapshot the panel mod draws: the
gh account's open pull requests and the ones waiting on its review, in a
program's repositories. Read-only: it only reads from the forge.

Usage:
  mc-reviews.sh refresh --program <p> [--now <epoch>]
      Rewrite the snapshot, <runtime>/reviews, unless the last attempt is
      younger than mission_control_reviews_ttl (a cadence). One GraphQL
      read, through gh and its own authentication, covers every repository
      the program names, after one repository-name lookup each. Prints
      `fresh` (nothing read), `written`, or `unavailable<TAB><reason>`.
      The snapshot, one tab-separated record per line:
        format<TAB>1
        taken<TAB><epoch>
        state<TAB>ok<TAB>-
        state<TAB>unavailable<TAB><reason>   gh missing, unauthenticated,
                                             refused or answering oddly; no
                                             rows follow
        count<TAB>mine|waiting<TAB><n>       every match of that search,
                                             though at most the newest 30
                                             mine (by update) and the oldest
                                             30 waiting (by creation) are
                                             listed
        mine<TAB><owner/name><TAB><number><TAB>draft|ready
            <TAB>green|red|running|none<TAB><unresolved threads>
            <TAB>yes|no (another account reviewed the current head)
            <TAB><requested reviewers, comma separated, or -><TAB><title>
        waiting<TAB><owner/name><TAB><number><TAB>draft|ready
            <TAB><requester><TAB><requested epoch><TAB><title>
      The requester and epoch are the newest review request naming the
      account, else the pull request's author and creation. A pull
      request's first 100 review threads, last 50 reviews, first 20
      requested reviewers and last 20 review requests are read. Titles have
      their control bytes dropped. A rate-limit refusal waits out the TTL
      like any other failure. The attempt is stamped in
      <runtime>/reviews.attempt before gh is called, so a read that never
      returns is not retried before the TTL either.

The panel reads the snapshot through `scripts/mc-panel.sh digest`.

Exit codes: 0 fresh, written, or unavailable (a degraded snapshot is a
result, never an error); 1 the knob is invalid or the snapshot cannot be
written (its path a symlink included); 2 usage; 3 the program is not
configured.

Portable bash 3.2 / BSD tooling; gh's built-in --jq does the JSON.
HELP
}
case ${1:-} in
  --help | -h)
    help_text
    exit 0
    ;;
esac
[ $# -ge 1 ] && [ "$1" = refresh ] || usage
shift
program=""
now=""
while [ $# -gt 0 ]; do
  case $1 in
    --program | --now)
      [ $# -ge 2 ] || usage
      case $1 in
        --program) program=$2 ;;
        --now) now=$2 ;;
      esac
      shift 2
      ;;
    *) usage ;;
  esac
done
[ -n "$program" ] || usage
mc_now_arg "$now"
mc_require_program "$program"
export PLANWRIGHT_MC_CHECKED="$program"

ttl_raw=$(mc_knob mission_control_reviews_ttl mc_parse_cadence) || exit 1
ttl=$(mc_seconds "$ttl_raw") || exit 1
runtime=$(mc_runtime "$program") || mc_fail "cannot create the runtime directory for '$program'"
snap=$runtime/reviews
attempt=$runtime/reviews.attempt
for f in "$snap" "$attempt"; do
  [ ! -L "$f" ] || mc_fail "$(basename "$f") is a symlink"
done

last=""
if [ -f "$attempt" ]; then
  last=$(awk 'NR == 1 { print; exit }' "$attempt")
fi
if ! mc_valid_uint "$last" && mc_format_ok "$snap"; then
  last=$(awk -F '\t' '$1 == "taken" { print $2; exit }' "$snap")
fi
if mc_valid_uint "$last" && [ "$NOW" -ge "$last" ] && [ $((NOW - last)) -lt "$ttl" ]; then
  printf 'fresh\n'
  exit 0
fi
printf '%s\n' "$NOW" | mc_write "$attempt" || mc_fail "cannot stamp the attempt"

errf=$(mktemp "${TMPDIR:-/tmp}/mc-reviews.XXXXXX") || mc_fail "mktemp failed"
body=$(mktemp "${TMPDIR:-/tmp}/mc-reviews.XXXXXX") || mc_fail "mktemp failed"
reasonf=$(mktemp "${TMPDIR:-/tmp}/mc-reviews.XXXXXX") || mc_fail "mktemp failed"
trap 'rm -f "$errf" "$body" "$reasonf"' EXIT

# unavailable <reason>: write the degraded snapshot and stop. The reason
# keeps printable ASCII only, so the byte cut never splits a character.
unavailable() {
  un_reason=$(printf '%s' "$1" | tr '\t' ' ' | mc_clean | cut -c "1-$REASON_MAX")
  printf 'format\t%s\ntaken\t%s\nstate\tunavailable\t%s\n' "$MC_FORMAT" "$NOW" "$un_reason" \
    | mc_write "$snap" || mc_fail "cannot write the snapshot"
  printf 'unavailable\t%s\n' "$un_reason"
  exit 0
}

# gh_read <args...>: run gh, stdout to the caller. On a failure it returns 1
# and leaves the reason the failure reads as in $reasonf, since a caller in a
# command substitution cannot degrade the snapshot itself.
esc=$(printf '\033')
gh_read() {
  gh "$@" 2>"$errf" && return 0
  gr_rc=$?
  if [ "$gr_rc" -eq 4 ] || grep -Eqi 'gh auth login|not logged in|bad credentials|HTTP 401' "$errf"; then
    printf 'gh is not authenticated\n' >"$reasonf"
  elif grep -qi 'rate limit' "$errf"; then
    printf 'the forge refused the read for its rate limit\n' >"$reasonf"
  else
    printf 'the gh read failed: %s\n' "$(head -n 1 "$errf" | sed "s/$esc\[[0-9;?]*[A-Za-z]//g")" >"$reasonf"
  fi
  return 1
}
failed() { unavailable "$(head -n 1 "$reasonf")"; }

command -v gh >/dev/null 2>&1 || unavailable "gh is not installed"
repos=$(/bin/bash "$script_dir/mc-program.sh" get "$program" repositories 2>/dev/null) \
  || unavailable "the program's repositories cannot be read"

scope=""
while IFS= read -r repo; do
  [ -n "$repo" ] || continue
  [ -d "$repo" ] && [ -x "$repo" ] || unavailable "a program repository is not reachable"
  slug=$(cd "$repo" && gh_read repo view --json nameWithOwner --jq .nameWithOwner) || failed
  mc_valid_slug "$slug" || unavailable "the forge answered with an unexpected repository name"
  scope="$scope repo:$slug"
done <<EOF
$repos
EOF
[ -n "$scope" ] || unavailable "the program names no repository"

# shellcheck disable=SC2016 # GraphQL variables, not shell ones
QUERY='query($mine:String!,$asked:String!){ viewer{ login } mine: search(query:$mine,type:ISSUE,first:'"$SEARCH_FIRST"'){ issueCount nodes{ ... on PullRequest{ number title isDraft headRefOid repository{ nameWithOwner } reviewRequests(first:20){ nodes{ requestedReviewer{ ... on User{ login } ... on Team{ slug } ... on Bot{ login } ... on Mannequin{ login } } } } reviewThreads(first:100){ nodes{ isResolved } } commits(last:1){ nodes{ commit{ statusCheckRollup{ state } } } } reviews(last:50){ nodes{ author{ login } commit{ oid } } } } } } asked: search(query:$asked,type:ISSUE,first:'"$SEARCH_FIRST"'){ issueCount nodes{ ... on PullRequest{ number title isDraft createdAt repository{ nameWithOwner } author{ login } timelineItems(itemTypes:[REVIEW_REQUESTED_EVENT],last:20){ nodes{ ... on ReviewRequestedEvent{ createdAt actor{ login } requestedReviewer{ ... on User{ login } } } } } } } } }'
# A search node that is not a pull request carries no number and is skipped.
# shellcheck disable=SC2016 # jq, not shell
JQ='def clean: gsub("[\u0000-\u001f\u007f-\u009f\u200e\u200f\u202a-\u202e\u2066-\u2069]+"; " ") | gsub("  +"; " ") | sub("^ "; "") | sub(" $"; "");
  def ci: if . == null then "none" elif . == "SUCCESS" then "green"
    elif . == "FAILURE" or . == "ERROR" then "red" else "running" end;
  def state: if .isDraft then "draft" else "ready" end;
  .data.viewer.login as $me
  | "count\tmine\t\(.data.mine.issueCount)", "count\twaiting\t\(.data.asked.issueCount)",
    (.data.mine.nodes[] | select(.number != null) | .headRefOid as $h
     | ["mine", .repository.nameWithOwner, .number, state,
        (.commits.nodes[0].commit.statusCheckRollup.state | ci),
        ([.reviewThreads.nodes[] | select(.isResolved | not)] | length),
        (if any(.reviews.nodes[]; .commit.oid == $h and .author.login != $me) then "yes" else "no" end),
        ([.reviewRequests.nodes[].requestedReviewer | (.login // .slug // empty)]
          | if length == 0 then "-" else join(", ") end),
        .title] | map(tostring | clean) | join("\t")),
    (.data.asked.nodes[] | select(.number != null)
     | ([.timelineItems.nodes[] | select(.requestedReviewer.login == $me)] | last) as $ev
     | ["waiting", .repository.nameWithOwner, .number, state,
        ($ev.actor.login // .author.login // "-"),
        (($ev.createdAt // .createdAt) | fromdateiso8601), .title] | map(tostring | clean) | join("\t"))'

rows=$(gh_read api graphql -f mine="${scope# } is:pr is:open author:@me sort:updated-desc" \
  -f asked="${scope# } is:pr is:open review-requested:@me sort:created-asc" -f query="$QUERY" --jq "$JQ") || failed

odd() { unavailable "the forge answered with an unexpected field"; }
while IFS='	' read -r kind slug number draft a b c d title; do
  [ -n "$kind" ] || continue
  if [ "$kind" = count ]; then
    case $slug in mine | waiting) ;; *) odd ;; esac
    mc_valid_uint "$number" || odd
    printf 'count\t%s\t%s\n' "$slug" "$number" >>"$body"
    continue
  fi
  mc_valid_slug "$slug" || odd
  mc_valid_uint "$number" || odd
  case $draft in draft | ready) ;; *) odd ;; esac
  case $kind in
    mine)
      case $a in green | red | running | none) ;; *) odd ;; esac
      mc_valid_uint "$b" || odd
      case $c in yes | no) ;; *) odd ;; esac
      printf 'mine\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$slug" "$number" "$draft" "$a" "$b" "$c" "$d" "$title" >>"$body"
      ;;
    waiting)
      mc_valid_uint "$b" || odd
      # The requester and title sit one field left of the mine row's.
      printf 'waiting\t%s\t%s\t%s\t%s\t%s\t%s\n' "$slug" "$number" "$draft" "$a" "$b" "$c" >>"$body"
      ;;
    *) odd ;;
  esac
done <<EOF
$rows
EOF

{
  printf 'format\t%s\ntaken\t%s\nstate\tok\t-\n' "$MC_FORMAT" "$NOW"
  mc_clean_text <"$body"
} | mc_write "$snap" || mc_fail "cannot write the snapshot"
printf 'written\n'
exit 0
