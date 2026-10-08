#!/bin/sh
# Tests for scripts/step-pool.sh — the step pool helper (custom-steps
# REQ-I1.1, REQ-I1.2, REQ-I1.3, REQ-I1.4, REQ-I1.6; D-22, D-23, D-24).
#
# Every pool lives under a temporary pools root, and every config layer is a
# fixture except core, which is the shipped config/defaults.yml so the three
# keys' defaults are the ones under test. Slot owners are fixture `sleep`
# processes, so a dead owner is one this file killed.
#
# Runs standalone under /bin/sh (the bash 3.2 / dash floor):
#   ./tests/test-step-pool.sh
# shellcheck disable=SC2016 # bodies handed to `sh -c` are literal shell text
set -u
LC_ALL=C
export LC_ALL
unset CDPATH

here=$(cd "$(dirname "$0")" && pwd)
repo_root=$(cd "$here/.." && pwd)
SP="$repo_root/scripts/step-pool.sh"
DEFAULTS="$repo_root/config/defaults.yml"
TAB=$(printf '\t')

failures=0
fail() {
  echo "FAIL: $1" >&2
  failures=$((failures + 1))
}
ok() { echo "ok: $1"; }
# check <status> <ok-message> <fail-message>
check() {
  if [ "$1" -eq 0 ]; then
    ok "$2"
  else
    fail "$3"
  fi
}
# verdict <ok-message> <fail-message> [<file>] — judged on the status of the
# command before the call; a failure appends <file>'s content. A message must
# not run a command substitution: under bash that resets $? before the
# function reads it.
verdict() {
  if [ $? -eq 0 ]; then
    ok "$1"
  else
    fail "$2${3:+: $(cat "$3" 2>/dev/null)}"
  fi
}

[ -x "$SP" ] || {
  echo "FAIL: scripts/step-pool.sh missing or not executable" >&2
  exit 1
}

tmp="$(cd "$(mktemp -d "${TMPDIR:-/tmp}/test-step-pool.XXXXXX")" && pwd -P)" || exit 1
# Owners start inside command substitutions, so their pids are kept in a file
# the parent shell can read back at exit.
owners="$tmp/owners"
cleanup() {
  [ -f "$owners" ] && while read -r _p; do kill "$_p" 2>/dev/null; done <"$owners"
  rm -rf "$tmp"
}
trap cleanup EXIT

pools="$tmp/pools"
adopter="$tmp/adopter"
repo="$tmp/repo"
other="$tmp/other"
mkdir -p "$adopter" "$repo/.claude" "$other/.claude"
for _r in "$repo" "$other"; do
  GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 git init -q "$_r"
done
mlocal="$repo/.claude/planwright.local.yml"
tracked="$repo/.claude/planwright.yml"

# sp [<env assignment>...] -- <verb> <args>... — run the helper against the
# fixture layers from the fixture checkout, with no inherited hold mark.
sp() {
  (
    cd "$repo" || exit 99
    unset PLANWRIGHT_STEP_POOL_HOLD
    while [ "$#" -gt 0 ] && [ "$1" != -- ]; do
      export "${1?}"
      shift
    done
    [ "${1:-}" = -- ] && shift
    PLANWRIGHT_CONFIG_DEFAULTS="$DEFAULTS" \
      PLANWRIGHT_ADOPTER_OVERLAY="$adopter" \
      PLANWRIGHT_REPO_ROOT="$repo" \
      PLANWRIGHT_LOCAL_CONFIG="" \
      PLANWRIGHT_STEP_POOL_ROOT="$pools" \
      "$SP" "$@"
  )
}

# owner — start a fixture slot owner and print its pid.
owner() {
  sleep 120 >/dev/null 2>&1 &
  _o=$!
  printf '%s\n' "$_o" >>"$owners"
  printf '%s' "$_o"
}

# kill_owner <pid> — end an owner and wait until it is gone.
kill_owner() {
  kill "$1" 2>/dev/null
  wait "$1" 2>/dev/null
  _k=0
  while kill -0 "$1" 2>/dev/null && [ "$_k" -lt 50 ]; do
    sleep 0.1
    _k=$((_k + 1))
  done
}

