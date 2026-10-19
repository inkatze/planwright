#!/bin/bash
# Tests for scripts/check-review-miss.sh — the miss-ledger grammar guard over
# the observation store and over a single text (review-effectiveness REQ-E1.5,
# D-8), and the vocabulary the independence rule doc states against the one the
# scripts share.
set -u
unset CDPATH

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CHECK="$REPO_ROOT/scripts/check-review-miss.sh"
DOC="$REPO_ROOT/doctrine/review-independence.md"

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
assert_eq() {
  if [ "$2" = "$3" ]; then ok "$1"; else fail "$1 (expected '$2', got '$3')"; fi
}
assert_not_contains() {
  case "$3" in
    *"$2"*) fail "$1 (unexpected '$2' in: $3)" ;;
    *) ok "$1" ;;
  esac
}

T=$(mktemp -d "${TMPDIR:-/tmp}/rmiss.XXXXXX")
trap 'chmod -R u+rw "$T" 2>/dev/null; rm -rf "$T"' EXIT

run_text() {
  rc=0
  out=$(/bin/sh "$CHECK" --text "$1" 2>&1) || rc=$?
}

# --- text mode ---
run_text 'review-miss(correctness, runtime-tracing): #12 scripts/a.sh: the pass never ran the script'
assert_exit "accepts a conforming miss text" 0 "$rc"

run_text 'review-miss(sibling-sweep, pruned): #7 lib/c.sh: a twin site kept the bug'
assert_exit "accepts the sibling-sweep lens" 0 "$rc"

run_text 'review-miss(correctness, pruned): scripts/a.sh: no PR number'
assert_exit "refuses a text without a PR number" 1 "$rc"
assert_contains "names the grammar on refusal" "review-miss(<lens>, <reason>): #<pr> <path>:" "$out"

run_text 'review-miss(correctness, pruned): #12: no path'
assert_exit "refuses a text without a path" 1 "$rc"

run_text 'review-miss(correctness, pruned): #12 scripts/a.sh:'
assert_exit "refuses a text without a description" 1 "$rc"

run_text 'review-miss(correctness): #12 scripts/a.sh: no reason'
assert_exit "refuses a text without a reason" 1 "$rc"

run_text 'review-miss(correctness, bogus): #12 scripts/a.sh: reason outside the vocabulary'
assert_exit "refuses a reason outside the vocabulary" 1 "$rc"
assert_contains "names the bad reason" "bogus" "$out"

run_text 'review-miss(vibes, pruned): #12 scripts/a.sh: lens outside the vocabulary'
assert_exit "refuses a lens outside the vocabulary" 1 "$rc"
assert_contains "names the bad lens" "vibes" "$out"

run_text 'review-miss(correctness, pruned): #0 scripts/a.sh: PR zero'
assert_exit "refuses PR number zero" 1 "$rc"

run_text 'review-miss(correctness, pruned): #12 /etc/passwd: absolute path'
assert_exit "refuses an absolute path" 1 "$rc"

run_text 'review-miss(correctness, pruned): #12 ../x.sh: escaping path'
assert_exit "refuses a path leaving the repository" 1 "$rc"

run_text "$(printf 'review-miss(correctness, pruned): #12 a.sh: x\nextra')"
assert_exit "refuses a text spanning two lines" 1 "$rc"

run_text 'review-miss(correctness, pruned): #12 scripts/a.sh: '
assert_exit "refuses a blank description" 1 "$rc"

run_text "$(printf 'review-miss(other, other): #1 a\tother: forged columns')"
assert_exit "refuses a tab smuggled into the path" 1 "$rc"

for p in ./a.sh a//b.sh a/./c.sh a/.; do
  run_text "review-miss(correctness, pruned): #12 $p: not the canonical path"
  assert_exit "refuses the non-canonical path $p" 1 "$rc"
done

# --- store mode ---
obs="$T/obs"
mkdir -p "$obs/entries" "$obs/archive"
printf '%s\n' "- 2026-10-01 [planwright] review-miss(correctness, outside-diff): #40 scripts/b.sh: a caller outside the diff broke" >"$obs/entries/2026-10-01-review-miss-0000aaaa.md"
printf '%s\n' "- 2026-10-01 [planwright] review-miss(tests, claim-vs-code): #41 tests/t.sh: the test never reached the branch" "" "Consumed-by: some-spec 2026-10-02" >"$obs/archive/2026-10-01-review-miss-0000bbbb.md"
printf '%s\n' "- 2026-10-01 [planwright] an unrelated observation that discusses the review-miss grammar in passing" >"$obs/entries/2026-10-01-skill-drift-0000cccc.md"

