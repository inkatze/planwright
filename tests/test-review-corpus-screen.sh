#!/bin/bash
# Tests for scripts/review-corpus-screen.sh — the backtest corpus's schema and
# hygiene screen — and the committed corpus versions passing it
# (review-effectiveness REQ-H1.2, REQ-E1.7, D-16).
set -u
unset CDPATH

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCREEN="$REPO_ROOT/scripts/review-corpus-screen.sh"
CORPUS_ROOT="$REPO_ROOT/tests/fixtures/review-backtest"

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

T=$(mktemp -d "${TMPDIR:-/tmp}/rcs.XXXXXX")
trap 'rm -rf "$T"' EXIT

HDR='id	pr	commit	path	line	category	reason	replayable	label_source	gist	dismissal'
SHA=0123456789abcdef0123456789abcdef01234567
good_row="r0001	12	$SHA	scripts/a.sh	40	correctness	runtime-tracing	yes	model	the retry loop exits zero when every attempt fails	-"
declined_row="r0002	12	$SHA	scripts/b.sh	7	portability	declined	no	declined-log	a GNU-only flag breaks the BSD floor	the pass judged the flag portable enough"

corpus() {
  # corpus <name> <row>... — write a corpus file with the header and rows.
  f="$T/$1.tsv"
  shift
  printf '%s\n' "$HDR" >"$f"
  for r in "$@"; do printf '%s\n' "$r" >>"$f"; done
  printf '%s\n' "$f"
}

# --- a conforming corpus passes, declined row and its dismissal included ---
f=$(corpus good "$good_row" "$declined_row")
out=$("$SCREEN" "$f" 2>&1)
assert_exit "conforming corpus passes" 0 $?
assert_contains "no name list announces the skipped product screen" "product-name screen skipped" "$out"

# --- each schema rule refuses its row, naming the row and the rule ---
check_refused() {
  # check_refused <label> <rule-needle> <row>
  f=$(corpus bad "$good_row" "$3")
  out=$("$SCREEN" "$f" 2>&1)
  rc=$?
  assert_exit "$1: refused" 1 "$rc"
  assert_contains "$1: names the rule" "$2" "$out"
  id=${3%%"	"*}
  assert_contains "$1: names the row" "$id" "$out"
}
check_refused "non-integer pr" "pr is not" "r0003	1x	$SHA	scripts/a.sh	4	correctness	other	yes	fallback	gist text here	-"
check_refused "short commit" "commit" "r0003	12	0123abc	scripts/a.sh	4	correctness	other	yes	fallback	gist text here	-"
check_refused "absolute path" "path" "r0003	12	$SHA	/etc/passwd	4	correctness	other	yes	fallback	gist text here	-"
check_refused "dot-dot path" "path" "r0003	12	$SHA	scripts/../x	4	correctness	other	yes	fallback	gist text here	-"
check_refused "non-ASCII path" "path" "r0003	12	$SHA	scripts/$(printf '\342\200\256')x.sh	4	correctness	other	yes	fallback	gist text here	-"
check_refused "zero line" "line" "r0003	12	$SHA	scripts/a.sh	0	correctness	other	yes	fallback	gist text here	-"
check_refused "unknown category" "category" "r0003	12	$SHA	scripts/a.sh	4	vibes	other	yes	fallback	gist text here	-"
check_refused "unknown reason" "reason" "r0003	12	$SHA	scripts/a.sh	4	correctness	lazy	yes	fallback	gist text here	-"
check_refused "bad replayable flag" "replayable" "r0003	12	$SHA	scripts/a.sh	4	correctness	other	maybe	fallback	gist text here	-"
check_refused "unknown label source" "label_source" "r0003	12	$SHA	scripts/a.sh	4	correctness	other	yes	guess	gist text here	-"
check_refused "fallback row not other" "fallback" "r0003	12	$SHA	scripts/a.sh	4	correctness	pruned	yes	fallback	gist text here	-"
check_refused "declined-log row not declined" "declined-log" "r0003	12	$SHA	scripts/a.sh	4	correctness	pruned	yes	declined-log	gist text here	-"
check_refused "overlong dismissal" "dismissal is longer" "r0003	12	$SHA	scripts/a.sh	4	correctness	declined	yes	declined-log	gist text here	$(printf 'word %.0s' $(seq 1 60))"
check_refused "empty gist" "gist" "r0003	12	$SHA	scripts/a.sh	4	correctness	other	yes	fallback		-"
check_refused "declined row without dismissal" "dismissal" "r0003	12	$SHA	scripts/a.sh	4	correctness	declined	yes	declined-log	gist text here	-"
check_refused "dismissal on a non-declined row" "dismissal" "r0003	12	$SHA	scripts/a.sh	4	correctness	other	yes	fallback	gist text here	a stray dismissal"
check_refused "duplicate id" "duplicate" "r0001	13	$SHA	scripts/c.sh	4	correctness	other	yes	fallback	gist text here	-"
check_refused "wrong field count" "fields" "r0003	12	$SHA	scripts/a.sh	4"

