#!/bin/sh
# inception-notion.sh — the Notion reference adapter for a venture's review
# cycle (inception REQ-G1.7 · D-10).
#
# An adapter moves bytes and nothing else. It sends a snapshot to the review
# surface and reads feedback back out as data; the cycle around it (when an
# export may happen, which items exist, what was decided, what was applied) is
# scripts/inception-review-cycle.sh's, under the contract in
# doctrine/review-seam.md. Nothing here writes a bundle file.
#
#   configure  record the destination page and, optionally, a token file
#   status     print the destination and where the token comes from
#   export     replace the page's content with a snapshot (Markdown Content
#              API, `replace_content`)
#   harvest    print every unresolved comment on the page and on its blocks,
#              as seam item records
#   parse-comments, parse-blocks
#              the pure transforms harvest applies to one API response; also
#              how the parser fixtures exercise them
#
# The Notion API is pinned to one version (NOTION_VERSION below). Its comment
# list returns unresolved comments only, carries no resolved field and no text
# range, and cannot resolve a comment, so a comment stays on the page after it
# is dispositioned: the seam's ledger, keyed by comment id, is the only record
# of what became of it. The comment endpoints need the integration's "Read
# comments" capability, which Notion ships switched off.
#
# Destination and token are machine-local. The page id lives in the clone's
# git directory (planwright-notion.local beside HEAD), never in the work tree:
# anything in the work tree arrives with a pull, so a commit could otherwise
# redirect the next export. The file is read as data, never sourced. The token
# comes from PLANWRIGHT_NOTION_TOKEN, else from the first line of the file
# `configure --token-file` named, which must be a regular file (never a
# symbolic link, whose own mode says nothing about its target) not readable by
# group or others; only the path is recorded. The token reaches curl through its config
# on stdin, never the command line, and its charset is checked first so it
# cannot rewrite that config. Every id taken from an API response is checked
# against the Notion id grammar before it is put into a URL.
#
# Usage:
#   inception-notion.sh configure --page <page-id> [--token-file <path>] <venture-dir>
#   inception-notion.sh status <venture-dir>
#   inception-notion.sh export <venture-dir> <snapshot-file>
#   inception-notion.sh harvest <venture-dir>
#   inception-notion.sh parse-comments <payload.json> [<anchor-text>]
#   inception-notion.sh parse-blocks <payload.json>
#
# Item records (harvest, parse-comments), tab-separated, one per comment, every
# field escaped as jq's @tsv escapes (\t, \n, \r, \\) and stripped of other
# control characters:
#   item  <source>  <thread>  <author>  <created>  <anchor>  <anchor-text>  <text>
# where <source> is notion:comment:<id>, <thread> the discussion id, <anchor>
# the commented block's id or `page`. harvest ends with
#   summary  complete|partial  <blocks-walked>
# `partial` when the walk stopped at PLANWRIGHT_NOTION_MAX_BLOCKS; comments on
# blocks past that point were not read.
#
# Environment:
#   PLANWRIGHT_NOTION_TOKEN       the integration token (outranks the file)
#   PLANWRIGHT_NOTION_MAX_BLOCKS  block-walk bound, a whole number, default 1000
#   PLANWRIGHT_NOTION_BACKOFF     seconds before the first retry of a rate
#                                 limit or server error, doubling; default 1.
#                                 A Retry-After the API sends outranks it,
#                                 capped at RETRY_AFTER_MAX seconds.
#
# Exit: 0 done · 1 the API refused or could not be reached · 2 usage or
#   environment error · 3 not configured (no page, or no token).
#
# POSIX sh; needs curl and jq (1.6 or later) on PATH.
set -u

LC_ALL=C
export LC_ALL
unset CDPATH

NOTION_VERSION=2026-03-11
API=https://api.notion.com
STATE_NAME=planwright-notion.local
RETRY_AFTER_MAX=60

