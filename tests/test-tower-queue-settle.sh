#!/bin/bash
# Tests for scripts/tower-queue.sh's settling pass and its catch-up — the
# level-triggered `settle` with no item id, the evidence that may close an
# item and the claims that may not, unavailable sources, the away record, and
# the `catchup` verb (REQ-B1.1, REQ-B1.2, REQ-B1.4, REQ-B1.5, REQ-F1.4,
# REQ-H1.2). Merging and pairing are in test-tower-queue-merge.sh.
#
# Contract under test:
#   settle [--evidence <file>] [--now <epoch>]
#       Re-evaluate every open item's closing condition against the evidence
#       available now. Prints one `settled` line per item closed (id, kind,
#       whether the operator was away, the reason), one `unavailable` line per
#       source that would not answer, and a `held` line carrying the seconds
#       the fleet lock was held. Takes no --tower: settling is evidence-driven.
#   catchup [--tower <id>] [--since <epoch>] [--now <epoch>]
#       What settled without the operator since their last reply: one
#       `settled` line each with its reason, most recent first, bounded to
#       `tower_catchup_limit`, then a `remainder` count and the open counts
#       by kind. Lock-free.
#
# Runs standalone under /bin/bash (the bash 3.2 floor).
set -eu
LC_ALL=C
export LC_ALL
unset CDPATH

here=$(cd "$(dirname "$0")" && pwd)
TQ="$here/../scripts/tower-queue.sh"

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

[ -x "$TQ" ] || fail "scripts/tower-queue.sh missing or not executable"

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
ev="$tmp/evidence"

TAB=$(printf '\t')

run() {
  PLANWRIGHT_FLEET_STATE_DIR="$home" \
    PLANWRIGHT_ADOPTER_OVERLAY="$adopter" \
    PLANWRIGHT_REPO_ROOT="$tmp" \
    PLANWRIGHT_LOCAL_CONFIG="$local_cfg" \
    /bin/sh "$TQ" "$@"
}

# evidence <line>... — the already-derived table the pass consumes. Owner-only,
# the same bar the store is held to: what settles an item settles it without
# the operator ever seeing it.
evidence() {
  : >"$ev"
  chmod 0600 "$ev"
  for l in "$@"; do printf '%s\n' "$l" >>"$ev"; done
}

# attention_row <worker> <scope> <state> <ts> <prio> <q> <def> <opts> [<reason> [<iid> [<claim> [<command>]]]]
attention_row() {
  mkdir -p "$attn_dir"
  chmod 0700 "$attn_dir"
  printf '%s' "$1" >>"$attn_store"
  shift
  for f in "$@"; do printf '\t%s' "$f" >>"$attn_store"; done
  printf '\n' >>"$attn_store"
}

drop_row() { # drop_row <worker>
  awk -F "$TAB" -v w="$1" '($1 "") != (w "")' "$attn_store" >"$tmp/rows" && mv "$tmp/rows" "$attn_store"
}

rec() { grep "^$1$TAB" "$store" || true; }
state_of() { rec "$1" | cut -f 12; }
reason_of() { rec "$1" | cut -f 18; }
away_of() { rec "$1" | cut -f 22; }

add_req() { # add_req <name> <subject> <now> [<urgency>]
  printf 'request %s\n' "$1" >"$content/$1"
  run add --kind request --root "$content" --pointer "$1" --origin operator \
    --subject "$2" --urgency "${4:-normal}" --closes 'the operator decides' --now "$3"
}

settled_line() { # settled_line <output> <id>
  printf '%s\n' "$1" | awk -F "$TAB" -v i="$2" '$1 == "settled" && $2 == i { print; exit }'
}

# --- one fixture per evidence source settles its item and nothing else -------------

