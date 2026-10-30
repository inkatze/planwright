#!/bin/bash
# Tests for scripts/tower-queue.sh's decided-by-mission-control items and the
# rebuild of the reviewable kinds: who may add one (the launcher registry, never
# a presence record), its grounds, reversal and gate, `ack` closing it as
# reviewed, `revoke` closing it as revoked, retention keeping it while
# unreviewed, and a deleted store rebuilding both reviewable kinds and every
# picklist from the event log (tower-comms REQ-A1.10, REQ-A1.13, REQ-A1.14,
# REQ-B1.6, REQ-B1.7, REQ-B1.8, REQ-G1.9, REQ-H1.5).
#
# Runs standalone under /bin/bash (the bash 3.2 floor).
set -eu
LC_ALL=C
export LC_ALL
unset CDPATH

here=$(cd "$(dirname "$0")" && pwd)
TQ="$here/../scripts/tower-queue.sh"
MCL="$here/../scripts/mission-control-launch.sh"
FIX="$here/fixtures/tower-comms"

errf=""

fail() {
  echo "FAIL: $1" >&2
  if [ -n "${errf:-}" ] && [ -s "$errf" ]; then
    echo "--- stderr of the last run ---" >&2
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

TAB=$(printf '\t')
MC=mc-fixture-mission-control-0a1b2c3d4e
PLAIN=mc-fixture-tower-5f6a7b8c9d

run() {
  : >"$errf"
  PLANWRIGHT_FLEET_STATE_DIR="$home" \
    PLANWRIGHT_ADOPTER_OVERLAY="$adopter" \
    PLANWRIGHT_REPO_ROOT=none \
    PLANWRIGHT_LOCAL_CONFIG="$local_cfg" \
    /bin/sh "$TQ" "$@" 2>"$errf"
}

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

marker() {
  mkdir -p "$surface/attention"
  chmod 0700 "$surface/attention"
  printf '%s\n' "$2" >"$surface/attention/$1"
  chmod 0600 "$surface/attention/$1"
}

rec() { grep "^$1$TAB" "$store" || true; }
fld() { rec "$1" | cut -f "$2"; }

# The token a mission-control session holds: the launcher exports its
# registry row's token into the session, and `add` compares the two.
MC_TOKEN=100-fixture-mc
decide() { # decide <caller> <text> [<flag>...] — a decided-by-mission-control add
  _c=$1
  _t=$2
  shift 2
  PLANWRIGHT_MC_TOKEN=$MC_TOKEN run add --kind decided-by-mission-control --origin mission-control --tower "$_c" --text "$_t" "$@"
}

# A tmux stub listing the windows in $TMUX_WINDOWS: the fixture rows name
# tmux windows, and a row whose window is not listed is a dead session.
mkdir -p "$tmp/bin"
cat >"$tmp/bin/tmux" <<'STUB'
case $1 in
  list-windows) cat "$TMUX_WINDOWS" 2>/dev/null ;;
  *) exit 1 ;;
esac
STUB
chmod +x "$tmp/bin/tmux"
PATH="$tmp/bin:$PATH"
TMUX_WINDOWS="$tmp/windows"
export PATH TMUX_WINDOWS
printf '@7\n@8\n' >"$TMUX_WINDOWS"

refused() { # refused <what> <the refusal's reason> <command...>
  _w=$1
  _why=$2
  shift 2
  _before=$(cat "$store" 2>/dev/null || true)
  _rc=0
  "$@" >/dev/null || _rc=$?
  [ "$_rc" = 2 ] || fail "$_w: exit $_rc, expected 2"
  [ "$(cat "$store" 2>/dev/null || true)" = "$_before" ] || fail "$_w: the store changed"
  grep -qF -- "$_why" "$errf" || fail "$_w: refused for another reason than '$_why'"
}

# The launcher registry, from the committed fixture rows standing in for
# mission-control Task 3's (one mission-control session, one plain tower).
reg="$home/mission-control/sessions"
mkdir -p "$reg"
chmod 0700 "$home/mission-control" "$reg"
cp "$FIX/registry-mission-control.row" "$reg/$MC"
cp "$FIX/registry-tower.row" "$reg/$PLAIN"

