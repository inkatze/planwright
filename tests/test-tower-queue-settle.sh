#!/bin/bash
# Tests for scripts/tower-queue.sh's settling pass — the level-triggered
# `settle` with no item id, the evidence that may close an item and the claims
# that may not, unavailable sources, and the
# the `catchup` verb (REQ-B1.1, REQ-B1.2, REQ-B1.4, REQ-B1.5, REQ-F1.4,
# REQ-H1.2). Merging and pairing are in test-tower-queue-merge.sh.
#
# Contract under test:
#   settle [--evidence <file>] [--now <epoch>]
#       Re-evaluate every open item's closing condition against the evidence
#       available now. Prints one `settled` line per item closed (id, kind,
#       whether the operator was away, the reason, and the tower that was
#       holding it), one `unavailable` line per source that would not answer,
#       and a `held` line carrying the seconds the fleet lock was held. Takes
#       no --tower: settling is evidence-driven and never asks a conversation.
#
# Runs standalone under /bin/bash (the bash 3.2 floor).
set -eu
LC_ALL=C
export LC_ALL
unset CDPATH

here=$(cd "$(dirname "$0")" && pwd)
TQ="$here/../scripts/tower-queue.sh"

# The stderr of the last `run`. Kept rather than discarded: a suite that sends
# the system under test to /dev/null reports its own generic message and hides
# the refusal that explains it.
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

run() {
  : >"$errf"
  PLANWRIGHT_FLEET_STATE_DIR="$home" \
    PLANWRIGHT_ADOPTER_OVERLAY="$adopter" \
    PLANWRIGHT_REPO_ROOT="$tmp" \
    PLANWRIGHT_LOCAL_CONFIG="$local_cfg" \
    /bin/sh "$TQ" "$@" 2>"$errf"
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
  {
    printf '%s' "$1"
    shift
    for f in "$@"; do printf '\t%s' "$f"; done
    printf '\n'
  } >>"$attn_store"
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
r_pr_closed=$(add_req r-pr-closed pr:44 1000) || fail "add r-pr-closed"

evidence \
  "stamp${TAB}900" \
  "pr${TAB}42${TAB}merged" \
  "pr${TAB}43${TAB}open" \
  "branch${TAB}feature-x${TAB}commits" \
  "branch${TAB}feature-y${TAB}none" \
  "ledger${TAB}AI-7${TAB}closed" \
  "ledger${TAB}AI-8${TAB}open" \
  "pr${TAB}44${TAB}closed"

out=$(run settle --evidence "$ev" --now 1100) || fail "the settling pass exited non-zero"
for id in $r_pr $r_pr_open $r_br $r_led; do
  [ "$(state_of "$id")" = closed ] || fail "$id did not settle on its evidence"
done
[ "$(state_of "$r_br_none")" = open ] || fail "a branch reporting no commits settled an item"
[ "$(state_of "$r_led_open")" = open ] || fail "an open ledger item settled an item"
[ "$(state_of "$r_pr_closed")" = open ] || fail "a PR reported closed rather than merged settled an item"
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
run settle --evidence "$ev" --now 1210 >/dev/null || fail "the pass exited non-zero over a worker report"
[ "$(state_of "$q_done")" = open ] || fail "a worker reporting completed/success settled its own question"
echo "ok: a worker's own completed/success status is a claim and settles nothing"

# --- a claim close on the worker's record settles it -----------------------------

drop_row w-done
attention_row w-done scope-1 'done' 1200 normal 'proceed?' yes 'yes,no' '' '' yes
evidence "stamp${TAB}1301"
run settle --evidence "$ev" --now 1310 >/dev/null || fail "the pass exited non-zero over a claim"
[ "$(state_of "$q_done")" = closed ] || fail "a claim close on the worker's record did not settle its question"
case "$(reason_of "$q_done")" in *'answered by another route'*) ;; *) fail "the claim settle does not name the route: '$(reason_of "$q_done")'" ;; esac
echo "ok: a claim close on the worker's record settles the question as answered by another route"

