#!/bin/bash
# Tests for scripts/mc-rules.sh — the program's rule store: add, supersede
# and withdraw under one writer, the active set, the scoped render the
# launcher embeds, the bring-up load, the post-compaction self-check and the
# shared-subject report (mission-control REQ-B1.1, REQ-B1.2, REQ-B1.3,
# REQ-B1.4, REQ-B1.7).
#
# Runs standalone under /bin/bash (the bash 3.2 floor):
#   ./tests/test-mc-rules.sh
set -u
LC_ALL=C
export LC_ALL
unset CDPATH

here=$(cd "$(dirname "$0")" && pwd)
repo_root=$(cd "$here/.." && pwd)

failures=0
fail() {
  echo "FAIL: $1" >&2
  failures=$((failures + 1))
}
ok() { echo "ok: $1"; }

[ -f "$repo_root/scripts/mc-rules.sh" ] || {
  echo "FAIL: scripts/mc-rules.sh missing" >&2
  exit 1
}

tmp=$(mktemp -d) || exit 1
if [ -z "$tmp" ] || [ ! -d "$tmp" ]; then
  echo "FAIL: mktemp -d produced no usable directory" >&2
  exit 1
fi
trap 'rm -rf "$tmp"' EXIT
tmp=$(cd "$tmp" && pwd -P) || exit 1

# shellcheck source=tests/lib/mission-control-fixture.sh
. "$here/lib/mission-control-fixture.sh"

tab=$(printf '\t')
reset_mc_fixture
mkdir -p "$repo/specs"
home="$tmp/mc-home/alpha"
store="$home/rules.yaml"
cat >"$tracked" <<EOF
mission_control_programs: [alpha]
program_alpha_repositories: [$repo, $tmp/work/planwright, $tmp/work/other]
program_alpha_spec_root: $repo/specs
program_alpha_home: $home
EOF

rules() { mc_run mc-rules.sh "$@"; }

