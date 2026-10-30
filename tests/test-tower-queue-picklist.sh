#!/bin/bash
# Tests for scripts/tower-queue.sh's picklist windows: the declaration `add`
# validates, the settling pass applying an ended window's default or park,
# the settled-by-default item staying visible for review, `revoke`, the merge
# rule, and the reason every route out of the open set carries (tower-comms
# REQ-A1.10, REQ-A1.11, REQ-A1.12, REQ-B1.6, REQ-B1.7, REQ-B1.8, REQ-F1.8,
# REQ-G1.9, REQ-H1.5).
#
# Runs standalone under /bin/bash (the bash 3.2 floor).
set -eu
LC_ALL=C
export LC_ALL
unset CDPATH

here=$(cd "$(dirname "$0")" && pwd)
TQ="$here/../scripts/tower-queue.sh"

errf=""

fail() {
  echo "FAIL: $1" >&2
  if [ -n "${errf:-}" ] && [ -s "$errf" ]; then
    echo "--- stderr of the last tower-queue run ---" >&2
    cat "$errf" >&2
  fi
  exit 1
}

[ -x "$TQ" ] || fail "scripts/tower-queue.sh missing or not executable"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
errf="$tmp/stderr"

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
ev="$tmp/evidence"

TAB=$(printf '\t')
A=tower-a

run() {
  : >"$errf"
  PLANWRIGHT_FLEET_STATE_DIR="$home" \
    PLANWRIGHT_ADOPTER_OVERLAY="$adopter" \
    PLANWRIGHT_REPO_ROOT=none \
    PLANWRIGHT_LOCAL_CONFIG="$local_cfg" \
    /bin/sh "$TQ" "$@" 2>"$errf"
}

refused() { # refused <what> <the refusal's reason> <args...> — exit 2, nothing added
  _w=$1
  _why=$2
  shift 2
  _before=$(cat "$store" 2>/dev/null || true)
  _rc=0
  run "$@" >/dev/null || _rc=$?
  [ "$_rc" = 2 ] || fail "$_w: exit $_rc, expected 2"
  [ "$(cat "$store" 2>/dev/null || true)" = "$_before" ] || fail "$_w: the store changed"
  grep -qF -- "$_why" "$errf" || fail "$_w: refused for another reason than '$_why'"
}

evidence() {
  : >"$ev"
  chmod 0600 "$ev"
  for l in "$@"; do printf '%s\n' "$l" >>"$ev"; done
}

# attention_row <worker> <scope> <state> <ts> <prio> <q> <def> <opts> [<reason> [<iid> [<claim> [<command>]]]]
attention_row() {
  mkdir -p "$attn_dir"
  chmod 0700 "$attn_dir"
  {
    printf '%s' "$1"
    shift
    for f in "$@"; do printf '\t%s' "$f"; done
    printf '\n'
  } >>"$attn_store"
}

marker() { # marker <tower> <epoch> — the operator replied in that tower
  mkdir -p "$surface/attention"
  chmod 0700 "$surface/attention"
  printf '%s\n' "$2" >"$surface/attention/$1"
  chmod 0600 "$surface/attention/$1"
}

rec() { grep "^$1$TAB" "$store" || true; }
fld() { rec "$1" | cut -f "$2"; }

# --- the declaration add validates (REQ-A1.11) ----------------------------------------

# The store exists before any row does, so no rebuild registers a row as a
# plain question ahead of the picklist its own add declares.
printf 'seed request\n' >"$content/seed"
seed=$(run add --kind request --root "$content" --pointer seed --origin operator --closes 'the operator decides' --now 900) || fail "seed the store"
run settle "$seed" --reason 'the seed is not under test' --now 901 >/dev/null || fail "settle the seed"

attention_row w-a spec/t1 awaiting-input 1000 normal 'Which base?' main 'main|dev' fork iid-a
attention_row w-perm spec/t2 awaiting-input 1000 high 'Allow the command?' - - permission iid-p - 'npm test'
attention_row w-r spec/t3 awaiting-input 1000 normal 'How to land it?' - 'merge|wait' fork iid-r

