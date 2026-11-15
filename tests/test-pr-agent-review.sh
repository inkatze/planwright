#!/bin/bash
# Tests for scripts/pr-agent-review.sh, the PR-Agent wrapper that retries a
# review the model left empty or unparseable. Stubs stand in for docker, gh,
# sleep and the per-try bound; no model API is ever called.
#
# Runs standalone under /bin/bash (the bash 3.2 floor).
set -eu
LC_ALL=C
export LC_ALL
unset CDPATH

here=$(cd "$(dirname "$0")" && pwd)
REAL="$here/../scripts/pr-agent-review.sh"
WORKFLOW="$here/../.github/workflows/pr-agent.yml"
failures=0

[ -x "$REAL" ] || {
  echo "FAIL: scripts/pr-agent-review.sh missing or not executable" >&2
  exit 1
}
# shellcheck source=tests/lib/poll-until.sh
. "$here/lib/poll-until.sh"
command -v jq >/dev/null 2>&1 || {
  echo "FAIL: jq is required to run the script's jq program" >&2
  exit 1
}

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
stub="$tmp/bin"
mkdir -p "$stub" "$tmp/scripts" "$tmp/real/scripts"
# One copy beside a stub bounded-run.sh, whose bound fires on request, and
# one beside the real helper.
SCRIPT="$tmp/scripts/pr-agent-review.sh"
cp "$REAL" "$SCRIPT"
cp "$REAL" "$here/../scripts/bounded-run.sh" "$tmp/real/scripts/"

HEAD_SHA=1111111111111111111111111111111111111111
MOVED_SHA=2222222222222222222222222222222222222222

# The docker stub plays one try per `run`, popping the case's next scenario:
#   good / clean   edit the persistent review comment (findings / no issues)
#   inc            posts a new incremental review comment
#   warned         posts a review although a fallback model logged empty output
#   lagged         posts a review the comment list shows only from its next read
#   empty parse transport yaml schema nomodel   a model-output failure
#   rate rate429 toomany ratelib rateword       a rate limit
#   ratempty       a rate limit and an empty output in one log
#   errored critical   an ERROR-level (coloured) or CRITICAL-level line
#   warnword       "ERROR" outside a level field; emptyerror both kinds of line
#   noise          a human and the run marker edit comments; empty output logged
#   quiet          nothing at all (PR-Agent's own silent skip)
#   exitN          exits N; exit1empty logs empty output, then exits 1
#   hang           sleeps past any bound; slowstart first takes 3s to create
# The failure scenarios post nothing. The gh stub runs the script's own --jq
# programs over $T/comments.json and a pull request built from $T/heads.
cat >"$stub/docker" <<'EOF'
#!/bin/sh
case "$1" in
  pull)
    [ "${PULL_FAIL:-0}" = 1 ] && { printf 'Error response from daemon: manifest unknown\n'; exit 1; }
    exit 0
    ;;
  rm)
    printf '%s\n' "$*" >>"$T/docker-rm.log"
    # Removing a container that exists ends its docker client, as the daemon does.
    [ -f "$T/created" ] && kill "$(cat "$T/run.pid")" 2>/dev/null
    exit 0
    ;;
  run) ;;
  *) exit 64 ;;