# field <line> <n>: the nth tab-separated field of a line.
field() { printf '%s\n' "$1" | cut -f "$2"; }
# run_reversal <undo line>: run the entry's reversal as its consumer would.
run_reversal() {
  rr=$(field "$1" 6)
  rr=${rr#mc-rules.sh }
  eval "set -- $rr"
  rules "$@"
}
# load_digest: the digest the last load's begin marker carried.
load_digest() { printf '%s\n' "$OUT" | sed -n 's/^<!-- mc-rules begin: .* digest \([0-9a-f]*\) -->$/\1/p'; }

# ---------------------------------------------------------------------------
# Before the first entry: an absent store reads as empty.
# ---------------------------------------------------------------------------
rules list alpha
expect_rc "list on an absent store succeeds" 0
expect_eq "list on an absent store prints nothing" ""
rules conflicts alpha
expect_rc "conflicts on an absent store succeeds" 0
rules render alpha
expect_rc "render on an absent store succeeds" 0
expect_out "an empty render says no rule is in force" "No standing rule is in force."
expect_out "a render with no scope is labelled all" "scope all, digest"
rules load alpha
expect_rc "the load of an absent store succeeds" 0
empty_digest=$(load_digest)
: >"$tmp/empty-held"
: >"$tmp/empty-durable"
rules selfcheck alpha --digest "$empty_digest" --held "$tmp/empty-held" --durable "$tmp/empty-durable"
expect_rc "a self-check of an empty program passes" 0
expect_out "the pass line counts nothing" "0 open items, 0 live sessions"

# ---------------------------------------------------------------------------
# REQ-B1.1: add requires text, subject, source and date.
# ---------------------------------------------------------------------------
rules add alpha --text "Never merge" --source "operator, turn" --date 2026-10-25
expect_rc "add without a subject is refused" 2
expect_err "the refusal names the subject" "subject"
if [ ! -e "$store" ]; then
  ok "a refused add writes no store"
else
  fail "a refused add wrote a store"
fi

rules add alpha --subject merging --source "operator" --date 2026-10-25
expect_rc "add without text is refused" 2
expect_err "the refusal names the text" "text"
rules add alpha --text "Never merge" --subject merging --date 2026-10-25
expect_rc "add without a source is refused" 2
expect_err "the refusal names the source" "source"
rules add alpha --text "Never merge" --subject merging --source operator
expect_rc "add without a date is refused" 2
expect_err "the refusal names the date" "date"
rules add alpha --text "Never merge" --subject merging --source operator --date 25/10/2026
expect_rc "a date not in YYYY-MM-DD is refused" 2
rules add alpha --text "Never merge" --subject merging --source operator --date 2026-19-39
expect_rc "an impossible month and day are refused" 2
rules add alpha --text "Never merge" --subject merging --source operator --date 2026-00-10
expect_rc "month zero is refused" 2
rules add alpha --text "Never merge" --subject merging --source operator --date 2026-02-30
expect_rc "a day past the end of its month is refused" 2
rules add alpha --text "Never merge" --subject merging --source operator --date 2026-02-29
expect_rc "February 29 outside a leap year is refused" 2
rules add alpha --text "Never merge" --subject merging --source operator --date 2026-04-31
expect_rc "the 31st of a 30-day month is refused" 2
rules add alpha --text "Never merge" --subject merging --source operator --date 2026-10-25 --scope duty:no-such-duty
expect_rc "a duty the program does not enable is refused" 2
expect_err "the refusal names the duty" "no-such-duty"
rules add alpha --text "Never merge" --subject merging --source operator --date 2026-10-25 --scope repo:elsewhere
expect_rc "a repository the program does not list is refused" 2
rules add alpha --text "$(printf '%2001s' x | tr ' ' y)" --subject merging --source operator --date 2026-10-25
expect_rc "text past its length is refused" 2
rules add alpha --text "   " --subject merging --source operator --date 2026-10-25
expect_rc "text of spaces alone is refused" 2
rules add alpha --text t --subject s --source o --date 2026-10-25 --withdraw
expect_rc "add takes no --withdraw" 2
rules add alpha --text "Never merge" --subject merging --source operator --date 2026-10-25 --scope repo:
expect_rc "a scope with an empty name is refused" 2
expect_err "the refusal names the scope" "scope"
rules add alpha --text "$(printf 'a\tb')" --subject merging --source operator --date 2026-10-25
expect_rc "a control character in the text is refused" 2
rules add alpha --text "$(printf 'a\302\233b')" --subject merging --source operator --date 2026-10-25
expect_rc "a C1 control in the text is refused" 2
rules add alpha --text "$(printf 'a\377b')" --subject merging --source operator --date 2026-10-25
expect_rc "text that is not UTF-8 is refused" 2
rules add nosuch --text t --subject s --source o --date 2026-10-25
expect_rc "an unconfigured program is refused" 3

# The direct-entry path: one entry at once, a one-line echo, an undo entry.
rules add alpha --text "Never merge a pull request" --subject merging --source "operator, mission-control turn" --date 2026-10-25
expect_rc "a complete add succeeds" 0
first=$(printf '%s\n' "$OUT" | sed -n 1p)
undo=$(printf '%s\n' "$OUT" | sed -n 2p)
if [ "$(printf '%s\n' "$OUT" | wc -l | tr -d ' ')" = 2 ]; then
  ok "add prints the echo line and the undo entry"
else
  fail "add printed other than two lines: $OUT"
fi
case $first in
  "rule r-1 added (program): merging: Never merge a pull request") ok "the echo names the id, scope, subject and text" ;;
  *) fail "unexpected echo: $first" ;;
esac
if [ "$(field "$undo" 1)" = undo ] && [ "$(field "$undo" 2)" = rule-add ] && [ "$(field "$undo" 3)" = merging ] && [ "$(field "$undo" 4)" = r-1 ]; then
  ok "the undo entry carries the act, subject and target"
else
  fail "unexpected undo entry: $undo"
fi
reversal=$(field "$undo" 6)
case $reversal in
  "mc-rules.sh supersede alpha r-1 --withdraw "*) ok "the reversal withdraws the added entry" ;;
  *) fail "unexpected reversal: $reversal" ;;
