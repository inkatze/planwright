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
# Runs in the isolated copy review-backtest.sh prepared (the working
# directory), through the operator's own `claude` login. The session may read
# the copy and the planwright checkout and run read-only git; it may not edit.
# A declined row's coordinator ledger (BACKTEST_LEDGER) is handed over as the
# loop ledger a pass holds today, with today's suppression rule.
#
# Prints one finding per line, `<path><TAB><line><TAB><lens><TAB><summary>`,
# and writes the session's total token count to BACKTEST_USAGE_FILE when set.
#
# Environment: the BACKTEST_* variables review-backtest.sh documents, plus
#   PLANWRIGHT_BACKTEST_CLAUDE     the claude binary (default: claude)
#   PLANWRIGHT_BACKTEST_MAX_TURNS  the turn cap (default: 80)
#
# Exit codes: 0 findings printed (possibly none); 1 the session failed or
# returned no result.
set -eu
unset CDPATH

prog=review-backtest-reviewer
claude_bin=${PLANWRIGHT_BACKTEST_CLAUDE:-claude}
max_turns=${PLANWRIGHT_BACKTEST_MAX_TURNS:-80}
: "${BACKTEST_BASE:?}" "${BACKTEST_PLANWRIGHT_ROOT:?}" "${BACKTEST_MODEL:?}"
: "${BACKTEST_HOME:?}" "${BACKTEST_STATE_HOME:?}"
root=$BACKTEST_PLANWRIGHT_ROOT

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

The change under review is \`git diff $BACKTEST_BASE...HEAD\` in the current
directory, a detached checkout of the change's branch.

Run the Discovery step of $root/skills/self-review/SKILL.md over that diff:
read $root/doctrine/discovery-rigor.md and $root/doctrine/artifact-lenses.md,
select the lens set for the change's artifact class, walk every lens over the
diff inline in this session, then run the self-critique pass. Do not run the
project's tooling, validate, fix, or prune by severity.$ledger_text

If you run any command other than read-only git, prefix it with
HOME=$BACKTEST_HOME CLAUDE_PLUGIN_DATA=$BACKTEST_STATE_HOME.

End your reply with every finding, one per line, in exactly this form:
FINDING<TAB><repository-relative path><TAB><line number in HEAD><TAB><lens><TAB><one-line summary>
using a real tab character between fields. Print nothing after the last one."

out=$("$claude_bin" -p "$prompt" --model "$BACKTEST_MODEL" \
  --output-format json --max-turns "$max_turns" --add-dir "$root" \
  --allowedTools 'Read' 'Grep' 'Glob' 'Bash(git diff:*)' 'Bash(git log:*)' 'Bash(git show:*)' 'Bash(git blame:*)' \
  --disallowedTools 'Edit' 'Write' 'NotebookEdit' 'WebFetch' 'WebSearch' </dev/null 2>/dev/null) || {
  printf '%s\n' "$prog: the review session failed" >&2
  exit 1
}
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
