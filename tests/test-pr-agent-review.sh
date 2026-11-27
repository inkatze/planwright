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
mkdir -p "$stub" "$tmp/scripts" "$tmp/real/scripts" "$tmp/runner-temp"
# The wrapper makes its scratch under RUNNER_TEMP, which a CI job sets to a
# directory this test may not write; every case gets one it owns.
RUNNER_TEMP="$tmp/runner-temp"
export RUNNER_TEMP
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
#   postexit3      posts a review, then exits 3
#   warned         posts a review although a fallback model logged empty output
#   lagged         posts a review the comment list shows only from its next read
#   empty parse transport yaml schema nomodel   a model-output failure
#   rate rate429 toomany ratelib rateword       a rate limit
#   ratempty       a rate limit and an empty output in one log
#   errored critical colourcritical   an ERROR- or CRITICAL-level line
#   warnword       "ERROR" outside a level field; emptyerror and rateerror an
#                  ERROR line beside an empty output or a rate limit
#   noise          a human and the run marker edit comments; empty output logged
#   quiet          nothing at all (PR-Agent's own silent skip)
#   exitN          exits N; exit1empty logs empty output, then exits 1
#   recorded       a model failure PR-Agent records, then exits 1 (its
#                  _fail_on_recorded_tool_error path, seen live)
#   authfail       the provider refuses the key, then exits 1
#   hang slowstart stubborn creating latestart   cancel cases (see cancel_case)
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
    # Removing a container that exists ends its docker client, even one that
    # ignores TERM, as the daemon does.
    if [ -f "$T/created" ]; then
      printf '%s created\n' "$*" >>"$T/docker-rm.log"
      kill -9 "$(cat "$T/run.pid")" 2>/dev/null
    else
      printf '%s\n' "$*" >>"$T/docker-rm.log"
    fi
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
  postexit3)
    edit "$persist"
    printf 'post\n' >>"$T/posted"
    exit 3
    ;;
  inc)
    edit '. +[{"id": 900, "user": {"login": "github-actions[bot]"}, "body": "## Incremental PR Reviewer Guide\n<!-- pr-agent:review:incremental -->", "updated_at": "2026-11-14T00:00:00Z"}]'
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
  recorded)
    printf '%s\n' "$w.ai_handlers.litellm_ai_handler:_chat_completion_with_retry:3259 - Error during LLM inference: Empty content in model response (finish_reason: length)" \
      "$w.pr_processing:retry_with_fallback_models:878 - Failed to generate prediction with openrouter/x/y"
    printf '\033[32m2026-11-15 05:48:54.118\033[0m | \033[31m\033[1mERROR   \033[0m | pr_agent.tools.pr_reviewer:run:502 - Failed to review PR: Failed to generate prediction with any model of [x, y]\n'
    printf '%s\n' '2026-11-15 05:48:54.118 | WARNING  | __main__:_fail_on_recorded_tool_error:113 - Tool reported success but recorded a failure; failing the action'
    exit 1
    ;;
  authfail)
    printf '%s\n' "$w.ai_handlers.litellm_ai_handler:_chat_completion_with_retry:3259 - Error during LLM inference: litellm.AuthenticationError: AuthenticationError: OpenrouterException - No auth credentials found" \
      "$w.pr_processing:retry_with_fallback_models:878 - Failed to generate prediction with openrouter/x/y"
    exit 1
    ;;
  exit*) exit "${step#exit}" ;;
  hang)
    : >"$T/created"
    printf '%s\n' "$$" >"$T/run.pid"
    exec /bin/sleep 300
    ;;
  slowstart)
    printf '%s\n' "$$" >"$T/run.pid"
    while [ ! -f "$T/go" ]; do /bin/sleep 0.1; done
    : >"$T/created"
    exec /bin/sleep 300
    ;;
  latestart)
    trap '' TERM
    printf '%s\n' "$$" >"$T/run.pid"
    /bin/sleep 1
    : >"$T/created"
    while :; do /bin/sleep 0.1; done
    ;;
  stubborn)
    trap '' TERM
    : >"$T/created"
    printf '%s\n' "$$" >"$T/run.pid"
    while :; do /bin/sleep 0.1; done
    ;;
  creating)
    trap '/bin/sleep 1; : >"$T/created"; exit 143' TERM
    printf '%s\n' "$$" >"$T/run.pid"
    while :; do /bin/sleep 0.1; done
    ;;
  critical) printf '%s\n' '2026-11-14 00:00:00.000 | CRITICAL | pr_agent.tools.pr_reviewer:run:900 - boom' ;;
  colourcritical) printf '\033[32m2026-11-14 00:00:00.000\033[0m | \033[41m\033[1mCRITICAL\033[0m | pr_agent.tools.pr_reviewer:run:900 - boom\n' ;;
  warnword)
    printf '%s\n' "$w.git_providers.github_provider:publish:1 - retrying after ERROR 502 from the API" \
      '| ERROR | handled |' 'foo | ERROR | bar'
    ;;
  rateerror)
    printf '%s\n' "$rate"
    printf '\033[32m2026-11-14 00:00:00.000\033[0m | \033[31m\033[1mERROR   \033[0m | pr_agent.tools.pr_reviewer:run:907 - Failed to review PR: 429\n'
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

