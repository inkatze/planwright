#!/bin/sh
# Tests for scripts/step-run.sh — /execute-task's command-step runner: pools,
# reuse, re-fire, and the head-move context (custom-steps Task 14;
# REQ-A1.6, REQ-D1.11, REQ-D1.12, REQ-I1.1, REQ-I1.2, REQ-I1.4, REQ-I1.8,
# REQ-I1.9, REQ-J1.1; D-22, D-27, D-28, D-29, D-30).
#
# Each scenario drives the runner's calls the way the skill sequences them,
# over fixture overlays in the adopter layer: a fixture worktree with a bare
# origin, a private pools root, and fixture command steps that log the
# context they saw.
#
# Runs standalone under /bin/sh (the bash 3.2 / dash floor):
#   ./tests/test-step-run.sh
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

# --- shipped defaults: nothing resolves, nothing re-fires --------------------------
fresh
rm -f "$adopter/planwright.yml" "$adopter/catalogs/steps.yaml"
r=$(sr new-run)
: >"$tmp/results"
unit "$r"
[ ! -s "$tmp/results" ] && [ ! -s "$tmp/plan" ] && [ ! -e "$tmp/pools" ]
verdict "with the shipped defaults no command step runs, no slot is taken, nothing re-fires" \
  "defaults: $(cat "$tmp/results" "$tmp/plan" 2>/dev/null)"

# --- pooled, path-declaring re-fire step and a pushing post-pr step (REQ-I1.1, REQ-I1.9) --
fresh
catalog "$GATE" "pushfix|kind: command|target: $bin/edit.sh|args: src push" \
  "show|kind: command|target: $bin/show.sh"
config 'steps_pre_pr: [gate]' 'steps_post_pr: [pushfix, show]'
r1=$(sr new-run)
: >"$tmp/results"
unit "$r1"
recs "$r1" pre-pr >"$tmp/l"
grep -qx "pool${TAB}gate" "$tmp/l" && grep -qx "outcome${TAB}passed" "$tmp/l" \
  && grep -q "^fingerprint${TAB}[0-9a-f]\{40\}" "$tmp/l"
verdict "the pooled pre-pr step records its pool and fingerprint and passes" "pre-pr: $(cat "$tmp/l")"
sed -n 1p "$tmp/check.log" | grep -q '^point=pre-pr hold=gate:[0-9][0-9]* '
verdict "the check ran under the hold mark naming its pool and owner" "log: $(cat "$tmp/check.log")"
[ ! -L "$tmp/pools/gate/slot-1" ]
verdict "the slot is released after the check ends" "slot-1 still held"
grep -q "^refire${TAB}gate${TAB}pre-pr${TAB}isolated$" "$tmp/plan"
verdict "a post-pr push under the declared path plans the re-fire" "plan: $(cat "$tmp/plan")"
recs "$r1" post-pr >"$tmp/l"
awk -F '\t' '$1 == "record" { r = $2 } $1 == "refire-of" && $2 == "pre-pr" { print r }' "$tmp/l" >"$tmp/refired"
[ -s "$tmp/refired" ] && grep -qx "end-head${TAB}$(head_of)" "$tmp/l"
verdict "the check re-fired on the final head, recorded under post-pr with refire-of pre-pr" \
  "post-pr: $(cat "$tmp/l")"
last_seq=0 done_seq=''
for f in "$wt/.claude/steps/$r1"/*; do
  case $f in
    *-step-post-pr.rec) last_seq=$((last_seq + 1)) ;;
    *-done-post-pr.rec) done_seq=$(basename "$f" | cut -c1-3) ;;
  esac
done
ref_seq=$(sed -n 's|.*/\([0-9]*\)-step-post-pr.rec$|\1|p' "$tmp/refired")
[ "$((1$ref_seq))" -lt "$((1$done_seq))" ] && [ "$last_seq" -eq 3 ]
verdict "the re-fire record lands before the post-pr completion record" "seqs: $ref_seq $done_seq"
line=$(sed -n 2p "$tmp/check.log")
printf '%s\n' "$line" | grep -q "^point=post-pr hold=gate:[0-9]* prev=$wt/.claude/steps/$r1/[0-9]*-step-post-pr.rec ph=[0-9a-f]\{40\} nh=$(head_of) "
verdict "the re-fired check reads point post-pr, the last post-pr record, and the post-pr move" "log: $line"
grep -q "^PLANWRIGHT_STEP_NEW_HEAD=$(head_of)$" "$tmp/show.show.env" \
  && grep -q '^PLANWRIGHT_STEP_PREV_HEAD=[0-9a-f]\{40\}$' "$tmp/show.show.env" \
  && grep -qx 'PLANWRIGHT_STEP_PR_NUMBER=7' "$tmp/show.show.env" \
  && [ "$(grep -c '^PLANWRIGHT_STEP_' "$tmp/show.show.env")" -eq 12 ] \
  && grep -qx 'host=kept' "$tmp/show.show.env"