r_pr=$(add_req r-pr pr:42 1000) || fail "add r-pr"
r_pr_open=$(add_req r-pr-open pr:43 1000) || fail "add r-pr-open"
r_br=$(add_req r-br branch:feature-x 1000) || fail "add r-br"
r_br_none=$(add_req r-br-none branch:feature-y 1000) || fail "add r-br-none"
r_led=$(add_req r-led ledger:AI-7 1000) || fail "add r-led"
r_led_open=$(add_req r-led-open ledger:AI-8 1000) || fail "add r-led-open"
r_quiet=$(add_req r-quiet pr:99 1000) || fail "add r-quiet"

evidence \
  "stamp${TAB}900" \
  "pr${TAB}42${TAB}merged" \
  "pr${TAB}43${TAB}open" \
  "branch${TAB}feature-x${TAB}commits" \
  "branch${TAB}feature-y${TAB}none" \
  "ledger${TAB}AI-7${TAB}closed" \
  "ledger${TAB}AI-8${TAB}open"

out=$(run settle --evidence "$ev" --now 1100 2>/dev/null) || fail "the settling pass exited non-zero"
for id in $r_pr $r_pr_open $r_br $r_led; do
  [ "$(state_of "$id")" = closed ] || fail "$id did not settle on its evidence"
done
[ "$(state_of "$r_br_none")" = open ] || fail "a branch reporting no commits settled an item"
[ "$(state_of "$r_led_open")" = open ] || fail "an open ledger item settled an item"
[ "$(state_of "$r_quiet")" = open ] || fail "an item whose subject the evidence never names settled"
case "$(reason_of "$r_pr")" in *'PR #42 is merged'*) ;; *) fail "the settle record does not name the merge: '$(reason_of "$r_pr")'" ;; esac
case "$(reason_of "$r_pr_open")" in *'PR #43 is open'*) ;; *) fail "an open PR did not settle its item with that reason" ;; esac
case "$(reason_of "$r_br")" in *'feature-x carries commits'*) ;; *) fail "the branch settle does not name the commits" ;; esac
case "$(reason_of "$r_led")" in *'AI-7 is closed'*) ;; *) fail "the ledger settle does not name the ledger item" ;; esac
[ -n "$(settled_line "$out" "$r_pr")" ] || fail "the pass printed no settled line for $r_pr"
grep -q "\"kind\":\"settled\".*\"item\":\"$r_pr\".*\"reason\":\"PR #42 is merged\"" "$log_file" \
  || fail "no settled event naming the evidence"
echo "ok: an open or merged PR, commits on a branch and a closed ledger item each settle their own item and nothing else"

# --- a worker's own completion report settles nothing (REQ-B1.2, REQ-H1.2) --------

attention_row w-done scope-1 awaiting-input 1000 normal 'proceed?' yes 'yes,no'
q_done=$(run add --kind question --worker w-done --origin w-done --closes 'the operator answers' --now 1010) || fail "add the w-done question"
drop_row w-done
attention_row w-done scope-1 'done' 1200 normal 'proceed?' yes 'yes,no'
evidence "stamp${TAB}1201" "report${TAB}w-done${TAB}completed success"
run settle --evidence "$ev" --now 1210 >/dev/null 2>&1 || fail "the pass exited non-zero over a worker report"
[ "$(state_of "$q_done")" = open ] || fail "a worker reporting completed/success settled its own question"
echo "ok: a worker's own completed/success status is a claim and settles nothing"

# --- a claim close on the worker's record settles it -----------------------------

drop_row w-done
attention_row w-done scope-1 'done' 1200 normal 'proceed?' yes 'yes,no' '' '' yes
evidence "stamp${TAB}1301"
run settle --evidence "$ev" --now 1310 >/dev/null 2>&1 || fail "the pass exited non-zero over a claim"
[ "$(state_of "$q_done")" = closed ] || fail "a claim close on the worker's record did not settle its question"
case "$(reason_of "$q_done")" in *'answered by another route'*) ;; *) fail "the claim settle does not name the route: '$(reason_of "$q_done")'" ;; esac
echo "ok: a claim close on the worker's record settles the question as answered by another route"

# --- a content home that has gone settles with that reason -----------------------

