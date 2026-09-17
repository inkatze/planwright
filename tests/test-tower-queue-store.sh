#!/bin/bash
# Tests for scripts/tower-queue.sh's queue store — the `add`, `list`,
# `counts`, `settle` and `shelve` verbs, the record grammar and the
# hostile-input table (REQ-A1.2, REQ-A1.3, REQ-A1.6, REQ-C1.5, REQ-C1.9,
# REQ-H1.3, REQ-H1.4). Attention, the lease and `ack` are in
# test-tower-queue-next.sh; the lock, concurrency, the surface and the
# rebuild are in test-tower-queue-store-lock.sh.
#
# Contract under test:
#   add --kind <kind> --origin <who> --closes <text>
#       (--worker <handle> [--root <dir> --park <rel>] | --root <dir> --pointer <rel> [--park <rel>])
#       [--urgency high|normal|low] [--now <epoch>]
#       Register one item: content already at its home, the index record
#       written after it, the identifier derived from the content home's key;
#       a question inherits its row's urgency and refuses --urgency.
#   list [--all]     every open item, lock-free; --all adds the retained
#                    closed ones.
#   counts           open count per kind, the total, and the top item's kind.
#   settle <id> --reason <text>   close an item on evidence, naming it.
#   shelve <id> [--for <span>]    park an item; it returns on its own.
#   Exit codes: 0 done; 1 a semantic refusal; 2 usage / refused input;
#       3 the bounded lock wait expired; 4 the surface is not verifiably
#       owner-only or a knob is malformed; 6 an infrastructure failure.
#
# Runs standalone under /bin/bash (the bash 3.2 floor).
set -eu
LC_ALL=C
export LC_ALL
unset CDPATH

here=$(cd "$(dirname "$0")" && pwd)
TQ="$here/../scripts/tower-queue.sh"
FS="$here/../scripts/fleet-state.sh"

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

[ -x "$TQ" ] || fail "scripts/tower-queue.sh missing or not executable"
[ -x "$FS" ] || fail "scripts/fleet-state.sh missing or not executable"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

home="$tmp/fleet-home"
mkdir -p "$home"
chmod 0700 "$home"
adopter="$tmp/adopter"
mkdir -p "$adopter"
local_cfg="$tmp/local.yml"
: >"$local_cfg"

surface="$home/tower-comms"
store="$surface/queue"
log_file="$surface/events.log"
attn_dir="$home/attention"
attn_store="$attn_dir/state"
content="$tmp/content"
mkdir -p "$content"

TAB=$(printf '\t')

run() {
  PLANWRIGHT_FLEET_STATE_DIR="$home" \
    PLANWRIGHT_ADOPTER_OVERLAY="$adopter" \
    PLANWRIGHT_REPO_ROOT="$tmp" \
    PLANWRIGHT_LOCAL_CONFIG="$local_cfg" \
    /bin/sh "$TQ" "$@"
}

# attention_row <worker> <scope> <state> <ts> <prio> <q> <def> <opts> [<reason> [<iid>]]
# — append one row in fleet-attention.sh's shipped layout (8 fields, +9 for
# a park reason, +10 for a fork instance id).
attention_row() {
  mkdir -p "$attn_dir"
  chmod 0700 "$attn_dir"
  if [ "$#" -ge 10 ]; then
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$4" "$5" "$6" "$7" "$8" "$9" "${10}" >>"$attn_store"
  elif [ "$#" -ge 9 ]; then
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$4" "$5" "$6" "$7" "$8" "$9" >>"$attn_store"
  else
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$4" "$5" "$6" "$7" "$8" >>"$attn_store"
  fi
}

# marker <tower> <epoch> — the per-tower attention marker the prompt-submit
# hook writes (REQ-C1.10), planted by hand here.
marker() {
  mkdir -p "$surface/attention"
  chmod 0700 "$surface/attention"
  printf '%s\n' "$2" >"$surface/attention/$1"
  chmod 0600 "$surface/attention/$1"
}

record_count() {
  if [ -f "$store" ]; then
    grep -c . "$store" || true
  else
    printf '0'
  fi
}

field() { # field <line> <n>
  printf '%s\n' "$1" | cut -f "$2"
}

# --- static guards ----------------------------------------------------------

