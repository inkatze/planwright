#!/bin/sh
# Tests for `step-record.sh supersede`: an append-only correction of a step
# record's start or end time, cited to the session event that proves it, read in
# place of the record it replaces by the cadence audit and the renderer.
# Fixtures are synthetic, shaped like the real cases (a polish started three
# seconds before its Skill call).
#
# Runs standalone under /bin/sh (the bash 3.2 / dash floor):
#   ./tests/test-step-record-supersede.sh
# shellcheck disable=SC2319 # each verdict judges the condition just before it
set -u
LC_ALL=C
export LC_ALL
unset CDPATH
umask 077

here=$(cd "$(dirname "$0")" && pwd)
repo_root=$(cd "$here/.." && pwd)
RUN="$repo_root/scripts/step-run.sh"
SR="$repo_root/scripts/step-record.sh"
SP="$repo_root/scripts/step-pool.sh"
TAB=$(printf '\t')

# shellcheck source=tests/lib/step-run-fixture.sh
. "$here/lib/step-run-fixture.sh"

PLANWRIGHT_FLEET_STATE_DIR="$tmp/fleet"
export PLANWRIGHT_FLEET_STATE_DIR

POLISH='polish|kind: skill|target: polish|args: --nested'

audit() {
  srun audit "$@" >"$tmp/audit" 2>"$tmp/audit.err"
  RC=$?
}
session() {
  sdir="$tmp/fleet/streamjson/s$n"
  mkdir -p "$sdir"
  printf '%s\n' "$wt" >"$sdir/cwd"
  printf '{"type":"user","timestamp":"%s.100Z","message":{"content":"go"}}\n' "$1" >"$sdir/events.jsonl"
}
call() {
  printf '{"type":"assistant","timestamp":"%s.700Z","message":{"content":[{"type":"tool_use","name":"%s","input":{"skill":"%s"}}]}}\n' \
    "$1" "$2" "${3:-}" >>"$sdir/events.jsonl"
}
# rec <run> <point> <step> <target> <outcome> <start> <end> [<head> [<end-head>]]
rec() {
  _h=${8:-$(head_of)}
  sr write --run "$1" --point "$2" --step "$3" --kind skill --target "$4" --hosting in-session \
    --backend in-session --head "$_h" --end-head "${9:-$_h}" --start "$6" --end "$7" --outcome "$5" \
    >"$tmp/rec.out" 2>&1 || fail "fixture: the $3 record: $(cat "$tmp/rec.out")"
}
done_at() { sr write --completion --run "$1" --point "$2" >"$tmp/done.out" || fail "fixture: the $2 completion"; }
# sup <args...>: a supersede, its status in RC and output in $tmp/sup.
sup() {
  sr supersede "$@" >"$tmp/sup" 2>&1
  RC=$?
}
files_of() {
  for _f in "$wt/.claude/steps/$1"/*; do printf '%s ' "${_f##*/}"; done
}

# A polish whose start was stamped three seconds before its Skill call, the
# shape every real case took. The session event log holds the true second.
misdated() {
  fresh
  catalog "$POLISH"
  config 'steps_convergence: [polish]'
  session 2026-11-04T10:00:00
  call 2026-11-04T10:00:11 Skill planwright:polish
  call 2026-11-04T10:00:20 Agent
  r=$(sr new-run)
  rec "$r" convergence polish /polish passed 2026-11-04T10:00:08Z 2026-11-04T10:00:47Z
  done_at "$r" convergence
  ref="$r:convergence:001"
}

# --- 1: the misdated record fails, and the failure names the verb --------------
misdated
audit --through convergence
[ "$RC" -eq 1 ] && grep -q "^gap${TAB}convergence${TAB}fault${TAB}.*not the second of the polish Skill call" "$tmp/audit"
verdict $? "a polish started three seconds before its Skill call fails the audit" \
  "rc $RC: $(cat "$tmp/audit" "$tmp/audit.err")"
grep -q "step-record.sh supersede" "$tmp/audit"
verdict $? "the audit advice names the supersede verb" "$(cat "$tmp/audit")"

