#!/bin/sh
# review-backtest-reviewer.sh — the default reviewer review-backtest.sh runs
# per corpus row: today's review pass, headless (review-effectiveness
# REQ-H1.2, D-7, D-9).
#
# "Today's pass" is /self-review's discovery step as the planwright checkout
# in BACKTEST_PLANWRIGHT_ROOT states it: the lens set chosen by artifact class,
# every lens walked over the diff, and the self-critique, with no validation,
# no fixes, and no loop. The lenses are walked inline in one session, the way
# most measured nested convergence runs walked them; a reviewer change that
# fans out or reads a handoff bundle is a different reviewer and is replayed
# through its own --reviewer command.
#
# The session reads historical, untrusted content, so it gets read-only file
# tools and nothing else: no shell (even read-only git can write a file through
# --output), no MCP servers, no settings files (restricted mode), and no
# permission prompts that an auto mode could approve. It reads the diff
# review-backtest.sh wrote (BACKTEST_DIFF), the copy (its working directory),
# and the planwright checkout. A declined row's coordinator ledger
# (BACKTEST_LEDGER) is handed over as the loop ledger a pass holds today, with
# today's suppression rule.
#
# Prints one finding per line, `<path><TAB><line><TAB><lens><TAB><summary>`,
# and writes the session's total token count to BACKTEST_USAGE_FILE when set.
#
# Environment: the BACKTEST_* variables review-backtest.sh documents, plus
#   PLANWRIGHT_BACKTEST_CLAUDE     the claude binary (default: claude)
#   PLANWRIGHT_BACKTEST_MAX_TURNS  the turn cap (default: 80)
#
# Exit codes: 0 findings printed (possibly none); 1 the session failed,
# reported an error, or returned no result.
set -eu
unset CDPATH

prog=review-backtest-reviewer
claude_bin=${PLANWRIGHT_BACKTEST_CLAUDE:-claude}
max_turns=${PLANWRIGHT_BACKTEST_MAX_TURNS:-80}
: "${BACKTEST_BASE:?}" "${BACKTEST_DIFF:?}" "${BACKTEST_PLANWRIGHT_ROOT:?}" "${BACKTEST_MODEL:?}"
root=$BACKTEST_PLANWRIGHT_ROOT
rowdir=$(dirname "$BACKTEST_DIFF")

ledger_text=
if [ -n "${BACKTEST_LEDGER:-}" ]; then
  ledger_text="
The loop ledger at $BACKTEST_LEDGER lists findings an earlier iteration of
this loop declined, with the reason. Treat it as /polish's ledger is treated
today: do not re-raise a declined finding unless you hold evidence its
decline did not consider."
fi

prompt="You are replaying planwright's review pass over one historical change to
measure what it finds. Do not modify any file.

The change under review is the diff in $BACKTEST_DIFF (from $BACKTEST_BASE to
the current directory's HEAD). The current directory is a checkout of the
change's branch at that HEAD; read any file in it for context.

Run the Discovery step of $root/skills/self-review/SKILL.md over that diff:
read $root/doctrine/discovery-rigor.md and $root/doctrine/artifact-lenses.md,
select the lens set for the change's artifact class, walk every lens over the
diff inline in this session, then run the self-critique pass. Do not run the
project's tooling, validate, fix, or prune by severity.$ledger_text

End your reply with every finding, one per line, in exactly this form:
FINDING<TAB><repository-relative path><TAB><line number in HEAD><TAB><lens><TAB><one-line summary>
using a real tab character between fields. Print nothing after the last one."

# The session runs in the background so a TERM sent to this script (the
# harness stopping a row) ends the session too instead of orphaning it.
outf=$(mktemp "${TMPDIR:-/tmp}/rbt-review.XXXXXX")
cpid=
trap 'rm -f "$outf"' EXIT
trap '[ -z "$cpid" ] || kill "$cpid" 2>/dev/null; exit 143' TERM
trap '[ -z "$cpid" ] || kill "$cpid" 2>/dev/null; exit 130' INT
"$claude_bin" -p "$prompt" --model "$BACKTEST_MODEL" \
  --output-format json --max-turns "$max_turns" \
  --tools 'Read,Grep,Glob' --allowedTools 'Read' 'Grep' 'Glob' \
  --permission-mode dontAsk --strict-mcp-config --restricted \
  --add-dir "$root" --add-dir "$rowdir" </dev/null >"$outf" 2>/dev/null &
cpid=$!
crc=0
wait "$cpid" || crc=$?
cpid=
if [ "$crc" -ne 0 ]; then
  printf '%s\n' "$prog: the review session failed" >&2
  exit 1
fi
out=$(cat "$outf")
if [ "$(printf '%s\n' "$out" | jq -r '.is_error // false' 2>/dev/null)" != false ]; then
  printf '%s\n' "$prog: the review session reported an error" >&2
  exit 1
fi
result=$(printf '%s\n' "$out" | jq -r '.result // empty' 2>/dev/null) || result=
if [ -z "$result" ]; then
  printf '%s\n' "$prog: the review session returned no result" >&2
  exit 1
fi
if [ -n "${BACKTEST_USAGE_FILE:-}" ]; then
  printf '%s\n' "$out" | jq -r '.usage // {} | [.input_tokens, .cache_creation_input_tokens, .cache_read_input_tokens, .output_tokens] | map(. // 0) | add' \
    >"$BACKTEST_USAGE_FILE" 2>/dev/null || true
fi
printf '%s\n' "$result" | awk -F '\t' 'BEGIN { OFS = "\t" } $1 == "FINDING" && $3 ~ /^[1-9][0-9]*$/ { print $2, $3, $4, $5 }'