# The reason is stored and rendered back to the operator, and the one redaction
# helper is out of awk's reach, so the label itself never travels in it.
drop_row w-done
attention_row w-secret scope-1 awaiting-input 1000 normal 'proceed?' yes 'yes,no'
q_secret=$(run add --kind question --worker w-secret --origin w-secret --closes 'the operator answers' --now 1320) || fail "add the w-secret question"
drop_row w-secret
attention_row w-secret scope-1 'done' 1330 normal 'proceed?' yes 'yes,no' '' '' 'retry with ghp_AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA'
run settle --evidence "$ev" --now 1340 >/dev/null || fail "the pass over a claim carrying a secret"
[ "$(state_of "$q_secret")" = closed ] || fail "the secret-bearing claim did not settle its question"
case "$(reason_of "$q_secret")" in *ghp_*) fail "the claim label was copied into the stored settle reason: '$(reason_of "$q_secret")'" ;; esac
grep -q 'ghp_AAAA' "$store" && fail "the store carries an unredacted secret from the attention row"
# Captured before it is searched: a `run | grep -q` would take a catchup that
# crashed and printed nothing for a catchup that printed no secret, so the one
# assertion guarding the redaction would pass precisely when it stopped running.
out=$(run catchup --since 1335 --now 1400) || fail "catchup over the secret-bearing claim exited non-zero"
printf '%s\n' "$out" | grep -q 'ghp_AAAA' && fail "catchup rendered an unredacted secret back to the operator"
echo "ok: a claim label never travels into the stored reason or the catch-up render"

# The same bar for the reason the pass writes itself: the subject grammar admits
# a token-shaped branch name, and the generated reason quotes it.
r_sub=$(add_req r-sub branch:ghp_BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB 1342) || fail "add r-sub"
evidence "stamp${TAB}1343" "branch${TAB}ghp_BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB${TAB}commits"
run settle --evidence "$ev" --now 1345 >/dev/null || fail "the pass over a token-shaped subject key"
[ "$(state_of "$r_sub")" = closed ] || fail "the branch fact did not settle its item, so the reason was never written"
case "$(reason_of "$r_sub")" in *ghp_BBBB*) fail "a token-shaped subject key reached the stored settle reason: '$(reason_of "$r_sub")'" ;; esac
case "$(reason_of "$r_sub")" in *redacted*) ;; *) fail "the generated reason names no redaction: '$(reason_of "$r_sub")'" ;; esac
out=$(run catchup --since 1344 --now 1400) || fail "catchup over the token-shaped subject key exited non-zero"
printf '%s\n' "$out" | grep -q 'ghp_BBBB' && fail "catchup rendered an unredacted subject key back to the operator"
echo "ok: a reason the pass generates itself is redacted before it is stored or rendered"

# --- an absent attention store is an unreachable source, not "every row gone" ------

attention_row w-mass scope-9 awaiting-input 1350 normal 'mass?' yes 'yes,no'
q_mass=$(run add --kind question --worker w-mass --origin w-mass --closes 'the operator answers' --now 1360) || fail "add the w-mass question"
mv "$attn_store" "$tmp/attn.bak"
out=$(run settle --evidence "$ev" --now 1370) || fail "the pass with no attention store exited non-zero"
[ "$(state_of "$q_mass")" = open ] || fail "a missing attention store closed an attention-homed item unseen"
printf '%s\n' "$out" | grep -q "^unavailable${TAB}attention-store$" || fail "a missing attention store was not reported as unreachable: '$out'"
[ -f "$surface/reknock.hold" ] || fail "a missing attention store did not hold the re-knock"
mv "$tmp/attn.bak" "$attn_store"
run settle --evidence "$ev" --now 1380 >/dev/null || fail "the pass after the attention store returned"
[ ! -f "$surface/reknock.hold" ] || fail "the hold outlived the missing attention store"
echo "ok: a missing attention store is reported as unreachable and settles nothing"

# --- a content home that has gone settles with that reason -----------------------

r_gone=$(add_req r-gone - 1400) || fail "add r-gone"
rm -f "$content/r-gone"
evidence "stamp${TAB}1401"
out=$(run settle --evidence "$ev" --now 1410) || fail "the pass exited non-zero over a vanished home"
[ "$(state_of "$r_gone")" = closed ] || fail "an item whose content home has gone did not settle"
case "$(reason_of "$r_gone")" in *'content home has gone'*) ;; *) fail "the vanished home is not the reason: '$(reason_of "$r_gone")'" ;; esac
grep -q "\"kind\":\"settled\".*\"item\":\"$r_gone\".*content home has gone" "$log_file" || fail "the vanished home was not logged"

