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
verdict $? "with the shipped defaults no command step runs, no slot is taken, nothing re-fires" \
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
verdict $? "the pooled pre-pr step records its pool and fingerprint and passes" "pre-pr: $(cat "$tmp/l")"
sed -n 1p "$tmp/check.log" | grep -q '^point=pre-pr hold=gate:[0-9][0-9]* '
verdict $? "the check ran under the hold mark naming its pool and owner" "log: $(cat "$tmp/check.log")"
[ ! -L "$tmp/pools/gate/slot-1" ]
verdict $? "the slot is released after the check ends" "slot-1 still held"
grep -q "^refire${TAB}gate${TAB}pre-pr${TAB}isolated$" "$tmp/plan"
verdict $? "a post-pr push under the declared path plans the re-fire" "plan: $(cat "$tmp/plan")"
recs "$r1" post-pr >"$tmp/l"
awk -F '\t' '$1 == "record" { r = $2 } $1 == "refire-of" && $2 == "pre-pr" { print r }' "$tmp/l" >"$tmp/refired"
[ -s "$tmp/refired" ] && grep -qx "end-head${TAB}$(head_of)" "$tmp/l"
verdict $? "the check re-fired on the final head, recorded under post-pr with refire-of pre-pr" \
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
verdict $? "the re-fire record lands before the post-pr completion record" "seqs: $ref_seq $done_seq"
line=$(sed -n 2p "$tmp/check.log")
printf '%s\n' "$line" | grep -q "^point=post-pr hold=gate:[0-9]* prev=$wt/.claude/steps/$r1/[0-9]*-step-post-pr.rec ph=[0-9a-f]\{40\} nh=$(head_of) "
verdict $? "the re-fired check reads point post-pr, the last post-pr record, and the post-pr move" "log: $line"
grep -q "^PLANWRIGHT_STEP_NEW_HEAD=$(head_of)$" "$tmp/show.show.env" \
  && grep -q '^PLANWRIGHT_STEP_PREV_HEAD=[0-9a-f]\{40\}$' "$tmp/show.show.env" \
  && grep -qx 'PLANWRIGHT_STEP_PR_NUMBER=7' "$tmp/show.show.env" \
  && [ "$(grep -c '^PLANWRIGHT_STEP_' "$tmp/show.show.env")" -eq 12 ] \
  && grep -qx 'host=kept' "$tmp/show.show.env"
verdict $? "the step after a push sees exactly the twelve fields, the push's move among them, the host env intact" \
  "env: $(cat "$tmp/show.show.env")"

# --- a second run with no change reuses the passing record (REQ-I1.8) -------------------
r2=$(sr new-run)
point_run "$r2" pre-pr
recs "$r2" pre-pr >"$tmp/l"
grep -qx "skip-code${TAB}reuse" "$tmp/l" && grep -q "^stands-on${TAB}$r1:post-pr:" "$tmp/l" \
  && [ "$(wc -l <"$tmp/check.log" | tr -d ' ')" -eq 2 ]
verdict $? "a second run reuses the passing record, naming the first run's re-fire" "r2: $(cat "$tmp/l")"
point_done "$r2" pre-pr
srun refire --run "$r2" >"$tmp/plan"
[ ! -s "$tmp/plan" ]
verdict $? "with no post-pr head move nothing re-fires" "plan: $(cat "$tmp/plan")"

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
verdict $? "a push touching no declared path re-fires as a reuse skip" "post-pr: $(cat "$tmp/l")"

# --- a failing re-fire records failed and exits 1 (the skill then parks) ----------------
fresh
catalog "$GATE" "pushfix|kind: command|target: $bin/edit.sh|args: src push"
config 'steps_pre_pr: [gate]' 'steps_post_pr: [pushfix]'
r=$(sr new-run)
point_run "$r" pre-pr
point_done "$r" pre-pr
point_run "$r" post-pr
touch "$tmp/fail"
srun command --run "$r" --point post-pr --step gate --refire-of pre-pr >"$tmp/out" 2>/dev/null
rc=$?
[ "$rc" -eq 1 ] && grep -q "^failed${TAB}" "$tmp/out" && grep -q 'step-run: exited 3' \
  "$(cut -f 2 "$tmp/out")"
