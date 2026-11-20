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
    --backend in-session --head "$_h" --end-head "${9:-$_h}" --start "$6" --end "$7" --outcome "$5" \
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
srec "$r" convergence polish /polish passed 2026-11-04T10:00:13Z 2026-11-04T10:00:47Z
done_at "$r" convergence
audit --through convergence
[ "$RC" -eq 1 ] && faulted convergence "start 2026-11-04T10:00:13Z .*polish Skill call.*nearest call at 2026-11-04T10:00:11Z"
verdict $? "a polish start two seconds off its Skill call is a fault naming both seconds" \
  "rc $RC: $(cat "$tmp/audit" "$tmp/audit.err")"
r=$(sr new-run)
srec "$r" convergence polish /polish passed 2026-11-04T10:00:11Z 2026-11-04T10:00:47Z
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
srec "$r" convergence polish /polish passed 2026-11-04T10:00:13Z 2026-11-04T10:00:47Z
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
srec "$r" convergence polish /polish applied 2026-11-04T10:00:11Z 2026-11-04T10:00:47Z "$old" "$(head_of)"
done_at "$r" convergence
forged="$wt/.claude/steps/$r/001-step-convergence.rec"
awk -F '\t' 'BEGIN { OFS = FS } $1 == "outcome" { $2 = "passed" } { print }' "$forged" >"$forged.new" && mv "$forged.new" "$forged"
audit --through convergence --head "$(head_of)"
[ "$RC" -eq 1 ] && faulted convergence "head moved"
verdict $? "the audit faults a polish record that says passed on a moved head" "rc $RC: $(cat "$tmp/audit" "$tmp/audit.err")"
grep -q "^gap${TAB}convergence${TAB}unaudited${TAB}polish$" "$tmp/audit"
verdict $? "and the step-record truth check leaves the same step unaudited beside the fault" "$(cat "$tmp/audit")"

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
prec "$r" post-pr fix-round-1 "fix the review findings" passed 2026-11-04T09:50:07Z 2026-11-04T10:30:19Z
done_at "$r" post-pr
audit --through post-pr
[ "$RC" -eq 1 ] && faulted post-pr "start 2026-11-04T09:50:07Z is before the session first event at 2026-11-04T10:00:00Z"
verdict $? "a fix-round record starting before the first event is a fault" "rc $RC: $(cat "$tmp/audit" "$tmp/audit.err")"
r2=$(sr new-run)
prec "$r2" post-pr fix-round-1 "fix the review findings" passed 2026-11-04T09:50:07Z 2026-11-04T10:30:19Z
done_at "$r2" post-pr
audit --through post-pr
[ "$RC" -eq 0 ]
verdict $? "a fresh run repeating that round with the earlier record's start is allowed" "rc $RC: $(cat "$tmp/audit")"
r3=$(sr new-run)
prec "$r3" post-pr fix-round-1 "fix the review findings" passed 2026-11-04T09:40:07Z 2026-11-04T10:30:19Z
done_at "$r3" post-pr
audit --through post-pr
[ "$RC" -eq 1 ] && faulted post-pr "start 2026-11-04T09:40:07Z is before the session first event"
verdict $? "a repeat whose start matches no earlier record of the round is still a fault" "rc $RC: $(cat "$tmp/audit")"
fresh
catalog "$FIX"
config 'steps_convergence: []' 'steps_post_pr: [fix-round-1]'
session 2026-11-04T10:00:00
r=$(sr new-run)
prec "$r" post-pr fix-round-1 "fix the review findings" passed 2026-11-04T10:10:07Z 2026-11-04T10:30:19Z
done_at "$r" post-pr
r2=$(sr new-run)
prec "$r2" post-pr fix-round-1 "fix the review findings" passed 2026-11-04T10:10:07Z 2026-11-04T10:30:19Z
done_at "$r2" post-pr
audit --through post-pr
[ "$RC" -eq 0 ]
verdict $? "a repeated round starting after the first event passes" "rc $RC: $(cat "$tmp/audit" "$tmp/audit.err")"
fresh
catalog "$FIX"
config 'steps_convergence: []' 'steps_post_pr: [fix-round-1]'
session 2026-11-04T09:00:00
call 2026-11-04T09:10:00 Agent
n=$((n + 1))
session 2026-11-04T10:00:00
call 2026-11-04T10:31:00 Agent
r=$(sr new-run)
prec "$r" post-pr fix-round-1 "fix the review findings" passed 2026-11-04T09:50:07Z 2026-11-04T10:30:19Z
done_at "$r" post-pr
audit --through post-pr
[ "$RC" -eq 1 ] && faulted post-pr "start 2026-11-04T09:50:07Z is before the session first event at 2026-11-04T10:00:00Z"
verdict $? "an earlier session in the worktree does not cover a fix round started before its own session" \
  "rc $RC: $(cat "$tmp/audit" "$tmp/audit.err")"
