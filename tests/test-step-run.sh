#!/bin/sh
# Tests for scripts/step-run.sh — /execute-task's command-step runner: pools,
# reuse, re-fire, resume, and the head-move context (custom-steps Task 14;
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

failures=0
fail() {
  printf 'FAIL: %s\n' "$1" >&2
  failures=$((failures + 1))
}
ok() { printf 'ok: %s\n' "$1"; }
verdict() {
  if [ $? -eq 0 ]; then
    ok "$1"
  else
    fail "$2"
  fi
}

[ -x "$RUN" ] || {
  echo "FAIL: scripts/step-run.sh missing or not executable" >&2
  exit 1
}

tmp="$(cd "$(mktemp -d "${TMPDIR:-/tmp}/test-step-run.XXXXXX")" && pwd -P)" || exit 1
owners="$tmp/owners"
cleanup() {
  [ -f "$owners" ] && while read -r _p; do kill "$_p" 2>/dev/null; done <"$owners"
  rm -rf "$tmp"
}
trap cleanup EXIT

PLANWRIGHT_SECRET_SCREEN_TOOL=none
export PLANWRIGHT_SECRET_SCREEN_TOOL
adopter="$tmp/adopter"
bin="$tmp/bin"
mkdir -p "$adopter/catalogs" "$bin" "$tmp/home" "$tmp/claude"

# The fixture steps. check.sh logs one line per run (point, hold mark, previous
# record, head move, start and end stamps) to $tmp/check.log, fails while
# $tmp/fail exists, sleeps while $tmp/slow holds a number, and takes its own
# pool again when $tmp/nest exists. edit.sh commits a change under <path> and,
# given `push`, pushes it. show.sh logs the context it saw.
cat >"$bin/check.sh" <<'EOF'
#!/bin/sh
t=$(dirname "$0")/..
start=$(date +%s)
[ ! -e "$t/nest" ] || "$SP_UNDER_TEST" take gate "$$" --step inner >"$t/nest.out" 2>&1 || exit 9
[ ! -s "$t/slow" ] || sleep "$(cat "$t/slow")"
printf 'point=%s hold=%s prev=%s ph=%s nh=%s start=%s end=%s wt=%s\n' "$PLANWRIGHT_STEP_POINT" \
  "${PLANWRIGHT_STEP_POOL_HOLD-}" "$PLANWRIGHT_STEP_PREV_RECORD" "$PLANWRIGHT_STEP_PREV_HEAD" \
  "$PLANWRIGHT_STEP_NEW_HEAD" "$start" "$(date +%s)" "$PLANWRIGHT_STEP_WORKTREE" >>"$t/check.log"
[ ! -e "$t/fail" ] || exit 3
exit 0
EOF
cat >"$bin/edit.sh" <<'EOF'
#!/bin/sh
mkdir -p "$1"
date +%s%N >>"$1/f.txt"
git add "$1/f.txt" && git commit -q -m "fix: edit $1" || exit 5
[ "${2:-}" != push ] || git push -q origin HEAD 2>/dev/null || exit 6
EOF
cat >"$bin/show.sh" <<'EOF'
#!/bin/sh
t=$(dirname "$0")/..
env | grep '^PLANWRIGHT_STEP_' | sort >"$t/show.$PLANWRIGHT_STEP_ID.env"
EOF
chmod +x "$bin/check.sh" "$bin/edit.sh" "$bin/show.sh"

n=0
# fresh: a new fixture worktree ($wt) with a bare origin and one commit.
fresh() {
  n=$((n + 1))
  wt="$tmp/wt$n"
  git init -q --bare "$tmp/origin$n.git"
  git init -q -b planwright/demo/task-1 "$wt"
  git -C "$wt" config user.name Fixture
  git -C "$wt" config user.email fixture@example.invalid
  git -C "$wt" config commit.gpgsign false
  mkdir -p "$wt/src" "$wt/docs"
  printf 'a\n' >"$wt/src/a.txt"
  printf 'd\n' >"$wt/docs/d.txt"
  printf '.claude/steps/\n' >"$wt/.gitignore"
  git -C "$wt" add -A && git -C "$wt" commit -q -m "chore: base"
  git -C "$wt" remote add origin "$tmp/origin$n.git"
  git -C "$wt" push -q origin HEAD 2>/dev/null
  rm -f "$tmp/check.log" "$tmp/fail" "$tmp/slow" "$tmp/nest" "$tmp"/show.*.env
}

# catalog <entry>...: the adopter steps catalog, one `id|field: value|...`
# argument per entry; config <line>...: the adopter config.
catalog() {
  printf 'steps:\n' >"$adopter/catalogs/steps.yaml"
  for e in "$@"; do
    printf '%s\n' "$e" | awk -F '|' '{ printf "  - id: %s\n", $1; for (i = 2; i <= NF; i++) printf "    %s\n", $i }' \
      >>"$adopter/catalogs/steps.yaml"
  done
}
config() {
  : >"$adopter/planwright.yml"
  for l in "$@"; do printf '%s\n' "$l" >>"$adopter/planwright.yml"; done
}