# --- the hygiene rules: no login, no bot marker, no URL, no home path ---
check_refused "reviewer login in gist" "login" "r0003	12	$SHA	scripts/a.sh	4	correctness	other	yes	fallback	as @someone noted the loop spins	-"
check_refused "bot marker in gist" "login" "r0003	12	$SHA	scripts/a.sh	4	correctness	other	yes	fallback	reviewer-x[bot] flagged the loop	-"
check_refused "URL in gist" "url" "r0003	12	$SHA	scripts/a.sh	4	correctness	other	yes	fallback	see https://example.com/thread	-"
check_refused "home path in dismissal" "home path" "r0003	12	$SHA	scripts/a.sh	4	correctness	declined	yes	declined-log	gist text here	read from /home/someone/x"
long=$(printf 'word %.0s' $(seq 1 60))
check_refused "overlong gist" "gist" "r0003	12	$SHA	scripts/a.sh	4	correctness	other	yes	fallback	$long	-"

# --- the product-name screen reads a name list and never prints the name ---
names="$T/names.txt"
printf '# product names\n\nAcmeReview\n' >"$names"
f=$(corpus named "$good_row" "r0003	12	$SHA	scripts/a.sh	4	correctness	other	yes	fallback	acmereview found the loop spins	-")
out=$("$SCREEN" --names "$names" "$f" 2>&1)
assert_exit "a row naming a listed product is refused" 1 $?
assert_contains "product refusal names the row" "r0003" "$out"
out_lc=$(printf '%s' "$out" | LC_ALL=C tr '[:upper:]' '[:lower:]')
assert_lacks "product refusal never prints the name, in any case" "acmereview" "$out_lc"
f=$(corpus unnamed "$good_row")
out=$("$SCREEN" --names "$names" "$f" 2>&1)
assert_exit "a clean corpus passes the product screen" 0 $?
assert_lacks "a supplied list is not reported skipped" "skipped" "$out"
f=$(corpus inword "r0003	12	$SHA	scripts/a.sh	4	correctness	other	yes	fallback	the acmereviewer field is unset	-")
"$SCREEN" --names "$names" "$f" >/dev/null 2>&1
assert_exit "a name inside a longer word is not a match" 0 $?
f=$(corpus repeated "r0003	12	$SHA	scripts/a.sh	4	correctness	other	yes	fallback	the acmereviewacmereview field is unset	-")
"$SCREEN" --names "$names" "$f" >/dev/null 2>&1
assert_exit "a name repeated inside one word is not a match" 0 $?

# --- refusals of the screen itself ---
printf '# only a comment\n\n' >"$T/empty-names.txt"
"$SCREEN" --names "$T/empty-names.txt" --require-names "$f" >/dev/null 2>&1
assert_exit "a list holding no names is refused, never a pass" 2 $?
"$SCREEN" --names "$T/absent.txt" "$f" >/dev/null 2>&1
assert_exit "a named but missing list is a usage error" 2 $?
"$SCREEN" --require-names "$f" >/dev/null 2>&1
assert_exit "--require-names without a list is a usage error" 2 $?
printf 'id\tpr\n' >"$T/hdr.tsv"
"$SCREEN" "$T/hdr.tsv" >/dev/null 2>&1
assert_exit "a wrong header is refused" 2 $?
f=$(corpus empty)
"$SCREEN" "$f" >/dev/null 2>&1
assert_exit "a corpus with zero rows is refused" 2 $?