grep -q 'jq' "$TQ" && fail "the script mentions jq (REQ-G1.7)"
if grep -E -q '(^|[^a-z-])claude( |$|")' "$TQ"; then
  fail "the script invokes the CLI binary (REQ-H1.4: no model invocation)"
fi
echo "ok: no jq and no model invocation in the script"

# --- usage ------------------------------------------------------------------

rc=0
run add >/dev/null 2>&1 || rc=$?
[ "$rc" = 2 ] || fail "add with no args: exit $rc, expected 2"
[ ! -e "$store" ] || fail "add with no args created a store"
echo "ok: add with no args refused"

# --- the five kinds, each with a closing condition (REQ-A1.2) -----------------

attention_row w-alpha spec-a/task-1 awaiting-input 1000 high 'Merge or rebase?' merge 'merge|rebase' fork iid-1
attention_row w-beta spec-a/task-2 awaiting-input 1100 low 'Which base?' main 'main|dev' fork iid-2
attention_row w-gamma spec-b/task-3 pr-ready 1200 normal - - -

q1=$(run add --kind question --worker w-alpha --origin w-alpha --closes 'the operator answers' --now 2000) \
  || fail "add question: exit"
case "$q1" in
  i[0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f]) ;;
  *) fail "add question printed '$q1', not an identifier" ;;
esac
line=$(grep "^$q1$TAB" "$store") || fail "question record absent from the store"
[ "$(field "$line" 2)" = question ] || fail "question kind not stored"
[ "$(field "$line" 3)" = high ] || fail "a worker question did not inherit its row's priority (got '$(field "$line" 3)')"
[ "$(field "$line" 6)" = attention ] || fail "question home is not the attention store"
[ "$(field "$line" 7)" = w-alpha ] || fail "question pointer is not the worker's row"
[ "$(field "$line" 8)" = iid-1 ] || fail "question record does not carry the row's instance identifier"
echo "ok: a worker question inherits its row's priority and carries its instance id"

q2=$(run add --kind question --worker w-beta --origin w-beta --closes 'the operator answers' --now 2001) \
  || fail "add second question: exit"
[ "$q2" != "$q1" ] || fail "two questions from two rows share an identifier"
line=$(grep "^$q2$TAB" "$store")
[ "$(field "$line" 3)" = low ] || fail "second question did not inherit low"

n1=$(run add --kind news --worker w-gamma --origin w-gamma --closes 'the operator has read it' --now 2002) \
  || fail "add news: exit"
line=$(grep "^$n1$TAB" "$store")
[ "$(field "$line" 3)" = normal ] || fail "news urgency not inherited from the row"
[ "$(field "$line" 8)" = 'pr-ready.1200' ] || fail "news record does not carry the row's state and stamp as its instance (got '$(field "$line" 8)')"
echo "ok: news points at the attention row and pins its instance"

printf -- '- **Task 1** — parked\n' >"$content/park-1"
q1p=$(run add --kind question --worker w-alpha --origin w-alpha --closes 'the operator answers' --root "$content" --park park-1 --now 2002 2>/dev/null) \
  || fail "add question with a park pointer: exit"
[ "$q1p" = "$q1" ] || fail "a park pointer changed the question's identity ($q1p vs $q1): one awaiting-input row is one question"
echo "ok: a park pointer never mints a second item for the same row"

printf 'please rename the branch to something readable\n' >"$content/req-1"
r1=$(run add --kind request --root "$content" --pointer req-1 --origin operator --closes 'the branch is renamed' --now 2003) \
  || fail "add request: exit"
line=$(grep "^$r1$TAB" "$store")
[ "$(field "$line" 6)" = path ] || fail "request home is not path"
[ "$(field "$line" 7)" = req-1 ] || fail "request pointer is not the relative path"
[ "$(field "$line" 9)" = "$content" ] || fail "request root not stored canonically (got '$(field "$line" 9)')"
[ "$(field "$line" 3)" = normal ] || fail "request urgency did not default to normal"
echo "ok: a request points at a relative path under its declared root"

printf 'mark PR 12 ready\n' >"$content/appr-1"
a1=$(run add --kind approval --root "$content" --pointer appr-1 --origin tower --urgency high --closes 'the operator gives the go-ahead' --now 2004) \
  || fail "add approval: exit"
line=$(grep "^$a1$TAB" "$store")
[ "$(field "$line" 3)" = high ] || fail "approval urgency not stored"

