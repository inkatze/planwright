#!/bin/bash
# Tests for scripts/pr-agent-review.sh, the PR-Agent wrapper that retries a
# review the model left empty or unparseable. Stubs stand in for docker, gh,
# sleep and the per-try bound; no model API is ever called.
#
# The docker stub plays one scripted try per `run`, popping the next line of
# $T/scen: good / clean / warned post a review (findings, "no issues", one a
# fallback model rescued), empty / parse / transport log a model-output
# failure, rate a rate limit, noop PR-Agent's own skip, silent nothing, and
# exitN exits N.
#
# Runs standalone under /bin/bash (the bash 3.2 floor).
set -eu
LC_ALL=C
export LC_ALL
unset CDPATH

here=$(cd "$(dirname "$0")" && pwd)
REAL="$here/../scripts/pr-agent-review.sh"
failures=0

[ -x "$REAL" ] || {
  echo "FAIL: scripts/pr-agent-review.sh missing or not executable" >&2
  exit 1
}

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
stub="$tmp/bin"
mkdir -p "$stub" "$tmp/scripts"
# A copy beside a stub bounded-run.sh: the per-try bound is the one seam the
# PATH stubs below cannot reach.
SCRIPT="$tmp/scripts/pr-agent-review.sh"
cp "$REAL" "$SCRIPT"

HEAD=1111111111111111111111111111111111111111
MOVED=2222222222222222222222222222222222222222

cat >"$stub/docker" <<'EOF'
#!/bin/sh
case "$1" in
  pull) exit 0 ;;
  rm) printf 'rm\n' >>"$T/docker-rm.log"; exit 0 ;;
  run) ;;
  *) exit 64 ;;
esac
printf '%s\n' "$*" >>"$T/docker-run.log"
step=$(sed -n 1p "$T/scen")
sed 1d "$T/scen" >"$T/scen.next" && mv "$T/scen.next" "$T/scen"
w='2026-11-14 00:00:00.000 | WARNING  | pr_agent.algo'
case "$step" in
  warned)
    date -u +%Y-%m-%dT%H:%M:%SZ >>"$T/posted"
    printf '%s\n' "$w.ai_handlers.litellm_ai_handler:_get_completion:3400 - Empty content in model response, finish_reason: length"
    ;;
  good | clean)
    date -u +%Y-%m-%dT%H:%M:%SZ >>"$T/posted"
    printf '%s\n' '2026-11-14 00:00:00.000 | INFO     | pr_agent.algo.pr_processing:get_pr_diff:262 - Tokens: 429, total tokens under limit: 64000, returning full diff.'
    ;;
  empty)
    printf '%s\n' "$w.ai_handlers.litellm_ai_handler:_get_completion:3400 - Empty content in model response, finish_reason: length" \
      "$w.pr_processing:retry_with_fallback_models:878 - Failed to generate prediction with openrouter/x/y"
    ;;
  parse)
    printf '%s\n' "$w.utils:load_yaml:1021 - Initial failure to parse AI prediction: expected '<document start>', but found '<scalar>'" \
      "$w.tools.pr_reviewer:_validate_review_schema:1290 - Review output failed schema validation"
    ;;
  transport)
    printf '%s\n' "$w.ai_handlers.litellm_ai_handler:_chat_completion_with_retry:3259 - Error during LLM inference: litellm.APIConnectionError: APIConnectionError: OpenrouterException - Response payload is not completed"
    ;;
  rate)
    printf '%s\n' "$w.ai_handlers.litellm_ai_handler:_chat_completion_with_retry:3259 - Error during LLM inference: litellm.RateLimitError: RateLimitError: OpenrouterException - Rate limit exceeded" \
      "$w.pr_processing:retry_with_fallback_models:878 - Failed to generate prediction with openrouter/x/y"
    ;;
  noop)
    printf '%s\n' '2026-11-14 00:00:00.000 | INFO     | pr_agent.tools.pr_reviewer:run:300 - Incremental review is enabled for https://api.github.com/repos/o/r/pulls/7 but there are no new files'
    ;;
  silent) ;;
  exit*) exit "${step#exit}" ;;
  *) printf 'stub docker: no scenario left\n' >&2; exit 70 ;;
