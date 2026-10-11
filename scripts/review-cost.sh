#!/bin/sh
# review-cost.sh — the review-effectiveness metrics: tokens per convergence run
# and the post-convergence finding rate, against the recorded baselines
# (review-effectiveness REQ-H1.4, REQ-H1.1, D-7).
#
# Runnable at any time, operator-local: it reads session transcripts, fleet
# events, and the operator's GitHub history, so it is an `eval:` task and never
# runs in CI. The closeout runs it over its window and records the output.
#
# TOKENS PER CONVERGENCE RUN, from the Claude Code transcripts. A run starts at
# a review-skill marker (a /polish, /self-review, or /blind-review command, or
# a Skill tool call naming one) and ends at the first of: a `gh pr create`
# call, a human message, a marker for any other skill, or the end of the
# session. Its tokens are every assistant message in that span (input, cache
# creation, cache read, and output, each message counted once by id) plus the
# session's sub-agent messages timestamped inside it. The unit's total is the
# session's fleet `result` events when the fleet logged any for it, else the
# whole transcript with its sub-agents; the run's share is run over unit. These
# boundaries are a heuristic, the same one the research seed measured with.
#
# THE POST-CONVERGENCE FINDING RATE, from the PR history and the miss ledger.
# Of the bot-reviewed PRs in the window (a review or thread by a bot account,
# the population the baselines measured), the share with a fixed external
# finding: a thread opened by anyone but the author# the author answered with a fix reply (review-backtest-lib.sh's predicate),
# or a `review-miss` ledger entry naming the PR. Also reported: the median
# fixed findings and external review rounds per such PR.
#
# THE BAR (REQ-H1.4, fixed before the window): both the finding rate and the
# median tokens per run below their baselines. A window with fewer than
# --min-window (default 15) bot-reviewed PRs gets no verdict.
#
# Usage:
#   review-cost.sh [--transcripts <dir>]... [--events <file>]...
#       [--history <file>] [--ledger-dir <dir>]... [--baselines <file>]
#       [--prs-from <N>] [--merged-after <YYYY-MM-DD>] [--min-window <N>]
#
#   --transcripts  a Claude Code project directory (<session>.jsonl files and
#                  <session>/subagents/); default every project directory of
#                  this repository's checkouts under ~/.claude/projects
#   --events       a fleet stream-json events.jsonl; default every worker's
#                  under the fleet home
#   --history      the normalized PR history review-backtest-refresh.sh
#                  writes; default a fresh fetch through it
#   --ledger-dir   repeatable; default the observation entries and archive
#                  under the spec root (a drained miss is still a miss)
#   --merged-after PRs merged on or after this date (UTC)
#   --baselines    default tests/fixtures/review-backtest/baselines.tsv
#
# Exit codes: 0 report printed; 2 usage or an unreadable input.
set -eu
LC_ALL=C
export LC_ALL
unset CDPATH

prog=review-cost
here=$(cd "$(dirname "$0")" && pwd)
repo_root=$(cd "$here/.." && pwd)
# shellcheck source=scripts/review-backtest-lib.sh
. "$here/review-backtest-lib.sh"

usage() {
  cat >&2 <<EOF
usage: $prog [--transcripts <dir>]... [--events <file>]... [--history <file>]
         [--ledger-dir <dir>] [--baselines <file>] [--prs-from <N>]
         [--merged-after <YYYY-MM-DD>] [--min-window <N>]
EOF
  exit 2
}
die() {
  printf '%s\n' "$prog: $2" >&2
  exit "$1"
}

tmp=$(mktemp -d "${TMPDIR:-/tmp}/rbt-cost.XXXXXX")
trap 'rm -rf "$tmp"' EXIT INT TERM
: >"$tmp/tdirs"
: >"$tmp/efiles"
history=
: >"$tmp/ldirs"
baselines=$repo_root/tests/fixtures/review-backtest/baselines.tsv
prs_from=1
merged_after=
min_window=15
while [ $# -gt 0 ]; do
  case $1 in
    --transcripts | --events | --history | --ledger-dir | --baselines | --prs-from | --merged-after | --min-window)
      [ $# -ge 2 ] || usage
      case $1 in
        --transcripts) printf '%s\n' "$2" >>"$tmp/tdirs" ;;
        --events) printf '%s\n' "$2" >>"$tmp/efiles" ;;
        --history) history=$2 ;;
        --ledger-dir) printf '%s\n' "$2" >>"$tmp/ldirs" ;;
        --baselines) baselines=$2 ;;
        --prs-from) prs_from=$2 ;;
        --merged-after) merged_after=$2 ;;
        --min-window) min_window=$2 ;;
      esac
      shift 2
      ;;
    *) usage ;;
  esac