reset() {
  rm -rf "$pools"
  rm -f "$mlocal" "$tracked" "$adopter/planwright.yml"
}

# --- the shipped keys ----------------------------------------------------------
grep -qx 'step_pool_capacity: 1' "$DEFAULTS"
verdict "core default step_pool_capacity is 1" "config/defaults.yml lacks 'step_pool_capacity: 1'"
grep -qx 'step_pool_wait: 60m' "$DEFAULTS"
verdict "core default step_pool_wait is 60m" "config/defaults.yml lacks 'step_pool_wait: 60m'"
grep -qx 'full_suite_pool:' "$DEFAULTS"
verdict "core default full_suite_pool is empty" "config/defaults.yml lacks an empty full_suite_pool"
! grep -q '^step_pool_capacity_' "$DEFAULTS"
verdict "the per-pool capacity family has no core default" "config/defaults.yml sets a step_pool_capacity_<pool> key"

# --- REQ-I1.3: capacity one serializes two callers -----------------------------
reset
printf 'step_pool_wait: 1s\n' >"$mlocal"
a=$(owner)
b=$(owner)
out=$(sp -- take serial "$a" --step build --worktree "$repo")
rc=$?
[ "$rc" -eq 0 ] && [ "$out" = "taken${TAB}1${TAB}0" ]
verdict "the first caller takes slot 1" "first take: rc=$rc out='$out'"
out=$(sp -- take serial "$b" --step lint --worktree "$other" 2>"$tmp/err")
rc=$?
[ "$rc" -eq 3 ] && printf '%s\n' "$out" | head -n 1 | grep -q "^expired${TAB}-${TAB}"
verdict "at capacity one the second caller's wait expires" "second take: rc=$rc out='$out'"

# --- REQ-I1.4: the waiter names the live holder, at the start and at expiry -----
grep -q "waiting.*pid $a.*step build.*worktree $repo" "$tmp/err"
verdict "the wait reports the holder's pid, step, and worktree at its start" \
  "start-of-wait report:" "$tmp/err"
grep -q "passed its 1s bound.*pid $a" "$tmp/err"
verdict "the expired wait names the holder" "expiry report:" "$tmp/err"
printf '%s\n' "$out" | grep -qx "holder${TAB}1${TAB}$a${TAB}build${TAB}$repo"
verdict "the expired take lists the holder on stdout" "expired stdout: '$out'"
out=$(sp -- report serial)
[ "$out" = "holder${TAB}1${TAB}$a${TAB}build${TAB}$repo" ]
verdict "report lists the live holder" "report: '$out'"

# --- REQ-I1.1: a slot shared by callers in two different checkouts ---------------
# The second caller ran from another checkout (its own --worktree) against the
# same per-user pool and waited on the first one's slot.
grep -q "worktree $repo" "$tmp/err"
verdict "a caller in another checkout waits on the same slot" "other checkout:" "$tmp/err"

# --- release: only the owner's release frees the slot ---------------------------
out=$(sp -- release serial "$b")
[ "$out" = none ] && [ -n "$(sp -- report serial)" ]
verdict "a release naming another owner frees nothing" "foreign release: '$out'"
out=$(sp -- release serial "$a")
[ "$out" = "released${TAB}1" ]
verdict "the owner's release frees its slot" "owner release: '$out'"
out=$(sp -- take serial "$b" --step lint)
[ "$out" = "taken${TAB}1${TAB}0" ]
verdict "the waiter then takes the freed slot" "take after release: '$out'"
sp -- release serial "$b" >/dev/null