verdict "the step after a push sees exactly the twelve fields, the push's move among them, the host env intact" \
  "env: $(cat "$tmp/show.show.env")"

# --- a second run with no change reuses the passing record (REQ-I1.8) -------------------
r2=$(sr new-run)
point_run "$r2" pre-pr
recs "$r2" pre-pr >"$tmp/l"
grep -qx "skip-code${TAB}reuse" "$tmp/l" && grep -q "^stands-on${TAB}$r1:post-pr:" "$tmp/l" \
  && [ "$(wc -l <"$tmp/check.log" | tr -d ' ')" -eq 2 ]
verdict "a second run reuses the passing record, naming the first run's re-fire" "r2: $(cat "$tmp/l")"
point_done "$r2" pre-pr
srun refire --run "$r2" >"$tmp/plan"
[ ! -s "$tmp/plan" ]
verdict "with no post-pr head move nothing re-fires" "plan: $(cat "$tmp/plan")"

# --- a push touching no declared path re-fires as a reuse skip ----------------------------
fresh
catalog "$GATE" "pushdoc|kind: command|target: $bin/edit.sh|args: docs push"
config 'steps_pre_pr: [gate]' 'steps_post_pr: [pushdoc]'
r=$(sr new-run)
: >"$tmp/results"
unit "$r"
recs "$r" post-pr >"$tmp/l"
grep -qx "refire-of${TAB}pre-pr" "$tmp/l" && grep -qx "skip-code${TAB}reuse" "$tmp/l" \
  && [ "$(wc -l <"$tmp/check.log" | tr -d ' ')" -eq 1 ]
verdict "a push touching no declared path re-fires as a reuse skip" "post-pr: $(cat "$tmp/l")"

# --- a failing re-fire fails, so the runner parks with the PR a draft ---------------------
fresh
catalog "$GATE" "pushfix|kind: command|target: $bin/edit.sh|args: src push"
config 'steps_pre_pr: [gate]' 'steps_post_pr: [pushfix]'
r=$(sr new-run)
point_run "$r" pre-pr
point_done "$r" pre-pr
point_run "$r" post-pr
touch "$tmp/fail"
srun refire --run "$r" >"$tmp/plan"
srun command --run "$r" --point post-pr --step gate --refire-of pre-pr >"$tmp/out" 2>/dev/null
rc=$?
[ "$rc" -eq 1 ] && grep -q "^failed${TAB}" "$tmp/out" && grep -q 'step-run: exited 3' \
  "$(cut -f 2 "$tmp/out")"
verdict "a failing re-fire records failed and exits 1" "rc=$rc out=$(cat "$tmp/out")"

# --- one id at pre-ci and pre-pr re-fires once, from pre-ci; a missing one never ---------
fresh
catalog "$GATE" "ghost|kind: command|target: $tmp/absent.sh|paths: src|refire: post-pr" \
  "pushfix|kind: command|target: $bin/edit.sh|args: src push"
config 'steps_pre_ci: [gate, ghost]' 'steps_pre_pr: [gate]' 'steps_post_pr: [pushfix]'
r=$(sr new-run)
point_run "$r" pre-ci
point_done "$r" pre-ci
point_run "$r" pre-pr
point_done "$r" pre-pr
point_run "$r" post-pr
srun refire --run "$r" >"$tmp/plan"
[ "$(wc -l <"$tmp/plan" | tr -d ' ')" -eq 1 ] && grep -q "^refire${TAB}gate${TAB}pre-ci${TAB}" "$tmp/plan"
verdict "an id at both lists re-fires once from pre-ci; a missing-skipped one is not planned" \
  "plan: $(cat "$tmp/plan")"