done
rbt_is_uint "$prs_from" || die 2 "--prs-from must be a positive integer"
rbt_is_uint "$min_window" || die 2 "--min-window must be a positive integer"
case $merged_after in
  '' | [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]) ;;
  *) die 2 "--merged-after must be YYYY-MM-DD" ;;
esac

if [ ! -s "$tmp/tdirs" ]; then
  primary=$("$here/resolve-root.sh" repo --primary 2>/dev/null) || primary=$repo_root
  slug=$(printf '%s' "$primary" | tr '/.' '--')
  for d in "${HOME:-/nonexistent}/.claude/projects/$slug"*; do
    [ -d "$d" ] && printf '%s\n' "$d" >>"$tmp/tdirs"
  done
fi
if [ ! -s "$tmp/efiles" ] && [ -n "${CLAUDE_PLUGIN_DATA:-}" ]; then
  for f in "${CLAUDE_PLUGIN_DATA%/}"/fleet/streamjson/*/events.jsonl; do
    [ -f "$f" ] && printf '%s\n' "$f" >>"$tmp/efiles"
  done
fi
if [ ! -s "$tmp/ldirs" ]; then
  spec_root=$("$here/resolve-root.sh" spec 2>/dev/null) || spec_root=
  [ -z "$spec_root" ] || printf '%s\n%s\n' "$spec_root/_observations/entries" "$spec_root/_observations/archive" >"$tmp/ldirs"
fi

# --- tokens per convergence run ----------------------------------------------

# One event line per marker or message: S (run start), E (run end), or
# T <ts> <id> <tokens>. Both markers precede their message's tokens: the PR
# creation call is not review work, and the call that starts the review is.
# shellcheck disable=SC2016 # jq program text
events_jq='
def review: test("(^|[:/])(polish|self-review|blind-review)$");
def tok: (.message.usage // {}) | [.input_tokens, .cache_creation_input_tokens, .cache_read_input_tokens, .output_tokens] | map(. // 0) | add;
def text: if (.message.content | type) == "string" then .message.content
  else ([.message.content[]? | select(.type == "text") | .text] | join("\n")) end;
def is_result: (.message.content | type) == "array" and any(.message.content[]; .type == "tool_result");
fromjson? | select(type == "object") | (.timestamp // "") as $ts
| if .type == "assistant" then
    ([.message.content[]? | select(.type == "tool_use")]) as $tu
    | ([$tu[] | select(.name == "Skill") | (.input.skill // "")]) as $sk
    | (if any($tu[]; .name == "Bash" and ((.input.command // "") | test("gh pr create")))
          or any($sk[]; review | not) then ["E", $ts] else empty end),
      (if any($sk[]; review) then ["S", $ts] else empty end),
      ["T", $ts, (.message.id // ""), tok]
  elif .type == "user" and (is_result | not) and (.isMeta != true) then
    text as $t
    | ([$t | scan("<command-name>/?([^<]+)</command-name>") | .[0]]) as $cmd
    | if ($cmd | length) > 0 then
        (if any($cmd[]; review) then ["S", $ts] else ["E", $ts] end)
      elif ($t | length) > 0 and ($t | test("^\\s*<") | not) then ["E", $ts]
      else empty end
  else empty end
| map(tostring) | join("\t")'

: >"$tmp/runs.tsv"
: >"$tmp/units.tsv"
while IFS= read -r d; do
  [ -d "$d" ] || die 2 "a transcripts directory is not readable"
  for f in "$d"/*.jsonl; do
    [ -f "$f" ] || continue
    sid=$(basename "$f" .jsonl)
    jq -R -r "$events_jq" "$f" >"$tmp/ev.tsv" 2>/dev/null || : >"$tmp/ev.tsv"
    : >"$tmp/sub.tsv"
    for s in "$d/$sid"/subagents/*.jsonl; do
      [ -f "$s" ] || continue
      jq -R -r "$events_jq" "$s" 2>/dev/null | awk -F '\t' '$1 == "T"' >>"$tmp/sub.tsv" || true
    done
    # Runs of this session: sid, start, end, main-transcript tokens.
    awk -F '\t' -v sid="$sid" '
      function close_run(end_ts) { if (inrun) printf "%s\t%s\t%s\t%d\n", sid, start, end_ts, tok; inrun = 0 }
      $1 == "S" { if (!inrun) { inrun = 1; start = $2; tok = 0; delete seen } next }
      $1 == "E" { close_run($2); next }
      $1 == "T" { if (inrun && !($3 in seen)) { seen[$3] = 1; tok += $4 } last = $2 }
      END { close_run(last "~") }
    ' "$tmp/ev.tsv" >"$tmp/sruns.tsv"
    # Add each run's sub-agent tokens; then the session's unit total.
    awk -F '\t' 'BEGIN { OFS = "\t" }
      FILENAME == ARGV[1] { if (!($3 in seen)) { seen[$3] = 1; n++; ts[n] = $2; tk[n] = $4 } next }
      { add = 0; for (i = 1; i <= n; i++) if (ts[i] >= $2 && ts[i] < $3) add += tk[i]; print $1, $2, $3, $4 + add }
    ' "$tmp/sub.tsv" "$tmp/sruns.tsv" >>"$tmp/runs.tsv"
    total=$(cat "$tmp/ev.tsv" "$tmp/sub.tsv" | awk -F '\t' '$1 == "T" && !($3 in s) { s[$3] = 1; t += $4 } END { printf "%d", t }')
    printf '%s\t%s\n' "$sid" "$total" >>"$tmp/units.tsv"
  done
done <"$tmp/tdirs"

: >"$tmp/fleet.tsv"
while IFS= read -r e; do
  [ -f "$e" ] || continue
  jq -R -r 'fromjson? | select(type == "object" and .type == "result" and (.session_id | type) == "string")
    | [.session_id, ((.usage // {}) | [.input_tokens, .cache_creation_input_tokens, .cache_read_input_tokens, .output_tokens] | map(. // 0) | add)]
    | map(tostring) | join("\t")' "$e" >>"$tmp/fleet.tsv" 2>/dev/null || true
done <"$tmp/efiles"

# shellcheck disable=SC2016 # awk program text
# The median of numbers already sorted ascending (`sort -n` feeds it).
median='{ v[NR] = $1 } END {
  if (NR == 0) { print "n/a"; exit }
  m = (NR % 2) ? v[(NR + 1) / 2] : (v[NR / 2] + v[NR / 2 + 1]) / 2
  print m
}'
runs=$(wc -l <"$tmp/runs.tsv" | tr -d ' ')
med_tokens=$(cut -f4 "$tmp/runs.tsv" | sort -n | awk "$median")
med_share=$(awk -F '\t' '
  FILENAME == ARGV[1] { fleet[$1] += $2; next }
  FILENAME == ARGV[2] { unit[$1] = $2; next }
  { u = ($1 in fleet) ? fleet[$1] : unit[$1]; if (u > 0) print $4 / u }
' "$tmp/fleet.tsv" "$tmp/units.tsv" "$tmp/runs.tsv" | sort -n | awk "$median")

# --- the post-convergence finding rate ---------------------------------------

if [ -z "$history" ]; then
  "$here/review-backtest-refresh.sh" --fetch-only --dump-history "$tmp/history.json" >/dev/null \
    || die 2 "could not fetch the PR history; pass --history"
  history=$tmp/history.json
fi
[ -f "$history" ] && [ -r "$history" ] || die 2 "the history file is not readable"
jq -e '.prs | type == "array"' "$history" >/dev/null 2>&1 || die 2 "the history is not the normalized shape"

set --
while IFS= read -r d; do set -- "$@" "$d"; done <"$tmp/ldirs"
rbt_read_ledger "$tmp/ledger.tsv" "$@"
jq -R -s -c '[split("\n")[] | select(length > 0) | split("\t")[0] | tonumber]' "$tmp/ledger.tsv" >"$tmp/ledger.json"

jq -r --slurpfile led "$tmp/ledger.json" --argjson from "$prs_from" --arg after "$merged_after" "$RBT_JQ_DEFS"'
  [ .prs[] | select(.number >= $from) | select($after == "" or ((.merged_at // "") >= $after))
    | . as $p
    | { n: .number, ext: rbt_bot_reviewed,
        fixed: (([.threads[]? | select(rbt_fixed_external($p.author))] | length)
                + ([$led[0][] | select(. == $p.number)] | length)),
        rounds: ([.reviews[]? | select((.author // "") != $p.author)] | length),
        ledger: ([$led[0][] | select(. == $p.number)] | length) } ] as $w
  | ($w | map(select(.ext))) as $ext
  | ($ext | map(select(.fixed > 0))) as $hit
  | [($w | length), ($ext | length), ($hit | length), ($w | map(.ledger) | add // 0),
     ($hit | map(.fixed) | map(tostring) | join(",")), ($hit | map(.rounds) | map(tostring) | join(","))]
  | map(tostring) | join("\t")
' "$history" >"$tmp/rate.tsv" || die 2 "could not read the PR history"
IFS='	' read -r n_window n_ext n_hit n_ledger fixed_list rounds_list <"$tmp/rate.tsv" || true
rate=$(awk -v h="$n_hit" -v e="$n_ext" 'BEGIN { if (e > 0) printf "%.3f", h / e; else print "n/a" }')
med_fixed=$(printf '%s\n' "$fixed_list" | tr ',' '\n' | awk 'NF' | sort -n | awk "$median")
med_rounds=$(printf '%s\n' "$rounds_list" | tr ',' '\n' | awk 'NF' | sort -n | awk "$median")

# --- report and bar ------------------------------------------------------------

fmt_share=$(printf '%s\n' "$med_share" | awk '$1 == "n/a" { print; next } { printf "%.2f\n", $1 }')
printf '%s\n' "convergence runs: $runs"
printf '%s\n' "tokens per convergence run (median): $med_tokens"
printf '%s\n' "convergence share of unit (median): $fmt_share"
printf '%s\n' "PRs in window: $n_window"
printf '%s\n' "bot-reviewed PRs: $n_ext"
printf '%s\n' "PRs with a fixed post-convergence finding: $n_hit"
printf '%s\n' "post-convergence finding rate: $rate"
printf '%s\n' "fixed findings per such PR (median): $med_fixed"
printf '%s\n' "review rounds per such PR (median): $med_rounds"
printf '%s\n' "miss-ledger entries in window: $n_ledger"

if [ -f "$baselines" ] && [ -r "$baselines" ]; then
  b_rate=$(awk -F '\t' '$1 == "post_convergence_finding_rate" { print $2; exit }' "$baselines")
  b_tokens=$(awk -F '\t' '$1 == "median_tokens_per_convergence_run" { print $2; exit }' "$baselines")
  case $b_rate in '' | *[!0-9.]*) die 2 "the baselines' post_convergence_finding_rate is missing or not a number" ;; esac
  case $b_tokens in '' | *[!0-9]*) die 2 "the baselines' median_tokens_per_convergence_run is missing or not a number" ;; esac
  printf '%s\n' "baseline: rate $b_rate, tokens $b_tokens"
  verdict=$(awk -v r="$rate" -v br="$b_rate" -v t="$med_tokens" -v bt="$b_tokens" -v e="$n_ext" -v m="$min_window" 'BEGIN {
    if (e < m) { printf "window too small (%d < %d)", e, m; exit }
    if (r == "n/a" || t == "n/a" || br == "" || bt == "") { print "no verdict (a metric or baseline is missing)"; exit }
    rb = (r + 0 < br + 0); tb = (t + 0 < bt + 0)
    printf "rate below baseline: %s; tokens below baseline: %s; verdict: %s", rb ? "yes" : "no", tb ? "yes" : "no", (rb && tb) ? "met" : "missed"
  }')
  case $verdict in
    window* | no*) verdict="verdict: $verdict" ;;
  esac
  printf '%s\n' "$verdict"
else
  printf '%s\n' "baseline: none (the baselines file is missing or unreadable); no verdict"
fi