printf 'second request\n' >"$content/req-2"
r2=$(run add --kind request --root "$content" --pointer req-2 --origin operator --closes 'the second branch is renamed' --now 2006) \
  || fail "add second request: exit"
printf 'always allow git fetch\n' >"$content/std-1"
s1=$(run add --kind standing --root "$content" --pointer std-1 --origin operator --now 2005) \
  || fail "add standing: exit"
line=$(grep "^$s1$TAB" "$store")
case "$(field "$line" 11)" in
  *revoke*) ;;
  *) fail "a standing decision's closing condition does not read as the operator's revocation: '$(field "$line" 11)'" ;;
esac
rc=0
run add --kind standing --root "$content" --pointer std-1 --origin operator --closes 'the worker finishes' >/dev/null 2>&1 || rc=$?
[ "$rc" = 2 ] || fail "standing with a non-revocation closing condition: exit $rc, expected 2"
echo "ok: a standing decision closes on the operator's revocation"

[ "$(record_count)" = 7 ] || fail "expected 7 records, found $(record_count)"

# Every line is a 20-field record.
while IFS= read -r l; do
  nf=$(printf '%s\n' "$l" | awk -F '\t' '{ print NF }')
  [ "$nf" = 20 ] || fail "a store line has $nf fields, expected 20: $l"
done <"$store"
echo "ok: every record has the declared field count"

# --- content in its home, delivery state in the store (REQ-A1.3) ---------------

grep -q 'rename the branch' "$store" && fail "the store carries request content text"
grep -q 'Merge or rebase' "$store" && fail "the store carries a worker question's text"
echo "ok: the store holds pointers and delivery state, no content"

rc=0
run add --kind request --root "$content" --pointer req-missing --origin operator --closes 'done' >/dev/null 2>&1 || rc=$?
[ "$rc" = 2 ] || fail "a pointer at absent content: exit $rc, expected 2 (content is written before the index record)"
echo "ok: an index record is refused before its content exists"

rc=0
run add --kind question --worker w-nobody --origin w-nobody --closes 'answered' >/dev/null 2>&1 || rc=$?
[ "$rc" = 2 ] || fail "a question with no attention row: exit $rc, expected 2"
rc=0
run add --kind question --worker w-gamma --origin w-gamma --closes 'answered' >/dev/null 2>&1 || rc=$?
[ "$rc" = 2 ] || fail "a question on a row that is not awaiting input: exit $rc, expected 2"
echo "ok: a worker question needs an awaiting-input row"

# --- the born event ------------------------------------------------------------

[ -f "$log_file" ] || fail "no event log after adds"
born=$(grep -c '"kind":"born"' "$log_file" || true)
[ "$born" = 7 ] || fail "expected 7 born lines, found $born"
grep -q "\"item\":\"$q1\",\"item_kind\":\"question\"" "$log_file" || fail "the born line does not carry item and item_kind"
grep -q "\"item\":\"$r1\"" "$log_file" || fail "the request's born line is missing"
grep -q '"pointer":"req-1"' "$log_file" || fail "the born line does not carry the pointer"
echo "ok: every add logs one born line naming the item and its kind"

# --- idempotent add ------------------------------------------------------------

again=$(run add --kind request --root "$content" --pointer req-1 --origin operator --closes 'the branch is renamed' --now 2010 2>"$tmp/err") \
  || fail "re-adding the same content: exit"
[ "$again" = "$r1" ] || fail "re-adding the same content minted a new identifier ($again vs $r1)"
[ "$(record_count)" = 7 ] || fail "re-adding the same content duplicated the record"
grep -q 'already' "$tmp/err" || fail "re-adding the same content did not say so"
echo "ok: an identifier is derived from the content home's key, so a re-add is a no-op"

# --- refusals: kinds, urgency, closing condition --------------------------------