# Backoffs only log; the exit trap's one-second removal cadence waits a little,
# so a cancel case does not spin while its stub client lives. SLEEP_REAL=1
# makes a backoff really wait, as the client of a cancel case.
cat >"$stub/sleep" <<'EOF'
#!/bin/sh
printf '%s\n' "$1" >>"$T/sleep.log"
[ "$1" = 1 ] && exec /bin/sleep 0.05
if [ "${SLEEP_REAL:-0}" = 1 ] && [ "$1" -ge 30 ]; then
  printf '%s\n' "$$" >"$T/run.pid"
  exec /bin/sleep "$1"
fi
exit 0
EOF

# bounded-run.sh -k <grace> <seconds> <cmd>...: logs the bound, then runs the
# command unbounded, or stands in for the bound firing: BOUND_FIRES=1 before
# the command runs, BOUND_FIRES=post after it has.
cat >"$tmp/scripts/bounded-run.sh" <<'EOF'
#!/bin/sh
printf '%s %s %s\n' "$1" "$2" "$3" >>"$T/bound.log"
[ "${BOUND_FIRES:-0}" = 1 ] && [ "$4" = docker ] && [ "$5" = run ] && exit 124
shift 3
if [ "${BOUND_FIRES:-0}" = post ] && [ "$1" = docker ] && [ "$2" = run ]; then
  "$@"
  exit 124
fi
exec "$@"
EOF

# tee runs as itself, unless TEE_FAIL=early makes it die before copying
# anything or TEE_FAIL=late after creating the log.
real_tee=$(command -v tee)
# shellcheck disable=SC2016 # the stub's own text
printf '%s\n' '#!/bin/sh' '[ "${TEE_FAIL:-}" = early ] && exit 1' \
  '[ "${TEE_FAIL:-}" = late ] && { : >"$1"; exit 1; }' "exec '$real_tee' \"\$@\"" >"$stub/tee"
chmod +x "$stub/docker" "$stub/gh" "$stub/sleep" "$stub/tee"
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
  mkdir "$T/scratch"
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
  OUT=$(env PATH="$stub:$PATH" T="$T" GITHUB_REPOSITORY=o/r RUNNER_TEMP="$T/scratch" \
    GITHUB_EVENT_PATH="$tmp/event.json" "CONFIG__MODEL=m" \
    "$SCRIPT" --image img@sha256:0 --pr 7 "$@" 2>&1) || RC=$?
}

