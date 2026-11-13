#!/bin/sh
# Tests for the audit's check of step records against the session's own event
# stream (scripts/step-events-audit.sh via step-run.sh audit) and for the two
# write-time refusals that belong with it (a future --end, a polish passed on
# a moved head).
#
# Runs standalone under /bin/sh (the bash 3.2 / dash floor):
#   ./tests/test-step-run-audit-events.sh
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
FIX='fix-round-1|kind: prompt|target: fix the review findings'
BOT='cubic-pr|kind: skill|target: bot-review'

audit() {
  srun audit "$@" >"$tmp/audit" 2>"$tmp/audit.err"
  RC=$?
}
# session <first event stamp>: this worktree's stream-json session, opened by
# an event at the stamp. call <stamp> <tool> [<skill>]: one tool call of it.
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
# srec <run> <point> <step> <target> <outcome> <start> <end> [<head> [<end-head>]]:
# an in-session skill step record.
srec() {
  _h=${8:-$(head_of)}
  sr write --run "$1" --point "$2" --step "$3" --kind "$KIND" --target "$4" --hosting in-session \
    --backend none --head "$_h" --end-head "${9:-$_h}" --start "$6" --end "$7" --outcome "$5" \
    >"$tmp/srec.out" 2>&1 || fail "fixture: the $3 record: $(cat "$tmp/srec.out")"
}
KIND=skill
prec() {
  KIND=prompt
  srec "$@"
  KIND=skill
}
done_at() { sr write --completion --run "$1" --point "$2" >/dev/null || fail "fixture: the $2 completion"; }
faulted() { grep -q "^gap${TAB}$1${TAB}fault${TAB}.*$2" "$tmp/audit"; }

# --- 1: a skill step starts on the second of its Skill call -------------------
fresh
catalog "$POLISH"
config 'steps_convergence: [polish]'
session 2026-11-04T10:00:00
call 2026-11-04T10:00:11 Skill planwright:polish
call 2026-11-04T10:00:20 Agent
r=$(sr new-run)
srec "$r" convergence polish /polish applied 2026-11-04T10:00:13Z 2026-11-04T10:00:30Z
done_at "$r" convergence
audit --through convergence
[ "$RC" -eq 1 ] && faulted convergence "start 2026-11-04T10:00:13Z .*polish Skill call.*nearest call at 2026-11-04T10:00:11Z"
verdict $? "a polish start two seconds off its Skill call is a fault naming both seconds" \
  "rc $RC: $(cat "$tmp/audit" "$tmp/audit.err")"
r=$(sr new-run)
srec "$r" convergence polish /polish applied 2026-11-04T10:00:11Z 2026-11-04T10:00:30Z
done_at "$r" convergence
audit --through convergence
[ "$RC" -eq 0 ]
verdict $? "a start on the Skill call's second passes" "rc $RC: $(cat "$tmp/audit" "$tmp/audit.err")"

fresh
catalog "$BOT"
config 'steps_convergence: []' 'steps_post_pr: [cubic-pr]'
session 2026-11-04T10:00:00
call 2026-11-04T10:05:00 Skill bot-review
r=$(sr new-run)
srec "$r" post-pr cubic-pr bot-review limited 2026-11-04T10:04:58Z 2026-11-04T10:06:00Z
done_at "$r" post-pr
audit --through post-pr
[ "$RC" -eq 1 ] && faulted post-pr "start 2026-11-04T10:04:58Z .*bot-review Skill call"
verdict $? "a cubic-pr record started at the trigger comment, not the Skill call, is a fault" \
  "rc $RC: $(cat "$tmp/audit" "$tmp/audit.err")"

fresh
catalog "$POLISH"
config 'steps_convergence: [polish]'
session 2026-11-04T10:00:00
r=$(sr new-run)
srec "$r" convergence polish /polish applied 2026-11-04T10:00:13Z 2026-11-04T10:00:30Z
done_at "$r" convergence
audit --through convergence
[ "$RC" -eq 1 ] && faulted convergence "no such call"
verdict $? "a skill step with no Skill call in the events at all is a fault" "rc $RC: $(cat "$tmp/audit")"

# --- 2: a polish passed or applied has an Agent call in its span --------------
fresh
catalog "$POLISH"
config 'steps_convergence: [polish]'
session 2026-11-04T10:00:00
call 2026-11-04T10:00:11 Skill polish
call 2026-11-04T10:01:30 Agent
r=$(sr new-run)
srec "$r" convergence polish /polish passed 2026-11-04T10:00:11Z 2026-11-04T10:01:00Z
done_at "$r" convergence
audit --through convergence
[ "$RC" -eq 1 ] && faulted convergence "no Agent tool call between 2026-11-04T10:00:11Z and 2026-11-04T10:01:00Z"
verdict $? "a polish passed with no Agent call inside its span is a fault naming the span" \
  "rc $RC: $(cat "$tmp/audit" "$tmp/audit.err")"