# --- text mode: the product-name check over prose files and directories ---
mkdir -p "$T/frag/entries/nested" "$T/frag/archive"
printf -- '- 2026-01-01 [x] the bot reviewer flagged the loop\n' >"$T/frag/entries/2026-01-01-clean-0000aaaa.md"
printf -- '- 2026-01-02 [x] a clean line\nAcmeReview flagged the loop\n' >"$T/frag/archive/2026-01-02-body-0000bbbb.md"
printf -- '- 2026-01-03 [x] a clean line\n' >"$T/frag/entries/nested/2026-01-03-acmereview-run-0000cccc.md"
out=$("$SCREEN" --text --names "$names" "$T/frag" 2>&1)
assert_exit "text mode refuses a directory holding a listed name" 1 $?
assert_contains "text mode names the file and line of a body match" "2026-01-02-body-0000bbbb.md:2:" "$out"
assert_contains "text mode screens a file name, recursing into subdirectories" "2026-01-03-acmereview-run-0000cccc.md: file name" "$out"
assert_lacks "text mode passes a clean file" "0000aaaa" "$out"
out_lc=$(printf '%s' "$out" | sed 's/[^:]*acmereview-run-0000cccc\.md//' | LC_ALL=C tr '[:upper:]' '[:lower:]')
assert_lacks "text mode never prints the matched text" "acmereview flagged" "$out_lc"
out=$("$SCREEN" --text --names "$names" "$T/frag/entries/2026-01-01-clean-0000aaaa.md" "$T/frag/archive" 2>&1)
assert_exit "text mode takes files and directories together" 1 $?
assert_lacks "text mode reads only the paths given" "0000cccc" "$out"
rm "$T/frag/archive/2026-01-02-body-0000bbbb.md" "$T/frag/entries/nested/2026-01-03-acmereview-run-0000cccc.md"
printf -- '- 2026-01-04 [x] the acmereviewer field is unset\n' >"$T/frag/entries/2026-01-04-inword-0000dddd.md"
out=$("$SCREEN" --text --names "$names" "$T/frag" 2>&1)
assert_exit "text mode passes clean files, a name inside a word included" 0 $?
assert_contains "text mode reports the files it passed" "2 file(s) pass" "$out"
"$SCREEN" --text "$T/frag" >/dev/null 2>&1
assert_exit "text mode refuses to run without a name list" 2 $?
"$SCREEN" --text --names "$T/empty-names.txt" "$T/frag" >/dev/null 2>&1
assert_exit "text mode refuses a list holding no names" 2 $?
"$SCREEN" --text --names "$names" "$T/absent-dir" >/dev/null 2>&1
assert_exit "text mode refuses a missing path" 2 $?
mkdir -p "$T/empty-dir"
"$SCREEN" --text --names "$names" "$T/empty-dir" >/dev/null 2>&1
assert_exit "text mode refuses paths holding no files, never a pass" 2 $?

# --- every committed corpus version passes its schema and hygiene screen ---
found=0
for c in "$CORPUS_ROOT"/v*/corpus.tsv; do
  [ -f "$c" ] || continue
  found=$((found + 1))
  out=$("$SCREEN" "$c" 2>&1)
  assert_exit "committed corpus ${c#"$REPO_ROOT"/} passes the screen" 0 $?
done
if [ "$found" -ge 1 ]; then ok "at least one committed corpus version exists"; else fail "no committed corpus version under tests/fixtures/review-backtest"; fi

if [ "$failures" -ne 0 ]; then
  echo "$failures failure(s)" >&2
  exit 1
fi
echo "all review-corpus-screen tests passed"
