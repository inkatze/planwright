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
files_of() { ls "$wt/.claude/steps/$1" | tr '\n' ' '; }

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
  _why=$1
  shift
  sup "$@"
  [ "$RC" -eq 2 ] && [ "$(files_of "$r")" = "$n_before" ] && grep -q "$_why" "$tmp/sup"
  verdict $? "$_msg" "rc $RC, files '$(files_of "$r")': $(cat "$tmp/sup")"
}
_msg="a supersede that changes the outcome is refused" \
  refused "outcome" --record "$ref" --start 2026-11-04T10:00:11Z --source event:2026-11-04T10:00:11Z --outcome applied
_msg="a supersede that changes the step is refused" \
  refused "step" --record "$ref" --start 2026-11-04T10:00:11Z --source event:2026-11-04T10:00:11Z --step self-review
_msg="a supersede that changes the kind is refused" \
  refused "kind" --record "$ref" --start 2026-11-04T10:00:11Z --source event:2026-11-04T10:00:11Z --kind prompt
_msg="a supersede that changes the head is refused" \
  refused "head" --record "$ref" --start 2026-11-04T10:00:11Z --source event:2026-11-04T10:00:11Z \
  --head 1111111111111111111111111111111111111111
_msg="a supersede that changes the end head is refused" \
  refused "end-head" --record "$ref" --start 2026-11-04T10:00:11Z --source event:2026-11-04T10:00:11Z \
  --end-head 1111111111111111111111111111111111111111
_msg="a supersede with no source is refused" \
  refused "source" --record "$ref" --start 2026-11-04T10:00:11Z
_msg="a supersede citing no event of the session is refused" \
  refused "source" --record "$ref" --start 2026-11-04T10:00:12Z --source event:2026-11-04T10:00:12Z
_msg="a supersede whose cited event is not the corrected time is refused" \
  refused "source" --record "$ref" --start 2026-11-04T10:00:11Z --source event:2026-11-04T10:00:20Z
_msg="a supersede with a malformed source is refused" \
  refused "source" --record "$ref" --start 2026-11-04T10:00:11Z --source 'my memory'
_msg="a supersede that corrects nothing is refused" \
  refused "start" --record "$ref" --source event:2026-11-04T10:00:11Z
_msg="a supersede targeting a missing record is refused" \
  refused "record" --record "$r:convergence:099" --start 2026-11-04T10:00:11Z --source event:2026-11-04T10:00:11Z
_msg="a supersede targeting a completion record is refused" \
  refused "record" --record "$r:convergence:002" --start 2026-11-04T10:00:11Z --source event:2026-11-04T10:00:11Z
_msg="a supersede targeting a malformed reference is refused" \
  refused "record" --record "convergence:001" --start 2026-11-04T10:00:11Z --source event:2026-11-04T10:00:11Z
_msg="a corrected window the truth check refuses (a skill under the floor) is refused" \
  refused "window-floor" --record "$ref" --start 2026-11-04T10:00:20Z --source event:2026-11-04T10:00:20Z
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
# The second call is on the log from the start of the test; both are real events.
sup --record "$ref" --start 2026-11-04T10:00:09Z --source event:2026-11-04T10:00:09Z
sup --record "$ref" --start 2026-11-04T10:00:11Z --source event:2026-11-04T10:00:11Z
sr list --run "$r" --effective >"$tmp/list"
grep -q "^start${TAB}2026-11-04T10:00:11Z$" "$tmp/list" && ! grep -q "^start${TAB}2026-11-04T10:00:09Z$" "$tmp/list"
verdict $? "of two supersedes of one record, the later one stands" "$(cat "$tmp/list")"
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

if [ "$failures" -gt 0 ]; then
  printf '%s failure(s)\n' "$failures" >&2
  exit 1
fi
echo "All step-record supersede tests passed."
