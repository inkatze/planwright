#!/bin/bash
# Tests for scripts/mc-handover.sh — mission control's succession, from the
# trigger to the resume (mission-control REQ-A1.1, REQ-A1.7, REQ-B1.7,
# REQ-L1.3, REQ-L1.5, REQ-L1.6). Successors launch on the stream-json rung
# against a CLI shim that reads its first message and exits, so each
# registry row is real and each retire goes through the launcher.
#
# Runs standalone under /bin/bash (the bash 3.2 floor).
# shellcheck disable=SC2015 # ok only prints, so a fail arm never follows a passing check
set -u
LC_ALL=C
export LC_ALL
unset CDPATH

here=$(cd "$(dirname "$0")" && pwd)
repo_root=$(cd "$here/.." && pwd -P)

failures=0
fail() {
  echo "FAIL: $1" >&2
  failures=$((failures + 1))
}
ok() { echo "ok: $1"; }
tab=$(printf '\t')
suite=test-mc-handover

# shellcheck source=tests/lib/mc-handover-fixture.sh
. "$here/lib/mc-handover-fixture.sh"
# shellcheck source=tests/lib/emitter-lint.sh
. "$here/lib/emitter-lint.sh"

run mc-rules.sh add alpha --text "Never hand the operator a pane" --subject panes --source "operator, fixture" --date 2026-10-26
[ "$RC" = 0 ] || fail "fixture: the rule was not added: $ERR"
run mc-kb.sh init --program alpha
[ "$RC" = 0 ] || fail "fixture: the knowledge base was not initialised: $ERR"
run mc-rules.sh load alpha
digest=$(printf '%s\n' "$OUT" | sed -n 's/.*, digest \([0-9a-f]*\) -->.*/\1/p' | head -n 1)
[ "${#digest}" = 64 ] || fail "fixture: no rules digest from the load: $OUT"
printf '%s\n' "item q-1" "session mc-worker-1" >"$tmp/picture"
printf '%s\n' "item q-1" >"$tmp/picture-short"
: >"$tmp/empty"

# ---------------------------------------------------------------------------
# REQ-L1.3, REQ-L1.5: each trigger source fires from its fixture; the
# compaction ceiling fires whatever the other two read.
# ---------------------------------------------------------------------------
ho due --program alpha --context 70 --wakes 0 --compactions 0
[ "$OUT" = "due${tab}context at 70%" ] && ok "context at the threshold triggers the handover" || fail "context at 70: $OUT $ERR"
ho due --program alpha --context 69 --wakes 999 --compactions 0
[ "$OUT" = not-due ] && ok "a context reading below the threshold is not due, whatever the wakes" || fail "context at 69: $OUT"
ho due --program alpha --context - --wakes 150 --compactions 0
[ "$OUT" = "due${tab}150 wakes" ] && ok "with no context reading the wake count triggers it" || fail "150 wakes: $OUT $ERR"
ho due --program alpha --context - --wakes 149 --compactions 1
[ "$OUT" = not-due ] && ok "below every threshold it is not due" || fail "149 wakes: $OUT"
ho due --program alpha --context 5 --wakes 0 --compactions 2
[ "$OUT" = "due${tab}2 compactions" ] && ok "the compaction ceiling fires regardless of the other two" || fail "2 compactions: $OUT"

# ---------------------------------------------------------------------------
# A first start: no holder, so a plain launch runs and takes the name.
# ---------------------------------------------------------------------------
ho launch --program alpha --brief "$tmp/brief.md"
[ "$RC" = 0 ] || fail "the first launch exited $RC: $ERR"
n1=$(col successor 2)
wait_done "$n1"
grep -qF 'Run program alpha.' "$fleet/mission-control/launch/$n1/brief.md" \
  && grep -qF 'no handover file' "$fleet/mission-control/launch/$n1/brief.md" \
  && ok "the successor's brief carries the brief and its succession note" \
  || fail "the composed brief lacks the brief or the note"
grep -qF "planwright's defaults win over the predecessor's habits" "$fleet/mission-control/launch/$n1/brief.md" \
  && grep -qF 'mc-config.sh doctor --program alpha' "$fleet/mission-control/launch/$n1/brief.md" \
  && grep -qF 'each finding it prints that no operator choice already settles' "$fleet/mission-control/launch/$n1/brief.md" \
  && ok "the successor's brief puts planwright's defaults over inherited habits and names the audit" \
  || fail "the successor's brief does not put planwright's defaults first or name the audit"
ho verify --program alpha --session "$n1" --picture "$tmp/picture" --digest "$digest" --ledger - --durable "$tmp/picture"
[ "$RC" = 0 ] && ok "a first start verifies against the durable picture" || fail "the first verify exited $RC: $OUT $ERR"
ho take --program alpha --session "$n1" --window 1s
[ "$(col took 2)" = "$n1" ] && [ "$(col took 3)" = - ] && ok "the first start takes the name from nobody" || fail "the first take: $RC $OUT $ERR"
holder_is "the name resolves to the first session" "$n1"