attention_row w-vanish scope-2 awaiting-input 1400 normal 'which?' a 'a,b'
q_vanish=$(run add --kind question --worker w-vanish --origin w-vanish --closes 'the operator answers' --now 1405) || fail "add the w-vanish question"
drop_row w-vanish
run settle --evidence "$ev" --now 1420 >/dev/null || fail "the pass exited non-zero over a vanished row"
[ "$(state_of "$q_vanish")" = closed ] || fail "an item whose attention row is gone did not settle"
case "$(reason_of "$q_vanish")" in *'attention row is gone'*) ;; *) fail "the vanished row is not the reason" ;; esac
echo "ok: a vanished content home and a vanished attention row each settle with that reason, logged"

# --- an unreachable source is logged, settles nothing, and holds the re-knock ------

r_hold=$(add_req r-hold pr:77 1500) || fail "add r-hold"
evidence "stamp${TAB}1501" "unavailable${TAB}github"
out=$(run settle --evidence "$ev" --now 1510) || fail "the pass exited non-zero over an unavailable source"
printf '%s\n' "$out" | grep -q "^unavailable${TAB}github$" || fail "the pass did not report the unavailable source: '$out'"
[ "$(state_of "$r_hold")" = open ] || fail "a source reporting nothing because it was unreachable settled an item"
grep -q '"kind":"unavailable".*"source":"github"' "$log_file" || fail "the unavailable source was not logged"
[ -f "$surface/reknock.hold" ] || fail "no re-knock hold while an evidence source is down"
grep -q '^github$' "$surface/reknock.hold" || fail "the re-knock hold does not name the source"

evidence "stamp${TAB}1502"
run settle --evidence "$ev" --now 1520 >/dev/null || fail "the pass exited non-zero once the source answered"
[ ! -f "$surface/reknock.hold" ] || fail "the re-knock hold outlived the outage"
echo "ok: an unreachable source is logged as unavailable, settles nothing, and holds the worsening re-knock"

# --- level-triggered: a condition met before the last pass still settles ----------

evidence "stamp${TAB}1600" "pr${TAB}50${TAB}merged"
run settle --evidence "$ev" --now 1610 >/dev/null || fail "the first pass over pr 50"
r_late=$(add_req r-late pr:50 1620) || fail "add r-late"
# The same evidence file, untouched: nothing happened since, and the pass has
# to read the condition rather than the events after it.
run settle --evidence "$ev" --now 1630 >/dev/null || fail "the second pass over the same evidence"
[ "$(state_of "$r_late")" = closed ] || fail "the pass replayed events instead of re-reading the condition"
echo "ok: the pass is level-triggered — an already-met condition settles on a later pass with no new event"

# --- one pass per iteration: the next that follows reuses it ---------------------

A=tower-a
evidence "stamp${TAB}1700" "pr${TAB}60${TAB}merged"
run settle --evidence "$ev" --now 1710 >/dev/null || fail "the iteration's pass"
r_reuse=$(add_req r-reuse pr:60 1720) || fail "add r-reuse"
run next --tower $A --evidence "$ev" --now 1730 >/dev/null || fail "next after the pass"
[ "$(state_of "$r_reuse")" = open ] || fail "next ran a second settling pass against evidence the iteration had already run"
evidence "stamp${TAB}1800" "pr${TAB}60${TAB}merged"
run next --tower $A --evidence "$ev" --now 1810 >/dev/null || fail "next against fresh evidence"
[ "$(state_of "$r_reuse")" = closed ] || fail "next did not settle against evidence no pass had seen"
echo "ok: one settling pass serves the iteration, and the next that follows reuses it"

# --- what the reuse key covers: the attention store, not just the stamp -----------

# The claim lands after the iteration's pass, with the evidence table untouched.
# Reusing on the table's stamp alone would put an answered question in front of
# the operator and leave it there until the facts were next re-derived.
attention_row w-reuse /wt/reuse awaiting-input 1900 normal 'go ahead?' yes 'yes,no'
q_reuse=$(run add --kind question --worker w-reuse --origin w-reuse --closes 'the operator answers' --now 1900) \
  || fail "add the w-reuse question"
