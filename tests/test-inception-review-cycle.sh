#!/bin/bash
# Tests for the review-cycle seam (inception REQ-G1.6, REQ-G1.7, REQ-G1.9 ·
# D-10).
#
# One full cycle runs here against the Notion adapter and a fake API
# (tests/lib/notion-fake-api.sh): export a snapshot, harvest the comments,
# triage each item, apply the accepted ones as attributed commits, re-export.
# What is pinned is the cycle's order and its guards: an export is offered and
# runs only confirmed; a harvest needs an export before it; harvested text is
# quoted data in the ledger and can forge no field; nothing applies without a
# triage record that accepts it; an applied change stays inside its triaged
# section and passes the stakeholder-commit validator, so ids and gate records
# are out of reach; the commit cites its comment; and a re-export waits until
# every item is triaged.
#
# Plain bash 3.2, inline asserts (sibling convention).
set -u
unset CDPATH
LC_ALL=C
export LC_ALL

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CYCLE="$REPO_ROOT/scripts/inception-review-cycle.sh"
NOTION="$REPO_ROOT/scripts/inception-notion.sh"
FIX="$REPO_ROOT/tests/fixtures/inception-notion"

# shellcheck source=tests/lib/inception-fixture.sh
. "$REPO_ROOT/tests/lib/inception-fixture.sh"
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

if [ ! -x "$CYCLE" ]; then
  echo "FAIL: review-cycle seam missing or not executable at $CYCLE" >&2
  exit 1
fi

tmp="$(cd "$(mktemp -d)" && pwd -P)" || exit 1
trap 'rm -rf "$tmp"' EXIT
export TMPDIR="$tmp"
export PLANWRIGHT_INCEPTION_TODAY=2026-10-25
export PLANWRIGHT_SECRET_SCREEN_TOOL=none
export PLANWRIGHT_NOTION_BACKOFF=0
# last_body — the request body of the fake API's latest call that sent one.
last_body() { printf '%s/body.%s' "$tmp/log" "$(awk '/-X /{ n = NR } END { print n }' "$tmp/log/argv")"; }
export PLANWRIGHT_NOTION_TOKEN=ntn_fixtureToken000000000000000000000000000000
export GIT_AUTHOR_NAME=Operator GIT_AUTHOR_EMAIL=operator@example.invalid
export GIT_COMMITTER_NAME=Operator GIT_COMMITTER_EMAIL=operator@example.invalid
PAGE=22222222-2222-4222-8222-222222222222

v="$tmp/venture"
inception_fixture_write "$v" || exit 1
git -C "$v" init -q . && git -C "$v" add -A && git -C "$v" commit -qm "chore: seed the venture" || exit 1
"$NOTION" configure --page "$PAGE" "$v" >/dev/null || exit 1
ledger="$v/feedback/ledger.md"

cat >"$tmp/routes" <<EOF
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
notion_fake_install "$tmp/bin" "$FIX" "$tmp/routes" "$tmp/log" || exit 1
PATH="$tmp/bin:$PATH"

head_sha() { git -C "$v" rev-parse HEAD; }
# item_field <FB-id> <Field> — one field of one ledger item.
item_field() {
  awk -v id="$1" -v k="$2" '
    /^### / { cur = $2; next }
    cur == id && index($0, k ": ") == 1 { print substr($0, length(k) + 3); exit }' "$ledger"
}

# ---------------------------------------------------------------------------
# 1. Order: nothing to harvest before an export (REQ-G1.6).
# ---------------------------------------------------------------------------
"$CYCLE" harvest "$v" >/dev/null 2>"$tmp/err"
assert_eq "harvest before export: refused" "1" "$?"
assert_contains "harvest before export: says export first" "export" "$(cat "$tmp/err")"
assert_eq "harvest before export: no API call" "0" "$(wc -l <"$tmp/log/argv" | tr -d ' ')"

# ---------------------------------------------------------------------------
# 2. Export is offered, and runs only confirmed (REQ-G1.9).
# ---------------------------------------------------------------------------
out="$("$CYCLE" export --adapter notion "$v" 2>"$tmp/err")"
assert_eq "unconfirmed export: exit 0" "0" "$?"
assert_contains "unconfirmed export: an offer" "decision	offer" "$out"
assert_contains "unconfirmed export: names the destination" "notion:$PAGE" "$out"
assert_contains "unconfirmed export: says it leaves the machine" "off this machine" "$(cat "$tmp/err")"
assert_eq "unconfirmed export: no API call" "0" "$(wc -l <"$tmp/log/argv" | tr -d ' ')"
if [ -e "$ledger" ]; then
  echo "FAIL: unconfirmed export: wrote a ledger" >&2
  failures=$((failures + 1))