refused "a picklist with one option" 'refusing --options' add --kind question --worker w-a --origin w-a --closes 'the operator answers' --options A --end A --gate none --now 1000
refused "an end naming no option" 'refusing --end' add --kind question --worker w-a --origin w-a --closes 'the operator answers' --options 'A|B' --end C --gate none --now 1000
refused "an end spanning two labels" 'refusing --end' add --kind question --worker w-a --origin w-a --closes 'the operator answers' --options 'A|B|C' --end 'A|B' --gate none --now 1000
refused "a window that fails the grammar" 'refusing --window' add --kind question --worker w-a --origin w-a --closes 'the operator answers' --options 'A|B' --end B --gate none --window soon --now 1000
refused "a declared default with no gate" 'needs --gate none|human-gate|disqualifier-zone' add --kind question --worker w-a --origin w-a --closes 'the operator answers' --options 'A|B' --end B --now 1000
refused "a default behind a human gate" 'behind a human-gate' add --kind question --worker w-a --origin w-a --closes 'the operator answers' --options 'A|B' --end B --gate human-gate --now 1000
refused "a default in a disqualifier zone" 'behind a disqualifier-zone' add --kind question --worker w-a --origin w-a --closes 'the operator answers' --options 'A|B' --end B --gate disqualifier-zone --now 1000
refused "a default on a permission prompt" 'on a worker permission prompt' add --kind question --worker w-perm --origin w-perm --closes 'the operator answers' --options 'allow|deny' --end deny --gate none --now 1000
refused "a default on options naming a reserved control" 'naming a reserved human control' add --kind question --worker w-r --origin w-r --closes 'the operator answers' --options 'merge it|wait' --end wait --gate none --now 1000
refused "a picklist on a request" 'declared only on a question' add --kind request --root "$content" --pointer nope --origin operator --closes 'the operator decides' --options 'A|B' --end A --gate none --now 1000
refused "an added settled-by-default item" 'is never added' add --kind settled-by-default --worker w-a --origin w-a --closes 'the operator answers' --now 1000
refused "a kind outside the closed set" 'refusing kind' add --kind decision --worker w-a --origin w-a --closes 'the operator answers' --now 1000
secret_opt="AKIAABCDEFGHIJKLMNOP"
refused "an end the redaction helper would change" 'redaction helper would change' add --kind question --worker w-a --origin w-a --closes 'the operator answers' --options "left|$secret_opt" --end "$secret_opt" --gate none --now 1000
attention_row w-fq spec/t3b awaiting-input 1000 normal 'Force-push the branch to main now?' - 'yes|no' fork iid-fq
refused "a default on a question whose text names a reserved control" 'question names a reserved human control' add --kind question --worker w-fq --origin w-fq --closes 'the operator answers' --options 'yes|no' --end no --gate none --now 1000
echo "ok: add refuses a malformed picklist, a default with no gate or behind a gate, and a default on a permission prompt or a reserved control, in the options or the question"

p_perm=$(run add --kind question --worker w-perm --origin w-perm --closes 'the operator answers' --options 'allow|deny' --end park --now 1000) \
  || fail "park on a permission prompt was refused"
p_res=$(run add --kind question --worker w-r --origin w-r --closes 'the operator answers' --options 'merge it|wait' --end park --gate human-gate --now 1000) \
  || fail "park behind a human gate on a reserved-control option was refused"
[ "$(fld "$p_res" 28)" = park ] || fail "the park end was not stored"
echo "ok: park is admitted on a permission prompt, a reserved control and a human gate"

# The knob default: a window left unset takes tower_picklist_window (30m).
attention_row w-k spec/t4 awaiting-input 1000 normal 'Retry?' yes 'yes|no' fork iid-k
p_knob=$(run add --kind question --worker w-k --origin w-k --closes 'the operator answers' --options 'yes|no' --end no --gate none --now 1000) \
  || fail "add with the knob's window"
[ "$(fld "$p_knob" 29)" = 2800 ] || fail "an unset window did not take tower_picklist_window: window end '$(fld "$p_knob" 29)'"
grep -q "\"kind\":\"picklist\".*\"item\":\"$p_knob\".*\"options\":\"yes|no\".*\"end\":\"no\"" "$log_file" \
  || fail "the picklist declaration was not logged with its birth"
echo "ok: an unset window takes tower_picklist_window and the declaration is logged with the birth"

printf 'tower_picklist_window: 500ms\n' >"$local_cfg"
attention_row w-ks spec/t4s awaiting-input 1000 normal 'Retry now?' yes 'yes|no' fork iid-ks
p_ks=$(run add --kind question --worker w-ks --origin w-ks --closes 'the operator answers' --options 'yes|no' --end no --gate none --now 1000) \
  || fail "add with a sub-second knob window"
[ "$(fld "$p_ks" 29)" = 1000.5 ] || fail "a sub-second tower_picklist_window was not honoured: window end '$(fld "$p_ks" 29)'"
run settle "$p_ks" --reason 'the sub-second knob is not under test past here' --now 1000 >/dev/null || fail "settle the sub-second knob item"
: >"$local_cfg"
echo "ok: tower_picklist_window takes a sub-second span"