printf 'seed request\n' >"$content/seed"
seed=$(run add --kind request --root "$content" --pointer seed --origin operator --closes 'the operator decides' --now 900) || fail "seed the store"
run settle "$seed" --reason 'the seed is not under test' --now 901 >/dev/null || fail "settle the seed"

# --- who may add a decided-by-mission-control item (REQ-A1.14) --------------------------

ok_flags="--grounds undo:u-17 --reversal undo:u-17 --gate none --now 1000"
# shellcheck disable=SC2086
refused "a caller the registry records as a plain tower" 'launcher registry records no launched mission-control' decide "$PLAIN" 'retried the flaky job' $ok_flags
# A presence record claiming the kind, with no registry row behind it.
mkdir -p "$home/presence/p1"
printf 'kind\tmission-control\n' >"$home/presence/p1/mc-fixture-claimed-1234567890"
# shellcheck disable=SC2086
refused "a caller with a presence record and no registry row" 'launcher registry records no launched mission-control' decide mc-fixture-claimed-1234567890 'retried the flaky job' $ok_flags
MC_TOKEN=100-fixture-other
# shellcheck disable=SC2086
refused "a token that is not the row's" 'does not match' decide "$MC" 'retried the flaky job' $ok_flags
MC_TOKEN=""
# shellcheck disable=SC2086
refused "no token at all" 'does not match' decide "$MC" 'retried the flaky job' $ok_flags
MC_TOKEN=100-fixture-mc
printf '@8\n' >"$TMUX_WINDOWS"
# shellcheck disable=SC2086
refused "a row whose session is gone" 'is not running' decide "$MC" 'retried the flaky job' $ok_flags
printf '@7\n@8\n' >"$TMUX_WINDOWS"
refused "no reversal field" 'needs --reversal' decide "$MC" 'retried the flaky job' --grounds undo:u-17 --gate none --now 1000
refused "no grounds pointer" 'needs --grounds' decide "$MC" 'retried the flaky job' --reversal none --gate none --now 1000
refused "no gate field" 'needs --gate' decide "$MC" 'retried the flaky job' --grounds undo:u-17 --reversal none --now 1000
refused "a human gate" 'behind a human-gate' decide "$MC" 'retried the flaky job' --grounds undo:u-17 --reversal none --gate human-gate --now 1000
refused "a disqualifier zone" 'behind a disqualifier-zone' decide "$MC" 'retried the flaky job' --grounds undo:u-17 --reversal none --gate disqualifier-zone --now 1000
refused "a reserved control" 'on a reserved human control' decide "$MC" 'merged PR 12 once green' --grounds undo:u-18 --reversal none --gate none --now 1000
attention_row w-perm spec/t1 awaiting-input 1000 high 'Allow the command?' - - permission iid-p - 'npm test'
refused "a permission prompt" 'on a worker permission prompt' decide "$MC" 'allowed the test run' --subject worker:w-perm --grounds undo:u-19 --reversal none --gate none --now 1000
echo "ok: a decided-by-mission-control add is refused from a plain tower, from a presence claim, with another token or none, from a dead row, and without its grounds, reversal or gate, behind a gate, or on a reserved control or permission prompt"

# shellcheck disable=SC2086
d1=$(decide "$MC" 'retried the flaky job' --subject pr:88 $ok_flags) || fail "the add from the mission-control registry row was refused"
[ "$(fld "$d1" 2)" = decided-by-mission-control ] && [ "$(fld "$d1" 12)" = open ] || fail "the decision is not an open item: $(rec "$d1")"
[ "$(fld "$d1" 33)" = undo:u-17 ] && [ "$(fld "$d1" 34)" = undo:u-17 ] && [ "$(fld "$d1" 30)" = none ] || fail "the record lost its grounds, reversal or gate"
grep -q "retried the flaky job" "$surface/ledger" || fail "the decision's content is not in the ledger fallback"
grep -q "\"kind\":\"born\".*\"item\":\"$d1\".*\"item_kind\":\"decided-by-mission-control\".*\"grounds\":\"undo:u-17\".*\"reversal\":\"undo:u-17\"" "$log_file" \
  || fail "the decided-by-mission-control birth was not logged with its grounds and reversal"