# ---------------------------------------------------------------------------
# REQ-A1.1: a launch with neither the ask nor a live handover refuses,
# naming the holder.
# ---------------------------------------------------------------------------
ho launch --program alpha --brief "$tmp/brief.md"
[ "$RC" = 3 ] && ok "a second unattended start is refused (exit 3)" || fail "a second start exited $RC: $OUT"
case $ERR in *"held by $n1"*) ok "the refusal names the holder" ;; *) fail "the refusal does not name $n1: $ERR" ;; esac
ho launch --program alpha --brief "$tmp/brief.md" --handover
[ "$RC" = 3 ] && ok "a handover launch with no handover file is refused" || fail "a fileless handover exited $RC"
case $ERR in *"$n1"*) ok "that refusal names the holder too" ;; *) fail "the fileless refusal does not name $n1: $ERR" ;; esac
ho write --program alpha --session mc-not-holder --picture "$tmp/picture" --digest "$digest"
[ "$RC" = 1 ] && ok "only the holder writes the handover file" || fail "a non-holder's write exited $RC"

# ---------------------------------------------------------------------------
# REQ-L1.6: the handover file carries its format; a successor refuses one
# whose format it does not know; a failed self-check keeps the predecessor.
# ---------------------------------------------------------------------------
run mc-kb.sh append decisions --program alpha --subject fixture --act "merged nothing" --no-reversal
led1=$(printf '%s\n' "$OUT" | head -n 1)
ho write --program alpha --session "$n1" --picture "$tmp/picture" --digest "$digest"
[ "$RC" = 0 ] || fail "the holder's write exited $RC: $ERR"
hf="$home/handover.tsv"
[ "$(head -n 1 "$hf")" = "format${tab}1" ] && ok "the handover file opens with its format field" || fail "the file opens with '$(head -n 1 "$hf")'"
grep -qx "ledger${tab}$led1" "$hf" && grep -qx "predecessor${tab}$n1" "$hf" && grep -qx "item${tab}q-1" "$hf" \
  && grep -qx "session${tab}mc-worker-1" "$hf" \
  && ok "it records the last ledger sequence, the predecessor, the open items and the live sessions" || fail "the file is incomplete: $(cat "$hf")"
ho launch --program alpha --brief "$tmp/brief.md" --handover
[ "$RC" = 0 ] || fail "the handover launch exited $RC: $ERR"
grep -qF "the handover file is $hf" "$fleet/mission-control/launch/$(col successor 2)/brief.md" \
  && ok "the successor's brief names the handover file" || fail "the successor's brief lacks the handover file's path"
if lint_emitted markdown mc-handover.sh "$fleet/mission-control/launch/$(col successor 2)/brief.md"; then
  ok "the successor's brief with its Succession section lints clean as markdown"
else
  fail "the successor's brief fails the markdown lint"
fi
n2=$(col successor 2)
wait_done "$n2"
[ "$n2" != "$n1" ] && ok "the successor has a name of its own" || fail "the successor reused $n1"
ho launch --program alpha --brief "$tmp/brief.md" --handover
[ "$RC" = 3 ] && ok "a second successor is refused while one is pending" || fail "a second successor exited $RC"

cp "$hf" "$tmp/hf.keep"
{
  printf 'format\t9\n'
  tail -n +2 "$tmp/hf.keep"
} >"$hf"
ho verify --program alpha --session "$n2" --picture "$tmp/picture" --digest "$digest" --ledger "$led1"
[ "$RC" = 1 ] && ok "a handover file of an unknown format is refused" || fail "the unknown format exited $RC"
case $OUT in *"format field is 9"*) ok "the refusal names the format field" ;; *) fail "the refusal does not name the format: $OUT" ;; esac
cp "$tmp/hf.keep" "$hf"

before=$(count_of handover-failed)
ho verify --program alpha --session "$n2" --picture "$tmp/picture-short" --digest "$digest" --ledger "$led1"
[ "$RC" = 1 ] && ok "a self-check missing a live session fails" || fail "the short picture exited $RC: $OUT"
case $OUT in "item${tab}"*mc-worker-1*) ok "it prints the item naming what is missing" ;; *) fail "no item line names the session: $OUT" ;; esac
[ "$(count_of handover-failed)" = $((before + 1)) ] && ok "the failed self-check raises one operator item" || fail "the self-check failure raised no item"
other=$(printf '%064d' 0)
ho verify --program alpha --session "$n2" --picture "$tmp/picture" --digest "$other" --ledger "$led1"
[ "$RC" = 1 ] && ok "rules that are not the predecessor's fail the self-check" || fail "the digest mismatch exited $RC"
case $OUT in "item${tab}handover${tab}rules${tab}"*) ok "the item names the rules" ;; *) fail "no rules item: $OUT" ;; esac
ho verify --program alpha --session "$n2" --picture "$tmp/picture" --digest "$digest" --ledger -
[ "$RC" = 1 ] && ok "a ledger position behind the predecessor's last entry fails" || fail "the stale ledger exited $RC"
case $OUT in "item${tab}handover${tab}ledger${tab}"*) ok "the item names the ledger" ;; *) fail "no ledger item: $OUT" ;; esac
ho take --program alpha --session "$n2" --window 1s
[ "$RC" = 1 ] && ok "an unverified successor cannot take the name" || fail "an unverified take exited $RC"
holder_is "after the failed self-check the predecessor keeps the name" "$n1"
[ -f "$(rowfile "$n1")" ] && ok "and its registry row stays" || fail "the predecessor's row went"