r_gone=$(add_req r-gone - 1400) || fail "add r-gone"
rm -f "$content/r-gone"
evidence "stamp${TAB}1401"
out=$(run settle --evidence "$ev" --now 1410 2>/dev/null) || fail "the pass exited non-zero over a vanished home"
[ "$(state_of "$r_gone")" = closed ] || fail "an item whose content home has gone did not settle"
case "$(reason_of "$r_gone")" in *'content home has gone'*) ;; *) fail "the vanished home is not the reason: '$(reason_of "$r_gone")'" ;; esac
grep -q "\"kind\":\"settled\".*\"item\":\"$r_gone\".*content home has gone" "$log_file" || fail "the vanished home was not logged"

attention_row w-vanish scope-2 awaiting-input 1400 normal 'which?' a 'a,b'
q_vanish=$(run add --kind question --worker w-vanish --origin w-vanish --closes 'the operator answers' --now 1405) || fail "add the w-vanish question"
drop_row w-vanish
run settle --evidence "$ev" --now 1420 >/dev/null 2>&1 || fail "the pass exited non-zero over a vanished row"
[ "$(state_of "$q_vanish")" = closed ] || fail "an item whose attention row is gone did not settle"
case "$(reason_of "$q_vanish")" in *'attention row is gone'*) ;; *) fail "the vanished row is not the reason" ;; esac
echo "ok: a vanished content home and a vanished attention row each settle with that reason, logged"

# --- an unreachable source is logged, settles nothing, and holds the re-knock ------

r_hold=$(add_req r-hold pr:77 1500) || fail "add r-hold"
evidence "stamp${TAB}1501" "unavailable${TAB}github"
out=$(run settle --evidence "$ev" --now 1510 2>/dev/null) || fail "the pass exited non-zero over an unavailable source"
printf '%s\n' "$out" | grep -q "^unavailable${TAB}github$" || fail "the pass did not report the unavailable source: '$out'"
[ "$(state_of "$r_hold")" = open ] || fail "a source reporting nothing because it was unreachable settled an item"
grep -q '"kind":"unavailable".*"source":"github"' "$log_file" || fail "the unavailable source was not logged"
[ -f "$surface/reknock.hold" ] || fail "no re-knock hold while an evidence source is down"
grep -q '^github$' "$surface/reknock.hold" || fail "the re-knock hold does not name the source"

evidence "stamp${TAB}1502"
run settle --evidence "$ev" --now 1520 >/dev/null 2>&1 || fail "the pass exited non-zero once the source answered"
[ ! -f "$surface/reknock.hold" ] || fail "the re-knock hold outlived the outage"
echo "ok: an unreachable source is logged as unavailable, settles nothing, and holds the worsening re-knock"

# --- level-triggered: a condition met before the last pass still settles ----------

evidence "stamp${TAB}1600" "pr${TAB}50${TAB}merged"
run settle --evidence "$ev" --now 1610 >/dev/null 2>&1 || fail "the first pass over pr 50"
r_late=$(add_req r-late pr:50 1620) || fail "add r-late"
# The same evidence file, untouched: nothing happened since, and the pass has
# to read the condition rather than the events after it.
run settle --evidence "$ev" --now 1630 >/dev/null 2>&1 || fail "the second pass over the same evidence"
[ "$(state_of "$r_late")" = closed ] || fail "the pass replayed events instead of re-reading the condition"
echo "ok: the pass is level-triggered — an already-met condition settles on a later pass with no new event"

# --- one pass per iteration: the next that follows reuses it ---------------------

A=tower-a
evidence "stamp${TAB}1700" "pr${TAB}60${TAB}merged"
run settle --evidence "$ev" --now 1710 >/dev/null 2>&1 || fail "the iteration's pass"
r_reuse=$(add_req r-reuse pr:60 1720) || fail "add r-reuse"
run next --tower $A --evidence "$ev" --now 1730 >/dev/null 2>&1 || fail "next after the pass"
[ "$(state_of "$r_reuse")" = open ] || fail "next ran a second settling pass against evidence the iteration had already run"
evidence "stamp${TAB}1800" "pr${TAB}60${TAB}merged"
run next --tower $A --evidence "$ev" --now 1810 >/dev/null 2>&1 || fail "next against fresh evidence"
[ "$(state_of "$r_reuse")" = closed ] || fail "next did not settle against evidence no pass had seen"
echo "ok: one settling pass serves the iteration, and the next that follows reuses it"

