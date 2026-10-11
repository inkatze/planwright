#!/bin/bash
# Tests for scripts/review-backtest-refresh.sh — rebuilding the backtest corpus
# into a new version from recorded PR history plus the miss ledger, offline
# against a local bare remote with pull-request head refs
# (review-effectiveness REQ-H1.2, REQ-E1.5, D-7, D-8, D-16).
set -u
unset CDPATH

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REFRESH="$REPO_ROOT/scripts/review-backtest-refresh.sh"
SCREEN="$REPO_ROOT/scripts/review-corpus-screen.sh"

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

T=$(mktemp -d "${TMPDIR:-/tmp}/rbr.XXXXXX")
trap 'rm -rf "$T"' EXIT
export HOME="$T/home" GIT_CONFIG_NOSYSTEM=1
mkdir -p "$HOME"
git config --global user.email t@example.invalid
git config --global user.name t
git config --global init.defaultBranch main

# --- the local bare remote: PR 7's head holds commit A; PR 2's head exists but
# its thread names a commit absent from that history; PR 3 has no head ref ---
src="$T/src"
git init -q "$src"
printf 'one\n' >"$src/a.sh"
git -C "$src" add a.sh
git -C "$src" commit -qm base
A=$(git -C "$src" rev-parse HEAD)
printf 'two\n' >>"$src/a.sh"
git -C "$src" commit -qam fix
B=$(git -C "$src" rev-parse HEAD)
git -C "$src" checkout -q --orphan other
printf 'x\n' >"$src/b.sh"
git -C "$src" add b.sh
git -C "$src" commit -qm other
C=$(git -C "$src" rev-parse HEAD)
remote="$T/remote.git"
git clone -q --bare "$src" "$remote"
git -C "$remote" update-ref refs/pull/7/head "$B"
git -C "$remote" update-ref refs/pull/2/head "$C"
git -C "$remote" update-ref refs/pull/4/head "$B"
# PR 5's head is the orphan branch: its commit is in the head ref but shares no
# history with main, as a PR from before a history rewrite does.
git -C "$remote" update-ref refs/pull/5/head "$C"
MISSING=ffffffffffffffffffffffffffffffffffffffff

history() {
  # history <pr1-number> — print the recorded history with PR 1 numbered as given.
  cat <<EOF
{"repo":"example/repo","prs":[
 {"number":$1,"author":"owner","merged_at":"2026-09-01T00:00:00Z","body":"no declined log",
  "reviews":[{"author":"helper-bot","bot":true,"submitted_at":"2026-09-01T00:00:00Z"}],
  "threads":[
   {"path":"a.sh","line":1,"commit":"$A","author":"helper-bot","bot":true,"body":"the loop never exits on error","replies":[{"author":"owner","body":"Fixed in abc1234"}]},
   {"path":"lib/c.sh","line":9,"commit":"$A","author":"helper-bot","bot":true,"body":"a sibling site keeps the bug","replies":[{"author":"owner","body":"Addressed in def5678"}]},
   {"path":"a.sh","line":3,"commit":"$A","author":"helper-bot","bot":true,"body":"style nit nobody fixed","replies":[{"author":"owner","body":"Declined: by design"}]},
   {"path":"a.sh","line":5,"commit":"$A","author":"owner","bot":false,"body":"note to self","replies":[{"author":"owner","body":"Fixed in 1234567"}]}
  ]},
 {"number":2,"author":"owner","merged_at":"2026-09-02T00:00:00Z","body":"",
  "reviews":[],
  "threads":[
   {"path":"b.sh","line":1,"commit":"$MISSING","author":"helper-bot","bot":true,"body":"quoting breaks on spaces","replies":[{"author":"owner","body":"Fixed in 7654321"}]}
  ]},
 {"number":3,"author":"owner","merged_at":"2026-09-03T00:00:00Z","body":"",
  "reviews":[],
  "threads":[
   {"path":"d.sh","line":2,"commit":"$A","author":"a-human","bot":false,"body":"VERBATIM the counter is read before it is set in this branch","replies":[{"author":"owner","body":"Fixed in 1111111"}]},
   {"path":"e.sh","line":2,"commit":"$A","author":"a-human","bot":false,"body":"acmereview style issue","replies":[{"author":"owner","body":"Fixed in 2222222"}]},
   {"path":"d2.sh","line":2,"commit":"$A","author":"a-human","bot":false,"body":"VERBATIM quote it","replies":[{"author":"owner","body":"Fixed in 5555555, thanks for catching that one"}]},
   {"path":"h.sh","line":2,"commit":"$A","author":"a-human","bot":false,"body":"BADANSWER thing","replies":[{"author":"owner","body":"Fixed in 6666666"}]},
   {"path":"i.sh","line":2,"commit":"$A","author":"a-human","bot":false,"body":"LOGINGIST thing","replies":[{"author":"owner","body":"Fixed in 7777777"}]},
   {"path":"k.sh","line":2,"commit":"$A","author":"a-human","bot":false,"body":"BADDISMISS thing","replies":[{"author":"owner","body":"Fixed in 8888888"}]}
  ]},
 {"number":4,"author":"owner","merged_at":"2026-09-04T00:00:00Z","body":"## Declined\\n\\n| f.sh | portable enough on the floor |\\n\\n## Next",
  "reviews":[],
  "threads":[
   {"path":"f.sh","line":12,"commit":"$A","author":"helper-bot","bot":true,"body":"GNU-only flag","replies":[{"author":"owner","body":"Fixed in 3333333"}]}
  ]},
 {"number":5,"author":"owner","merged_at":"2026-09-05T00:00:00Z","body":"",
  "reviews":[],
  "threads":[
   {"path":"g.sh","line":1,"commit":"$C","author":"helper-bot","bot":true,"body":"an unrelated-history finding","replies":[{"author":"owner","body":"Fixed in 4444444"}]}
  ]}
]}
EOF
}