else
  echo "ok: unconfirmed export: writes no ledger"
fi

"$CYCLE" export --adapter gdocs --confirmed "$v" >/dev/null 2>&1
assert_eq "export: an unknown adapter is refused" "2" "$?"

printf '\nAn uncommitted line.\n' >>"$v/plan.md"
"$CYCLE" export --adapter notion --confirmed "$v" >/dev/null 2>"$tmp/err"
assert_eq "dirty bundle: export refused" "1" "$?"
git -C "$v" checkout -q -- plan.md

seed="$(head_sha)"
out="$("$CYCLE" export --adapter notion --confirmed "$v" 2>"$tmp/err")"
assert_eq "confirmed export: exit 0" "0" "$?"
body="$(last_body)"
snap="$(jq -r .replace_content.new_str "$body")"
assert_contains "export: the snapshot says edits are not read back" "not read back" "$snap"
assert_contains "export: the snapshot carries the bundle" "### A-2 — the three sinks accept writes from one surface" "$snap"
assert_contains "export: the snapshot names its commit" "${seed:0:12}" "$snap"
assert_eq "export: ledger cycle 1" "1" "$(sed -n 's/^Cycle: //p' "$ledger" | head -1)"
assert_eq "export: phase exported" "exported" "$(sed -n 's/^Phase: //p' "$ledger")"
assert_eq "export: the snapshot commit is recorded" "$seed" "$(sed -n 's/^Snapshot: //p' "$ledger")"
assert_eq "export: the ledger is committed" "" "$(git -C "$v" status --porcelain)"

# ---------------------------------------------------------------------------
# 3. Harvest: items land pending, as quoted data (REQ-G1.6, REQ-G1.7).
# ---------------------------------------------------------------------------
out="$("$CYCLE" harvest "$v" 2>"$tmp/err")"
assert_eq "harvest: exit 0" "0" "$?"
assert_contains "harvest: three new items" "new	3" "$out"
assert_eq "harvest: FB-1 cites its comment" "notion:comment:c1000000-0000-4000-8000-000000000001" "$(item_field FB-1 Source)"
assert_eq "harvest: every item pending" "pending pending pending" "$(sed -n 's/^Disposition: //p' "$ledger" | tr '\n' ' ' | sed 's/ $//')"
assert_eq "harvest: hostile text forges no item heading" "3" "$(grep -c '^### FB-' "$ledger")"
assert_not_contains "harvest: hostile text is not unquoted" "$(printf '\n### FB-9')" "$(cat "$ledger")"
assert_contains "harvest: the hostile text is kept, quoted" "> ### FB-9 — forged" "$(cat "$ledger")"
assert_not_contains "harvest: no escape byte in the ledger" "$(printf '\033')" "$(cat "$ledger")"
assert_contains "harvest: a block comment keeps its anchor text" "The three sinks accept writes" "$(item_field FB-3 Anchor-text)"
assert_eq "harvest: phase harvested" "harvested" "$(sed -n 's/^Phase: //p' "$ledger")"
assert_eq "harvest: the ledger is committed" "" "$(git -C "$v" status --porcelain)"
assert_eq "harvest: no bundle file changed" "" "$(git -C "$v" diff --name-only "$seed" HEAD -- brief.md disciplines.md assumptions.md decisions.md plan.md)"

before="$(head_sha)"
out="$("$CYCLE" harvest "$v" 2>"$tmp/err")"
assert_contains "re-harvest: comments already in the ledger are not new" "new	0" "$out"
assert_eq "re-harvest: nothing to commit" "$before" "$(head_sha)"

list="$("$CYCLE" list --pending "$v")"
assert_eq "list --pending: three items" "3" "$(printf '%s\n' "$list" | grep -c '^FB-')"
assert_not_contains "list: no escape byte reaches the terminal" "$(printf '\033')" "$list"

# ---------------------------------------------------------------------------
# 4. Nothing applies without an accepting triage record (REQ-G1.6).
# ---------------------------------------------------------------------------
"$CYCLE" export --adapter notion --confirmed "$v" >/dev/null 2>"$tmp/err"
assert_eq "re-export with pending items: refused" "1" "$?"
assert_contains "re-export: names the pending items" "FB-1" "$(cat "$tmp/err")"