esac
if grep -qx 'format: 1' "$store"; then
  ok "the store carries its format field"
else
  fail "the store lacks 'format: 1'"
fi
perm=$(find "$home" -prune -perm 700)
if [ "$perm" = "$home" ]; then
  ok "the home is created private"
else
  fail "the home is not created mode 700"
fi
if [ "$(find "$store" -perm 600)" = "$store" ]; then
  ok "the store is written mode 600"
else
  fail "the store is not mode 600"
fi

rules list alpha
expect_rc "list reads the store" 0
line=$(printf '%s\n' "$OUT" | grep "^r-1$tab")
if [ "$(field "$line" 2)" = active ] && [ "$(field "$line" 3)" = 2026-10-25 ] && [ "$(field "$line" 4)" = program ] && [ "$(field "$line" 5)" = merging ] && [ "$(field "$line" 6)" = "Never merge a pull request" ] && [ "$(field "$line" 7)" = "operator, mission-control turn" ]; then
  ok "list shows the text, subject, source, date and scope"
else
  fail "unexpected list line: $line"
fi

# Quotes, backslashes and UTF-8 round-trip through the store.
tricky='Say "no" to C:\temp \\ and résumé'
today_before=$(date -u +%Y-%m-%d)
rules add alpha --text "$tricky" --subject 'quoting "test"' --source op --date today --scope repo:planwright
expect_rc "a value with quotes, backslashes and UTF-8 is stored" 0
rules active alpha
line=$(printf '%s\n' "$OUT" | grep "^r-2$tab")
if [ "$(field "$line" 6)" = "$tricky" ] && [ "$(field "$line" 5)" = 'quoting "test"' ]; then
  ok "quotes, backslashes and UTF-8 round-trip"
else
  fail "the round-trip changed the text: $line"
fi
today_after=$(date -u +%Y-%m-%d)
if [ "$(field "$line" 3)" = "$today_after" ] || [ "$(field "$line" 3)" = "$today_before" ]; then
  ok "--date today records the current date"
else
  fail "--date today recorded $(field "$line" 3)"
fi

# The reversal runs from the undo entry and leaves the entry in list only.
run_reversal "$undo"
expect_rc "the undo entry's reversal runs" 0
expect_out "the reversal echoes the withdrawal" "withdraws r-1"
rules active alpha
expect_rc "active reads the store after a withdrawal" 0
expect_no_out "a withdrawn entry leaves the active set" "Never merge a pull request"
expect_no_out "the withdrawal entry itself is never active" "r-3$tab"
rules load alpha
expect_no_out "the load carries no withdrawn subject" "**merging**"
rules list alpha
expect_out "a withdrawn entry stays in list" "r-1${tab}superseded"
expect_out "the withdrawal is listed" "r-3${tab}withdrawal"

# ---------------------------------------------------------------------------
# REQ-B1.2: supersession is explicit; a shared subject is reported.
# ---------------------------------------------------------------------------
rules add alpha --text "Rebase onto main daily" --subject syncing --source op --date 2026-10-25
old_id=r-4
rules supersede alpha r-4 --text "Merge main only on conflict" --source op --date 2026-10-26
expect_rc "supersede succeeds" 0
expect_out "the supersede echo names both ids" "rule r-5 supersedes r-4"
sup_undo=$(printf '%s\n' "$OUT" | sed -n 2p)
if [ "$(field "$sup_undo" 2)" = rule-supersede ]; then
  ok "a supersede carries an undo entry"
else
  fail "unexpected supersede undo entry: $sup_undo"
fi
rules active alpha
expect_no_out "the superseded entry leaves the active set" "Rebase onto main daily"
expect_out "the replacement is active" "Merge main only on conflict"
line=$(printf '%s\n' "$OUT" | grep "^r-5$tab")
if [ "$(field "$line" 5)" = syncing ] && [ "$(field "$line" 8)" = "$old_id" ]; then
  ok "the replacement inherits the subject and names what it supersedes"
else
  fail "unexpected replacement line: $line"
fi
rules list alpha
expect_out "the superseded entry stays in list" "r-4${tab}superseded"

