#!/bin/bash
# Tests for scripts/classify-ci-failure.sh — the adaptive-retry CI-failure
# classifier (REQ-E1.2, D-25). `/execute-task` calls it to decide whether a
# failed CI run is a transient failure (retry with backoff) or a logic
# failure (escalate immediately). The classification is the fixture-testable
# core of the adaptive-retry behavior (kickoff brief Section 4).
#
# Contract under test:
#   - prints `transient` (exit 0) only when a transient indicator is present
#     AND no logic indicator is present;
#   - prints `logic` (exit 1) otherwise — any logic indicator, or no signal
#     at all (unknown defaults to logic: safer to escalate than burn retries);
#   - reads from a file argument or from stdin;
#   - a missing file argument is a usage error (exit 2), not a silent pass.
set -u
unset CDPATH

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CLASSIFIER="$REPO_ROOT/scripts/classify-ci-failure.sh"

failures=0

# assert_exit <label> <expected-exit> <actual-exit>
assert_exit() {
  if [ "$2" -eq "$3" ]; then
    echo "ok: $1"
  else
    echo "FAIL: $1 (expected exit $2, got $3)" >&2
    failures=$((failures + 1))
  fi
}

# assert_word <label> <expected-word> <actual-word>
assert_word() {
  if [ "$2" = "$3" ]; then
    echo "ok: $1 (word)"
  else
    echo "FAIL: $1 (expected word '$2', got '$3')" >&2
    failures=$((failures + 1))
  fi
}

if [ ! -x "$CLASSIFIER" ]; then
  echo "FAIL: classifier script missing or not executable at $CLASSIFIER" >&2
  exit 1
fi

tmp="$(mktemp -d)" || exit 1
trap 'rm -rf "$tmp"' EXIT

# classify <fixture-content> -> sets `word` and `code` from a file-arg run
classify() {
  printf '%s\n' "$1" >"$tmp/ci.log"
  word="$(/bin/bash "$CLASSIFIER" "$tmp/ci.log" 2>/dev/null)"
  code=$?
}

# 1. Pure transient samples classify as transient (exit 0). One per
#    indicator family the classifier recognizes.
transient_samples='curl: (28) Operation timed out after 30000 ms
fatal: unable to access: Could not resolve host: github.com
Error response from daemon: failed to pull image "node:20"
HTTP 503 Service Unavailable
remote: 429 Too Many Requests
dial tcp: connection refused
TLS handshake timeout
The remote end hung up unexpectedly
npm ERR! request to https://registry.npmjs.org failed, reason: getaddrinfo ENOTFOUND registry.npmjs.org
Error: connect ECONNREFUSED 140.82.112.3:443
Error: read ECONNRESET
Error: connect ETIMEDOUT 140.82.112.3:443
ping: connect: Network is unreachable
HTTP 502 Bad Gateway
ssh: connect to host github.com port 22: No route to host'
ts_n=0
while IFS= read -r line; do
  [ -n "$line" ] || continue
  ts_n=$((ts_n + 1))
  classify "$line"
  assert_exit "transient sample $ts_n classifies transient" 0 "$code"
  assert_word "transient sample $ts_n" "transient" "$word"
done <<EOF
$transient_samples
EOF