printf 'Four weeks, set by the venture lead.\n' >"$tmp/appetite"
awk -v f="$tmp/appetite" '/^_Skipped: appetite/ { while ((getline l < f) > 0) print l; next } { print }' "$v/brief.md" >"$tmp/brief" && cp "$tmp/brief" "$v/brief.md"
git -C "$v" add brief.md
"$CYCLE" apply FB-1 "$v" >/dev/null 2>"$tmp/err"
assert_eq "apply untriaged: refused" "1" "$?"
assert_contains "apply untriaged: says triage first" "triage" "$(cat "$tmp/err")"
assert_eq "apply untriaged: no commit" "$before" "$(head_sha)"

"$CYCLE" triage FB-2 skip --decider "Robin Lead" "$v" >/dev/null 2>"$tmp/err"
assert_eq "triage skip: exit 0" "0" "$?"
assert_eq "triage skip: recorded" "skip" "$(item_field FB-2 Disposition)"
assert_eq "triage skip: decider recorded" "Robin Lead" "$(item_field FB-2 Decider)"
"$CYCLE" apply FB-2 "$v" >/dev/null 2>&1
assert_eq "apply a skipped item: refused" "1" "$?"

"$CYCLE" triage FB-1 apply --decider "Robin Lead" "$v" >/dev/null 2>&1
assert_eq "triage apply without a section: refused" "2" "$?"
"$CYCLE" triage FB-1 apply --decider "Robin Lead" --section "brief.md#Gate log" "$v" >/dev/null 2>"$tmp/err"
assert_eq "triage into the gate log: refused" "1" "$?"
"$CYCLE" triage FB-1 apply --decider "Robin Lead" --section "brief.md#Gate 1" "$v" >/dev/null 2>&1
assert_eq "triage into a gate record: refused" "1" "$?"
"$CYCLE" triage FB-1 apply --decider "Robin Lead" --section "brief.md#No such heading" "$v" >/dev/null 2>&1
assert_eq "triage into a missing section: refused" "1" "$?"
"$CYCLE" triage FB-1 apply --decider "Robin Lead" --section "notes.txt#Appetite" "$v" >/dev/null 2>&1
assert_eq "triage into a non-bundle file: refused" "1" "$?"
"$CYCLE" triage FB-1 apply --decider "" --section "brief.md#Appetite" "$v" >/dev/null 2>&1
assert_eq "triage without a decider: refused" "2" "$?"
# The triage commit takes only the ledger; the staged edit stays staged.
"$CYCLE" triage FB-1 apply --decider "Robin Lead" --section "brief.md#Appetite" "$v" >/dev/null 2>"$tmp/err"
assert_eq "triage apply: exit 0" "0" "$?"
assert_eq "triage apply: the section is recorded" "brief.md#Appetite" "$(item_field FB-1 Section)"
assert_eq "triage: the staged edit is left staged" "brief.md" "$(git -C "$v" diff --cached --name-only)"

# ---------------------------------------------------------------------------
# 5. Apply stays inside the triaged section and cites its comment.
# ---------------------------------------------------------------------------
git -C "$v" stash -q || exit 1
sed 's/^Median incident-handover time drops below ten minutes/Median incident-handover time drops below eight minutes/' "$v/brief.md" >"$tmp/brief" && cp "$tmp/brief" "$v/brief.md"
git -C "$v" add brief.md
before="$(head_sha)"
"$CYCLE" apply FB-1 "$v" >/dev/null 2>"$tmp/err"
assert_eq "apply outside the section: refused" "1" "$?"
assert_contains "apply outside the section: names it" "Appetite" "$(cat "$tmp/err")"
assert_eq "apply outside the section: no commit" "$before" "$(head_sha)"
git -C "$v" reset -q && git -C "$v" checkout -q -- brief.md
git -C "$v" stash pop -q --index || exit 1