# --- REQ-I1.3: a per-pool override admits two; hyphens become underscores ------
reset
printf 'step_pool_wait: 1s\nstep_pool_capacity_wide_pool: 2\n' >"$mlocal"
a=$(owner)
b=$(owner)
c=$(owner)
o1=$(sp -- take wide-pool "$a")
o2=$(sp -- take wide-pool "$b")
[ "$o1" = "taken${TAB}1${TAB}0" ] && [ "$o2" = "taken${TAB}2${TAB}0" ]
verdict "a per-pool capacity of two admits two callers" "wide: '$o1' '$o2'"
sp -- take wide-pool "$c" --waited 1 >/dev/null 2>&1
check $(($? == 3 ? 0 : 1)) "the third caller waits past the override" "a third caller was admitted"
sp -- take serial "$c" >/dev/null 2>&1
verdict "another pool keeps the shared capacity" "pool 'serial' did not admit its first caller"
out=$(sp -- report wide-pool | sort)
printf '%s\n' "$out" | grep -q "${TAB}(full-suite)${TAB}"
verdict "a take naming no step records the full-suite marker" "report: '$out'"

# --- REQ-I1.3: a malformed capacity falls back in order, naming the layer -------
reset
printf 'step_pool_wait: 1s\nstep_pool_capacity_mal: two\nstep_pool_capacity: 2\n' >"$mlocal"
a=$(owner)
b=$(owner)
sp -- take mal "$a" >/dev/null 2>"$tmp/err"
o2=$(sp -- take mal "$b" 2>/dev/null)
grep -q 'machine-local layer sets step_pool_capacity_mal.*falling back to step_pool_capacity$' "$tmp/err" \
  && [ "$o2" = "taken${TAB}2${TAB}0" ]
verdict "a malformed per-pool value falls back to step_pool_capacity with a warning naming the layer" \
  "per-pool fallback: '$o2' /" "$tmp/err"
[ "$(grep -c . "$tmp/err")" -eq 1 ]
verdict "the fallback costs one warning" "warnings:" "$tmp/err"

reset
printf 'step_pool_wait: 1s\n' >"$mlocal"
printf 'step_pool_capacity: 0\n' >"$tracked"
a=$(owner)
b=$(owner)
sp -- take mal "$a" >/dev/null 2>"$tmp/err"
sp -- take mal "$b" --waited 1 >/dev/null 2>&1
rc=$?
grep -q 'repo-tracked layer sets step_pool_capacity .*core default 1' "$tmp/err" && [ "$rc" -eq 3 ]
verdict "a malformed shared value falls back to the core default with a warning naming the layer" \
  "shared fallback: rc=$rc /" "$tmp/err"

reset
printf 'step_pool_wait: 1s\nstep_pool_capacity_mal: -1\nstep_pool_capacity: x\n' >"$mlocal"
a=$(owner)
b=$(owner)
sp -- take mal "$a" >/dev/null 2>"$tmp/err"
sp -- take mal "$b" --waited 1 >/dev/null 2>&1
rc=$?
grep -q 'step_pool_capacity_mal' "$tmp/err" && grep -q "machine-local.*'step_pool_capacity'.*core default" "$tmp/err" \
  && [ "$rc" -eq 3 ]
verdict "two malformed values fall back to the core default of one" "double fallback: rc=$rc /" "$tmp/err"

reset
printf 'step_pool_wait: 1s\nnot a key line\n' >"$mlocal"
a=$(owner)
out=$(sp -- take filebad "$a" 2>"$tmp/err")
[ "$out" = "taken${TAB}1${TAB}0" ] && ! grep -q 'step_pool_capacity_filebad' "$tmp/err"
verdict "a malformed overlay file is not blamed on an unset per-pool key" "file fallback: '$out'" "$tmp/err"

reset
printf 'step_pool_wait: 1s\nstep_pool_capacity_empty:\n' >"$mlocal"
a=$(owner)
sp -- take empty "$a" >/dev/null 2>"$tmp/err"
grep -q "machine-local layer sets step_pool_capacity_empty to ''," "$tmp/err"
verdict "an empty per-pool value is named as empty" "empty value:" "$tmp/err"