grep -q "^skip${TAB}ghost${TAB}pre-ci" "$wt/.claude/steps/$r/runner-rows-pre-ci"
verdict "the unplanned step is the one the matrix skipped as missing" "rows: $(cat "$wt/.claude/steps/$r/runner-rows-pre-ci")"

# --- a step missing at its first declaring list is not re-fired from a later one -----------
fresh
catalog "$GATE" "pushfix|kind: command|target: $bin/edit.sh|args: src push"
config 'steps_pre_ci: [gate]' 'steps_pre_pr: [gate]' 'steps_post_pr: [pushfix]'
r=$(sr new-run)
mv "$bin/check.sh" "$bin/check.sh.away"
point_run "$r" pre-ci
mv "$bin/check.sh.away" "$bin/check.sh"
point_done "$r" pre-ci
point_run "$r" pre-pr
point_done "$r" pre-pr
point_run "$r" post-pr
srun refire --run "$r" >"$tmp/plan"
[ ! -s "$tmp/plan" ]
verdict "a step skipped missing at its first declaring list is not re-fired" "plan: $(cat "$tmp/plan")"

# --- the second re-fire reads the pass's previous record (REQ-I1.9) -------------------------
fresh
catalog "$GATE" "gate2|kind: command|target: $bin/check.sh|paths: src docs|refire: post-pr" \
  "pushfix|kind: command|target: $bin/edit.sh|args: src push"
config 'steps_pre_pr: [gate, gate2]' 'steps_post_pr: [pushfix]'
r=$(sr new-run)
: >"$tmp/results"
unit "$r"
first_refire=$(sed -n 4p "$tmp/results" | cut -f 2)
sed -n 4p "$tmp/check.log" | grep -q "^point=post-pr hold= prev=$first_refire "
verdict "the second re-fire's previous record is the first re-fire's" \
  "first=$first_refire log: $(sed -n 4p "$tmp/check.log")"

# --- an expired pool wait fails naming the holder (REQ-I1.4) ------------------------------
fresh
catalog "$GATE"
config 'steps_pre_pr: [gate]' 'step_pool_wait: 1s'
h=$(owner)
sp take gate "$h" --step other --worktree "$tmp/elsewhere" >/dev/null
r=$(sr new-run)
srun resolve --run "$r" pre-pr --unattended >/dev/null 2>&1
srun command --run "$r" --point pre-pr --step gate >"$tmp/out" 2>/dev/null
rc=$?
recs "$r" pre-pr >"$tmp/l"
[ "$rc" -eq 1 ] && grep -qx "outcome${TAB}failed" "$tmp/l" && grep -q "^holder${TAB}pid $h (step other" "$tmp/l" \
  && grep -q "^wait${TAB}[0-9]" "$tmp/l" && [ ! -e "$tmp/check.log" ]
verdict "an expired wait records failed, the holder, and its wait seconds, running nothing" "$(cat "$tmp/l")"

# --- a wait longer than a shell-call cap still admits the step ----------------------------
config 'steps_pre_pr: [gate]' 'step_pool_wait: 60s'
r=$(sr new-run)
srun resolve --run "$r" pre-pr --unattended >/dev/null 2>&1
srun command --run "$r" --point pre-pr --step gate >"$tmp/out" 2>"$tmp/wait.err" &
bg=$!
# Bounded one-second polls: until the step is waiting, then three more while
# the holder keeps the slot.
i=0
while ! grep -q 'is full' "$tmp/wait.err" 2>/dev/null && [ "$i" -lt 60 ]; do
  sleep 1
  i=$((i + 1))
done
sleep 3
sp release gate "$h" >/dev/null
wait "$bg"
rc=$?
recs "$r" pre-pr >"$tmp/l"
w=$(sed -n "s/^wait${TAB}//p" "$tmp/l")
[ "$rc" -eq 0 ] && grep -qx "outcome${TAB}passed" "$tmp/l" && [ "${w:-0}" -ge 2 ]
verdict "a backgrounded step outlasting several bounded polls is admitted, its whole wait recorded" "rc=$rc wait=$w"