rules supersede alpha r-4 --text "Again" --source op --date 2026-10-26
expect_rc "superseding an entry no longer active is refused" 1
expect_err "the refusal names the entry" "r-4"
rules supersede alpha r-99 --text "Again" --source op --date 2026-10-26
expect_rc "superseding an unknown entry is refused" 1
expect_err "the refusal names the unknown entry" "no entry r-99"
rules supersede alpha r-0 --text "Again" --source op --date 2026-10-26
expect_rc "a malformed id is a usage error" 2
rules supersede alpha r-1234567890 --text "Again" --source op --date 2026-10-26
expect_rc "an id past nine digits is refused" 2
rules supersede alpha r-5 --withdraw --subject x --source op --date 2026-10-26
expect_rc "--withdraw with --subject is a usage error" 2
rules supersede alpha r-5 --text "Again" --withdraw --source op --date 2026-10-26
expect_rc "--withdraw with --text is a usage error" 2

# The supersede's reversal restores the old text as a new active entry.
run_reversal "$sup_undo"
expect_rc "the supersede's reversal runs" 0
rules active alpha
expect_out "the reversal restores the superseded text" "Rebase onto main daily"
expect_no_out "the reversal retires the replacement" "Merge main only on conflict"

rules conflicts alpha
expect_rc "the report runs with no shared subject" 0
expect_eq "no shared subject, no report" ""

rules add alpha --text "Merge main weekly" --subject " Syncing " --source op --date 2026-10-27
rules add alpha --text "Docs need review" --subject docs --source op --date 2026-10-27
rules conflicts alpha
expect_rc "the report runs with a shared subject" 0
if [ "$(printf '%s\n' "$OUT" | wc -l | tr -d ' ')" = 1 ]; then
  ok "one shared subject, one report line"
else
  fail "unexpected report: $OUT"
fi
expect_out "two active entries sharing a subject are reported" "shared${tab}syncing${tab}r-6,r-7"
expect_no_out "different subjects are not reported" "docs"

# ---------------------------------------------------------------------------
# REQ-B1.4: render --scope emits only in-scope rules; a brief embeds it.
# ---------------------------------------------------------------------------
rules add alpha --text "Duty rule one" --subject d1 --source op --date 2026-10-27 --scope duty:inbox
rules add alpha --text "Other repo rule" --subject o1 --source op --date 2026-10-27 --scope repo:other
rules render alpha --scope repo:planwright
expect_rc "a scoped render succeeds" 0
expect_out "a scoped render is labelled with its scope" "scope repo:planwright, digest"
scoped_render=$OUT
expect_out "the render carries an in-scope repository rule" "$tricky"
expect_out "the render carries program rules" "Docs need review"
expect_no_out "the render leaves out another repository's rule" "Other repo rule"
expect_no_out "the render leaves out a duty's rule" "Duty rule one"
expect_no_out "the render leaves out superseded entries" "Merge main only on conflict"
rules render alpha --scope duty:inbox
expect_out "a duty render carries the duty's rule" "Duty rule one"
expect_no_out "a duty render leaves out a repository rule" "$tricky"
rules render alpha --scope duty:inbox --scope repo:other
expect_out "two scopes render both" "Duty rule one"
expect_out "two scopes render both (second)" "Other repo rule"
rules render alpha --scope bogus
expect_rc "an unknown scope kind is refused" 2

brief="$tmp/brief.md"
printf '%s\n' "# Fixture brief" "" "Do the task." "" >"$brief"
printf '%s\n' "$scoped_render" >>"$brief"
if grep -q '^<!-- mc-rules begin: program alpha' "$brief" && grep -q '^<!-- mc-rules end -->$' "$brief" && grep -qF -- "- **docs**: Docs need review (r-8, op, 2026-10-27, program)" "$brief"; then
  ok "a fixture brief contains the rendered rules between their markers"
else
  fail "the fixture brief lacks the rendered rules"
fi
if grep -qF -e "Other repo rule" -e "Duty rule one" "$brief"; then
  fail "the fixture brief carries another scope's rule"
