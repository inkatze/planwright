#!/usr/bin/env bash
# pr-agent-review.sh — run the PR-Agent image on one pull request, retrying a
# try that ends with no review because the model's output was empty or did
# not parse. The action itself exits 0 either way, so whether a review landed
# is read from GitHub (a PR-Agent comment updated since the try began), and
# the cause from the try's log. Rate limits back off longer on a budget of
# their own. Every retry first confirms the PR head is still the one under
# review; a moved head is left to its own run.
#
# Usage: pr-agent-review.sh --image <ref> --pr <n> [--head <sha>]
#          [--retries <n>] [--try-seconds <n>]
#   Needs GITHUB_REPOSITORY and GITHUB_EVENT_PATH, and gh signed in. PR-Agent
#   settings (CONFIG.*, OPENROUTER.*, GITHUB_ACTION_CONFIG.*, PR_REVIEWER.*)
#   pass through from the environment. Without --head no retry runs.
# Exit: 0 a review was posted, or PR-Agent skipped on purpose; 1 no review
#   (the cause is named); 2 usage.

set -u
LC_ALL=C
export LC_ALL
unset CDPATH

EMPTY_BACKOFF=30
RATE_BACKOFF=120
RATE_RETRIES=2
KILL_GRACE=30

die_usage() {
  printf 'pr-agent-review: %s\n' "$1" >&2
  printf '%s\n' 'usage: pr-agent-review.sh --image <ref> --pr <n> [--head <sha>] [--retries <n>] [--try-seconds <n>]' >&2
  exit 2
}

fail() {
  printf '::error title=PR-Agent review failed::%s\n' "$1"
  exit 1
}

image="" pr="" head="" retries=2 try_seconds=600
while [ "$#" -gt 0 ]; do
  case "$1" in
    --image | --pr | --head | --retries | --try-seconds)
      [ "$#" -ge 2 ] || die_usage "$1 needs a value"
      case "$1" in
        --image) image=$2 ;;
        --pr) pr=$2 ;;
        --head) head=$2 ;;
        --retries) retries=$2 ;;
        --try-seconds) try_seconds=$2 ;;
      esac
      shift 2
      ;;
    *) die_usage "unknown argument: $1" ;;
  esac
done

nat() {
  case "$1" in '' | *[!0-9]* | 0?*) return 1 ;; esac
}
[ -n "$image" ] || die_usage "--image is required"
nat "$pr" && [ "$pr" != 0 ] || die_usage "--pr must be a pull request number"
nat "$retries" || die_usage "--retries must be a whole number"
nat "$try_seconds" && [ "$try_seconds" != 0 ] || die_usage "--try-seconds must be a positive whole number"
[ -n "${GITHUB_REPOSITORY:-}" ] || die_usage "GITHUB_REPOSITORY is not set"
[ -r "${GITHUB_EVENT_PATH:-}" ] || die_usage "GITHUB_EVENT_PATH is not a readable file"
if [ -z "$head" ]; then
  printf '::warning title=PR-Agent retries off::The PR head is unknown, so no retry can be held to it; one try only.\n'
  retries=0
fi

work=$(mktemp -d "${RUNNER_TEMP:-${TMPDIR:-/tmp}}/pr-agent.XXXXXX") || fail "could not create a scratch directory"
trap 'rm -rf "$work"' EXIT

# docker -e NAME copies NAME from this process's environment; the dotted
# PR-Agent names are not shell variables, so only env(1) can list them.
docker_env=(-e GITHUB_EVENT_PATH=/github/workflow/event.json)
for name in $(env | sed -En 's/^((CONFIG|OPENROUTER|GITHUB_ACTION_CONFIG|PR_REVIEWER)\.[A-Za-z0-9_]+)=.*/\1/p' | sort -u) \
  GITHUB_TOKEN GITHUB_EVENT_NAME GITHUB_REPOSITORY GITHUB_API_URL GITHUB_SERVER_URL \
  GITHUB_GRAPHQL_URL GITHUB_SHA GITHUB_REF GITHUB_HEAD_REF GITHUB_BASE_REF GITHUB_ACTOR \
  GITHUB_RUN_ID GITHUB_RUN_ATTEMPT GITHUB_ACTIONS CI; do
  docker_env+=(-e "$name")
done