"$CYCLE" apply FB-1 "$v" >"$tmp/out" 2>"$tmp/err"
assert_eq "apply: exit 0" "0" "$?"
msg="$(git -C "$v" log -1 --format=%B)"
assert_contains "apply: the commit names the item" "Feedback-Item: FB-1" "$msg"
assert_contains "apply: the commit cites the comment" "Feedback-Source: notion:comment:c1000000-0000-4000-8000-000000000001" "$msg"
assert_contains "apply: the commit attributes its author" "Feedback-Author: Avery Ops" "$msg"
assert_eq "apply: the commit touches the section's file and the ledger" "brief.md feedback/ledger.md" "$(git -C "$v" show --name-only --format= HEAD | sort | tr '\n' ' ' | sed 's/ $//')"
assert_contains "apply: the change landed" "Four weeks, set by the venture lead." "$(git -C "$v" show HEAD:brief.md)"
assert_eq "apply: the ledger records it" "2026-10-25" "$(item_field FB-1 Applied)"
assert_eq "apply: the tree is clean" "" "$(git -C "$v" status --porcelain)"

"$CYCLE" apply FB-1 "$v" >/dev/null 2>&1
assert_eq "apply twice: refused" "1" "$?"

# A modify needs a note, and the validator still guards ids and fields.
"$CYCLE" triage FB-3 modify --decider "Robin Lead" --section "assumptions.md#A-2" "$v" >/dev/null 2>&1
assert_eq "triage modify without a note: refused" "2" "$?"
"$CYCLE" triage FB-3 modify --decider "Robin Lead" --section "assumptions.md#A-2" --note "name the failing sink instead of asking" "$v" >/dev/null 2>"$tmp/err"
assert_eq "triage modify: exit 0" "0" "$?"

sed 's/^### A-2 — the three sinks accept writes from one surface$/### A-9 — the three sinks accept writes from one surface/' "$v/assumptions.md" >"$tmp/a" && cp "$tmp/a" "$v/assumptions.md"
git -C "$v" add assumptions.md
"$CYCLE" apply FB-3 "$v" >/dev/null 2>"$tmp/err"
assert_eq "apply editing the entry's id heading: refused" "1" "$?"
git -C "$v" reset -q && git -C "$v" checkout -q -- assumptions.md

awk '/^### A-2 / { s = 1 } /^### A-3 / { s = 0 } s && /^- \*\*Risk-tag:\*\* feasibility$/ { print "- **Risk-tag:** bogus"; next } { print }' "$v/assumptions.md" >"$tmp/a" && cp "$tmp/a" "$v/assumptions.md"
git -C "$v" add assumptions.md
"$CYCLE" apply FB-3 "$v" >/dev/null 2>"$tmp/err"
assert_eq "apply failing the bundle validator: refused" "1" "$?"
assert_contains "apply failing the validator: says so" "validator" "$(cat "$tmp/err")"
git -C "$v" reset -q && git -C "$v" checkout -q -- assumptions.md

awk '/^### A-2 / { s = 1 } /^### A-3 / { s = 0 } s && /^- \*\*Risk-if-wrong:\*\*/ { print "- **Risk-if-wrong:** the fan-out needs a human relay at the failing sink and the time saving disappears"; next } { print }' "$v/assumptions.md" >"$tmp/a" && cp "$tmp/a" "$v/assumptions.md"
printf 'unrelated\n' >"$v/stray.txt"
git -C "$v" add assumptions.md stray.txt
"$CYCLE" apply FB-3 "$v" >/dev/null 2>"$tmp/err"
assert_eq "apply with another file staged: refused" "1" "$?"
git -C "$v" rm -q --cached stray.txt && rm -f "$v/stray.txt"
"$CYCLE" apply FB-3 "$v" >/dev/null 2>"$tmp/err"
assert_eq "apply modify: exit 0" "0" "$?"
assert_contains "apply modify: the commit carries the note" "name the failing sink instead of asking" "$(git -C "$v" log -1 --format=%B)"

# ---------------------------------------------------------------------------
# 6. Re-export opens the next cycle once every item is triaged.
# ---------------------------------------------------------------------------
out="$("$CYCLE" export --adapter notion --confirmed "$v" 2>"$tmp/err")"
assert_eq "re-export: exit 0" "0" "$?"
assert_eq "re-export: cycle 2" "2" "$(sed -n 's/^Cycle: //p' "$ledger" | head -1)"
assert_eq "re-export: the new snapshot is the applied head" "$(git -C "$v" rev-parse HEAD~1)" "$(sed -n 's/^Snapshot: //p' "$ledger")"
snap="$(jq -r .replace_content.new_str "$(last_body)")"
assert_contains "re-export: the snapshot carries the applied change" "Four weeks, set by the venture lead." "$snap"