# --- 2: a supersede citing the Skill call's second passes it -------------------
before=$(cat "$wt/.claude/steps/$r/001-step-convergence.rec")
sup --record "$ref" --start 2026-11-04T10:00:11Z --source event:2026-11-04T10:00:11Z
[ "$RC" -eq 0 ] && [ -f "$(cat "$tmp/sup")" ]
verdict $? "a supersede citing the Skill call's second is written" "rc $RC: $(cat "$tmp/sup")"
audit --through convergence
[ "$RC" -eq 0 ]
verdict $? "the audit reads the supersede in place of the misdated record" \
  "rc $RC: $(cat "$tmp/audit" "$tmp/audit.err")"
[ "$(cat "$wt/.claude/steps/$r/001-step-convergence.rec")" = "$before" ] \
  && grep -q "^start${TAB}2026-11-04T10:00:08Z$" "$wt/.claude/steps/$r/001-step-convergence.rec"
verdict $? "the original record stays on disk, unedited" "$(cat "$wt/.claude/steps/$r/001-step-convergence.rec")"
case $(files_of "$r") in
  *001-step-convergence.rec*002-done-convergence.rec*003-fix-convergence.rec*) ok "the correction is its own record, after the original and the completion" ;;
  *) fail "the run holds: $(files_of "$r")" ;;
esac
# shellcheck disable=SC2154 # sr list is the plain reader
sr list --run "$r" >"$tmp/list"
grep -q "^supersedes${TAB}$ref$" "$tmp/list" && grep -q "^start${TAB}2026-11-04T10:00:08Z$" "$tmp/list"
verdict $? "plain list shows the original and the record that supersedes it" "$(cat "$tmp/list")"
sr list --run "$r" --effective >"$tmp/list"
grep -q "^start${TAB}2026-11-04T10:00:11Z$" "$tmp/list" && ! grep -q "^start${TAB}2026-11-04T10:00:08Z$" "$tmp/list" \
  && ! grep -q "^type${TAB}supersede$" "$tmp/list"
verdict $? "list --effective shows the corrected start and no supersede record" "$(cat "$tmp/list")"
sr render --run "$r" >"$tmp/render"
grep -q "2026-11-04T10:00:11Z" "$tmp/render" && ! grep -q "2026-11-04T10:00:08Z" "$tmp/render" \
  && grep -q "corrected" "$tmp/render"
verdict $? "render shows the corrected start, marked as corrected" "$(cat "$tmp/render")"
sr untrue >"$tmp/untrue"
[ ! -s "$tmp/untrue" ]
verdict $? "the corrected record passes the truth check" "$(cat "$tmp/untrue")"

# --- 3: refusals ----------------------------------------------------------------
misdated
n_before=$(files_of "$r")
refused() {
  _msg=$1
  _why=$2
  shift 2
  sup "$@"
  [ "$RC" -eq 2 ] && [ "$(files_of "$r")" = "$n_before" ] && grep -q -- "$_why" "$tmp/sup"
  verdict $? "$_msg" "rc $RC, files '$(files_of "$r")': $(cat "$tmp/sup")"
}
refused "a supersede that changes the outcome is refused" "outcome" --record "$ref" --start 2026-11-04T10:00:11Z --source event:2026-11-04T10:00:11Z --outcome applied
refused "a supersede that changes the step is refused" "--step: a supersede corrects timing only" --record "$ref" --start 2026-11-04T10:00:11Z --source event:2026-11-04T10:00:11Z --step self-review
refused "a supersede that changes the kind is refused" "kind" --record "$ref" --start 2026-11-04T10:00:11Z --source event:2026-11-04T10:00:11Z --kind prompt
refused "a supersede that changes the head is refused" "head" --record "$ref" --start 2026-11-04T10:00:11Z --source event:2026-11-04T10:00:11Z \
  --head 1111111111111111111111111111111111111111
refused "a supersede that changes the end head is refused" "end-head" --record "$ref" --start 2026-11-04T10:00:11Z --source event:2026-11-04T10:00:11Z \
  --end-head 1111111111111111111111111111111111111111