verdict $? "a failing re-fire records failed and exits 1" "rc=$rc out=$(cat "$tmp/out")"

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
verdict $? "an id at both lists re-fires once from pre-ci; a missing-skipped one is not planned" \
  "plan: $(cat "$tmp/plan")"
grep -q "^skip${TAB}ghost${TAB}pre-ci" "$wt/.claude/steps/$r/runner-rows-pre-ci"
verdict $? "the unplanned step is the one the matrix skipped as missing" "rows: $(cat "$wt/.claude/steps/$r/runner-rows-pre-ci")"

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
verdict $? "a step skipped missing at its first declaring list is not re-fired" "plan: $(cat "$tmp/plan")"

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
verdict $? "the second re-fire's previous record is the first re-fire's" \
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
verdict $? "an expired wait records failed, the holder, and its wait seconds, running nothing" "$(cat "$tmp/l")"
sp release gate "$h" >/dev/null

# --- a wait longer than a shell-call cap still admits the step ----------------------------
config 'steps_pre_pr: [gate]' 'step_pool_wait: 60s'
h=$(owner)
sp take gate "$h" --step other --worktree "$tmp/elsewhere" >/dev/null
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
verdict $? "a backgrounded step outlasting several bounded polls is admitted, its whole wait recorded" "rc=$rc wait=$w"

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
verdict $? "a check taking its own pool again runs nested and passes" "rc=$rc nest=$(cat "$tmp/nest.out")"

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
verdict $? "two units' pooled steps on a one-slot pool run disjoint" "intervals: $(cat "$tmp/iv")"
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
verdict $? "a commit without a push moves the record's end head and reaches the next step" \
  "heads $h0 $h1; env: $(cat "$tmp/show.show.env")"
fresh
catalog "show|kind: command|target: $bin/show.sh"
config 'steps_pre_ci: [show]'
r=$(sr new-run)
PR='' point_run "$r" pre-ci
grep -qx 'PLANWRIGHT_STEP_PR_NUMBER=' "$tmp/show.show.env" && grep -qx 'PLANWRIGHT_STEP_PREV_HEAD=' "$tmp/show.show.env" && grep -qx 'PLANWRIGHT_STEP_NEW_HEAD=' "$tmp/show.show.env" \
  && grep -qx 'PLANWRIGHT_STEP_PREV_RECORD=' "$tmp/show.show.env"
verdict $? "a first run before any PR sees an empty PR number, and with no earlier move empty head fields" \
  "env: $(cat "$tmp/show.show.env")"

# --- a launched worker names no step context: the session record supplies it ---------------
fresh
catalog "show|kind: command|target: $bin/show.sh"
config 'steps_pre_pr: [show]'
wtp=$(cd -P "$tmp/wt$n" && pwd -P)
printf 'policy=\nunit_branch=planwright/flight/demo-0123abcd\nworktree_root=%s\npr_base=origin/main\n' "$wtp" >"$tmp/launch.record"
noctx() {
  _rec=$1
  shift
  env_run env -u PLANWRIGHT_STEP_SPEC -u PLANWRIGHT_STEP_TASK_IDS -u PLANWRIGHT_STEP_UNIT_KIND \
    -u PLANWRIGHT_STEP_BRANCH -u PLANWRIGHT_STEP_BASE_BRANCH -u PLANWRIGHT_STEP_WORKTREE \
    -u PLANWRIGHT_STEP_PR_NUMBER "PLANWRIGHT_WORKER_SESSION_RECORD=$_rec" "$RUN" --worktree "$tmp/wt$n" "$@"
}
r=$(sr new-run)
noctx "$tmp/launch.record" resolve --run "$r" pre-pr --unattended >/dev/null 2>"$tmp/err"
noctx "$tmp/launch.record" command --run "$r" --point pre-pr --step show >/dev/null 2>>"$tmp/err"
grep -qx 'PLANWRIGHT_STEP_UNIT_KIND=flight' "$tmp/show.show.env" \
  && grep -qx 'PLANWRIGHT_STEP_BRANCH=planwright/flight/demo-0123abcd' "$tmp/show.show.env" \
  && grep -qx 'PLANWRIGHT_STEP_BASE_BRANCH=main' "$tmp/show.show.env" \
  && grep -qx "PLANWRIGHT_STEP_WORKTREE=$wtp" "$tmp/show.show.env" \
  && grep -qx 'PLANWRIGHT_STEP_SPEC=' "$tmp/show.show.env"