esac
printf '%s\n' "$*" >>"$T/docker-run.log"
step=$(sed -n 1p "$T/scen")
sed 1d "$T/scen" >"$T/scen.next" && mv "$T/scen.next" "$T/scen"
w='2026-11-14 00:00:00.000 | WARNING  | pr_agent.algo'
empty="$w.ai_handlers.litellm_ai_handler:_get_completion:3400 - Empty content in model response, finish_reason: length"
rate="$w.ai_handlers.litellm_ai_handler:_chat_completion_with_retry:3259 - Error during LLM inference: litellm.RateLimitError: RateLimitError: OpenrouterException - Rate limit exceeded"
# edit <jq program> [<file>]: rewrite the comment list, once per review posted.
edit() {
  jq --arg t "$(printf '2026-11-15T00:00:%02dZ' "$(($(wc -l <"$T/posted") + 1))")" "$1" "$T/comments.json" >"$T/comments.next" &&
    mv "$T/comments.next" "${2:-$T/comments.json}"
}
persist='(.[] | select(.id == 3) | .updated_at) = $t'
case "$step" in
  good | clean | warned)
    edit "$persist"
    printf 'post\n' >>"$T/posted"
    [ "$step" = warned ] && printf '%s\n' "$empty"
    [ "$step" = good ] && printf '%s\n' '2026-11-14 00:00:00.000 | INFO     | pr_agent.tools.pr_reviewer:_publish_key_issues_as_inline_comments:1600 - Published 2 review finding(s) as inline comments'
    ;;
  inc)
    edit '. + [{"id": 900, "user": {"login": "github-actions[bot]"}, "body": "## Incremental PR Reviewer Guide\n<!-- pr-agent:review:incremental -->", "updated_at": "2026-11-14T00:00:00Z"}]'
    printf 'post\n' >>"$T/posted"
    ;;
  lagged)
    edit "$persist" "$T/comments.pending"
    printf 'post\n' >>"$T/posted"
    printf '%s\n' "$empty"
    ;;
  empty) printf '%s\n' "$empty" "$w.pr_processing:retry_with_fallback_models:878 - Failed to generate prediction with openrouter/x/y" ;;
  parse)
    printf '%s\n' "$w.utils:load_yaml:1021 - Initial failure to parse AI prediction: expected '<document start>', but found '<scalar>'" \
      "$w.tools.pr_reviewer:_validate_review_schema:1290 - Review output failed schema validation"
    ;;
  transport) printf '%s\n' "$w.ai_handlers.litellm_ai_handler:_chat_completion_with_retry:3259 - Error during LLM inference: litellm.APIConnectionError: APIConnectionError: OpenrouterException - Response payload is not completed" ;;
  yaml) printf '%s\n' "$w.utils:load_yaml:1021 - Initial failure to parse AI prediction: expected '<document start>'" ;;
  schema) printf '%s\n' "$w.tools.pr_reviewer:_validate_review_schema:1290 - Review output failed schema validation" ;;
  nomodel) printf '%s\n' "$w.pr_processing:retry_with_fallback_models:878 - Failed to generate prediction with openrouter/x/y" ;;
  rate) printf '%s\n' "$rate" ;;
  ratelib) printf '%s\n' "$w.ai_handlers.litellm_ai_handler:_chat_completion_with_retry:3259 - Error during LLM inference: litellm.RateLimitError" ;;
  rateword) printf '%s\n' "$w.ai_handlers.litellm_ai_handler:_chat_completion_with_retry:3259 - Error during LLM inference: OpenrouterException - rate limit exceeded" ;;
  errored) printf '\033[32m2026-11-14 00:00:00.000\033[0m | \033[31m\033[1mERROR   \033[0m | pr_agent.tools.pr_reviewer:run:907 - Failed to review PR: boom\n' ;;
  rate429) printf '%s\n' "$w.ai_handlers.litellm_ai_handler:_chat_completion_with_retry:3259 - Error during LLM inference: OpenrouterException - {\"error\": {\"code\": 429}}" ;;
  toomany) printf '%s\n' "$w.ai_handlers.litellm_ai_handler:_chat_completion_with_retry:3259 - Error during LLM inference: 429 Too Many Requests" ;;
  ratempty) printf '%s\n' "$rate" "$empty" ;;
  noise)
    edit '(.[] | select(.id == 1 or .id == 2) | .updated_at) = $t'
    printf '%s\n' "$empty"
    ;;
  quiet) ;;
  exit1empty) printf '%s\n' "$empty"; exit 1 ;;
  exit*) exit "${step#exit}" ;;
  hang)
    printf '%s\n' "$$" >"$T/run.pid"
    : >"$T/created"
    exec /bin/sleep 300
    ;;
  slowstart)
    printf '%s\n' "$$" >"$T/run.pid"
    /bin/sleep 3
    : >"$T/created"
    /bin/sleep 300
    ;;
  critical) printf '%s\n' '2026-11-14 00:00:00.000 | CRITICAL | pr_agent.tools.pr_reviewer:run:900 - boom' ;;
  warnword)
    printf '%s\n' "$w.git_providers.github_provider:publish:1 - retrying after ERROR 502 from the API" \
      '| ERROR | handled |' 'foo | ERROR | bar'
    ;;
  emptyerror)
    printf '%s\n' "$empty"
    printf '\033[32m2026-11-14 00:00:00.000\033[0m | \033[31m\033[1mERROR   \033[0m | pr_agent.tools.pr_reviewer:run:907 - Failed to review PR: empty\n'
    ;;
  *) printf 'stub docker: no scenario left\n' >&2; exit 70 ;;
esac
EOF