# 2. Pure logic samples classify as logic (exit 1). These carry a
#    deterministic failure marker and no transient indicator.
logic_samples='AssertionError: expected 3 but got 4
test.ts(12,5): error TS2322: Type "string" is not assignable to type "number"
SyntaxError: Unexpected token
mymod.rb:9: undefined method `frobnicate'"'"' for nil:NilClass
Traceback (most recent call last):
12 failing
would reformat scripts/foo.sh
panic: runtime error: index out of range [3] with length 2
bash: line 4: parse error near unexpected token
In scripts/foo.sh line 9: SC2086: Double quote to prevent globbing
Error response from daemon: failed to pull image "node:99": manifest unknown'
ls_n=0
while IFS= read -r line; do
  [ -n "$line" ] || continue
  ls_n=$((ls_n + 1))
  classify "$line"
  assert_exit "logic sample $ls_n classifies logic" 1 "$code"
  assert_word "logic sample $ls_n" "logic" "$word"
done <<EOF
$logic_samples
EOF

# 3. Mixed signal: a real logic failure whose log also contains a transient
#    line. Logic wins (escalate) — never burn retries on a deterministic
#    failure that happens to share a log with a network blip.
classify 'warning: connection reset by peer during fetch
AssertionError: expected true to be false'
assert_exit "mixed transient+logic classifies logic" 1 "$code"
assert_word "mixed transient+logic" "logic" "$word"

# 4. Unknown / no recognized signal defaults to logic (safer to escalate
#    than retry an unclassifiable failure indefinitely).
classify 'some bespoke failure the classifier has never seen'
assert_exit "unknown defaults to logic" 1 "$code"
assert_word "unknown default" "logic" "$word"

# 4b. Empty input defaults to logic, not a crash or a silent transient.
: >"$tmp/empty.log"
word="$(/bin/bash "$CLASSIFIER" "$tmp/empty.log" 2>/dev/null)"
code=$?
assert_exit "empty input defaults to logic" 1 "$code"
assert_word "empty input" "logic" "$word"

# 5. Reads from stdin when no file argument is given.
word="$(printf '%s\n' 'Could not resolve host: registry.npmjs.org' \
  | /bin/bash "$CLASSIFIER" 2>/dev/null)"
code=$?
assert_exit "stdin transient classifies transient" 0 "$code"
assert_word "stdin transient" "transient" "$word"

# 6. A missing file argument is a usage error (exit 2), not a silent pass.
/bin/bash "$CLASSIFIER" "$tmp/no-such-file.log" >/dev/null 2>&1
assert_exit "missing file argument is a usage error" 2 $?

# 7. Matching is case-insensitive: uppercased transient text still matches.
classify 'CONNECTION TIMED OUT'
assert_exit "uppercase transient classifies transient" 0 "$code"
assert_word "uppercase transient" "transient" "$word"

# 8. Input is treated as data: a line that looks like a shell substitution
#    or metacharacters is never evaluated, just scanned.
# shellcheck disable=SC2016 # the substitution syntax is the literal fixture
classify '$(rm -rf /); `reboot`; transient? connection refused'
assert_exit "metacharacter input is scanned, not evaluated" 0 "$code"
assert_word "metacharacter input" "transient" "$word"

# 9. A benign log containing "expected … to …" prose alongside a real
#    transient indicator must stay transient: the logic patterns must not
#    over-match common infrastructure phrasing and suppress the retry (logic
#    wins over transient, so an over-broad logic match defeats adaptive retry).
classify 'Waiting for expected service to start
connection refused'
assert_exit "benign expected-to phrasing stays transient" 0 "$code"
assert_word "benign expected-to phrasing" "transient" "$word"

# 10. A filename beginning with a hyphen is read as a file, never parsed as a
#     command option: the classifier takes a single file argument (no `--`
#     separator on its own CLI) and guards it internally when it hands the path
#     to grep (`grep ... -- "$file"`).
printf '%s\n' 'connection refused' >"$tmp/-dash.log"
word="$(cd "$tmp" && /bin/bash "$CLASSIFIER" -dash.log 2>/dev/null)"
code=$?
assert_exit "leading-hyphen filename is read, not parsed as an option" 0 "$code"
assert_word "leading-hyphen filename" "transient" "$word"

# 11. A `:latest` image-pull failure is transient: the logic word "test failed"
#     must not substring-match inside "latest failed" and suppress the retry.
classify 'pulling ubuntu:latest failed: connection refused'
assert_exit "':latest failed' stays transient" 0 "$code"
assert_word "':latest failed'" "transient" "$word"

# 11b. A genuine test-runner "tests failed" summary still classifies logic
#      (the boundary-anchored pattern keeps the real case).
classify 'Summary
tests failed'
assert_exit "'tests failed' summary classifies logic" 1 "$code"
assert_word "'tests failed' summary" "logic" "$word"

# 12. A benign "timeout_test" token in an otherwise-unrecognized failure must
#     not create a false transient (the bare word "timeout" was over-matching
#     adjacent identifiers), so the doomed build escalates instead of retrying.
classify 'ran timeout_test.go
some unrecognized build failure'
assert_exit "benign timeout_test token defaults to logic" 1 "$code"
assert_word "benign timeout_test token" "logic" "$word"

# 12b. A real bounded "timeout" word is still a transient indicator.
classify 'fetch error: read timeout'
assert_exit "bounded 'timeout' word stays transient" 0 "$code"
assert_word "bounded 'timeout' word" "transient" "$word"

if [ "$failures" -gt 0 ]; then
  echo "$failures failure(s)" >&2
  exit 1
fi
echo "all classify-ci-failure tests passed"
