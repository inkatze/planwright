#!/usr/bin/env bash
# pr-agent-review.sh — run the PR-Agent image on one pull request, retrying a
# try that ends with no review because the model's output was empty, did not
# parse, or arrived truncated. The action exits 0 either way, so whether a
# review landed is read from GitHub (a PR-Agent review comment that is new, or
# whose updated_at moved, against a snapshot taken before the first try), and
# the cause from the try's log. Rate limits back off longer on a budget of
# their own. Every retry first confirms the PR head is still the one under
# review.
#
# Usage: pr-agent-review.sh --image <ref> --pr <n> [--head <sha>]
#          [--retries <n>] [--try-seconds <n>] [--deadline-seconds <n>]
#   Needs docker, gh signed in, GITHUB_REPOSITORY, GITHUB_EVENT_PATH and the
#   container's GITHUB_TOKEN. PR-Agent settings (CONFIG.*, OPENROUTER.*,
#   GITHUB_ACTION_CONFIG.*, PR_REVIEWER.*) pass through from the environment.
#   --head: the full commit; without it no retry runs.
#   --retries: retries of a model-output failure (default 2, at most 99).
#   --try-seconds: one try's bound (default 600). --deadline-seconds: no retry
#   starts that could end past this many seconds from the start (default 2100).
# Exit: 0 a review was posted, or the first try posted none and logged neither
#   a failure nor an error (PR-Agent's own skips are silent); 1 no review, the
#   cause named; 2 usage.

set -u
LC_ALL=C
export LC_ALL
unset CDPATH

OUTPUT_BACKOFF=30
RATE_BACKOFF=120
RATE_RETRIES=2
KILL_GRACE=30
READ_TRIES=3
READ_BOUND=60
# One quick comment and head read after a try and its backoff; a degraded API
# that spends every read's bound runs into the step limit's margin instead.
READ_SLACK=60
REVIEW_MARK='<!-- pr-agent:review:'
OUTPUT_FAILURE='Empty content in model response|failure to parse AI prediction|failed schema validation|Failed to generate prediction|APIConnectionError'
RATE_LIMIT='RateLimitError|rate limit exceeded|too many requests|"code": ?429'
# A loguru line's level field, colour codes and all; anchored on the line's
# timestamp so an echoed table row or a continuation line never matches.
# loguru pads the level inside its colour codes, so a coloured CRITICAL meets
# its reset code with no space.
ANSI="($(printf '\033')\\[[0-9;]*m)*"
LOGGED_ERROR="^${ANSI}[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9:.]+${ANSI} \\| ${ANSI}(ERROR|CRITICAL) *${ANSI} \\|"

die_usage() {
  printf 'pr-agent-review: %s\n' "$1" >&2
  printf '%s\n' 'usage: pr-agent-review.sh --image <ref> --pr <n> [--head <sha>] [--retries <n>] [--try-seconds <n>] [--deadline-seconds <n>]' >&2
  exit 2
}

fail() {
  printf '::error title=PR-Agent review failed::%s\n' "$1"
  exit 1
}