# The head lookup pops $T/heads, keeping its last line once one remains. A
# comment read prints the --jq program's output over $T/comments.json, then
# lets a lagged post show; GH_COMMENTS_FAIL_FROM=<n> fails the nth read on.
cat >"$stub/gh" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >>"$T/gh.log"
case "$*" in
  *"/pulls/"*)
    [ "${GH_HEAD_FAIL:-0}" = 1 ] && exit 1
    sha=$(sed -n 1p "$T/heads")
    [ "$(wc -l <"$T/heads")" -gt 1 ] && { sed 1d "$T/heads" >"$T/heads.next" && mv "$T/heads.next" "$T/heads"; }
    while [ "$#" -gt 0 ]; do
      [ "$1" = --jq ] && { jq -nr --arg s "$sha" '{number: 7, head: {sha: $s, ref: "b"}}' | jq -r "$2" || exit 1; }
      shift
    done
    exit 0
    ;;
  *"/comments"*)
    printf 'read\n' >>"$T/reads"
    [ "$(wc -l <"$T/reads")" -ge "${GH_COMMENTS_FAIL_FROM:-999}" ] && exit 1
    [ "${GH_COMMENTS_NULL:-0}" = 1 ] && {
      jq '. + [{"id": 5, "user": {"login": "github-actions[bot]"}, "body": "<!-- pr-agent:review:full -->", "updated_at": null}]' \
        "$T/comments.json" >"$T/comments.next" && mv "$T/comments.next" "$T/comments.json"
    }
    while [ "$#" -gt 0 ]; do
      [ "$1" = --jq ] && { jq -r "$2" "$T/comments.json" || exit 1; }
      shift
    done
    [ -f "$T/comments.pending" ] && mv "$T/comments.pending" "$T/comments.json"
    exit 0
    ;;
esac
exit 64
EOF

cat >"$stub/sleep" <<'EOF'
#!/bin/sh
printf '%s\n' "$1" >>"$T/sleep.log"
EOF

# bounded-run.sh -k <grace> <seconds> <cmd>...: logs the bound, then runs the
# command unbounded, or stands in for the bound firing when BOUND_FIRES=1.
cat >"$tmp/scripts/bounded-run.sh" <<'EOF'
#!/bin/sh
printf '%s %s %s\n' "$1" "$2" "$3" >>"$T/bound.log"
[ "${BOUND_FIRES:-0}" = 1 ] && [ "$4" = docker ] && [ "$5" = run ] && exit 124
# STATUS_LOST=1 kills the try's subshell before it can record the status.
[ "${STATUS_LOST:-0}" = 1 ] && [ "$4" = docker ] && [ "$5" = run ] && { kill -9 "$PPID"; exit 0; }
shift 3
exec "$@"
EOF
chmod +x "$stub/docker" "$stub/gh" "$stub/sleep"
# The real helper's watcher needs the real sleep.
mkdir -p "$tmp/realbin"
cp "$stub/docker" "$stub/gh" "$tmp/realbin/"

printf '{}\n' >"$tmp/event.json"

# new_case <scenario words> <heads words>: a fresh $T.
new_case() {
  T=$(mktemp -d "$tmp/case.XXXXXX")
  # shellcheck disable=SC2086 # one line per word on purpose
  printf '%s\n' $1 >"$T/scen"
  # shellcheck disable=SC2086
  printf '%s\n' $2 >"$T/heads"
  : >"$T/posted"
  cat >"$T/comments.json" <<'EOF'
[
  {"id": 1, "user": {"login": "someone"}, "body": "quoting <!-- pr-agent:review:full -->", "updated_at": "2026-11-14T00:00:00Z"},
  {"id": 2, "user": {"login": "github-actions[bot]"}, "body": "<!-- pr-agent-run: id=1.1 head=x status=success -->", "updated_at": "2026-11-14T00:00:00Z"},
  {"id": 3, "user": {"login": "github-actions[bot]"}, "body": "## PR Reviewer Guide\n\n<!-- pr-agent:review:full -->", "updated_at": "2026-11-14T00:00:00Z"}
]
EOF
  # A PR's first review starts from no PR-Agent comment at all.
  [ "${EMPTY_BASELINE:-0}" = 1 ] && printf '[]\n' >"$T/comments.json"
  return 0
}

# run <scenario words> <heads words> -- <script args>: sets OUT and RC. The
# `--` is only a visual separator; it is consumed with the first two words.
run() {
  new_case "$1" "$2"
  shift 3
  RC=0
  OUT=$(env PATH="$stub:$PATH" T="$T" GITHUB_REPOSITORY=o/r \
    GITHUB_EVENT_PATH="$tmp/event.json" "CONFIG.MODEL=m" \
    "$SCRIPT" --image img@sha256:0 --pr 7 "$@" 2>&1) || RC=$?
}

lines() {
  if [ -f "$1" ]; then wc -l <"$1" | tr -d ' '; else printf '0\n'; fi
}

failed() {
  echo "FAIL: $1; exit $RC; output: $OUT" >&2
  failures=$((failures + 1))
}

ok() { echo "ok: $1"; }

has() {
  case "$OUT" in *"$2"*) return 0 ;; esac
  failed "$1: output lacks '$2'"
  return 1
}

lacks() {
  case "$OUT" in *"$2"*)
    failed "$1: output has '$2'"
    return 1
    ;;
  esac
  return 0
}

