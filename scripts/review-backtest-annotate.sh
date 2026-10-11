#!/bin/sh
# review-backtest-annotate.sh — the default annotator for
# review-backtest-refresh.sh (review-effectiveness REQ-H1.2, D-7, D-16).
#
# Reads annotation requests as JSON lines on stdin (one per fixed external
# finding: key, pr, path, line, finding, reply, declined_log, label_reason) and
# prints one JSON line per request: {key, category, gist, declined,
# dismissal?, reason?}. One headless model call per batch, through the
# operator's own `claude` login; operator-local only, like its caller.
#
# The gist and the dismissal are paraphrases: the refresh drops any that
# repeats the comment's wording or names a login, and screens the rest, so this
# prompt asks for
# the defect in fresh words and never for a quote, a login, or a product name.
#
# Environment:
#   PLANWRIGHT_BACKTEST_CLAUDE   the claude binary (default: claude)
#   PLANWRIGHT_BACKTEST_MODEL    the model for the call (default: the CLI's)
#
# Exit codes: 0 answers printed (possibly fewer than requested; the refresh
# counts the gap); 1 the model call failed, reported an error, or returned no
# result, or a class in the shared vocabulary has no description here.
set -eu
unset CDPATH

prog=review-backtest-annotate
here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=scripts/review-backtest-lib.sh
. "$here/review-backtest-lib.sh"

claude_bin=${PLANWRIGHT_BACKTEST_CLAUDE:-claude}
batch=$(cat)
[ -n "$batch" ] || exit 0

# The class list is the shared vocabulary; `declined` comes from the declined-log
# match, never from this choice. A class added to the vocabulary without a
# description here stops the run rather than going unoffered.
reason_lines=
for r in $RBT_REASONS; do
  case $r in
    outside-diff) d='seeing it needed code outside the changed lines (callers, other files)' ;;
    runtime-tracing) d="seeing it needed running or tracing the code's behaviour" ;;
    claim-vs-code) d='a comment, doc, header, usage text, or PR claim disagrees with the code' ;;
    pruned) d='it was visible in the changed lines, or a twin site of a fixed one was left unswept' ;;
    spec-conflict) d='it conflicts with a spec, doctrine rule, or repository convention' ;;
    lintable) d='a shell-lint or formatter rule could have caught it' ;;
    other) d='none of the above fits' ;;
    declined) continue ;;
    *)
      printf '%s\n' "$prog: no description for a miss reason in the vocabulary" >&2
      exit 1
      ;;
  esac
  reason_lines="$reason_lines  $r: $d
"
done

prompt="You annotate fixed code-review findings for a regression corpus.
The input below is JSON lines, one finding per line: key, pr, path, line,
finding (the review comment that raised it), reply (the author's fix reply),
declined_log (lines of the PR body's declined log naming the same file), and
label_reason.

For EVERY input line print exactly one JSON object on its own line, and print
nothing else (no prose, no code fences):
{\"key\": <the input key, unchanged>, \"category\": <one of: $RBT_CATEGORIES>,
 \"gist\": <one plain sentence, at most 200 characters, naming the defect in
 your own words>, \"declined\": <true or false>, \"dismissal\": <see below>,
 \"reason\": <only when label_reason is true; see below>}

gist: describe what was wrong, in fresh words. Never copy a phrase of five or
more words from the finding or the reply. Never include a person's or bot's
name or @login, a product or tool brand name, a URL, or an absolute path.

declined: true only when a declined_log line clearly records this same defect
being declined earlier; then dismissal is one plain sentence (at most 200
characters, your own words, same rules as gist) saying why it was declined.
Otherwise declined is false and dismissal is omitted.

reason (only when label_reason is true): why a reviewer reading the change
missed this defect, one of:
$reason_lines"

# The input is untrusted review text: the call gets no tools, no MCP servers,
# no settings files (restricted mode), and no permission prompt an auto mode
# could approve.
set -- --output-format json --max-turns 1 --tools '' --permission-mode dontAsk \
  --strict-mcp-config --restricted
[ -z "${PLANWRIGHT_BACKTEST_MODEL:-}" ] || set -- "$@" --model "$PLANWRIGHT_BACKTEST_MODEL"
# In the background so a TERM sent to this script ends the call too.
outf=$(mktemp "${TMPDIR:-/tmp}/rbt-annotate.XXXXXX")
cpid=
trap 'rm -f "$outf"' EXIT
trap '[ -z "$cpid" ] || kill "$cpid" 2>/dev/null; exit 143' TERM
trap '[ -z "$cpid" ] || kill "$cpid" 2>/dev/null; exit 130' INT
printf '%s\n' "$batch" | "$claude_bin" -p "$prompt" "$@" >"$outf" 2>/dev/null &
cpid=$!
crc=0
wait "$cpid" || crc=$?
cpid=
if [ "$crc" -ne 0 ]; then
  printf '%s\n' "$prog: the model call failed" >&2
  exit 1
fi
out=$(cat "$outf")
if [ "$(printf '%s\n' "$out" | jq -r '.is_error // false' 2>/dev/null)" != false ]; then
  printf '%s\n' "$prog: the model call reported an error" >&2
  exit 1
fi
result=$(printf '%s\n' "$out" | jq -r '.result // empty' 2>/dev/null) || result=
if [ -z "$result" ]; then
  printf '%s\n' "$prog: the model call returned no result" >&2
  exit 1
fi
printf '%s\n' "$result" | jq -c -R 'fromjson? | select(type == "object" and has("key"))'