r=$(sr new-run)
srec "$r" convergence polish /polish passed 2026-11-04T10:00:11Z 2026-11-04T10:02:00Z
done_at "$r" convergence
audit --through convergence
[ "$RC" -eq 0 ]
verdict $? "an Agent call inside the span passes" "rc $RC: $(cat "$tmp/audit" "$tmp/audit.err")"

# --- 3: a polish passed ended on the head it began on --------------------------
fresh
catalog "$POLISH"
config 'steps_convergence: [polish]'
session 2026-11-04T10:00:00
call 2026-11-04T10:00:11 Skill polish
call 2026-11-04T10:00:20 Agent
old=$(head_of)
printf 'x\n' >>"$wt/src/a.txt" && git -C "$wt" add -A && git -C "$wt" commit -q -m "fix: moved"
r=$(sr new-run)
if sr write --run "$r" --point convergence --step polish --kind skill --target polish --hosting in-session \
  --backend none --head "$old" --end-head "$(head_of)" --start 2026-11-04T10:00:11Z --end 2026-11-04T10:00:30Z \
  --outcome passed >"$tmp/w.out" 2>&1; then rc=0; else rc=1; fi
[ "$rc" -eq 1 ] && grep -q "applied, not passed" "$tmp/w.out"
verdict $? "write refuses a polish passed whose head moved, naming both heads" "$(cat "$tmp/w.out")"
if sr write --run "$r" --point convergence --step polish-again --kind skill --target planwright:polish --hosting in-session \
  --backend none --head "$old" --end-head "$(head_of)" --start 2026-11-04T10:00:11Z --end 2026-11-04T10:00:30Z \
  --outcome passed >"$tmp/w.out" 2>&1; then rc=0; else rc=1; fi
[ "$rc" -eq 1 ] && grep -q "applied, not passed" "$tmp/w.out"
verdict $? "write refuses a passed polish skill step under another step name on a moved head" "rc $rc: $(cat "$tmp/w.out")"
if sr write --run "$r" --point convergence --step polish-path --kind skill --target /opt/planwright/skills/polish/SKILL.md --hosting in-session \
  --backend none --head "$old" --end-head "$(head_of)" --start 2026-11-04T10:00:11Z --end 2026-11-04T10:00:30Z \
  --outcome passed >"$tmp/w.out" 2>&1; then rc=0; else rc=1; fi
[ "$rc" -eq 1 ] && grep -q "applied, not passed" "$tmp/w.out"
verdict $? "write refuses a passed polish skill step targeting its SKILL.md path on a moved head" "rc $rc: $(cat "$tmp/w.out")"
srec "$r" convergence polish /polish applied 2026-11-04T10:00:11Z 2026-11-04T10:00:30Z "$old" "$(head_of)"
done_at "$r" convergence
forged="$wt/.claude/steps/$r/001-step-convergence.rec"
awk -F '\t' 'BEGIN { OFS = FS } $1 == "outcome" { $2 = "passed" } { print }' "$forged" >"$forged.new" && mv "$forged.new" "$forged"
audit --through convergence --head "$(head_of)"
[ "$RC" -eq 1 ] && faulted convergence "head moved"
verdict $? "the audit faults a polish record that says passed on a moved head" "rc $RC: $(cat "$tmp/audit" "$tmp/audit.err")"

# --- 4: write refuses an end later than the clock ------------------------------
fresh
catalog "$POLISH"
r=$(sr new-run)
if sr write --run "$r" --point convergence --step polish --kind skill --target polish --hosting in-session \
  --backend none --start 2026-11-04T10:00:11Z --end 2099-01-01T00:00:00Z --outcome applied >"$tmp/w.out" 2>&1; then rc=0; else rc=1; fi
[ "$rc" -eq 1 ] && grep -q "later than the moment of writing" "$tmp/w.out"
verdict $? "write refuses a future --end, naming the clock and the stamp" "$(cat "$tmp/w.out")"