fresh
catalog "$FIX"
config 'steps_convergence: []' 'steps_post_pr: [fix-round-1]'
session 2026-11-04T10:00:00
call 2026-11-04T10:31:00 Agent
n=$((n + 1))
session 2026-11-04T10:20:00
call 2026-11-04T10:40:00 Agent
r=$(sr new-run)
prec "$r" post-pr fix-round-1 "fix the review findings" passed 2026-11-04T10:05:07Z 2026-11-04T10:30:19Z
done_at "$r" post-pr
audit --through post-pr
[ "$RC" -eq 0 ]
verdict $? "a session opened inside a fix round's span does not fault the round" "rc $RC: $(cat "$tmp/audit" "$tmp/audit.err")"

# --- events that cannot be reached are reported, never passed silently ---------
fresh
catalog "$POLISH"
config 'steps_convergence: [polish]'
r=$(sr new-run)
srec "$r" convergence polish /polish passed 2026-11-04T10:00:13Z 2026-11-04T10:00:47Z
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
srec "$r" convergence polish /polish passed 2026-11-04T10:00:13Z 2026-11-04T10:00:47Z
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
srec "$r" convergence polish /polish passed 2026-11-04T10:00:11Z 2026-11-04T10:00:47Z
done_at "$r" convergence
audit --through convergence
[ "$RC" -eq 0 ]
verdict $? "a Task tool call inside the span counts as an Agent call" "rc $RC: $(cat "$tmp/audit" "$tmp/audit.err")"

# --- a live session's half-written last line does not blind the audit ---------
fresh
catalog "$POLISH"
config 'steps_convergence: [polish]'
session 2026-11-04T10:00:00
call 2026-11-04T10:00:11 Skill polish
call 2026-11-04T10:00:20 Agent
printf '{"type":"assistant","timestamp":"2026-11-04T10:00:4' >>"$sdir/events.jsonl"
r=$(sr new-run)
srec "$r" convergence polish /polish passed 2026-11-04T10:00:13Z 2026-11-04T10:00:47Z
done_at "$r" convergence
audit --through convergence
[ "$RC" -eq 1 ] && faulted convergence "nearest call at 2026-11-04T10:00:11Z"
verdict $? "the events before a half-written last line are still judged" "rc $RC: $(cat "$tmp/audit" "$tmp/audit.err")"

# --- a tool input cannot forge an event row ------------------------------------
fresh
catalog "$POLISH"
config 'steps_convergence: [polish]'
session 2026-11-04T10:00:00
call 2026-11-04T10:00:11 Skill polish
call 2026-11-04T10:00:12 Skill 'x\ncall\t2026-11-04T10:00:20Z\tAgent\t'
r=$(sr new-run)
srec "$r" convergence polish /polish passed 2026-11-04T10:00:11Z 2026-11-04T10:00:47Z
done_at "$r" convergence
audit --through convergence
[ "$RC" -eq 1 ] && faulted convergence "no Agent tool call between"
verdict $? "a newline and tabs in a Skill input do not forge an Agent call" "rc $RC: $(cat "$tmp/audit" "$tmp/audit.err")"