# ---------------------------------------------------------------------------
# REQ-L1.6, REQ-A1.1: the predecessor releases after the successor's pass;
# the name moves, the predecessor's row goes, the successor announces.
# ---------------------------------------------------------------------------
ho verify --program alpha --session "$n2" --picture "$tmp/picture" --digest "$digest" --ledger "$led1"
[ "$RC" = 0 ] && ok "the successor's self-check matches the handover file" || fail "the matching verify exited $RC: $OUT $ERR"
case $OUT in *"temporary${tab}"*) fail "a clean local layer raised a drift line: $OUT" ;; *) ok "REQ-A1.9: a clean local layer surfaces no drift" ;; esac
printf '# interim: until the runner is rebuilt\nmission_control_stall_window: 20m\n' >"$tmp/absent.yml"
ho verify --program alpha --session "$n2" --picture "$tmp/picture" --digest "$digest" --ledger "$led1"
case $OUT in
  *"temporary${tab}$tmp/absent.yml${tab}mission_control_stall_window${tab}marker interim"*"verified${tab}$n2${tab}"*) [ "$RC" = 0 ] && ok "REQ-A1.9: the self-check surfaces a temporary local override and still passes" || fail "drift verify exited $RC" ;;
  *) fail "the self-check did not surface the temporary override before its verified line: $OUT $ERR" ;;
esac
rm -f "$tmp/absent.yml"
printf 'mission_control_launch_backend: tmux\nmission_control_stall_window: 20m\n' >"$tmp/absent.yml"
run mc-rules.sh add alpha --text "Set mission_control_repeat_window to 99m." --subject repeat --source "operator, fixture" --date 2026-10-26
[ "$RC" = 0 ] || fail "fixture: the drift rule was not added: $ERR"
run mc-rules.sh load alpha
digest_drift=$(printf '%s\n' "$OUT" | sed -n 's/.*, digest \([0-9a-f]*\) -->.*/\1/p' | head -n 1)
cp "$hf" "$tmp/hf.drift"
awk -F '\t' -v OFS='\t' -v d="$digest_drift" '$1 == "rules" { $2 = d } { print }' "$tmp/hf.drift" >"$hf"
ho verify --program alpha --session "$n2" --picture "$tmp/picture" --digest "$digest_drift" --ledger "$led1"
[ "$RC" = 0 ] || fail "the drift verify exited $RC: $OUT $ERR"
for kind in "override${tab}mission_control_stall_window" "duty-off${tab}" "launch-backend${tab}" "rule-knob${tab}r-2${tab}mission_control_repeat_window"; do
  case $OUT in
    *"$kind"*"verified${tab}$n2${tab}"*) ok "REQ-A1.9: the self-check surfaces a ${kind%%"$tab"*} finding before its verified line" ;;
    *) fail "the self-check did not surface $kind before its verified line: $OUT" ;;
  esac
done
rm -f "$tmp/absent.yml"
# A doctor that dies (its final awk fails here) must still read as a finding.
cat >"$tmp/bin/awk" <<'SHIM'
#!/bin/sh
if [ -e "${AWK_FAIL_FLAG:-/nonexistent}" ]; then
  case $* in *'\302'*) case $(ps -o args= -p "$PPID" 2>/dev/null) in *mc-config.sh*) exit 1 ;; esac ;; esac
fi
for a in /usr/bin/awk /bin/awk; do [ -x "$a" ] && exec "$a" "$@"; done
exit 127
SHIM
chmod +x "$tmp/bin/awk"
: >"$tmp/awk-fail"
AWK_FAIL_FLAG="$tmp/awk-fail"
export AWK_FAIL_FLAG
ho verify --program alpha --session "$n2" --picture "$tmp/picture" --digest "$digest_drift" --ledger "$led1"
unset AWK_FAIL_FLAG
rm -f "$tmp/awk-fail" "$tmp/bin/awk"
case $OUT in
  *"unknown${tab}doctor${tab}"*"verified${tab}$n2${tab}"*) ok "REQ-A1.9: a doctor that cannot run reads as a finding, never as clean" ;;
  *) fail "a failing doctor surfaced no finding: rc $RC $OUT $ERR" ;;
esac
cp "$tmp/hf.drift" "$hf"
run mc-rules.sh supersede alpha r-2 --withdraw --source "operator, fixture" --date 2026-10-27
[ "$RC" = 0 ] || fail "fixture: the drift rule was not withdrawn: $ERR"
run mc-rules.sh load alpha
[ "$(printf '%s\n' "$OUT" | sed -n 's/.*, digest \([0-9a-f]*\) -->.*/\1/p' | head -n 1)" = "$digest" ] || fail "fixture: the rules digest did not return after the drift rule was withdrawn"
pred_sid=11111111-2222-3333-4444-555555555555
other_sid=22222222-2222-3333-4444-555555555555
act="$fleet/mission-control/_panel/active"
for s in "$pred_sid" "$other_sid"; do
  RUN_SESSION=$s run mc-panel.sh activate --program alpha --session "$s" --now 1000
  RUN_SESSION=$s run mc-panel.sh ack --session "$s"