# scratch_gone <name>: the run left nothing in its scratch directory.
scratch_gone() {
  if [ -z "$(ls -A "$T/scratch")" ]; then ok "$1"; else failed "$1: left $(ls -A "$T/scratch")"; fi
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

name="a late review that shows only after the head moved does not pass for this run"
run "lagged good" "$MOVED_SHA" -- --head "$HEAD_SHA" --retries 2
expect "$name" 1 1 1 "30 " && has "$name" "head moved" && lacks "$name" "appeared after its check" && ok "$name"

name="a posted review outranks the try's non-zero exit"
run "postexit3 empty" "$HEAD_SHA" -- --head "$HEAD_SHA" --retries 2
expect "$name" 0 1 1 "" && ok "$name"

name="a posted review outranks the try's bound firing after it"
BOUND_FIRES=post
export BOUND_FIRES
run "good empty" "$HEAD_SHA" -- --head "$HEAD_SHA" --retries 2
unset BOUND_FIRES
expect "$name" 0 1 1 "" && ok "$name"

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

for crit in critical colourcritical; do
  name="a $crit log line with no review fails without a retry"
  run "$crit good" "$HEAD_SHA" -- --head "$HEAD_SHA" --retries 2
  expect "$name" 1 1 0 "" && has "$name" "logged an error on try 1" && ok "$name"
done

name="ERROR outside a log line's level field is not an error"
run "warnword good" "$HEAD_SHA" -- --head "$HEAD_SHA" --retries 2
expect "$name" 0 1 0 "" && has "$name" "its own skip" && ok "$name"

name="an empty output beside an ERROR line is retried as model output"
run "emptyerror good" "$HEAD_SHA" -- --head "$HEAD_SHA" --retries 2
expect "$name" 0 2 1 "30 " && ok "$name"

name="a rate limit beside an ERROR line backs off as a rate limit"
run "rateerror good" "$HEAD_SHA" -- --head "$HEAD_SHA" --retries 0
expect "$name" 0 2 1 "120 " && ok "$name"

name="a run that posts leaves no scratch behind"
run "good" "$HEAD_SHA" -- --head "$HEAD_SHA"
scratch_gone "$name"

name="a run that fails leaves no scratch behind"
run "parse parse parse" "$HEAD_SHA" -- --head "$HEAD_SHA" --retries 2
scratch_gone "$name"

name="a non-zero PR-Agent exit fails without a retry"
run "exit3 good" "$HEAD_SHA" -- --head "$HEAD_SHA" --retries 2
expect "$name" 1 1 0 "" && has "$name" "exited 3" && ok "$name"
# Reads docker-rm.log and docker-run.log left by the exit3 case above; keep
# the two adjacent.
name="a failed docker client's container is removed by name"
if [ "$(cat "$T/docker-rm.log")" = "rm -f $(sed -n 's/.*--name \([^ ]*\) .*/\1/p' "$T/docker-run.log")" ]; then
  ok "$name"
else
  failed "$name: rm $(cat "$T/docker-rm.log")"
fi

for when in early late; do
  name="a try whose log tee lost ($when) fails, never passing as a skip"
  TEE_FAIL=$when
  export TEE_FAIL
  run "quiet good" "$HEAD_SHA" -- --head "$HEAD_SHA" --retries 2
  unset TEE_FAIL
  expect "$name" 1 1 0 "" && has "$name" "could not keep the log of try 1" && ok "$name"
done

# PR-Agent exits 1 when it records a model failure, so the exit alone does
# not say whether a retry can help; the log does.
name="a non-zero exit with a model-output failure in its log is retried"
run "exit1empty good" "$HEAD_SHA" -- --head "$HEAD_SHA" --retries 2
expect "$name" 0 2 1 "30 " && ok "$name"

name="PR-Agent's recorded-failure exit after an empty chain is retried"
run "recorded good" "$HEAD_SHA" -- --head "$HEAD_SHA" --retries 2
expect "$name" 0 2 1 "30 " && has "$name" "returned no parseable review" && ok "$name"

name="PR-Agent's recorded-failure exit every time fails by name after the retries"
run "recorded recorded recorded" "$HEAD_SHA" -- --head "$HEAD_SHA" --retries 2
expect "$name" 1 3 0 "30 60 " && has "$name" "PR-Agent returned no parseable review after 3 tries" && ok "$name"

name="a refused provider key fails at once, never retried"
run "authfail good" "$HEAD_SHA" -- --head "$HEAD_SHA" --retries 2
expect "$name" 1 1 0 "" && has "$name" "model provider refused" && ok "$name"

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
  "CONFIG__MODEL=m" "OPENROUTER__KEY=sekrit" "GITHUB_ACTION_CONFIG__PR_ACTIONS=x" "PR_REVIEWER__NUM_MAX_FINDINGS=3" \
  GITHUB_TOKEN=tok-value-9z "$SCRIPT" --image img@sha256:0 --pr 7 2>&1) || RC=$?
if [ -f "$T/docker-run.log" ]; then args=$(cat "$T/docker-run.log"); else args="(docker run never ran)"; fi
missing=""
for want in "-e CONFIG__MODEL" "-e OPENROUTER__KEY" "-e GITHUB_ACTION_CONFIG__PR_ACTIONS" \
  "-e PR_REVIEWER__NUM_MAX_FINDINGS" "-e GITHUB_TOKEN" "-e GITHUB_EVENT_PATH=/github/workflow/event.json" \
  "-v $tmp/event.json:/github/workflow/event.json:ro img@sha256:0"; do
  case "$args" in *"$want"*) ;; *) missing="$missing [$want]" ;; esac
done
# PR-Agent's action entrypoint reads these; without GITHUB_EVENT_NAME, say,
# it would skip silently, and a quiet first try passes.
for runner_var in GITHUB_TOKEN GITHUB_EVENT_NAME GITHUB_REPOSITORY GITHUB_API_URL GITHUB_SERVER_URL \
  GITHUB_GRAPHQL_URL GITHUB_SHA GITHUB_REF GITHUB_HEAD_REF GITHUB_BASE_REF GITHUB_ACTOR \
  GITHUB_RUN_ID GITHUB_RUN_ATTEMPT GITHUB_ACTIONS CI; do
  case "$args " in *"-e $runner_var "*) ;; *) missing="$missing [-e $runner_var]" ;; esac
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