esac
EOF

# The head lookup pops $T/heads, keeping its last line once one remains.
cat >"$stub/gh" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >>"$T/gh.log"
case "$*" in
  *"/pulls/"*)
    [ "${GH_HEAD_FAIL:-0}" = 1 ] && exit 1
    sed -n 1p "$T/heads"
    [ "$(wc -l <"$T/heads")" -gt 1 ] && { sed 1d "$T/heads" >"$T/heads.next" && mv "$T/heads.next" "$T/heads"; }
    exit 0
    ;;
  *"/comments"*)
    [ "${GH_COMMENTS_FAIL:-0}" = 1 ] && exit 1
    [ -f "$T/posted" ] && cat "$T/posted"
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
[ "${BOUND_FIRES:-0}" = 1 ] && exit 124
shift 3
exec "$@"
EOF
chmod +x "$stub/docker" "$stub/gh" "$stub/sleep"

printf '{}\n' >"$tmp/event.json"

# run <scenario words> <heads words> -- <script args>: sets OUT, RC and the
# per-run state under $T.
run() {
  T="$tmp/case.$RANDOM$RANDOM"
  mkdir -p "$T"
  # shellcheck disable=SC2086 # one line per word on purpose
  printf '%s\n' $1 >"$T/scen"
  # shellcheck disable=SC2086
  printf '%s\n' $2 >"$T/heads"
  shift 3
  RC=0
  OUT=$(env PATH="$stub:$PATH" T="$T" GITHUB_REPOSITORY=o/r \
    GITHUB_EVENT_PATH="$tmp/event.json" "CONFIG.MODEL=m" \
    "$SCRIPT" --image img@sha256:0 --pr 7 "$@" 2>&1) || RC=$?
}

count() {
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
  [ "$(count "$T/docker-run.log")" = "$3" ] || {
    failed "$1: want $3 tries, got $(count "$T/docker-run.log")"
    return 1
  }
  [ "$(count "$T/posted")" = "$4" ] || {
    failed "$1: want $4 reviews posted, got $(count "$T/posted")"
    return 1
  }
  got=$(if [ -f "$T/sleep.log" ]; then tr '\n' ' ' <"$T/sleep.log"; fi)
  [ "$got" = "$5" ] || {
    failed "$1: want backoffs '$5', got '$got'"
    return 1
  }
  return 0
}

name="empty output then a good one: retried once, review posted once"
run "empty good" "$HEAD" -- --head "$HEAD" --retries 2
expect "$name" 0 2 1 "30 " && has "$name" "returned no parseable review" && ok "$name"

name="parse error every time: N retries, then the named failure, nothing posted"
run "parse parse parse" "$HEAD" -- --head "$HEAD" --retries 2
expect "$name" 1 3 0 "30 60 " \
  && has "$name" "PR-Agent returned no parseable review after 3 tries" && ok "$name"

name="the retry count comes from --retries"
run "empty empty" "$HEAD" -- --head "$HEAD" --retries 1
expect "$name" 1 2 0 "30 " \
  && has "$name" "PR-Agent returned no parseable review after 2 tries" && ok "$name"

name="retries 0 tries once and still fails visibly"
run "empty" "$HEAD" -- --head "$HEAD" --retries 0
expect "$name" 1 1 0 "" \
  && has "$name" "PR-Agent returned no parseable review after 1 try" && ok "$name"

name="a truncated model payload counts as unparseable output"
run "transport good" "$HEAD" -- --head "$HEAD" --retries 2
expect "$name" 0 2 1 "30 " && ok "$name"

name="good output first time: no retry"
run "good" "$HEAD" -- --head "$HEAD" --retries 2
expect "$name" 0 1 1 "" && lacks "$name" "retry" && ok "$name"

name="a deliberate no-issues review is never retried"
run "clean empty" "$HEAD" -- --head "$HEAD" --retries 2
expect "$name" 0 1 1 "" && ok "$name"

name="a review posted beside a model warning is never retried"
run "warned empty" "$HEAD" -- --head "$HEAD" --retries 2
expect "$name" 0 1 1 "" && ok "$name"