# expect <name> <rc> <tries> <posted> <sleeps>
expect() {
  [ "$RC" = "$2" ] || {
    failed "$1: want exit $2"
    return 1
  }
  [ "$(lines "$T/docker-run.log")" = "$3" ] || {
    failed "$1: want $3 tries, got $(lines "$T/docker-run.log")"
    return 1
  }
  [ "$(lines "$T/posted")" = "$4" ] || {
    failed "$1: want $4 reviews posted, got $(lines "$T/posted")"
    return 1
  }
  got=$(if [ -f "$T/sleep.log" ]; then tr '\n' ' ' <"$T/sleep.log"; fi)
  [ "$got" = "$5" ] || {
    failed "$1: want sleeps '$5', got '$got'"
    return 1
  }
  return 0
}

name="empty output then a good one: retried once, review posted once"
run "empty good" "$HEAD_SHA" -- --head "$HEAD_SHA" --retries 2
expect "$name" 0 2 1 "30 " && has "$name" "returned no parseable review" && ok "$name"

name="parse error every time: N retries, then the named failure, nothing posted"
run "parse parse parse" "$HEAD_SHA" -- --head "$HEAD_SHA" --retries 2
expect "$name" 1 3 0 "30 60 " \
  && has "$name" "PR-Agent returned no parseable review after 3 tries" && ok "$name"

name="the retry count comes from --retries"
run "empty empty" "$HEAD_SHA" -- --head "$HEAD_SHA" --retries 1
expect "$name" 1 2 0 "30 " \
  && has "$name" "PR-Agent returned no parseable review after 2 tries" && ok "$name"

name="retries 0 tries once and still fails visibly"
run "empty" "$HEAD_SHA" -- --head "$HEAD_SHA" --retries 0
expect "$name" 1 1 0 "" \
  && has "$name" "PR-Agent returned no parseable review after 1 try" && ok "$name"

name="a truncated model payload counts as unparseable output"
run "transport good" "$HEAD_SHA" -- --head "$HEAD_SHA" --retries 2
expect "$name" 0 2 1 "30 " && ok "$name"

for sig in yaml schema nomodel; do
  name="the $sig signature alone counts as unparseable output"
  run "$sig good" "$HEAD_SHA" -- --head "$HEAD_SHA" --retries 2
  expect "$name" 0 2 1 "30 " && ok "$name"
done

name="good output first time: no retry"
run "good" "$HEAD_SHA" -- --head "$HEAD_SHA" --retries 2
expect "$name" 0 1 1 "" && lacks "$name" "retry" && ok "$name"
if [ -f "$T/docker-rm.log" ]; then
  failed "a clean try's container is left to docker run --rm: rm $(cat "$T/docker-rm.log")"
else
  ok "a clean try's container is left to docker run --rm"
fi

name="a PR's first review, with no earlier PR-Agent comment, counts as posted"
EMPTY_BASELINE=1
run "inc empty" "$HEAD_SHA" -- --head "$HEAD_SHA" --retries 2
EMPTY_BASELINE=0
expect "$name" 0 1 1 "" && ok "$name"

name="a deliberate no-issues review is never retried"
run "clean empty" "$HEAD_SHA" -- --head "$HEAD_SHA" --retries 2
expect "$name" 0 1 1 "" && ok "$name"

name="a new incremental review comment counts as posted"
run "inc empty" "$HEAD_SHA" -- --head "$HEAD_SHA" --retries 2
expect "$name" 0 1 1 "" && ok "$name"

name="a review posted beside a model warning is never retried"
run "warned empty" "$HEAD_SHA" -- --head "$HEAD_SHA" --retries 2
expect "$name" 0 1 1 "" && ok "$name"

name="a review the comment list shows late is found before any retry"
run "lagged good" "$HEAD_SHA" -- --head "$HEAD_SHA" --retries 2
expect "$name" 0 1 1 "30 " && has "$name" "appeared after its check" && ok "$name"

name="a human's or the run marker's comment edit is not a review"
run "noise good" "$HEAD_SHA" -- --head "$HEAD_SHA" --retries 2
expect "$name" 0 2 1 "30 " && ok "$name"

name="the head moves between tries: stops"
run "empty good" "$MOVED_SHA" -- --head "$HEAD_SHA" --retries 2
expect "$name" 1 1 0 "30 " && has "$name" "head moved" && has "$name" "${MOVED_SHA:0:12}" && ok "$name"
if grep -qx -- 'api repos/o/r/pulls/7 --jq .head.sha' "$T/gh.log"; then
  ok "the head is read from this PR"
else
  failed "the head is read from this PR: gh.log: $(cat "$T/gh.log")"
fi