# A runner cancel can signal the wrapper's shell alone, at any moment of a try.
# The docker stub's cancel scenarios:
#   hang           creates its container, then sleeps past any bound
#   slowstart      creates nothing until $T/go appears (never, in its test)
#   stubborn       creates its container and ignores TERM
#   creating       is still creating its container when TERM arrives
#   latestart      ignores TERM and creates its container a second later

# cancel_case <scenario> [<script arg>...]: start a try, TERM the wrapper once
# the stub client runs, and set RC, OUT and CANCEL_CONTAINER; returns 1 when
# the wrapper outlived the TERM or the try never started. A stuck wrapper and
# the stub client are killed either way, so a failing case neither hangs the
# suite nor leaves a sleeper behind. CC_BIN and CC_SCRIPT swap in the real
# bounded-run.sh copy.
cancel_case() {
  new_case "$1" "$HEAD_SHA"
  cc_what=$1
  shift
  env PATH="${CC_BIN:-$stub}:$PATH" T="$T" GITHUB_REPOSITORY=o/r GITHUB_EVENT_PATH="$tmp/event.json" \
    RUNNER_TEMP="$T/scratch" "${CC_SCRIPT:-$SCRIPT}" --image img --pr 7 "$@" >"$T/out" 2>&1 &
  cc_pid=$!
  CANCEL_CONTAINER="pr-agent-$cc_pid-1"
  cc_rc=0
  poll_until --what "the $cc_what try to start" -- test -s "$T/run.pid" || cc_rc=1
  kill -TERM "$cc_pid"
  if [ "$cc_rc" = 0 ]; then
    poll_until --what "the wrapper to exit on TERM" -- pid_gone "$cc_pid" || cc_rc=1
  fi
  [ "$cc_rc" = 0 ] || kill -9 "$cc_pid" 2>/dev/null || :
  # run.pid may not exist when the try never started.
  kill -9 "$(cat "$T/run.pid" 2>/dev/null)" 2>/dev/null || :
  RC=0
  wait "$cc_pid" || RC=$?
  OUT=$(cat "$T/out")
  return "$cc_rc"
}

name="a TERM while the container runs removes it at once"
if cancel_case hang; then
  if [ "$RC" = 143 ] && grep -qx "rm -f $CANCEL_CONTAINER created" "$T/docker-rm.log"; then
    ok "$name"
  else
    failed "$name: want exit 143 and the container removed; rm: $(cat "$T/docker-rm.log")"
  fi
else
  failed "$name: the wrapper outlived TERM, or the try never started"
fi

name="a TERM before the container exists ends the docker client too"
if cancel_case slowstart && [ "$RC" = 143 ]; then
  ok "$name"
else
  failed "$name: want a prompt exit 143 with the client ended"
fi

# docker run passes the TERM to a container whose PID 1 may ignore it; the
# removal must not wait for the client.
name="a TERM removes a container whose client ignores the TERM"
if cancel_case stubborn && [ "$RC" = 143 ] && grep -qx "rm -f $CANCEL_CONTAINER created" "$T/docker-rm.log"; then
  ok "$name"
else
  failed "$name: want a prompt exit 143 and the container removed; rm: $(cat "$T/docker-rm.log")"
fi
scratch_gone "a cancel leaves no scratch behind"

name="through the real bounded-run.sh, a TERM removes a container whose client ignores it"
CC_BIN="$tmp/realbin" CC_SCRIPT="$tmp/real/scripts/pr-agent-review.sh"
if cancel_case stubborn && [ "$RC" = 143 ] && grep -qx "rm -f $CANCEL_CONTAINER created" "$T/docker-rm.log"; then
  ok "$name"
else
  failed "$name: want a prompt exit 143 and the container removed; rm: $(cat "$T/docker-rm.log")"
fi
unset CC_BIN CC_SCRIPT

name="a container created after the first removal is removed while its client lives"
if cancel_case latestart && [ "$RC" = 143 ] && grep -qx "rm -f $CANCEL_CONTAINER created" "$T/docker-rm.log"; then
  ok "$name"
else
  failed "$name: want a prompt exit 143 and a removal after the creation; rm: $(cat "$T/docker-rm.log")"
fi