run list | grep -q "^$d1${TAB}decided-by-mission-control${TAB}" || fail "list does not print the decision"
run counts | grep -q "^decided-by-mission-control${TAB}1$" || fail "counts does not count the decision"
# Evidence never closes a reviewable item: only a review or a revocation does.
printf 'stamp\t1001\npr\t88\tmerged\n' >"$tmp/ev"
chmod 0600 "$tmp/ev"
run settle --evidence "$tmp/ev" --now 1002 >/dev/null || fail "the pass over the decision"
[ "$(fld "$d1" 12)" = open ] || fail "evidence closed a reviewable item"
rc=0
run settle "$d1" --reason 'evidence' --now 1003 >/dev/null || rc=$?
[ "$rc" = 1 ] || fail "settle <id> on a reviewable item: exit $rc, expected 1"
echo "ok: one from a mission-control registry row is accepted and listed, its content in the ledger, and evidence never closes it"

# Handed over for review, then acknowledged: closed as reviewed.
run next --tower t1 --now 1010 >/dev/null || fail "the knock"
marker t1 1011
out=$(run next --tower t1 --now 1012) || fail "the hand-over"
printf '%s\n' "$out" | grep -q "^item${TAB}$d1${TAB}decided-by-mission-control" || fail "the decision was not handed over for review: $out"
run ack "$d1" --tower t1 --now 1013 >/dev/null || fail "ack the decision"
[ "$(fld "$d1" 12)" = closed ] || fail "ack did not close the decision"
case "$(fld "$d1" 18)" in
  "reviewed by the operator (reversal: undo:u-17)") ;;
  *) fail "the review reason does not name the reversal: '$(fld "$d1" 18)'" ;;
esac
grep -q "\"kind\":\"reviewed\".*\"item\":\"$d1\".*\"reversal\":\"undo:u-17\"" "$log_file" || fail "the review was not logged"
grep -q "\"kind\":\"reviewed\".*\"item\":\"$d1\".*\"reason\":\"reviewed by the operator (reversal: undo:u-17)\"" "$log_file" || fail "the review log line carries no settling reason"
echo "ok: a decision is handed over for review and closes on ack as reviewed, logged with its reversal"

# Revoked: closed as revoked, the reversal pointer logged, nothing run.
d2=$(decide "$MC" 'paused the nightly sweep' --grounds undo:u-20 --reversal undo:u-20 --gate none --now 1100) || fail "add d2"
out=$(run revoke "$d2" --tower t1 --now 1101) || fail "revoke d2"
printf '%s\n' "$out" | grep -q "^revoked${TAB}$d2${TAB}decided-by-mission-control${TAB}undo:u-20" || fail "revoke printed '$out'"
[ "$(fld "$d2" 12)" = closed ] || fail "a revoked decision stayed open"
case "$(fld "$d2" 18)" in *"revoked by the operator (reversal: undo:u-20)"*) ;; *) fail "the revocation reason: '$(fld "$d2" 18)'" ;; esac
grep -q "\"kind\":\"revoked\".*\"item\":\"$d2\".*\"reversal\":\"undo:u-20\".*\"outcome\":\"revoked\"" "$log_file" || fail "the revocation was not logged with its reversal pointer"
grep -q "\"kind\":\"revoked\".*\"item\":\"$d2\".*\"reason\":\"revoked by the operator (reversal: undo:u-20)\"" "$log_file" || fail "the revocation log line carries no settling reason"
run catchup | grep -q "^settled${TAB}$d2${TAB}" && fail "the catch-up of what settled without the operator lists their own revocation"
run show "$d2" | grep -q "^reason${TAB}revoked by the operator (reversal: undo:u-20)${TAB}1101$" || fail "show does not date the revocation"
echo "ok: a revoked decision leaves the open set by that revocation, logged with its reversal pointer"

