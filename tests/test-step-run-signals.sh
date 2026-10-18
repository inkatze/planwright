#!/bin/sh
# Tests for scripts/step-run.sh's timeout and signal handling: the check's
# whole process group ended before its slot is released (custom-steps
# Task 14; REQ-D1.7, REQ-I1.1, REQ-I1.2).
#
# Runs standalone under /bin/sh (the bash 3.2 / dash floor):
#   ./tests/test-step-run-signals.sh
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

# --- a runner-owned step past its timeout is ended and fails naming it (REQ-D1.7) ---------
fresh
catalog "slow|kind: command|target: $bin/grand.sh|pool: gate|timeout: 1"
config 'steps_pre_pr: [slow]'
r=$(sr new-run)
srun resolve --run "$r" pre-pr --unattended >/dev/null 2>&1
t0=$(date +%s)
srun command --run "$r" --point pre-pr --step slow >"$tmp/out" 2>/dev/null
rc=$?
t1=$(date +%s)
[ "$rc" -eq 1 ] && [ $((t1 - t0)) -lt 20 ] && recs "$r" pre-pr | grep -q "^excerpt${TAB}step-run: timed out after 1s" \
  && [ -z "$(sp report gate)" ] && ! kill -0 "$(cat "$tmp/grand.pid")" 2>/dev/null
verdict "a step past its timeout is ended with everything it started, records failed, and frees its slot" \
  "rc=$rc took $((t1 - t0))s: $(recs "$r" pre-pr)"

# --- a check that ignores TERM is killed ten seconds after its timeout ----------------------
catalog "stub|kind: command|target: $bin/stubborn.sh|pool: gate|timeout: 1"
config 'steps_pre_pr: [stub]'
r=$(sr new-run)
srun resolve --run "$r" pre-pr --unattended >/dev/null 2>&1
t0=$(date +%s)
srun command --run "$r" --point pre-pr --step stub >"$tmp/out" 2>/dev/null
rc=$?
t1=$(date +%s)
[ "$rc" -eq 1 ] && [ $((t1 - t0)) -lt 25 ] && ! kill -0 "$(cat "$tmp/parent.pid")" 2>/dev/null \
  && [ -z "$(sp report gate)" ]
verdict "a check ignoring TERM is killed after the grace, then its slot freed" "rc=$rc took $((t1 - t0))s"

# --- a signal to the runner ends the check's group before the slot goes -------------------
rm -f "$tmp/grand.pid"
catalog "sig|kind: command|target: $bin/grand.sh|pool: gate"
config 'steps_pre_pr: [sig]'
r=$(sr new-run)
srun resolve --run "$r" pre-pr --unattended >/dev/null 2>&1
srun command --run "$r" --point pre-pr --step sig >"$tmp/out" 2>/dev/null &
bg=$!
i=0
while [ ! -s "$tmp/grand.pid" ] && [ "$i" -lt 100 ]; do
  sleep 0.1
  i=$((i + 1))
done
runner=$(pgrep -f "step-run.sh --worktree $wt command" | head -n 1)
kill -TERM "$runner"
wait "$bg"
rc=$?
[ "$rc" -eq 143 ] && ! kill -0 "$(cat "$tmp/grand.pid")" 2>/dev/null && [ -z "$(sp report gate)" ] \
  && recs "$r" pre-pr | grep -q "^excerpt${TAB}step-run: stopped by signal 15"
verdict "a TERM to the runner ends the check's group, records failed, frees the slot, and exits 143" \
  "rc=$rc: $(recs "$r" pre-pr)"

if [ "$failures" -gt 0 ]; then
  printf '%s failure(s)\n' "$failures" >&2
  exit 1
fi
echo "all step-run signal tests passed"