done
[ -f "$act/$pred_sid.ack" ] && [ -f "$act/$other_sid.ack" ] || fail "fixture: the activation records were not acknowledged: $ERR"
RUN_SESSION=$pred_sid ho release --program alpha --session "$n1"
[ "$RC" = 0 ] && [ "$(col released 3)" = "$n2" ] && ok "the predecessor releases the name to the verified successor" || fail "release: $RC $OUT $ERR"
# The predecessor ends itself: the release leaves its own mod the exit.
[ "$(col exit 2)" = mod ] && ok "the release says the predecessor's own mod ends its session" || fail "the release's exit line: $OUT"
[ -f "$act/$pred_sid.exit" ] && [ ! -e "$act/$pred_sid" ] && ok "the release leaves the predecessor's mod its exit marker" || fail "no exit marker after the release: $(ls "$act")"
[ -f "$act/$other_sid" ] && [ ! -e "$act/$other_sid.exit" ] && ok "and touches no other session's record" || fail "the release touched another session: $(ls "$act")"
fake_session
p2=$FAKE
ho take --program alpha --session "$n2" --window 5s --pid "$p2"
[ "$RC" = 0 ] || fail "the take exited $RC: $OUT $ERR"
[ "$(col took 4)" = released ] && ok "the successor takes the name on the release" || fail "the take did not see the release: $OUT"
[ "$(col retire 3)" = released ] && [ ! -f "$(rowfile "$n1")" ] && ok "the predecessor's registry row is gone" || fail "the predecessor was not retired: $OUT"
[ -n "$(col line 2)" ] && [ "$(printf '%s\n' "$OUT" | grep -c "^line$tab")" = 1 ] && ok "the operator sees one line" || fail "not one line: $OUT"
holder_is "the name resolves to the successor only" "$n2"
grep -qx "pid${tab}$p2" "$fleet/mission-control/alpha/holder" && ok "the holder record names the taker's process" || fail "the holder record lacks pid $p2: $(cat "$fleet/mission-control/alpha/holder")"
[ -n "$(events_of mission-control-announce)" ] && ok "the successor announces itself" || fail "no announce event"
[ ! -f "$hf" ] && ok "the consumed handover file is gone" || fail "the handover file outlived the take"

# A file naming a predecessor already retired authorises nothing.
cp "$tmp/hf.keep" "$hf"
ho launch --program alpha --brief "$tmp/brief.md" --handover
[ "$RC" = 3 ] && ok "a handover file naming a retired predecessor is refused" || fail "the stale file exited $RC"
case $ERR in *"held by $n2"*) ok "that refusal names the holder" ;; *) fail "the stale-file refusal does not name $n2: $ERR" ;; esac
rm -f "$hf"

# ---------------------------------------------------------------------------
# REQ-A1.7: a predecessor that cannot release within the window is retired
# by the successor.
# ---------------------------------------------------------------------------
ho write --program alpha --session "$n2" --picture "$tmp/picture" --digest "$digest"
ho launch --program alpha --brief "$tmp/brief.md" --handover
n3=$(col successor 2)
wait_done "$n3"
ho verify --program alpha --session "$n3" --picture "$tmp/picture" --digest "$digest" --ledger "$led1"
[ "$RC" = 0 ] || fail "the third verify exited $RC: $OUT $ERR"
[ -f "$(rowfile "$n2")" ] || fail "fixture: the predecessor's row is missing before the hung take"
before=$(count_of handover-requested)
kill "$p2" 2>/dev/null
ho take --program alpha --session "$n3" --window 1s --exit-wait 20s
[ "$RC" = 0 ] && [ "$(col took 4)" = retired ] && ok "a predecessor silent past the window is retired" || fail "the hung take: $RC $OUT $ERR"
[ "$(col retire 3)" = released ] && ok "the launcher retired it" || fail "the hung predecessor's retire line: $OUT"
[ "$(count_of handover-requested)" = $((before + 1)) ] && ok "the take asked the live predecessor to release" || fail "no handover-requested event for the take"
[ ! -f "$(rowfile "$n2")" ] && ok "the hung predecessor's row is gone" || fail "the hung predecessor's row stayed"
holder_is "the name resolves to the successor" "$n3"

# ---------------------------------------------------------------------------
# REQ-A1.7: resume by name in the operator's session: what changed since the
# last operator turn, an announcement to every live session, the holder
# releasing on request.
# ---------------------------------------------------------------------------
# A worker starts in its own worktree, which needs a default branch to
# branch from.
git -C "$repo" symbolic-ref HEAD refs/heads/main
git -C "$repo" -c user.name=fixture -c user.email=fixture@example.invalid -c commit.gpgsign=false \
  commit -q --allow-empty -m init || fail "fixture: the initial commit failed"