# --- settled while the operator was away is recorded as such (REQ-B1.4) ----------

printf 'tower_quiet_interval: 100s\ntower_lease_interval: 200s\n' >"$local_cfg"
r_away=$(add_req r-away pr:70 1900) || fail "add r-away"
evidence "stamp${TAB}1901" "pr${TAB}70${TAB}merged"
run settle --evidence "$ev" --now 1910 >/dev/null 2>&1 || fail "the away pass"
[ "$(away_of "$r_away")" = 1 ] || fail "an item settled with nobody present was not recorded as settled while away"

mkdir -p "$surface/attention"
chmod 0700 "$surface/attention"
printf '2000\n' >"$surface/attention/$A"
chmod 0600 "$surface/attention/$A"
r_here=$(add_req r-here pr:71 2000) || fail "add r-here"
evidence "stamp${TAB}2001" "pr${TAB}71${TAB}merged"
run settle --evidence "$ev" --now 2010 >/dev/null 2>&1 || fail "the present pass"
[ "$(away_of "$r_here")" = 0 ] || fail "an item settled while the operator was replying was recorded as away"
echo "ok: an item settled while the operator was away is recorded as such, and one settled while they were present is not"

# --- nothing is dropped or auto-answered for lack of attention (REQ-F1.4) ---------

rm -f "$surface/attention/$A"
before=$(grep -c . "$store")
r_open1=$(add_req r-open1 - 2100) || fail "add r-open1"
r_open2=$(add_req r-open2 pr:900 2100) || fail "add r-open2"
evidence "stamp${TAB}2101"
i=0
while [ "$i" -lt 6 ]; do
  run settle --evidence "$ev" --now $((2200 + i * 100)) >/dev/null 2>&1 || fail "the away timeline's pass $i"
  i=$((i + 1))
done
[ "$(state_of "$r_open1")" = open ] || fail "an item with no evidence was closed over a long away timeline"
[ "$(state_of "$r_open2")" = open ] || fail "an item whose evidence never arrived was closed over a long away timeline"
[ "$(grep -c . "$store")" -ge "$before" ] || fail "records were dropped over a long away timeline"
echo "ok: over a long timeline with no operator reply every item stays open or evidence-settled, none answered or dropped"

# --- a delivered item is not a decided one (REQ-B1.5) ----------------------------

printf '2800\n' >"$surface/attention/$A"
chmod 0600 "$surface/attention/$A"
run next --tower $A --evidence "$ev" --now 2801 >/dev/null 2>&1 || fail "the knock before the mention case"
printf '2802\n' >"$surface/attention/$A"
chmod 0600 "$surface/attention/$A"
handed=$(run next --tower $A --evidence "$ev" --now 2803 2>/dev/null | awk -F "$TAB" '$1 == "item" { print $2; exit }')
[ -n "$handed" ] || fail "nothing was handed over for the mention case"
run settle --evidence "$ev" --now 2804 >/dev/null 2>&1 || fail "the pass after the hand-over"
[ "$(state_of "$handed")" = open ] || fail "an item that was only mentioned in a turn was treated as decided"
echo "ok: an item delivered but not acknowledged stays open across a later pass"

# --- catchup: the settled history with reasons, bounded, then the open counts -----

out=$(run catchup --now 3000 2>/dev/null) || fail "catchup exited non-zero"
printf '%s\n' "$out" | grep -q "^settled${TAB}$r_pr${TAB}request${TAB}" || fail "catchup does not list a settled item"
printf '%s\n' "$out" | awk -F "$TAB" -v i="$r_pr" '$1 == "settled" && $2 == i { print $8 }' | grep -q 'PR #42 is merged' \
  || fail "catchup does not carry the settle reason"