# --- the Done-when fixture: options A and B, default B, a sub-second window -----------

attention_row w-b spec/t5 awaiting-input 1000 normal 'Keep the old name or take the new one?' A 'A|B' fork iid-b
q=$(run add --kind question --worker w-b --origin w-b --closes 'the operator answers' \
  --options 'A|B' --end B --gate none --window 500ms --subject pr:31 --now 1000) || fail "add the sub-second picklist"
[ "$(fld "$q" 29)" = 1000.5 ] || fail "the window end is not the birth plus the window: '$(fld "$q" 29)'"
# The pass runs long after the window: the end time, not the pass time, is
# what the record carries (REQ-A1.12).
out=$(run settle --now 1900) || fail "the settling pass after the window"
[ "$(fld "$q" 2)" = settled-by-default ] || fail "the ended window was not applied: kind '$(fld "$q" 2)'"
[ "$(fld "$q" 12)" = open ] || fail "a settled-by-default item left the open set before its review"
[ "$(fld "$q" 17)" = 1001 ] || fail "the settled time is not the window's end: '$(fld "$q" 17)' (the pass ran at 1900)"
case "$(fld "$q" 18)" in
  *"default: B"*"window end 1000.5"*) ;;
  *) fail "the record does not carry the option applied and the window end: '$(fld "$q" 18)'" ;;
esac
printf '%s\n' "$out" | grep -q "^window${TAB}$q${TAB}default${TAB}B${TAB}1000.5" || fail "the pass printed no window line: $out"
grep -q "\"kind\":\"window\".*\"item\":\"$q\".*\"end\":\"default\".*\"option\":\"B\".*\"at\":1000.5" "$log_file" \
  || fail "the window's end was not logged with the option and the end time"
grep -q "\"item_kind\":\"settled-by-default\"" "$surface/ledger" 2>/dev/null \
  || grep -q "review.$q.1000.5" "$surface/ledger" || fail "the review content is not in the ledger fallback"
echo "ok: a timed-out picklist settles to its default with the window's end time, logged, its content in the ledger"

run list | grep -q "^$q${TAB}settled-by-default${TAB}" || fail "list does not print the settled-by-default item"
show=$(run show "$q") || fail "show exited non-zero"
printf '%s\n' "$show" | grep -q "^item${TAB}$q${TAB}settled-by-default" || fail "show does not render the item: $show"
printf '%s\n' "$show" | grep -q "^reason${TAB}the window ended on its default: B" || fail "show does not render the reason: $show"
printf '%s\n' "$show" | grep -q "^picklist${TAB}A|B${TAB}B${TAB}1000.5${TAB}none" || fail "show does not render the picklist: $show"
counts=$(run counts) || fail "counts exited non-zero"
printf '%s\n' "$counts" | grep -q "^settled-by-default${TAB}1$" || fail "counts does not count it: $counts"
printf '%s\n' "$counts" | grep -q "^malformed${TAB}0$" || fail "counts reads the new record as malformed: $counts"
run catchup | grep -q "^settled${TAB}$q${TAB}settled-by-default" || fail "catchup does not carry the default applied without the operator"
echo "ok: list, show, counts and catchup still show it"

# A present operator is handed it for review; it is never pushed. The open
# questions rank above it, so they are shelved out of the way first.
for id in $p_perm $p_res $p_knob; do
  run shelve "$id" --tower $A --for 1h --now 1905 >/dev/null || fail "shelve $id"
done
run next --tower $A --now 1910 >/dev/null || fail "the knock"
marker $A 1911
handed=$(run next --tower $A --now 1912) || fail "the hand-over"
printf '%s\n' "$handed" | grep -q "^item${TAB}$q${TAB}settled-by-default" || fail "a present operator was not handed it for review: $handed"
grep -q "\"kind\":\"pushed\".*\"item\":\"$q\"" "$log_file" && fail "a settled-by-default item was pushed"
echo "ok: a present operator is handed it for review"

# --- revoke reopens the question with no window, and it never defaults again ----------