# --- REQ-I1.4: a malformed wait falls back to the default with a warning --------
reset
printf 'step_pool_wait: soon\n' >"$mlocal"
a=$(owner)
b=$(owner)
sp -- take w "$a" >/dev/null 2>&1
out=$(sp -- take w "$b" --for 1 2>"$tmp/err")
rc=$?
[ "$rc" -eq 4 ] && grep -q 'step_pool_wait' "$tmp/err" && grep -q 'up to 3600s' "$tmp/err"
verdict "a malformed wait falls back to 60m with a warning" "malformed wait: rc=$rc /" "$tmp/err"
[ "$(grep -c 'step_pool_wait' "$tmp/err")" -eq 1 ]
verdict "the wait fallback costs one warning" "warnings:" "$tmp/err"
reset
printf 'step_pool_wait: soon\n' >"$tracked"
a=$(owner)
b=$(owner)
sp -- take w "$a" >/dev/null 2>&1
sp -- take w "$b" --for 1 >/dev/null 2>"$tmp/err"
rc=$?
[ "$rc" -eq 4 ] && grep -q 'repo-tracked layer sets step_pool_wait' "$tmp/err" && grep -q 'up to 3600s' "$tmp/err" \
  && [ "$(grep -c 'step_pool_wait' "$tmp/err")" -eq 1 ]
verdict "a malformed repo-tracked wait falls back too, with one warning" "tracked wait: rc=$rc /" "$tmp/err"

reset
printf 'step_pool_wait: 1.1h\n' >"$mlocal"
a=$(owner)
b=$(owner)
sp -- take whole "$a" >/dev/null
sp -- take whole "$b" --waited 3961 >/dev/null 2>"$tmp/err"
grep -q 'passed its 3960s bound' "$tmp/err"
verdict "a whole-second wait is not rounded up a second by float error" "1.1h bound:" "$tmp/err"

# --- REQ-I1.1: bounded repeated calls sum their seconds -------------------------
reset
printf 'step_pool_wait: 3s\n' >"$mlocal"
a=$(owner)
b=$(owner)
sp -- take sum "$a" >/dev/null
out=$(sp -- take sum "$b" --for 1 2>"$tmp/err")
rc=$?
[ "$rc" -eq 4 ] && printf '%s\n' "$out" | grep -q "^waiting${TAB}-${TAB}[1-9]"
verdict "a call capped by --for returns waiting with its seconds" "capped call: rc=$rc out='$out'"
w1=$(printf '%s\n' "$out" | cut -f 3)
sp -- take sum "$b" --waited "$w1" --for 1 >/dev/null 2>"$tmp/err2"
! grep -q 'waiting up to' "$tmp/err2"
verdict "a continuing call does not repeat the start-of-wait report" "continuation:" "$tmp/err2"
out=$(sp -- take sum "$b" --waited 3 --for 1 2>/dev/null)
rc=$?
[ "$rc" -eq 3 ]
verdict "the bound covers the summed wait across calls" "summed bound: rc=$rc out='$out'"
sp -- release sum "$a" >/dev/null
out=$(sp -- take sum "$b" --waited 2 --for 1)
rc=$?
[ "$rc" -eq 0 ] && printf '%s\n' "$out" | grep -q "^taken${TAB}1${TAB}2$"
verdict "a continued call that takes reports the summed wait" "continued take: rc=$rc out='$out'"

# --- REQ-I1.2: a dead holder's slot is reclaimed --------------------------------
reset
printf 'step_pool_wait: 1s\n' >"$mlocal"
a=$(owner)
b=$(owner)
sp -- take dead "$a" >/dev/null
kill_owner "$a"
out=$(sp -- take dead "$b")
[ "$out" = "taken${TAB}1${TAB}0" ]
verdict "a dead holder's slot is reclaimed by the next caller" "reclaim: '$out'"

# --- REQ-I1.1: a slot is reclaimed after its owner exits normally ---------------
reset
printf 'step_pool_wait: 1s\n' >"$mlocal"
sleep 1 &
short=$!
b=$(owner)
sp -- take exit "$short" >/dev/null
wait "$short"
out=$(sp -- take exit "$b")
[ "$out" = "taken${TAB}1${TAB}0" ]
verdict "a slot is reclaimed after its owner process exits" "after exit: '$out'"

