#!/usr/bin/env bash
# pr-agent-review.sh — run the PR-Agent image on one pull request, retrying a
# try that ends with no review because the model's output was empty, did not
# parse, or arrived truncated. The action exits 0 either way, so whether a
# review landed is read from GitHub (a PR-Agent review comment created or
# edited since the run began), and the cause from the try's log. Rate limits
# back off longer on a budget of their own. Every retry first confirms the PR
# head is still the one under review.
#
# Usage: pr-agent-review.sh --image <ref> --pr <n> [--head <sha>]
#          [--retries <n>] [--try-seconds <n>] [--deadline-seconds <n>]
#   Needs GITHUB_REPOSITORY and GITHUB_EVENT_PATH, and gh signed in. PR-Agent
#   settings (CONFIG.*, OPENROUTER.*, GITHUB_ACTION_CONFIG.*, PR_REVIEWER.*)
#   pass through from the environment. Without --head no retry runs.
#   --retries: retries of a model-output failure (default 2, at most 99).
#   --try-seconds: one try's bound (default 600). --deadline-seconds: no retry
#   starts that could end past this many seconds from the start (default 2100).
# Exit: 0 a review was posted, or PR-Agent posted none and logged no failure
#   (its own skips are silent); 1 no review, the cause named; 2 usage.

set -u
LC_ALL=C
export LC_ALL
unset CDPATH

OUTPUT_BACKOFF=30
RATE_BACKOFF=120
KILL_GRACE=30
READ_TRIES=3
REVIEW_MARK='<!-- pr-agent:review:'
OUTPUT_FAILURE='Empty content in model response|failure to parse AI prediction|failed schema validation|Failed to generate prediction|APIConnectionError'
RATE_LIMIT='RateLimitError|rate limit exceeded|too many requests|"code": ?429'

die_usage() {
  printf 'pr-agent-review: %s\n' "$1" >&2
  printf '%s\n' 'usage: pr-agent-review.sh --image <ref> --pr <n> [--head <sha>] [--retries <n>] [--try-seconds <n>] [--deadline-seconds <n>]' >&2
  exit 2
}

fail() {
  printf '::error title=PR-Agent review failed::%s\n' "$1"
  exit 1
}

# count <value> <max digits>: a whole number without a leading zero.
count() {
  case "$1" in '' | *[!0-9]* | 0?*) return 1 ;; esac
  [ "${#1}" -le "$2" ]
}

image="" pr="" head="" retries=2 try_seconds=600 deadline=2100
while [ "$#" -gt 0 ]; do
  case "$1" in
    --image | --pr | --head | --retries | --try-seconds | --deadline-seconds)
      [ "$#" -ge 2 ] || die_usage "$1 needs a value"
      case "$1" in
        --image) image=$2 ;;
        --pr) pr=$2 ;;
        --head) head=$2 ;;
        --retries) retries=$2 ;;
        --try-seconds) try_seconds=$2 ;;
        --deadline-seconds) deadline=$2 ;;
      esac
      shift 2
      ;;
    *) die_usage "unknown argument: $1" ;;
  esac
done

[ -n "$image" ] || die_usage "--image is required"
count "$pr" 9 && [ "$pr" != 0 ] || die_usage "--pr must be a pull request number"
count "$retries" 2 || die_usage "--retries must be a whole number up to 99"
# bounded-run.sh takes at most six digits.
count "$try_seconds" 6 && [ "$try_seconds" != 0 ] || die_usage "--try-seconds must be a positive whole number"
count "$deadline" 6 || die_usage "--deadline-seconds must be a whole number"
[ -n "${GITHUB_REPOSITORY:-}" ] || die_usage "GITHUB_REPOSITORY is not set"
[ -r "${GITHUB_EVENT_PATH:-}" ] || die_usage "GITHUB_EVENT_PATH is not a readable file"
rate_retries=2
if [ -z "$head" ]; then
  printf '::warning title=PR-Agent retries off::The PR head is unknown, so no retry can be held to it; one try only.\n'
  retries=0 rate_retries=0
fi

script_dir=$(cd "$(dirname "$0")" && pwd) || fail "could not resolve the script directory"
work=$(mktemp -d "${RUNNER_TEMP:-${TMPDIR:-/tmp}}/pr-agent.XXXXXX") || fail "could not create a scratch directory"
container=""
# A cancel or the step limit kills this shell, not the container, which would
# go on calling the model and could post after the run reported its end.
cleanup() {
  [ -z "$container" ] || docker rm -f "$container" >/dev/null 2>&1
  rm -rf "$work"
}
trap cleanup EXIT
trap 'exit 143' TERM
trap 'exit 130' INT

# docker -e NAME copies NAME from this process's environment; the dotted
# PR-Agent names are not shell variables, so only env(1) can list them.
docker_env=(-e GITHUB_EVENT_PATH=/github/workflow/event.json)
for name in $(env | sed -En 's/^((CONFIG|OPENROUTER|GITHUB_ACTION_CONFIG|PR_REVIEWER)\.[A-Za-z0-9_]+)=.*/\1/p' | sort -u); do
  docker_env+=(-e "$name")
done
# The runner variables PR-Agent's action entrypoint and gh client read.
for name in GITHUB_TOKEN GITHUB_EVENT_NAME GITHUB_REPOSITORY GITHUB_API_URL GITHUB_SERVER_URL \
  GITHUB_GRAPHQL_URL GITHUB_SHA GITHUB_REF GITHUB_HEAD_REF GITHUB_BASE_REF GITHUB_ACTOR \
  GITHUB_RUN_ID GITHUB_RUN_ATTEMPT GITHUB_ACTIONS CI; do
  docker_env+=(-e "$name")