env_run() {
  PLANWRIGHT_ROOT="$repo_root" PLANWRIGHT_CONFIG_DEFAULTS="$repo_root/config/defaults.yml" \
    PLANWRIGHT_ADOPTER_OVERLAY="$adopter" PLANWRIGHT_REPO_ROOT="$wt" PLANWRIGHT_LOCAL_CONFIG="" \
    PLANWRIGHT_POOL_DIR="$tmp/pools" CLAUDE_DIR="$tmp/claude" HOME="$tmp/home" \
    SP_UNDER_TEST="$SP" PLANWRIGHT_STEP_SPEC=demo PLANWRIGHT_STEP_TASK_IDS=1 \
    PLANWRIGHT_STEP_UNIT_KIND=task PLANWRIGHT_STEP_BRANCH=planwright/demo/task-1 \
    PLANWRIGHT_STEP_BASE_BRANCH=main PLANWRIGHT_STEP_WORKTREE="$wt" PLANWRIGHT_STEP_PR_NUMBER=7 \
    "$@"
}
srun() { env_run "$RUN" --worktree "$wt" "$@"; }
sr() { "$SR" --worktree "$wt" "$@"; }
sp() { env_run "$SP" "$@"; }
recs() { sr list --run "$1" ${2:+--point "$2"}; }
head_of() { git -C "$wt" rev-parse HEAD; }
owner() {
  sleep 120 >/dev/null 2>&1 &
  _o=$!
  printf '%s\n' "$_o" >>"$owners"
  printf '%s' "$_o"
}

# point_run <run> <point> [--refire-of ...]: resolve the point, host each of
# its command steps, write its completion. Records every result line.
point_run() {
  _r=$1 _p=$2
  srun resolve --run "$_r" "$_p" --unattended >"$tmp/rows" 2>"$tmp/resolve.err"
  while IFS=$TAB read -r _d _id _rest; do
    [ "$_d" = run ] || continue
    srun command --run "$_r" --point "$_p" --step "$_id" >>"$tmp/results" 2>>"$tmp/err"
  done <"$tmp/rows"
}
point_done() { sr write --completion --run "$1" --point "$2" >/dev/null; }
# refire_pass <run>: the plan, then each planned step at post-pr.
refire_pass() {
  srun refire --run "$1" >"$tmp/plan"
  while IFS=$TAB read -r _ _id _decl _; do
    srun command --run "$1" --point post-pr --step "$_id" --refire-of "$_decl" >>"$tmp/results" 2>>"$tmp/err"
  done <"$tmp/plan"
}
# unit <run>: a unit run's pre-pr and post-pr points with the re-fire pass.
unit() {
  point_run "$1" pre-pr
  point_done "$1" pre-pr
  point_run "$1" post-pr
  refire_pass "$1"
  point_done "$1" post-pr
}

GATE="gate|kind: command|target: $bin/check.sh|pool: gate|paths: src|refire: post-pr"

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
  && [ "$(grep -c '^PLANWRIGHT_STEP_' "$tmp/show.show.env")" -eq 12 ]
verdict "the step after a push sees exactly the twelve fields, the push's move among them" \
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
srun command --run "$r" --point pre-pr --step gate >"$tmp/out" 2>/dev/null &
bg=$!
# Bounded one-second "calls" while the holder keeps the slot for three.
i=0
while [ "$i" -lt 3 ]; do
  sleep 1
  i=$((i + 1))
done
sp release gate "$h" >/dev/null
wait "$bg"
rc=$?
recs "$r" pre-pr >"$tmp/l"
w=$(sed -n "s/^wait${TAB}//p" "$tmp/l")
[ "$rc" -eq 0 ] && grep -qx "outcome${TAB}passed" "$tmp/l" && [ "${w:-0}" -ge 2 ]
verdict "a background step outlasting bounded waits is admitted, its wait seconds summed" "rc=$rc wait=$w"

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

# --- a runner-owned step past its timeout is ended and fails naming it (REQ-D1.7) ---------
fresh
catalog "slow|kind: command|target: $bin/check.sh|pool: gate|timeout: 1"
config 'steps_pre_pr: [slow]'
printf '30\n' >"$tmp/slow"
r=$(sr new-run)
srun resolve --run "$r" pre-pr --unattended >/dev/null 2>&1
t0=$(date +%s)
srun command --run "$r" --point pre-pr --step slow >"$tmp/out" 2>/dev/null
rc=$?
t1=$(date +%s)
[ "$rc" -eq 1 ] && [ $((t1 - t0)) -lt 20 ] && recs "$r" pre-pr | grep -q "^excerpt${TAB}step-run: timed out after 1s" \
  && [ -z "$(sp report gate)" ]
verdict "a step past its timeout is ended, records failed naming the timeout, and frees its slot" \
  "rc=$rc took $((t1 - t0))s: $(recs "$r" pre-pr)"
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
point_run "$r" pre-ci
grep -qx 'PLANWRIGHT_STEP_PREV_HEAD=' "$tmp/show.show.env" && grep -qx 'PLANWRIGHT_STEP_NEW_HEAD=' "$tmp/show.show.env" \
  && grep -qx 'PLANWRIGHT_STEP_PREV_RECORD=' "$tmp/show.show.env"
verdict "with no earlier move both head fields are empty strings" "env: $(cat "$tmp/show.show.env")"

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

if [ "$failures" -gt 0 ]; then
  printf '%s failure(s)\n' "$failures" >&2
  exit 1
fi
echo "all step-run tests passed"