# --- REQ-I1.2: a child that outlives its owner does not keep the slot -----------
reset
printf 'step_pool_wait: 1s\n' >"$mlocal"
sh -c 'sleep 120 >/dev/null 2>&1 & echo $! >"$1"; sleep 1' sh "$tmp/child" &
parent=$!
b=$(owner)
sp -- take leak "$parent" >/dev/null
wait "$parent"
child=$(cat "$tmp/child")
printf '%s\n' "$child" >>"$owners"
kill -0 "$child" 2>/dev/null
verdict "the fixture child outlives its owner" "the child exited with its owner"
out=$(sp -- take leak "$b")
[ "$out" = "taken${TAB}1${TAB}0" ]
verdict "a leaked child does not keep its owner's slot" "leaked child: '$out'"

# --- REQ-I1.1: an owner that stops running ends its own wait --------------------
reset
printf 'step_pool_wait: 60s\n' >"$mlocal"
a=$(owner)
w=$(owner)
sp -- take gone "$a" >/dev/null
sp -- take gone "$w" >"$tmp/out" 2>"$tmp/err" &
waiter=$!
_n=0
until grep -q 'is full' "$tmp/err" 2>/dev/null || [ "$_n" -ge 300 ]; do
  sleep 0.1
  _n=$((_n + 1))
done
kill_owner "$w"
wait "$waiter"
rc=$?
out=$(cat "$tmp/out")
[ "$rc" -eq 2 ] && grep -q "owner $w is not running" "$tmp/err" && [ -z "$out" ] \
  && [ "$(sp -- report gone | grep -c .)" -eq 1 ]
verdict "a take whose owner stops running mid-wait ends at once, holding nothing" \
  "owner gone mid-wait: rc=$rc out='$out'" "$tmp/err"

# --- an interrupted take leaves no scratch file behind ---------------------------
reset
printf 'step_pool_wait: 60s\n' >"$mlocal"
mkdir -p "$tmp/scratch"
a=$(owner)
w=$(owner)
sp -- take sig "$a" >/dev/null
(
  cd "$repo" || exit 99
  unset PLANWRIGHT_STEP_POOL_HOLD
  TMPDIR="$tmp/scratch" PLANWRIGHT_CONFIG_DEFAULTS="$DEFAULTS" PLANWRIGHT_ADOPTER_OVERLAY="$adopter" \
    PLANWRIGHT_REPO_ROOT="$repo" PLANWRIGHT_LOCAL_CONFIG="" PLANWRIGHT_STEP_POOL_ROOT="$pools" \
    exec "$SP" take sig "$w" >/dev/null 2>"$tmp/err"
) &
waiter=$!
_n=0
until grep -q 'is full' "$tmp/err" 2>/dev/null || [ "$_n" -ge 300 ]; do
  sleep 0.1
  _n=$((_n + 1))
done
kill -TERM "$waiter"
wait "$waiter"
rc=$?
left=$(ls -A "$tmp/scratch")
[ "$rc" -eq 143 ] && [ -z "$left" ]
verdict "a take stopped by TERM exits 143 and removes its scratch file" "TERM: rc=$rc left='$left'" "$tmp/err"

# --- REQ-I1.1: released by its owner after a non-zero exit ----------------------
reset
printf 'step_pool_wait: 1s\n' >"$mlocal"
b=$(owner)
(
  cd "$repo" || exit 99
  PLANWRIGHT_CONFIG_DEFAULTS="$DEFAULTS" PLANWRIGHT_ADOPTER_OVERLAY="$adopter" \
    PLANWRIGHT_REPO_ROOT="$repo" PLANWRIGHT_LOCAL_CONFIG="" PLANWRIGHT_STEP_POOL_ROOT="$pools" \
    sh -c '"$1" take nz "$$" >/dev/null || exit 9
      PLANWRIGHT_STEP_POOL_HOLD="nz:$$" sh -c "exit 7"
      rc=$?
      "$1" release nz "$$" >/dev/null
      exit "$rc"' sh "$SP"
)
rc=$?
out=$(sp -- take nz "$b")
[ "$rc" -eq 7 ] && [ "$out" = "taken${TAB}1${TAB}0" ]
verdict "the owner releases its slot after a non-zero exit" "non-zero exit: rc=$rc out='$out'"