name="the head moving before the second retry stops too"
run "empty empty good" "$HEAD_SHA $MOVED_SHA" -- --head "$HEAD_SHA" --retries 2
expect "$name" 1 2 0 "30 60 " && has "$name" "head moved" && ok "$name"

name="an unreadable head between tries stops too"
GH_HEAD_FAIL=1
export GH_HEAD_FAIL
run "empty good" "$HEAD_SHA" -- --head "$HEAD_SHA" --retries 2
unset GH_HEAD_FAIL
expect "$name" 1 1 0 "30 " && has "$name" "could not confirm the PR head" && ok "$name"

name="a malformed head between tries stops too"
run "empty good" "not-a-sha" -- --head "$HEAD_SHA" --retries 2
expect "$name" 1 1 0 "30 " && has "$name" "could not confirm the PR head" && ok "$name"

name="rate limited: longer backoff, model-output budget untouched"
run "rate empty good" "$HEAD_SHA" -- --head "$HEAD_SHA" --retries 1
expect "$name" 0 3 1 "120 30 " && has "$name" "rate limited" && ok "$name"

name="a rate limit is retried even with no model-output retries"
run "rate good" "$HEAD_SHA" -- --head "$HEAD_SHA" --retries 0
expect "$name" 0 2 1 "120 " && ok "$name"

name="rate limits are bounded on their own"
run "rate rate rate" "$HEAD_SHA" -- --head "$HEAD_SHA" --retries 2
expect "$name" 1 3 0 "120 240 " && has "$name" "past its 2 rate-limit retries" && ok "$name"

name="a 429 code and Too Many Requests read as rate limits"
run "rate429 toomany good" "$HEAD_SHA" -- --head "$HEAD_SHA" --retries 0
expect "$name" 0 3 1 "120 240 " && ok "$name"

name="RateLimitError and rate limit exceeded each read as rate limits"
run "ratelib rateword good" "$HEAD_SHA" -- --head "$HEAD_SHA" --retries 0
expect "$name" 0 3 1 "120 240 " && ok "$name"

name="a rate limit outranks an empty output in the same try"
run "ratempty good" "$HEAD_SHA" -- --head "$HEAD_SHA" --retries 0
expect "$name" 0 2 1 "120 " && ok "$name"

name="no head given: one try, no retry, still a visible failure"
run "empty good" "$HEAD_SHA" -- --retries 2
expect "$name" 1 1 0 "" && has "$name" "PR-Agent returned no parseable review after 1 try" \
  && has "$name" "retries off" && ok "$name"

name="no head given: a rate limit is not retried either"
run "rate good" "$HEAD_SHA" -- --retries 2
expect "$name" 1 1 0 "" && has "$name" "past its 0 rate-limit retries" && ok "$name"

name="no review and no logged failure is PR-Agent's own skip"
run "quiet good" "$HEAD_SHA" -- --head "$HEAD_SHA" --retries 2
expect "$name" 0 1 0 "" && has "$name" "its own skip" && ok "$name"

name="a retry that posts nothing and logs nothing is a failure, never a skip"
run "empty quiet good" "$HEAD_SHA" -- --head "$HEAD_SHA" --retries 2
expect "$name" 1 2 0 "30 " && has "$name" "a retry after a failed try, posted no review" && ok "$name"

name="an ERROR-level log line with no review fails without a retry"
run "errored good" "$HEAD_SHA" -- --head "$HEAD_SHA" --retries 2
expect "$name" 1 1 0 "" && has "$name" "logged an error on try 1" && ok "$name"

name="a CRITICAL-level log line with no review fails without a retry"
run "critical good" "$HEAD_SHA" -- --head "$HEAD_SHA" --retries 2
expect "$name" 1 1 0 "" && has "$name" "logged an error on try 1" && ok "$name"

name="ERROR outside a log line's level field is not an error"
run "warnword good" "$HEAD_SHA" -- --head "$HEAD_SHA" --retries 2
expect "$name" 0 1 0 "" && has "$name" "its own skip" && ok "$name"

name="an empty output beside an ERROR line is retried as model output"
run "emptyerror good" "$HEAD_SHA" -- --head "$HEAD_SHA" --retries 2
expect "$name" 0 2 1 "30 " && ok "$name"

name="a non-zero PR-Agent exit fails without a retry"
run "exit3 good" "$HEAD_SHA" -- --head "$HEAD_SHA" --retries 2
expect "$name" 1 1 0 "" && has "$name" "exited 3" && ok "$name"
# Reads the case above.
name="a failed docker client's container is removed by name"
if [ "$(cat "$T/docker-rm.log")" = "rm -f $(sed -n 's/.*--name \([^ ]*\) .*/\1/p' "$T/docker-run.log")" ]; then
  ok "$name"
else
  failed "$name: rm $(cat "$T/docker-rm.log")"
fi