refused "a supersede with no source is refused" "source" --record "$ref" --start 2026-11-04T10:00:11Z
refused "a supersede citing no event of the session is refused" "source" --record "$ref" --start 2026-11-04T10:00:12Z --source event:2026-11-04T10:00:12Z
refused "a supersede whose cited event is not the corrected time is refused" "source" --record "$ref" --start 2026-11-04T10:00:11Z --source event:2026-11-04T10:00:20Z
refused "a supersede with a malformed source is refused" "source" --record "$ref" --start 2026-11-04T10:00:11Z --source 'my memory'
refused "a supersede that corrects nothing is refused" "start" --record "$ref" --source event:2026-11-04T10:00:11Z
refused "a supersede targeting a missing record is refused" "--record: names no step record" --record "$r:convergence:099" --start 2026-11-04T10:00:11Z --source event:2026-11-04T10:00:11Z
refused "a supersede targeting a completion record is refused" "--record: names no step record" --record "$r:convergence:002" --start 2026-11-04T10:00:11Z --source event:2026-11-04T10:00:11Z
refused "a supersede targeting a malformed reference is refused" "--record: not <run>" --record "convergence:001" --start 2026-11-04T10:00:11Z --source event:2026-11-04T10:00:11Z
refused "a corrected window the truth check refuses (a skill under the floor) is refused" "window-floor" --record "$ref" --start 2026-11-04T10:00:20Z --source event:2026-11-04T10:00:20Z
audit --through convergence
[ "$RC" -eq 1 ]
verdict $? "after every refusal the misdated record still fails the audit" "rc $RC: $(cat "$tmp/audit")"

# --- 4: a source cited by event-log line ----------------------------------------
misdated
# Line 1 is the opening event, line 2 the Skill call.
sup --record "$ref" --start 2026-11-04T10:00:11Z --source event-line:2
[ "$RC" -eq 0 ]
verdict $? "a source cited as an event-log line holding the corrected second is accepted" "rc $RC: $(cat "$tmp/sup")"
misdated
sup --record "$ref" --start 2026-11-04T10:00:11Z --source event-line:9
[ "$RC" -eq 2 ]
verdict $? "an event-log line that does not exist is refused" "rc $RC: $(cat "$tmp/sup")"
misdated
sup --record "$ref" --start 2026-11-04T10:00:11Z --source event-line:1
[ "$RC" -eq 2 ]
verdict $? "an event-log line holding another second is refused" "rc $RC: $(cat "$tmp/sup")"

# --- 5: the latest supersede wins ------------------------------------------------
misdated
call 2026-11-04T10:00:09 Skill planwright:polish
sup --record "$ref" --start 2026-11-04T10:00:11Z --source event:2026-11-04T10:00:11Z
[ "$RC" -eq 0 ]
verdict $? "the first of two supersedes is written" "rc $RC: $(cat "$tmp/sup")"
sup --record "$ref" --start 2026-11-04T10:00:09Z --source event:2026-11-04T10:00:09Z
[ "$RC" -eq 0 ]
verdict $? "the second of two supersedes is written" "rc $RC: $(cat "$tmp/sup")"
sr list --run "$r" --effective >"$tmp/list"
grep -q "^start${TAB}2026-11-04T10:00:09Z$" "$tmp/list" && ! grep -q "^start${TAB}2026-11-04T10:00:11Z$" "$tmp/list"
verdict $? "of two supersedes of one record, the later one stands, whatever its stamp" "$(cat "$tmp/list")"
sup --record "$r:convergence:003" --start 2026-11-04T10:00:11Z --source event:2026-11-04T10:00:11Z
[ "$RC" -eq 2 ]
verdict $? "a supersede cannot target another supersede" "rc $RC: $(cat "$tmp/sup")"

# --- 6: a correction to the end -------------------------------------------------
misdated
call 2026-11-04T10:00:52 Agent
sup --record "$ref" --end 2026-11-04T10:00:52Z --source event:2026-11-04T10:00:52Z
[ "$RC" -eq 0 ]
verdict $? "a corrected end, cited to an event at that second, is accepted" "rc $RC: $(cat "$tmp/sup")"
sr list --run "$r" --effective >"$tmp/list"
grep -q "^end${TAB}2026-11-04T10:00:52Z$" "$tmp/list" && grep -q "^start${TAB}2026-11-04T10:00:08Z$" "$tmp/list"
verdict $? "the effective record takes the corrected end and keeps the original start" "$(cat "$tmp/list")"