# --- REQ-I1.2: the hold mark ----------------------------------------------------
reset
printf 'step_pool_wait: 1s\n' >"$mlocal"
a=$(owner)
b=$(owner)
sp -- take mark "$a" --step suite >/dev/null
out=$(sp "PLANWRIGHT_STEP_POOL_HOLD=mark:$a" -- take mark "$b" 2>"$tmp/err")
rc=$?
[ "$rc" -eq 0 ] && [ "$out" = "nested${TAB}-${TAB}0" ] && [ ! -s "$tmp/err" ]
verdict "a take under a live same-pool mark returns at once, without a slot or a warning" \
  "nested take: rc=$rc out='$out'" "$tmp/err"
[ "$(sp -- report mark | grep -c .)" -eq 1 ]
verdict "the nested take took no slot" "the nested take holds a slot"
out=$(sp "PLANWRIGHT_STEP_POOL_HOLD=mark:$a" -- release mark "$b")
rc=$?
[ "$rc" -eq 0 ] && [ "$out" = nested ] && [ -n "$(sp -- report mark)" ]
verdict "a nested caller's release is a successful no-op" "nested release: rc=$rc out='$out'"
out=$(sp "PLANWRIGHT_STEP_POOL_HOLD=mark:$a" -- release mark "$a")
[ "$out" = nested ] && [ -n "$(sp -- report mark)" ]
verdict "a release under the mark leaves the owner's hold alone" "release under mark: '$out'"

sp -- take mark "$a" --waited 1 >/dev/null 2>&1
check $(($? == 3 ? 0 : 1)) "a same-owner take without a mark waits like any caller" \
  "a same-owner take without a mark was admitted"

dead=$(owner)
kill_owner "$dead"
for m in "mark:$dead" "other:$a" "mark:abc" "Mark:$a" "mark:0$a" "mark" "mark:$a:1" ":$a"; do
  sp "PLANWRIGHT_STEP_POOL_HOLD=$m" -- take mark "$b" --waited 1 >/dev/null 2>&1
  check $(($? == 3 ? 0 : 1)) "a mark '$m' is ignored and the caller waits" "mark '$m' admitted the caller"
done

# --- REQ-I1.2: an unusable pool runs unpooled, naming the cause -----------------
reset
printf 'step_pool_wait: 1s\n' >"$mlocal"
a=$(owner)
mkdir -p "$pools" "$tmp/elsewhere"
ln -s "$tmp/elsewhere" "$pools/linked"
out=$(sp -- take linked "$a" 2>"$tmp/err")
rc=$?
[ "$rc" -eq 0 ] && [ "$out" = "unpooled${TAB}-${TAB}0" ] && grep -q 'symbolic link' "$tmp/err" \
  && [ "$(grep -c . "$tmp/err")" -eq 1 ]
verdict "a symbolic-link pool directory runs unpooled with one warning" "linked: rc=$rc out='$out'" "$tmp/err"
[ -z "$(ls "$tmp/elsewhere")" ]
verdict "nothing is written through the link" "the link's target was written"

rm -rf "$pools"
ln -s "$tmp/elsewhere" "$pools"
out=$(sp -- take rootlink "$a" 2>"$tmp/err")
[ "$out" = "unpooled${TAB}-${TAB}0" ] && grep -q 'symbolic link' "$tmp/err"
verdict "a symbolic-link pools root runs unpooled" "root link: '$out'" "$tmp/err"
rm -f "$pools"

stub="$tmp/stub"
mkdir -p "$stub"
real_id=$(command -v id)
printf '#!/bin/sh\nif [ "$1" = -u ]; then echo 4242424; exit 0; fi\nexec %s "$@"\n' "$real_id" >"$stub/id"
chmod +x "$stub/id"
sp -- take foreign "$a" >/dev/null 2>&1
sp -- release foreign "$a" >/dev/null 2>&1
out=$(sp "PATH=$stub:$PATH" -- take foreign "$a" 2>"$tmp/err")
rc=$?
[ "$rc" -eq 0 ] && [ "$out" = "unpooled${TAB}-${TAB}0" ] && grep -q 'not owned' "$tmp/err"
verdict "a pool directory another user owns runs unpooled" "foreign: rc=$rc out='$out'" "$tmp/err"