run mission-control-launch.sh launch --program alpha --kind worker --scope fixture-worker --brief "$tmp/brief.md"
[ "$RC" = 0 ] || fail "fixture: the worker did not launch: $ERR"
worker=$(printf '%s\n' "$OUT" | awk -F '\t' '$2 == "name" { print $3 }')
wait_done "$worker"
run mc-kb.sh append decisions --program alpha --subject "before the last turn" --act "held a branch" --no-reversal
sleep 1
run mc-panel.sh presence --program alpha --prompt --now "$(date +%s)"
[ "$RC" = 0 ] || fail "fixture: the presence marker was not written: $ERR"
sleep 1
run mc-kb.sh append decisions --program alpha --subject "after the last turn" --act "retargeted a branch" --no-reversal
led3=$(printf '%s\n' "$OUT" | head -n 1)
ho resume --program alpha --session operator-term --picture "$tmp/picture-short" --digest "$digest" --durable "$tmp/picture"
[ "$RC" = 1 ] && ok "a resume whose self-check fails is refused" || fail "the failing resume exited $RC"
holder_is "and the name stays where it was" "$n3"
(
  n=0
  until [ -f "$fleet/mission-control/alpha/release-request" ] || [ "$n" -ge 100 ]; do
    sleep 0.1
    n=$((n + 1))
  done
  RUN_SESSION=$other_sid RUN_ERR="$tmp/stderr-helper" run mc-handover.sh release --program alpha --session "$n3"
  printf '%s\n' "$OUT" >"$tmp/stdout-helper"
) &
# An exit marker that cannot be written: the release still stands the panel
# down, so the released session stops acting for the program.
ln -s "$tmp/nowhere" "$act/$other_sid.exit"
helper=$!
ho resume --program alpha --session operator-term --picture "$tmp/picture" --digest "$digest" --durable "$tmp/picture" --window 10s
wait "$helper"
[ "$RC" = 0 ] || fail "the resume exited $RC: $OUT $ERR"
[ "$(col took 3)" = "$n3" ] && [ "$(col took 4)" = released ] && ok "the holder releases the name on the resume's request" || fail "the resume did not see the release: $OUT"
case $(cat "$tmp/stdout-helper") in
  *"exit${tab}none${tab}the exit marker could not be written; the panel stood down"*) ok "a release whose exit marker cannot be written says so" ;;
  *) fail "the failed exit marker's exit line: $(cat "$tmp/stdout-helper")" ;;
esac
[ ! -e "$act/$other_sid" ] && [ ! -e "$act/$other_sid.ack" ] && ok "and its panel stood down all the same" || fail "the panel outlived the failed exit marker: $(ls "$act")"
[ ! -f "$(rowfile "$n3")" ] && ok "the released holder's row is gone" || fail "the released holder's row stayed"
case $OUT in *"changed${tab}decision${tab}"*"after the last turn${tab}retargeted a branch"*) ok "the resume reports what changed since the last turn" ;; *) fail "no change reported: $OUT" ;; esac
case $OUT in *"held a branch"* | *"merged nothing"*) fail "a decision before the last turn was reported as changed" ;; *) ok "a decision before the last turn is not reported" ;; esac
case $OUT in *"announce${tab}$worker"*) ok "it announces itself to every live session" ;; *) fail "the worker was not announced to: $OUT" ;; esac
[ -n "$(events_of handover-requested)" ] && ok "the request reached the holder as an event" || fail "no handover-requested event"
holder_is "the name resolves to the operator's session" operator-term
# A session without the mod writes no lease, so nothing proves it gone.
ho holder --program alpha
[ "$(col holder 6)" = live ] && ok "an attended holder with no lease counts as live" || fail "the leaseless holder: $OUT"
ho launch --program alpha --brief "$tmp/brief.md"
[ "$RC" = 3 ] && ok "so a plain launch over it is refused" || fail "a launch over the leaseless holder exited $RC"
mkdir -p "$fleet/mission-control/alpha/leases"
printf "%s\n" "$(($(date +%s) - 600))" >"$fleet/mission-control/alpha/leases/operator-term"
ho holder --program alpha
[ "$(col holder 6)" = stale ] && ok "a lease older than the bound makes it stale" || fail "the old lease: $OUT"
ho path --program alpha
[ "$OUT" = "path${tab}unattended" ] && ok "a stale attended holder has no terminal to hand over, so the path is unattended" || fail "path over the stale holder: $OUT"

# ---------------------------------------------------------------------------
# REQ-L1.6: where the holder is the operator's own session the
# harness cannot swap it, so the handover is one operator act on the panel.
# ---------------------------------------------------------------------------
printf "%s\n" "$(date +%s)" >"$fleet/mission-control/alpha/leases/operator-term"
ho path --program alpha
[ "$(col path 2)" = operator-act ] && ok "an attended holder with no multiplexer gets the operator's act" || fail "path: $OUT $ERR"
[ "$(col path 3)" = "claude '/planwright:mission-control alpha'" ] && ok "the act is one command: a fresh session running the resume" || fail "the act is not one command: $OUT"
ho launch --program alpha --brief "$tmp/brief.md" --handover
[ "$RC" = 4 ] && ok "with no multiplexer no successor is launched over an attended holder" || fail "a launch over the attended holder exited $RC"
ho offer --program alpha
[ "$RC" = 0 ] && [ -n "$(events_of handover-act)" ] && ok "the act is offered as an operator item" || fail "offer: $RC $OUT $ERR"

# A record's handles reach paths and the launcher, so one outside the
# grammar is refused, never followed.
printf 'format\t1\nsession\tmc-x\npredecessor\t../../escape\npredecessor-kind\tregistry\nlaunched\t1\nmode\thandover\nverified\t1\n' \
  >"$fleet/mission-control/alpha/successor"