done

bounded() { /bin/sh "$script_dir/bounded-run.sh" -k "$KILL_GRACE" "$@"; }

# reviews <file>: write one "<id> <updated_at>" line per PR-Agent review
# comment. A full review edits one persistent comment and an incremental one
# posts a new comment, so a new line, or a moved updated_at, is a review.
reviews() {
  local filter='.[] | select(.user.login == "github-actions[bot]" and (.body | contains("'"$REVIEW_MARK"'"))) | "\(.id) \(.updated_at)"'
  local n=0
  while [ "$n" -lt "$READ_TRIES" ]; do
    n=$((n + 1))
    if gh api --paginate "repos/$GITHUB_REPOSITORY/issues/$pr/comments?per_page=100" --jq "$filter" >"$1"; then
      if grep -Evq '^[0-9]+ [0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$' "$1"; then
        fail "the PR's comment list came back in a shape this script cannot read"
      fi
      return
    fi
    [ "$n" -lt "$READ_TRIES" ] && sleep 5
  done
  fail "could not read the PR's comments, so whether a review was posted is unknown"
}

# posted: a review comment exists that the baseline did not hold.
posted() {
  reviews "$work/now"
  awk 'FILENAME == ARGV[1] { seen[$0] = 1; next } !($0 in seen) { found = 1 } END { exit !found }' \
    "$work/baseline" "$work/now"
}

# try <n>: one PR-Agent run; sets verdict to posted, timeout, exited:<status>,
# rate, output or quiet.
try() {
  local log="$work/try-$1.log" status
  container="pr-agent-$$-$1"
  bounded "$try_seconds" docker run --rm --name "$container" "${docker_env[@]}" \
    -v "$GITHUB_EVENT_PATH:/github/workflow/event.json:ro" "$image" 2>&1 | tee "$log"
  status=${PIPESTATUS[0]}
  # bounded-run.sh ends the docker client; the container can outlive it.
  [ "$status" = 124 ] && docker rm -f "$container" >/dev/null 2>&1
  container=""
  if posted; then
    verdict=posted
  elif [ "$status" = 124 ]; then
    verdict=timeout
  elif [ "$status" != 0 ]; then
    verdict="exited:$status"
  elif grep -Eiq "$RATE_LIMIT" "$log"; then
    verdict=rate
  elif grep -Eq "$OUTPUT_FAILURE" "$log"; then
    verdict=output
  else
    verdict=quiet
  fi
}

# same_head: stop unless the PR's head is still the one this run reviews.
same_head() {
  local now
  now=$(gh api "repos/$GITHUB_REPOSITORY/pulls/$pr" --jq .head.sha) || now=""
  [[ "$now" =~ ^[0-9a-f]{40}$ ]] || fail "could not confirm the PR head before a retry, so none ran"
  [ "$now" = "$head" ] \
    || fail "the PR head moved from ${head:0:12} to ${now:0:12} between tries; a review of the new head is that head's own run"
}

started=$(date +%s)
bounded 300 docker pull --quiet "$image" >"$work/pull.log" 2>&1 \
  || fail "could not pull $image: $(tail -n 1 "$work/pull.log")"
reviews "$work/baseline"

tries=0 output_fails=0 rate_hits=0
while :; do
  tries=$((tries + 1))
  try "$tries"
  wait_s=0
  case "$verdict" in
    posted)
      printf 'PR-Agent posted its review on try %s.\n' "$tries"
      exit 0
      ;;
    quiet)
      printf '::notice title=PR-Agent posted no review::PR-Agent logged no model failure, so this is its own skip (see its log above).\n'
      exit 0
      ;;
    timeout) fail "PR-Agent try $tries timed out after ${try_seconds}s; a timeout is not retried" ;;
    exited:*) fail "PR-Agent exited ${verdict#exited:} on try $tries without posting a review" ;;
    rate)
      rate_hits=$((rate_hits + 1))
      [ "$rate_hits" -le "$rate_retries" ] \
        || fail "PR-Agent was rate limited $rate_hits times, past its $rate_retries rate-limit retries; no review was posted"
      wait_s=$((RATE_BACKOFF * rate_hits))
      printf '::warning title=PR-Agent rate limited::Try %s was rate limited; backing off %ss (not counted against the %s model-output retries).\n' \
        "$tries" "$wait_s" "$retries"
      ;;
    output)
      output_fails=$((output_fails + 1))
      if [ "$output_fails" -gt "$retries" ]; then
        word=tries
        [ "$tries" = 1 ] && word=try
        fail "PR-Agent returned no parseable review after $tries $word (empty or unparseable model output)"
      fi
      wait_s=$((OUTPUT_BACKOFF * output_fails))
      printf '::warning title=PR-Agent retry::Try %s returned no parseable review (empty or unparseable model output); retrying in %ss.\n' \
        "$tries" "$wait_s"
      ;;
  esac
  [ $(($(date +%s) - started + wait_s + try_seconds + KILL_GRACE)) -le "$deadline" ] \
    || fail "no review after try $tries, and another try would run past the ${deadline}s deadline"
  sleep "$wait_s"
  # The comment list can lag the post, so a try judged empty may have landed.
  if posted; then
    printf 'The review from try %s appeared after its check.\n' "$tries"
    exit 0
  fi
  same_head
done