name="the head moves between tries: stops"
run "empty good" "$MOVED" -- --head "$HEAD" --retries 2
expect "$name" 1 1 0 "30 " && has "$name" "head moved" && has "$name" "${MOVED:0:12}" && ok "$name"

name="an unreadable head between tries stops too"
GH_HEAD_FAIL=1
export GH_HEAD_FAIL
run "empty good" "$HEAD" -- --head "$HEAD" --retries 2
unset GH_HEAD_FAIL
expect "$name" 1 1 0 "30 " && has "$name" "could not confirm the PR head" && ok "$name"

name="rate limited: longer backoff, empty-output budget untouched"
run "rate empty good" "$HEAD" -- --head "$HEAD" --retries 1
expect "$name" 0 3 1 "120 30 " && has "$name" "rate limited" && ok "$name"

name="rate limits are bounded on their own"
run "rate rate rate" "$HEAD" -- --head "$HEAD" --retries 2
expect "$name" 1 3 0 "120 240 " && has "$name" "rate limited on every try" && ok "$name"

name="no head given: one try, no retry, still a visible failure"
run "empty good" "$HEAD" -- --retries 2
expect "$name" 1 1 0 "" && has "$name" "PR-Agent returned no parseable review after 1 try" && ok "$name"

name="PR-Agent's own skip is a success with nothing posted"
run "noop" "$HEAD" -- --head "$HEAD" --retries 2
expect "$name" 0 1 0 "" && ok "$name"

name="no review and no known cause fails without a retry"
run "silent good" "$HEAD" -- --head "$HEAD" --retries 2
expect "$name" 1 1 0 "" && has "$name" "posted no review" && ok "$name"

name="a non-zero PR-Agent exit fails without a retry"
run "exit3 good" "$HEAD" -- --head "$HEAD" --retries 2
expect "$name" 1 1 0 "" && has "$name" "exited 3" && ok "$name"

name="a try past its bound fails without a retry and removes the container"
BOUND_FIRES=1
export BOUND_FIRES
run "good good" "$HEAD" -- --head "$HEAD" --retries 2 --try-seconds 5
unset BOUND_FIRES
if [ "$RC" = 1 ] && [ "$(count "$T/docker-rm.log")" = 1 ] && [ "$(count "$T/posted")" = 0 ] \
  && grep -q -- '-k 30 5' "$T/bound.log"; then
  has "$name" "timed out" && ok "$name"
else
  failed "$name: want exit 1, one container removal, nothing posted, the bound passed"
fi

name="an unreadable comment list is a failure, never a retry or a pass"
GH_COMMENTS_FAIL=1
export GH_COMMENTS_FAIL
run "good good" "$HEAD" -- --head "$HEAD" --retries 2
unset GH_COMMENTS_FAIL
expect "$name" 1 1 1 "" && has "$name" "could not read" && ok "$name"

name="the comment query is scoped to the try's start"
run "good" "$HEAD" -- --head "$HEAD" --retries 2
if grep -q 'issues/7/comments?since=20[0-9-]*T[0-9:]*Z' "$T/gh.log"; then
  ok "$name"
else
  failed "$name: gh.log: $(cat "$T/gh.log")"
fi

name="PR-Agent's dotted settings and the event reach the container"
run "good" "$HEAD" -- --head "$HEAD" --retries 2
args=$(cat "$T/docker-run.log")
case "$args" in
  *"-e CONFIG.MODEL"*"/github/workflow/event.json"*"img@sha256:0"*) ok "$name" ;;
  *) failed "$name: docker args: $args" ;;
esac

for bad in "--retries x" "--retries" "--pr" "--try-seconds 0" "--bogus"; do
  name="usage error: $bad"
  RC=0
  # shellcheck disable=SC2086 # the flags split on purpose
  OUT=$(env PATH="$stub:$PATH" T="$tmp" GITHUB_REPOSITORY=o/r GITHUB_EVENT_PATH="$tmp/event.json" \
    "$SCRIPT" --image img --pr 7 $bad 2>&1) || RC=$?
  if [ "$RC" = 2 ]; then ok "$name"; else failed "$name: want exit 2"; fi
done

if [ "$failures" -ne 0 ]; then
  echo "$failures failure(s)" >&2
  exit 1
fi
echo "all pr-agent-review tests passed"