ho take --program alpha --session mc-x --window 1s
case "$RC:$ERR" in
  1:*"outside the handle grammar"*) ok "a successor record naming a handle outside the grammar is refused" ;;
  *) fail "the tampered record was not refused for its handle: exit $RC: $ERR" ;;
esac
holder_is "and the name stays put" operator-term

# A picture built from the handover file keeps its tab separator; the reader
# takes it as readily as the space form, so the check reaches the successor
# test (none is pending) rather than refusing the grammar.
printf 'item\tq-1\nsession\tmc-worker-1\n' >"$tmp/picture-tab"
ho verify --program alpha --session mc-nobody --picture "$tmp/picture-tab" --digest "$digest" --ledger -
case "$OUT $ERR" in *"none is pending"* | *"is not the pending successor"*) ok "a tab-separated picture is read by verify" ;; *) fail "verify refused the tab picture: exit $RC: $OUT $ERR" ;; esac

# ---------------------------------------------------------------------------
# A retired predecessor is reported released only once the process its
# holder record names has exited: one still running is reported alive and
# raised as an operator item.
# ---------------------------------------------------------------------------
rm -f "$fleet/mission-control/alpha/successor"
holder_file="$fleet/mission-control/alpha/holder"
# A holder record with no process (an earlier planwright's) leaves nothing
# to wait for.
fake_session
self_a=$FAKE
ho resume --program alpha --session op-a --pid "$self_a" --picture "$tmp/picture" --digest "$digest" --durable "$tmp/picture" --window 1s --exit-wait 30s
[ "$RC" = 0 ] && [ "$(col retire 2)" = operator-term ] && [ "$(col retire 3)" = attended ] \
  && ok "a predecessor recorded with no process is retired as before" || fail "the processless predecessor: $RC $OUT $ERR"
grep -qx "pid${tab}$self_a" "$holder_file" && grep -q "^pid-start${tab}." "$holder_file" \
  && ok "the resume records its own process and that process's identity" || fail "the resume's holder record: $(cat "$holder_file")"

# An attended predecessor whose process keeps running.
fake_session
self_b=$FAKE
before=$(count_of handover-predecessor-alive)
announced=$(count_of mission-control-announce)
ho resume --program alpha --session op-b --pid "$self_b" --picture "$tmp/picture" --digest "$digest" --durable "$tmp/picture" --window 1s --exit-wait 1s
[ "$RC" = 1 ] && ok "a resume whose predecessor keeps running exits 1" || fail "the resume over a running predecessor exited $RC: $OUT $ERR"
[ "$(col retire 2)" = op-a ] && [ "$(col retire 3)" = alive ] && [ "$(col retire 4)" = "$self_a" ] \
  && ok "the attended predecessor is reported alive, naming its process" || fail "the running attended predecessor's retire line: $OUT"
[ "$(count_of handover-predecessor-alive)" = $((before + 1)) ] && ok "and an operator item is raised for it" || fail "no handover-predecessor-alive item: $(events_of handover-predecessor-alive)"
[ "$(count_of mission-control-announce)" = $((announced + 1)) ] && [ -n "$(col line 2)" ] \
  && ok "and the resuming session still announces itself" || fail "the alive resume did not announce: $OUT"
holder_is "the name still moves to the resuming session" op-b
kill "$self_a" 2>/dev/null

# An attended predecessor whose process exits during the wait: no retire
# line until it has.
fake_session
self_c=$FAKE
mc_env /bin/bash "$repo_root/scripts/mc-handover.sh" resume --program alpha --session op-c --pid "$self_c" \
  --picture "$tmp/picture" --digest "$digest" --durable "$tmp/picture" --window 1s --exit-wait 60s >"$tmp/waiting.out" 2>&1 &
waiting=$!
n=0
until grep -q "^took${tab}" "$tmp/waiting.out" || [ "$n" -ge 600 ]; do
  sleep 0.1
  n=$((n + 1))
done
sleep 2
if grep -q "^took${tab}" "$tmp/waiting.out" && ! grep -q "^retire${tab}" "$tmp/waiting.out" && kill -0 "$waiting" 2>/dev/null; then
  ok "the resume holds its retire line while the predecessor's process runs"
else
  fail "the resume did not wait on $self_b: $(cat "$tmp/waiting.out")"
fi
kill "$self_b" 2>/dev/null
wait "$waiting"
wrc=$?
[ "$wrc" = 0 ] && grep -qx "retire${tab}op-b${tab}attended" "$tmp/waiting.out" \
  && ok "once that process exits the predecessor is retired" || fail "the exiting predecessor: exit $wrc: $(cat "$tmp/waiting.out")"

# The resuming session's own process never counts as its predecessor's.
kill -0 "$self_c" 2>/dev/null || fail "fixture: the stand-in $self_c ended early"
ho resume --program alpha --session op-d --pid "$self_c" --picture "$tmp/picture" --digest "$digest" --durable "$tmp/picture" --window 1s --exit-wait 2s
[ "$RC" = 0 ] && [ "$(col retire 3)" = attended ] \
  && ok "a predecessor recorded with the resumer's own process is not waited for" || fail "the same-process resume: $RC $OUT $ERR"