out=$(run revoke "$q" --tower $A --now 2000) || fail "revoke exited non-zero"
printf '%s\n' "$out" | grep -q "^reopened${TAB}$q${TAB}settled-by-default${TAB}reopen" || fail "revoke printed '$out'"
[ "$(fld "$q" 2)" = question ] || fail "a revoked default did not reopen as its question"
[ "$(fld "$q" 28)" = - ] && [ "$(fld "$q" 29)" = 0 ] || fail "the reopened question kept its window"
grep -q "\"kind\":\"revoked\".*\"item\":\"$q\".*\"reversal\":\"reopen\"" "$log_file" || fail "the revocation was not logged with its reversal"
run settle --now 9000 >/dev/null || fail "the pass after the revoke"
[ "$(fld "$q" 2)" = question ] || fail "a revoked default defaulted a second time"
[ "$(fld "$q" 12)" = open ] || fail "the reopened question left the open set"
rc=0
run revoke "$q" --tower $A --now 9001 >/dev/null || rc=$?
[ "$rc" = 1 ] || fail "revoking a plain question: exit $rc, expected 1"
echo "ok: revoke reopens the question with no window, and a later pass does not default it again"

# --- a park answers nothing (REQ-A1.12) ------------------------------------------------

attention_row w-p spec/t6 awaiting-input 1000 normal 'Ship now?' - 'now|later' fork iid-pk
pk=$(run add --kind question --worker w-p --origin w-p --closes 'the operator answers' --options 'now|later' --end park --window 1s --now 3000) \
  || fail "add the park picklist"
out=$(run settle --now 3005) || fail "the pass past the park window"
[ "$(fld "$pk" 2)" = question ] && [ "$(fld "$pk" 12)" = open ] || fail "a park window changed the question: $(rec "$pk")"
[ "$(fld "$pk" 31)" = 1 ] || fail "the parked question is not marked parked"
[ "$(fld "$pk" 18)" = - ] || fail "a park answered something: '$(fld "$pk" 18)'"
run list | grep -q "^$pk${TAB}question${TAB}.*${TAB}parked${TAB}" || fail "list does not show the question parked"
run show "$pk" | grep -q "^picklist${TAB}now|later${TAB}park${TAB}3001${TAB}-${TAB}parked" || fail "show does not render the park"
grep -q "\"kind\":\"window\".*\"item\":\"$pk\".*\"end\":\"park\"" "$log_file" || fail "the park was not logged"
[ "$(grep -c "\"kind\":\"window\".*\"item\":\"$pk\"" "$log_file")" = 1 ] || {
  run settle --now 3100 >/dev/null
  fail "a park was logged more than once"
}
run settle --now 3100 >/dev/null || fail "a second pass over the park"
[ "$(grep -c "\"kind\":\"window\".*\"item\":\"$pk\"" "$log_file")" = 1 ] || fail "a second pass ended the park again"
echo "ok: a park window ends with the question open, marked parked, nothing answered"

# --- a PR's merge settles with a reason show and catchup render (REQ-B1.7) -------------

printf 'request r1\n' >"$content/r1"
r1=$(run add --kind request --root "$content" --pointer r1 --origin operator --subject pr:57 --closes 'the operator decides' --now 3200) || fail "add r1"
evidence "stamp${TAB}3300" "pr${TAB}57${TAB}merged"
run settle --evidence "$ev" --now 3310 >/dev/null || fail "the pass with the merge"
[ "$(fld "$r1" 12)" = closed ] || fail "the merged PR did not settle its item"
run show "$r1" | grep -q "^reason${TAB}PR #57 is merged" || fail "show does not render the PR reason"
run catchup | grep "^settled${TAB}$r1${TAB}" | grep -q 'PR #57 is merged' || fail "catchup does not render the PR reason beside the item"
echo "ok: an item whose PR merged settles with a reason naming it, rendered by show and catchup"

# --- an unreachable source keeps the item open past every horizon (REQ-B1.6) -----------

printf 'tower_catchup_limit: 1\ntower_quiet_interval: 1s\ntower_lease_interval: 2s\ntower_shelve_return: 1s\n' >"$local_cfg"
printf 'request r2\n' >"$content/r2"
r2=$(run add --kind request --root "$content" --pointer r2 --origin operator --subject pr:58 --closes 'the operator decides' --now 4000) || fail "add r2"
run shelve "$r2" --tower $A --for 1s --now 4001 >/dev/null || fail "shelve r2"
evidence "stamp${TAB}4002" "unavailable${TAB}github${TAB}timeout"
i=0
while [ "$i" -lt 4 ]; do
  printf 'request filler %s\n' "$i" >"$content/f$i"
  f=$(run add --kind request --root "$content" --pointer "f$i" --origin operator --closes 'the operator decides' --now $((4010 + i))) || fail "add filler $i"
  run settle "$f" --reason "filler $i" --now $((4011 + i)) >/dev/null || fail "settle filler $i"
  run settle --evidence "$ev" --now $((5000 + i * 1000)) >/dev/null || fail "the unreachable pass $i"
  i=$((i + 1))