# --- the stub annotator: deterministic, offline, logs every batch it is given ---
cat >"$T/annotate.sh" <<'STUB'
#!/bin/sh
batch=$(cat)
printf '%s\n' "$batch" >>"$ANNOTATE_LOG.all"
printf '%s\n' "$batch" | jq -c '
  if (.finding | test("BADANSWER")) then {key, category: "o", gist: 5}
  elif (.finding | test("BADDISMISS")) then {key, category: "correctness", gist: "a dismissal of the wrong type", declined: true, dismissal: 5}
  else
  { key, category: "correctness",
    gist: (if (.finding | test("VERBATIM")) then .finding
           elif (.finding | test("acmereview")) then "acmereview flagged a style issue"
           elif (.finding | test("LOGINGIST")) then "as helper-bot noted, the loop races"
           else "paraphrased finding at \(.path)" end) }
  + (if .label_reason then {reason: "runtime-tracing"} else {} end)
  + (if (.declined_log | length) > 0 then {declined: true, dismissal: "the pass judged it portable enough"} else {declined: false} end)
  end'
STUB
chmod +x "$T/annotate.sh"
export ANNOTATE_LOG="$T/annotate"
: >"$ANNOTATE_LOG.all"
names="$T/names.txt"
printf 'AcmeReview\n' >"$names"
ledger="$T/entries"
mkdir -p "$ledger"
printf '%s\n' "- 2026-09-05 [planwright] review-miss(sibling-sweep, outside-diff): #7 lib/c.sh: a twin site kept the bug" >"$ledger/2026-09-05-review-miss-0000aaaa.md"
printf '%s\n' "- 2026-09-05 [planwright] review-miss(correctness, pruned): #9 x.sh: a different PR" >"$ledger/2026-09-05-review-miss-0000bbbb.md"
printf '%s\n' "- 2026-09-05 [planwright] review-miss(correctness): #7 a.sh: malformed, no reason" >"$ledger/2026-09-05-review-miss-0000cccc.md"
printf '%s\n' "- 2026-09-05 [planwright] review-miss(correctness, pruned): a.sh: no PR number" >"$ledger/2026-09-05-review-miss-0000dddd.md"

hist="$T/history.json"
history 7 >"$hist"
croot="$T/corpus"
mkdir -p "$croot"

run_refresh() {
  "$REFRESH" --history "$hist" --remote "$remote" --corpus-root "$croot" \
    --ledger-dir "$ledger" --annotate-cmd "$T/annotate.sh" "$@"
}

