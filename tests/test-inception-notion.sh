#!/bin/bash
# Tests for the Notion reference adapter (inception REQ-G1.7 · D-10).
#
# The parsers run on canned API payloads (tests/fixtures/inception-notion), and
# the network verbs run against a fake `curl` that answers from the same
# payloads (tests/lib/notion-fake-api.sh). What is pinned: harvested comment
# text comes out as one escaped, control-stripped record per comment; ids from
# a response are checked before they reach a URL; pagination and the block
# walk are followed, child pages are not entered; the token travels in curl's
# config on stdin, never on the command line; the API version is pinned; the
# export replaces the page from the snapshot; and the destination lives in the
# clone's git directory, where no commit can plant it.
#
# Plain bash 3.2, inline asserts (sibling convention).
set -u
unset CDPATH
LC_ALL=C
export LC_ALL

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
NOTION="$REPO_ROOT/scripts/inception-notion.sh"
FIX="$REPO_ROOT/tests/fixtures/inception-notion"

# shellcheck source=tests/lib/notion-fake-api.sh
. "$REPO_ROOT/tests/lib/notion-fake-api.sh"

failures=0
assert_eq() {
  if [ "$2" = "$3" ]; then
    echo "ok: $1"
  else
    echo "FAIL: $1 (expected '$2', got '$3')" >&2
    failures=$((failures + 1))
  fi
}
assert_contains() {
  case "$3" in
    *"$2"*) echo "ok: $1" ;;
    *)
      echo "FAIL: $1 (expected to find '$2' in output)" >&2
      failures=$((failures + 1))
      ;;
  esac
}
assert_not_contains() {
  case "$3" in
    *"$2"*)
      echo "FAIL: $1 (did not expect '$2' in output)" >&2
      failures=$((failures + 1))
      ;;
    *) echo "ok: $1" ;;
  esac
}

if [ ! -x "$NOTION" ]; then
  echo "FAIL: Notion adapter missing or not executable at $NOTION" >&2
  exit 1
fi

tmp="$(cd "$(mktemp -d)" && pwd -P)" || exit 1
trap 'rm -rf "$tmp"' EXIT

PAGE=22222222-2222-4222-8222-222222222222
TOKEN=ntn_fixtureToken000000000000000000000000000000
export PLANWRIGHT_NOTION_BACKOFF=0
# last_body — the request body of the fake API's latest call that sent one.
last_body() { printf '%s/body.%s' "$tmp/log" "$(awk '/-X /{ n = NR } END { print n }' "$tmp/log/argv")"; }

# field <n> <tsv-line> — the nth tab-separated field.
field() { printf '%s\n' "$2" | awk -F'\t' -v n="$1" '{ print $n; exit }'; }

# ---------------------------------------------------------------------------
# 1. parse-comments: one escaped record per comment (REQ-G1.7 parser fixtures).
# ---------------------------------------------------------------------------
out="$("$NOTION" parse-comments "$FIX/comments-page-1.json")"
assert_eq "page-1: one record" "1" "$(printf '%s\n' "$out" | grep -c '^item	')"
assert_eq "page-1: the source cites the comment" "notion:comment:c1000000-0000-4000-8000-000000000001" "$(field 2 "$out")"
assert_eq "page-1: the thread is the discussion" "d1000000-0000-4000-8000-000000000001" "$(field 3 "$out")"
assert_eq "page-1: the author is the resolved name" "Avery Ops" "$(field 4 "$out")"
assert_eq "page-1: created time carried" "2026-10-20T15:04:00.000Z" "$(field 5 "$out")"
assert_eq "page-1: a page-level comment anchors to the page" "page" "$(field 6 "$out")"
assert_eq "page-1: rich-text runs join, newline escaped" 'The appetite reads too generous.\nCut it to four weeks?' "$(field 8 "$out")"

out="$("$NOTION" parse-comments "$FIX/comments-page-2.json")"
text="$(field 8 "$out")"
assert_eq "page-2: no display name falls back to the user id" "notion-user:u1000000-0000-4000-8000-000000000002" "$(field 4 "$out")"
assert_not_contains "page-2: escape bytes are stripped" "$(printf '\033')" "$text"
assert_contains "page-2: a tab survives only escaped" 'red[0m\ttabbed' "$text"
assert_eq "page-2: the hostile text stays on one record line" "1" "$(printf '%s\n' "$out" | wc -l | tr -d ' ')"