done
[ "$(fld "$r2" 12)" = open ] || fail "an item whose source is unreachable left the open set"
[ "$(grep -c '"kind":"unavailable".*"source":"github"' "$log_file")" -ge 4 ] || fail "each pass did not log the source unavailable"
evidence "stamp${TAB}9500" "pr${TAB}58${TAB}merged"
run settle --evidence "$ev" --now 9600 >/dev/null || fail "the pass with the evidence"
[ "$(fld "$r2" 12)" = closed ] && [ "$(fld "$r2" 18)" = "PR #58 is merged" ] || fail "the evidence did not settle it with its reason: $(rec "$r2")"
echo "ok: an unreachable source keeps the item open past every timeout, lease, shelve and horizon until evidence settles it"
: >"$local_cfg"

# --- picklists merge only on identical options, end and window end ---------------------

attention_row w-m1 spec/t7 awaiting-input 1000 normal 'Rebuild the cache?' yes 'yes|no' fork iid-m1
attention_row w-m2 spec/t8 awaiting-input 1000 normal 'Rebuild the cache?' yes 'yes|no' fork iid-m2
attention_row w-m3 spec/t9 awaiting-input 1000 normal 'Rebuild the cache?' yes 'yes|no' fork iid-m3
m1=$(run add --kind question --worker w-m1 --origin w-m1 --closes 'the operator answers' --options 'yes|no' --end no --gate none --window 1h --now 10000) || fail "add m1"
m2=$(run add --kind question --worker w-m2 --origin w-m2 --closes 'the operator answers' --options 'yes|no' --end no --gate none --window 2h --now 10000) || fail "add m2"
run settle --now 10001 >/dev/null || fail "the merge pass, windows differing"
[ "$(fld "$m1" 12)" = open ] && [ "$(fld "$m2" 12)" = open ] || fail "two picklists with different window ends merged"
m3=$(run add --kind question --worker w-m3 --origin w-m3 --closes 'the operator answers' --options 'yes|no' --end no --gate none --window 1h --now 10000) || fail "add m3"
run settle --now 10002 >/dev/null || fail "the merge pass, windows identical"
if [ "$(fld "$m1" 12)" = open ]; then
  [ "$(fld "$m3" 18)" = "merged into $m1" ] || fail "two identical picklists did not merge: $(rec "$m3")"
else
  [ "$(fld "$m1" 18)" = "merged into $m3" ] || fail "two identical picklists did not merge: $(rec "$m1")"
fi
[ "$(fld "$m2" 12)" = open ] || fail "the picklist with its own window end was absorbed"
attention_row w-m4 spec/t7a awaiting-input 1000 normal 'Rebuild the cache?' yes 'yes|no' fork iid-m4
attention_row w-m5 spec/t7b awaiting-input 1000 normal 'Rebuild the cache?' yes 'yes|no' fork iid-m5
m4=$(run add --kind question --worker w-m4 --origin w-m4 --closes 'the operator answers' --options 'yes|no' --end yes --gate none --window 1h --now 10000) || fail "add m4"
m5=$(run add --kind question --worker w-m5 --origin w-m5 --closes 'the operator answers' --options 'no|yes' --end no --gate none --window 1h --now 10000) || fail "add m5"
run settle --now 10003 >/dev/null || fail "the merge pass, ends or options differing"
[ "$(fld "$m4" 12)" = open ] || fail "a picklist with another end was absorbed: $(rec "$m4")"
[ "$(fld "$m5" 12)" = open ] || fail "a picklist with other options was absorbed: $(rec "$m5")"
echo "ok: picklist items merge only when options, end and window end are identical"

# --- evidence that already answered a question wins over its ended window -------------