rc=0
run add --kind rumour --root "$content" --pointer req-1 --origin operator --closes x >/dev/null 2>&1 || rc=$?
[ "$rc" = 2 ] || fail "unknown kind: exit $rc, expected 2"
rc=0
run add --kind request --root "$content" --pointer req-1 --origin operator --urgency urgent --closes x >/dev/null 2>&1 || rc=$?
[ "$rc" = 2 ] || fail "urgency outside high/normal/low: exit $rc, expected 2"
rc=0
run add --kind question --worker w-alpha --origin w-alpha --urgency low --closes x >/dev/null 2>&1 || rc=$?
[ "$rc" = 2 ] || fail "an explicit urgency on a worker question (which inherits): exit $rc, expected 2"
rc=0
run add --kind request --root "$content" --pointer req-1 --origin operator >/dev/null 2>&1 || rc=$?
[ "$rc" = 2 ] || fail "no closing condition: exit $rc, expected 2"
rc=0
run add --kind request --root "$content" --pointer req-1 --origin operator --closes 'the branch is renamed automatically on merge' >/dev/null 2>&1 || rc=$?
[ "$rc" = 2 ] || fail "a closing condition promising an automatic step: exit $rc, expected 2"
rc=0
run add --kind request --root "$content" --pointer req-1 --origin operator --closes 'closes on its own after the next sweep' >/dev/null 2>&1 || rc=$?
[ "$rc" = 2 ] || fail "a closing condition promising a future automatic step: exit $rc, expected 2"
[ "$(record_count)" = 7 ] || fail "a refused add wrote a record"
echo "ok: unknown kinds, out-of-scale urgency, and promised automatic steps are refused"

# --- the hostile-input table (REQ-A1.6, REQ-H1.3) -------------------------------

before=$(record_count)
hostile() { # hostile <label> <args...>
  h_label=$1
  shift
  rc=0
  run "$@" >"$tmp/out" 2>"$tmp/err" || rc=$?
  [ "$rc" = 2 ] || fail "hostile input ($h_label): exit $rc, expected 2"
  [ -s "$tmp/err" ] || fail "hostile input ($h_label): refused silently"
  if tr -d '\t' <"$tmp/err" | LC_ALL=C grep -q '[[:cntrl:]]'; then
    fail "hostile input ($h_label): a control byte reached stderr"
  fi
  [ "$(record_count)" = "$before" ] || fail "hostile input ($h_label): a record was written"
}
hostile 'control byte in closes' add --kind request --root "$content" --pointer req-1 --origin operator --closes "$(printf 'done\033[31m')"
hostile 'embedded newline in closes' add --kind request --root "$content" --pointer req-1 --origin operator --closes "$(printf 'done\nrm -rf')"
hostile 'embedded tab in closes' add --kind request --root "$content" --pointer req-1 --origin operator --closes "$(printf 'done\there')"
hostile 'leading whitespace' add --kind request --root "$content" --pointer req-1 --origin operator --closes ' done'
hostile 'JSON-shaped closes (the log refuses it)' add --kind request --root "$content" --pointer req-1 --origin operator --closes '{the operator answers}'
hostile 'C1 control byte' add --kind request --root "$content" --pointer req-1 --origin operator --closes "$(printf 'done\233here')"
long=$(awk 'BEGIN { while (length(s) < 600) s = s "x"; print s }')
hostile 'over-long closes' add --kind request --root "$content" --pointer req-1 --origin operator --closes "$long"
hostile 'traversal pointer' add --kind request --root "$content" --pointer '../req-1' --origin operator --closes 'done'
hostile 'inner traversal pointer' add --kind request --root "$content" --pointer 'a/../../req-1' --origin operator --closes 'done'
hostile 'absolute pointer' add --kind request --root "$content" --pointer "$content/req-1" --origin operator --closes 'done'
hostile 'pointer with a tab' add --kind request --root "$content" --pointer "$(printf 'req\t1')" --origin operator --closes 'done'
mkdir -p "$content/sub"
ln -s "$tmp/local.yml" "$content/sub/escape"
hostile 'symlink escaping the root' add --kind request --root "$content" --pointer sub/escape --origin operator --closes 'done'
mkdir -p "$tmp/outside"
ln -s "$tmp/outside" "$content/dirlink"
printf 'x\n' >"$tmp/outside/req-x"
hostile 'directory symlink escaping the root' add --kind request --root "$content" --pointer dirlink/req-x --origin operator --closes 'done'
hostile 'traversal worker handle' add --kind question --worker '../w-alpha' --origin w-alpha --closes answered
hostile 'origin with a space' add --kind request --root "$content" --pointer req-1 --origin 'the operator' --closes 'done'
hostile 'origin with a control byte' add --kind request --root "$content" --pointer req-1 --origin "$(printf 'op\001')" --closes 'done'
hostile 'over-long origin' add --kind request --root "$content" --pointer req-1 --origin "$long" --closes 'done'
hostile 'malformed --now' add --kind request --root "$content" --pointer req-1 --origin operator --closes 'done' --now 0012
hostile 'traversal park pointer' add --kind question --worker w-alpha --origin w-alpha --closes answered --park '../x'
hostile 'backslash in a worker handle (awk -v would re-read it)' add --kind question --worker 'w-alph\141' --origin w-alpha --closes answered
hostile 'shell metacharacter in an origin' add --kind request --root "$content" --pointer req-1 --origin 'op;id' --closes 'done'
hostile '--root with no --park on a question' add --kind question --worker w-alpha --origin w-alpha --closes answered --root "$content"
hostile 'the absent-owner sentinel as a tower' next --tower unknown-owner
echo "ok: the hostile-input table is refused at add, each with a message and no record"