evidence "stamp${TAB}1900"
run settle --evidence "$ev" --now 1910 >/dev/null || fail "the pass before the claim"
[ "$(state_of "$q_reuse")" = open ] || fail "the question settled before anything answered it"
drop_row w-reuse
attention_row w-reuse /wt/reuse awaiting-input 1900 normal 'go ahead?' yes 'yes,no' '' '' yes
run next --tower $A --evidence "$ev" --now 1920 >/dev/null || fail "next after the claim"
[ "$(state_of "$q_reuse")" = closed ] || fail "next reused a pass taken before the claim and left the answered question open"
echo "ok: a claim arriving after the iteration's pass is settled by the next verb, not carried to the operator"

# A worker returning to its fork is the same staleness through the merge half:
# the pass left the pair unmerged because one of them was not answerable then,
# and reusing it would hand the operator both copies of one question.
attention_row w-back /wt/back awaiting-input 1930 normal 'deploy it?' yes 'yes,no'
attention_row w-mate /wt/mate awaiting-input 1930 normal 'deploy it?' yes 'yes,no'
q_back=$(run add --kind question --worker w-back --origin w-back --closes 'the operator answers' --now 1930) \
  || fail "add the w-back question"
q_mate=$(run add --kind question --worker w-mate --origin w-mate --closes 'the operator answers' --now 1931) \
  || fail "add the w-mate question"
drop_row w-back
attention_row w-back /wt/back working 1930 normal 'deploy it?' yes 'yes,no'
evidence "stamp${TAB}1930"
run settle --evidence "$ev" --now 1940 >/dev/null || fail "the pass while one of the pair was away from its fork"
[ "$(state_of "$q_back")" = open ] && [ "$(state_of "$q_mate")" = open ] \
  || fail "the pair merged while one of them was not answerable"
drop_row w-back
attention_row w-back /wt/back awaiting-input 1930 normal 'deploy it?' yes 'yes,no'
run next --tower $A --evidence "$ev" --now 1950 >/dev/null || fail "next after the worker came back"
[ "$(state_of "$q_back")" = closed ] || [ "$(state_of "$q_mate")" = closed ] \
  || fail "next reused a pass taken while the fork was unanswerable and left the operator two copies"
echo "ok: a worker returning to its fork is a pass the reuse key has not seen, so the duplicate still merges"

# An attention store that comes back empty reads nothing like one that is gone:
# gone holds the away re-knock, back-and-empty says every row has answered. Both
# contribute no rows, so the key has to say which of the two it saw.
attention_row w-gone /wt/gone awaiting-input 1960 normal 'still there?' yes 'yes,no'
q_gone=$(run add --kind question --worker w-gone --origin w-gone --closes 'the operator answers' --now 1960) \
  || fail "add the w-gone question"
rm -f "$attn_store"
evidence "stamp${TAB}1960"
run settle --evidence "$ev" --now 1970 >/dev/null || fail "the pass with the attention store gone"
[ "$(state_of "$q_gone")" = open ] || fail "a gone attention store closed its question instead of holding"
[ -f "$surface/reknock.hold" ] || fail "a gone attention store did not hold the re-knock"
mkdir -p "$attn_dir"
chmod 0700 "$attn_dir"
: >"$attn_store"
chmod 0600 "$attn_store"
run next --tower $A --evidence "$ev" --now 1980 >/dev/null || fail "next after the attention store came back empty"
[ "$(state_of "$q_gone")" = closed ] || fail "next reused a pass taken while the store was gone and never saw the row vanish"
[ ! -f "$surface/reknock.hold" ] || fail "the re-knock hold outlived the store coming back"
echo "ok: a gone attention store and one that returns empty are different passes to the reuse key"

# --- settled while the operator was away is recorded as such (REQ-B1.4) ----------

printf 'tower_quiet_interval: 100s\ntower_lease_interval: 200s\n' >"$local_cfg"
r_away=$(add_req r-away pr:70 1900) || fail "add r-away"
evidence "stamp${TAB}1901" "pr${TAB}70${TAB}merged"
run settle --evidence "$ev" --now 1910 >/dev/null || fail "the away pass"
[ "$(away_of "$r_away")" = 1 ] || fail "an item settled with nobody present was not recorded as settled while away"