else
  ok "the fixture brief carries no other scope's rule"
fi
rules render alpha --scope program
expect_out "a program-only render carries program rules" "Docs need review"
expect_no_out "a program-only render leaves out repository rules" "$tricky"

# ---------------------------------------------------------------------------
# REQ-B1.3 / REQ-B1.7: the bring-up load and the post-compaction self-check.
# ---------------------------------------------------------------------------
rules load alpha
expect_rc "the bring-up load succeeds" 0
expect_out "the load carries every scope" "Duty rule one"
expect_out "the load carries every scope (repository)" "Other repo rule"
digest=$(load_digest)
if [ "${#digest}" -eq 64 ]; then
  ok "the load's marker carries the active set's digest"
else
  fail "no digest in: $OUT"
fi

held="$tmp/held"
durable="$tmp/durable"
printf '%s\n' "item i0000aaaa" "session w-one" "session w-two" >"$durable"
printf '%s\n' "session w-two" "item i0000aaaa" "session w-one" >"$held"
rules selfcheck alpha --digest "$digest" --held "$held" --durable "$durable"
expect_rc "the self-check passes with rules, items and sessions held" 0
expect_out "a passing self-check says so" "self-check passed"

rules selfcheck alpha --digest 0000 --held "$held" --durable "$durable"
expect_rc "a self-check with a stale rule digest fails" 1
expect_out "a failed rule check raises an item" "item${tab}self-check${tab}rules"
printf '%s\n' "session w-one" "session w-two" >"$held"
rules selfcheck alpha --digest "$digest" --held "$held" --durable "$durable"
expect_rc "a self-check missing an open item fails" 1
expect_out "a missing open item raises an item" "item${tab}self-check${tab}items"
expect_out "the item names the missing open item" "i0000aaaa"
printf '%s\n' "item i0000aaaa" "session w-one" >"$held"
rules selfcheck alpha --digest "$digest" --held "$held" --durable "$durable"
expect_rc "a self-check missing a live session fails" 1
expect_out "a missing live session raises an item" "item${tab}self-check${tab}sessions"
expect_out "the item names the missing session" "w-two"
rules selfcheck alpha --digest "$digest" --held "$tmp/empty-held" --durable "$durable"
expect_rc "an empty held picture fails the self-check" 1
expect_out "an empty held picture misses the open items" "item${tab}self-check${tab}items"
expect_out "an empty held picture misses the live sessions" "item${tab}self-check${tab}sessions"
printf '%s\n' "item i0000aaaa" "session w-one" "session w-two" "bogus line" >"$held"
rules selfcheck alpha --digest "$digest" --held "$held" --durable "$durable"
expect_rc "a malformed held picture is refused" 1
expect_err "the refusal names the malformed line" "not an 'item <id>' or 'session <handle>' line"
expect_out "a refused self-check still raises an item" "item${tab}self-check${tab}run"
rules selfcheck alpha --digest "$digest" --held "$tmp/no-such-file" --durable "$durable"
expect_rc "a missing held file is refused" 1
expect_out "a missing held file raises an item" "item${tab}self-check"
rules selfcheck alpha --held "$held" --durable "$durable"
expect_rc "a self-check without a digest is a usage error" 2
expect_out "a self-check usage error raises an item" "item${tab}self-check"
# Relative to the runner's directory, where awk would read it as name=value.
cp "$held" "$repo/held=1"
mc_run mc-rules.sh selfcheck alpha --digest "$digest" --held 'held=1' --durable "$durable" </dev/null
expect_rc "a held file named like an awk assignment is read as a file" 1
expect_err "the held file named like an assignment is the one refused" "./held=1:4"
mc_run mc-rules.sh load
expect_rc "a load naming no program is a usage error" 2
expect_out "a load naming no program raises an item" "item${tab}rules-load"
rules load nosuch
expect_rc "the load of an unconfigured program fails" 3
expect_out "a load that cannot resolve its program raises an item" "item${tab}rules-load"