# --- a skill step targeting its SKILL.md path is judged as that skill ----------
fresh
catalog "$POLISH"
config 'steps_convergence: [polish]'
session 2026-11-04T10:00:00
call 2026-11-04T10:00:11 Skill planwright:polish
call 2026-11-04T10:00:20 Agent
r=$(sr new-run)
srec "$r" convergence polish /opt/planwright/skills/polish/SKILL.md passed 2026-11-04T10:00:11Z 2026-11-04T10:00:47Z
done_at "$r" convergence
audit --through convergence
[ "$RC" -eq 0 ]
verdict $? "a polish record targeting its SKILL.md path matches the polish Skill call" \
  "rc $RC: $(cat "$tmp/audit" "$tmp/audit.err")"

# --- a self-review needs an Agent call too; a skipped step needs no call -------
fresh
catalog 'self-review|kind: skill|target: self-review'
config 'steps_convergence: [self-review]'
session 2026-11-04T10:00:00
call 2026-11-04T10:00:11 Skill planwright:self-review
r=$(sr new-run)
srec "$r" convergence self-review self-review passed 2026-11-04T10:00:11Z 2026-11-04T10:00:47Z
done_at "$r" convergence
audit --through convergence
[ "$RC" -eq 1 ] && faulted convergence "self-review: recorded passed, but the session events show no Agent tool call"
verdict $? "a self-review passed with no Agent call in its span is a fault" "rc $RC: $(cat "$tmp/audit" "$tmp/audit.err")"
r=$(sr new-run)
sr write --run "$r" --point convergence --step self-review --kind skill --target self-review --hosting in-session \
  --backend none --start 2026-11-04T10:00:40Z --end 2026-11-04T10:00:41Z --outcome skipped --skip-code missing \
  >"$tmp/w.out" 2>&1 || fail "fixture: the skipped record: $(cat "$tmp/w.out")"
done_at "$r" convergence
audit --through convergence
[ "$RC" -eq 0 ]
verdict $? "a skipped skill step with no Skill call is not a fault" "rc $RC: $(cat "$tmp/audit" "$tmp/audit.err")"

# --- only the records that decided a point are judged --------------------------
fresh
catalog "$POLISH" "$BOT"
config 'steps_convergence: [polish]' 'steps_post_pr: [cubic-pr]'
session 2026-11-04T10:00:00
call 2026-11-04T10:00:11 Skill polish
call 2026-11-04T10:00:20 Agent
call 2026-11-04T10:05:07 Skill bot-review
ra=$(sr new-run)
srec "$ra" convergence polish /polish passed 2026-11-04T10:00:13Z 2026-11-04T10:00:47Z
done_at "$ra" convergence
srec "$ra" post-pr cubic-pr bot-review passed 2026-11-04T10:05:07Z 2026-11-04T10:06:19Z
done_at "$ra" post-pr
rb=$(sr new-run)
srec "$rb" convergence polish /polish passed 2026-11-04T10:00:11Z 2026-11-04T10:00:47Z
done_at "$rb" convergence
audit --through post-pr
[ "$RC" -eq 0 ]
verdict $? "a superseded record in a run that decided another point is not judged" \
  "rc $RC: $(cat "$tmp/audit" "$tmp/audit.err")"

# --- a run is attributed by the worktree it is recorded in ---------------------
# two_worktrees: a fresh A and a second worktree B of it ($wta, $wtb), $wt left at A.
two_worktrees() {
  fresh
  catalog "$POLISH" "$FIX"
  config 'steps_convergence: [polish]'
  wta=$wt
  wtb="$tmp/wtb$n"
  git -C "$wta" worktree add -q -b planwright/flight/review-b "$wtb" || fail "fixture: worktree B"
}
# names_b <command text>: an event of the session in $sdir running that text.
names_b() {
  printf '{"type":"assistant","timestamp":"2026-11-04T10:20:03.000Z","message":{"content":[{"type":"tool_use","name":"Bash","input":{"command":"%s"}}]}}\n' "$1" >>"$sdir/events.jsonl"
}
# One reviewer session launched in worktree A records a review run into
# worktree B (the pull request's own worktree, where an earlier session of its
# author ran). B's audit counts the run; A's, holding no such run, does not.
two_worktrees
# B's author session: launched in B, never saw the review.
wt=$wtb
session 2026-11-04T10:00:00
call 2026-11-04T10:00:05 Skill planwright:execute-task
# The reviewer session: launched in A, reviews B's branch.
wt=$wta
n=$((n + 1))
session 2026-11-04T10:20:00
names_b "step-record.sh --worktree $wtb list"
call 2026-11-04T10:30:11 Skill planwright:polish
call 2026-11-04T10:30:20 Agent
reviewer_dir=$sdir
wt=$wtb
r=$(sr new-run)
srec "$r" convergence polish /polish passed 2026-11-04T10:30:11Z 2026-11-04T10:30:47Z
done_at "$r" convergence
audit --through convergence
[ "$RC" -eq 0 ] && ! grep -q "^gap${TAB}" "$tmp/audit" && grep -q "^audit${TAB}complete${TAB}" "$tmp/audit"
verdict $? "a review run recorded in B by a session launched in A counts for B's audit" \
  "rc $RC: $(cat "$tmp/audit" "$tmp/audit.err")"
