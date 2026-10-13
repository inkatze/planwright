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
BASE=$(git -C "$src" rev-parse HEAD)
# The PR commits sit on a side branch, as an unmerged or squash-merged PR's do;
# main stays at the base.
git -C "$src" checkout -qb pr
printf 'change\n' >>"$src/a.sh"
git -C "$src" commit -qam change
A=$(git -C "$src" rev-parse HEAD)
printf 'two\n' >>"$src/a.sh"
git -C "$src" commit -qam fix
B=$(git -C "$src" rev-parse HEAD)
git -C "$src" checkout -q main
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
   {"path":"a.sh","line":1,"commit":"$A","author":"other-bot","bot":true,"body":"the same line again","replies":[{"author":"owner","body":"Fixed in abc1234"}]},
   {"path":"l.sh","line":3,"side":"LEFT","commit":"$A","author":"helper-bot","bot":true,"body":"on a deleted line","replies":[{"author":"owner","body":"Fixed in abc1234"}]},
   {"path":"a.sh","line":7,"commit":"$A","author":"helper-bot","bot":true,"body":"a declined one","replies":[{"author":"owner","body":"Addressed: this is a false positive, declining."}]},
   {"path":"a.sh","line":8,"commit":"$A","author":"helper-bot","bot":true,"body":"a deferred one","replies":[{"author":"owner","body":"Not fixed in 1234567; deferring to a follow-up"}]},
   {"path":"a.sh","line":10,"commit":"$A","author":"helper-bot","bot":true,"body":"another deferred one","replies":[{"author":"owner","body":"Not yet fixed in 1234567"}]},
   {"path":"a.sh","line":11,"commit":"$A","author":"helper-bot","bot":true,"body":"split negation","replies":[{"author":"owner","body":"Not\\nfixed in 1234567"}]},
   {"path":"a.sh","line":12,"commit":"$A","author":"helper-bot","bot":true,"body":"long negation","replies":[{"author":"owner","body":"This has not been fixed in 1234567"}]},
   {"path":"a.sh","line":13,"commit":"$A","author":"helper-bot","bot":true,"body":"negated other verb","replies":[{"author":"owner","body":"Not changed in 1234567; keeping it"}]},
   {"path":"a.sh","line":14,"commit":"$A","author":"helper-bot","bot":true,"body":"unit word","replies":[{"author":"owner","body":"Unit tests fixed in 1234567"}]},
   {"path":"a.sh","line":15,"commit":"$A","author":"helper-bot","bot":true,"body":"cannot","replies":[{"author":"owner","body":"This cannot be addressed in 1234567; it is upstream"}]},
   {"path":"a.sh","line":9,"commit":"$A","author":"helper-bot","bot":true,"body":"a real one","replies":[{"author":"owner","body":"Fixed, not a false positive after all"}]},
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
   {"path":"h2.sh","line":2,"commit":"$A","author":"a-human","bot":false,"body":"BADCATEGORY thing","replies":[{"author":"owner","body":"Fixed in 6666667"}]},
   {"path":"h3.sh","line":2,"commit":"$A","author":"a-human","bot":false,"body":"BADREASON thing","replies":[{"author":"owner","body":"Fixed in 6666668"}]},
   {"path":"bs.sh","line":2,"commit":"$A","author":"a-human","bot":false,"body":"BACKSLASH thing","replies":[{"author":"owner","body":"Fixed in 6666669"}]},
   {"path":"twoword.sh","line":2,"commit":"$A","author":"a-human","bot":false,"body":"VERBATIM nit","replies":[{"author":"owner","body":"Fixed in 6666673"}]},
   {"path":"ok.sh","line":2,"commit":"$A","author":"a-human","bot":false,"body":"OBJECTKEY thing","replies":[{"author":"owner","body":"Fixed in 6666671"}]},
   {"path":"arr.sh","line":2,"commit":"$A","author":"a-human","bot":false,"body":["not","a","string"],"replies":[{"author":"owner","body":["Fixed in 6666672"]}]},
   {"path":"bidi\u202esh","line":2,"commit":"$A","author":"a-human","bot":false,"body":"a hidden path","replies":[{"author":"owner","body":"Fixed in 6666670"}]},
   {"path":"i.sh","line":2,"commit":"$A","author":"a-human","bot":false,"body":"LOGINGIST thing","replies":[{"author":"owner","body":"Fixed in 7777777"}]},
   {"path":"k.sh","line":2,"commit":"$A","author":"a-human","bot":false,"body":"BADDISMISS thing","replies":[{"author":"owner","body":"Fixed in 8888888"}]}
  ]},
 {"number":4,"author":"owner","merged_at":"2026-09-04T00:00:00Z","body":"## Declined\\n\\n| f.sh | portable enough on the floor |\\n\\n## Next",
  "reviews":[],
  "threads":[
   {"path":"f.sh","line":12,"commit":"$A","author":"helper-bot","bot":true,"body":"GNU-only flag","replies":[{"author":"owner","body":"Fixed in 3333333"}]}
  ]},
 {"number":5,"author":"owner","merged_at":"2026-09-05T00:00:00Z","body":"","truncated":true,
  "reviews":[],
  "threads":[
   {"path":"onmain.sh","line":1,"commit":"$BASE","author":"helper-bot","bot":true,"body":"a commit already on main","replies":[{"author":"owner","body":"Fixed in 4444445"}]},
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
  if (.finding | test("BADANSWER")) then {key, category: "correctness", gist: 5}
  elif (.finding | test("OBJECTKEY")) then {key: {"x": 1}, category: "correctness", gist: "a key that is an object"}
  elif (.finding | test("BADCATEGORY")) then {key, category: "o", gist: "a category that is only a substring"}
  elif (.finding | test("BADREASON")) then {key, category: "correctness", gist: "a reason that is only a substring", reason: "tracing", declined: false}
  elif (.finding | test("BACKSLASH")) then {key, category: "correctness", gist: "the format string printf %s\\n lost its newline", declined: false}
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
r=$(row 5 onmain.sh)
assert_contains "a commit already on main marks the row unreplayable" "	no	" "$r"
r=$(row 5 g.sh)
assert_contains "a commit with no merge base on main marks the row unreplayable" "	no	" "$r"
assert_lacks "an unfixed thread is not a row" "	a.sh	3	" "$(cat "$c1")"
assert_lacks "the author's own thread is not a row" "	a.sh	5	" "$(cat "$c1")"
assert_lacks "a verbatim gist is dropped" "VERBATIM" "$(cat "$c1")"
assert_lacks "a row naming a listed product is dropped" "e.sh" "$(cat "$c1")"
assert_lacks "no reviewer login reaches the corpus" "helper-bot" "$(cat "$c1")"
assert_contains "reports the fallback count (a.sh three times, b.sh, g.sh, onmain.sh, k.sh, h3.sh, bs.sh)" "fallback other: 9" "$out"
assert_contains "reports the unreplayable count (b.sh, g.sh, onmain.sh, and three rows on a PR with no head ref)" "unreplayable: 6" "$out"
assert_contains "reports the verbatim drops, short comments copied whole included" "dropped verbatim: 3" "$out"
assert_contains "a path outside printable ASCII and a base-side thread are skipped" "skipped malformed location: 2" "$out"
assert_contains "two threads on one line of one commit are one row" "merged duplicate threads: 1" "$out"
if [ "$(awk -F '\t' '$2 == 7 && $4 == "a.sh" && $5 == 1' "$c1" | wc -l | tr -d ' ')" -eq 1 ]; then ok "the duplicate thread writes a single row"; else fail "the duplicate thread wrote two rows"; fi
assert_lacks "a reply that declines is not a fix, whatever its first word" "	a.sh	7	" "$(cat "$c1")"
assert_lacks "\"not fixed in <sha>\" is not a fix" "	a.sh	8	" "$(cat "$c1")"
assert_lacks "\"not yet fixed in <sha>\" is not a fix" "	a.sh	10	" "$(cat "$c1")"
assert_lacks "a negation split by a newline is still a negation" "	a.sh	11	" "$(cat "$c1")"
assert_lacks "\"has not been fixed in <sha>\" is not a fix" "	a.sh	12	" "$(cat "$c1")"
assert_lacks "a negated verb other than fixed is not a fix" "	a.sh	13	" "$(cat "$c1")"
assert_contains "a word ending in n-t (unit) is no negation" "	a.sh	14	" "$(cat "$c1")"
assert_lacks "\"cannot\" is a negation" "	a.sh	15	" "$(cat "$c1")"
assert_contains "\"not a false positive\" does not veto a fix" "	a.sh	9	" "$(cat "$c1")"
assert_contains "warns about a PR whose threads overflowed the fetch page" "warning: 1 PR(s) had more reviews, threads, or comments" "$out"
assert_lacks "a non-string comment body never becomes a row" "arr.sh" "$(cat "$c1")"
assert_contains "a non-string gist and a substring category are each dropped, not fatal" "dropped unannotated: 3" "$out"
assert_contains "a gist naming a login from the history is dropped" "dropped naming a login: 1" "$out"
assert_lacks "the login-naming gist never reaches the corpus" "i.sh" "$(cat "$c1")"
r=$(row 3 k.sh)
assert_contains "a non-string dismissal is not a declined match" "	other	no	fallback	" "$r"
assert_contains "reports the screened drop" "dropped by screen: 1" "$out"
assert_contains "warns about the malformed miss fragments, one lacking a PR number" "warning: 2 malformed review-miss" "$out"
assert_lacks "never echoes a PR body or comment" "never exits" "$out"

# --- a second refresh writes v2, carries labels, leaves v1 untouched ---
bs1=$(awk -F '\t' '$4 == "bs.sh"' "$c1")
assert_contains "a backslash in a gist is written once" 'printf %s\n lost' "$bs1"
awk -F '\t' 'BEGIN { OFS = "\t" } $4 == "f.sh" { $10 = "as helper-bot put it, the flag is GNU-only" } $4 == "g.sh" { $10 = "an unrelated-history finding" } { print }' "$c1" >"$T/c1.tampered"
cat "$T/c1.tampered" >"$c1"
sum1=$(cksum <"$c1")
printf '%s\n' "- 2026-09-06 [planwright] review-miss(correctness, declined): #7 a.sh: declined before the fix" >"$ledger/2026-09-06-review-miss-0000eeee.md"
: >"$ANNOTATE_LOG.all"
out=$(run_refresh --names "$names" 2>&1)
assert_exit "refresh into v2 succeeds" 0 $?
if [ -f "$croot/v2/corpus.tsv" ]; then ok "v2 corpus written"; else fail "v2 corpus missing"; fi
if [ "$(cksum <"$c1")" = "$sum1" ]; then ok "v1 is unchanged by a later refresh"; else fail "v1 changed"; fi
carried=$(grep -c '"path":"a.sh"' "$ANNOTATE_LOG.all")
if [ "$carried" -eq 0 ]; then ok "a carried row is not re-annotated"; else fail "carried row re-annotated ($carried)"; fi
assert_contains "reports the carried rows" "carried: 9" "$out"
assert_contains "a carried gist naming a login is dropped too" "dropped naming a login: 2" "$out"
assert_contains "a carried gist copying its comment is dropped too" "dropped verbatim: 4" "$out"
if [ "$(awk -F '\t' '$4 == "bs.sh"' "$croot/v2/corpus.tsv" | cut -f2-)" = "$(printf '%s\n' "$bs1" | cut -f2-)" ]; then ok "a carried backslash survives a refresh unchanged"; else fail "a carried backslash changed"; fi
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
r=$(awk -F '\t' '$4 == "h3.sh"' "$croot/v1/corpus.tsv")
assert_contains "a reason that only contains a class name falls back to other" "	other	no	fallback	" "$r"

# --- an abandoned empty version directory never blocks the next refresh ---
mkdir "$croot/v2"
run_refresh --names "$names" >/dev/null 2>&1
assert_exit "a refresh past an abandoned empty claim succeeds" 0 $?
if [ -f "$croot/v3/corpus.tsv" ]; then ok "it writes the version after the abandoned one"; else fail "the abandoned claim blocked the refresh"; fi
if [ -d "$croot/v2" ] && [ ! -e "$croot/v2/corpus.tsv" ]; then ok "the abandoned directory is left as it was"; else fail "the abandoned directory was touched"; fi
rm -rf "$croot/v2" "$croot/v3"
: >"$croot/v2"
run_refresh --names "$names" >/dev/null 2>&1
assert_exit "a version that cannot be claimed is refused" 1 $?
if [ -f "$croot/v2" ]; then ok "a refused claim leaves what held the name"; else fail "a refused claim removed what it did not create"; fi
rm -f "$croot/v2"

# --- an interrupted refresh ends its running annotator ---
cat >"$T/slow-annotate.sh" <<EOF
#!/bin/sh
cat >/dev/null
: >"$T/annotate.started"
sleep 4
: >"$T/annotate.finished"
EOF
chmod +x "$T/slow-annotate.sh"
rm -f "$T/annotate.started" "$T/annotate.finished"
mkdir -p "$T/croot2"
"$REFRESH" --history "$hist" --remote "$remote" --corpus-root "$T/croot2" --ledger-dir "$ledger" \
  --annotate-cmd "$T/slow-annotate.sh" --names "$names" >/dev/null 2>&1 &
rpid=$!
n=0
until [ -e "$T/annotate.started" ] || [ "$n" -ge 200 ]; do
  sleep 0.1
  n=$((n + 1))
done
kill -TERM "$rpid"
wait "$rpid" 2>/dev/null
sleep 5
if [ -e "$T/annotate.started" ] && [ ! -e "$T/annotate.finished" ]; then ok "a TERM to the refresh ends its annotator"; else fail "the annotator outlived the refresh"; fi
if [ ! -e "$T/croot2/v1" ]; then ok "an interrupted refresh writes no version"; else fail "an interrupted refresh left a version"; fi
"$REFRESH" --fetch-only --dump-history "$T/x.json" --history "$hist" >/dev/null 2>&1
assert_exit "--fetch-only refuses --history" 2 $?

"$REFRESH" --history "$hist" --remote "--upload-pack=x" --corpus-root "$T/croot3" --ledger-dir "$ledger" --annotate-cmd "$T/annotate.sh" --names "$names" >/dev/null 2>&1
assert_exit "a remote beginning with a dash is refused" 2 $?

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
  "reviewThreads":{"totalCount":150,"nodes":[{"path":"a.sh","originalLine":4,"diffSide":"LEFT","comments":{"nodes":[
    {"author":{"login":"helper-bot","__typename":"Bot"},"body":"x","originalCommit":{"oid":"0123456789abcdef0123456789abcdef01234567"}},
    {"author":null,"body":"Fixed in abc1234","originalCommit":{"oid":"0123456789abcdef0123456789abcdef01234567"}}]}}]}},
 {"number":13,"mergedAt":"2026-09-02T00:00:00Z","body":"","author":{"login":"owner"},
  "reviews":{"totalCount":70,"nodes":[]},"reviewThreads":{"totalCount":0,"nodes":[]}}
]}}}}
JSON
    ;;
  *) exit 9 ;;