# A recorded pid now held by another process is not the predecessor's; the
# taker's process defaults to CLAUDE_PID.
awk -F '\t' -v OFS='\t' '$1 == "pid-start" { $2 = "boot:another:1" } { print }' "$holder_file" >"$tmp/holder.edit"
cp "$tmp/holder.edit" "$holder_file"
kill -0 "$self_c" 2>/dev/null || fail "fixture: the stand-in $self_c ended early"
fake_session
self_e=$FAKE
OUT=$(mc_env env CLAUDE_PID="$self_e" /bin/bash "$repo_root/scripts/mc-handover.sh" resume --program alpha --session op-e \
  --picture "$tmp/picture" --digest "$digest" --durable "$tmp/picture" --window 1s --exit-wait 2s 2>"$tmp/stderr")
RC=$?
[ "$RC" = 0 ] && [ "$(col retire 3)" = attended ] \
  && ok "a recorded pid whose identity no longer matches is not waited for" || fail "the recycled pid: $RC $OUT $(cat "$tmp/stderr")"
grep -qx "pid${tab}$self_e" "$holder_file" && ok "with no --pid the holder record takes CLAUDE_PID" || fail "CLAUDE_PID was not recorded: $(cat "$holder_file")"
kill "$self_c" "$self_e" 2>/dev/null

# A registry predecessor the launcher retired while its process runs on.
ho launch --program alpha --brief "$tmp/brief.md" --asked
r1=$(col successor 2)
wait_done "$r1"
ho verify --program alpha --session "$r1" --picture "$tmp/picture" --digest "$digest" --ledger "$led3" --durable "$tmp/picture"
[ "$RC" = 0 ] || fail "fixture: the registry successor's verify exited $RC: $OUT $ERR"
fake_session
pr=$FAKE
ho take --program alpha --session "$r1" --window 1s --pid "$pr" --exit-wait 2s
[ "$RC" = 0 ] && [ "$(col retire 2)" = op-e ] || fail "fixture: the registry take: $RC $OUT $ERR"
ho launch --program alpha --brief "$tmp/brief.md" --asked
r2=$(col successor 2)
wait_done "$r2"
ho verify --program alpha --session "$r2" --picture "$tmp/picture" --digest "$digest" --ledger "$led3" --durable "$tmp/picture"
before=$(count_of handover-predecessor-alive)
ho take --program alpha --session "$r2" --window 1s --exit-wait 1s
[ "$RC" = 1 ] && [ "$(col retire 2)" = "$r1" ] && [ "$(col retire 3)" = alive ] && [ "$(col retire 4)" = "$pr" ] \
  && ok "a registry predecessor still running after its retire is reported alive" || fail "the running registry predecessor: $RC $OUT $ERR"
[ "$(count_of handover-predecessor-alive)" = $((before + 1)) ] && ok "and raised as an operator item" || fail "no item for the running registry predecessor"
[ ! -f "$(rowfile "$r1")" ] && ok "its registry row is still retired" || fail "the running registry predecessor's row stayed"
holder_is "the name rests with the successor" "$r2"
kill "$pr" 2>/dev/null

# ---------------------------------------------------------------------------
# REQ-L1.9, D-43: an attended holder inside tmux hands over itself, in a
# pane beside it; the successor closes exactly the recorded predecessor pane
# once the name has moved, never on a refused or failed take. A fake tmux
# answers for the panes listed in its panes file and logs what it is asked.
# ---------------------------------------------------------------------------
cat >"$tmp/bin/tmux" <<'FAKE'
#!/bin/sh
d=${FAKE_TMUX_DIR:?}
if [ "$1" = -S ]; then
  sock=$2
  shift 2
  printf 'sock %s: ' "$sock" >>"$d/tmux.log"
fi
printf '%s\n' "$*" >>"$d/tmux.log"
mkdir -p "$d/tmuxw"
case $1 in
  display-message)
    t=''
    for a in "$@"; do [ "$prev" = -t ] && t=$a; prev=$a; done
    case $t in
      %*) grep -qx -- "$t" "$d/tmux.panes" && printf '%s\n' "$t" && exit 0 ;;
      @*) if [ -e "$d/tmuxw/$t" ]; then
        case $* in *session_name*) echo stub ;; *) echo "$t" ;; esac
        exit 0
      fi ;;
    esac
    exit 1
    ;;
  new-window)
    n=$(cat "$d/tmuxw/next" 2>/dev/null || echo 1)
    echo $((n + 1)) >"$d/tmuxw/next"
    shift
    printf '%s\n' "$@" >"$d/tmuxw/argv-@$n"
    wname=''
    while [ "$#" -gt 0 ]; do
      [ "$1" = -n ] && wname=$2
      shift
    done
    printf '%s\n' "$wname" >"$d/tmuxw/@$n"
    echo "@$n"
    exit 0
    ;;
  list-windows)
    for w in "$d"/tmuxw/@*; do
      [ -f "$w" ] || continue
      case $* in *window_name*) printf '%s %s\n' "${w##*/}" "$(cat "$w")" ;; *) printf '%s\n' "${w##*/}" ;; esac
    done
    exit 0
    ;;
  kill-window)
    rm -f "$d/tmuxw/$3"
    exit 0
    ;;
  kill-pane)
    id=$3
    grep -vx -- "$id" "$d/tmux.panes" >"$d/tmux.panes.new"
    mv "$d/tmux.panes.new" "$d/tmux.panes"
    exit 0
    ;;
  has-session) exit 1 ;;