printf '%s\n' "- 2026-10-01 [planwright] review-missing tests let the cost metric drift" >"$obs/entries/2026-10-01-cost-drift-0000c0c0.md"

rc=0
out=$(/bin/sh "$CHECK" --obs-dir "$obs" 2>&1) || rc=$?
assert_exit "a store of conforming misses and other fragments is clean" 0 "$rc"

printf '%s\n' "- 2026-10-02 [planwright] review-miss(correctness, pruned): scripts/b.sh: no PR number" >"$obs/entries/2026-10-02-review-miss-0000dddd.md"
rc=0
out=$(/bin/sh "$CHECK" --obs-dir "$obs" 2>&1) || rc=$?
assert_exit "a malformed miss fragment fails the store" 1 "$rc"
assert_contains "names the malformed fragment" "2026-10-02-review-miss-0000dddd.md" "$out"
assert_not_contains "does not flag a passing mention in another slug" "skill-drift" "$out"
rm -f "$obs/entries/2026-10-02-review-miss-0000dddd.md"

printf '%s\n' "- 2026-10-02 [planwright] review-miss(correctness, pruned): #42 scripts/b.sh: recorded under another slug" >"$obs/archive/2026-10-02-misc-0000eeee.md"
rc=0
out=$(/bin/sh "$CHECK" --obs-dir "$obs" 2>&1) || rc=$?
assert_exit "a miss text under another slug fails" 1 "$rc"
assert_contains "names the slug mismatch" "2026-10-02-misc-0000eeee.md" "$out"
rm -f "$obs/archive/2026-10-02-misc-0000eeee.md"

printf '%s\n' "- 2026-10-02 [planwright] a plain note filed under the miss slug" >"$obs/entries/2026-10-02-review-miss-0000abcd.md"
rc=0
out=$(/bin/sh "$CHECK" --obs-dir "$obs" 2>&1) || rc=$?
assert_exit "a miss-slug fragment carrying no miss fails" 1 "$rc"
assert_contains "says the first line is no miss" "first line" "$out"
rm -f "$obs/entries/2026-10-02-review-miss-0000abcd.md"

escname=$(printf '2026-10-02-review-miss-0000\033[2J.md')
printf '%s\n' "- 2026-10-02 [planwright] review-miss(correctness, pruned): no PR number" >"$obs/entries/$escname"
rc=0
out=$(/bin/sh "$CHECK" --obs-dir "$obs" 2>&1) || rc=$?
assert_exit "a malformed miss with a hostile name fails" 1 "$rc"
case $out in
  *"$(printf '\033')"*) fail "strips control bytes from the fragment name it reports" ;;
  *) ok "strips control bytes from the fragment name it reports" ;;
esac
rm -f "$obs/entries/$escname"

if [ "$(id -u)" -ne 0 ]; then
  printf '%s\n' "- 2026-10-03 [planwright] review-miss(correctness, pruned): #43 a.sh: unreadable" >"$obs/entries/2026-10-03-review-miss-0000ffff.md"
  chmod 000 "$obs/entries/2026-10-03-review-miss-0000ffff.md"
  rc=0
  out=$(/bin/sh "$CHECK" --obs-dir "$obs" 2>&1) || rc=$?
  assert_exit "an unreadable fragment is an error, never a pass" 2 "$rc"
  assert_contains "says the fragment cannot be read" "cannot be read" "$out"
  chmod 644 "$obs/entries/2026-10-03-review-miss-0000ffff.md"
  rm -f "$obs/entries/2026-10-03-review-miss-0000ffff.md"

  chmod 000 "$obs/archive"
  rc=0
  out=$(/bin/sh "$CHECK" --obs-dir "$obs" 2>&1) || rc=$?
  assert_exit "an unreadable store directory is an error, never a pass" 2 "$rc"
  chmod 755 "$obs/archive"
fi

rc=0
out=$(/bin/sh "$CHECK" --obs-dir "$T/absent" 2>&1) || rc=$?
assert_exit "an absent store is a clean pass" 0 "$rc"

rc=0
out=$(/bin/sh "$CHECK" --obs-dir "" 2>&1) || rc=$?
assert_exit "an empty --obs-dir is a usage error" 2 "$rc"

rc=0
out=$(/bin/sh "$CHECK" --bogus 2>&1) || rc=$?
assert_exit "an unknown flag is a usage error" 2 "$rc"