# A changed active set changes the digest.
rules add alpha --text "One more" --subject more --source op --date 2026-10-28
rules load alpha
d2=$(load_digest)
if [ -n "$d2" ] && [ "$d2" != "$digest" ]; then
  ok "a new rule changes the digest"
else
  fail "the digest did not change"
fi

# ---------------------------------------------------------------------------
# The format field: an unknown or missing format is refused, named.
# ---------------------------------------------------------------------------
cp "$store" "$tmp/store.bak"
sed 's/^format: 1$/format: 2/' "$tmp/store.bak" >"$store"
rules active alpha
expect_rc "a store with an unknown format is refused" 1
expect_err "the refusal names the format field" "format"
expect_err "the refusal names the unknown value" "'2'"
rules add alpha --text t --subject s --source o --date 2026-10-28
expect_rc "add refuses a store of an unknown format" 1
rules load alpha
expect_rc "the load fails on a store of an unknown format" 1
expect_out "a failed load raises an item" "item${tab}rules-load"
grep -v '^format:' "$tmp/store.bak" >"$store"
rules list alpha
expect_rc "a store with no format field is refused" 1
expect_err "the missing field is named" "format"
{
  cat "$tmp/store.bak"
  printf '%s\n' "    stray: value"
} >"$store"
rules list alpha
expect_rc "a store with a line outside the grammar is refused" 1
corrupt() { # corrupt <label> <needle> <awk program>
  awk "$3" "$tmp/store.bak" >"$store"
  rules list alpha
  expect_rc "$1 is refused" 1
  expect_err "the refusal of $1 names the defect" "$2"
}
# shellcheck disable=SC2016 # awk programs, expanded by awk
{
  corrupt "a duplicated id" "appears twice" '$0 == "  - id: r-2" { $0 = "  - id: r-1" } { print }'
  corrupt "a missing field" "lacks its source field" '$0 == "    source: \"op\"" && !done { done = 1; next } { print }'
  corrupt "an unknown escape" "unknown escape" '$0 == "    text: \"Docs need review\"" { $0 = "    text: \"Docs \\q review\"" } { print }'
  corrupt "a supersedes naming no earlier entry" "which no earlier entry is" '$0 == "    supersedes: r-1" { $0 = "    supersedes: r-99" } { print }'
  corrupt "a repeated field" "repeats its date field" '{ print } $0 == "    date: 2026-10-28" && !done { done = 1; print }'
  corrupt "an impossible date" "is not a YYYY-MM-DD date" '$0 == "    date: 2026-10-28" { $0 = "    date: 2026-13-28" } { print }'
  corrupt "a day past the end of its month" "is not a YYYY-MM-DD date" '$0 == "    date: 2026-10-28" { $0 = "    date: 2026-02-29" } { print }'
  corrupt "an id past nine digits" "is not a rule id" '$0 == "  - id: r-1" { $0 = "  - id: r-1234567890" } { print }'
  corrupt "a missing rules list" "expected the rules: list" '$0 == "rules:" { $0 = "entries:" } { print }'
}
# shellcheck disable=SC2016 # an awk program, expanded by awk
awk '$0 == "    date: 2026-10-28" { $0 = "    date: 2028-02-29" } { print }' "$tmp/store.bak" >"$store"
rules list alpha
expect_rc "a leap day in a leap year reads" 0
# entry <id> <supersedes> <withdrawn>: a hand-written store entry.
entry() {
  printf '%s\n' "  - id: $1" '    text: "Hand written"' '    subject: "hand"' '    source: "op"' \
    "    date: 2026-10-28" "    scope: program" "    supersedes: $2" "    withdrawn: $3"
}
{
  cat "$tmp/store.bak"
  entry r-90 r-1 false
} >"$store"
rules list alpha
expect_rc "a second replacement of one entry is refused" 1
expect_err "the refusal names the earlier supersession" "already superseded"
{
  cat "$tmp/store.bak"
  entry r-90 - false
  entry r-91 r-90 true
  entry r-92 r-91 false
} >"$store"
rules list alpha
expect_rc "an entry superseding a withdrawal is refused" 1
expect_err "the refusal names the withdrawal" "is a withdrawal"
printf '\001' | cat "$tmp/store.bak" - >"$store"
rules list alpha
expect_rc "a store carrying a control character is refused" 1
printf '\377\n' | cat "$tmp/store.bak" - >"$store"
rules list alpha
expect_rc "a store that is not UTF-8 is refused" 1
expect_err "the refusal says why" "not UTF-8"
: >"$store"
rules list alpha
expect_rc "an empty store file is refused" 1
expect_err "the empty store's refusal names the format field" "format"
rules load alpha
expect_out "the load of an empty store file raises an item" "item${tab}rules-load"
printf '\000' | cat "$tmp/store.bak" - >"$store"
rules list alpha
expect_rc "a store carrying a NUL is refused" 1
rm -f "$store"
ln -s "$tmp/store.bak" "$store"
rules list alpha
expect_rc "a store that is a symbolic link is refused" 1
rm -f "$store"