out="$("$CYCLE" harvest "$v" 2>"$tmp/err")"
assert_contains "cycle 2 harvest: unresolved comments that stayed on the page are not new" "new	0" "$out"

# ---------------------------------------------------------------------------
# 7. A malformed pinned date stops the step before anything leaves or lands.
# ---------------------------------------------------------------------------
before="$(head_sha)"
calls="$(wc -l <"$tmp/log/argv" | tr -d ' ')"
PLANWRIGHT_INCEPTION_TODAY=bogus "$CYCLE" export --confirmed "$v" >/dev/null 2>"$tmp/err"
assert_eq "bad pinned date: export refused" "2" "$?"
assert_eq "bad pinned date: no API call" "$calls" "$(wc -l <"$tmp/log/argv" | tr -d ' ')"
assert_eq "bad pinned date: no commit" "$before" "$(head_sha)"

# fresh_venture <dir> — a second venture, exported and harvested, its three
# items pending.
fresh_venture() {
  inception_fixture_write "$1" || return 1
  git -C "$1" init -q . && git -C "$1" add -A && git -C "$1" commit -qm "chore: seed the venture" || return 1
  "$NOTION" configure --page "$PAGE" "$1" >/dev/null || return 1
  "$CYCLE" export --adapter notion --confirmed "$1" >/dev/null 2>&1 || return 1
  "$CYCLE" harvest "$1" >/dev/null 2>&1
}
# field_of <venture> <FB-id> <Field>
field_of() {
  awk -v id="$2" -v k="$3" '
    /^### / { cur = $2; next }
    cur == id && index($0, k ": ") == 1 { print substr($0, length(k) + 3); exit }' "$1/feedback/ledger.md"
}

# ---------------------------------------------------------------------------
# 8. A register entry named by its full heading is applied as triaged.
# ---------------------------------------------------------------------------
v2="$tmp/venture2"
fresh_venture "$v2" || exit 1
full="assumptions.md#A-2 — the three sinks accept writes from one surface"
"$CYCLE" triage FB-3 apply --decider "Robin Lead" --section "$full" "$v2" >/dev/null 2>"$tmp/err"
assert_eq "full heading: triage exit 0" "0" "$?"
assert_eq "full heading: recorded as given" "$full" "$(field_of "$v2" FB-3 Section)"
awk '/^### A-2 / { s = 1 } /^### A-3 / { s = 0 } s && /^- \*\*Risk-if-wrong:\*\*/ { print "- **Risk-if-wrong:** the fan-out needs a human relay at the failing sink"; next } { print }' "$v2/assumptions.md" >"$tmp/a" && cp "$tmp/a" "$v2/assumptions.md"
git -C "$v2" add assumptions.md
"$CYCLE" apply FB-3 "$v2" >/dev/null 2>"$tmp/err"
assert_eq "full heading: apply exit 0" "0" "$?"

# ---------------------------------------------------------------------------
# 9. A step whose commit fails leaves the committed ledger, and a step never
#    starts from an uncommitted one.
# ---------------------------------------------------------------------------
printf '#!/bin/sh\nexit 1\n' >"$v2/.git/hooks/pre-commit" && chmod +x "$v2/.git/hooks/pre-commit"
"$CYCLE" triage FB-2 skip --decider "Robin Lead" "$v2" >/dev/null 2>"$tmp/err"
assert_eq "failed triage commit: exit 2" "2" "$?"
assert_eq "failed triage commit: the ledger is restored" "" "$(git -C "$v2" status --porcelain)"
rm -f "$v2/.git/hooks/pre-commit"
"$CYCLE" triage FB-2 skip --decider "Robin Lead" "$v2" >/dev/null 2>"$tmp/err"
assert_eq "failed triage commit: a re-run records it" "0" "$?"

printf 'a hand edit\n' >>"$v2/feedback/ledger.md"
before="$(git -C "$v2" rev-parse HEAD)"
"$CYCLE" triage FB-1 skip --decider "Robin Lead" "$v2" >/dev/null 2>"$tmp/err"
assert_eq "uncommitted ledger: triage refused" "1" "$?"
assert_contains "uncommitted ledger: says so" "uncommitted" "$(cat "$tmp/err")"
assert_eq "uncommitted ledger: no commit" "$before" "$(git -C "$v2" rev-parse HEAD)"
git -C "$v2" checkout -q -- feedback/ledger.md