mkdir -p "$surface/attention"
chmod 0700 "$surface/attention"
printf '2000\n' >"$surface/attention/$A"
chmod 0600 "$surface/attention/$A"
r_here=$(add_req r-here pr:71 2000) || fail "add r-here"
evidence "stamp${TAB}2001" "pr${TAB}71${TAB}merged"
run settle --evidence "$ev" --now 2010 >/dev/null || fail "the present pass"
[ "$(away_of "$r_here")" = 0 ] || fail "an item settled while the operator was replying was recorded as away"
echo "ok: an item settled while the operator was away is recorded as such, and one settled while they were present is not"

# --- nothing is dropped or auto-answered for lack of attention (REQ-F1.4) ---------

rm -f "$surface/attention/$A"
r_open1=$(add_req r-open1 - 2100) || fail "add r-open1"
r_open2=$(add_req r-open2 pr:900 2100) || fail "add r-open2"
before=$(cut -f 1 "$store" | sort)
evidence "stamp${TAB}2101"
i=0
while [ "$i" -lt 6 ]; do
  run settle --evidence "$ev" --now $((2200 + i * 100)) >/dev/null || fail "the away timeline's pass $i"
  i=$((i + 1))
done
[ "$(state_of "$r_open1")" = open ] || fail "an item with no evidence was closed over a long away timeline"
[ "$(state_of "$r_open2")" = open ] || fail "an item whose evidence never arrived was closed over a long away timeline"
[ "$(cut -f 1 "$store" | sort)" = "$before" ] || fail "the away timeline dropped or added records"
echo "ok: over a long timeline with no operator reply every item stays open or evidence-settled, none answered or dropped"

# --- a delivered item is not a decided one (REQ-B1.5) ----------------------------

printf '2800\n' >"$surface/attention/$A"
chmod 0600 "$surface/attention/$A"
run next --tower $A --evidence "$ev" --now 2801 >/dev/null || fail "the knock before the mention case"
printf '2802\n' >"$surface/attention/$A"
chmod 0600 "$surface/attention/$A"
out=$(run next --tower $A --evidence "$ev" --now 2803) || fail "the hand-over for the mention case exited non-zero"
handed=$(printf '%s\n' "$out" | awk -F "$TAB" '$1 == "item" { print $2; exit }')
[ -n "$handed" ] || fail "nothing was handed over for the mention case"
run settle --evidence "$ev" --now 2804 >/dev/null || fail "the pass after the hand-over"
[ "$(state_of "$handed")" = open ] || fail "an item that was only mentioned in a turn was treated as decided"
echo "ok: an item delivered but not acknowledged stays open across a later pass"

# --- an item settled under a tower that was holding it records that (REQ-B1.4) ----

# High urgency puts it at the top, so the reply after the last hand-over
# releases this item and no other.
held=$(add_req r-held pr:80 2850 high) || fail "add r-held"
printf '2851\n' >"$surface/attention/$A"
chmod 0600 "$surface/attention/$A"
out=$(run next --tower $A --evidence "$ev" --now 2852) || fail "the held case's hand-over exited non-zero"
handed=$(printf '%s\n' "$out" | awk -F "$TAB" '$1 == "item" { print $2; exit }')
[ "$handed" = "$held" ] || fail "the held case's item was not the one handed over: '$handed'"
[ "$(rec "$held" | cut -f 19)" = "$A" ] || fail "the held case's item was not leased to $A"
evidence "stamp${TAB}2855" "pr${TAB}80${TAB}merged"
run settle --evidence "$ev" --now 2860 >/dev/null || fail "the pass over a leased item"
[ "$(state_of "$held")" = closed ] || fail "settling deferred to a leaseholder instead of the evidence"
[ "$(rec "$held" | cut -f 24)" = "$A" ] || fail "the item does not record the tower that was holding it when it settled"
grep -q "\"kind\":\"settled\".*\"item\":\"$held\".*\"held_by\":\"$A\"" "$log_file" || fail "the holder was not logged with the settle"
out=$(run catchup --since 2856 --now 2900) || fail "catchup over the held item"
[ "$(printf '%s\n' "$out" | awk -F "$TAB" -v i="$held" '$1 == "settled" && $2 == i { print $9 }')" = "$A" ] \
  || fail "catchup does not say which conversation was holding the item when it settled"