die() {
  code=$1
  shift
  printf 'inception-notion: %s\n' "$*" >&2
  exit "$code"
}

usage() {
  cat >&2 <<'EOF'
usage: inception-notion.sh configure --page <page-id> [--token-file <path>] <venture-dir>
       inception-notion.sh status <venture-dir>
       inception-notion.sh export <venture-dir> <snapshot-file>
       inception-notion.sh harvest <venture-dir>
       inception-notion.sh parse-comments <payload.json> [<anchor-text>]
       inception-notion.sh parse-blocks <payload.json>
EOF
  exit 2
}

need_jq() {
  command -v jq >/dev/null 2>&1 || die 2 "jq is required and was not found on PATH"
}

# The Notion id grammar: a UUID, dashed or not. Anything else from a response
# is dropped rather than interpolated into a path.
JQ_DEFS='
def nid: type == "string" and test("^[0-9a-fA-F]{8}-?[0-9a-fA-F]{4}-?[0-9a-fA-F]{4}-?[0-9a-fA-F]{4}-?[0-9a-fA-F]{12}$");
def clean: [splits("\n")] | map([splits("\t")] | map(gsub("[[:cntrl:]]"; "")) | join("\t")) | join("\n");
def oneline: gsub("[[:cntrl:]]"; " ");
def runs: [.[]? | .plain_text // empty | strings] | join("");
'

parse_comments() {
  need_jq
  jq -r --arg anchor_text "${2:-}" "$JQ_DEFS"'
    .results[]?
    | select(.id | nid)
    | [ "item",
        ("notion:comment:" + .id),
        ((.discussion_id // "") | if nid then . else "" end),
        ((.display_name.resolved_name // "") | strings | oneline
          | if . == "" then null else . end)
          // ("notion-user:" + ((.created_by.id // "unknown") | tostring | oneline)),
        ((.created_time // "") | tostring | oneline),
        (if .parent.type == "block_id" and (.parent.block_id | nid) then .parent.block_id else "page" end),
        ($anchor_text | oneline),
        (.rich_text | runs | clean) ]
    | @tsv' "$1"
}

parse_blocks() {
  need_jq
  jq -r "$JQ_DEFS"'
    .results[]?
    | select(.id | nid)
    | . as $b
    | [ .id,
        (if .has_children == true and (.type != "child_page" and .type != "child_database") then "1" else "0" end),
        (($b[$b.type].rich_text // []) | runs | oneline | gsub("[\\\\]"; "") | .[0:80]) ]
    | @tsv' "$1"
}

# next_cursor <payload> — the next page's cursor, or nothing on the last page;
# status 1 when more pages follow but the cursor fails its grammar, since
# stopping there would report a partial read as complete.
next_cursor() {
  [ "$(jq -r '.has_more == true' "$1")" = true ] || return 0
  _nc=$(jq -r '.next_cursor // "" | strings' "$1" | awk '/^[A-Za-z0-9-]+$/ { print; exit }')
  [ -n "$_nc" ] || return 1
  printf '%s\n' "$_nc"
}

NO_CURSOR="Notion said more results follow but gave no usable cursor; the harvest stops rather than report a partial read as complete"

# --- arguments ---------------------------------------------------------------

[ $# -ge 1 ] || usage
cmd=$1
shift

case $cmd in
  parse-comments)
    [ $# -ge 1 ] && [ $# -le 2 ] || usage
    parse_comments "$@"
    exit $?
    ;;
  parse-blocks)
    [ $# -eq 1 ] || usage
    parse_blocks "$1"
    exit $?
    ;;
  configure | status | export | harvest) ;;
  *) usage ;;
esac

page_arg=
token_file_arg=
target=
snapshot=
while [ $# -gt 0 ]; do
  case $1 in
    --page)
      [ "$cmd" = configure ] && [ $# -ge 2 ] || usage
      page_arg=$2
      shift 2
      ;;
    --token-file)
      [ "$cmd" = configure ] && [ $# -ge 2 ] || usage
      token_file_arg=$2
      shift 2
      ;;
    -*) usage ;;
    *)
      if [ -z "$target" ]; then
        target=$1
      elif [ "$cmd" = export ] && [ -z "$snapshot" ]; then
        snapshot=$1
      else
        usage
      fi
      shift
      ;;
  esac
done
[ -n "$target" ] || usage
[ "$cmd" != export ] || [ -n "$snapshot" ] || usage

[ -d "$target" ] || die 2 "venture directory not found"
gitdir=$(git -C "$target" rev-parse --absolute-git-dir 2>/dev/null) \
  || die 2 "the venture is not a git clone, so there is no machine-local place for the destination"
state="$gitdir/$STATE_NAME"

# normalize_page <id> — lowercase, dashed; empty when the id is malformed.
normalize_page() {
  # Length and class tested apart: old BSD awks do not read interval
  # expressions such as {32}.
  printf '%s\n' "$1" | tr 'A-F' 'a-f' | tr -d '-' | awk '
    length($0) == 32 && $0 !~ /[^0-9a-f]/ {
      print substr($0, 1, 8) "-" substr($0, 9, 4) "-" substr($0, 13, 4) "-" substr($0, 17, 4) "-" substr($0, 21, 12)
    }'
}

state_value() {
  [ -f "$state" ] || return 0
  awk -v k="$1" 'index($0, k "=") == 1 { print substr($0, length(k) + 2); exit }' "$state"
}

# file_private <path> — no read bit for group or others.
file_private() {
  [ -z "$(find "$1" -prune \( -perm -040 -o -perm -004 \) 2>/dev/null)" ]
}

if [ "$cmd" = configure ]; then
  [ -n "$page_arg" ] || usage
  page=$(normalize_page "$page_arg")
  [ -n "$page" ] || die 2 "--page must be a Notion page id (32 hex digits, dashes optional)"
  token_file=$(state_value token_file)
  if [ -n "$token_file_arg" ]; then
    case $token_file_arg in
      /*) ;;
      *) die 2 "--token-file must be an absolute path" ;;
    esac
    case $token_file_arg in
      *'
'*) die 2 "--token-file must not contain a newline" ;;
    esac
    [ ! -L "$token_file_arg" ] || die 2 "the token file is a symbolic link, whose permissions say nothing about its target; point --token-file at the file itself"
    [ -f "$token_file_arg" ] && [ -r "$token_file_arg" ] || die 2 "--token-file is not a readable file"
    file_private "$token_file_arg" \
      || die 2 "the token file is readable by group or others; chmod 600 it first"
    token_file=$token_file_arg
  fi
  tmpstate=$(mktemp "$gitdir/$STATE_NAME.XXXXXX") || die 2 "cannot write in the git directory"
  {
    printf 'page=%s\n' "$page"
    [ -z "$token_file" ] || printf 'token_file=%s\n' "$token_file"
  } >"$tmpstate" || {
    rm -f "$tmpstate"
    die 2 "cannot write $STATE_NAME in the git directory"
  }
  mv "$tmpstate" "$state" || {
    rm -f "$tmpstate"
    die 2 "cannot write $STATE_NAME in the git directory"
  }
  printf 'page\t%s\n' "$page"
  exit 0
fi

page=$(normalize_page "$(state_value page)")
token_file=$(state_value token_file)

if [ "$cmd" = status ]; then
  printf 'page\t%s\n' "${page:-none}"
  if [ -n "${PLANWRIGHT_NOTION_TOKEN:-}" ]; then
    printf 'token\tenvironment\n'
  elif [ -n "$token_file" ]; then
    printf 'token\tfile\n'
  else
    printf 'token\tmissing\n'
  fi
  exit 0
fi

[ -n "$page" ] || die 3 "no Notion page is configured for this clone; run: inception-notion.sh configure --page <page-id> <venture-dir>"

if [ -n "${PLANWRIGHT_NOTION_TOKEN:-}" ]; then
  token=$PLANWRIGHT_NOTION_TOKEN
elif [ -n "$token_file" ]; then
  [ ! -L "$token_file" ] || die 2 "the configured token file is now a symbolic link; point configure --token-file at the file itself"
  [ -f "$token_file" ] && [ -r "$token_file" ] || die 2 "the configured token file is missing or unreadable"
  file_private "$token_file" || die 2 "the token file is readable by group or others; chmod 600 it first"
  token=$(sed -n 1p "$token_file")
else
  die 3 "no Notion token: set PLANWRIGHT_NOTION_TOKEN or configure --token-file"
fi
case $token in
  '' | *[!A-Za-z0-9_.-]*) die 2 "the Notion token has characters a Notion token never carries; check the token file" ;;
esac

command -v curl >/dev/null 2>&1 || die 2 "curl is required and was not found on PATH"
need_jq

max_blocks=${PLANWRIGHT_NOTION_MAX_BLOCKS:-1000}
case $max_blocks in '' | *[!0-9]*) die 2 "PLANWRIGHT_NOTION_MAX_BLOCKS must be a whole number" ;; esac
backoff=${PLANWRIGHT_NOTION_BACKOFF:-1}
case $backoff in '' | *[!0-9]*) die 2 "PLANWRIGHT_NOTION_BACKOFF must be a whole number" ;; esac

work=$(mktemp -d "${TMPDIR:-/tmp}/inception-notion.XXXXXX") || die 2 "cannot create a scratch directory"
trap 'rm -rf "$work"' EXIT
trap 'exit 2' HUP INT TERM
resp="$work/resp.json"

# request <method> <path> [<body-file>] — leaves the body in $resp, the status
# in $http. Rate limits and server errors are retried with a doubling wait.
request() {
  _m=$1 _p=$2 _b=${3:-}
  _try=0
  _wait=$backoff
  while :; do
    : >"$resp"
    : >"$work/headers"
    if [ -n "$_b" ]; then
      http=$(printf 'header = "Authorization: Bearer %s"\nheader = "Notion-Version: %s"\n' "$token" "$NOTION_VERSION" \
        | curl -sS -K - --proto =https --connect-timeout 15 --max-time 120 -o "$resp" -D "$work/headers" -w '%{http_code}' \
          -X "$_m" -H 'Content-Type: application/json' --data-binary "@$_b" "$API$_p" 2>"$work/curl.err")
    else
      http=$(printf 'header = "Authorization: Bearer %s"\nheader = "Notion-Version: %s"\n' "$token" "$NOTION_VERSION" \
        | curl -sS -K - --proto =https --connect-timeout 15 --max-time 120 -o "$resp" -D "$work/headers" -w '%{http_code}' \
          "$API$_p" 2>"$work/curl.err")
    fi
    _rc=$?
    case $_rc:$http in
      0:2??) return 0 ;;
      0:429 | 0:500 | 0:502 | 0:503 | 0:504 | 0:529 | [!0]*) ;;
      *) fail_request ;;
    esac
    _try=$((_try + 1))
    if [ "$_try" -ge 4 ]; then
      [ "$_rc" -eq 0 ] || die 1 "could not reach the Notion API ($(tr -d '\000-\037\177\200-\237' <"$work/curl.err" | cut -c1-200))"
      fail_request
    fi
    # The server's own Retry-After (seconds; Notion sends it on a 429) outranks
    # the doubling wait, capped so a hostile or broken value cannot park the
    # harvest. A date-form value is not parsed and falls back to the doubling.
    _ra=$(awk 'tolower($0) ~ /^retry-after:/ { v = $2; gsub(/[^0-9]/, "", v); print v; exit }' "$work/headers" 2>/dev/null)
    if [ -n "$_ra" ]; then
      [ "${#_ra}" -le 4 ] && [ "$_ra" -le "$RETRY_AFTER_MAX" ] || _ra=$RETRY_AFTER_MAX
      [ "$_ra" -eq 0 ] || sleep "$_ra"
    else
      [ "$_wait" -eq 0 ] || sleep "$_wait"
    fi
    _wait=$((_wait * 2))
  done
}

fail_request() {
  code=$(jq -r '.code // empty | strings' "$resp" 2>/dev/null | tr -cd 'a-z_' | cut -c1-40)
  case $http in
    401) die 1 "Notion rejected the token (401${code:+ $code}); check the integration token" ;;
    403) die 1 "the integration lacks a capability on this page (403${code:+ $code}): a harvest needs Read content and Read comments (Notion ships comment capabilities off), an export needs Update content" ;;
    404) die 1 "Notion found no such page or block (404${code:+ $code}); is the page shared with the integration?" ;;
    *) die 1 "the Notion API answered $http${code:+ ($code)}" ;;
  esac
}

if [ "$cmd" = export ]; then
  [ -f "$snapshot" ] && [ -r "$snapshot" ] || die 2 "snapshot file not found or unreadable"
  jq -n --rawfile s "$snapshot" '{type: "replace_content", replace_content: {new_str: $s}}' >"$work/body.json" \
    || die 2 "cannot build the request body"
  request PATCH "/v1/pages/$page/markdown" "$work/body.json"
  if [ "$(jq -r '.truncated // false' "$resp" 2>/dev/null)" = true ]; then
    printf '%s\n' "inception-notion: Notion reports the page as truncated; part of the snapshot may not show" >&2
  fi
  printf 'destination\tnotion:%s\n' "$page"
  exit 0
fi

# --- harvest -----------------------------------------------------------------

items="$work/items.tsv"
blocks="$work/blocks.tsv"
queue="$work/queue"
: >"$items"
: >"$blocks"

# comments_of <block-id> <anchor-text>
comments_of() {
  _cursor=
  while :; do
    request GET "/v1/comments?block_id=$1&page_size=100${_cursor:+&start_cursor=$_cursor}"
    parse_comments "$resp" "$2" >>"$items" || die 1 "a comments response did not parse"
    _cursor=$(next_cursor "$resp") || die 1 "$NO_CURSOR"
    [ -n "$_cursor" ] || break
  done
}

comments_of "$page" ""

printf '%s\n' "$page" >"$queue"
walked=0
status=complete
qpos=1
while :; do
  parent=$(sed -n "${qpos}p" "$queue")
  [ -n "$parent" ] || break
  qpos=$((qpos + 1))
  cursor=
  while :; do
    request GET "/v1/blocks/$parent/children?page_size=100${cursor:+&start_cursor=$cursor}"
    parse_blocks "$resp" >"$work/children.tsv" || die 1 "a block-children response did not parse"
    while IFS="$(printf '\t')" read -r bid kids snippet; do
      if [ "$walked" -ge "$max_blocks" ]; then
        status=partial
        break
      fi
      walked=$((walked + 1))
      printf '%s\t%s\n' "$bid" "$snippet" >>"$blocks"
      [ "$kids" != 1 ] || printf '%s\n' "$bid" >>"$queue"
    done <"$work/children.tsv"
    [ "$status" = complete ] || break
    cursor=$(next_cursor "$resp") || die 1 "$NO_CURSOR"
    [ -n "$cursor" ] || break
  done
  [ "$status" = complete ] || break
done

while IFS="$(printf '\t')" read -r bid snippet; do
  comments_of "$bid" "$snippet"
done <"$blocks"

cat "$items"
printf 'summary\t%s\t%s\n' "$status" "$walked"
if [ "$status" = partial ]; then
  printf '%s\n' "inception-notion: the block walk stopped at $max_blocks blocks; comments on later blocks were not read" >&2
fi
exit 0
