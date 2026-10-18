#!/bin/sh
# Tests for scripts/step-run.sh's resume continuation, its session-hosted
# begin and end, and /execute-task's wiring of the runner (custom-steps
# Task 14; REQ-D1.11, REQ-I1.1, REQ-I1.9, REQ-J1.1; D-29, D-30).
#
# Each scenario drives the runner's calls the way the skill sequences them,
# over fixture overlays in the adopter layer: a fixture worktree with a bare
# origin, a private pools root, and fixture command steps that log the
# context they saw.
#
# Runs standalone under /bin/sh (the bash 3.2 / dash floor):
#   ./tests/test-step-run-resume.sh
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

[ -x "$RUN" ] || {
  echo "FAIL: scripts/step-run.sh missing or not executable" >&2
  exit 1
}
# shellcheck source=tests/lib/step-run-fixture.sh
. "$here/lib/step-run-fixture.sh"

# --- resume continuation (REQ-J1.1) ---------------------------------------------------------
fresh
catalog "one|kind: command|target: $bin/show.sh" "two|kind: command|target: $bin/show.sh" \
  "three|kind: command|target: $bin/show.sh"
config 'steps_post_pr: [one, two, three]'
r1=$(sr new-run)
srun resolve --run "$r1" post-pr --unattended >/dev/null 2>&1
srun command --run "$r1" --point post-pr --step one >/dev/null 2>&1
srun command --run "$r1" --point post-pr --step two >/dev/null 2>&1
r2=$(sr new-run)
srun resume --run "$r2" --from "$r1:post-pr" >"$tmp/skips"
[ "$(cut -f 2 "$tmp/skips" | tr '\n' ' ')" = "one two " ] \
  && [ "$(recs "$r2" post-pr | grep -c "^skip-code${TAB}resume$")" -eq 2 ] \
  && [ -z "$(recs "$r2" pre-pr)" ]
verdict "a resume skips the interrupted run's passing prefix, no earlier point firing" "skips: $(cat "$tmp/skips")"
r3=$(sr new-run)
srun resume --run "$r3" --from "$r2:post-pr" >"$tmp/skips3"
[ "$(cut -f 2 "$tmp/skips3" | tr '\n' ' ')" = "one two " ] \
  && recs "$r3" post-pr | grep -q "^stands-on${TAB}$r1:post-pr:"
verdict "a chained resume skips the same prefix, standing on the original records" "skips: $(cat "$tmp/skips3")"
git -C "$wt" commit -q --allow-empty -m "chore: move"
r4=$(sr new-run)
srun resume --run "$r4" --from "$r1:post-pr" >"$tmp/skips4"
[ ! -s "$tmp/skips4" ]
verdict "a head moved since the interruption skips nothing" "skips: $(cat "$tmp/skips4")"
for bad in "12:post-pr" "abcdef:post-pr" "$r1:pre-ready-flip" "$r1:nowhere" "$r1"; do
  srun resume --run "$r4" --from "$bad" >/dev/null 2>&1
  [ $? -eq 2 ] || fail "resume accepted --from '$bad'"
done
ok "a malformed run id or a point outside the in-run points is refused"
mkdir -p "$tmp/norec"
srun resume --run 999999 --from "x:post-pr" >/dev/null 2>"$tmp/e"
grep -q 'six-digit run id' "$tmp/e"
verdict "the --from grammar is checked before the run is read" "err: $(cat "$tmp/e")"

# --- a resume-skipped head move still triggers re-fire and reaches the next step -----------
fresh
catalog "$GATE" "pushfix|kind: command|target: $bin/edit.sh|args: src push" \
  "show|kind: command|target: $bin/show.sh"
config 'steps_pre_pr: [gate]' 'steps_post_pr: [pushfix, show]'
r1=$(sr new-run)
point_run "$r1" pre-pr
point_done "$r1" pre-pr
srun resolve --run "$r1" post-pr --unattended >/dev/null 2>&1
srun command --run "$r1" --point post-pr --step pushfix >/dev/null 2>&1
r2=$(sr new-run)
srun resume --run "$r2" --from "$r1:post-pr" >"$tmp/skips"
srun resolve --run "$r2" post-pr --unattended >/dev/null 2>&1
srun command --run "$r2" --point post-pr --step show >/dev/null 2>&1
srun refire --run "$r2" >"$tmp/plan"
grep -q "^refire${TAB}gate${TAB}pre-pr${TAB}" "$tmp/plan" \
  && grep -qx "PLANWRIGHT_STEP_NEW_HEAD=$(head_of)" "$tmp/show.show.env"
verdict "a resume-skipped move triggers the re-fire and reaches the next step" \
  "plan: $(cat "$tmp/plan"); env: $(cat "$tmp/show.show.env")"