# --- 5: a fix round does not start before the session's first event ------------
fresh
catalog "$FIX"
config 'steps_convergence: []' 'steps_post_pr: [fix-round-1]'
session 2026-11-04T10:00:00
r=$(sr new-run)
prec "$r" post-pr fix-round-1 "fix the review findings" applied 2026-11-04T09:50:00Z 2026-11-04T10:30:00Z
done_at "$r" post-pr
audit --through post-pr
[ "$RC" -eq 1 ] && faulted post-pr "start 2026-11-04T09:50:00Z is before the session first event at 2026-11-04T10:00:00Z"
verdict $? "a fix-round record starting before the first event is a fault" "rc $RC: $(cat "$tmp/audit" "$tmp/audit.err")"
r2=$(sr new-run)
prec "$r2" post-pr fix-round-1 "fix the review findings" applied 2026-11-04T09:50:00Z 2026-11-04T10:30:00Z
done_at "$r2" post-pr
audit --through post-pr
[ "$RC" -eq 0 ]
verdict $? "a fresh run repeating that round with the earlier record's start is allowed" "rc $RC: $(cat "$tmp/audit")"
r3=$(sr new-run)
prec "$r3" post-pr fix-round-1 "fix the review findings" applied 2026-11-04T09:40:00Z 2026-11-04T10:30:00Z
done_at "$r3" post-pr
audit --through post-pr
[ "$RC" -eq 1 ] && faulted post-pr "start 2026-11-04T09:40:00Z is before the session first event"
verdict $? "a repeat whose start matches no earlier record of the round is still a fault" "rc $RC: $(cat "$tmp/audit")"
fresh
catalog "$FIX"
config 'steps_convergence: []' 'steps_post_pr: [fix-round-1]'
session 2026-11-04T10:00:00
r=$(sr new-run)
prec "$r" post-pr fix-round-1 "fix the review findings" applied 2026-11-04T10:10:00Z 2026-11-04T10:30:00Z
done_at "$r" post-pr
r2=$(sr new-run)
prec "$r2" post-pr fix-round-1 "fix the review findings" applied 2026-11-04T10:10:00Z 2026-11-04T10:30:00Z
done_at "$r2" post-pr
audit --through post-pr
[ "$RC" -eq 0 ]
verdict $? "a repeated round starting after the first event passes" "rc $RC: $(cat "$tmp/audit" "$tmp/audit.err")"

# --- events that cannot be reached are reported, never passed silently ---------
fresh
catalog "$POLISH"
config 'steps_convergence: [polish]'
r=$(sr new-run)
srec "$r" convergence polish /polish applied 2026-11-04T10:00:13Z 2026-11-04T10:00:30Z
done_at "$r" convergence
audit --through convergence
[ "$RC" -eq 0 ] && grep -q "^note${TAB}convergence${TAB}unverified${TAB}.*polish: the session events are not reachable" "$tmp/audit" \
  && grep -q "^audit${TAB}complete${TAB}" "$tmp/audit"
verdict $? "with no session events the audit says it cannot verify the skill record, and a note is not a gap" \
  "rc $RC: $(cat "$tmp/audit" "$tmp/audit.err")"

fresh
catalog "$POLISH"
config 'steps_convergence: [polish]'
session 2026-11-04T10:00:00
printf '{"type":"user","message":{"content":"go"}}\n' >"$sdir/events.jsonl"
r=$(sr new-run)
srec "$r" convergence polish /polish applied 2026-11-04T10:00:13Z 2026-11-04T10:00:30Z
done_at "$r" convergence
audit --through convergence
[ "$RC" -eq 0 ] && grep -q "^note${TAB}convergence${TAB}unverified${TAB}.*polish: the session events carry no timestamps" "$tmp/audit"
verdict $? "events carrying no timestamps are unverified, never a false fault or a silent pass" \
  "rc $RC: $(cat "$tmp/audit" "$tmp/audit.err")"

# --- the Task tool name counts as an Agent call --------------------------------
fresh
catalog "$POLISH"
config 'steps_convergence: [polish]'
session 2026-11-04T10:00:00
call 2026-11-04T10:00:11 Skill polish
call 2026-11-04T10:00:20 Task
r=$(sr new-run)
srec "$r" convergence polish /polish passed 2026-11-04T10:00:11Z 2026-11-04T10:00:30Z
done_at "$r" convergence
audit --through convergence
[ "$RC" -eq 0 ]
verdict $? "a Task tool call inside the span counts as an Agent call" "rc $RC: $(cat "$tmp/audit" "$tmp/audit.err")"

if [ "$failures" -gt 0 ]; then
  printf '%s failure(s)\n' "$failures" >&2
  exit 1
fi
echo "All step-run audit-events tests passed."