# A hand edit that leaves the last line unterminated still takes an add.
printf '%s' "$(cat "$tmp/store.bak")" >"$store"
rules add alpha --text "After a hand edit" --subject hand --source op --date 2026-10-28
expect_rc "an add to an unterminated store succeeds" 0
rules list alpha
expect_rc "the store an add wrote after a hand edit reads again" 0
expect_out "the added entry is listed" "After a hand edit"
cp "$tmp/store.bak" "$store"
rules list alpha
expect_rc "the restored store reads again" 0

# ---------------------------------------------------------------------------
# One writer under a lock: concurrent adds lose nothing.
# ---------------------------------------------------------------------------
before=$(grep -c '^  - id: ' "$store")
pids=""
i=0
while [ "$i" -lt 8 ]; do
  (rules add alpha --text "Concurrent $i" --subject "c$i" --source op --date 2026-10-28) &
  pids="$pids $!"
  i=$((i + 1))
done
for p in $pids; do wait "$p"; done
after=$(grep -c '^  - id: ' "$store")
if [ "$after" -eq $((before + 8)) ]; then
  ok "eight concurrent adds all land"
else
  fail "concurrent adds landed $((after - before)) of 8"
fi
dups=$(grep '^  - id: ' "$store" | sort | uniq -d)
if [ -z "$dups" ]; then
  ok "concurrent adds take distinct ids"
else
  fail "duplicate ids: $dups"
fi

# Two writers superseding one entry: exactly one wins.
rules add alpha --text "Race target" --subject race --source op --date 2026-10-28
race_id=$(printf '%s\n' "$OUT" | sed -n 's/^rule \(r-[0-9]*\) added.*/\1/p')
pids=""
i=0
while [ "$i" -lt 4 ]; do
  (rules supersede alpha "$race_id" --text "Race winner $i" --source op --date 2026-10-28) &
  pids="$pids $!"
  i=$((i + 1))
done
for p in $pids; do wait "$p"; done
if [ "$(grep -c "^    supersedes: $race_id\$" "$store")" -eq 1 ]; then
  ok "concurrent supersedes of one entry land exactly one replacement"
else
  fail "concurrent supersedes landed $(grep -c "^    supersedes: $race_id\$" "$store") replacements"
fi

# ---------------------------------------------------------------------------
# Supersede inherits or overrides subject and scope; every undo restores.
# ---------------------------------------------------------------------------
rules add alpha --text "Repo scoped rule" --subject inherit --source op --date 2026-10-28 --scope repo:planwright
inh_id=$(printf '%s\n' "$OUT" | sed -n 's/^rule \(r-[0-9]*\) added.*/\1/p')
rules supersede alpha "$inh_id" --text "Repo scoped rule, revised" --source op --date 2026-10-28
inh_new=$(printf '%s\n' "$OUT" | sed -n 's/^rule \(r-[0-9]*\) supersedes.*/\1/p')
rules active alpha
line=$(printf '%s\n' "$OUT" | grep "^$inh_new$tab")
if [ "$(field "$line" 4)" = repo:planwright ] && [ "$(field "$line" 5)" = inherit ]; then
  ok "a replacement inherits the scope and subject"