# --- a run held in its re-fire pass resumes inside it, from the chain's first lists -------
fresh
catalog "$GATE" "gate2|kind: command|target: $bin/check.sh|paths: src docs|refire: post-pr" \
  "pushfix|kind: command|target: $bin/edit.sh|args: src push"
config 'steps_pre_pr: [gate, gate2]' 'steps_post_pr: [pushfix]'
r1=$(sr new-run)
point_run "$r1" pre-pr
point_done "$r1" pre-pr
point_run "$r1" post-pr
srun command --run "$r1" --point post-pr --step gate --refire-of pre-pr >/dev/null 2>&1
config 'steps_pre_pr: []' 'steps_post_pr: [pushfix]'
r2=$(sr new-run)
srun resume --run "$r2" --from "$r1:post-pr" >"$tmp/skips"
r3=$(sr new-run)
srun resume --run "$r3" --from "$r2:post-pr" >"$tmp/skips3"
srun refire --run "$r3" >"$tmp/plan"
[ "$(cut -f 2 "$tmp/skips3" | tr '\n' ' ')" = "pushfix gate " ] \
  && [ "$(cat "$tmp/plan")" = "refire${TAB}gate2${TAB}pre-pr${TAB}isolated" ]
verdict "a resumed re-fire pass skips what ran and plans the rest from the chain's first run" \
  "skips: $(cat "$tmp/skips3"); plan: $(cat "$tmp/plan")"

# --- a continue step attaches to the session behind a reused predecessor (REQ-D1.11) -------
fresh
catalog "sess|kind: command|target: $bin/check.sh|paths: src|hosting: in-session"
config 'steps_pre_pr: [sess]'
me=$(owner)
r1=$(sr new-run)
srun resolve --run "$r1" pre-pr --unattended >/dev/null 2>&1
srun begin --run "$r1" --point pre-pr --step sess --owner "$me" --session unit-sess-1 >"$tmp/begin"
grep -q "^run${TAB}PLANWRIGHT_STEP_SPEC='demo' .* '$bin/check.sh'$" "$tmp/begin"
verdict "begin prints the session line for an in-session step" "begin: $(cat "$tmp/begin")"
srun end --run "$r1" --point pre-pr --step sess --exit 0 >"$tmp/end"
grep -q "^passed${TAB}.*${TAB}in-session${TAB}unit-sess-1$" "$tmp/end"
verdict "end writes the session step's record" "end: $(cat "$tmp/end")"
r2=$(sr new-run)
srun resolve --run "$r2" pre-pr --unattended >/dev/null 2>&1
srun begin --run "$r2" --point pre-pr --step sess --owner "$me" --session unit-sess-2 >"$tmp/begin"
grep -q "^skipped${TAB}.*${TAB}in-session${TAB}unit-sess-1$" "$tmp/begin"
verdict "a reused predecessor names the hosting and session a continue step attaches to" \
  "begin: $(cat "$tmp/begin")"

# --- a pooled in-session step holds its slot for the session's process -------------------
fresh
catalog "sp1|kind: command|target: $bin/check.sh|pool: gate|hosting: in-session"
config 'steps_pre_pr: [sp1]'
me=$(owner)
r=$(sr new-run)
srun resolve --run "$r" pre-pr --unattended >/dev/null 2>&1
srun begin --run "$r" --point pre-pr --step sp1 --owner "$me" >"$tmp/begin"
held=$(sp report gate)
grep -q "PLANWRIGHT_STEP_POOL_HOLD='gate:$me'" "$tmp/begin" \
  && printf '%s\n' "$held" | grep -q "^holder${TAB}1${TAB}$me${TAB}sp1${TAB}"
verdict "begin takes the slot for the session's process and renders its hold mark" "held=$held"
srun end --run "$r" --point pre-pr --step sp1 --exit 0 >/dev/null
[ -z "$(sp report gate)" ] && recs "$r" pre-pr | grep -qx "pool${TAB}gate"
verdict "end releases the session's slot and records the pool" "still held"

# --- /execute-task wires the runner's calls ------------------------------------------------
skill=$(tr '\n' ' ' <"$repo_root/skills/execute-task/SKILL.md")
# shellcheck disable=SC2016 # literal backticks of the skill text
for call in 'step-run.sh resolve --run' 'step-run.sh resume' '`command`' 'begin --owner <session pid>' \
  'step-run.sh refire' 'full-suite-run.sh --run <id>' '--resume <run>:<point>'; do
  printf '%s' "$skill" | grep -Fq -- "$call" || fail "/execute-task does not name '$call'"
done
ok "/execute-task names the runner's resolve, resume, command, begin, refire, and full-suite calls"

if [ "$failures" -gt 0 ]; then
  printf '%s failure(s)\n' "$failures" >&2
  exit 1
fi
echo "all step-run resume tests passed"