verdict $? "a flight worker's step sees its kind, branch, base and worktree from the launch record" \
  "env: $(cat "$tmp/show.show.env" 2>&1) err: $(cat "$tmp/err")"
rm -f "$tmp/show.show.env"
printf 'policy=\nunit_branch=planwright/flight/demo-0123abcd\nworktree_root=%s/elsewhere\npr_base=origin/main\n' "$wtp" >"$tmp/other.record"
r=$(sr new-run)
noctx "$tmp/other.record" resolve --run "$r" pre-pr --unattended >/dev/null 2>"$tmp/err"
noctx "$tmp/other.record" command --run "$r" --point pre-pr --step show >/dev/null 2>>"$tmp/err"
grep -qx 'PLANWRIGHT_STEP_UNIT_KIND=' "$tmp/show.show.env" && grep -qx 'PLANWRIGHT_STEP_BRANCH=' "$tmp/show.show.env"
verdict $? "a record naming another worktree supplies nothing" "env: $(cat "$tmp/show.show.env" 2>&1)"
rm -f "$tmp/show.show.env"
r=$(sr new-run)
env_run env "PLANWRIGHT_WORKER_SESSION_RECORD=$tmp/launch.record" "$RUN" --worktree "$tmp/wt$n" resolve --run "$r" pre-pr --unattended >/dev/null 2>"$tmp/err"
env_run env "PLANWRIGHT_WORKER_SESSION_RECORD=$tmp/launch.record" "$RUN" --worktree "$tmp/wt$n" command --run "$r" --point pre-pr --step show >/dev/null 2>>"$tmp/err"
grep -qx 'PLANWRIGHT_STEP_UNIT_KIND=task' "$tmp/show.show.env" && grep -qx 'PLANWRIGHT_STEP_BRANCH=planwright/demo/task-1' "$tmp/show.show.env"
verdict $? "a context the caller exports is never replaced by the record's" "env: $(cat "$tmp/show.show.env" 2>&1)"

# --- a location in a git checkout runs only as that checkout's trusted commit holds it ---
# The declaration names a file, not its content, and a worker can Write any
# file in its worktree, so a location the checkout's trusted commit does not
# hold is refused.
fresh
# The worktree by its own name: `wt` is also assigned inside a subshell further
# up, which shellcheck reads as a change that may be lost.
lw=$tmp/wt$n
mkdir -p "$lw/tools" "$tmp/elsewhere" "$tmp/other/tools"
printf '#!/bin/sh\nprintf ran >>"%s/ran"\n' "$tmp" >"$lw/tools/mark.sh"
chmod +x "$lw/tools/mark.sh"
# A committed symbolic link, so only the link itself is the reason to refuse.
ln -s mark.sh "$lw/tools/lnk.sh"
git -C "$lw" add tools && git -C "$lw" commit -q -m "chore: a step"
cp "$lw/tools/mark.sh" "$tmp/elsewhere/mark.sh"
ln -s "$tmp/elsewhere" "$lw/linked"
# Another checkout, as the primary a worktree sits under is.
cp "$lw/tools/mark.sh" "$tmp/other/tools/mark.sh"
cp "$lw/tools/mark.sh" "$tmp/other/tools/kept.sh"
git init -q "$tmp/other"
git -C "$tmp/other" add tools
git -C "$tmp/other" -c user.name=Fixture -c user.email=fixture@example.invalid -c commit.gpgsign=false \
  -c core.hooksPath=/dev/null commit -q -m "chore: tools"