rc=0
run settle '../x' --reason evidence >/dev/null 2>"$tmp/err" || rc=$?
[ "$rc" = 2 ] || fail "hostile item id at settle: exit $rc, expected 2"
rc=0
run shelve "$(printf 'i\001')" >/dev/null 2>"$tmp/err" || rc=$?
[ "$rc" = 2 ] || fail "hostile item id at shelve: exit $rc, expected 2"
rc=0
run settle "$r1" --reason "$(printf 'merged\033')" >/dev/null 2>"$tmp/err" || rc=$?
[ "$rc" = 2 ] || fail "control byte in a settle reason: exit $rc, expected 2"
echo "ok: the hostile-input table is refused at settle and shelve"

# --- list and counts (REQ-C1.9) --------------------------------------------------

listed=$(run list) || fail "list: exit"
[ "$(printf '%s\n' "$listed" | grep -c .)" = 7 ] || fail "list printed $(printf '%s\n' "$listed" | grep -c .) items, expected 7"
printf '%s\n' "$listed" | grep -q "^$s1$TAB" || fail "list omits the standing decision (it is open)"
echo "ok: list prints every open item"

counts=$(run counts) || fail "counts: exit"
[ "$(printf '%s\n' "$counts" | awk -F '\t' '$1 == "question" { print $2 }')" = 2 ] || fail "counts: question count wrong: $counts"
[ "$(printf '%s\n' "$counts" | awk -F '\t' '$1 == "approval" { print $2 }')" = 1 ] || fail "counts: approval count wrong"
[ "$(printf '%s\n' "$counts" | awk -F '\t' '$1 == "request" { print $2 }')" = 2 ] || fail "counts: request count wrong"
[ "$(printf '%s\n' "$counts" | awk -F '\t' '$1 == "news" { print $2 }')" = 1 ] || fail "counts: news count wrong"
[ "$(printf '%s\n' "$counts" | awk -F '\t' '$1 == "standing" { print $2 }')" = 1 ] || fail "counts: standing count wrong"
[ "$(printf '%s\n' "$counts" | awk -F '\t' '$1 == "total" { print $2 }')" = 6 ] || fail "counts: the total counts the ranked kinds only: $counts"
[ "$(printf '%s\n' "$counts" | awk -F '\t' '$1 == "store" { print $2 }')" = present ] || fail "counts: no store row"
[ "$(printf '%s\n' "$counts" | awk -F '\t' '$1 == "malformed" { print $2 }')" = 0 ] || fail "counts: malformed row wrong"
[ "$(printf '%s\n' "$counts" | awk -F '\t' '$1 == "top" { print $2 }')" = question ] || fail "counts: top kind is not question: $counts"
echo "ok: counts prints the open count per kind and the top item's kind"

# --- ordering by consequence (REQ-C1.5) -----------------------------------------

# Attention confirmed: knock, then a reply later than the knock, then each
# delivery followed by a reply later than it. The fixture's clock spans more
# than the default lease backstop, and a delivered item whose lease lapsed is
# deliverable again by design, so the lease is stretched for this section.
printf 'tower_quiet_interval: 2h\ntower_lease_interval: 2h\n' >"$local_cfg"
tower='tower-order'
run next --tower "$tower" --now 3000 >"$tmp/out" || fail "first next: exit"
grep -q '^knock' "$tmp/out" || fail "first next did not knock: $(cat "$tmp/out")"
order=""
t=3001
i=0
while [ "$i" -lt 7 ]; do
  marker "$tower" "$t"
  t=$((t + 1))
  out=$(run next --tower "$tower" --now "$t") || fail "next #$i: exit"
  t=$((t + 1))
  case "$out" in
    "") break ;;
    item*) ;;
    *) fail "next printed something other than one item: $out" ;;
  esac
  [ "$(printf '%s\n' "$out" | grep -c .)" = 1 ] || fail "next printed more than one line"
  order="$order $(field "$out" 3):$(field "$out" 2)"
  i=$((i + 1))