# --- 7: no session events at all ------------------------------------------------
fresh
catalog "$POLISH"
config 'steps_convergence: [polish]'
r=$(sr new-run)
rec "$r" convergence polish /polish passed 2026-11-04T10:00:08Z 2026-11-04T10:00:47Z
sup --record "$r:convergence:001" --start 2026-11-04T10:00:11Z --source event:2026-11-04T10:00:11Z
[ "$RC" -eq 2 ] && grep -q "event log" "$tmp/sup"
verdict $? "a source that cannot be checked against any session event is refused" "rc $RC: $(cat "$tmp/sup")"

# --- 8: a correction of one stamp never undoes the other ------------------------
misdated
call 2026-11-04T10:00:52 Agent
sup --record "$ref" --start 2026-11-04T10:00:11Z --source event:2026-11-04T10:00:11Z
[ "$RC" -eq 0 ]
verdict $? "a start correction is written" "rc $RC: $(cat "$tmp/sup")"
sup --record "$ref" --end 2026-11-04T10:00:52Z --source event:2026-11-04T10:00:52Z
[ "$RC" -eq 0 ]
verdict $? "an end correction after it is written" "rc $RC: $(cat "$tmp/sup")"
sr list --run "$r" --effective >"$tmp/list"
grep -q "^start${TAB}2026-11-04T10:00:11Z$" "$tmp/list" && grep -q "^end${TAB}2026-11-04T10:00:52Z$" "$tmp/list"
verdict $? "a later end correction keeps the start an earlier supersede corrected" "$(cat "$tmp/list")"
sr render --run "$r" >"$tmp/render"
grep -Fq "start and end corrected by supersede" "$tmp/render"
verdict $? "render says both stamps were corrected when two supersedes stood" "$(cat "$tmp/render")"
sr list --run "$r" --effective >"$tmp/list"
awk -F '\t' 'c { exit ($0 == "" ? 0 : 1) } $1 == "corrected-by" { c = 1 }' "$tmp/list" \
  && grep -q "^corrected-by${TAB}$r:convergence:004$" "$tmp/list" && grep -q "^start-source${TAB}supersede:004$" "$tmp/list"
verdict $? "list --effective names the standing supersede inside the stanza and rewrites the start source" "$(cat "$tmp/list")"

# --- 9: one stamp a supersede, the one its source proves -----------------------
misdated
call 2026-11-04T10:00:52 Agent
before9=$(files_of "$r")
sup --record "$ref" --start 2026-11-04T10:00:11Z --end 2026-11-04T10:00:52Z --source event:2026-11-04T10:00:11Z
[ "$RC" -eq 2 ] && [ "$(files_of "$r")" = "$before9" ] && grep -q "one stamp" "$tmp/sup"
verdict $? "a supersede giving both stamps is refused, so one event cannot vouch for two" "rc $RC: $(cat "$tmp/sup")"

# --- 10: only a top-level event timestamp is a source --------------------------
misdated
printf '{"type":"assistant","timestamp":"2026-11-04T10:00:30.000Z","message":{"content":[{"type":"tool_use","name":"Agent","input":{"timestamp":"2026-11-04T10:00:12.000Z"}}]}}\n' >>"$sdir/events.jsonl"
sup --record "$ref" --start 2026-11-04T10:00:12Z --source event:2026-11-04T10:00:12Z
[ "$RC" -eq 2 ]
verdict $? "a timestamp inside a tool input is no event of the log" "rc $RC: $(cat "$tmp/sup")"
sup --record "$ref" --start 2026-11-04T10:00:12Z --source event-line:4
[ "$RC" -eq 2 ]
verdict $? "nor is it by line number" "rc $RC: $(cat "$tmp/sup")"