cp "$lw/tools/mark.sh" "$tmp/other/.git/inside.sh"
loc_out() { printf 'out: %s' "$(cat "$tmp/loc.out" "$tmp/loc.err")"; }
loc_run() {
  rm -f "$tmp/ran"
  catalog "loc|kind: command|target: $1"
  config 'steps_pre_ci: [loc]'
  _lr=$(sr new-run)
  srun_loc resolve --run "$_lr" pre-ci --unattended >/dev/null 2>"$tmp/err"
  srun_loc command --run "$_lr" --point pre-ci --step loc >"$tmp/loc.out" 2>"$tmp/loc.err"
}
# srun_loc: srun, under the worker session record LOC_REC names when it is set.
LOC_REC=''
srun_loc() {
  if [ -n "$LOC_REC" ]; then
    env_run env "PLANWRIGHT_WORKER_SESSION_RECORD=$LOC_REC" "$RUN" --worktree "$lw" "$@"
  else
    srun "$@"
  fi
}
loc_ran() { loc_run "$1" && [ -s "$tmp/ran" ] && grep -q '^passed' "$tmp/loc.out"; }
# loc_refused <location> [<phrase>]: the step fails without running, and its
# refusal reads <phrase>: by default the one that names an edit as the remedy;
# NO_TRUST for the one given where no commit is trusted at all.
EDIT='not as its trusted commit holds it'
NO_TRUST='trusts no commit of'
loc_refused() {
  ! loc_run "$1" && [ ! -e "$tmp/ran" ] && grep -q '^failed' "$tmp/loc.out" \
    && grep -q "${2:-$EDIT}" "$tmp/loc.err"
}
loc_ran "$lw/tools/mark.sh"
verdict $? "a committed, unmodified location runs" "$(loc_out)"
loc_ran tools/mark.sh
verdict $? "a committed location named relative to the worktree runs" "$(loc_out)"
cp "$lw/tools/mark.sh" "$tmp/mark.orig"
printf 'printf pwned >>"%s/ran"\n' "$tmp" >>"$lw/tools/mark.sh"
loc_refused "$lw/tools/mark.sh"
verdict $? "a location edited since HEAD is refused before it runs" "$(loc_out)"
git -C "$lw" add tools/mark.sh
loc_refused "$lw/tools/mark.sh"
verdict $? "a location staged but not committed is refused" "$(loc_out)"
git -C "$lw" reset -q -- tools/mark.sh
cp "$tmp/mark.orig" "$lw/tools/mark.sh"
cp "$tmp/mark.orig" "$lw/tools/new.sh"
chmod +x "$lw/tools/new.sh"
loc_refused "$lw/tools/new.sh"
verdict $? "a location HEAD does not hold is refused" "$(loc_out)"
loc_refused "$lw/linked/mark.sh"
verdict $? "a location spelled inside the worktree through a folder linked out of it is refused" "$(loc_out)"
loc_refused "$lw/tools/lnk.sh"
verdict $? "a location that is itself a symbolic link is refused" "$(loc_out)"
loc_ran "$tmp/elsewhere/mark.sh"
verdict $? "a location in no checkout keeps the declaration's trust" "$(loc_out)"
loc_ran "$tmp/other/tools/kept.sh"
verdict $? "a location another checkout commits unchanged runs" "$(loc_out)"
printf 'printf pwned >>"%s/ran"\n' "$tmp" >>"$tmp/other/tools/mark.sh"
loc_refused "$tmp/other/tools/mark.sh"
verdict $? "a location another checkout holds, edited since its HEAD, is refused" "$(loc_out)"
loc_refused "$tmp/other/.git/inside.sh"
verdict $? "a location inside a checkout's git folder is refused" "$(loc_out)"
catalog "loc|kind: command|target: $lw/tools/new.sh|hosting: in-session"
config 'steps_pre_ci: [loc]'
r=$(sr new-run)
rm -f "$tmp/ran"
srun resolve --run "$r" pre-ci --unattended >/dev/null 2>"$tmp/err"
! srun begin --run "$r" --point pre-ci --step loc --owner "$(owner)" >"$tmp/loc.out" 2>"$tmp/loc.err" \
  && grep -q '^failed' "$tmp/loc.out" && ! grep -q '^run' "$tmp/loc.out" \
  && grep -q 'not as its trusted commit holds it' "$tmp/loc.err"