done
[ "$order" = " question:$q1 question:$q2 approval:$a1 request:$r1 request:$r2 news:$n1" ] \
  || fail "ordering by consequence, urgency, then age is wrong:$order"
echo "ok: next orders blocked workers, approvals, requests, then news, by urgency then age"

# --- settle closes with a reason; list drops it; counts follow -------------------

run settle "$r1" --reason 'branch renamed: commit on main' --now 4000 >/dev/null || fail "settle: exit"
line=$(grep "^$r1$TAB" "$store")
[ "$(field "$line" 12)" = closed ] || fail "settled record is not closed"
[ "$(field "$line" 17)" = 4000 ] || fail "settled stamp missing"
[ "$(field "$line" 18)" = 'branch renamed: commit on main' ] || fail "settled record does not name what settled it"
[ "$(field "$line" 19)" = - ] || fail "settling did not release the lease"
run list | grep -q "^$r1$TAB" && fail "list prints a settled item"
run list --all | grep "^$r1$TAB" | grep -q "${TAB}closed${TAB}" || fail "list --all does not show the settled item as closed"
grep -q "\"kind\":\"settled\".*\"item\":\"$r1\"" "$log_file" || fail "no settled event logged"
rc=0
run settle "$r1" --reason again --now 4001 >/dev/null 2>"$tmp/err" || rc=$?
[ "$rc" = 0 ] || fail "settling a closed item: exit $rc, expected 0 (a logged no-op)"
rc=0
run settle inope0000 --reason x --now 4002 >/dev/null 2>&1 || rc=$?
[ "$rc" = 2 ] || fail "settling an unknown item: exit $rc, expected 2"
echo "ok: settle closes an item naming what settled it; list never prints a settled one"

born_before=$(grep -c '"kind":"born"' "$log_file")
again=$(run add --kind request --root "$content" --pointer req-1 --origin operator --closes 'the branch is renamed' --now 4003) \
  || fail "re-adding settled content: exit"
[ "$again" = "$r1" ] || fail "re-adding settled content minted a new id ($again vs $r1)"
line=$(grep "^$r1$TAB" "$store")
[ "$(field "$line" 12)" = open ] || fail "re-adding settled content did not re-open the item"
[ "$(field "$line" 5)" = 4003 ] || fail "a re-opened item did not get a fresh birth stamp"
[ "$(field "$line" 18)" = - ] || fail "a re-opened item kept its old settling reason"
[ "$(grep -c '"kind":"born"' "$log_file")" = $((born_before + 1)) ] || fail "a re-opened item was not born again in the log"
run settle "$r1" --reason 'renamed again' --now 4004 >/dev/null || fail "settle r1 again"
echo "ok: content queued again after its item closed re-opens the same item"

# --- shelve parks with a bounded return (REQ-C1.6) --------------------------------

run shelve "$a1" --tower "$tower" --for 30s --now 4100 >/dev/null || fail "shelve: exit"
line=$(grep "^$a1$TAB" "$store")
[ "$(field "$line" 16)" = 4130 ] || fail "shelve did not record the return time (got '$(field "$line" 16)')"
[ "$(field "$line" 12)" = open ] || fail "a shelved item is not open"
[ "$(field "$line" 19)" = - ] || fail "shelving did not release the lease"
run list | grep -q "^$a1$TAB" || fail "list omits a shelved item (it is open, not dropped)"
grep -q "\"kind\":\"shelved\".*\"item\":\"$a1\"" "$log_file" || fail "no shelved event logged"
marker "$tower" 4110
out=$(run next --tower "$tower" --now 4111) || fail "next while shelved: exit"
case "$out" in
  *"$a1"*) fail "a shelved item was handed over before its return time" ;;
esac
marker "$tower" 4140
out=$(run next --tower "$tower" --now 4141) || fail "next after return: exit"
case "$out" in
  *"$a1"*) ;;
  *) fail "a shelved item did not return after its span: '$out'" ;;
esac
echo "ok: a shelved item returns on its own and is never dropped"

