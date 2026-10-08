#!/bin/bash
# Tests for scripts/classify-limit.sh: captured output matched against a
# vendor's fixed-string recognizers, reporting the recognizer id, a screened
# excerpt, and an accepted reset time (quota-handling REQ-A1.2, REQ-A1.5,
# REQ-C1.5). Plain bash 3.2, inline asserts (sibling convention).
set -u
unset CDPATH
LC_ALL=C
export LC_ALL
PLANWRIGHT_SECRET_SCREEN_TOOL=none
export PLANWRIGHT_SECRET_SCREEN_TOOL

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CL="$REPO_ROOT/scripts/classify-limit.sh"
TAB=$(printf '\t')

failures=0
ok() { echo "ok: $1"; }
fail() {
  echo "FAIL: $1" >&2
  failures=$((failures + 1))
}
assert_rc() {
  if [ "$2" -eq "$3" ]; then ok "$1"; else fail "$1 (expected exit $2, got $3; stderr: $ERR)"; fi
}
assert_contains() {
  case "$3" in
    *"$2"*) ok "$1" ;;
    *) fail "$1 (expected to find '$2' in: $3)" ;;
  esac
}
assert_absent() {
  case "$3" in
    *"$2"*) fail "$1 (did not expect '$2' in: $3)" ;;
    *) ok "$1" ;;
  esac
}

[ -f "$CL" ] || {
  echo "FAIL: classifier script missing at $CL" >&2
  exit 1
}

tmp="$(cd "$(mktemp -d)" && pwd -P)" || exit 1
trap 'rm -rf "$tmp"' EXIT

base() {
  env -u PLANWRIGHT_ROOT -u CLAUDE_PLUGIN_ROOT -u CLAUDE_DIR \
    -u PLANWRIGHT_ADOPTER_OVERLAY -u CLAUDE_PLUGIN_DATA \
    -u PLANWRIGHT_REPO_ROOT -u HOME "$@"
}

sb="$tmp/sb"
mkdir -p "$sb/core/scripts" "$sb/core/config" "$sb/repo"
GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 git init -q "$sb/repo"
cat >"$sb/core/config/vendors.yaml" <<'YAML'
vendors:
  - id: sample-cli.vendor
    vendor: sample-cli
    part: vendor
    evidence: none
  - id: sample-cli.quota
    vendor: sample-cli
    part: recognizer
    match: monthly quota exhausted
    reset-after: "resets at "
  - id: sample-cli.substitution
    vendor: sample-cli
    part: recognizer
    match: $(touch PWNED)
  - id: sample-cli.pattern
    vendor: sample-cli
    part: recognizer
    match: a.*b[0-9]
YAML

# NOW: a fixed clock; the throttle's hold ceiling bounds an accepted reset.
NOW=1790000000
NOW_ISO=2026-09-21T14:13:20Z
HOUR_ISO=2026-09-21T15:13:20Z

# cl <args...>: run the classifier against the sandbox catalog, stdin from
# $tmp/in; stdout in OUT, stderr in ERR, exit status in RC.
cl() {
  RC=0
  (cd "$sb/repo" && base PLANWRIGHT_ROOT="$sb/core" PLANWRIGHT_ADOPTER_OVERLAY="$sb/adopter" \
    PLANWRIGHT_REPO_ROOT="$sb/repo" PLANWRIGHT_SECRET_SCREEN_TOOL=none \
    /bin/sh "$CL" "$@" <"$tmp/in" >"$tmp/out" 2>"$tmp/err") || RC=$?
  OUT=$(cat "$tmp/out")
  ERR=$(cat "$tmp/err")
}

ceiling=$(/bin/sh "$REPO_ROOT/scripts/fleet-throttle.sh" ceiling)
case "$ceiling" in
  "" | *[!0-9]*) fail "fleet-throttle.sh ceiling printed '$ceiling'" ;;
  *) ok "the throttle exposes its hold ceiling ($ceiling s)" ;;
esac

# ---------------------------------------------------------------------------
# REQ-A1.5: a recognized text is reported with its fields.
# ---------------------------------------------------------------------------
printf 'starting review\nerror: monthly quota exhausted, resets at %s\nbye\n' "$HOUR_ISO" >"$tmp/in"
cl --vendor sample-cli --now "$NOW"
assert_rc "a recognized refusal exits 0" 0 "$RC"
assert_contains "outcome is limited" "outcome${TAB}limited" "$OUT"
assert_contains "the vendor is named" "vendor${TAB}sample-cli" "$OUT"
assert_contains "the recognizer id is named" "recognizer${TAB}sample-cli.quota" "$OUT"
assert_contains "an ISO-8601 reset converts to epoch seconds" "reset${TAB}$((NOW + 3600))" "$OUT"
assert_contains "the excerpt carries the refusal line" "excerpt${TAB}error: monthly quota exhausted, resets at $HOUR_ISO" "$OUT"
assert_absent "the excerpt omits unrelated lines" "starting review" "$OUT"