esac
EOF
chmod +x "$T/bin/gh"
out=$(PATH="$T/bin:$PATH" CLAUDE_PLUGIN_DATA="$T/nostate" "$REFRESH" --fetch-only --annotate-cmd "$T/absent-annotator" --dump-history "$T/fetched.json" 2>&1)
assert_exit "--fetch-only runs without the name list or an annotator" 0 $?
norm=$(jq -c '.prs[0] | [.number, .author, .reviews[0].bot, .threads[0].line, .threads[0].commit[0:7], .threads[0].replies[0].author, .threads[0].side, .truncated]' "$T/fetched.json" 2>&1)
assert_contains "--fetch-only writes the normalized history, side and truncation included" '[12,"owner",true,4,"0123456","ghost","LEFT",true]' "$norm"
assert_contains "a PR whose reviews overflow the page is truncated" "true" "$(jq -c '.prs[1].truncated' "$T/fetched.json")"
if [ -d "$croot/v2" ]; then fail "--fetch-only wrote a corpus version"; else ok "--fetch-only writes no corpus"; fi
"$REFRESH" --fetch-only >/dev/null 2>&1
assert_exit "--fetch-only without --dump-history is a usage error" 2 $?

if [ "$failures" -ne 0 ]; then
  echo "$failures failure(s)" >&2
  exit 1
fi
echo "all review-backtest-refresh tests passed"
