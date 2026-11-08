#!/bin/sh
# token-spend.sh: where a host's Claude tokens go. `rows` reads Claude Code
# transcripts one file at a time into one line per assistant message; `report`
# turns those lines into spend per session, per branch and per driver.
# `token-spend.sh --help` prints the contract. Read-only over every input;
# operator-local (it reads the host's transcripts), so it never runs in CI.
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

rows    Prints one tab-separated line per assistant message and at most one
        per transcript file, reading each file alone (grep, then jq) so a
        sweep never holds more than one transcript. With no files it walks
        every *.jsonl under $CLAUDE_CONFIG_DIR/projects (default
        ~/.claude/projects), sub-agent transcripts included; --since (walk
        only) skips files last written before local midnight of that date,
        so a file written since still contributes its older messages. Lines:
          m <message-id> <session> main|sub <timestamp> <model> <input>
            <cache-write-5m> <cache-write-1h> <cache-write-total>
            <cache-read> <output> <cwd> <branch> <agent-id>
          s <session> main|sub <agent-id> <prompt-chars> <rules-chars>
            <prompt-head>
        The s line is the file's first user prompt that is not a system or
        local-command message, from its first eight user lines. A message the
        transcript writes on several lines (one per content block) is printed
        per line; report counts each message id once. A message with no id
        prints `-` and is never merged. A file that cannot be read is named
        on stderr and skipped, and rows then exits 1.

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
        Control bytes in transcript text are dropped before printing.

Exit: 0 printed; 1 rows skipped a file it could not read or list;
      2 usage, a missing tool or transcript directory, an unreadable rows
      file, or an unreadable or malformed price table.
EOF
}

die() {
  printf '%s: %s\n' "$prog" "$2" >&2
  exit "$1"
}

clean() { printf '%s' "$1" | tr -d '\000-\010\013-\037\177'; }

scratch=""
cleanup() { [ -z "$scratch" ] || rm -rf "$scratch"; }
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
scratch_dir() {
  [ -n "$scratch" ] || scratch=$(mktemp -d "${TMPDIR:-/tmp}/token-spend.XXXXXX") || die 2 "mktemp failed"
}

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
["m", ([.message.id, .uuid] | map(select(. != null and . != "")) | .[0] // "-"), (.sessionId // ""),
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
 ($t | length), (if $b != null and $e != null and $e > $b then $e - $b else 0 end),
 ($t[0:160])] | @tsv'

skipped=0

# rows_of <file>: the file's rows. The fast parse stops at a malformed line
# (a live transcript's torn tail), so its output is kept only when it parsed
# the whole file; otherwise the slow parse, which skips such lines, runs alone.
rows_of() {
  rf=$1
  if [ ! -f "$rf" ] || [ ! -r "$rf" ]; then
    printf '%s: unreadable, skipped: %s\n' "$prog" "$(clean "$rf")" >&2
    skipped=1
    return 0
  fi
  if out=$(grep -F -e '"type":"assistant"' -- "$rf" | jq -r "$ROWS_JQ" 2>/dev/null); then
    [ -z "$out" ] || printf '%s\n' "$out"
  else
    grep -F -e '"type":"assistant"' -- "$rf" | jq -Rr "fromjson? | $ROWS_JQ" 2>/dev/null
  fi
  grep -m 8 -F -e '"type":"user"' -- "$rf" | jq -Rr "$PROMPT_JQ" 2>/dev/null | head -n 1
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
  command -v jq >/dev/null 2>&1 || die 2 "jq is required"
  if [ -n "$since" ]; then
    case $since in
      [0-9][0-9][0-9][0-9]-[01][0-9]-[0-3][0-9]) ;;
      *) die 2 "--since takes YYYY-MM-DD" ;;
    esac
    [ $# -eq 0 ] || die 2 "--since applies to the transcript walk, not to named files"
  fi
  if [ $# -gt 0 ]; then
    for f in "$@"; do rows_of "$f"; done
    [ "$skipped" -eq 0 ] || exit 1
    return 0
  fi
  root=${CLAUDE_CONFIG_DIR:-$HOME/.claude}/projects
  [ -d "$root" ] || die 2 "no transcript directory: $(clean "$root")"
  scratch_dir
  list=$scratch/files
  if [ -n "$since" ]; then
    touch -t "$(printf '%s' "$since" | tr -d '-')0000" "$scratch/since" 2>/dev/null || die 2 "not a date: $since"
    find "$root" -type f -name '*.jsonl' -newer "$scratch/since" >"$list" || skipped=1
  else
    find "$root" -type f -name '*.jsonl' >"$list" || skipped=1
  fi
  while IFS= read -r f; do rows_of "$f"; done <"$list"
  [ "$skipped" -eq 0 ] || exit 1
}

cmd_report() {
  prices=$here/../config/token-prices.tsv
  idle=3600
  cap=200000
  top=10
  while [ $# -gt 0 ]; do
    case $1 in
      --prices | --idle | --context-cap | --top) [ $# -ge 2 ] || usage ;;
      --) shift && break ;;
      -*) usage ;;
      *) break ;;
    esac
    case $1 in
      --prices) prices=$2 ;;
      --idle) idle=$2 ;;
      --context-cap) cap=$2 ;;
      --top) top=$2 ;;
    esac
    shift 2
  done
  [ $# -eq 1 ] || usage
  for n in "$idle" "$cap" "$top"; do
    case $n in '' | *[!0-9]*) die 2 "--idle, --context-cap and --top take whole numbers" ;; esac
  done
  [ -f "$1" ] && [ -r "$1" ] || die 2 "unreadable rows file: $(clean "$1")"
  [ -f "$prices" ] && [ -r "$prices" ] && [ -s "$prices" ] || die 2 "unreadable or empty price table: $(clean "$prices")"
  scratch_dir
  sort -t "$(printf '\t')" -k1,1 -k3,3 -k5,5 "$1" >"$scratch/sorted" || die 2 "sorting the rows failed"
  awk -F '\t' -v prog="$prog" -v idle="$idle" -v cap="$cap" -v top="$top" \
    -f "$here/token-spend-lib.awk" -f "$here/token-spend-report.awk" "$prices" "$scratch/sorted"
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