name="a non-zero exit outranks a model-output failure in its log"
run "exit1empty good" "$HEAD_SHA" -- --head "$HEAD_SHA" --retries 2
expect "$name" 1 1 0 "" && has "$name" "exited 1" && ok "$name"

name="a try past its bound fails without a retry and removes the container"
BOUND_FIRES=1
export BOUND_FIRES
run "good good" "$HEAD_SHA" -- --head "$HEAD_SHA" --retries 2 --try-seconds 5
unset BOUND_FIRES
if [ "$RC" = 1 ] && [ "$(lines "$T/docker-rm.log")" = 1 ] && [ "$(lines "$T/posted")" = 0 ] \
  && grep -q -- '-k 30 5' "$T/bound.log"; then
  has "$name" "timed out" && ok "$name"
else
  failed "$name: want exit 1, one container removal, nothing posted, the bound passed"
fi

name="a try that never records its exit status fails by name"
STATUS_LOST=1
export STATUS_LOST
run "good" "$HEAD_SHA" -- --head "$HEAD_SHA" --retries 2
unset STATUS_LOST
expect "$name" 1 0 0 "" && has "$name" "ended without recording its exit status" && ok "$name"

name="each try is bounded at 600s by default and the pull at 300s"
run "good" "$HEAD_SHA" -- --head "$HEAD_SHA"
if [ "$RC" = 0 ] && grep -qx -- '-k 30 600' "$T/bound.log" && grep -qx -- '-k 30 300' "$T/bound.log"; then
  ok "$name"
else
  failed "$name: bound.log: $(cat "$T/bound.log")"
fi

name="no retry starts that could end past the deadline"
run "empty empty good" "$HEAD_SHA" -- --head "$HEAD_SHA" --retries 2 --deadline-seconds 740
expect "$name" 1 2 0 "30 " && has "$name" "740s deadline" && ok "$name"

name="an image that will not pull fails before any try"
PULL_FAIL=1
export PULL_FAIL
run "good" "$HEAD_SHA" -- --head "$HEAD_SHA"
unset PULL_FAIL
expect "$name" 1 0 0 "" && has "$name" "could not pull img@sha256:0: Error response" && ok "$name"

name="an unreadable comment list after a try fails after its re-reads, never retrying"
GH_COMMENTS_FAIL_FROM=2
export GH_COMMENTS_FAIL_FROM
run "good good" "$HEAD_SHA" -- --head "$HEAD_SHA" --retries 2
unset GH_COMMENTS_FAIL_FROM
expect "$name" 1 1 1 "5 5 " && has "$name" "could not read the PR's comments" && ok "$name"

name="an unreadable comment list before the first try fails with no try"
GH_COMMENTS_FAIL_FROM=1
export GH_COMMENTS_FAIL_FROM
run "good" "$HEAD_SHA" -- --head "$HEAD_SHA"
unset GH_COMMENTS_FAIL_FROM
expect "$name" 1 0 0 "5 5 " && has "$name" "could not read the PR's comments" && ok "$name"

name="a review comment with no updated_at is a failure, never a pass"
GH_COMMENTS_NULL=1
export GH_COMMENTS_NULL
run "good" "$HEAD_SHA" -- --head "$HEAD_SHA"
unset GH_COMMENTS_NULL
expect "$name" 1 0 0 "" && has "$name" "shape" && ok "$name"

name="the comment read pages through every comment"
run "good" "$HEAD_SHA" -- --head "$HEAD_SHA"
if grep -q -- '--paginate repos/o/r/issues/7/comments?per_page=100' "$T/gh.log"; then
  ok "$name"
else
  failed "$name: gh.log: $(cat "$T/gh.log")"
fi

name="PR-Agent's settings, the token and the event reach the container by name"
new_case "good" "$HEAD_SHA"
RC=0
OUT=$(env PATH="$stub:$PATH" T="$T" GITHUB_REPOSITORY=o/r GITHUB_EVENT_PATH="$tmp/event.json" \
  "CONFIG.MODEL=m" "OPENROUTER.KEY=sekrit" "GITHUB_ACTION_CONFIG.PR_ACTIONS=x" "PR_REVIEWER.NUM_MAX_FINDINGS=3" \
  GITHUB_TOKEN=tok-value-9z "$SCRIPT" --image img@sha256:0 --pr 7 2>&1) || RC=$?
args=$(cat "$T/docker-run.log")
missing=""
for want in "-e CONFIG.MODEL" "-e OPENROUTER.KEY" "-e GITHUB_ACTION_CONFIG.PR_ACTIONS" \
  "-e PR_REVIEWER.NUM_MAX_FINDINGS" "-e GITHUB_TOKEN" "-e GITHUB_EVENT_PATH=/github/workflow/event.json" \
  "-v $tmp/event.json:/github/workflow/event.json:ro img@sha256:0"; do
  case "$args" in *"$want"*) ;; *) missing="$missing [$want]" ;; esac