verdict $? "a session-hosted step's begin refuses the location too, printing no line to run" "$(loc_out)"
catalog "loc|kind: command|target: $lw/tools/mark.sh|hosting: in-session"
r=$(sr new-run)
srun resolve --run "$r" pre-ci --unattended >/dev/null 2>"$tmp/err"
srun begin --run "$r" --point pre-ci --step loc --owner "$(owner)" >"$tmp/loc.out" 2>"$tmp/loc.err" \
  && grep -q "^run.*$lw/tools/mark.sh" "$tmp/loc.out"
verdict $? "a session-hosted step's begin prints the line of a committed location" "$(loc_out)"
loc_ran "$lw/tools/mark.sh"
verdict $? "the location put back byte for byte runs again" "$(loc_out)"

# --- under a worker session record, the worktree is held to its base ---------
# The worker can commit on its own branch, so in the worktree the record names
# a location runs only as the merge base with the record's pr_base holds it.
lwp=$(cd -P "$lw" && pwd -P)
git -C "$lw" update-ref refs/remotes/origin/main HEAD~1
printf 'worktree_root=%s\npr_base=origin/main\n' "$lwp" >"$tmp/loc.record"
LOC_REC=$tmp/loc.record
loc_refused "$lw/tools/mark.sh"
verdict $? "under a record, a location the worker committed but the base lacks is refused" "$(loc_out)"
git -C "$lw" update-ref refs/remotes/origin/main HEAD
loc_ran "$lw/tools/mark.sh"
verdict $? "under a record, a location the base holds runs" "$(loc_out)"
loc_ran "$tmp/other/tools/kept.sh"
verdict $? "under a record, another checkout is still held to its HEAD" "$(loc_out)"
git -C "$lw" branch -q -d -r origin/main
git -C "$lw" branch refs/remotes/origin/main HEAD
loc_refused "$lw/tools/mark.sh" "$NO_TRUST"
verdict $? "under a record, a local branch standing in for the deleted base ref is refused" "$(loc_out)"
git -C "$lw" branch -q -D refs/remotes/origin/main
git -C "$lw" update-ref refs/remotes/origin/main HEAD
printf 'worktree_root=%s\n' "$lwp" >"$tmp/loc.record"
loc_refused "$lw/tools/mark.sh" "$NO_TRUST"
verdict $? "under a record with no pr_base, a location is refused" "$(loc_out)"
printf 'worktree_root=%s\nworktree_root=%s\npr_base=origin/main\n' "$lwp" "$lwp" >"$tmp/loc.record"
loc_refused "$lw/tools/mark.sh" "$NO_TRUST"
verdict $? "under a record repeating worktree_root, a location is refused" "$(loc_out)"
# An unusable record trusts nothing anywhere: the worker may still commit, and
# the runner cannot tell where.
loc_refused "$tmp/other/tools/kept.sh" "$NO_TRUST"
verdict $? "under a record repeating worktree_root, another checkout is refused too" "$(loc_out)"
for spec in "$lwp/|trailing slash" "$tmp/gone|a missing directory" "$tmp/elsewhere|a directory that is no checkout"; do
  printf 'worktree_root=%s\npr_base=origin/main\n' "${spec%%|*}" >"$tmp/loc.record"
  loc_refused "$lw/tools/mark.sh" "$NO_TRUST"
  verdict $? "under a record whose worktree_root is not a canonical checkout (${spec#*|}), a location is refused" "$(loc_out)"
