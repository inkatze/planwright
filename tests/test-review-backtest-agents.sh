#!/bin/bash
# Tests for the two model-facing helpers of the review backtest, run offline
# through a stub claude binary: scripts/review-backtest-reviewer.sh (today's
# pass, per corpus row) and scripts/review-backtest-annotate.sh (the refresh's
# paraphrase and labels) (review-effectiveness REQ-H1.2, D-7, D-16).
set -u
unset CDPATH

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REVIEWER="$REPO_ROOT/scripts/review-backtest-reviewer.sh"
ANNOTATE="$REPO_ROOT/scripts/review-backtest-annotate.sh"

failures=0
ok() { echo "ok: $1"; }
fail() {
  echo "FAIL: $1" >&2
  failures=$((failures + 1))
}
assert_exit() {
  if [ "$2" -eq "$3" ]; then ok "$1"; else fail "$1 (expected exit $2, got $3)"; fi
}
assert_contains() {
  case "$3" in
    *"$2"*) ok "$1" ;;
    *) fail "$1 (missing '$2' in: $3)" ;;
  esac
}
assert_lacks() {
  case "$3" in
    *"$2"*) fail "$1 (unexpectedly contains '$2')" ;;
    *) ok "$1" ;;
  esac
}

T=$(mktemp -d "${TMPDIR:-/tmp}/rba.XXXXXX")
trap 'rm -rf "$T"' EXIT

# The stub records its argv one per line and answers with $STUB_REPLY.
cat >"$T/claude" <<'EOF'
#!/bin/sh
for a in "$@"; do printf '%s\n' "$a"; done >"$STUB_ARGV"
cat >/dev/null
printf '%s\n' "$STUB_REPLY"
EOF
chmod +x "$T/claude"
export PLANWRIGHT_BACKTEST_CLAUDE="$T/claude" STUB_ARGV="$T/argv"

# --- the reviewer ---
mkdir -p "$T/row/copy"
: >"$T/row/change.diff"
export BACKTEST_BASE=0123456789abcdef0123456789abcdef01234567 BACKTEST_DIFF="$T/row/change.diff" \
  BACKTEST_PLANWRIGHT_ROOT="$REPO_ROOT" BACKTEST_MODEL=stub-model BACKTEST_USAGE_FILE="$T/usage"
export STUB_REPLY='{"is_error":false,"result":"walked the lenses\nFINDING\ta.sh\t12\tcorrectness\tthe loop spins\nFINDING\tb.sh\tx\tdocs\tno line\nnot a finding","usage":{"input_tokens":10,"cache_creation_input_tokens":20,"cache_read_input_tokens":30,"output_tokens":40}}'
out=$(cd "$T/row/copy" && "$REVIEWER" 2>&1)
assert_exit "the reviewer succeeds on a normal result" 0 $?
assert_contains "prints a well-formed finding" "a.sh	12	correctness	the loop spins" "$out"
assert_lacks "drops a finding without a line number" "b.sh" "$out"
assert_lacks "drops the session's prose" "walked the lenses" "$out"
if [ "$(cat "$T/usage")" = 100 ]; then ok "writes the session's token total"; else fail "token total wrong"; fi
argv=$(cat "$T/argv")
assert_contains "the session gets read-only file tools only" "Read,Grep,Glob" "$argv"
assert_contains "the session never prompts for a permission" "dontAsk" "$argv"
assert_contains "the session runs restricted" "--restricted" "$argv"
assert_contains "the session loads no MCP servers" "--strict-mcp-config" "$argv"
assert_lacks "the session is never handed a shell" "Bash" "$argv"
assert_contains "the prompt names the diff file" "$T/row/change.diff" "$argv"

export STUB_REPLY='{"is_error":true,"result":"API Error: rate limited"}'
(cd "$T/row/copy" && "$REVIEWER" >/dev/null 2>&1)
assert_exit "an error result is a failure, never zero findings" 1 $?
export STUB_REPLY='{"is_error":false}'
(cd "$T/row/copy" && "$REVIEWER" >/dev/null 2>&1)
assert_exit "a result with no text is a failure" 1 $?
if ! (cd "$T/row/copy" && env -u BACKTEST_DIFF "$REVIEWER" >/dev/null 2>&1); then ok "the reviewer refuses to run without the diff file"; else fail "ran without BACKTEST_DIFF"; fi

# --- the annotator ---
req='{"key":"7:a.sh:1:x","pr":7,"path":"a.sh","line":1,"finding":"f","reply":"r","declined_log":[],"label_reason":true}'
export STUB_REPLY='{"is_error":false,"result":"here you go\n{\"key\":\"7:a.sh:1:x\",\"category\":\"correctness\",\"gist\":\"g\",\"declined\":false,\"reason\":\"pruned\"}\nnot json"}'
out=$(printf '%s\n' "$req" | "$ANNOTATE" 2>&1)
assert_exit "the annotator succeeds on a normal result" 0 $?
assert_contains "prints the answer object" '"key":"7:a.sh:1:x"' "$out"
assert_lacks "drops the chatter around it" "here you go" "$out"
argv=$(cat "$T/argv")
if printf '%s\n' "$argv" | awk 'prev == "--tools" && $0 == "" { found = 1 } { prev = $0 } END { exit !found }'; then ok "the annotator's call has no tools"; else fail "the annotator's call was given tools"; fi
assert_contains "the annotator's call runs restricted" "--restricted" "$argv"
assert_contains "the prompt offers every class but declined" "spec-conflict:" "$argv"
assert_lacks "the prompt never offers declined as a class" "  declined:" "$argv"
export STUB_REPLY='{"is_error":true,"result":"API Error"}'
printf '%s\n' "$req" | "$ANNOTATE" >/dev/null 2>&1
assert_exit "an annotator error result is a failure" 1 $?
: | "$ANNOTATE" >/dev/null 2>&1
assert_exit "an empty batch is a no-op" 0 $?

# --- a TERM to either helper ends its session, never orphans it ---
cat >"$T/slow-claude" <<EOF
#!/bin/sh
cat >/dev/null &
: >"$T/session.started"
sleep 4
: >"$T/session.finished"
EOF
chmod +x "$T/slow-claude"
term_check() {
  # term_check <label> <command>... — start the helper, TERM it once its
  # session runs, and require that the session never finishes.
  label=$1
  shift
  rm -f "$T/session.started" "$T/session.finished"
  "$@" >/dev/null 2>&1 &
  hpid=$!
  n=0
  until [ -e "$T/session.started" ] || [ "$n" -ge 200 ]; do
    sleep 0.1
    n=$((n + 1))
  done
  kill -TERM "$hpid"
  wait "$hpid" 2>/dev/null
  sleep 5
  if [ -e "$T/session.started" ] && [ ! -e "$T/session.finished" ]; then ok "$label"; else fail "$label"; fi
}
# shellcheck disable=SC2016 # the inner shell expands its own positionals
PLANWRIGHT_BACKTEST_CLAUDE="$T/slow-claude" term_check "a TERM to the reviewer ends its session" sh -c 'cd "$1" && exec "$2"' _ "$T/row/copy" "$REVIEWER"
printf '%s\n' "$req" >"$T/req.jsonl"
# shellcheck disable=SC2016 # the inner shell expands its own positionals
PLANWRIGHT_BACKTEST_CLAUDE="$T/slow-claude" term_check "a TERM to the annotator ends its call" sh -c 'exec "$0" <"$1"' "$ANNOTATE" "$T/req.jsonl"

if [ "$failures" -ne 0 ]; then
  echo "$failures failure(s)" >&2
  exit 1
fi
echo "all review-backtest-agents tests passed"