echo "ok: settling stays evidence-driven over a live lease, and the catch-up says who was holding it"

# --- the default evidence path, which is what the tower loop actually uses ---------

r_def=$(add_req r-def pr:88 3100) || fail "add r-def"
run settle --now 3110 >/dev/null || fail "the pass with no --evidence and no table exited non-zero"
[ "$(state_of "$r_def")" = open ] || fail "the pass settled an item with no evidence at all"
printf 'stamp\t3111\npr\t88\tmerged\n' >"$surface/evidence"
chmod 0600 "$surface/evidence"
run settle --now 3120 >/dev/null || fail "the pass over the default evidence table exited non-zero"
[ "$(state_of "$r_def")" = closed ] || fail "the pass did not read <surface>/evidence when given no --evidence"
rm -f "$surface/evidence"
rc=0
run settle --evidence "$tmp/no-such-table" --now 3130 >/dev/null || rc=$?
[ "$rc" = 2 ] || fail "a named evidence table that does not exist: exit $rc, expected 2"
echo "ok: the pass reads <surface>/evidence by default and refuses a named table that is not there"

# The evidence table the pass normalises for itself is scratch, and the tower
# loop reaches the pass on every iteration: one file left behind per pass grows
# without bound inside the sub-surface.
leftover=$(find "$surface" -maxdepth 1 -name '.*' -type f | wc -l | tr -d ' ')
[ "$leftover" = 0 ] || fail "the settling pass left $leftover scratch file(s) on the surface: $(find "$surface" -maxdepth 1 -name '.*' -type f)"
echo "ok: the pass leaves no scratch file behind on the sub-surface"

# --- a rebuild never leaves the operator two copies of one question ---------------

attention_row w-m1 /wt/m1 awaiting-input 3200 normal 'ship it?' yes 'yes,no'
attention_row w-m2 /wt/m2 awaiting-input 3200 normal 'ship  it?' yes 'YES,no'
m1=$(run add --kind question --worker w-m1 --origin w-m1 --closes 'the operator answers' --now 3200) || fail "add m1"
m2=$(run add --kind question --worker w-m2 --origin w-m2 --closes 'the operator answers' --now 3200) || fail "add m2"
run settle --now 3210 >/dev/null || fail "the merging pass before the rebuild"
gone=$m1
[ "$(state_of "$m1")" = closed ] || gone=$m2
[ "$(state_of "$gone")" = closed ] || fail "the duplicates did not merge before the rebuild"
# Both workers are still awaiting input, so both rows re-attest an open
# question and the rebuild is right to register them again — the settling
# reason is the store's alone and does not survive it. What must hold is that
# the operator is still never handed two copies: the next pass re-merges.
rm -f "$store"
printf 'rebuild probe\n' >"$content/r-probe"
run add --kind request --root "$content" --pointer r-probe --origin operator \
  --closes 'the operator decides' --now 3220 >/dev/null || fail "the add that rebuilds the store"
[ -n "$(rec "$m1")" ] && [ -n "$(rec "$m2")" ] || fail "the rebuild lost a still-blocked worker's question"
run settle --now 3230 >/dev/null || fail "the pass after the rebuild"
open_dupes=0
for id in $m1 $m2; do
  [ "$(state_of "$id")" != open ] || open_dupes=$((open_dupes + 1))
done
[ "$open_dupes" = 1 ] || fail "after a rebuild the duplicates left $open_dupes open copies, expected 1"
echo "ok: a rebuild re-registers both still-blocked workers and the next pass merges them back to one"

# --- the fleet lock's hold over a large fixture stays inside the stated bound ------