printf '%s\n' "$out" | grep -q "^settled${TAB}$r_open1${TAB}" && fail "catchup listed an open item"
printf '%s\n' "$out" | grep -q "^open${TAB}request${TAB}" || fail "catchup prints no open count per kind"
[ "$(printf '%s\n' "$out" | awk -F "$TAB" '$1 == "open" && $2 == "request" { print $3 }')" -ge 2 ] \
  || fail "catchup's open request count is wrong"
[ "$(printf '%s\n' "$out" | awk -F "$TAB" '$1 == "remainder" { print $2 }')" = 0 ] \
  || fail "catchup reported a remainder with everything shown"
# Most recent first: the last item settled leads the list.
[ "$(printf '%s\n' "$out" | awk -F "$TAB" '$1 == "settled" { print $2; exit }')" = "$r_here" ] \
  || fail "catchup is not ordered most recent first"

# The window is the operator's own last reply in that conversation: a reply
# after everything settled leaves nothing to catch up on.
printf '2900\n' >"$surface/attention/$A"
chmod 0600 "$surface/attention/$A"
out=$(run catchup --tower $A --now 3000 2>/dev/null) || fail "catchup --tower exited non-zero"
printf '%s\n' "$out" | grep -q "^settled${TAB}$r_here${TAB}" && fail "catchup showed an item settled before the operator's last reply"
[ "$(printf '%s\n' "$out" | grep -c "^settled${TAB}" || true)" = 0 ] || fail "catchup's since-last-reply window is not applied"

# Lowered below what the store still keeps, the bound shows and the rest is
# counted: the store retained at the limit in force when it was last written.
total=$(run catchup --now 3000 2>/dev/null | grep -c "^settled${TAB}" || true)
[ "$total" -ge 3 ] || fail "too few settled records to bound: $total"
printf 'tower_catchup_limit: 2\n' >"$local_cfg"
out=$(run catchup --now 3000 2>/dev/null) || fail "catchup at a lowered bound exited non-zero"
[ "$(printf '%s\n' "$out" | grep -c "^settled${TAB}" || true)" = 2 ] || fail "catchup did not bound to tower_catchup_limit"
[ "$(printf '%s\n' "$out" | awk -F "$TAB" '$1 == "remainder" { print $2 }')" = "$((total - 2))" ] \
  || fail "catchup's remainder count is wrong"
: >"$local_cfg"
echo "ok: catchup lists every settled item with its reason up to the bound, then a remainder count and the open counts"

# --- the fleet lock's hold over a large fixture stays inside the stated bound ------

: >"$store"
chmod 0600 "$store"
i=0
while [ "$i" -lt 400 ]; do
  printf 'i%08x\trequest\tnormal\toperator\t4000\tpath\tbig\t-\t%s\t-\tthe operator decides\topen\t0\t0\t0\t0\t0\t-\t-\t0\tpr:%d\t0\t-\n' \
    "$i" "$content" "$i" >>"$store"
  i=$((i + 1))
done
printf 'big\n' >"$content/big"
evidence "stamp${TAB}4001" "pr${TAB}7${TAB}merged" "pr${TAB}11${TAB}merged" "pr${TAB}23${TAB}merged"
printf 'tower_catchup_limit: 500\n' >"$local_cfg"
out=$(run settle --evidence "$ev" --now 4100 2>/dev/null) || fail "the pass over the large fixture exited non-zero"
held=$(printf '%s\n' "$out" | awk -F "$TAB" '$1 == "held" { print $2 }')
[ -n "$held" ] || fail "the pass printed no held line"
awk -v h="$held" 'BEGIN { exit (h < 2) ? 0 : 1 }' || fail "the settling pass held the fleet lock ${held}s over a 400-record fixture, past the 2s bound"
[ "$(printf '%s\n' "$out" | grep -c "^settled${TAB}" || true)" = 3 ] || fail "the large fixture settled the wrong number of items"
: >"$local_cfg"
echo "ok: the fleet lock's hold over a 400-record fixture stays inside the stated bound (${held}s)"

echo "PASS: tower-queue settling pass and catch-up"