# --- refuses to run without the product-name list ---
out=$(CLAUDE_PLUGIN_DATA="$T/nostate" run_refresh 2>&1)
assert_exit "refuses without a product-name list" 2 $?
assert_contains "names the missing list" "product-name list" "$out"
if [ -d "$croot/v1" ]; then fail "a refused run wrote a corpus version"; else ok "a refused run writes nothing"; fi

# --- rejects a non-integer PR number before anything else ---
history '"7; rm -rf /"' >"$T/bad.json"
out=$("$REFRESH" --history "$T/bad.json" --remote "$remote" --corpus-root "$croot" \
  --ledger-dir "$ledger" --annotate-cmd "$T/annotate.sh" --names "$names" 2>&1)
assert_exit "rejects a non-integer PR number" 2 $?
assert_contains "names the PR-number rule" "PR number" "$out"
if [ -d "$croot/v1" ]; then fail "a rejected history wrote a corpus version"; else ok "a rejected history writes nothing"; fi

# --- a full refresh into v1 ---
out=$(run_refresh --names "$names" 2>&1)
rc=$?
assert_exit "refresh into v1 succeeds" 0 "$rc"
c1="$croot/v1/corpus.tsv"
if [ -f "$c1" ]; then ok "v1 corpus written"; else fail "v1 corpus missing"; fi
"$SCREEN" --names "$names" "$c1" >/dev/null 2>&1
assert_exit "the written corpus passes the screen with the list" 0 $?

row() { awk -F '\t' -v pr="$1" -v p="$2" '$2 == pr && $4 == p' "$c1"; }
r=$(row 7 a.sh)
assert_contains "the fixed external finding is a row with its pre-fix hash" "	$A	a.sh	1	" "$r"
assert_contains "a row whose commit is in its head ref is replayable" "	yes	" "$r"
assert_contains "an unrecorded fixed finding takes reason other" "	other	yes	fallback	" "$r"
r=$(row 7 lib/c.sh)
assert_contains "a ledger fragment keyed on PR and path labels its row" "	outside-diff	yes	ledger	" "$r"
r=$(row 2 b.sh)
assert_contains "a commit absent from the head ref marks the row unreplayable" "	no	" "$r"
r=$(row 4 f.sh)
assert_contains "a declined-log match becomes a declined row" "	declined	yes	declined-log	" "$r"
assert_contains "the declined row carries its paraphrased dismissal" "portable enough" "$r"
r=$(row 5 g.sh)
assert_contains "a commit with no merge base on main marks the row unreplayable" "	no	" "$r"
assert_lacks "an unfixed thread is not a row" "	a.sh	3	" "$(cat "$c1")"
assert_lacks "the author's own thread is not a row" "	a.sh	5	" "$(cat "$c1")"
assert_lacks "a verbatim gist is dropped" "VERBATIM" "$(cat "$c1")"
assert_lacks "a row naming a listed product is dropped" "e.sh" "$(cat "$c1")"
assert_lacks "no reviewer login reaches the corpus" "helper-bot" "$(cat "$c1")"
assert_contains "reports the fallback count (a.sh, b.sh, g.sh, k.sh)" "fallback other: 4" "$out"
assert_contains "reports the unreplayable count (b.sh, g.sh, and k.sh on a PR with no head ref)" "unreplayable: 3" "$out"
assert_contains "reports the verbatim drops, a short comment copied whole included" "dropped verbatim: 2" "$out"
assert_contains "a malformed annotator answer is dropped, not fatal" "dropped unannotated: 1" "$out"
assert_contains "a gist naming a login from the history is dropped" "dropped naming a login: 1" "$out"
assert_lacks "the login-naming gist never reaches the corpus" "i.sh" "$(cat "$c1")"
r=$(row 3 k.sh)
assert_contains "a non-string dismissal is not a declined match" "	other	no	fallback	" "$r"
assert_contains "reports the screened drop" "dropped by screen: 1" "$out"
assert_contains "warns about the malformed miss fragments, one lacking a PR number" "warning: 2 malformed review-miss" "$out"
assert_lacks "never echoes a PR body or comment" "never exits" "$out"