wt=$wta
audit --through convergence
[ "$RC" -eq 1 ] && grep -q "^gap${TAB}convergence${TAB}incomplete${TAB}" "$tmp/audit"
verdict $? "and does not count for A's audit, which holds no such run" "rc $RC: $(cat "$tmp/audit" "$tmp/audit.err")"
# The attribution does not loosen the timing: a start off every Skill call is still a fault.
wt=$wtb
r=$(sr new-run)
srec "$r" convergence polish /polish passed 2026-11-04T10:30:13Z 2026-11-04T10:30:47Z
done_at "$r" convergence
audit --through convergence
[ "$RC" -eq 1 ] && faulted convergence "start 2026-11-04T10:30:13Z .*polish Skill call.*nearest call at 2026-11-04T10:30:11Z" \
  && ! faulted convergence "no Agent tool call"
verdict $? "a start two seconds off the other session's Skill call is still a fault, and only that one" "rc $RC: $(cat "$tmp/audit" "$tmp/audit.err")"
# A session that never touched B cannot have written its records.
printf '{"type":"user","timestamp":"2026-11-04T10:20:00.100Z","message":{"content":"go"}}\n' >"$reviewer_dir/events.jsonl"
printf '{"type":"assistant","timestamp":"2026-11-04T10:30:11.700Z","message":{"content":[{"type":"tool_use","name":"Skill","input":{"skill":"polish"}}]}}\n' >>"$reviewer_dir/events.jsonl"
printf '{"type":"assistant","timestamp":"2026-11-04T10:30:20.700Z","message":{"content":[{"type":"tool_use","name":"Agent","input":{}}]}}\n' >>"$reviewer_dir/events.jsonl"
r=$(sr new-run)
srec "$r" convergence polish /polish passed 2026-11-04T10:30:11Z 2026-11-04T10:30:47Z
done_at "$r" convergence
audit --through convergence
[ "$RC" -eq 1 ] && faulted convergence "no such call"
verdict $? "a session whose events never name B is not counted toward B's records" "rc $RC: $(cat "$tmp/audit" "$tmp/audit.err")"
# A session naming a longer path that merely starts with B's is not B's either.
sdir=$reviewer_dir
names_b "ls ${wtb}0/src"
audit --through convergence
[ "$RC" -eq 1 ] && faulted convergence "no such call"
verdict $? "nor one naming only a longer path that begins with B's" "rc $RC: $(cat "$tmp/audit" "$tmp/audit.err")"

# --- what a session that only names B may vouch for ---------------------------
# An Agent call of another session that only names B does not satisfy the span:
# only the session whose Skill call vouched for the start may. A decoy named
# session holding a polish Skill call a second off does not vouch either.
two_worktrees
session 2026-11-04T10:20:00
names_b "step-record.sh --worktree $wtb list"
call 2026-11-04T10:30:11 Skill planwright:polish
reviewer_dir=$sdir
n=$((n + 1))
session 2026-11-04T10:20:00
names_b "git worktree list: $wtb  abcdef0 [review-b]"
call 2026-11-04T10:30:12 Skill planwright:polish
call 2026-11-04T10:30:20 Agent
wt=$wtb
r=$(sr new-run)
srec "$r" convergence polish /polish passed 2026-11-04T10:30:11Z 2026-11-04T10:30:47Z
done_at "$r" convergence
audit --through convergence
[ "$RC" -eq 1 ] && faulted convergence "no Agent tool call between 2026-11-04T10:30:11Z and 2026-11-04T10:30:47Z"
verdict $? "another named session's Agent call does not stand in for the reviewer's own" "rc $RC: $(cat "$tmp/audit" "$tmp/audit.err")"
# The same Agent call inside the reviewer's own session satisfies it.
sdir=$reviewer_dir
call 2026-11-04T10:30:20 Agent
audit --through convergence
[ "$RC" -eq 0 ] && ! grep -q -e "^gap" -e "^note" "$tmp/audit"
verdict $? "the Agent call inside the reviewer's own session satisfies the span" "rc $RC: $(cat "$tmp/audit" "$tmp/audit.err")"