# whole_number <value> <max digits>: no sign, no leading zero.
whole_number() {
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
whole_number "$pr" 9 && [ "$pr" != 0 ] || die_usage "--pr must be a pull request number"
[ -z "$head" ] || [[ "$head" =~ ^[0-9a-f]{40}$ ]] || die_usage "--head must be a full lowercase commit id"
whole_number "$retries" 2 || die_usage "--retries must be a whole number up to 99"
# bounded-run.sh takes at most six digits.
whole_number "$try_seconds" 6 && [ "$try_seconds" != 0 ] || die_usage "--try-seconds must be a positive whole number"
whole_number "$deadline" 6 || die_usage "--deadline-seconds must be a whole number"
[ -n "${GITHUB_REPOSITORY:-}" ] || die_usage "GITHUB_REPOSITORY is not set"
[ -r "${GITHUB_EVENT_PATH:-}" ] || die_usage "GITHUB_EVENT_PATH is not a readable file"
rate_retries=$RATE_RETRIES
if [ -z "$head" ]; then
  printf '::warning title=PR-Agent retries off::The PR head is unknown, so no retry can be held to it; one try only.\n'
  retries=0 rate_retries=0
fi

script_dir=$(cd "$(dirname "$0")" && pwd) || fail "could not resolve the script directory"
work=$(mktemp -d "${RUNNER_TEMP:-${TMPDIR:-/tmp}}/pr-agent.XXXXXX") || fail "could not create a scratch directory"
# The exit trap's state: the try's container, the current background job (the
# docker client's bounded-run.sh, or a backoff sleep), the tee copying the
# try's log, and a signal held while a job starts.
container="" job="" tee_job="" held=""

bounded() { /bin/sh "$script_dir/bounded-run.sh" -k "$KILL_GRACE" "$@"; }

# A cancel or the step limit kills this shell, not the container, which would
# go on calling the model and could post after the run reported its end.
# docker run passes a TERM on to the container, whose PID 1 may ignore it, so
# the container is removed without waiting for the client, and again each
# second while the client lives, in case it was still creating it.
cleanup() {
  # A no-op handler, not an ignore: an ignored signal is inherited, and the
  # bounded docker rm below could then not be ended by its bound.
  trap : TERM INT HUP
  [ -z "$job" ] || kill "$job" 2>/dev/null
  if [ -n "$container" ]; then
    bounded 10 docker rm -f "$container" >/dev/null 2>&1
    while [ -n "$job" ] && kill -0 "$job" 2>/dev/null; do
      sleep 1
      bounded 10 docker rm -f "$container" >/dev/null 2>&1
    done
  fi
  [ -z "$job" ] || wait "$job" 2>/dev/null
  # The daemon can still finish a create the client asked for before it died.
  [ -z "$container" ] || bounded 10 docker rm -f "$container" >/dev/null 2>&1
  # A job killed before it opened the FIFO leaves tee blocked on it forever.
  [ -z "$tee_job" ] || kill "$tee_job" 2>/dev/null
  [ -z "$tee_job" ] || wait "$tee_job" 2>/dev/null
  rm -rf "$work"
}
arm_traps() {
  trap 'exit 143' TERM
  trap 'exit 130' INT
  trap 'exit 129' HUP
}
# hold_traps and release_traps bracket a job's start: a signal before its pid
# is known is noted, then acted on once cleanup can reach the job.
hold_traps() {
  held=""
  trap 'held=143' TERM
  trap 'held=130' INT
  trap 'held=129' HUP
}
release_traps() {
  arm_traps
  [ -z "$held" ] || exit "$held"
}
trap cleanup EXIT
arm_traps

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

# reviews <file>: write one "<id> <updated_at>" line per PR-Agent review
# comment. A full review edits one persistent comment and an incremental one
# posts a new comment, so a new line, or a moved updated_at, is a review.
reviews() {
  local filter='.[] | select(.user.login == "github-actions[bot]" and (.body | contains("'"$REVIEW_MARK"'"))) | "\(.id) \(.updated_at)"'
  local n=0
  while [ "$n" -lt "$READ_TRIES" ]; do
    n=$((n + 1))
    if bounded "$READ_BOUND" gh api --paginate "repos/$GITHUB_REPOSITORY/issues/$pr/comments?per_page=100" --jq "$filter" >"$1"; then
      if grep -Evq '^[0-9]+ [0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$' "$1"; then
        fail "the PR's comment list came back in a shape this script cannot read"
      fi
      return
    fi
    [ "$n" -lt "$READ_TRIES" ] && sleep 5
  done
  fail "could not read the PR's comments, so whether a review was posted is unknown"
}

# review_posted: a review comment exists that the baseline did not hold.
review_posted() {
  reviews "$work/now"
  awk 'FILENAME == ARGV[1] { seen[$0] = 1; next } !($0 in seen) { found = 1 } END { exit !found }' \
    "$work/baseline" "$work/now"
}

# try <n>: one PR-Agent run; sets verdict to posted, timeout, exited:<status>,
# rate_limited, bad_output, errored or quiet.
try() {
  local log="$work/try-$1.log" pipe="$work/try-$1.pipe" status tee_status
  # In the background, so a signal interrupts the wait at once (bash holds a
  # trap until a foreground job ends), and through a FIFO rather than a pipe,
  # so the job's pid is bounded-run.sh itself: the process that passes a TERM
  # on to docker, and whose wait gives the client's status. The bounded
  # function cannot start it: backgrounding a function gives a subshell's pid.
  mkfifo "$pipe" || fail "could not create the log FIFO for try $1"
  hold_traps
  container="pr-agent-$$-$1"
  tee "$log" <"$pipe" &
  tee_job=$!
  /bin/sh "$script_dir/bounded-run.sh" -k "$KILL_GRACE" "$try_seconds" \
    docker run --rm --name "$container" "${docker_env[@]}" \
    -v "$GITHUB_EVENT_PATH:/github/workflow/event.json:ro" "$image" >"$pipe" 2>&1 &
  job=$!
  release_traps
  wait "$job"
  status=$?
  job=""
  wait "$tee_job"
  tee_status=$?
  tee_job=""
  # A killed or failed docker client can leave its container running; a clean
  # exit's container went with --rm.
  [ "$status" = 0 ] || bounded 60 docker rm -f "$container" >/dev/null 2>&1
  container=""
  # The verdicts below read the log; without all of it a failed try could
  # pass as PR-Agent's own skip.
  [ "$tee_status" = 0 ] && [ -f "$log" ] \
    || fail "could not keep the log of try $1, so its outcome is unknown"
  if review_posted; then
    verdict=posted
  elif [ "$status" = 124 ]; then
    verdict=timeout
  elif [ "$status" != 0 ]; then
    verdict="exited:$status"
  # A rate-limited fallback chain also logs empty output; it needs the longer wait.
  elif grep -Eiq "$RATE_LIMIT" "$log"; then
    verdict=rate_limited
  elif grep -Eq "$OUTPUT_FAILURE" "$log"; then
    verdict=bad_output
  elif grep -Eq "$LOGGED_ERROR" "$log"; then
    verdict=errored
  else
    verdict=quiet
  fi
}

# same_head: stop unless the PR's head is still the one this run reviews.
same_head() {
  local now
  now=$(bounded "$READ_BOUND" gh api "repos/$GITHUB_REPOSITORY/pulls/$pr" --jq .head.sha) || now=""
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
      # A skip depends on the event alone, so it shows on the first try; a
      # quiet retry is a failure nobody logged.
      [ "$tries" = 1 ] \
        || fail "try $tries, a retry after a failed try, posted no review and logged no cause"
      printf '::notice title=PR-Agent posted no review::PR-Agent logged no failure or error, so this is its own skip (see its log above).\n'
      exit 0
      ;;
    timeout) fail "PR-Agent try $tries timed out after ${try_seconds}s; a timeout is not retried" ;;
    exited:*) fail "PR-Agent exited ${verdict#exited:} on try $tries without posting a review" ;;
    errored) fail "PR-Agent logged an error on try $tries and posted no review; see its log above" ;;
    rate_limited)
      rate_hits=$((rate_hits + 1))
      [ "$rate_hits" -le "$rate_retries" ] \
        || fail "PR-Agent was rate limited past its $rate_retries rate-limit retries; no review was posted"
      wait_s=$((RATE_BACKOFF * rate_hits))
      note_title="PR-Agent rate limited" note_body="Try $tries was rate limited; backing off ${wait_s}s (not counted against the $retries model-output retries)."
      ;;
    bad_output)
      output_fails=$((output_fails + 1))
      if [ "$output_fails" -gt "$retries" ]; then
        word=tries
        [ "$tries" = 1 ] && word=try
        fail "PR-Agent returned no parseable review after $tries $word (empty or unparseable model output)"
      fi
      wait_s=$((OUTPUT_BACKOFF * output_fails))
      note_title="PR-Agent retry" note_body="Try $tries returned no parseable review (empty or unparseable model output); retrying in ${wait_s}s."
      ;;
  esac
  # Start a retry only if it could finish, its kill grace and reads included.
  [ $(($(date +%s) - started + wait_s + try_seconds + KILL_GRACE + READ_SLACK)) -le "$deadline" ] \
    || fail "no review after try $tries, and another try would run past the ${deadline}s deadline"
  printf '::warning title=%s::%s\n' "$note_title" "$note_body"
  hold_traps
  sleep "$wait_s" &
  job=$!
  release_traps
  wait "$job"
  job=""
  # The head first: a review that lands after the head moved may be the new
  # head's run's, and must not pass for this one.
  same_head
  # The comment list can lag the post, so a try judged empty may have landed.
  if review_posted; then
    printf 'The review from try %s appeared after its check.\n' "$tries"
    exit 0
  fi
done