esac
exit 1
FAKE
chmod +x "$tmp/bin/tmux"
export FAKE_TMUX_DIR="$tmp"
printf '%s\n' '%7' '%9' '%3' >"$tmp/tmux.panes"
: >"$tmp/tmux.log"

fake_session
self_f=$FAKE
ho resume --program alpha --session op-f --pid "$self_f" --picture "$tmp/picture" --digest "$digest" --durable "$tmp/picture" --window 1s --exit-wait 2s
[ "$RC" = 0 ] || fail "fixture: the attended resume exited $RC: $OUT $ERR"
printf "%s\n" "$(date +%s)" >"$fleet/mission-control/alpha/leases/op-f"

RUN_TMUX_PANE='%7' ho path --program alpha
[ "$OUT" = "path${tab}pane${tab}tmux" ] && ok "an attended holder inside tmux gets the pane path" || fail "path in tmux: $OUT $ERR"
RUN_TMUX_PANE='%99' ho path --program alpha
[ "$(col path 2)" = operator-act ] && ok "a pane tmux does not know still gets the operator's act" || fail "path in an unknown pane: $OUT"
RUN_TMUX_PANE='7;rm' ho path --program alpha
[ "$(col path 2)" = operator-act ] && ok "a pane id outside the grammar gets the operator's act" || fail "path with a malformed pane: $OUT"

ho write --program alpha --session op-f --picture "$tmp/picture" --digest "$digest"
[ "$RC" = 0 ] || fail "fixture: the handover file was not written: $OUT $ERR"
led_f=$(col handover 3)
RUN_TMUX_PANE='%7' ho launch --program alpha --brief "$tmp/brief.md" --handover --backend stream-json
[ "$RC" = 0 ] || fail "fixture: the headless handover launch exited $RC: $OUT $ERR"
ns=$(col successor 2)
wait_done "$ns"
grep -q '^predecessor-pane' "$fleet/mission-control/alpha/successor" && ! grep -q "^predecessor-pane${tab}%" "$fleet/mission-control/alpha/successor" \
  && ok "a headless successor records no pane, so it can never close the operator's" || fail "the headless record: $(cat "$fleet/mission-control/alpha/successor")"
run mission-control-launch.sh retire "$ns"
rm -f "$fleet/mission-control/alpha/successor"

RUN_TMUX_PANE='%7' ho launch --program alpha --brief "$tmp/brief.md" --handover
[ "$RC" = 0 ] && ok "a handover launch over an attended holder inside tmux is admitted, on the tmux rung" || fail "the pane handover launch exited $RC: $OUT $ERR"
nf=$(col successor 2)
grep -qx "predecessor-pane${tab}%7" "$fleet/mission-control/alpha/successor" \
  && grep -qx "predecessor-tmux${tab}$tmp/tmux.sock" "$fleet/mission-control/alpha/successor" \
  && ok "the predecessor's pane id and tmux socket are recorded" || fail "no recorded pane: $(cat "$fleet/mission-control/alpha/successor")"

RUN_TMUX_PANE='%9' ho take --program alpha --session "$nf" --window 1s --exit-wait 1s
[ "$RC" != 0 ] && ! grep -q kill-pane "$tmp/tmux.log" \
  && ok "a take before the self-check closes no pane" || fail "the unverified take: $RC $OUT $ERR $(cat "$tmp/tmux.log")"
RUN_TMUX_PANE='%9' ho take --program alpha --session mc-someone-else --window 1s --exit-wait 1s
[ "$RC" != 0 ] && ! grep -q kill-pane "$tmp/tmux.log" \
  && ok "a refused take (not the pending successor) closes no pane" || fail "the refused take: $RC $OUT $ERR"
holder_is "and the name stays put" op-f

ho verify --program alpha --session "$nf" --picture "$tmp/picture" --digest "$digest" --ledger "$led_f"
[ "$RC" = 0 ] || fail "fixture: the pane successor's verify exited $RC: $OUT $ERR"
grep -qx "predecessor-pane${tab}%7" "$fleet/mission-control/alpha/successor" \
  && ok "the verify keeps the recorded pane" || fail "verify dropped the pane: $(cat "$fleet/mission-control/alpha/successor")"
kill "$self_f" 2>/dev/null
RUN_TMUX_PANE='%9' ho take --program alpha --session "$nf" --window 1s --exit-wait 5s
[ "$RC" = 0 ] && [ "$(col pane 2)" = '%7' ] && [ "$(col pane 3)" = closed ] \
  && ok "the successful take reports the predecessor's pane closed" || fail "the pane take: $RC $OUT $ERR"
[ "$(grep -c kill-pane "$tmp/tmux.log")" = 1 ] && grep -qx "sock $tmp/tmux.sock: kill-pane -t %7" "$tmp/tmux.log" \
  && grep -qx '%9' "$tmp/tmux.panes" && grep -qx '%3' "$tmp/tmux.panes" \
  && ok "exactly the recorded pane was killed, no other" || fail "tmux log: $(cat "$tmp/tmux.log")"
holder_is "the name moved to the pane successor" "$nf"

echo
if [ "$failures" -gt 0 ]; then
  echo "test-mc-handover: $failures failure(s)" >&2
  exit 1
fi
echo "test-mc-handover: all passed"