# Identical input, identical output, byte for byte (REQ-A1.2).
first=$OUT
cl --vendor sample-cli --now "$NOW"
[ "$first" = "$OUT" ] && ok "identical input yields identical output" || fail "output differs between runs"

# Epoch-seconds reset.
printf 'monthly quota exhausted; resets at %s.\n' "$((NOW + 60))" >"$tmp/in"
cl --vendor sample-cli --now "$NOW"
assert_contains "an epoch reset is accepted" "reset${TAB}$((NOW + 60))" "$OUT"

# Fractional-second ISO reset.
printf 'monthly quota exhausted resets at 2026-09-21T15:13:20.250Z\n' >"$tmp/in"
cl --vendor sample-cli --now "$NOW"
assert_contains "a fractional ISO reset is accepted" "reset${TAB}$((NOW + 3600))" "$OUT"

# The reset time is omitted when the locator finds none, or finds an
# unparseable, past, or beyond-ceiling value.
no_reset() {
  printf '%s\n' "$2" >"$tmp/in"
  cl --vendor sample-cli --now "$NOW"
  assert_rc "$1: still limited" 0 "$RC"
  assert_absent "$1: no reset line" "reset${TAB}" "$OUT"
}
no_reset "no locator text" "monthly quota exhausted"
no_reset "unparseable value" "monthly quota exhausted, resets at soon"
no_reset "invalid calendar date" "monthly quota exhausted, resets at 2026-02-30T00:00:00Z"
no_reset "non-UTC offset" "monthly quota exhausted, resets at 2026-09-21T15:13:20+02:00"
no_reset "past ISO value" "monthly quota exhausted, resets at 2026-09-21T14:13:19Z"
no_reset "the current second" "monthly quota exhausted, resets at $NOW_ISO"
no_reset "past epoch" "monthly quota exhausted, resets at $((NOW - 1))"
no_reset "beyond the ceiling" "monthly quota exhausted, resets at $((NOW + ceiling + 1))"
no_reset "oversized epoch" "monthly quota exhausted, resets at 1790000000000000000"
printf 'monthly quota exhausted, resets at %s\n' "$((NOW + ceiling))" >"$tmp/in"
cl --vendor sample-cli --now "$NOW"
assert_contains "a reset exactly at the ceiling is accepted" "reset${TAB}$((NOW + ceiling))" "$OUT"

# ---------------------------------------------------------------------------
# No match on unrecognized text.
# ---------------------------------------------------------------------------
printf 'the build failed: assertion error\nMonthly Quota Exhausted\n' >"$tmp/in"
cl --vendor sample-cli --now "$NOW"
assert_rc "unrecognized text exits 1" 1 "$RC"
[ -z "$OUT" ] && ok "unrecognized text prints nothing" || fail "unrecognized text printed: $OUT"
: >"$tmp/in"
cl --vendor sample-cli --now "$NOW"
assert_rc "empty input is unrecognized" 1 "$RC"

# ---------------------------------------------------------------------------
# REQ-C1.5: recognizers are inert fixed strings.
# ---------------------------------------------------------------------------
printf 'aXXb7 looks like the pattern but is not the literal\n' >"$tmp/in"
cl --vendor sample-cli --now "$NOW"
assert_rc "a regex-shaped recognizer does not match as a pattern" 1 "$RC"
printf 'got a.*b[0-9] literally\n' >"$tmp/in"
cl --vendor sample-cli --now "$NOW"
assert_contains "a regex-shaped recognizer matches its literal text" "recognizer${TAB}sample-cli.pattern" "$OUT"
printf 'output: $(touch PWNED)\n' >"$tmp/in"
cl --vendor sample-cli --now "$NOW"
assert_contains "a substitution-shaped recognizer matches literally" "recognizer${TAB}sample-cli.substitution" "$OUT"
[ ! -e "$sb/repo/PWNED" ] && [ ! -e "$tmp/PWNED" ] && [ ! -e PWNED ] \
  && ok "no recognizer is executed" || fail "a recognizer ran a command"

# Several recognizers on one line: the first declared wins; the earliest
# matching line wins over a later one.
printf 'line one $(touch PWNED)\nmonthly quota exhausted\n' >"$tmp/in"
cl --vendor sample-cli --now "$NOW"
assert_contains "the earliest matching line wins" "recognizer${TAB}sample-cli.substitution" "$OUT"
printf 'a.*b[0-9] and monthly quota exhausted\n' >"$tmp/in"
cl --vendor sample-cli --now "$NOW"
assert_contains "on one line, the first declared recognizer wins" "recognizer${TAB}sample-cli.quota" "$OUT"

# ---------------------------------------------------------------------------
# The excerpt is screened as a step-record excerpt is.
# ---------------------------------------------------------------------------
tok="ghp_$(printf 'a%.0s' $(seq 1 36))"
printf 'monthly quota exhausted for token %s\n' "$tok" >"$tmp/in"
RC=0
(cd "$sb/repo" && base PLANWRIGHT_ROOT="$sb/core" PLANWRIGHT_ADOPTER_OVERLAY="$sb/adopter" \
  PLANWRIGHT_REPO_ROOT="$sb/repo" PLANWRIGHT_SECRET_SCREEN_TOOL=none \
  /bin/sh "$CL" --vendor sample-cli --now "$NOW" <"$tmp/in" >"$tmp/out" 2>&1) || RC=$?