done
case "$args" in *sekrit* | *tok-value-9z*) missing="$missing [a value in argv]" ;; esac
if [ "$RC" = 0 ] && [ -z "$missing" ]; then ok "$name"; else failed "$name: missing$missing in: $args"; fi

name="the real bounded-run.sh runs a try and ends one past its bound"
new_case "good" "$HEAD_SHA"
RC=0
OUT=$(env PATH="$tmp/realbin:$PATH" T="$T" GITHUB_REPOSITORY=o/r GITHUB_EVENT_PATH="$tmp/event.json" \
  "$tmp/real/scripts/pr-agent-review.sh" --image img --pr 7 2>&1) || RC=$?
if [ "$RC" = 0 ]; then
  new_case "hang" "$HEAD_SHA"
  RC=0
  OUT=$(env PATH="$tmp/realbin:$PATH" T="$T" GITHUB_REPOSITORY=o/r GITHUB_EVENT_PATH="$tmp/event.json" \
    "$tmp/real/scripts/pr-agent-review.sh" --image img --pr 7 --try-seconds 1 2>&1) || RC=$?
  if [ "$RC" = 1 ]; then has "$name" "timed out after 1s" && ok "$name"; else failed "$name: the hang"; fi
else
  failed "$name: the good try"
fi

# A runner cancel can signal the wrapper's shell alone; bash defers a trap
# until a foreground job ends, which would leave the container running.
name="a TERM to the wrapper alone removes the running container at once"
new_case "hang" "$HEAD_SHA"
env PATH="$stub:$PATH" T="$T" GITHUB_REPOSITORY=o/r GITHUB_EVENT_PATH="$tmp/event.json" \
  "$SCRIPT" --image img --pr 7 >"$T/out" 2>&1 &
spid=$!
container="pr-agent-$spid-1"
if poll_until --what "the try to start" -- test -s "$T/run.pid"; then
  kill -TERM "$spid"
  if poll_until --what "the wrapper to exit on TERM" -- pid_gone "$spid"; then
    RC=0
    wait "$spid" || RC=$?
    OUT=$(cat "$T/out")
    if [ "$RC" = 143 ] && grep -qx "rm -f $container" "$T/docker-rm.log"; then
      ok "$name"
    else
      failed "$name: want exit 143 and the container removed; rm: $(cat "$T/docker-rm.log")"
    fi
  else
    kill "$(cat "$T/run.pid")"
    RC=0
    wait "$spid" || RC=$?
    OUT=$(cat "$T/out")
    failed "$name: the wrapper outlived TERM while its try ran"
  fi
else
  kill -TERM "$spid"
  RC=0
  wait "$spid" || RC=$?
  OUT=$(cat "$T/out")
  failed "$name: the try never started"
fi
kill "$(cat "$T/run.pid")" 2>/dev/null || :

# A cancel before docker has created the container: removing it then finds
# nothing, so the docker client itself must end before the wrapper does.
name="a TERM before the container exists ends the docker client too"
new_case "slowstart" "$HEAD_SHA"
env PATH="$stub:$PATH" T="$T" GITHUB_REPOSITORY=o/r GITHUB_EVENT_PATH="$tmp/event.json" \
  "$SCRIPT" --image img --pr 7 >"$T/out" 2>&1 &
spid=$!
if poll_until --what "the try to start" -- test -s "$T/run.pid"; then
  kill -TERM "$spid"
  if poll_until --what "the wrapper to exit on TERM" -- pid_gone "$spid"; then
    RC=0
    wait "$spid" || RC=$?
    OUT=$(cat "$T/out")
    if [ "$RC" = 143 ] && ! kill -0 "$(cat "$T/run.pid")" 2>/dev/null; then
      ok "$name"
    else
      failed "$name: want exit 143 with the docker client gone"
    fi
  else
    RC=0
    failed "$name: the wrapper outlived TERM"
  fi
else
  kill -TERM "$spid"
  RC=0
  failed "$name: the try never started"
fi
kill "$(cat "$T/run.pid")" 2>/dev/null || :