attention_row w-c spec/t10 awaiting-input 1000 normal 'Pick one?' A 'A|B' fork iid-c claimed-elsewhere
qc=$(run add --kind question --worker w-c --origin w-c --closes 'the operator answers' --options 'A|B' --end B --gate none --window 500ms --now 11000) || fail "add the answered picklist"
out=$(run settle --now 11100) || fail "the pass over an answered question with an ended window"
[ "$(fld "$qc" 2)" = question ] && [ "$(fld "$qc" 12)" = closed ] || fail "a default was applied to a question the evidence had answered: $(rec "$qc")"
[ "$(fld "$qc" 18)" = "answered by another route (its worker record was claimed)" ] || fail "the answered question carries '$(fld "$qc" 18)'"
printf '%s\n' "$out" | grep -q "^window${TAB}$qc${TAB}" && fail "the pass printed a window line for an answered question: $out"
grep -q "review\.$qc\." "$surface/ledger" && fail "the ledger records a default for a question the evidence answered"
attention_row w-gone spec/t10g awaiting-input 1000 normal 'Pick again?' A 'A|B' fork iid-gone
qgone=$(run add --kind question --worker w-gone --origin w-gone --closes 'the operator answers' --options 'A|B' --end B --gate none --window 500ms --now 11200) || fail "add the picklist whose row will go"
awk -F "$TAB" '$1 != "w-gone"' "$attn_store" >"$tmp/attn" && cat "$tmp/attn" >"$attn_store"
run settle --now 11300 >/dev/null || fail "the pass over a question whose row is gone"
[ "$(fld "$qgone" 2)" = question ] && [ "$(fld "$qgone" 12)" = closed ] || fail "a default was applied to a question whose row is gone: $(rec "$qgone")"
grep -q "review\.$qgone\." "$surface/ledger" && fail "the ledger records a default for a question whose row is gone"
echo "ok: a question the evidence answered settles by that evidence, never by its window's default"

# --- one window whose review content cannot be written stops nothing else -------------

attention_row w-f spec/t11 awaiting-input 1000 normal 'Keep going?' yes 'yes|no' fork iid-f
qf=$(run add --kind question --worker w-f --origin w-f --closes 'the operator answers' --options 'yes|no' --end yes --gate none --window 500ms --now 12000) || fail "add the picklist whose content write will fail"
printf 'request r3\n' >"$content/r3"
r3=$(run add --kind request --root "$content" --pointer r3 --origin operator --closes 'the operator decides' --now 12000) || fail "add r3"
rm -f "$content/r3"
bad_helper="$tmp/refusing-ledger.sh"
printf '#!/bin/sh\nexit 1\n' >"$bad_helper"
chmod 0755 "$bad_helper"
rc=0
PLANWRIGHT_ACTION_LEDGER="$bad_helper" run settle --now 12100 >/dev/null || rc=$?
[ "$rc" = 0 ] || fail "a refused review-content write failed the whole pass: exit $rc"
[ "$(fld "$qf" 2)" = question ] && [ "$(fld "$qf" 31)" = 0 ] || fail "a window whose content was not written was applied: $(rec "$qf")"
[ "$(fld "$r3" 12)" = closed ] || fail "the pass stopped before settling an unrelated item: $(rec "$r3")"
grep -q "review content for $qf could not be written" "$errf" || fail "the failed content write was not reported"
run settle --now 12200 >/dev/null || fail "the pass once the ledger takes the content"
[ "$(fld "$qf" 2)" = settled-by-default ] || fail "the window did not apply once its content could be written: $(rec "$qf")"
echo "ok: a window whose review content cannot be written stays a question and the pass settles the rest"

# --- the long away timeline: open, evidence-settled or defaulted, never dropped -------

all_ids=$(cut -f 1 "$store" | sort)
i=0
while [ "$i" -lt 5 ]; do
  run settle --now $((20000 + i * 5000)) >/dev/null || fail "the away pass $i"
  i=$((i + 1))
done
[ "$(cut -f 1 "$store" | sort)" = "$all_ids" ] || fail "the away timeline dropped or added records"
[ "$(fld "$p_knob" 2)" = settled-by-default ] || fail "the knob-window picklist did not default over the away timeline"
[ "$(fld "$p_perm" 2)" = question ] && [ "$(fld "$p_perm" 12)" = open ] || fail "the permission park was answered over the away timeline"
echo "ok: over a long away timeline nothing is dropped and the only answer taken is a declared default"

# --- the settling pass parks a default whose question turned into a reserved control ---

attention_row w-tq spec/t10 awaiting-input 1000 normal 'Retry the job?' yes 'yes|no' fork iid-tq
tq=$(run add --kind question --worker w-tq --origin w-tq --closes 'the operator answers' --options 'yes|no' --end yes --gate none --window 1s --now 40000) \
  || fail "add the question that changes"