# A named session never sets the fix-round floor: with no session launched in
# B, a fix-round start is unverified, not passed.
two_worktrees
config 'steps_convergence: []' 'steps_post_pr: [fix-round-1]'
session 2026-11-04T10:20:00
names_b "step-record.sh --worktree $wtb list"
call 2026-11-04T10:30:11 Skill planwright:polish
wt=$wtb
r=$(sr new-run)
prec "$r" post-pr fix-round-1 "fix the review findings" passed 2026-11-04T09:00:07Z 2026-11-04T09:30:19Z
done_at "$r" post-pr
audit --through post-pr
[ "$RC" -eq 0 ] && grep -q "^note${TAB}post-pr${TAB}unverified${TAB}.*fix-round-1: no session was launched in the worktree" "$tmp/audit"
verdict $? "a fix round with only a named session is unverified, not silently passed" \
  "rc $RC: $(cat "$tmp/audit" "$tmp/audit.err")"

# With no session launched in B, a session that merely names it cannot prove a
# Skill call absent: the start is unverified, not a fault.
two_worktrees
config 'steps_convergence: [polish]'
session 2026-11-04T10:20:00
names_b "git worktree list: $wtb  abcdef0 [review-b]"
call 2026-11-04T10:25:00 Skill planwright:mission-control
wt=$wtb
r=$(sr new-run)
srec "$r" convergence polish /polish passed 2026-11-04T10:30:11Z 2026-11-04T10:30:47Z
done_at "$r" convergence
audit --through convergence
[ "$RC" -eq 0 ] && grep -q "^note${TAB}convergence${TAB}unverified${TAB}.*polish: no session was launched in the worktree" "$tmp/audit"
verdict $? "a hub session naming B with no matching Skill call leaves a skill step unverified, not faulted" \
  "rc $RC: $(cat "$tmp/audit" "$tmp/audit.err")"

# A session that names B but holds no Skill or Agent call at all gives no
# evidence either way: the step is unverified, with that reason.
two_worktrees
session 2026-11-04T10:20:00
names_b "git worktree list: $wtb  abcdef0 [review-b]"
wt=$wtb
r=$(sr new-run)
srec "$r" convergence polish /polish passed 2026-11-04T10:30:11Z 2026-11-04T10:30:47Z
done_at "$r" convergence
audit --through convergence
[ "$RC" -eq 0 ] && grep -q "^note${TAB}convergence${TAB}unverified${TAB}.*polish: no session that names the worktree holds a timestamped Skill or Agent call" "$tmp/audit"
verdict $? "a named session with no Skill or Agent call leaves a skill step unverified, saying so" \
  "rc $RC: $(cat "$tmp/audit" "$tmp/audit.err")"

# B's own session holds the Skill call and the reviewer session (named) the
# Agent call: the Agent call vouches only for a Skill call of its own session.
two_worktrees
wt=$wtb
session 2026-11-04T10:00:00
call 2026-11-04T10:30:11 Skill planwright:polish
wt=$wta
n=$((n + 1))
session 2026-11-04T10:20:00
names_b "step-record.sh --worktree $wtb list"
call 2026-11-04T10:30:20 Agent
wt=$wtb
r=$(sr new-run)
srec "$r" convergence polish /polish passed 2026-11-04T10:30:11Z 2026-11-04T10:30:47Z
done_at "$r" convergence
audit --through convergence
[ "$RC" -eq 1 ] && faulted convergence "no Agent tool call between"
verdict $? "a named session's Agent call does not vouch for a Skill call of B's own session" \
  "rc $RC: $(cat "$tmp/audit" "$tmp/audit.err")"