else
  fail "unexpected inherited line: $line"
fi
quoted="It's \$(touch $tmp/injected) and \`id\`"
rules supersede alpha "$inh_new" --text "$quoted" --subject moved --scope duty:inbox --source op --date 2026-10-28
expect_rc "a supersede may override subject and scope" 0
ovr_undo=$(printf '%s\n' "$OUT" | sed -n 2p)
rules active alpha
line=$(printf '%s\n' "$OUT" | grep "^r-[0-9]*${tab}active${tab}[^$tab]*${tab}duty:inbox${tab}moved$tab")
if [ "$(field "$line" 6)" = "$quoted" ]; then
  ok "the override and a text with quotes and substitutions are stored"
else
  fail "unexpected override line: $line"
fi
run_reversal "$ovr_undo"
expect_rc "the override's reversal runs" 0
rules active alpha
line=$(printf '%s\n' "$OUT" | grep "${tab}Repo scoped rule, revised$tab")
if [ "$(field "$line" 4)" = repo:planwright ] && [ "$(field "$line" 5)" = inherit ]; then
  ok "the reversal restores the old subject and scope"
else
  fail "the reversal did not restore subject and scope: $line"
fi
rules supersede alpha "$(field "$line" 1)" --text "$quoted" --source op --date 2026-10-28
q_undo=$(printf '%s\n' "$OUT" | sed -n 2p)
q_id=$(field "$q_undo" 4)
rules supersede alpha "$q_id" --withdraw --source op --date 2026-10-28
expect_rc "a withdrawal succeeds" 0
wd_undo=$(printf '%s\n' "$OUT" | sed -n 2p)
if [ "$(field "$wd_undo" 2)" = rule-withdraw ]; then
  ok "a withdrawal carries an undo entry"
else
  fail "unexpected withdrawal undo entry: $wd_undo"
fi
run_reversal "$wd_undo"
expect_rc "the withdrawal's reversal runs" 0
rules active alpha
line=$(printf '%s\n' "$OUT" | grep "${tab}inherit${tab}")
if [ "$(field "$line" 6)" = "$quoted" ] && [ "$(field "$line" 4)" = repo:planwright ]; then
  ok "the withdrawal's reversal restores the text quoted for the shell"
else
  fail "the withdrawal's reversal restored: $line"
fi
if [ ! -e "$tmp/injected" ]; then
  ok "no reversal ran a substitution from the text"
else
  fail "a reversal ran a substitution from the text"
fi

# A reversal recorded under an earlier configuration still runs.
rules add alpha --text "Inbox rule" --subject inbox-rule --source op --date 2026-10-28 --scope duty:inbox
ib_id=$(printf '%s\n' "$OUT" | sed -n 's/^rule \(r-[0-9]*\) added.*/\1/p')
rules supersede alpha "$ib_id" --text "Inbox rule, revised" --source op --date 2026-10-28
ib_undo=$(printf '%s\n' "$OUT" | sed -n 2p)
cp "$tracked" "$tmp/tracked.bak"
printf '%s\n' "program_alpha_duties: [session-keeper]" >>"$tracked"
run_reversal "$ib_undo"
expect_rc "a reversal still runs after the duty is disabled" 0
cp "$tmp/tracked.bak" "$tracked"

# Two repositories sharing a last path component leave repo:<name> unable to
# say which one it means.
sed "s|^program_alpha_repositories: .*|program_alpha_repositories: [$repo, $tmp/work/twin, $tmp/fork/twin]|" \
  "$tmp/tracked.bak" >"$tracked"
rules add alpha --text "Forked" --subject forked --source op --date 2026-10-28 --scope repo:twin
expect_rc "a repository name two repositories end in is refused" 2
expect_err "the refusal says the name is ambiguous" "is ambiguous"
cp "$tmp/tracked.bak" "$tracked"

rules bogus alpha
expect_rc "an unknown verb is a usage error" 2

if [ "$failures" -ne 0 ]; then
  echo "test-mc-rules: $failures failure(s)" >&2
  exit 1
fi
echo "test-mc-rules: all passed"