run shelve "$n1" --tower "$tower" --for 500ms --now 4160 >/dev/null || fail "sub-second shelve: exit"
[ "$(grep "^$n1$TAB" "$store" | cut -f 16)" = 4161 ] || fail "a sub-second shelve did not park the item (return $(grep "^$n1$TAB" "$store" | cut -f 16))"
counts=$(run counts --now 4160) || fail "counts with a shelved item"
[ "$(printf '%s\n' "$counts" | awk -F '\t' '$1 == "news" { print $2 }')" = 0 ] || fail "counts still counts a shelved item as waiting: $counts"
# No --for: the shipped tower_shelve_return (1h) decides the return.
run shelve "$a1" --tower "$tower" --now 4162 >/dev/null || fail "shelve with no --for: exit"
[ "$(grep "^$a1$TAB" "$store" | cut -f 16)" = 7762 ] || fail "a shelve with no --for did not park for tower_shelve_return (return $(grep "^$a1$TAB" "$store" | cut -f 16), expected 7762)"
rc=0
run shelve "$a1" --for 0 >/dev/null 2>&1 || rc=$?
[ "$rc" = 2 ] || fail "shelve for a zero span: exit $rc, expected 2"
rc=0
run shelve "$r1" --for 1m --now 4150 >/dev/null 2>&1 || rc=$?
[ "$rc" = 0 ] || fail "shelving a closed item: exit $rc, expected 0 (a logged no-op)"

# --- retention keeps the open items plus a bounded settled set (REQ-A1.3) --------

printf 'tower_catchup_limit: 2\n' >"$local_cfg"
i=0
while [ "$i" -lt 4 ]; do
  printf 'req %s\n' "$i" >"$content/ret-$i"
  id=$(run add --kind request --root "$content" --pointer "ret-$i" --origin operator --closes 'done' --now $((5000 + i))) || fail "add ret-$i"
  run settle "$id" --reason "evidence $i" --now $((5100 + i)) >/dev/null || fail "settle ret-$i"
  i=$((i + 1))
done
closed=$(awk -F '\t' '$12 == "closed"' "$store" | grep -c . || true)
[ "$closed" = 2 ] || fail "retention kept $closed settled records, expected the 2 most recent"
awk -F '\t' '$12 == "closed" { print $18 }' "$store" | grep -q 'evidence 3' || fail "retention dropped the newest settled record"
awk -F '\t' '$12 == "closed" { print $18 }' "$store" | grep -q 'evidence 0' && fail "retention kept a settled record past the window"
open=$(awk -F '\t' '$12 == "open"' "$store" | grep -c . || true)
[ "$open" = 6 ] || fail "retention touched the open items ($open open, expected 6)"
printf 'tower_catchup_limit: 501\n' >"$local_cfg"
rc=0
run counts --now 5200 >/dev/null 2>&1 || rc=$?
[ "$rc" = 0 ] || fail "counts should not resolve the retention knob"
run settle i00000001 --reason x --now 5200 >/dev/null 2>"$tmp/err" || rc=$?
[ "$rc" = 4 ] || fail "a catch-up limit above the cap: exit $rc, expected 4"
: >"$local_cfg"
echo "ok: retention keeps every open item and only the settled ones inside the catch-up window"

# --- secrets are redacted before the shape check (REQ-G1.8) --------------------------

# A value that is only a secret redacts to a bracketed marker, the one shape
# the log refuses: it must be refused up front, never stored without a birth.
# The literal is split so the source never carries the key shape itself.
secret=AKIA""ABCDEFGHIJKLMNOP
before=$(record_count)
rc=0
run add --kind request --root "$content" --pointer req-1 --origin operator --closes "$secret" --now 5210 >/dev/null 2>"$tmp/err" || rc=$?
[ "$rc" = 2 ] || fail "a closing condition that is only a secret: exit $rc, expected 2"
[ "$(record_count)" = "$before" ] || fail "a secret-only closing condition wrote a record"
grep -q 'did not reach the event log' "$tmp/err" && fail "a secret-only closing condition reached the store before the log refused it"
printf 'request sec\n' >"$content/req-sec"
sid=$(run add --kind request --root "$content" --pointer req-sec --origin operator --closes "rotate $secret then confirm" --now 5211 2>/dev/null) \
  || fail "a closing condition with an embedded secret: refused"