# The row is re-asked in place before the window ends: same instance, new text.
awk -F "$TAB" -v OFS="$TAB" '$1 == "w-tq" { $6 = "Rebase onto main and force-push?" } { print }' "$attn_store" >"$tmp/attn" && cat "$tmp/attn" >"$attn_store"
run settle --now 40005 >/dev/null || fail "the pass over the changed question"
[ "$(fld "$tq" 2)" = question ] && [ "$(fld "$tq" 31)" = 1 ] || fail "a default answered a question that now names a reserved control: $(rec "$tq")"
grep -q "review.$tq" "$surface/ledger" && fail "review content was written for a question the pass parked"
echo "ok: the settling pass parks, never defaults, a question whose text names a reserved control"

# --- the settling pass re-checks the options of a stored default ----------------------

attention_row w-so spec/t11 awaiting-input 1000 normal 'Which one?' a 'a|b' fork iid-so
so=$(run add --kind question --worker w-so --origin w-so --closes 'the operator answers' --options 'a|b' --end b --gate none --window 1s --now 41000) \
  || fail "add the question whose stored options change"
# A store written by an older or a forged writer: the options now name one.
awk -F "$TAB" -v OFS="$TAB" -v i="$so" '$1 == i { $27 = "merge it|b" } { print }' "$store" >"$tmp/store" && cat "$tmp/store" >"$store"
run settle --now 41005 >/dev/null || fail "the pass over the changed options"
[ "$(fld "$so" 2)" = question ] && [ "$(fld "$so" 31)" = 1 ] || fail "a default applied over options naming a reserved control: $(rec "$so")"
echo "ok: the settling pass parks a stored default whose options name a reserved control"

# --- no route out of the open set leaves a record without a reason --------------------

awk -F "$TAB" '$12 == "closed" && ($18 == "-" || $18 == "") { print; bad = 1 } END { exit bad }' "$store" \
  || fail "a closed record carries no settling reason"
echo "ok: every closed record carries its settling reason"

# --- the pass re-reads the gate and the permission marker itself (REQ-H1.5) ------------

# add refuses both, so each record is written straight into the store.
attention_row w-g spec/t12 awaiting-input 1000 normal 'Proceed?' yes 'yes|no' fork iid-g
qg=$(run add --kind question --worker w-g --origin w-g --closes 'the operator answers' --options 'yes|no' --end park --window 1s --now 30000) || fail "add the gated picklist"
for pair in "$p_perm:allow" "$qg:yes"; do
  pid=${pair%%:*}
  gate=none
  [ "$pid" != "$qg" ] || gate=human-gate
  grep -v "^$pid$TAB" "$store" >"$tmp/store.new"
  rec "$pid" | awk -F "$TAB" -v OFS="$TAB" -v e="${pair#*:}" -v g="$gate" '{ $28 = e; $30 = g; $31 = 0; print }' >>"$tmp/store.new"
  cat "$tmp/store.new" >"$store"
done
run settle --now 30100 >/dev/null || fail "the pass over the planted defaults"
for pid in $p_perm $qg; do
  [ "$(fld "$pid" 2)" = question ] && [ "$(fld "$pid" 31)" = 1 ] || fail "a planted default was applied, not parked: $(rec "$pid")"
  grep -q "review\.$pid\." "$surface/ledger" && fail "review content was written for $pid, which the pass parks"
done
echo "ok: the pass parks a default on a permission prompt or behind a gate, and writes no review content for it"

# --- a malformed record with an ended window never forces a pass on every next --------

grep -v "^$qf$TAB" "$store" >"$tmp/store.new"
rec "$qf" | awk -F "$TAB" -v OFS="$TAB" '{ $2 = "question"; $3 = "urgent"; $31 = 0; print }' >>"$tmp/store.new"
cat "$tmp/store.new" >"$store"
evidence "stamp${TAB}40000"
run settle --evidence "$ev" --now 40001 >/dev/null || fail "the pass that stamps the evidence"
run next --tower $A --evidence "$ev" --now 40002 >/dev/null || fail "next after the stamped pass"
[ "$(cut -f 1 "$surface/settle.stamp")" = 40001 ] || fail "a malformed record with an ended window forced another pass: stamp $(cut -f 1 "$surface/settle.stamp")"
echo "ok: a record the pass cannot read never keeps a window due"

# --- the catch-up remainder counts defaults past the store's horizon (REQ-B1.7) -------