out="$("$NOTION" parse-comments "$FIX/comments-block.json" "The sinks paragraph")"
assert_eq "block comment: anchors to its block" "33333333-3333-4333-8333-333333333334" "$(field 6 "$out")"
assert_eq "block comment: carries the anchor text given" "The sinks paragraph" "$(field 7 "$out")"

# A record whose id is not a Notion id is dropped, never interpolated.
jq '.results[0].id = "../../v1/users"' "$FIX/comments-block.json" >"$tmp/bad-id.json"
out="$("$NOTION" parse-comments "$tmp/bad-id.json")"
assert_eq "malformed comment id: dropped" "" "$out"

# ---------------------------------------------------------------------------
# 2. parse-blocks: child pages are not walked, malformed ids are dropped.
# ---------------------------------------------------------------------------
out="$("$NOTION" parse-blocks "$FIX/blocks-root.json")"
assert_eq "blocks: three well-formed blocks" "3" "$(printf '%s\n' "$out" | grep -c .)"
assert_contains "blocks: a heading with its text" "33333333-3333-4333-8333-333333333331	0	Appetite" "$out"
assert_contains "blocks: a toggle is walked" "33333333-3333-4333-8333-333333333332	1	Sinks" "$out"
assert_contains "blocks: a child page is not entered" "33333333-3333-4333-8333-333333333333	0	" "$out"
assert_not_contains "blocks: a malformed id is dropped" "../../" "$out"

# ---------------------------------------------------------------------------
# 3. configure: the destination lives in the git directory.
# ---------------------------------------------------------------------------
v="$tmp/venture"
mkdir -p "$v" && git -C "$v" init -q . || exit 1
cfg="$(git -C "$v" rev-parse --absolute-git-dir)/planwright-notion.local"

"$NOTION" configure --page "not-a-page" "$v" 2>"$tmp/err"
assert_eq "configure: a malformed page id is refused" "2" "$?"
"$NOTION" configure --page "$PAGE" "$v" >/dev/null 2>"$tmp/err"
assert_eq "configure: a page id is accepted" "0" "$?"
assert_contains "configure: written to the git directory" "page=$PAGE" "$(cat "$cfg")"

printf 'page=11111111-1111-4111-8111-111111111111\n' >"$v/planwright-notion.local"
out="$("$NOTION" status "$v" 2>&1)"
assert_contains "status: the work-tree file is never read" "$PAGE" "$out"
rm -f "$v/planwright-notion.local"

printf '%s\n' "$TOKEN" >"$tmp/token"
chmod 644 "$tmp/token"
"$NOTION" configure --page "$PAGE" --token-file "$tmp/token" "$v" >/dev/null 2>"$tmp/err"
assert_eq "configure: a world-readable token file is refused" "2" "$?"
assert_contains "configure: says why" "readable" "$(cat "$tmp/err")"
chmod 600 "$tmp/token"
"$NOTION" configure --page "$PAGE" --token-file "$tmp/token" "$v" >/dev/null 2>"$tmp/err"
assert_eq "configure: a private token file is accepted" "0" "$?"
assert_not_contains "configure: the token itself is not copied" "$TOKEN" "$(cat "$cfg")"