script_dir=$(cd "$(dirname "$0")" && pwd) || fail "could not resolve the script directory"

docker pull --quiet "$image" >"$work/pull.log" 2>&1 || fail "could not pull $image: $(tail -n 1 "$work/pull.log")"

# try <n>: one PR-Agent run; sets verdict to posted, rate, model, skipped,
# silent, exited:<status> or timeout.
try() {
  log="$work/try-$1.log"
  container="pr-agent-$$-$1"
  start=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  /bin/sh "$script_dir/bounded-run.sh" -k "$KILL_GRACE" "$try_seconds" \
    docker run --rm --name "$container" "${docker_env[@]}" \
    -v "$GITHUB_EVENT_PATH:/github/workflow/event.json:ro" "$image" 2>&1 | tee "$log"
  status=${PIPESTATUS[0]}
  if [ "$status" = 124 ]; then
    docker rm -f "$container" >"$work/rm.log" 2>&1
    verdict=timeout
    return
  fi
  marks=$(gh api "repos/$GITHUB_REPOSITORY/issues/$pr/comments?since=$start&per_page=100" --paginate \
    --jq '.[] | select(.user.login == "github-actions[bot]" and (.body | contains("<!-- pr-agent:review:"))) | .updated_at') \
    || fail "could not read the PR's comments, so whether try $1 posted a review is unknown"
  while IFS= read -r at; do
    [ -n "$at" ] && ! [[ "$at" < "$start" ]] && {
      verdict=posted
      return
    }
  done <<<"$marks"
  if grep -Eiq 'RateLimitError|rate limit exceeded|too many requests|"code": ?429' "$log"; then
    verdict=rate
  elif grep -Eq 'Empty content in model response|failure to parse AI prediction|failed schema validation|Failed to generate prediction|APIConnectionError' "$log"; then
    verdict=model
  elif [ "$status" != 0 ]; then
    verdict="exited:$status"
  elif grep -Eq 'there are no new files|Skipping [a-z_]+: bot commit' "$log"; then
    verdict=skipped
  else
    verdict=silent
  fi
}

# same_head: the PR's head is still the one this run reviews.
same_head() {
  now=$(gh api "repos/$GITHUB_REPOSITORY/pulls/$pr" --jq .head.sha) || now=""
  [[ "$now" =~ ^[0-9a-f]{40}$ ]] || fail "could not confirm the PR head before a retry, so none ran"
  [ "$now" = "$head" ] \
    || fail "the PR head moved from ${head:0:12} to ${now:0:12} between tries; the new head's own run reviews it"
}

tries=0 model_fails=0 rate_hits=0
while :; do
  tries=$((tries + 1))
  try "$tries"
  case "$verdict" in
    posted)
      printf 'PR-Agent posted its review on try %s.\n' "$tries"
      exit 0
      ;;
    skipped)
      printf 'PR-Agent skipped this event on purpose (see its log above); nothing to review.\n'
      exit 0
      ;;
    timeout) fail "PR-Agent try $tries timed out after ${try_seconds}s; a timeout is not retried" ;;
    exited:*) fail "PR-Agent exited ${verdict#exited:} on try $tries without posting a review" ;;
    silent) fail "PR-Agent posted no review on try $tries and logged no known cause; see its log above" ;;
    rate)
      rate_hits=$((rate_hits + 1))
      [ "$rate_hits" -le "$RATE_RETRIES" ] \
        || fail "PR-Agent was rate limited on every try ($rate_hits times); no review was posted"
      wait_s=$((RATE_BACKOFF * rate_hits))
      printf '::warning title=PR-Agent rate limited::Try %s was rate limited; backing off %ss (not counted against the %s empty-output retries).\n' \
        "$tries" "$wait_s" "$retries"
      ;;
    model)
      model_fails=$((model_fails + 1))
      if [ "$model_fails" -gt "$retries" ]; then
        word=tries
        [ "$tries" = 1 ] && word=try
        fail "PR-Agent returned no parseable review after $tries $word (empty or unparseable model output)"
      fi
      wait_s=$((EMPTY_BACKOFF * model_fails))
      printf '::warning title=PR-Agent retry::Try %s returned no parseable review (empty or unparseable model output); retrying in %ss.\n' \
        "$tries" "$wait_s"
      ;;
  esac
  sleep "$wait_s"
  same_head
done