# A rate-limit backoff is 120s: a TERM must not wait it out.
name="a TERM during a backoff exits at once"
SLEEP_REAL=1
export SLEEP_REAL
if cancel_case rate --head "$HEAD_SHA" && [ "$RC" = 143 ]; then
  ok "$name"
else
  failed "$name: want a prompt exit 143"
fi
unset SLEEP_REAL

name="a TERM mid-creation removes the container once the client ends"
if cancel_case creating && [ "$RC" = 143 ] && [ "$(tail -n 1 "$T/docker-rm.log")" = "rm -f $CANCEL_CONTAINER created" ]; then
  ok "$name"
else
  failed "$name: want exit 143 and a removal after the creation; rm: $(cat "$T/docker-rm.log")"
fi

for bad in "--retries x|--retries must be" "--retries|--retries needs a value" "--retries 100|up to 99" \
  "--pr 0|--pr must be" "--pr 07|--pr must be" "--pr abc|--pr must be" "--pr|--pr needs a value" \
  "--try-seconds 0|--try-seconds must be" "--try-seconds 1000000|--try-seconds must be" \
  "--deadline-seconds x|--deadline-seconds must be" "--deadline-seconds 1000000|--deadline-seconds must be" \
  "--pr 1000000000|--pr must be" "--head abc123|--head must be a full" \
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
  'GITHUB_ACTION_CONFIG__ENABLE_OUTPUT: "false"'; do
  case "$review" in *"$want"*) ;; *) missing="$missing [$want]" ;; esac
done
grep -q '^          sparse-checkout: scripts$' "$WORKFLOW" || missing="$missing [sparse-checkout: scripts]"
# A dotted setting never reaches the container: the /bin/sh (dash) that runs
# bounded-run.sh drops a name that is not a shell identifier.
if printf '%s\n' "$review" | grep -Eq '^          (CONFIG|OPENROUTER|GITHUB_ACTION_CONFIG|PR_REVIEWER)\.'; then
  missing="$missing [no dotted PR-Agent setting]"
fi
# shellcheck disable=SC2016 # the workflow's literal text
printf '%s\n' "$review" | grep -q '^          OPENROUTER__KEY: \${{ secrets.OPENROUTER_API_KEY }}$' \
  || missing="$missing [OPENROUTER__KEY from the secret]"
marker=$(awk '/^      - name: / { on = ($0 == "      - name: Record the run for /bot-review") } on' "$WORKFLOW")
# shellcheck disable=SC2016 # the workflow's literal text
for want in "STATUS: \${{ steps.review.outcome == 'skipped' && 'failure' || steps.review.outcome }}" \
  'PR: ${{ github.event.pull_request.number }}' 'HEAD_SHA: ${{ steps.head.outputs.sha }}' \
  "if: \${{ !cancelled() && env.HAS_KEY == 'true' && steps.head.outputs.sha != '' && steps.prior.outputs.reviewed != 'true' }}"; do
  case "$marker" in *"$want"*) ;; *) missing="$missing [marker step: $want]" ;; esac
done
# A head already reviewed skips the review and keeps its marker.
printf '%s\n' "$review" | grep -qF "if: env.HAS_KEY == 'true' && steps.prior.outputs.reviewed != 'true'" \
  || missing="$missing [the Review step waits on the once-per-head check]"
prior=$(awk '/^      - name: / { on = ($0 == "      - name: Skip a head already reviewed") } on' "$WORKFLOW")
# shellcheck disable=SC2016 # the workflow's literal text
for want in '        id: prior' "if: env.HAS_KEY == 'true' && steps.head.outputs.sha != ''" \
  'run: /bin/bash scripts/pr-agent-reviewed.sh --pr "$PR" --head "$HEAD_SHA"' \
  'GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}' 'PR: ${{ github.event.pull_request.number }}' \
  'HEAD_SHA: ${{ steps.head.outputs.sha }}'; do
  case "$prior" in *"$want"*) ;; *) missing="$missing [once-per-head step: $want]" ;; esac
done
# It runs after the checkout that brings scripts/ and before the review.
order=$(grep -n -e '^      - name: Check out the review wrapper$' -e '^      - name: Skip a head already reviewed$' \
  -e '^      - name: Review$' "$WORKFLOW" | cut -d: -f2- | tr -d ' -' | tr '\n' ',')
[ "$order" = "name:Checkoutthereviewwrapper,name:Skipaheadalreadyreviewed,name:Review," ] \
  || missing="$missing [step order: $order]"
printf '%s\n' "$review" | grep -qx '        id: review' || missing="$missing [the Review step's id]"
grep -qx '        id: head' "$WORKFLOW" || missing="$missing [the head step's id]"
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