# --- the launcher registry accepts the mission-control kind ------------------------------

[ -f "$MCL" ] || fail "scripts/mission-control-launch.sh is missing, so its accepted kinds go unchecked"
PLANWRIGHT_FLEET_STATE_DIR="$home" /bin/sh "$MCL" kinds | grep -q "^mission-control${TAB}" || fail "the launcher does not list the mission-control kind"
PLANWRIGHT_FLEET_STATE_DIR="$home" /bin/sh "$MCL" name --program fixture --kind mission-control --scope fleet >/dev/null 2>&1 \
  || fail "the launcher refused the mission-control kind"
rc=0
PLANWRIGHT_FLEET_STATE_DIR="$home" /bin/sh "$MCL" name --program fixture --kind overseer --scope fleet >/dev/null 2>&1 || rc=$?
[ "$rc" = 2 ] || fail "the launcher accepted an unknown kind (exit $rc)"
echo "ok: the launcher registry accepts a mission-control row and still refuses an unknown kind"

# --- retention keeps an unreviewed reviewable item past the horizon (REQ-B1.6) ----------

printf 'tower_catchup_limit: 1\n' >"$local_cfg"
d3=$(decide "$MC" 'rotated the logs' --grounds undo:u-21 --reversal none --gate none --now 1200) || fail "add d3"
i=0
while [ "$i" -lt 4 ]; do
  printf 'filler %s\n' "$i" >"$content/f$i"
  f=$(run add --kind request --root "$content" --pointer "f$i" --origin operator --closes 'the operator decides' --now $((1300 + i))) || fail "add filler $i"
  run settle "$f" --reason "filler $i" --now $((99000 + i)) >/dev/null || fail "settle filler $i"
  i=$((i + 1))
done
[ "$(awk -F "$TAB" '$12 == "closed"' "$store" | grep -c .)" -le 1 ] || fail "the retention horizon did not trim the closed records"
[ "$(fld "$d3" 12)" = open ] || fail "an unreviewed reviewable item fell past the retention horizon"
: >"$local_cfg"
echo "ok: an unreviewed reviewable item older than the horizon is still in the store"

# --- a deleted store rebuilds both reviewable kinds and every picklist (REQ-A1.13) ------

attention_row w-sbd spec/t2 awaiting-input 2000 normal 'Squash or keep?' A 'A|B' fork iid-s
attention_row w-park spec/t3 awaiting-input 2000 normal 'Ship now?' - 'now|later' fork iid-k
attention_row w-rot spec/t4 awaiting-input 2000 normal 'Retry?' yes 'yes|no' fork iid-r
attention_row w-news spec/t5 pr-ready 2000 normal - - -
mkdir -p "$content" && printf "parked work\n" >"$content/sbd-park"
sbd=$(run add --kind question --worker w-sbd --origin w-sbd --closes 'the operator answers' --root "$content" --park sbd-park --options 'A|B' --end B --gate none --window 1s --now 2000) || fail "add sbd"
park=$(run add --kind question --worker w-park --origin w-park --closes 'the operator answers' --options 'now|later' --end park --window 1s --now 2000) || fail "add park"
rot=$(run add --kind question --worker w-rot --origin w-rot --closes 'the operator answers' --options 'yes|no' --end no --gate none --window 1h --now 2000) || fail "add rot"
news=$(run add --kind news --worker w-news --origin w-news --closes 'the operator has read it' --now 2000) || fail "add news"
run settle --now 2005 >/dev/null || fail "the pass ending both windows"
[ "$(fld "$sbd" 2)" = settled-by-default ] && [ "$(fld "$park" 31)" = 1 ] || fail "the windows did not end before the loss"
[ "$(fld "$sbd" 22)" = 1 ] || fail "the fixture needs the default applied while the operator was away: $(rec "$sbd")"
sbd_root=$(fld "$sbd" 9)
[ "$sbd_root" != - ] || fail "the fixture needs a question with a declared root"