[ "$(field "$(grep "^$sid$TAB" "$store")" 11)" = 'rotate [redacted:aws-access-key-id] then confirm' ] || fail "the store carries the secret or lost the text around it"
grep -q "\"kind\":\"born\".*\"item\":\"$sid\"" "$log_file" || fail "the born line for a redacted closing condition never landed"
rc=0
run settle "$sid" --reason "$secret" --now 5212 >/dev/null 2>"$tmp/err" || rc=$?
[ "$rc" = 2 ] || fail "a settle reason that is only a secret: exit $rc, expected 2"
[ "$(field "$(grep "^$sid$TAB" "$store")" 12)" = open ] || fail "a secret-only settle reason closed the item"
run settle "$sid" --reason "rotated, $secret revoked" --now 5213 >/dev/null || fail "a settle reason with an embedded secret: refused"
[ "$(field "$(grep "^$sid$TAB" "$store")" 18)" = 'rotated, [redacted:aws-access-key-id] revoked' ] || fail "the settled record carries the secret"
grep -q "\"kind\":\"settled\".*\"item\":\"$sid\"" "$log_file" || fail "the settled line for a redacted reason never landed"
grep -q "$secret" "$store" "$log_file" && fail "the secret reached the store or the log"
echo "ok: a closing condition or settle reason that is only a secret is refused; an embedded one is redacted before the store and the log"

# --- echo safety on a hand-corrupted store line (REQ-A1.6) ------------------------

# The detector: the output is tab-separated, so the tab is the one control
# byte allowed; anything else must trip it. Proven on ESC and NUL first, so
# a green run below means the byte was stripped, not that nothing was looked at.
has_control() { tr -d '\t' | LC_ALL=C grep -q '[[:cntrl:]]'; }
printf 'a\033[31mb' | has_control || fail "self-check: the detector misses ESC"
printf 'a\001b' | has_control || fail "self-check: the detector misses a C0 byte"
printf 'a\tb' | has_control && fail "self-check: the detector trips on the tab delimiter"

{
  printf 'ibad00001\tnews\tnormal\top\033[31m\t1\tpath\tx\t-\t%s\t-\tdone\topen\t0\t0\t0\t0\t0\t-\t-\t0\n' "$content"
  printf 'ibad00002\tnews\tnormal\top\t1\tpath\tx\t-\t%s\t-\tdone\001here\topen\t0\t0\t0\t0\t0\t-\t-\t0\n' "$content"
  printf 'ibad00003\tnews\tnormal\top\t1\tpath\tx\t-\t%s\t-\ttorn\topen\t0\t0\t0\t0\n' "$content"
} >>"$store"
out=$(run list 2>"$tmp/err") || fail "list over a corrupted line: exit"
grep -q 'do not parse' "$tmp/err" || fail "list skipped a store line without saying so"
if printf '%s' "$out" | has_control; then
  fail "a control byte from a corrupted store line reached stdout"
fi
printf '%s\n' "$out" | grep -q '^ibad00001' || fail "the corrupted line was dropped from list rather than rendered clean"
printf '%s\n' "$out" | grep -q 'op.31m' || fail "the ESC byte was not stripped from the rendered origin"
# One line per open record: an embedded newline surviving into the render
# would show as an extra line.
[ "$(printf '%s\n' "$out" | grep -c .)" = 8 ] || fail "list printed $(printf '%s\n' "$out" | grep -c .) lines over 8 open records (the torn line is skipped)"
[ "$(run counts --now 5300 | awk -F '\t' '$1 == "malformed" { print $2 }')" = 1 ] || fail "counts did not report the unparseable line"
out=$(run counts) || fail "counts over a corrupted line: exit"
printf '%s' "$out" | has_control && fail "counts echoed a control byte"
echo "ok: a hand-corrupted store line renders with no control byte"

# --- no repo file changes, everything under the fleet home ------------------------

[ -z "$(find "$tmp" -newer "$store" -not -path "$home/*" -not -path "$home" -not -path "$content*" -not -path "$tmp" -not -path "$tmp/local.yml" -not -path "$tmp/err" -not -path "$tmp/out" 2>/dev/null)" ] \
  || fail "a file outside the fleet home and the content root changed: $(find "$tmp" -newer "$store" -not -path "$home/*" -not -path "$content*" | head -n 3)"

echo "ALL PASS: tower-queue store"