# --- 11: untrue and the readers judge a record on its corrected times ----------
# A supersede written by hand (the verb would refuse it) puts the window under
# the skill floor: only a reader that takes the supersede's stamps sees it.
misdated
sr untrue >"$tmp/untrue"
[ ! -s "$tmp/untrue" ]
verdict $? "the misdated record alone passes the truth check" "$(cat "$tmp/untrue")"
printf 'type\tsupersede\nrun\t%s\nseq\t003\npoint\tconvergence\nsupersedes\t%s\nstart\t2026-11-04T10:00:40Z\nend\t2026-11-04T10:00:47Z\nfrom-start\t2026-11-04T10:00:08Z\nfrom-end\t2026-11-04T10:00:47Z\nsource\tevent:2026-11-04T10:00:40Z\n' \
  "$r" "$ref" >"$wt/.claude/steps/$r/003-fix-convergence.rec"
sr untrue >"$tmp/untrue"
grep -q "^$ref${TAB}polish${TAB}--start${TAB}window-floor$" "$tmp/untrue"
verdict $? "untrue judges a record on its standing supersede's stamps" "$(cat "$tmp/untrue")"

# --- 12: a malformed supersede is ignored by every reader -----------------------
misdated
printf 'type\tsupersede\nrun\t%s\nseq\t003\npoint\tconvergence\nsupersedes\t%s\nstart\t2026-11-04T10:00:11Z\nstart\t2026-11-04T10:00:11Z\nend\t2026-11-04T10:00:47Z\nsource\tevent:2026-11-04T10:00:11Z\n' \
  "$r" "$ref" >"$wt/.claude/steps/$r/003-fix-convergence.rec"
sr list --run "$r" --effective >"$tmp/list"
sr render --run "$r" >"$tmp/render"
grep -q "^start${TAB}2026-11-04T10:00:08Z$" "$tmp/list" && ! grep -q "corrected" "$tmp/render" && grep -q "2026-11-04T10:00:08Z" "$tmp/render"
verdict $? "a supersede with a repeated key corrects nothing, in list and in render" "$(cat "$tmp/list" "$tmp/render")"
audit --through convergence
[ "$RC" -eq 1 ]
verdict $? "so the audit still fails the misdated record" "rc $RC: $(cat "$tmp/audit")"

# --- 13: the source check reads the log as the audit does ----------------------
misdated
printf '{"type":"assistant","timestamp":"2026-11-04T10:00:12+05:00","message":{"content":"x"}}\n' >>"$sdir/events.jsonl"
sup --record "$ref" --start 2026-11-04T10:00:12Z --source event:2026-11-04T10:00:12Z
[ "$RC" -eq 2 ]
verdict $? "an event whose timestamp the audit would not read is no source" "rc $RC: $(cat "$tmp/sup")"
misdated
# A live log's half-written tail has no newline: its line still counts as the next.
printf '{"type":"assistant","timestamp":"2026-11-04T10:00:15.000Z","message":{"content":"x"}}' >>"$sdir/events.jsonl"
sup --record "$ref" --start 2026-11-04T10:00:15Z --source event-line:4
[ "$RC" -eq 0 ]
verdict $? "an unterminated last log line is numbered as the line it is" "rc $RC: $(cat "$tmp/sup")"

# --- 14: a supersede cannot restore the record's own start ---------------------
misdated
call 2026-11-04T10:00:08 Agent
sup --record "$ref" --start 2026-11-04T10:00:11Z --source event:2026-11-04T10:00:11Z
sup --record "$ref" --start 2026-11-04T10:00:08Z --source event:2026-11-04T10:00:08Z
[ "$RC" -eq 2 ] && grep -q "own start" "$tmp/sup"
verdict $? "a supersede restoring the original start is refused" "rc $RC: $(cat "$tmp/sup")"