# --- a nested take of the same pool under the hold mark does not wait (REQ-I1.2) ---------
fresh
catalog "$GATE"
config 'steps_pre_pr: [gate]' 'step_pool_wait: 5s'
touch "$tmp/nest"
r=$(sr new-run)
srun resolve --run "$r" pre-pr --unattended >/dev/null 2>&1
srun command --run "$r" --point pre-pr --step gate >"$tmp/out" 2>/dev/null
rc=$?
[ "$rc" -eq 0 ] && grep -q "^nested${TAB}" "$tmp/nest.out" && grep -q "^passed${TAB}" "$tmp/out"
verdict "a check taking its own pool again runs nested and passes" "rc=$rc nest=$(cat "$tmp/nest.out")"

# --- two units sharing a pool never overlap -------------------------------------------------
fresh
wt_a=$wt
catalog "gate|kind: command|target: $bin/check.sh|pool: gate"
config 'steps_pre_pr: [gate]'
printf '2\n' >"$tmp/slow"
fresh
wt_b=$wt
printf '2\n' >"$tmp/slow"
for w in "$wt_a" "$wt_b"; do
  wt=$w
  r=$(sr new-run)
  srun resolve --run "$r" pre-pr --unattended >/dev/null 2>&1
done
(wt=$wt_a && srun command --run 000001 --point pre-pr --step gate >/dev/null 2>&1) &
pa=$!
(wt=$wt_b && srun command --run 000001 --point pre-pr --step gate >/dev/null 2>&1) &
pb=$!
wait "$pa"
wait "$pb"
awk '{ for (i = 1; i <= NF; i++) { split($i, kv, "="); v[kv[1]] = kv[2] } print v["start"], v["end"] }' \
  "$tmp/check.log" | sort -n >"$tmp/iv"
s2=$(sed -n 2p "$tmp/iv" | cut -d' ' -f1)
e1=$(sed -n 1p "$tmp/iv" | cut -d' ' -f2)
[ "$(wc -l <"$tmp/iv" | tr -d ' ')" -eq 2 ] && [ "$s2" -ge "$e1" ]
verdict "two units' pooled steps on a one-slot pool run disjoint" "intervals: $(cat "$tmp/iv")"
rm -f "$tmp/slow"

# --- a post-pr commit without a push moves the head for the next step (REQ-D1.12) ---------
fresh
catalog "commit|kind: command|target: $bin/edit.sh|args: docs" "show|kind: command|target: $bin/show.sh"
config 'steps_post_pr: [commit, show]'
r=$(sr new-run)
point_run "$r" post-pr
recs "$r" post-pr >"$tmp/l"
h0=$(awk -F '\t' '$1 == "head" { print $2; exit }' "$tmp/l")
h1=$(awk -F '\t' '$1 == "end-head" { print $2; exit }' "$tmp/l")
[ "$h0" != "$h1" ] && grep -qx "PLANWRIGHT_STEP_PREV_HEAD=$h0" "$tmp/show.show.env" \
  && grep -qx "PLANWRIGHT_STEP_NEW_HEAD=$h1" "$tmp/show.show.env"
verdict "a commit without a push moves the record's end head and reaches the next step" \
  "heads $h0 $h1; env: $(cat "$tmp/show.show.env")"
fresh
catalog "show|kind: command|target: $bin/show.sh"
config 'steps_pre_ci: [show]'
r=$(sr new-run)
PR='' point_run "$r" pre-ci
grep -qx 'PLANWRIGHT_STEP_PR_NUMBER=' "$tmp/show.show.env" && grep -qx 'PLANWRIGHT_STEP_PREV_HEAD=' "$tmp/show.show.env" && grep -qx 'PLANWRIGHT_STEP_NEW_HEAD=' "$tmp/show.show.env" \
  && grep -qx 'PLANWRIGHT_STEP_PREV_RECORD=' "$tmp/show.show.env"
verdict "a first run before any PR sees an empty PR number, and with no earlier move empty head fields" \
  "env: $(cat "$tmp/show.show.env")"

if [ "$failures" -gt 0 ]; then
  printf '%s failure(s)\n' "$failures" >&2
  exit 1
fi
echo "all step-run tests passed"