for bad in "--retries x|--retries must be" "--retries|--retries needs a value" "--retries 100|up to 99" \
  "--pr 0|--pr must be" "--pr 07|--pr must be" "--pr abc|--pr must be" "--pr|--pr needs a value" \
  "--try-seconds 0|--try-seconds must be" "--try-seconds 1000000|--try-seconds must be" \
  "--deadline-seconds x|--deadline-seconds must be" "--head abc123|--head must be a full" \
  "--head ABCDEF1111111111111111111111111111111111|--head must be a full" \
  "--head 111111111111111111111111111111111111111|--head must be a full" \
  "--head 11111111111111111111111111111111111111111|--head must be a full" \
  "--head g111111111111111111111111111111111111111|--head must be a full" "--bogus|unknown argument: --bogus"; do
  flags=${bad%%|*}
  want=${bad#*|}
  name="usage error: $flags"
  RC=0
  # shellcheck disable=SC2086 # the flags split on purpose
  OUT=$(env PATH="$stub:$PATH" T="$tmp" GITHUB_REPOSITORY=o/r GITHUB_EVENT_PATH="$tmp/event.json" \
    "$SCRIPT" --image img --pr 7 $flags 2>&1) || RC=$?
  if [ "$RC" = 2 ]; then has "$name" "$want" && ok "$name"; else failed "$name: want exit 2"; fi
done

name="usage error: no --image"
RC=0
OUT=$(env PATH="$stub:$PATH" GITHUB_REPOSITORY=o/r GITHUB_EVENT_PATH="$tmp/event.json" "$SCRIPT" --pr 7 2>&1) || RC=$?
if [ "$RC" = 2 ]; then has "$name" "--image is required" && ok "$name"; else failed "$name: want exit 2"; fi

name="usage error: no GITHUB_REPOSITORY"
RC=0
OUT=$(env -u GITHUB_REPOSITORY PATH="$stub:$PATH" GITHUB_EVENT_PATH="$tmp/event.json" "$SCRIPT" --image i --pr 7 2>&1) || RC=$?
if [ "$RC" = 2 ]; then has "$name" "GITHUB_REPOSITORY is not set" && ok "$name"; else failed "$name: want exit 2"; fi

name="usage error: an unreadable event file"
RC=0
OUT=$(env PATH="$stub:$PATH" GITHUB_REPOSITORY=o/r GITHUB_EVENT_PATH="$tmp/no-such.json" "$SCRIPT" --image i --pr 7 2>&1) || RC=$?
if [ "$RC" = 2 ]; then has "$name" "GITHUB_EVENT_PATH is not a readable file" && ok "$name"; else failed "$name: want exit 2"; fi

# The workflow hands the wrapper its values, and its step limit sits between
# the wrapper's deadline and the job's limit, so the wrapper's named failure
# fires first and the run marker still posts.
name="the workflow's Review step wires the wrapper and outlasts its deadline"
review=$(awk '/^      - name: / { on = ($0 == "      - name: Review") } on' "$WORKFLOW")
step_min=$(printf '%s\n' "$review" | sed -n 's/^        timeout-minutes: *\([0-9][0-9]*\)$/\1/p')
job_min=$(sed -n 's/^    timeout-minutes: *\([0-9][0-9]*\)$/\1/p' "$WORKFLOW")
deadline=$(printf '%s\n' "$review" | sed -n 's/.*--deadline-seconds \([0-9][0-9]*\).*/\1/p')
missing=""
# shellcheck disable=SC2016 # the workflow's literal text
for want in 'scripts/pr-agent-review.sh --image "$PR_AGENT_IMAGE"' '--pr "$PR"' '--head "$HEAD_SHA"' \
  '--retries "$PR_AGENT_REVIEW_RETRIES"' 'GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}' \
  'PR_AGENT_IMAGE: pragent/pr-agent@sha256:' 'PR: ${{ github.event.pull_request.number }}' \
  'HEAD_SHA: ${{ steps.head.outputs.sha }}' "PR_AGENT_REVIEW_RETRIES: \${{ vars.PR_AGENT_REVIEW_RETRIES || '2' }}" \
  'GITHUB_ACTION_CONFIG.ENABLE_OUTPUT: "false"'; do
  case "$review" in *"$want"*) ;; *) missing="$missing [$want]" ;; esac
done
grep -q '^          sparse-checkout: scripts$' "$WORKFLOW" || missing="$missing [sparse-checkout: scripts]"
# shellcheck disable=SC2016 # the workflow's literal text
grep -qF "STATUS: \${{ steps.review.outcome == 'skipped' && 'failure' || steps.review.outcome }}" "$WORKFLOW" \
  || missing="$missing [the marker's skipped-to-failure status]"
if [ -z "$missing" ] && [ -n "$step_min" ] && [ -n "$job_min" ] && [ -n "$deadline" ] \
  && [ $((step_min * 60)) -ge $((deadline + 120)) ] && [ "$step_min" -lt "$job_min" ]; then
  ok "$name"
else
  failed "$name: missing$missing; step ${step_min:-?} min, job ${job_min:-?} min, deadline ${deadline:-?}s"
fi

if [ "$failures" -ne 0 ]; then
  echo "$failures failure(s)" >&2
  exit 1
fi
echo "all pr-agent-review tests passed"