home="$tmp/fleet-home-catchup"
mkdir -p "$home"
chmod 0700 "$home"
surface="$home/tower-comms"
store="$surface/queue"
log_file="$surface/events.log"
attn_dir="$home/attention"
attn_store="$attn_dir/state"
printf 'tower_catchup_limit: 1\n' >"$local_cfg"
seed=$(run add --kind request --root "$content" --pointer seed --origin operator --closes 'the operator decides' --now 900) || fail "seed the catch-up store"
run settle "$seed" --reason 'the seed' --now 901 >/dev/null || fail "settle the catch-up seed"
for w in c1 c2 c3; do
  attention_row "w-$w" "spec/$w" awaiting-input 1000 normal 'Which?' A 'A|B' fork "iid-$w"
  run add --kind question --worker "w-$w" --origin "w-$w" --closes 'the operator answers' --options 'A|B' --end B --gate none --window 1s --now 1000 >/dev/null || fail "add $w"
done
run settle --now 1100 >/dev/null || fail "the pass that defaults all three"
t=1200
run next --tower $A --now $t >/dev/null || fail "the catch-up knock"
for w in c1 c2 c3; do
  t=$((t + 10))
  marker $A $t
  got=$(run next --tower $A --now $((t + 1))) || fail "hand over a default for review"
  id=$(printf '%s\n' "$got" | awk -F "$TAB" '$1 == "item" { print $2; exit }')
  [ -n "$id" ] || fail "no default handed over: $got"
  run ack "$id" --tower $A --now $((t + 2)) >/dev/null || fail "review $id"
  case "$(fld "$id" 18)" in
    "reviewed by the operator (reversal: reopen); the window ended on its default: B"*) ;;
    *) fail "an acknowledged default does not close as reviewed with its reversal: '$(fld "$id" 18)'" ;;
  esac
  grep -q "\"kind\":\"reviewed\".*\"item\":\"$id\".*\"item_kind\":\"settled-by-default\"" "$log_file" || fail "the review of $id was not logged"
done
remainder=$(run catchup | awk -F "$TAB" '$1 == "remainder"')
[ "$remainder" = "remainder${TAB}3${TAB}exact${TAB}-" ] || fail "the catch-up remainder lost the reviewed defaults past the horizon: '$remainder'"
remainder=$(run catchup --since 1050 | awk -F "$TAB" '$1 == "remainder"')
[ "$remainder" = "remainder${TAB}0${TAB}exact${TAB}-" ] || fail "a default whose window ended before --since was counted by its pass time: '$remainder'"
attention_row w-c4 spec/c4 awaiting-input 1000 normal 'Which?' A 'A|B' fork iid-c4
c4=$(run add --kind question --worker w-c4 --origin w-c4 --closes 'the operator answers' --options 'A|B' --end B --gate none --window 1s --now 1300) || fail "add c4"
run settle --now 1400 >/dev/null || fail "the pass that defaults c4"
marker $A 1401
run next --tower $A --now 1402 >/dev/null || fail "hand over c4"
run revoke "$c4" --tower $A --now 1403 >/dev/null || fail "revoke c4"
remainder=$(run catchup | awk -F "$TAB" '$1 == "remainder"')
[ "$remainder" = "remainder${TAB}3${TAB}exact${TAB}-" ] || fail "a revoked default still counts toward the remainder: '$remainder'"
echo "ok: the catch-up remainder counts the defaults the store no longer keeps, by their window end, less any revoked"
: >"$local_cfg"

# --- a fallback ledger that fails its owner check refuses the verb, lock released -----

home="$tmp/fleet-home-ledger-mode"
mkdir -p "$home"
chmod 0700 "$home"
surface="$home/tower-comms"
store="$surface/queue"
log_file="$surface/events.log"
attn_dir="$home/attention"
attn_store="$attn_dir/state"
seed=$(run add --kind request --root "$content" --pointer seed --origin operator --closes 'the operator decides' --now 900) || fail "seed the ledger-mode store"
run settle "$seed" --reason 'the seed' --now 901 >/dev/null || fail "settle the ledger-mode seed"
for w in l1 l2; do
  attention_row "w-$w" "spec/$w" awaiting-input 1000 normal 'Which?' A 'A|B' fork "iid-$w"
  run add --kind question --worker "w-$w" --origin w-$w --closes 'the operator answers' --options 'A|B' --end B --gate none --window 1s --now 1000 >/dev/null || fail "add $w"
done
printf 'format\t1\n' >"$surface/ledger"
chmod 0644 "$surface/ledger"
rc=0
run settle --now 1100 >/dev/null || rc=$?
[ "$rc" = 4 ] || fail "a fallback ledger that is not owner-only: exit $rc, expected the security refusal 4"
[ ! -e "$home/.fleet.lock" ] && [ ! -L "$home/.fleet.lock" ] || fail "the refused ledger write left the fleet lock held"
echo "ok: a fallback ledger failing its owner check refuses the pass outright and leaves no lock behind"