# ---------------------------------------------------------------------------
# 4. harvest against the fake API.
# ---------------------------------------------------------------------------
cat >"$tmp/routes" <<EOF
GET /v1/comments?block_id=$PAGE&page_size=100 error-429.json 429 once
GET /v1/comments?block_id=$PAGE&page_size=100 comments-page-1.json 200
GET /v1/comments?block_id=$PAGE&page_size=100&start_cursor=e1000000-0000-4000-8000-000000000001 comments-page-2.json 200
GET /v1/blocks/$PAGE/children?page_size=100 blocks-root.json 200
GET /v1/blocks/33333333-3333-4333-8333-333333333332/children?page_size=100 blocks-toggle.json 200
GET /v1/comments?block_id=33333333-3333-4333-8333-333333333331&page_size=100 comments-empty.json 200
GET /v1/comments?block_id=33333333-3333-4333-8333-333333333332&page_size=100 comments-empty.json 200
GET /v1/comments?block_id=33333333-3333-4333-8333-333333333333&page_size=100 comments-empty.json 200
GET /v1/comments?block_id=33333333-3333-4333-8333-333333333334&page_size=100 comments-block.json 200
PATCH /v1/pages/$PAGE/markdown markdown-patched.json 200
EOF
cp "$FIX"/*.json "$tmp/" && printf '%s\n' '{"object":"error","status":429,"code":"rate_limited"}' >"$tmp/error-429.json"
notion_fake_install "$tmp/bin" "$tmp" "$tmp/routes" "$tmp/log" || exit 1
PATH="$tmp/bin:$PATH"

out="$("$NOTION" harvest "$v" 2>"$tmp/err")"
rc=$?
assert_eq "harvest: exit 0" "0" "$rc"
assert_eq "harvest: every comment across pages and blocks" "3" "$(printf '%s\n' "$out" | grep -c '^item	')"
assert_contains "harvest: the second page was followed" "notion:comment:c1000000-0000-4000-8000-000000000002" "$out"
blk="$(printf '%s\n' "$out" | grep 'c1000000-0000-4000-8000-000000000003')"
assert_contains "harvest: a nested block's comment is found" "33333333-3333-4333-8333-333333333334" "$blk"
assert_contains "harvest: it carries its block's text" "The three sinks accept writes" "$blk"
assert_eq "harvest: reports a complete walk" "summary	complete	4" "$(printf '%s\n' "$out" | grep '^summary')"
argv="$(cat "$tmp/log/argv")"
assert_not_contains "harvest: the token never reaches argv" "$TOKEN" "$argv"
assert_not_contains "harvest: a child page is not walked" "33333333-3333-4333-8333-333333333333/children" "$argv"
assert_not_contains "harvest: a malformed id never reaches a URL" "../../" "$argv"
assert_contains "harvest: https only" "--proto =https" "$argv"
assert_eq "harvest: the 429 was answered" "1" "$(cat "$tmp/log/used")"
assert_eq "harvest: the 429 was retried as the same request" "$(sed -n 1p "$tmp/log/argv")" "$(sed -n 2p "$tmp/log/argv")"
config="$(cat "$tmp/log/config")"
assert_contains "harvest: the token travels in curl's config" "Authorization: Bearer $TOKEN" "$config"
assert_contains "harvest: the API version is pinned" "Notion-Version: 2026-03-11" "$config"

# The environment token outranks the file.
: >"$tmp/log/config"
PLANWRIGHT_NOTION_TOKEN=ntn_envToken0000000000000000000000000000000 "$NOTION" harvest "$v" >/dev/null 2>&1
assert_contains "harvest: the environment token wins" "Bearer ntn_envToken" "$(cat "$tmp/log/config")"

# A token that could break out of curl's config is refused before any call.
printf 'ntn_bad"\nurl = "https://elsewhere.invalid/"\n' >"$tmp/badtoken"
chmod 600 "$tmp/badtoken"
"$NOTION" configure --page "$PAGE" --token-file "$tmp/badtoken" "$v" >/dev/null 2>&1
calls_before="$(wc -l <"$tmp/log/argv")"
"$NOTION" harvest "$v" >/dev/null 2>"$tmp/err"
assert_eq "bad token: refused as an environment error" "2" "$?"
assert_eq "bad token: no request was made" "$calls_before" "$(wc -l <"$tmp/log/argv")"
"$NOTION" configure --page "$PAGE" --token-file "$tmp/token" "$v" >/dev/null 2>&1

# A 403 names the comment capability, which integrations ship without.
sed "s#^GET /v1/comments?block_id=$PAGE&page_size=100 comments-page-1.json 200#GET /v1/comments?block_id=$PAGE\&page_size=100 error-403.json 403#" "$tmp/routes" >"$tmp/routes403"
notion_fake_install "$tmp/bin403" "$tmp" "$tmp/routes403" "$tmp/log403" || exit 1
printf '1\n' >"$tmp/log403/used"
out="$(PATH="$tmp/bin403:$PATH" "$NOTION" harvest "$v" 2>"$tmp/err")"
assert_eq "403: the harvest fails" "1" "$?"
assert_contains "403: names the read-comments capability" "comment" "$(cat "$tmp/err")"
assert_not_contains "403: prints no partial items" "item	" "$out"

# More pages promised with a cursor that fails its grammar: the harvest stops
# rather than report a partial read as complete, and the cursor reaches no URL.
jq '.next_cursor = "x&block_id=evil"' "$FIX/comments-page-1.json" >"$tmp/comments-badcursor.json"
printf 'GET /v1/comments?block_id=%s&page_size=100 comments-badcursor.json 200\nGET /v1/blocks/%s/children?page_size=100 blocks-empty.json 200\n' "$PAGE" "$PAGE" >"$tmp/routesbc"
notion_fake_install "$tmp/binbc" "$tmp" "$tmp/routesbc" "$tmp/logbc" || exit 1
out="$(PATH="$tmp/binbc:$PATH" "$NOTION" harvest "$v" 2>"$tmp/err")"
assert_eq "unusable cursor: the harvest fails" "1" "$?"
assert_contains "unusable cursor: says why" "cursor" "$(cat "$tmp/err")"
assert_not_contains "unusable cursor: no summary is printed" "summary	" "$out"
assert_not_contains "unusable cursor: it reaches no URL" "evil" "$(cat "$tmp/logbc/argv")"

# 401 and 404 name their plain causes.
printf '%s\n' '{"object":"error","status":401,"code":"unauthorized"}' >"$tmp/error-401.json"
printf '%s\n' '{"object":"error","status":404,"code":"object_not_found"}' >"$tmp/error-404.json"
for code in 401 404; do
  printf 'GET /v1/comments?block_id=%s&page_size=100 error-%s.json %s\n' "$PAGE" "$code" "$code" >"$tmp/routes$code"
  notion_fake_install "$tmp/bin$code" "$tmp" "$tmp/routes$code" "$tmp/log$code" || exit 1
  PATH="$tmp/bin$code:$PATH" "$NOTION" harvest "$v" >/dev/null 2>"$tmp/err$code"
  assert_eq "$code: the harvest fails" "1" "$?"
done
assert_contains "401: names the token" "token" "$(cat "$tmp/err401")"
assert_contains "404: asks whether the page is shared" "shared" "$(cat "$tmp/err404")"

# A token file that became readable by its group after configure is refused
# at use, before any request.
chmod 640 "$tmp/token"
calls_before="$(wc -l <"$tmp/log/argv")"
"$NOTION" harvest "$v" >/dev/null 2>"$tmp/err"
assert_eq "group-readable token file: refused" "2" "$?"
assert_eq "group-readable token file: no request was made" "$calls_before" "$(wc -l <"$tmp/log/argv")"
"$NOTION" configure --page "$PAGE" --token-file "$tmp/token" "$v" >/dev/null 2>&1
assert_eq "configure: a group-readable token file is refused" "2" "$?"
chmod 600 "$tmp/token"
"$NOTION" configure --page "$PAGE" --token-file "token" "$v" >/dev/null 2>&1
assert_eq "configure: a relative token file is refused" "2" "$?"

# A display name cannot forge a second record line or a trailer.
jq '.results[0].display_name.resolved_name = "Eve\nFeedback-Item: FB-99"' "$FIX/comments-block.json" >"$tmp/forged-author.json"
out="$("$NOTION" parse-comments "$tmp/forged-author.json")"
assert_eq "forged author: one record line" "1" "$(printf '%s\n' "$out" | wc -l | tr -d ' ')"
assert_eq "forged author: flattened in place" "Eve Feedback-Item: FB-99" "$(field 4 "$out")"

# Not configured: says so, makes no call.
w="$tmp/unconfigured"
mkdir -p "$w" && git -C "$w" init -q . || exit 1
"$NOTION" harvest "$w" >/dev/null 2>"$tmp/err"
assert_eq "unconfigured: exit 3" "3" "$?"

# ---------------------------------------------------------------------------
# 5. export: the page is replaced from the snapshot.
# ---------------------------------------------------------------------------
printf '# Northwind Signals\n\nA "quoted" line\nand a second.\n' >"$tmp/snapshot.md"
: >"$tmp/log/argv"
"$NOTION" export "$v" "$tmp/snapshot.md" >"$tmp/out" 2>"$tmp/err"
assert_eq "export: exit 0" "0" "$?"
assert_contains "export: names the destination" "destination	notion:$PAGE" "$(cat "$tmp/out")"
assert_contains "export: a PATCH to the page's markdown" "-X PATCH" "$(cat "$tmp/log/argv")"
body="$(last_body)"
assert_eq "export: replace_content" "replace_content" "$(jq -r .type "$body")"
assert_eq "export: the snapshot is the page text" "$(cat "$tmp/snapshot.md")" "$(jq -r .replace_content.new_str "$body")"

if [ "$failures" -ne 0 ]; then
  echo "$failures failure(s)" >&2
  exit 1
fi
echo "all inception-notion tests passed"