# --- a miss written through the observation helper passes the guard ---
rt="$T/roundtrip"
mkdir -p "$rt"
rc=0
/bin/sh "$REPO_ROOT/scripts/obs-record.sh" --slug review-miss --scope planwright --today 2026-10-05 \
  --text 'review-miss(cross-file, claim-vs-code): #46 doctrine/x.md: the doc named a flag the script lost' \
  --obs-dir "$rt" >/dev/null 2>&1 || rc=$?
assert_exit "the observation helper records a conforming miss" 0 "$rc"
set -- "$rt"/entries/*-review-miss-*.md
assert_eq "the helper wrote one miss fragment" 1 "$(ls "$@" 2>/dev/null | wc -l | tr -d ' ')"
rc=0
out=$(/bin/sh "$CHECK" --obs-dir "$rt" 2>&1) || rc=$?
assert_exit "a miss the helper wrote passes the guard" 0 "$rc"

# --- the readers share the grammar: a miss the guard refuses is never read ---
. "$REPO_ROOT/scripts/review-backtest-lib.sh"
ledger="$T/ledger"
mkdir -p "$ledger"
printf '%s\n' "- 2026-10-04 [planwright] review-miss(vibes, pruned): #44 a.sh: lens outside the vocabulary" >"$ledger/2026-10-04-review-miss-0000abab.md"
printf '%s\n' "- 2026-10-04 [planwright] review-miss(correctness, pruned): #45 a.sh: conforming" >"$ledger/2026-10-04-review-miss-0000cdcd.md"
printf '%s\n' "- 2026-10-04 [planwright] a note that mentions review-miss without being one" >"$ledger/2026-10-04-note-0000efef.md"
rbt_read_ledger "$T/rows.tsv" "$ledger"
assert_eq "the reader counts only the out-of-vocabulary miss as malformed" 1 "$RBT_LEDGER_MALFORMED"
assert_contains "the reader keeps the conforming miss" "45	a.sh	pruned	correctness" "$(cat "$T/rows.tsv")"
assert_not_contains "the reader never reads the out-of-vocabulary miss" "vibes" "$(cat "$T/rows.tsv")"

rc=0
rbt_miss_fragment "$T/gone/2026-10-04-review-miss-0000aaaa.md" || rc=$?
assert_exit "a fragment a drain moved away is reported gone" 4 "$rc"
if [ "$(id -u)" -ne 0 ]; then
  printf '%s\n' "- 2026-10-04 [planwright] an ordinary note" >"$ledger/2026-10-04-note-00001111.md"
  chmod 000 "$ledger/2026-10-04-note-00001111.md"
  rbt_read_ledger "$T/rows.tsv" "$ledger"
  assert_eq "the reader never counts an unreadable non-miss fragment" 1 "$RBT_LEDGER_MALFORMED"
  chmod 644 "$ledger/2026-10-04-note-00001111.md"
fi

# --- the doctrine states the vocabulary the scripts enforce ---
doc_tokens() {
  awk -v k="**$1**: " 'index($0, k) == 1 { on = 1; $0 = substr($0, length(k) + 1) } on && /^$/ { exit } on { print }' "$DOC" \
    | tr -d '`.' | tr ',' '\n' | sed 's/^ *//;s/ *$//;/^$/d' | sort | tr '\n' ' '
}
lib_tokens() { printf '%s\n' "$1" | tr ' ' '\n' | sed '/^$/d' | sort | tr '\n' ' '; }
if [ -f "$DOC" ]; then
  doc_l=$(doc_tokens 'Lens tokens')
  doc_r=$(doc_tokens 'Reason tokens')
  if [ -n "$doc_l" ] && [ "$doc_l" = "$(lib_tokens "$RBT_LENSES")" ]; then
    ok "the doc's lens tokens match the scripts'"
  else
    fail "the doc's lens tokens match the scripts' (doc: '$doc_l', lib: '$(lib_tokens "$RBT_LENSES")')"
  fi
  if [ -n "$doc_r" ] && [ "$doc_r" = "$(lib_tokens "$RBT_REASONS")" ]; then
    ok "the doc's reason tokens match the scripts'"
  else
    fail "the doc's reason tokens match the scripts' (doc: '$doc_r', lib: '$(lib_tokens "$RBT_REASONS")')"
  fi
else
  fail "doctrine/review-independence.md exists"
fi

if [ "$failures" -gt 0 ]; then
  echo "$failures failure(s)" >&2
  exit 1
fi
echo "all passed"