# --- a second refresh writes v2, carries labels, leaves v1 untouched ---
sum1=$(cksum <"$c1")
printf '%s\n' "- 2026-09-06 [planwright] review-miss(correctness, declined): #7 a.sh: declined before the fix" >"$ledger/2026-09-06-review-miss-0000eeee.md"
: >"$ANNOTATE_LOG.all"
out=$(run_refresh --names "$names" 2>&1)
assert_exit "refresh into v2 succeeds" 0 $?
if [ -f "$croot/v2/corpus.tsv" ]; then ok "v2 corpus written"; else fail "v2 corpus missing"; fi
if [ "$(cksum <"$c1")" = "$sum1" ]; then ok "v1 is unchanged by a later refresh"; else fail "v1 changed"; fi
carried=$(grep -c '"path":"a.sh"' "$ANNOTATE_LOG.all")
if [ "$carried" -eq 0 ]; then ok "a carried row is not re-annotated"; else fail "carried row re-annotated ($carried)"; fi
assert_contains "reports the carried rows" "carried: 6" "$out"
r=$(awk -F '\t' '$2 == 7 && $4 == "a.sh"' "$croot/v2/corpus.tsv")
assert_contains "a new ledger entry relabels a carried row" "	declined	yes	ledger	" "$r"
assert_contains "a carried row relabelled declined gets a dismissal" "the convergence pass declined it" "$r"
rm -f "$ledger/2026-09-06-review-miss-0000eeee.md"

# --- --label-reasons asks the annotator for the class (the v1 bootstrap) ---
rm -rf "$croot"/v*
run_refresh --names "$names" --label-reasons >/dev/null 2>&1
assert_exit "a labelling refresh succeeds" 0 $?
r=$(awk -F '\t' '$2 == 7 && $4 == "a.sh"' "$croot/v1/corpus.tsv")
assert_contains "a model-labelled row records its label source" "	runtime-tracing	yes	model	" "$r"

# --- --fetch-only normalizes the fetched history, needing no list or annotator ---
mkdir -p "$T/bin"
cat >"$T/bin/gh" <<'EOF'
#!/bin/sh
case "$1 $2" in
  "repo view") printf 'example/repo\n' ;;
  "api graphql")
    cat <<'JSON'
{"data":{"repository":{"pullRequests":{"pageInfo":{"hasNextPage":false,"endCursor":null},"nodes":[
 {"number":12,"mergedAt":"2026-09-01T00:00:00Z","body":"b","author":{"login":"owner"},
  "reviews":{"nodes":[{"author":{"login":"helper-bot","__typename":"Bot"},"submittedAt":"2026-09-01T00:00:00Z"}]},
  "reviewThreads":{"nodes":[{"path":"a.sh","originalLine":4,"comments":{"nodes":[
    {"author":{"login":"helper-bot","__typename":"Bot"},"body":"x","originalCommit":{"oid":"0123456789abcdef0123456789abcdef01234567"}},
    {"author":null,"body":"Fixed in abc1234","originalCommit":{"oid":"0123456789abcdef0123456789abcdef01234567"}}]}}]}}
]}}}}
JSON
    ;;
  *) exit 9 ;;
esac
EOF
chmod +x "$T/bin/gh"
out=$(PATH="$T/bin:$PATH" CLAUDE_PLUGIN_DATA="$T/nostate" "$REFRESH" --fetch-only --dump-history "$T/fetched.json" 2>&1)
assert_exit "--fetch-only runs without the name list or an annotator" 0 $?
norm=$(jq -c '.prs[0] | [.number, .author, .reviews[0].bot, .threads[0].line, .threads[0].commit[0:7], .threads[0].replies[0].author]' "$T/fetched.json" 2>&1)
assert_contains "--fetch-only writes the normalized history" '[12,"owner",true,4,"0123456","ghost"]' "$norm"
if [ -d "$croot/v2" ]; then fail "--fetch-only wrote a corpus version"; else ok "--fetch-only writes no corpus"; fi
"$REFRESH" --fetch-only >/dev/null 2>&1
assert_exit "--fetch-only without --dump-history is a usage error" 2 $?

if [ "$failures" -ne 0 ]; then
  echo "$failures failure(s)" >&2
  exit 1
fi
echo "all review-backtest-refresh tests passed"