sdir="$tmp/fleet/streamjson/s$((n - 1))"
call 2026-11-04T10:30:25 Agent
audit --through convergence
[ "$RC" -eq 0 ] && ! grep -q -e "^gap" -e "^note" "$tmp/audit"
verdict $? "while an Agent call of B's own session does" "rc $RC: $(cat "$tmp/audit" "$tmp/audit.err")"

# A named session's Skill call with an Agent call in B's own session passes.
two_worktrees
wt=$wtb
session 2026-11-04T10:00:00
call 2026-11-04T10:30:25 Agent
wt=$wta
n=$((n + 1))
session 2026-11-04T10:20:00
names_b "step-record.sh --worktree $wtb list"
call 2026-11-04T10:30:11 Skill planwright:polish
wt=$wtb
r=$(sr new-run)
srec "$r" convergence polish /polish passed 2026-11-04T10:30:11Z 2026-11-04T10:30:47Z
done_at "$r" convergence
audit --through convergence
[ "$RC" -eq 0 ] && ! grep -q -e "^gap" -e "^note" "$tmp/audit"
verdict $? "a named session's Skill call is enough when B's own session holds the Agent call" \
  "rc $RC: $(cat "$tmp/audit" "$tmp/audit.err")"

# A named session that opened earlier does not lower the fix-round floor: the
# fix round starts before B's own session opened, so it faults.
two_worktrees
config 'steps_convergence: []' 'steps_post_pr: [fix-round-1]'
wt=$wtb
session 2026-11-04T10:10:00
wt=$wta
n=$((n + 1))
session 2026-11-04T09:00:00
names_b "step-record.sh --worktree $wtb list"
call 2026-11-04T09:00:05 Skill planwright:mission-control
wt=$wtb
r=$(sr new-run)
prec "$r" post-pr fix-round-1 "fix the review findings" passed 2026-11-04T09:30:07Z 2026-11-04T09:45:19Z
done_at "$r" post-pr
audit --through post-pr
[ "$RC" -eq 1 ] && faulted post-pr "start 2026-11-04T09:30:07Z is before the session first event at 2026-11-04T10:10:00Z"
verdict $? "an earlier named session does not lower the fix-round floor" "rc $RC: $(cat "$tmp/audit" "$tmp/audit.err")"

# Each way a path ends in an event names it. B has no session of its own, so a
# session not found leaves the step unverified: a note counts as a miss.
two_worktrees
wt=$wtb
r=$(sr new-run)
srec "$r" convergence polish /polish passed 2026-11-04T10:30:11Z 2026-11-04T10:30:47Z
done_at "$r" convergence
for term in quote slash newline apostrophe semicolon paren; do
  wt=$wta
  session 2026-11-04T10:20:00
  case $term in
    quote) printf '{"type":"assistant","timestamp":"2026-11-04T10:20:03.000Z","message":{"content":[{"type":"tool_use","name":"Read","input":{"cwd":"%s"}}]}}\n' "$wtb" >>"$sdir/events.jsonl" ;;
    slash) names_b "ls $wtb/src" ;;
    newline) names_b "cd $wtb\\npwd" ;;
    apostrophe) names_b "cd '$wtb'" ;;
    semicolon) names_b "cd $wtb; ls" ;;
    paren) names_b "(cd $wtb)" ;;
  esac
  call 2026-11-04T10:30:11 Skill planwright:polish
  call 2026-11-04T10:30:20 Agent
  wt=$wtb
  audit --through convergence
  [ "$RC" -eq 0 ] && ! grep -q -e "^gap" -e "^note" "$tmp/audit"
  verdict $? "a session naming B ending in a $term counts for B's records" "rc $RC: $(cat "$tmp/audit" "$tmp/audit.err")"
done

if [ "$failures" -gt 0 ]; then
  printf '%s failure(s)\n' "$failures" >&2
  exit 1
fi
echo "All step-run audit-events tests passed."