done
printf 'worktree_root=%s\npr_base=origin/main\npr_base=origin/main\n' "$lwp" >"$tmp/loc.record"
loc_refused "$lw/tools/mark.sh" "$NO_TRUST"
verdict $? "under a record repeating pr_base, a location is refused" "$(loc_out)"
git -C "$lw" update-ref refs/remotes/o+x/main HEAD
printf 'worktree_root=%s\npr_base=o+x/main\n' "$lwp" >"$tmp/loc.record"
loc_refused "$lw/tools/mark.sh" "$NO_TRUST"
verdict $? "under a record whose pr_base names a remote outside its grammar, a location is refused" "$(loc_out)"
git -C "$lw" update-ref -d refs/remotes/o+x/main
{
  printf 'worktree_root=%s\npr_base=origin/main\n' "$lwp"
  awk 'BEGIN { for (i = 0; i < 100; i++) printf "pad=%050d\n", i }'
} >"$tmp/loc.record"
loc_refused "$lw/tools/mark.sh" "$NO_TRUST"
verdict $? "under a record past the size bound, a location is refused" "$(loc_out)"
printf 'worktree_root=%s\npr_base=origin/main\n' "$lwp" >"$lw/inside.record"
LOC_REC=$lw/inside.record
loc_refused "$lw/tools/mark.sh" "$NO_TRUST"
verdict $? "under a record stored inside the worktree it names, a location is refused" "$(loc_out)"
rm -f "$lw/inside.record"
mkdir -p "$tmp/scr"
printf 'worktree_root=%s\npr_base=origin/main\nscratch_root=%s\n' "$lwp" "$tmp/scr" >"$tmp/scr/in.record"
LOC_REC=$tmp/scr/in.record
loc_refused "$lw/tools/mark.sh" "$NO_TRUST"
verdict $? "under a record stored inside the scratch root it names, a location is refused" "$(loc_out)"
LOC_REC=$tmp/missing.record
loc_refused "$lw/tools/mark.sh" "$NO_TRUST"
verdict $? "under a record path that does not exist, a location is refused" "$(loc_out)"
# A relative record path would resolve from the worktree the runner enters.
printf 'worktree_root=%s\npr_base=origin/main\n' "$lwp" >"$tmp/loc.record"
LOC_REC=../loc.record
loc_refused "$lw/tools/mark.sh" "$NO_TRUST"
verdict $? "under a relative record path, a location is refused" "$(loc_out)"
ln -sf "$tmp/loc.record" "$tmp/link.record"
LOC_REC=$tmp/link.record
loc_refused "$lw/tools/mark.sh" "$NO_TRUST"
verdict $? "under a record that is a symbolic link, a location is refused" "$(loc_out)"
LOC_REC=$tmp/loc.record
git -C "$lw" symbolic-ref refs/remotes/origin/main "refs/heads/$(git -C "$lw" symbolic-ref --short HEAD)"
loc_refused "$lw/tools/mark.sh" "$NO_TRUST"
verdict $? "under a record, the base's name as a symbolic ref is refused" "$(loc_out)"
git -C "$lw" symbolic-ref --delete refs/remotes/origin/main
git -C "$lw" update-ref refs/remotes/origin/main HEAD
# A repository nested in the recorded worktree, whatever refs it carries.
mkdir -p "$lw/sub/n/tools"
cp "$tmp/mark.orig" "$lw/sub/n/tools/n.sh"
chmod +x "$lw/sub/n/tools/n.sh"
git init -q "$lw/sub/n"
git -C "$lw/sub/n" add tools
git -C "$lw/sub/n" -c user.name=Fixture -c user.email=fixture@example.invalid -c commit.gpgsign=false \
  -c core.hooksPath=/dev/null commit -q -m "chore: nested"
git -C "$lw/sub/n" update-ref refs/remotes/origin/main HEAD
loc_refused "$lw/sub/n/tools/n.sh" "$NO_TRUST"
verdict $? "under a record, a repository nested in its worktree is refused" "$(loc_out)"
ln -s "$lw/sub/n/tools" "$tmp/nlink"
loc_refused "$tmp/nlink/n.sh" "$NO_TRUST"
verdict $? "under a record, that repository reached through a link outside the worktree is refused" "$(loc_out)"
LOC_REC=''
loc_refused "$lw/sub/n/tools/n.sh" "$NO_TRUST"
verdict $? "with no record, a repository nested in the worktree is refused still" "$(loc_out)"
LOC_REC=$tmp/loc.record
loc_ran "$lw/tools/mark.sh"
verdict $? "under the usable record again, the base's location runs" "$(loc_out)"
LOC_REC=''
loc_ran "$lw/tools/mark.sh"
verdict $? "with no record, the location is held to HEAD again" "$(loc_out)"

if [ "$failures" -gt 0 ]; then
  printf '%s failure(s)\n' "$failures" >&2
  exit 1
fi
echo "all step-run tests passed"