mkdir -p "$pools/squat/slot-1"
out=$(sp -- take squat "$a" 2>"$tmp/err")
rc=$?
[ "$rc" -eq 0 ] && [ "$out" = "unpooled${TAB}-${TAB}0" ] && grep -q 'lock' "$tmp/err" \
  && grep -q 'not a lock symlink' "$tmp/err"
verdict "a lock-library error runs unpooled naming the cause" "squat: rc=$rc out='$out'" "$tmp/err"

# --- REQ-I1.2: no scratch file still runs unpooled, and release needs none -------
reset
a=$(owner)
sp -- take noscratch "$a" >/dev/null
out=$(sp "TMPDIR=$tmp/absent" -- release noscratch "$a" 2>"$tmp/err")
rc=$?
[ "$rc" -eq 0 ] && [ "$out" = "released${TAB}1" ]
verdict "release needs no scratch file" "release without TMPDIR: rc=$rc out='$out'" "$tmp/err"
out=$(sp "TMPDIR=$tmp/absent" -- take noscratch "$a" 2>"$tmp/err")
rc=$?
[ "$rc" -eq 0 ] && [ "$out" = "unpooled${TAB}-${TAB}0" ] && grep -q 'scratch file' "$tmp/err" \
  && [ "$(grep -c . "$tmp/err")" -eq 1 ]
verdict "a take that cannot create its scratch file runs unpooled with one warning" \
  "take without TMPDIR: rc=$rc out='$out'" "$tmp/err"

# --- REQ-I1.6: no verb executes a command it is given ---------------------------
reset
a=$(owner)
marker="$tmp/executed"
for args in "take p $a touch $marker" "report p touch $marker" "release p $a touch $marker" \
  "take p $a --step touch $marker" "touch $marker"; do
  # shellcheck disable=SC2086 # the argument list is split on purpose
  sp -- $args >/dev/null 2>&1
  rc=$?
  [ "$rc" -eq 2 ] && [ ! -e "$marker" ]
  verdict "'$args' is refused and runs nothing" "'$args': rc=$rc, or the marker exists"
done
sp -- take p "$a" --step 'x;touch' >/dev/null 2>&1
check $(($? == 2 ? 0 : 1)) "a step id outside the charset is refused" "a malformed step id was accepted"
sp -- take 'p;touch' "$a" >/dev/null 2>&1
check $(($? == 2 ? 0 : 1)) "a pool name outside the charset is refused" "a malformed pool name was accepted"
dead=$(owner)
kill_owner "$dead"
sp -- take p "$dead" >/dev/null 2>&1
check $(($? == 2 ? 0 : 1)) "a take for an owner that is not running is refused" "a dead owner was given a slot"
[ ! -e "$marker" ]
verdict "no fixture command ran" "the marker exists"

# --- REQ-I1.2: the helper sits on the shared primitive --------------------------
grep -q '^[[:space:]]*# shellcheck source=scripts/lock-lib\.sh$' "$SP"
verdict "the helper sources the lock library" "scripts/step-pool.sh does not source lock-lib.sh"
grep -q '^#   scripts/step-pool.sh' "$repo_root/scripts/lock-lib.sh"
verdict "the lock-holder list names the helper" "lock-lib.sh's holder list omits scripts/step-pool.sh"
mkdir -p "$tmp/scan/scripts" "$tmp/scan/tests" "$tmp/scan/githooks"
cp "$SP" "$tmp/scan/scripts/step-pool.sh"
cp "$here/test-step-pool.sh" "$tmp/scan/tests/test-step-pool.sh"
out=$(/bin/bash "$repo_root/scripts/check-lock-primitive.sh" "$tmp/scan" 2>&1)
verdict "check-lock-primitive reports the helper and its test clean" "check-lock-primitive: $out"

if [ "$failures" -gt 0 ]; then
  echo "$failures failure(s)" >&2
  exit 1
fi
echo "all step-pool tests passed"