OUT=$(cat "$tmp/out")
assert_rc "a token-bearing refusal is still classified" 0 "$RC"
assert_absent "the token never reaches the output" "$tok" "$OUT"
assert_contains "the excerpt is withheld" "excerpt${TAB}[withheld: the secret screen flagged this excerpt]" "$OUT"
printf 'monthly quota exhausted \033[31mred\033[0m\n' >"$tmp/in"
cl --vendor sample-cli --now "$NOW"
case "$OUT" in
  *"$(printf '\033')"*) fail "a control byte reached the excerpt" ;;
  *) ok "control bytes are stripped from the excerpt" ;;
esac
# A long matching line keeps the match inside the bounded excerpt.
pad=$(printf 'p%.0s' $(seq 1 3000))
printf '%s monthly quota exhausted %s\n' "$pad" "$pad" >"$tmp/in"
cl --vendor sample-cli --now "$NOW"
ex=$(printf '%s\n' "$OUT" | sed -n "s/^excerpt${TAB}//p")
[ "${#ex}" -le 2000 ] && ok "the excerpt stays within the byte bound" || fail "excerpt is ${#ex} bytes"
assert_contains "the bounded excerpt still holds the match" "monthly quota exhausted" "$ex"

# Input from a file argument reads the same as stdin.
printf 'monthly quota exhausted\n' >"$tmp/capture.txt"
: >"$tmp/in"
cl --vendor sample-cli --now "$NOW" --input "$tmp/capture.txt"
assert_contains "--input reads a capture file" "recognizer${TAB}sample-cli.quota" "$OUT"

# ---------------------------------------------------------------------------
# Usage and vendor resolution.
# ---------------------------------------------------------------------------
printf 'monthly quota exhausted\n' >"$tmp/in"
cl --vendor nobody --now "$NOW"
assert_rc "an undeclared vendor exits 3" 3 "$RC"
for hostile in "../x" '$(id)' "Sample" ""; do
  cl --vendor "$hostile" --now "$NOW"
  assert_rc "hostile vendor '$hostile' is a usage error" 2 "$RC"
done
cl --now "$NOW"
assert_rc "a missing --vendor is a usage error" 2 "$RC"
cl --vendor sample-cli --now soon
assert_rc "a non-numeric --now is a usage error" 2 "$RC"

# ---------------------------------------------------------------------------
# The shipped claude adapter: a rate-limit death is recognized, a routine
# rate-limit frame and an overload error are not.
# ---------------------------------------------------------------------------
claude_cl() {
  RC=0
  base PLANWRIGHT_ROOT="$REPO_ROOT" PLANWRIGHT_ADOPTER_OVERLAY="$tmp/none" \
    PLANWRIGHT_REPO_ROOT="$sb/repo" /bin/sh "$CL" --vendor claude --now "$NOW" \
    <"$tmp/in" >"$tmp/out" 2>"$tmp/err" || RC=$?
  OUT=$(cat "$tmp/out")
  ERR=$(cat "$tmp/err")
}
printf '%s\n' '{"type":"result","is_error":true,"error":"rate_limit"}' >"$tmp/in"
claude_cl
assert_rc "a stream-json rate-limit result is limited" 0 "$RC"
printf '%s\n' '{"type":"error","error":{"type":"rate_limit_error","message":"x"}}' >"$tmp/in"
claude_cl
assert_rc "an API rate_limit_error is limited" 0 "$RC"
printf 'Claude AI usage limit reached|%s\n' "$((NOW + 600))" >"$tmp/in"
claude_cl
assert_contains "the usage-limit line states its reset" "reset${TAB}$((NOW + 600))" "$OUT"
printf '%s\n' '{"type":"rate_limit_event","rate_limit_info":{"status":"allowed"}}' >"$tmp/in"
claude_cl
assert_rc "a routine rate-limit frame is not a refusal" 1 "$RC"
printf '%s\n' '{"type":"error","error":{"type":"overloaded_error"}}' >"$tmp/in"
claude_cl
assert_rc "an overload error is not a limit" 1 "$RC"

# ---------------------------------------------------------------------------
# REQ-A1.2: classification is script logic, never a model call.
# ---------------------------------------------------------------------------
if grep -nE '(^|[^a-z-])(claude|codex|gemini|llm|ollama)( |$)|offload-dispatch|fleet-dispatch' "$CL" \
  | grep -v '^[0-9]*:[[:space:]]*#' >/dev/null; then
  fail "the classifier invokes a model or agent command"
else
  ok "the classifier invokes no model or agent command"
fi

if [ "$failures" -gt 0 ]; then
  echo "$failures failure(s)" >&2
  exit 1
fi
echo "all classify-limit tests passed"