# --- 15: an end-only correction does not source the original start -------------
# A start on seconds :00 over a whole-minute window is what the truth check
# flags when nothing sources the start; correcting the end alone cannot clear it.
fresh
catalog "$POLISH"
config 'steps_convergence: [polish]'
session 2026-11-04T10:00:00
call 2026-11-04T10:00:00 Skill planwright:polish
call 2026-11-04T10:01:07 Agent
call 2026-11-04T10:02:00 Agent
r=$(sr new-run)
h=$(head_of)
# Written by hand: `write` itself refuses a round start and window with no source.
printf 'type\tstep\nrun\t%s\nseq\t001\npoint\tconvergence\nstep\tpolish\nkind\tskill\ntarget\t/polish\nhosting\tin-session\nbackend\tin-session\nsession\t\nhead\t%s\nend-head\t%s\nstart\t2026-11-04T10:00:00Z\nend\t2026-11-04T10:01:00Z\nstart-source\t\noutcome\tpassed\noutput\t\nskip-code\t\nskip-reason\t\ndegraded\t\nstands-on\t\npool\t\nwait\t\nunpooled\t\nfingerprint\t\nargs-digest\t\nrefire-of\t\n' \
  "$r" "$h" "$h" >"$wt/.claude/steps/$r/001-step-convergence.rec"
sr untrue >"$tmp/untrue"
grep -q "window-round-minutes" "$tmp/untrue"
verdict $? "fixture: the round start and window is flagged by the truth check" "$(cat "$tmp/untrue")"
sup --record "$r:convergence:001" --end 2026-11-04T10:02:00Z --source event:2026-11-04T10:02:00Z
[ "$RC" -eq 2 ] && grep -q "window-round-minutes" "$tmp/sup"
verdict $? "an end-only correction to another whole-minute window is refused: it sources the end, not the start" "rc $RC: $(cat "$tmp/sup")"
sup --record "$r:convergence:001" --end 2026-11-04T10:01:07Z --source event:2026-11-04T10:01:07Z
[ "$RC" -eq 0 ]
verdict $? "an end-only correction to a window that is not whole minutes is written" "rc $RC: $(cat "$tmp/sup")"
sr untrue >"$tmp/untrue"
[ ! -s "$tmp/untrue" ]
verdict $? "once the window is no longer whole minutes the record passes" "$(cat "$tmp/untrue")"

# --- 16: a session launched elsewhere that names the worktree is a source ------
fresh
catalog "$POLISH"
config 'steps_convergence: [polish]'
wta=$wt
wtb="$tmp/wtb$n"
git -C "$wta" worktree add -q -b planwright/flight/review-b "$wtb" || fail "fixture: worktree B"
# The reviewer's session, launched in A, names B in a command it ran.
session 2026-11-04T10:00:00
printf '{"type":"assistant","timestamp":"2026-11-04T10:00:03.000Z","message":{"content":[{"type":"tool_use","name":"Bash","input":{"command":"step-record.sh --worktree %s list"}}]}}\n' "$wtb" >>"$sdir/events.jsonl"
call 2026-11-04T10:00:11 Skill planwright:polish
call 2026-11-04T10:00:20 Agent
# A session that never names B, with an event at a second only it holds.
n=$((n + 1))
session 2026-11-04T10:05:00
call 2026-11-04T10:05:11 Skill planwright:polish
wt=$wtb
r=$(sr new-run)
rec "$r" convergence polish /polish passed 2026-11-04T10:00:08Z 2026-11-04T10:00:47Z
sup --record "$r:convergence:001" --end 2026-11-04T10:05:11Z --source event:2026-11-04T10:05:11Z
[ "$RC" -eq 2 ] && grep -q "no event of the session's log is stamped" "$tmp/sup"
verdict $? "an event only a session that never names B holds is refused as a source" "rc $RC: $(cat "$tmp/sup")"
sup --record "$r:convergence:001" --start 2026-11-04T10:00:11Z --source event:2026-11-04T10:00:11Z
[ "$RC" -eq 0 ]
verdict $? "an event of the reviewer session launched in A that names B is a source for B's record" "rc $RC: $(cat "$tmp/sup")"
done_at "$r" convergence
audit --through convergence
[ "$RC" -eq 0 ] && ! grep -q -e "^gap" -e "^note" "$tmp/audit"
verdict $? "and B's audit reads the corrected record against that session's Skill call and Agent call" \
  "rc $RC: $(cat "$tmp/audit" "$tmp/audit.err")"

if [ "$failures" -gt 0 ]; then
  printf '%s failure(s)\n' "$failures" >&2
  exit 1
fi
echo "All step-record supersede tests passed."