: >"$store"
chmod 0600 "$store"
i=0
{
  while [ "$i" -lt 400 ]; do
    printf 'i%08x\trequest\tnormal\toperator\t4000\tpath\tbig\t-\t%s\t-\tthe operator decides\topen\t0\t0\t0\t0\t0\t-\t-\t0\tpr:%d\t0\t-\t-\n' \
      "$i" "$content" "$i"
    i=$((i + 1))
  done
} >>"$store"
printf 'big\n' >"$content/big"
evidence "stamp${TAB}4001" "pr${TAB}7${TAB}merged" "pr${TAB}11${TAB}merged" "pr${TAB}23${TAB}merged"
printf 'tower_catchup_limit: 500\n' >"$local_cfg"
out=$(run settle --evidence "$ev" --now 4100) || fail "the pass over the large fixture exited non-zero"
held=$(printf '%s\n' "$out" | awk -F "$TAB" '$1 == "held" { print $2 }')
case "$held" in
  '' | *[!0-9.]*) fail "the pass printed no usable held line: '$held'" ;;
esac
awk -v h="$held" 'BEGIN { exit (h < 2) ? 0 : 1 }' || fail "the settling pass held the fleet lock ${held}s over a 400-record fixture, past the 2s bound"
[ "$(printf '%s\n' "$out" | grep -c "^settled${TAB}" || true)" = 3 ] || fail "the large fixture settled the wrong number of items"
: >"$local_cfg"
echo "ok: the fleet lock's hold over a 400-record fixture stays inside the stated bound (${held}s)"

# --- a stamp the pass cannot write does not swallow what it settled ---------------

# The store commits before `reknock.hold` and `settle.stamp` are published, so a
# failure there is reported as a 6 over settlements that already stand. They have
# to reach stdout and the event log anyway: catch-up counts its remainder from
# the log, and a settlement missing there is one the operator is never told about.
: >"$store"
chmod 0600 "$store"
r_pub=$(add_req r-pub pr:88 5000) || fail "add r-pub"
evidence "stamp${TAB}5001" "pr${TAB}88${TAB}merged"
rm -f "$surface/settle.stamp"
mkdir -p "$surface/settle.stamp"
rc=0
out=$(run settle --evidence "$ev" --now 5100) || rc=$?
rmdir "$surface/settle.stamp" || fail "the test could not undo the unwritable stamp"
[ "$rc" = 6 ] || fail "an unwritable settle stamp did not report 6: exit $rc"
[ "$(state_of "$r_pub")" = closed ] || fail "the settlement did not commit before the stamp write"
printf '%s\n' "$out" | grep -q "^settled${TAB}$r_pub${TAB}" || fail "the settlement never reached stdout: '$out'"
grep -q "\"kind\":\"settled\"" "$log_file" || fail "the settlement never reached the event log"
grep -q "\"item\":\"$r_pub\"" "$log_file" || fail "the event log does not name the settled item"
echo "ok: a settlement the pass committed is printed and logged even when the stamp write then fails"

# --- a hand-over is never swallowed by the stamp write that follows it ------------

# `next` commits the lease and the delivery record before it publishes the
# settling pass's two files. A failure there is still this verb's 6, but the
# item line has to go out first: the tower now holds the item, and a 6 with no
# hand-over hides it from its own holder until the lease backstop, which is the
# outcome the record-first order exists to prevent.
: >"$store"
chmod 0600 "$store"
r_hand=$(add_req r-hand pr:90 5400) || fail "add r-hand"
evidence "stamp${TAB}5401"
printf '5410\n' >"$surface/attention/$A"
chmod 0600 "$surface/attention/$A"
run next --tower $A --evidence "$ev" --now 5411 >/dev/null || fail "the knock for r-hand"
printf '5412\n' >"$surface/attention/$A"
rm -f "$surface/settle.stamp"
mkdir -p "$surface/settle.stamp"
rc=0
out=$(run next --tower $A --evidence "$ev" --now 5413) || rc=$?
rmdir "$surface/settle.stamp" || fail "the test could not undo the unwritable stamp"
[ "$rc" = 6 ] || fail "an unwritable settle stamp did not report 6 from next: exit $rc"
printf '%s\n' "$out" | grep -q "^item${TAB}$r_hand${TAB}" || fail "the hand-over was swallowed by the stamp failure: '$out'"
[ "$(rec "$r_hand" | cut -f 19)" = "$A" ] || fail "the item was not actually leased, so the assertion above proves nothing"
grep -q "\"kind\":\"delivered\"" "$log_file" || fail "the hand-over was never logged"
echo "ok: a hand-over that committed is printed and logged before a failed stamp write becomes the exit"

echo "PASS: tower-queue settling pass"