# The loss: the store goes, the rot picklist's declaring line rotates out of
# the log, and the news row moves on.
rm -f "$store"
grep -v "\"kind\":\"picklist\".*\"item\":\"$rot\"" "$log_file" >"$tmp/log" && cat "$tmp/log" >"$log_file"
awk -F "$TAB" '$1 != "w-news"' "$attn_store" >"$tmp/attn" && cat "$tmp/attn" >"$attn_store"
printf 'w-news\tspec/t5\tmerged\t2010\tnormal\t-\t-\t-\n' >>"$attn_store"
run list >/dev/null || fail "list over the lost store"
run settle --now 2020 >/dev/null || fail "the rebuild"
grep -q 'rebuilt' "$errf" || fail "the rebuild was not announced"

[ "$(fld "$sbd" 2)" = settled-by-default ] && [ "$(fld "$sbd" 12)" = open ] || fail "the settled-by-default item did not come back awaiting review: $(rec "$sbd")"
[ "$(fld "$sbd" 17)" = 2001 ] || fail "the rebuilt default lost its window end time"
[ "$(fld "$sbd" 22)" = 1 ] || fail "the rebuilt default forgot it was applied while the operator was away"
[ "$(fld "$sbd" 9)" = "$sbd_root" ] || fail "the rebuilt default lost the root its park path is relative to: $(rec "$sbd")"
case "$(fld "$sbd" 18)" in *"default: B"*) ;; *) fail "the rebuilt default lost its reason" ;; esac
[ "$(fld "$d3" 2)" = decided-by-mission-control ] && [ "$(fld "$d3" 12)" = open ] || fail "the unreviewed decision did not come back awaiting review"
[ "$(fld "$d3" 33)" = undo:u-21 ] && [ "$(fld "$d3" 34)" = none ] || fail "the rebuilt decision lost its grounds or reversal"
rec "$d1" | grep -q . && fail "the reviewed decision came back"
rec "$d2" | grep -q . && fail "the revoked decision came back"
[ "$(fld "$park" 31)" = 1 ] && [ "$(fld "$park" 28)" = park ] || fail "the parked question lost its park"
[ "$(fld "$rot" 2)" = question ] && [ "$(fld "$rot" 28)" = - ] && [ "$(fld "$rot" 29)" = 0 ] \
  || fail "a picklist whose declaring line rotated out did not come back as a plain question: $(rec "$rot")"
[ "$(fld "$news" 12)" = closed ] || fail "the news item whose row moved on was not recorded as settled"
case "$(fld "$news" 18)" in *"moved on (merged)"*) ;; *) fail "the moved-on item carries no reason: '$(fld "$news" 18)'" ;; esac
run settle --now 9000 >/dev/null || fail "a pass long after the rebuild"
[ "$(fld "$rot" 2)" = question ] || fail "a loss added a default: the rotated picklist defaulted"
echo "ok: a deleted store rebuilds the reviewable items awaiting review, picklists from the log, a rotated one as plain, and a moved-on row as settled"

awk -F "$TAB" '$12 == "closed" && ($18 == "-" || $18 == "") { print; bad = 1 } END { exit bad }' "$store" \
  || fail "a closed record carries no settling reason"
echo "ok: every closed record carries its settling reason"

# --- a ledger that will not read costs only the defaults it holds ----------------------

chmod 0000 "$surface/ledger"
rm -f "$store"
rc=0
run settle --now 9100 >/dev/null || rc=$?
chmod 0600 "$surface/ledger"
[ "$rc" = 0 ] || fail "an unreadable ledger failed the rebuild: exit $rc"
grep -q 'the ledger would not read' "$errf" || fail "the unreadable ledger was not reported"
[ "$(fld "$sbd" 2)" = question ] && [ "$(fld "$sbd" 28)" = - ] || fail "a default came back without its review content: $(rec "$sbd")"
[ "$(fld "$d3" 2)" = decided-by-mission-control ] || fail "an unreadable ledger cost an item it does not decide: $(rec "$d3")"
echo "ok: an unreadable ledger rebuilds its defaults as plain questions and everything else as before"