v3="$tmp/venture3"
inception_fixture_write "$v3" || exit 1
git -C "$v3" init -q . && git -C "$v3" add -A && git -C "$v3" commit -qm "chore: seed the venture" || exit 1
"$NOTION" configure --page "$PAGE" "$v3" >/dev/null || exit 1
"$CYCLE" export --adapter notion --confirmed "$v3" >/dev/null 2>&1 || exit 1
printf '#!/bin/sh\nexit 1\n' >"$v3/.git/hooks/pre-commit" && chmod +x "$v3/.git/hooks/pre-commit"
"$CYCLE" harvest "$v3" >/dev/null 2>"$tmp/err"
assert_eq "failed harvest commit: exit 2" "2" "$?"
assert_eq "failed harvest commit: the ledger is restored" "" "$(git -C "$v3" status --porcelain)"
rm -f "$v3/.git/hooks/pre-commit"
out="$("$CYCLE" harvest "$v3" 2>"$tmp/err")"
assert_contains "failed harvest commit: a re-run records the items" "new	3" "$out"

# ---------------------------------------------------------------------------
# 10. A pre-commit hook that stages files (as the venture hook stages its
#     regenerated exports) leaves the index matching each step's commit.
# ---------------------------------------------------------------------------
cat >"$v3/.git/hooks/pre-commit" <<'EOF'
#!/bin/sh
printf '%s\n' "$$" >hooked.txt
blob=$(git hash-object -w hooked.txt) && git update-index --add --cacheinfo "100644,$blob,hooked.txt"
EOF
chmod +x "$v3/.git/hooks/pre-commit"
"$CYCLE" triage FB-1 apply --decider "Robin Lead" --section "brief.md#Appetite" "$v3" >/dev/null 2>"$tmp/err"
assert_eq "staging hook: triage exit 0" "0" "$?"
assert_eq "staging hook: nothing left staged after triage" "" "$(git -C "$v3" diff --cached --name-only)"
awk -v f="$tmp/appetite" '/^_Skipped: appetite/ { while ((getline l < f) > 0) print l; next } { print }' "$v3/brief.md" >"$tmp/brief" && cp "$tmp/brief" "$v3/brief.md"
git -C "$v3" add brief.md
"$CYCLE" apply FB-1 "$v3" >/dev/null 2>"$tmp/err"
assert_eq "staging hook: apply exit 0" "0" "$?"
assert_eq "staging hook: nothing left staged after apply" "" "$(git -C "$v3" diff --cached --name-only)"
rm -f "$v3/.git/hooks/pre-commit"

# ---------------------------------------------------------------------------
# 11. A partial harvest does not open the next export (REQ-G1.6).
# ---------------------------------------------------------------------------
v4="$tmp/venture4"
inception_fixture_write "$v4" || exit 1
git -C "$v4" init -q . && git -C "$v4" add -A && git -C "$v4" commit -qm "chore: seed the venture" || exit 1
"$NOTION" configure --page "$PAGE" "$v4" >/dev/null || exit 1
"$CYCLE" export --adapter notion --confirmed "$v4" >/dev/null 2>&1 || exit 1
out="$(PLANWRIGHT_NOTION_MAX_BLOCKS=1 "$CYCLE" harvest "$v4" 2>"$tmp/err")"
assert_contains "partial harvest: reported" "walk	partial" "$out"
assert_contains "partial harvest: says the export waits" "next export waits" "$(cat "$tmp/err")"
assert_eq "partial harvest: still exported" "exported" "$(sed -n 's/^Phase: //p' "$v4/feedback/ledger.md")"
for id in FB-1 FB-2; do
  "$CYCLE" triage "$id" skip --decider "Robin Lead" "$v4" >/dev/null 2>&1
done
"$CYCLE" export --confirmed "$v4" >/dev/null 2>"$tmp/err"
assert_eq "partial harvest: the next export is refused" "1" "$?"
assert_contains "partial harvest: the refusal says why" "in full" "$(cat "$tmp/err")"
out="$("$CYCLE" harvest "$v4" 2>"$tmp/err")"
assert_contains "complete harvest: reads what the partial one missed" "new	1" "$out"
assert_eq "complete harvest: harvested" "harvested" "$(sed -n 's/^Phase: //p' "$v4/feedback/ledger.md")"

if [ "$failures" -ne 0 ]; then
  echo "$failures failure(s)" >&2
  exit 1
fi
echo "all inception-review-cycle tests passed"
