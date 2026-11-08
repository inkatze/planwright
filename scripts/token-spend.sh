#!/bin/sh
# token-spend.sh: where a host's Claude tokens go. `rows` reads Claude Code
# transcripts one file at a time into one line per assistant message; `report`
# turns those lines into spend per session, per branch and per driver.
# `token-spend.sh --help` prints the contract. Read-only over every input.
#
# Usage: token-spend.sh rows [--since <YYYY-MM-DD>] [<transcript.jsonl>...]
#        token-spend.sh report [--prices <tsv>] [--idle <seconds>]
#            [--context-cap <tokens>] [--top <n>] <rows-file>
set -u
LC_ALL=C
export LC_ALL
unset CDPATH

prog=token-spend
here=$(cd "$(dirname "$0")" && pwd) || exit 2

usage() {
  cat >&2 <<'EOF'
usage: token-spend.sh rows [--since <YYYY-MM-DD>] [<transcript.jsonl>...]
       token-spend.sh report [--prices <tsv>] [--idle <seconds>]
           [--context-cap <tokens>] [--top <n>] <rows-file>
EOF
  exit 2
}

help_text() {
  cat <<'EOF'
token-spend.sh: where a host's Claude tokens go.

rows    Prints one tab-separated line per assistant message and one per
        transcript file, reading each file alone (grep, then jq) so a sweep
        never holds more than one transcript. With no files it walks every
        *.jsonl under $CLAUDE_CONFIG_DIR/projects (default ~/.claude/projects),
        sub-agent transcripts included, skipping files last written before
        --since. Lines:
          m <message-id> <session> main|sub <timestamp> <model> <input>
            <cache-write-5m> <cache-write-1h> <cache-write-total>
            <cache-read> <output> <cwd> <branch> <agent-id>
          s <session> main|sub <agent-id> <prompt-chars> <rules-chars>
            <prompt-head>
        A message the transcript writes on several lines (one per content
        block) is printed per line; report counts each message id once.

report  Reads rows output and prints totals by token class, model, day,
        session kind (read from each session's first prompt), the dearest
        sessions and branches, and each spend driver in tokens and dollars:
        cold starts, warm-up writes (main turns 2 to 10), cache rebuilds
        after an idle gap (--idle, default 3600 s, the 1-hour cache
        lifetime), cache reads above --context-cap (default 200000),
        sub-agents by prompt with their write and output share, sessions
        beyond the first on one branch, the first prompt and its rule block
        re-read every turn, output, and what main sessions would save by
        writing a 5-minute cache instead of the 1-hour one, net of the reads
        that gaps of 5 to 60 minutes would turn into rewrites. A session
        whose first prompt carries a mission-control rule block counts as
        mc-launched. Dollars use --prices (default config/token-prices.tsv);
        a model missing from it is priced at zero and named on stderr.

Exit: 0 printed; 2 usage or an unreadable input.
EOF
}

die() {
  printf '%s: %s\n' "$prog" "$1" >&2
  exit 2
}

command -v jq >/dev/null 2>&1 || die "jq is required"

# One message per line: the usage block, or the sum of its iterations when the
# top-level counters are zero (a resumed or server-iterated message).
# shellcheck disable=SC2016 # jq program, not shell
ROWS_JQ='
select(.type? == "assistant" and (.message.usage | type) == "object") |
.message.usage as $u |
(if (($u.input_tokens // 0) + ($u.cache_creation_input_tokens // 0)
     + ($u.cache_read_input_tokens // 0) + ($u.output_tokens // 0)) == 0
    and ($u.iterations | type) == "array"
 then reduce ($u.iterations[] | objects) as $x ({};
   .input_tokens += ($x.input_tokens // 0)
   | .cache_creation_input_tokens += ($x.cache_creation_input_tokens // 0)
   | .cache_read_input_tokens += ($x.cache_read_input_tokens // 0)
   | .output_tokens += ($x.output_tokens // 0)
   | .cache_creation.ephemeral_5m_input_tokens += ($x.cache_creation.ephemeral_5m_input_tokens? // 0)
   | .cache_creation.ephemeral_1h_input_tokens += ($x.cache_creation.ephemeral_1h_input_tokens? // 0))
 else $u end) as $v |
["m", (.message.id // .uuid // ""), (.sessionId // ""),
 (if .isSidechain == true then "sub" else "main" end),
 (.timestamp // ""), (.message.model // "unknown"),
 ($v.input_tokens // 0), ($v.cache_creation.ephemeral_5m_input_tokens? // 0),
 ($v.cache_creation.ephemeral_1h_input_tokens? // 0), ($v.cache_creation_input_tokens // 0),
 ($v.cache_read_input_tokens // 0), ($v.output_tokens // 0),
 (.cwd // ""), (.gitBranch // ""), (.agentId // "")] | @tsv'

# shellcheck disable=SC2016 # jq program, not shell
PROMPT_JQ='
fromjson? | select(type == "object" and .type == "user") |
(.message.content | if type == "string" then .
  elif type == "array" then ([.[]? | select(.type? == "text") | .text] | join(" "))
  else "" end) as $t |
select(($t | length) > 0 and ($t | test("^<(local-command|system-reminder)") | not)) |
($t | index("<!-- mc-rules begin")) as $b | ($t | index("<!-- mc-rules end")) as $e |
["s", (.sessionId // ""), (if .isSidechain == true then "sub" else "main" end), (.agentId // ""),
 ($t | length), (if $b != null and $e != null then $e - $b else 0 end),
 ($t[0:160])] | @tsv'

rows_of() {
  rf=$1
  [ -r "$rf" ] || {
    printf '%s: unreadable, skipped: %s\n' "$prog" "$rf" >&2
    return 0
  }
  # The fast parse stops at a malformed line (a live transcript's torn tail);
  # the slow one skips it. report counts a message printed twice once.
  grep -F '"type":"assistant"' "$rf" 2>/dev/null | jq -r "$ROWS_JQ" 2>/dev/null \
    || grep -F '"type":"assistant"' "$rf" 2>/dev/null | jq -Rr "fromjson? | $ROWS_JQ" 2>/dev/null
  grep -m 8 -F '"type":"user"' "$rf" 2>/dev/null | jq -Rr "$PROMPT_JQ" 2>/dev/null | head -n 1
}

cmd_rows() {
  since=""
  while [ $# -gt 0 ]; do
    case $1 in
      --since)
        [ $# -ge 2 ] || usage
        since=$2
        shift 2
        ;;
      --)
        shift
        break
        ;;
      -*) usage ;;
      *) break ;;
    esac
  done
  if [ $# -gt 0 ]; then
    for f in "$@"; do rows_of "$f"; done
    return 0
  fi
  root=${CLAUDE_CONFIG_DIR:-$HOME/.claude}/projects
  [ -d "$root" ] || die "no transcript directory: $root"
  stamp=""
  if [ -n "$since" ]; then
    case $since in
      [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]) ;;
      *) die "--since takes YYYY-MM-DD" ;;
    esac
    stamp=$(mktemp "${TMPDIR:-/tmp}/token-spend.XXXXXX") || die "mktemp failed"
    # shellcheck disable=SC2064
    trap "rm -f '$stamp'" EXIT
    touch -t "$(printf '%s' "$since" | tr -d '-')0000" "$stamp" || die "bad --since date"
  fi
  if [ -n "$stamp" ]; then
    find "$root" -type f -name '*.jsonl' -newer "$stamp"
  else
    find "$root" -type f -name '*.jsonl'
  fi | while IFS= read -r f; do rows_of "$f"; done
}

cmd_report() {
  prices=$here/../config/token-prices.tsv
  idle=3600
  cap=200000
  top=10
  while [ $# -gt 0 ]; do
    case $1 in
      --prices | --idle | --context-cap | --top)
        [ $# -ge 2 ] || usage
        case $1 in
          --prices) prices=$2 ;;
          --idle) idle=$2 ;;
          --context-cap) cap=$2 ;;
          --top) top=$2 ;;
        esac
        shift 2
        ;;
      --)
        shift
        break
        ;;
      -*) usage ;;
      *) break ;;
    esac
  done
  [ $# -eq 1 ] || usage
  for n in "$idle" "$cap" "$top"; do
    case $n in '' | *[!0-9]*) die "--idle, --context-cap and --top take whole numbers" ;; esac
  done
  [ -f "$1" ] && [ -r "$1" ] || die "unreadable rows file: $1"
  [ -r "$prices" ] || die "unreadable price table: $prices"
  sort -t "$(printf '\t')" -k1,1 -k3,3 -k5,5 "$1" \
    | awk -F '\t' -v idle="$idle" -v cap="$cap" -v top="$top" -f "$here/token-spend-report.awk" "$prices" -
}

[ $# -ge 1 ] || usage
verb=$1
shift
case $verb in
  rows) cmd_rows "$@" ;;
  report) cmd_report "$@" ;;
  -h | --help) help_text ;;
  *) usage ;;
esac
